import 'account_api.dart';

/// Typed access layer for the account-scoped TeamStudio REST endpoints.
/// It never stores credentials: the shared RemoteAccountApi supplies the
/// secure bearer session and enforces same-origin HTTPS.
class RemoteTeamApi {
  const RemoteTeamApi(this._api);

  final RemoteAccountApi _api;

  Future<List<Map<String, dynamic>>> listProjects() async =>
      _items(await _api.request('GET', '/v1/team/projects'), 'projects');

  Future<List<Map<String, dynamic>>> listInvitations() async =>
      _items(await _api.request('GET', '/v1/team/invitations'), 'invitations');

  Future<Map<String, dynamic>> createProject({
    required String name,
    String description = '',
  }) async {
    final result = await _api.request('POST', '/v1/team/projects',
        body: {'name': name.trim(), 'description': description.trim()});
    return _object(result, 'project');
  }

  Future<Map<String, dynamic>> invite({
    required String projectId,
    required String collaboratorUserId,
  }) async {
    final result = await _api.request(
      'POST',
      '/v1/team/projects/${_segment(projectId)}/invitations',
      body: {'collaboratorUserId': collaboratorUserId.trim()},
    );
    return _object(result, 'invitation');
  }

  Future<Map<String, dynamic>> respondInvitation({
    required String projectId,
    required bool accept,
  }) async {
    final result = await _api.request(
      'PUT',
      '/v1/team/projects/${_segment(projectId)}/invitation',
      body: {'accept': accept},
    );
    return _object(result, 'invitation');
  }

  Future<List<Map<String, dynamic>>> listMembers(String projectId) async =>
      _items(await _api.request(
        'GET', '/v1/team/projects/${_segment(projectId)}/members'), 'members');

  Future<void> revokeMember({
    required String projectId,
    required String memberUserId,
  }) async {
    await _api.request(
      'DELETE',
      '/v1/team/projects/${_segment(projectId)}/members/${_segment(memberUserId)}',
    );
  }

  Future<List<Map<String, dynamic>>> listComments(String projectId) async =>
      _items(await _api.request(
        'GET', '/v1/team/projects/${_segment(projectId)}/comments'), 'comments');

  Future<Map<String, dynamic>> addComment({
    required String projectId,
    required String body,
  }) async {
    final result = await _api.request(
      'POST',
      '/v1/team/projects/${_segment(projectId)}/comments',
      body: {'body': body.trim()},
    );
    return _object(result, 'comment');
  }

  Future<List<Map<String, dynamic>>> listApprovals(String projectId) async =>
      _items(await _api.request(
        'GET', '/v1/team/projects/${_segment(projectId)}/approvals'), 'approvals');

  Future<Map<String, dynamic>> requestApproval({
    required String projectId,
    String note = '',
  }) async {
    final result = await _api.request(
      'POST',
      '/v1/team/projects/${_segment(projectId)}/approvals',
      body: {'note': note.trim()},
    );
    return _object(result, 'approval');
  }

  Future<Map<String, dynamic>> respondApproval({
    required String approvalId,
    required String decision,
    String note = '',
  }) async {
    final result = await _api.request(
      'PUT',
      '/v1/team/approvals/${_segment(approvalId)}',
      body: {'decision': decision, 'note': note.trim()},
    );
    return _object(result, 'approval');
  }

  static String _segment(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty || trimmed.length > 128 ||
        trimmed.contains('/') || trimmed.contains('\\\\')) {
      throw ArgumentError.value(value, 'identifier', 'Identificativo TeamStudio non valido.');
    }
    return Uri.encodeComponent(trimmed);
  }

  static List<Map<String, dynamic>> _items(
    Map<String, dynamic> response,
    String key,
  ) {
    final value = response[key];
    if (value is! List) {
      throw FormatException('Elenco TeamStudio "$key" non valido.');
    }
    return value.map((item) {
      if (item is! Map) throw const FormatException('Elemento TeamStudio non valido.');
      return Map<String, dynamic>.from(item);
    }).toList(growable: false);
  }

  static Map<String, dynamic> _object(
    Map<String, dynamic> response,
    String key,
  ) {
    final value = response[key];
    if (value is! Map) throw FormatException('Oggetto TeamStudio "$key" non valido.');
    return Map<String, dynamic>.from(value);
  }
}
