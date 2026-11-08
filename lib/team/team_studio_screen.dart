import 'package:flutter/material.dart';

import '../services/account_api.dart';
import '../services/remote_team_api.dart';

/// Team collaboration workspace. Project media remains local until a separate
/// encrypted media-sync service is implemented and enabled.
class TeamStudioScreen extends StatefulWidget {
  const TeamStudioScreen({super.key, required this.apiBaseUrl});

  final String apiBaseUrl;

  @override
  State<TeamStudioScreen> createState() => _TeamStudioScreenState();
}

class _TeamStudioScreenState extends State<TeamStudioScreen> {
  final _sessions = const AccountSessionStore();
  final _projectName = TextEditingController();
  final _projectDescription = TextEditingController();
  final _inviteUserId = TextEditingController();
  final _comment = TextEditingController();
  final _approvalNote = TextEditingController();

  RemoteAccountApi? _accountApi;
  RemoteTeamApi? _teamApi;
  Map<String, dynamic>? _user;
  List<Map<String, dynamic>> _projects = [];
  List<Map<String, dynamic>> _invitations = [];
  List<Map<String, dynamic>> _members = [];
  List<Map<String, dynamic>> _comments = [];
  List<Map<String, dynamic>> _approvals = [];
  String? _selectedProjectId;
  bool _loading = true;
  bool _busy = false;
  String? _error;
  String? _notice;

  bool get _isManager => _user?['role'] == 'owner' || _user?['role'] == 'admin';
  bool get _isCollaborator => _user?['role'] == 'collaborator';

  @override
  void initState() {
    super.initState();
    _restoreSession();
  }

  @override
  void dispose() {
    _accountApi?.close();
    _projectName.dispose();
    _projectDescription.dispose();
    _inviteUserId.dispose();
    _comment.dispose();
    _approvalNote.dispose();
    super.dispose();
  }

  Uri? get _baseUri {
    final value = widget.apiBaseUrl.trim();
    if (value.isEmpty) return null;
    return Uri.tryParse(value);
  }

  Future<void> _restoreSession() async {
    if (_baseUri == null) {
      if (mounted) setState(() {
        _loading = false;
        _error = 'Configura MEDIA_API_URL per collegare TeamStudio.';
      });
      return;
    }
    try {
      final token = await _sessions.readToken();
      if (token == null || token.isEmpty) {
        if (mounted) setState(() {
          _loading = false;
          _error = 'Accedi dal pannello Account per utilizzare TeamStudio.';
        });
        return;
      }
      final api = RemoteAccountApi(baseUri: _baseUri!, bearerToken: token);
      final response = await api.request('GET', '/v1/auth/me');
      if (!mounted) {
        api.close();
        return;
      }
      _accountApi?.close();
      _accountApi = api;
      _teamApi = RemoteTeamApi(api);
      _user = Map<String, dynamic>.from(response['user'] as Map);
      await _reload();
    } on AccountApiException catch (error) {
      if (error.statusCode == 401) await _sessions.clear();
      if (mounted) setState(() {
        _loading = false;
        _error = error.statusCode == 401
            ? 'Sessione scaduta. Accedi nuovamente dal pannello Account.'
            : error.message;
      });
    } catch (error) {
      if (mounted) setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _reload() async {
    final api = _teamApi;
    if (api == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        api.listProjects(),
        if (_isCollaborator) api.listInvitations() else Future.value(<Map<String, dynamic>>[]),
      ]);
      if (!mounted) return;
      _projects = results[0];
      _invitations = results[1];
      if (_selectedProjectId == null ||
          !_projects.any((p) => p['projectId'] == _selectedProjectId)) {
        _selectedProjectId = _projects.isEmpty
            ? null
            : _projects.first['projectId']?.toString();
      }
      await _loadProjectDetails();
    } catch (error) {
      if (mounted) setState(() => _error = _safeMessage(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadProjectDetails() async {
    final api = _teamApi;
    final id = _selectedProjectId;
    if (api == null || id == null) {
      _members = [];
      _comments = [];
      _approvals = [];
      return;
    }
    try {
      final results = await Future.wait([
        api.listMembers(id),
        api.listComments(id),
        api.listApprovals(id),
      ]);
      if (!mounted || _selectedProjectId != id) return;
      _members = results[0];
      _comments = results[1];
      _approvals = results[2];
    } catch (error) {
      if (mounted) setState(() => _error = _safeMessage(error));
    }
  }

  String _safeMessage(Object error) =>
      error is AccountApiException ? error.message : error.toString();

  Future<void> _run(Future<void> Function() action, String success) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      await action();
      if (mounted) setState(() => _notice = success);
    } catch (error) {
      if (mounted) setState(() => _error = _safeMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _createProject() async {
    final name = _projectName.text.trim();
    if (name.length < 3) {
      setState(() => _error = 'Inserisci un nome di almeno 3 caratteri.');
      return;
    }
    await _run(() async {
      await _teamApi!.createProject(
        name: name,
        description: _projectDescription.text,
      );
      _projectName.clear();
      _projectDescription.clear();
      await _reload();
    }, 'Progetto TeamStudio creato.');
  }

  Future<void> _invite() async {
    final id = _selectedProjectId;
    final userId = _inviteUserId.text.trim();
    if (id == null || userId.isEmpty) return;
    await _run(() async {
      await _teamApi!.invite(projectId: id, collaboratorUserId: userId);
      _inviteUserId.clear();
      await _loadProjectDetails();
    }, 'Invito inviato. Il collaboratore deve accettarlo.');
  }

  Future<void> _respondInvitation(String projectId, bool accept) async {
    await _run(() async {
      await _teamApi!.respondInvitation(projectId: projectId, accept: accept);
      await _reload();
    }, accept ? 'Invito accettato.' : 'Invito rifiutato.');
  }

  Future<void> _revoke(String memberId) async {
    final id = _selectedProjectId;
    if (id == null) return;
    await _run(() async {
      await _teamApi!.revokeMember(projectId: id, memberUserId: memberId);
      await _loadProjectDetails();
    }, 'Accesso del collaboratore revocato.');
  }

  Future<void> _sendComment() async {
    final id = _selectedProjectId;
    final body = _comment.text.trim();
    if (id == null || body.isEmpty) return;
    await _run(() async {
      await _teamApi!.addComment(projectId: id, body: body);
      _comment.clear();
      await _loadProjectDetails();
    }, 'Commento aggiunto.');
  }

  Future<void> _requestApproval() async {
    final id = _selectedProjectId;
    if (id == null) return;
    await _run(() async {
      await _teamApi!.requestApproval(
        projectId: id,
        note: _approvalNote.text,
      );
      _approvalNote.clear();
      await _loadProjectDetails();
    }, 'Richiesta di approvazione inviata.');
  }

  Future<void> _respondApproval(String approvalId, String decision) async {
    await _run(() async {
      await _teamApi!.respondApproval(
        approvalId: approvalId,
        decision: decision,
      );
      await _loadProjectDetails();
    }, decision == 'approved'
        ? 'Approvazione registrata.'
        : 'Modifiche richieste.');
  }

  @override
  Widget build(BuildContext context) {
    final selected = _projects.where((p) => p['projectId'] == _selectedProjectId);
    final project = selected.isEmpty ? null : selected.first;
    return Scaffold(
      appBar: AppBar(
        title: const Text('TeamStudio'),
        actions: [
          IconButton(
            tooltip: 'Aggiorna',
            onPressed: _busy ? null : _reload,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_error != null) _message(_error!, isError: true),
                if (_notice != null) _message(_notice!),
                if (_user == null) _message(
                  'TeamStudio richiede una sessione account valida.',
                  isError: true,
                ) else ...[
                  _identityCard(),
                  if (_isManager) _createProjectCard(),
                  if (_isCollaborator) _invitationsCard(),
                  _projectsCard(),
                  if (project != null) ...[
                    const SizedBox(height: 12),
                    _projectDetailsCard(project),
                    _membersCard(),
                    _commentsCard(),
                    _approvalsCard(),
                  ],
                ],
                const SizedBox(height: 24),
                const Text(
                  'Nota: TeamStudio gestisce attualmente metadati e collaborazione. '
                  'I file multimediali locali non vengono caricati o sincronizzati.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
    );
  }

  Widget _message(String text, {bool isError = false}) => Card(
        color: isError
            ? Theme.of(context).colorScheme.errorContainer
            : Theme.of(context).colorScheme.secondaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text(text),
        ),
      );

  Widget _identityCard() => Card(
        child: ListTile(
          leading: const CircleAvatar(child: Icon(Icons.groups_outlined)),
          title: Text(_user?['username']?.toString() ?? 'Account'),
          subtitle: Text('Ruolo: ${_user?['role'] ?? 'utente'}'),
          trailing: const Icon(Icons.verified_user_outlined),
        ),
      );

  Widget _createProjectCard() => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Nuovo progetto condiviso',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              TextField(
                controller: _projectName,
                maxLength: 100,
                decoration: const InputDecoration(
                  labelText: 'Nome progetto',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _projectDescription,
                maxLength: 1000,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Descrizione (facoltativa)',
                  border: OutlineInputBorder(),
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: _busy ? null : _createProject,
                  icon: const Icon(Icons.add),
                  label: const Text('Crea progetto'),
                ),
              ),
            ],
          ),
        ),
      );

  Widget _invitationsCard() => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('I miei inviti', style: Theme.of(context).textTheme.titleMedium),
              if (_invitations.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text('Non hai inviti in attesa.'),
                ),
              for (final invitation in _invitations)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.mail_outline),
                  title: Text(invitation['projectName']?.toString() ?? 'Progetto'),
                  subtitle: const Text('Invito in attesa di risposta'),
                  trailing: Wrap(
                    spacing: 4,
                    children: [
                      IconButton(
                        tooltip: 'Accetta',
                        onPressed: _busy
                            ? null
                            : () => _respondInvitation(
                                invitation['projectId'].toString(), true),
                        icon: const Icon(Icons.check_circle_outline),
                      ),
                      IconButton(
                        tooltip: 'Rifiuta',
                        onPressed: _busy
                            ? null
                            : () => _respondInvitation(
                                invitation['projectId'].toString(), false),
                        icon: const Icon(Icons.cancel_outlined),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      );

  Widget _projectsCard() => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Progetti accessibili', style: Theme.of(context).textTheme.titleMedium),
              if (_projects.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text('Non ci sono ancora progetti condivisi.'),
                ),
              for (final project in _projects)
                RadioListTile<String>(
                  value: project['projectId'].toString(),
                  groupValue: _selectedProjectId,
                  contentPadding: EdgeInsets.zero,
                  title: Text(project['name']?.toString() ?? 'Progetto'),
                  subtitle: Text(project['description']?.toString() ?? ''),
                  onChanged: _busy
                      ? null
                      : (value) async {
                          setState(() => _selectedProjectId = value);
                          await _loadProjectDetails();
                          if (mounted) setState(() {});
                        },
                ),
            ],
          ),
        ),
      );

  Widget _projectDetailsCard(Map<String, dynamic> project) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(project['name']?.toString() ?? 'Progetto',
                  style: Theme.of(context).textTheme.titleLarge),
              if ((project['description']?.toString() ?? '').isNotEmpty)
                Text(project['description'].toString()),
              if (_isManager) ...[
                const Divider(height: 24),
                Text('Invita un Collaboratore',
                    style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                TextField(
                  controller: _inviteUserId,
                  decoration: const InputDecoration(
                    labelText: 'ID account Collaboratore',
                    helperText: 'L’account deve essere già creato e attivo.',
                    border: OutlineInputBorder(),
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.tonalIcon(
                    onPressed: _busy ? null : _invite,
                    icon: const Icon(Icons.person_add_alt_1),
                    label: const Text('Invita'),
                  ),
                ),
              ],
            ],
          ),
        ),
      );

  Widget _membersCard() => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Membri e accessi', style: Theme.of(context).textTheme.titleMedium),
              for (final member in _members)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(member['role'] == 'owner'
                      ? Icons.workspace_premium_outlined
                      : Icons.person_outline),
                  title: Text(member['username']?.toString() ?? member['userId'].toString()),
                  subtitle: Text('${member['role']} · ${_status(member['status'])}'),
                  trailing: _isManager &&
                          member['role'] == 'collaborator' &&
                          member['status'] != 'revoked'
                      ? IconButton(
                          tooltip: 'Revoca accesso',
                          onPressed: _busy
                              ? null
                              : () => _confirmRevoke(member['userId'].toString()),
                          icon: const Icon(Icons.person_remove_outlined),
                        )
                      : null,
                ),
            ],
          ),
        ),
      );

  Future<void> _confirmRevoke(String memberId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Revocare l’accesso?'),
        content: const Text(
          'Il collaboratore non potrà più aprire il progetto o consultare commenti e approvazioni.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Revoca'),
          ),
        ],
      ),
    );
    if (confirmed == true) await _revoke(memberId);
  }

  Widget _commentsCard() => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Commenti', style: Theme.of(context).textTheme.titleMedium),
              for (final comment in _comments)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.chat_bubble_outline),
                  title: Text(comment['body']?.toString() ?? ''),
                  subtitle: Text('Autore: ${comment['authorUserId']}'),
                ),
              TextField(
                controller: _comment,
                maxLength: 4000,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Scrivi un commento',
                  border: OutlineInputBorder(),
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.tonal(
                  onPressed: _busy ? null : _sendComment,
                  child: const Text('Invia commento'),
                ),
              ),
            ],
          ),
        ),
      );

  Widget _approvalsCard() => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Approvazioni', style: Theme.of(context).textTheme.titleMedium),
              if (_isManager) ...[
                TextField(
                  controller: _approvalNote,
                  maxLength: 2000,
                  decoration: const InputDecoration(
                    labelText: 'Nota per il collaboratore (facoltativa)',
                    border: OutlineInputBorder(),
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.tonalIcon(
                    onPressed: _busy ? null : _requestApproval,
                    icon: const Icon(Icons.fact_check_outlined),
                    label: const Text('Richiedi approvazione'),
                  ),
                ),
              ],
              for (final approval in _approvals)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.assignment_turned_in_outlined),
                  title: Text(_status(approval['status'])),
                  subtitle: Text(approval['note']?.toString() ?? ''),
                  trailing: _isCollaborator && approval['status'] == 'pending'
                      ? Wrap(
                          spacing: 0,
                          children: [
                            IconButton(
                              tooltip: 'Approva',
                              onPressed: _busy
                                  ? null
                                  : () => _respondApproval(
                                      approval['approvalId'].toString(), 'approved'),
                              icon: const Icon(Icons.check_circle_outline),
                            ),
                            IconButton(
                              tooltip: 'Richiedi modifiche',
                              onPressed: _busy
                                  ? null
                                  : () => _respondApproval(
                                      approval['approvalId'].toString(), 'changes_requested'),
                              icon: const Icon(Icons.edit_note),
                            ),
                          ],
                        )
                      : null,
                ),
            ],
          ),
        ),
      );

  String _status(Object? value) => switch (value?.toString()) {
        'active' => 'Attivo',
        'pending' => 'In attesa',
        'revoked' => 'Revocato',
        'approved' => 'Approvato',
        'changes_requested' => 'Modifiche richieste',
        _ => value?.toString() ?? 'Sconosciuto',
      };
}
