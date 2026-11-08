import pytest

from backend.accounts import AccountStore
from backend.team_workspace import TeamWorkspaceError, TeamWorkspaceStore


def _accounts(tmp_path):
    path = tmp_path / "accounts.sqlite3"
    accounts = AccountStore(path)
    owner = accounts.bootstrap_owner("team_owner", "owner password long enough")
    collaborator = accounts._create("team_collab", "collaborator password", "collaborator")
    other = accounts._create("other_collab", "another collaborator password", "collaborator")
    return path, accounts, owner, collaborator, other


def test_team_invitation_requires_collaborator_acceptance_and_scopes_project(tmp_path):
    path, _, owner, collaborator, other = _accounts(tmp_path)
    team = TeamWorkspaceStore(path)
    project = team.create_project(owner["userId"], "Campagna estate", "Video social")
    invited = team.invite_member(owner["userId"], project["projectId"], collaborator["userId"])
    assert invited["status"] == "pending"
    assert team.list_projects(collaborator["userId"]) == []
    assert len(team.list_invitations(collaborator["userId"])) == 1
    assert team.respond_invitation(collaborator["userId"], project["projectId"], True)["status"] == "active"
    assert team.list_projects(collaborator["userId"])[0]["projectId"] == project["projectId"]
    assert team.list_projects(other["userId"]) == []


def test_only_project_owner_can_invite_or_revoke_and_only_collaborator_can_accept(tmp_path):
    path, _, owner, collaborator, other = _accounts(tmp_path)
    team = TeamWorkspaceStore(path)
    project = team.create_project(owner["userId"], "Progetto team")
    with pytest.raises(TeamWorkspaceError, match="proprietario"):
        team.invite_member(collaborator["userId"], project["projectId"], other["userId"])
    team.invite_member(owner["userId"], project["projectId"], collaborator["userId"])
    with pytest.raises(TeamWorkspaceError, match="Invito non disponibile"):
        team.respond_invitation(other["userId"], project["projectId"], True)
    with pytest.raises(TeamWorkspaceError, match="proprietario"):
        team.revoke_member(other["userId"], project["projectId"], collaborator["userId"])


def test_revocation_removes_project_and_comment_access(tmp_path):
    path, _, owner, collaborator, _ = _accounts(tmp_path)
    team = TeamWorkspaceStore(path)
    project = team.create_project(owner["userId"], "Progetto riservato")
    project_id = project["projectId"]
    team.invite_member(owner["userId"], project_id, collaborator["userId"])
    team.respond_invitation(collaborator["userId"], project_id, True)
    team.add_comment(collaborator["userId"], project_id, "Prima revisione")
    assert len(team.list_comments(owner["userId"], project_id)) == 1
    assert team.revoke_member(owner["userId"], project_id, collaborator["userId"])
    assert team.list_projects(collaborator["userId"]) == []
    with pytest.raises(TeamWorkspaceError, match="non disponibile"):
        team.add_comment(collaborator["userId"], project_id, "Accesso revocato")


def test_comments_and_approval_are_audited_and_collaborator_can_decide(tmp_path):
    path, accounts, owner, collaborator, _ = _accounts(tmp_path)
    team = TeamWorkspaceStore(path)
    project = team.create_project(owner["userId"], "Revisione spot")
    project_id = project["projectId"]
    team.invite_member(owner["userId"], project_id, collaborator["userId"])
    team.respond_invitation(collaborator["userId"], project_id, True)
    comment = team.add_comment(collaborator["userId"], project_id, "Rivedere la musica")
    assert team.list_comments(owner["userId"], project_id)[0]["commentId"] == comment["commentId"]
    approval = team.request_approval(owner["userId"], project_id, "Versione candidata")
    result = team.respond_approval(collaborator["userId"], approval["approvalId"], "changes_requested", "Correggere il finale")
    assert result["status"] == "changes_requested"
    assert team.list_approvals(owner["userId"], project_id)[0]["note"] == "Correggere il finale"
    actions = {event["action"] for event in accounts.list_audit_events(100)}
    assert {"team.project_created", "team.member_invited", "team.invitation_accepted",
            "team.comment_added", "team.approval_requested", "team.approval_responded"} <= actions


def test_disabled_or_non_collaborator_accounts_cannot_be_invited(tmp_path):
    path, accounts, owner, collaborator, _ = _accounts(tmp_path)
    user = accounts.register("ordinary_user", "ordinary user password")
    team = TeamWorkspaceStore(path)
    project = team.create_project(owner["userId"], "Progetto")
    with pytest.raises(TeamWorkspaceError, match="Collaboratore attivo"):
        team.invite_member(owner["userId"], project["projectId"], user["userId"])
    with accounts._connect() as db:
        db.execute("UPDATE accounts SET disabled_at=1 WHERE user_id=?", (collaborator["userId"],))
    with pytest.raises(TeamWorkspaceError, match="Collaboratore attivo"):
        team.invite_member(owner["userId"], project["projectId"], collaborator["userId"])
