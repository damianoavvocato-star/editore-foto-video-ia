"""Account-scoped TeamStudio collaboration records.

This module stores project metadata and collaboration events only. It does not
pretend that local editor media or project files have been uploaded/synchronized.
"""
from __future__ import annotations

import json
import re
import sqlite3
import time
import uuid
from pathlib import Path
from typing import Any


class TeamWorkspaceError(ValueError):
    pass


class TeamWorkspaceStore:
    def __init__(self, database: str | Path):
        self.database = str(database)
        Path(self.database).parent.mkdir(parents=True, exist_ok=True)
        with self._connect() as db:
            db.execute("""CREATE TABLE IF NOT EXISTS team_projects (
                project_id TEXT PRIMARY KEY,
                owner_user_id TEXT NOT NULL REFERENCES accounts(user_id) ON DELETE CASCADE,
                name TEXT NOT NULL,
                description TEXT NOT NULL DEFAULT '',
                status TEXT NOT NULL CHECK(status IN ('active','archived')),
                created_at INTEGER NOT NULL,
                updated_at INTEGER NOT NULL
            )""")
            db.execute("CREATE INDEX IF NOT EXISTS team_projects_owner_idx ON team_projects(owner_user_id, updated_at)")
            db.execute("""CREATE TABLE IF NOT EXISTS team_memberships (
                project_id TEXT NOT NULL REFERENCES team_projects(project_id) ON DELETE CASCADE,
                user_id TEXT NOT NULL REFERENCES accounts(user_id) ON DELETE CASCADE,
                invited_by_user_id TEXT NOT NULL REFERENCES accounts(user_id),
                status TEXT NOT NULL CHECK(status IN ('pending','active','revoked')),
                invited_at INTEGER NOT NULL,
                responded_at INTEGER,
                PRIMARY KEY(project_id,user_id)
            )""")
            db.execute("CREATE INDEX IF NOT EXISTS team_members_user_idx ON team_memberships(user_id,status)")
            db.execute("""CREATE TABLE IF NOT EXISTS team_comments (
                comment_id TEXT PRIMARY KEY,
                project_id TEXT NOT NULL REFERENCES team_projects(project_id) ON DELETE CASCADE,
                author_user_id TEXT NOT NULL REFERENCES accounts(user_id),
                body TEXT NOT NULL,
                created_at INTEGER NOT NULL
            )""")
            db.execute("CREATE INDEX IF NOT EXISTS team_comments_project_idx ON team_comments(project_id,created_at)")
            db.execute("""CREATE TABLE IF NOT EXISTS team_approvals (
                approval_id TEXT PRIMARY KEY,
                project_id TEXT NOT NULL REFERENCES team_projects(project_id) ON DELETE CASCADE,
                requested_by_user_id TEXT NOT NULL REFERENCES accounts(user_id),
                status TEXT NOT NULL CHECK(status IN ('pending','approved','changes_requested')),
                note TEXT NOT NULL DEFAULT '',
                created_at INTEGER NOT NULL,
                updated_at INTEGER NOT NULL
            )""")
            db.execute("CREATE INDEX IF NOT EXISTS team_approvals_project_idx ON team_approvals(project_id,created_at)")

    def _connect(self) -> sqlite3.Connection:
        db = sqlite3.connect(self.database, timeout=10)
        db.row_factory = sqlite3.Row
        db.execute("PRAGMA foreign_keys=ON")
        return db

    @staticmethod
    def _id(value: str) -> bool:
        return isinstance(value, str) and re.fullmatch(r"[a-f0-9]{32}", value) is not None

    @staticmethod
    def _audit(db: sqlite3.Connection, actor: str, action: str,
               target: str | None, details: dict[str, Any]) -> None:
        db.execute(
            """INSERT INTO account_audit_events
               (actor_user_id,action,target_user_id,details_json,created_at)
               VALUES(?,?,?,?,?)""",
            (actor, action, target, json.dumps(details, separators=(",", ":")), int(time.time())),
        )

    @staticmethod
    def _actor(db: sqlite3.Connection, actor_id: str) -> sqlite3.Row:
        actor = db.execute(
            "SELECT user_id,role,disabled_at FROM accounts WHERE user_id=?", (actor_id,)
        ).fetchone()
        if actor is None or actor["disabled_at"] is not None:
            raise TeamWorkspaceError("Account non disponibile.")
        if actor["role"] not in {"owner", "admin", "collaborator"}:
            raise TeamWorkspaceError("Ruolo non autorizzato per TeamStudio.")
        return actor

    def create_project(self, actor_id: str, name: str, description: str = "") -> dict[str, Any]:
        name = name.strip() if isinstance(name, str) else ""
        description = description.strip() if isinstance(description, str) else ""
        if not 3 <= len(name) <= 100 or len(description) > 1000:
            raise TeamWorkspaceError("Nome progetto o descrizione non validi.")
        with self._connect() as db:
            actor = self._actor(db, actor_id)
            if actor["role"] not in {"owner", "admin"}:
                raise TeamWorkspaceError("Solo Owner/Admin può creare un progetto TeamStudio.")
            project_id, now = uuid.uuid4().hex, int(time.time())
            db.execute(
                """INSERT INTO team_projects
                   (project_id,owner_user_id,name,description,status,created_at,updated_at)
                   VALUES(?,?,?,?, 'active',?,?)""",
                (project_id, actor_id, name, description, now, now),
            )
            self._audit(db, actor_id, "team.project_created", None, {"projectId": project_id})
        return self.get_project(actor_id, project_id)  # type: ignore[return-value]

    def invite_member(self, actor_id: str, project_id: str, member_user_id: str) -> dict[str, Any]:
        if not self._id(project_id) or not isinstance(member_user_id, str) or not member_user_id:
            raise TeamWorkspaceError("Identificativo progetto o collaboratore non valido.")
        now = int(time.time())
        with self._connect() as db:
            actor = self._actor(db, actor_id)
            project = db.execute("SELECT owner_user_id FROM team_projects WHERE project_id=?", (project_id,)).fetchone()
            if project is None:
                raise TeamWorkspaceError("Progetto non trovato.")
            if actor["role"] != "owner" and project["owner_user_id"] != actor_id:
                raise TeamWorkspaceError("Solo il proprietario del progetto può invitare collaboratori.")
            member = db.execute(
                "SELECT role,disabled_at FROM accounts WHERE user_id=?", (member_user_id,)
            ).fetchone()
            if member is None or member["disabled_at"] is not None or member["role"] != "collaborator":
                raise TeamWorkspaceError("Il destinatario deve essere un account Collaboratore attivo.")
            if member_user_id == project["owner_user_id"]:
                raise TeamWorkspaceError("Il proprietario è già membro del progetto.")
            db.execute(
                """INSERT INTO team_memberships
                   (project_id,user_id,invited_by_user_id,status,invited_at,responded_at)
                   VALUES(?,?,?,'pending',?,NULL)
                   ON CONFLICT(project_id,user_id) DO UPDATE SET
                   invited_by_user_id=excluded.invited_by_user_id,status='pending',
                   invited_at=excluded.invited_at,responded_at=NULL""",
                (project_id, member_user_id, actor_id, now),
            )
            self._audit(db, actor_id, "team.member_invited", member_user_id, {"projectId": project_id})
        return {"projectId": project_id, "userId": member_user_id, "status": "pending"}

    def respond_invitation(self, actor_id: str, project_id: str, accept: bool) -> dict[str, Any]:
        if not self._id(project_id) or not isinstance(accept, bool):
            raise TeamWorkspaceError("Risposta invito non valida.")
        now = int(time.time())
        with self._connect() as db:
            actor = self._actor(db, actor_id)
            if actor["role"] != "collaborator":
                raise TeamWorkspaceError("Solo il collaboratore invitato può rispondere.")
            row = db.execute(
                "SELECT status FROM team_memberships WHERE project_id=? AND user_id=?",
                (project_id, actor_id),
            ).fetchone()
            if row is None or row["status"] != "pending":
                raise TeamWorkspaceError("Invito non disponibile.")
            status = "active" if accept else "revoked"
            db.execute(
                "UPDATE team_memberships SET status=?,responded_at=? WHERE project_id=? AND user_id=?",
                (status, now, project_id, actor_id),
            )
            self._audit(db, actor_id, "team.invitation_accepted" if accept else "team.invitation_declined",
                        None, {"projectId": project_id})
        return {"projectId": project_id, "status": status}

    def revoke_member(self, actor_id: str, project_id: str, member_user_id: str) -> bool:
        if not self._id(project_id) or not isinstance(member_user_id, str):
            raise TeamWorkspaceError("Identificativo non valido.")
        with self._connect() as db:
            actor = self._actor(db, actor_id)
            project = db.execute("SELECT owner_user_id FROM team_projects WHERE project_id=?", (project_id,)).fetchone()
            if project is None:
                raise TeamWorkspaceError("Progetto non trovato.")
            if actor["role"] != "owner" and project["owner_user_id"] != actor_id:
                raise TeamWorkspaceError("Solo il proprietario del progetto può revocare accessi.")
            result = db.execute(
                "UPDATE team_memberships SET status='revoked',responded_at=? WHERE project_id=? AND user_id=? AND status!='revoked'",
                (int(time.time()), project_id, member_user_id),
            )
            if result.rowcount:
                self._audit(db, actor_id, "team.member_revoked", member_user_id, {"projectId": project_id})
            return result.rowcount == 1

    def get_project(self, actor_id: str, project_id: str) -> dict[str, Any] | None:
        if not self._id(project_id):
            return None
        with self._connect() as db:
            actor = self._actor(db, actor_id)
            row = db.execute(
                """SELECT p.* FROM team_projects p
                   LEFT JOIN team_memberships m ON m.project_id=p.project_id AND m.user_id=?
                   WHERE p.project_id=? AND (p.owner_user_id=? OR m.status='active')""",
                (actor_id, project_id, actor_id),
            ).fetchone()
            if row is None:
                return None
            return { "projectId": row["project_id"], "ownerUserId": row["owner_user_id"],
                     "name": row["name"], "description": row["description"],
                     "status": row["status"], "createdAt": row["created_at"],
                     "updatedAt": row["updated_at"] }

    def list_projects(self, actor_id: str) -> list[dict[str, Any]]:
        with self._connect() as db:
            self._actor(db, actor_id)
            rows = db.execute(
                """SELECT p.project_id,p.owner_user_id,p.name,p.description,p.status,p.created_at,p.updated_at
                   FROM team_projects p LEFT JOIN team_memberships m
                     ON m.project_id=p.project_id AND m.user_id=?
                   WHERE p.owner_user_id=? OR m.status='active'
                   ORDER BY p.updated_at DESC,p.project_id""",
                (actor_id, actor_id),
            ).fetchall()
        return [{"projectId": r["project_id"], "ownerUserId": r["owner_user_id"],
                 "name": r["name"], "description": r["description"], "status": r["status"],
                 "createdAt": r["created_at"], "updatedAt": r["updated_at"]} for r in rows]

    def list_invitations(self, actor_id: str) -> list[dict[str, Any]]:
        with self._connect() as db:
            actor = self._actor(db, actor_id)
            if actor["role"] != "collaborator":
                raise TeamWorkspaceError("Solo i collaboratori possono consultare gli inviti personali.")
            rows = db.execute(
                """SELECT p.project_id,p.name,m.invited_by_user_id,m.status,m.invited_at
                   FROM team_memberships m JOIN team_projects p ON p.project_id=m.project_id
                   WHERE m.user_id=? AND m.status='pending' ORDER BY m.invited_at DESC""",
                (actor_id,),
            ).fetchall()
        return [{"projectId": r["project_id"], "projectName": r["name"],
                 "invitedByUserId": r["invited_by_user_id"], "status": r["status"],
                 "invitedAt": r["invited_at"]} for r in rows]

    def add_comment(self, actor_id: str, project_id: str, body: str) -> dict[str, Any]:
        body = body.strip() if isinstance(body, str) else ""
        if not self._id(project_id) or not 1 <= len(body) <= 4000:
            raise TeamWorkspaceError("Commento non valido.")
        with self._connect() as db:
            self._actor(db, actor_id)
            access = db.execute(
                """SELECT p.owner_user_id FROM team_projects p
                   LEFT JOIN team_memberships m ON m.project_id=p.project_id AND m.user_id=?
                   WHERE p.project_id=? AND (p.owner_user_id=? OR m.status='active')""",
                (actor_id, project_id, actor_id),
            ).fetchone()
            if access is None:
                raise TeamWorkspaceError("Progetto non disponibile.")
            comment_id, now = uuid.uuid4().hex, int(time.time())
            db.execute(
                "INSERT INTO team_comments(comment_id,project_id,author_user_id,body,created_at) VALUES(?,?,?,?,?)",
                (comment_id, project_id, actor_id, body, now),
            )
            self._audit(db, actor_id, "team.comment_added", None, {"projectId": project_id, "commentId": comment_id})
        return {"commentId": comment_id, "projectId": project_id, "authorUserId": actor_id,
                "body": body, "createdAt": now}

    def list_comments(self, actor_id: str, project_id: str) -> list[dict[str, Any]]:
        if self.get_project(actor_id, project_id) is None:
            raise TeamWorkspaceError("Progetto non disponibile.")
        with self._connect() as db:
            rows = db.execute(
                """SELECT comment_id,author_user_id,body,created_at FROM team_comments
                   WHERE project_id=? ORDER BY created_at,comment_id""", (project_id,)
            ).fetchall()
        return [{"commentId": r["comment_id"], "projectId": project_id,
                 "authorUserId": r["author_user_id"], "body": r["body"], "createdAt": r["created_at"]}
                for r in rows]

    def request_approval(self, actor_id: str, project_id: str, note: str = "") -> dict[str, Any]:
        note = note.strip() if isinstance(note, str) else ""
        if not self._id(project_id) or len(note) > 2000:
            raise TeamWorkspaceError("Richiesta di approvazione non valida.")
        with self._connect() as db:
            actor = self._actor(db, actor_id)
            project = db.execute("SELECT owner_user_id FROM team_projects WHERE project_id=?", (project_id,)).fetchone()
            if project is None or project["owner_user_id"] != actor_id or actor["role"] not in {"owner", "admin"}:
                raise TeamWorkspaceError("Solo il proprietario del progetto può richiedere l'approvazione.")
            approval_id, now = uuid.uuid4().hex, int(time.time())
            db.execute(
                """INSERT INTO team_approvals
                   (approval_id,project_id,requested_by_user_id,status,note,created_at,updated_at)
                   VALUES(?,?,?,'pending',?,?,?)""",
                (approval_id, project_id, actor_id, note, now, now),
            )
            self._audit(db, actor_id, "team.approval_requested", None, {"projectId": project_id, "approvalId": approval_id})
        return {"approvalId": approval_id, "projectId": project_id, "status": "pending", "note": note,
                "updatedAt": now}

    def respond_approval(self, actor_id: str, approval_id: str, decision: str, note: str = "") -> dict[str, Any]:
        note = note.strip() if isinstance(note, str) else ""
        if not self._id(approval_id) or decision not in {"approved", "changes_requested"} or len(note) > 2000:
            raise TeamWorkspaceError("Decisione di approvazione non valida.")
        with self._connect() as db:
            actor = self._actor(db, actor_id)
            if actor["role"] != "collaborator":
                raise TeamWorkspaceError("Solo un collaboratore può rispondere alla richiesta.")
            row = db.execute(
                """SELECT a.project_id,a.status FROM team_approvals a
                   JOIN team_memberships m ON m.project_id=a.project_id
                   WHERE a.approval_id=? AND m.user_id=? AND m.status='active'""",
                (approval_id, actor_id),
            ).fetchone()
            if row is None or row["status"] != "pending":
                raise TeamWorkspaceError("Richiesta non disponibile.")
            now = int(time.time())
            db.execute("UPDATE team_approvals SET status=?,note=?,updated_at=? WHERE approval_id=?",
                       (decision, note, now, approval_id))
            self._audit(db, actor_id, "team.approval_responded", None,
                        {"projectId": row["project_id"], "approvalId": approval_id, "decision": decision})
        return {"approvalId": approval_id, "projectId": row["project_id"], "status": decision,
                "note": note, "updatedAt": now}

    def list_approvals(self, actor_id: str, project_id: str) -> list[dict[str, Any]]:
        if self.get_project(actor_id, project_id) is None:
            raise TeamWorkspaceError("Progetto non disponibile.")
        with self._connect() as db:
            rows = db.execute(
                """SELECT approval_id,project_id,requested_by_user_id,status,note,created_at,updated_at
                   FROM team_approvals WHERE project_id=? ORDER BY created_at DESC""", (project_id,)
            ).fetchall()
        return [{"approvalId": r["approval_id"], "projectId": r["project_id"],
                 "requestedByUserId": r["requested_by_user_id"], "status": r["status"],
                 "note": r["note"], "createdAt": r["created_at"], "updatedAt": r["updated_at"]}
                for r in rows]
