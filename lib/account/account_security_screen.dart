import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/account_api.dart';

/// Account sign-in, owner security and least-privilege account console.
class AccountSecurityScreen extends StatefulWidget {
  const AccountSecurityScreen({super.key, required this.apiBaseUrl});

  final String apiBaseUrl;

  @override
  State<AccountSecurityScreen> createState() => _AccountSecurityScreenState();
}

class _AccountSecurityScreenState extends State<AccountSecurityScreen> {
  final _sessions = const AccountSessionStore();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _loginCode = TextEditingController();
  final _newPassword = TextEditingController();
  final _search = TextEditingController();
  RemoteAccountApi? _api;
  Map<String, dynamic>? _user;
  List<Map<String, dynamic>> _accounts = [];
  List<Map<String, dynamic>> _activeSessions = [];
  List<Map<String, dynamic>> _supportTickets = [];
  Map<String, dynamic>? _adminStats;
  bool _busy = false;
  bool _needsTotp = false;
  bool _totpEnabled = false;
  String? _error;

  Uri? get _baseUri {
    final value = widget.apiBaseUrl.trim();
    if (value.isEmpty) return null;
    return Uri.tryParse(value);
  }

  bool get _isOwner => _user?['role'] == 'owner';
  bool get _isAdmin => _user?['role'] == 'admin';
  bool get _isSupportStaff => _isOwner || _isAdmin || _user?['role'] == 'support';
  bool get _canManage => _isOwner || _user?['role'] == 'admin';
  bool get _canReset => _canManage || _user?['role'] == 'support';
  bool get _mustChangePassword => _user?['mustChangePassword'] == true;

  String get _rolePanelTitle => switch (_user?['role']) {
        'owner' => 'Pannello Proprietario',
        'admin' => 'Pannello Amministratore',
        'support' => 'Pannello Assistenza',
        'collaborator' => 'Pannello Collaboratore',
        _ => 'Area Account',
      };

  String get _rolePanelDescription => switch (_user?['role']) {
        'owner' => 'Controllo completo: account, ruoli, permessi, sicurezza e registro attività.',
        'admin' => 'Gestione operativa degli account e delle attività consentite. Le funzioni esclusive del Proprietario restano bloccate.',
        'support' => 'Assistenza account e reimpostazione password secondo i permessi assegnati.',
        'collaborator' => 'Accesso alle sole funzioni abilitate per il tuo profilo.',
        _ => 'Gestisci le tue sessioni e le impostazioni di sicurezza.',
      };

  @override
  void initState() {
    super.initState();
    _restoreSession();
  }

  @override
  void dispose() {
    _api?.close();
    _username.dispose();
    _password.dispose();
    _loginCode.dispose();
    _newPassword.dispose();
    _search.dispose();
    super.dispose();
  }

  RemoteAccountApi _createApi([String? token]) {
    final base = _baseUri;
    if (base == null) throw StateError('Configura MEDIA_API_URL per collegare il server.');
    return RemoteAccountApi(baseUri: base, bearerToken: token);
  }

  Future<void> _restoreSession() async {
    if (_baseUri == null) return;
    try {
      final token = await _sessions.readToken();
      if (token == null || token.isEmpty) return;
      final api = _createApi(token);
      final response = await api.request('GET', '/v1/auth/me');
      if (!mounted) {
        api.close();
        return;
      }
      _api?.close();
      final restoredUser = Map<String, dynamic>.from(response['user'] as Map);
      setState(() {
        _user = restoredUser;
        _username.text = restoredUser['username']?.toString() ?? '';
      });
      _api = api;
      if (!_mustChangePassword) await _loadConsoleData();
    } on AccountApiException catch (error) {
      if (error.statusCode == 401) await _sessions.clear();
      if (mounted) setState(() => _error = error.message);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _login() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    RemoteAccountApi? api;
    try {
      api = _createApi();
      final body = <String, Object?>{
        'username': _username.text.trim(),
        'password': _password.text,
      };
      if (_loginCode.text.trim().isNotEmpty) {
        body['totpCode'] = _loginCode.text.trim();
      }
      final response = await api.request('POST', '/v1/auth/login', body: body);
      final token = response['accessToken']?.toString() ?? '';
      if (token.isEmpty) throw const FormatException('Il server non ha restituito una sessione.');
      await _sessions.saveToken(token);
      final authenticatedApi = _createApi(token);
      _api?.close();
      _api = authenticatedApi;
      api.close();
      api = null;
      if (!mounted) return;
      setState(() {
        _user = Map<String, dynamic>.from(response['user'] as Map);
        _username.text = _user?['username']?.toString() ?? _username.text;
        _needsTotp = false;
        _loginCode.clear();
        _error = null;
      });
      if (!_mustChangePassword) await _loadConsoleData();
    } on AccountApiException catch (error) {
      if (mounted) {
        setState(() {
          _needsTotp = error.code == 'two_factor_required';
          _error = error.message;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      api?.close();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _logout() async {
    final api = _api;
    try {
      await api?.request('DELETE', '/v1/auth/logout');
    } catch (_) {
      // Always clear the local credential even if the server is unreachable.
    }
    await _sessions.clear();
    api?.close();
    if (!mounted) return;
    setState(() {
      _api = null;
      _user = null;
      _accounts = [];
      _supportTickets = [];
      _adminStats = null;
      _totpEnabled = false;
      _needsTotp = false;
      _password.clear();
      _loginCode.clear();
    });
  }

  Future<void> _changePassword() async {
    final api = _api;
    if (api == null) return;
    final body = <String, Object?>{'newPassword': _newPassword.text};
    if (!_mustChangePassword) body['currentPassword'] = _password.text;
    try {
      final passwordJustSet = _newPassword.text;
      final response = await api.request('POST', '/v1/auth/change-password', body: body);
      final token = response['accessToken']?.toString() ?? '';
      if (token.isEmpty) throw const FormatException('Nuova sessione non restituita.');
      await _sessions.saveToken(token);
      _api?.close();
      _api = _createApi(token);
      if (!mounted) return;
      setState(() {
        _user = Map<String, dynamic>.from(response['user'] as Map);
        _password.text = passwordJustSet;
        _newPassword.clear();
        _error = null;
      });
      await _loadConsoleData();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _loadConsoleData() async {
    final user = _user;
    if (user == null || _mustChangePassword) return;
    await _refreshSessions();
    if (_canReset) await _refreshAccounts();
    if (_isAdmin) await _loadAdminDashboard();
    await _refreshSupportTickets();
    if (_isOwner) await _loadTotpStatus();
  }

  Future<void> _refreshSessions() async {
    final api = _api;
    if (api == null) return;
    try {
      final response = await api.request('GET', '/v1/auth/sessions');
      final rows = response['sessions'] as List? ?? const [];
      if (mounted) {
        setState(() => _activeSessions = rows
            .whereType<Map>()
            .map((row) => Map<String, dynamic>.from(row))
            .toList());
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _revokeSession(Map<String, dynamic> session) async {
    final api = _api;
    if (api == null) return;
    final id = session['sessionId']?.toString() ?? '';
    if (id.isEmpty) return;
    try {
      final response = await api.request(
        'DELETE',
        '/v1/auth/sessions/${Uri.encodeComponent(id)}',
      );
      if (response['currentSessionRevoked'] == true) {
        await _logout();
      } else {
        await _refreshSessions();
        _notify('Sessione revocata.');
      }
    } catch (error) {
      _notify(error.toString());
    }
  }

  Future<void> _refreshAccounts() async {
    final api = _api;
    if (api == null) return;
    try {
      final q = Uri.encodeQueryComponent(_search.text.trim());
      final response = await api.request(
        'GET',
        '/v1/owner/accounts?limit=100&q=$q',
      );
      final rows = response['accounts'] as List? ?? const [];
      if (mounted) {
        setState(() => _accounts = rows
            .whereType<Map>()
            .map((row) => Map<String, dynamic>.from(row))
            .toList());
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _refreshSupportTickets() async {
    final api = _api;
    if (api == null) return;
    try {
      final response = await api.request('GET', '/v1/support/tickets?limit=50');
      final rows = response['tickets'] as List? ?? const [];
      if (mounted) {
        setState(() => _supportTickets = rows
            .whereType<Map>()
            .map((row) => Map<String, dynamic>.from(row))
            .toList());
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _createSupportTicket() async {
    final api = _api;
    if (api == null) return;
    final subject = TextEditingController();
    final message = TextEditingController();
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Nuova richiesta di assistenza'),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: subject, maxLength: 120,
                  decoration: const InputDecoration(labelText: 'Oggetto')),
              TextField(controller: message, minLines: 3, maxLines: 6, maxLength: 4000,
                  decoration: const InputDecoration(labelText: 'Descrivi il problema')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Annulla')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, {
            'subject': subject.text.trim(), 'message': message.text.trim(),
          }), child: const Text('Invia richiesta')),
        ],
      ),
    );
    subject.dispose();
    message.dispose();
    if (result == null) return;
    try {
      await api.request('POST', '/v1/support/tickets', body: result);
      await _refreshSupportTickets();
      _notify('Richiesta inviata all’assistenza.');
    } catch (error) {
      _notify(error.toString());
    }
  }

  Future<void> _openSupportTicket(Map<String, dynamic> row) async {
    final api = _api;
    if (api == null) return;
    final id = row['ticketId']?.toString() ?? '';
    if (id.isEmpty) return;
    final reply = TextEditingController();
    var status = row['status']?.toString() ?? 'open';
    var assignee = row['assignedToUserId']?.toString() ?? '';
    Map<String, dynamic>? ticket;
    try {
      final response = await api.request('GET', '/v1/support/tickets/${Uri.encodeComponent(id)}');
      ticket = Map<String, dynamic>.from(response['ticket'] as Map);
    } catch (error) {
      _notify(error.toString());
      reply.dispose();
      return;
    }
    if (!mounted) { reply.dispose(); return; }
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, refresh) {
          final messages = ticket?['messages'] as List? ?? const [];
          return AlertDialog(
            title: Text(ticket?['subject']?.toString() ?? 'Ticket'),
            content: SizedBox(
              width: 560,
              height: 480,
              child: Column(
                children: [
                  Align(alignment: Alignment.centerLeft,
                    child: Text('Stato: ${ticket?['status'] ?? status}')),
                  const Divider(),
                  Expanded(
                    child: ListView(
                      children: messages.whereType<Map>().map((item) {
                        final isStaff = {'owner', 'admin', 'support'}.contains(item['authorRole']);
                        return Card(
                          child: ListTile(
                            title: Text(isStaff ? 'Assistenza' : 'Utente'),
                            subtitle: SelectableText(item['body']?.toString() ?? ''),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  TextField(
                    controller: reply,
                    minLines: 2,
                    maxLines: 4,
                    maxLength: 4000,
                    decoration: const InputDecoration(labelText: 'Scrivi una risposta'),
                  ),
                  if (_isOwner || _isAdmin) ...[
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: assignee,
                      decoration: const InputDecoration(labelText: 'Operatore assegnato'),
                      items: [
                        const DropdownMenuItem<String>(
                          value: '',
                          child: Text('Non assegnato'),
                        ),
                        ..._accounts.where((account) =>
                          account['role'] == 'support' && account['disabled'] != true
                        ).map((account) => DropdownMenuItem<String>(
                          value: account['userId']?.toString() ?? '',
                          child: Text(account['username']?.toString() ?? 'Support'),
                        )),
                      ],
                      onChanged: (value) => refresh(() => assignee = value ?? ''),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: () async {
                          try {
                            final updated = await api.request(
                              'PUT',
                              '/v1/support/tickets/${Uri.encodeComponent(id)}/assignment',
                              body: {'assigneeUserId': assignee.isEmpty ? null : assignee},
                            );
                            ticket = Map<String, dynamic>.from(updated['ticket'] as Map);
                            await _refreshSupportTickets();
                            refresh(() {});
                            _notify('Assegnazione ticket aggiornata.');
                          } catch (error) {
                            _notify(error.toString());
                          }
                        },
                        icon: const Icon(Icons.assignment_ind_outlined),
                        label: const Text('Salva assegnazione'),
                      ),
                    ),
                  ],
                  if (_isSupportStaff)
                    DropdownButtonFormField<String>(
                      initialValue: status,
                      decoration: const InputDecoration(labelText: 'Stato ticket'),
                      items: const [
                        DropdownMenuItem(value: 'open', child: Text('Aperto')),
                        DropdownMenuItem(value: 'waiting_user', child: Text('In attesa utente')),
                        DropdownMenuItem(value: 'resolved', child: Text('Risolto')),
                        DropdownMenuItem(value: 'escalated', child: Text('Escalato')),
                      ],
                      onChanged: (value) => refresh(() => status = value ?? status),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Chiudi')),
              FilledButton(
                onPressed: () async {
                  if (reply.text.trim().isEmpty) return;
                  try {
                    final body = <String, Object?>{'message': reply.text.trim()};
                    if (_isSupportStaff) body['status'] = status;
                    final updated = await api.request(
                      'POST',
                      '/v1/support/tickets/${Uri.encodeComponent(id)}/messages',
                      body: body,
                    );
                    ticket = Map<String, dynamic>.from(updated['ticket'] as Map);
                    reply.clear();
                    refresh(() {});
                    await _refreshSupportTickets();
                  } catch (error) {
                    _notify(error.toString());
                  }
                },
                child: const Text('Invia risposta'),
              ),
            ],
          );
        },
      ),
    );
    reply.dispose();
  }

  Future<void> _loadAdminDashboard() async {
    final api = _api;
    if (api == null || !_isAdmin) return;
    try {
      final response = await api.request('GET', '/v1/admin/dashboard');
      final data = response['dashboard'];
      if (mounted && data is Map) {
        setState(() => _adminStats = Map<String, dynamic>.from(data));
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _loadTotpStatus() async {
    final api = _api;
    if (api == null || !_isOwner) return;
    try {
      final response = await api.request('GET', '/v1/owner/security/totp');
      if (mounted) setState(() => _totpEnabled = response['enabled'] == true);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _createAccount() async {
    final api = _api;
    if (api == null || !_canManage) return;
    final username = TextEditingController();
    final password = TextEditingController();
    var role = 'user';
    final allowedRoles = _isOwner
        ? const ['user', 'collaborator', 'support', 'admin']
        : const ['user', 'collaborator'];
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, refresh) => AlertDialog(
          title: const Text('Crea account'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: username, decoration: const InputDecoration(labelText: 'Nome utente')),
              TextField(controller: password, obscureText: true, decoration: const InputDecoration(labelText: 'Password temporanea (minimo 12 caratteri)')),
              DropdownButton<String>(
                value: role,
                isExpanded: true,
                items: allowedRoles.map((value) => DropdownMenuItem(value: value, child: Text(value))).toList(),
                onChanged: (value) => refresh(() => role = value ?? role),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Annulla')),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, {
                'username': username.text.trim(),
                'password': password.text,
                'role': role,
              }),
              child: const Text('Crea'),
            ),
          ],
        ),
      ),
    );
    username.dispose();
    password.dispose();
    if (result == null) return;
    try {
      await api.request('POST', '/v1/owner/accounts', body: {
        'username': result['username'],
        'temporaryPassword': result['password'],
        'role': result['role'],
      });
      await _refreshAccounts();
      _notify('Account creato. Al primo accesso dovrà cambiare la password.');
    } catch (error) {
      _notify(error.toString());
    }
  }

  Future<void> _resetPassword(Map<String, dynamic> account) async {
    final api = _api;
    if (api == null || !_canReset) return;
    try {
      final response = await api.request(
        'POST',
        '/v1/owner/accounts/${Uri.encodeComponent(account['userId'].toString())}/reset-password',
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Password temporanea'),
          content: SelectableText(response['temporaryPassword']?.toString() ?? ''),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Chiudi'))],
        ),
      );
      await _refreshAccounts();
    } catch (error) {
      _notify(error.toString());
    }
  }

  Future<void> _setRole(Map<String, dynamic> account) async {
    final api = _api;
    if (api == null || !_canManage || account['role'] == 'owner') return;
    var role = account['role']?.toString() ?? 'user';
    final roles = _isOwner
        ? const ['user', 'collaborator', 'support', 'admin']
        : const ['user', 'collaborator', 'support'];
    final selected = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, refresh) => AlertDialog(
          title: const Text('Modifica ruolo'),
          content: DropdownButton<String>(
            value: roles.contains(role) ? role : roles.first,
            isExpanded: true,
            items: roles.map((value) => DropdownMenuItem(value: value, child: Text(value))).toList(),
            onChanged: (value) => refresh(() => role = value ?? role),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Annulla')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, role), child: const Text('Salva')),
          ],
        ),
      ),
    );
    if (selected == null) return;
    try {
      await api.request(
        'POST',
        '/v1/owner/accounts/${Uri.encodeComponent(account['userId'].toString())}/role',
        body: {'role': selected},
      );
      await _refreshAccounts();
    } catch (error) {
      _notify(error.toString());
    }
  }

  Future<void> _setDisabled(Map<String, dynamic> account, bool disabled) async {
    final api = _api;
    if (api == null || !_canManage || account['role'] == 'owner') return;
    try {
      await api.request(
        'POST',
        '/v1/owner/accounts/${Uri.encodeComponent(account['userId'].toString())}/${disabled ? 'disable' : 'enable'}',
      );
      await _refreshAccounts();
    } catch (error) {
      _notify(error.toString());
    }
  }

  Future<void> _showPermissions(Map<String, dynamic> account) async {
    final api = _api;
    if (api == null || !_isOwner) return;
    final id = Uri.encodeComponent(account['userId'].toString());
    try {
      final response = await api.request('GET', '/v1/owner/accounts/$id/permissions');
      final effective = (response['effectivePermissions'] as List? ?? const []).join('\n');
      final overrides = response['overrides'] as List? ?? const [];
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Permessi · ${account['username']}'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Permessi effettivi', style: TextStyle(fontWeight: FontWeight.bold)),
                  SelectableText(effective.isEmpty ? 'Nessuno' : effective),
                  const SizedBox(height: 12),
                  const Text('Override', style: TextStyle(fontWeight: FontWeight.bold)),
                  ...overrides.map((item) => Row(
                    children: [
                      Expanded(child: Text('${item['permission']}: ${item['effect']}')),
                      IconButton(
                        tooltip: 'Rimuovi override',
                        onPressed: () async {
                          Navigator.pop(context);
                          await _removePermissionOverride(
                            account, item['permission']?.toString() ?? '',
                          );
                        },
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ],
                  )),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                await _editPermission(account);
              },
              child: const Text('Modifica override'),
            ),
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Chiudi')),
          ],
        ),
      );
    } catch (error) {
      _notify(error.toString());
    }
  }

  Future<void> _removePermissionOverride(
    Map<String, dynamic> account, String permission
  ) async {
    final api = _api;
    if (api == null || !_isOwner || permission.isEmpty) return;
    try {
      await api.request(
        'DELETE',
        '/v1/owner/accounts/${Uri.encodeComponent(account['userId'].toString())}/permissions/${Uri.encodeComponent(permission)}',
      );
      _notify('Override rimosso: torna ai permessi predefiniti.');
      await _showPermissions(account);
    } catch (error) {
      _notify(error.toString());
    }
  }

  Future<void> _editPermission(Map<String, dynamic> account) async {
    final api = _api;
    if (api == null || !_isOwner) return;
    const permissions = [
      'accounts.read', 'accounts.create', 'accounts.update', 'accounts.disable',
      'accounts.password_reset', 'audit.read', 'media.support_read',
      'billing.read', 'billing.grant', 'family.manage', 'settings.manage',
    ];
    var permission = permissions.first;
    var effect = 'allow';
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, refresh) => AlertDialog(
          title: const Text('Override permesso'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButton<String>(
                value: permission,
                isExpanded: true,
                items: permissions.map((value) => DropdownMenuItem(value: value, child: Text(value))).toList(),
                onChanged: (value) => refresh(() => permission = value ?? permission),
              ),
              DropdownButton<String>(
                value: effect,
                isExpanded: true,
                items: const [
                  DropdownMenuItem(value: 'allow', child: Text('Consenti')),
                  DropdownMenuItem(value: 'deny', child: Text('Nega')),
                ],
                onChanged: (value) => refresh(() => effect = value ?? effect),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Annulla')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, {'permission': permission, 'effect': effect}), child: const Text('Salva')),
          ],
        ),
      ),
    );
    if (result == null) return;
    try {
      await api.request(
        'PUT',
        '/v1/owner/accounts/${Uri.encodeComponent(account['userId'].toString())}/permissions',
        body: result,
      );
      _notify('Override aggiornato.');
    } catch (error) {
      _notify(error.toString());
    }
  }

  Future<void> _showAudit() async {
    final api = _api;
    if (api == null || !_isOwner) return;
    try {
      final response = await api.request('GET', '/v1/owner/audit?limit=100');
      var events = (response['events'] as List? ?? const [])
          .whereType<Map>()
          .map((event) => Map<String, dynamic>.from(event))
          .toList();
      var hasMore = response['hasMore'] == true;
      var loadingMore = false;
      if (!mounted) return;
      final search = TextEditingController();
      String action = 'Tutte';
      final actions = ['Tutte', ...{for (final event in events) event['action']?.toString() ?? ''}.where((value) => value.isNotEmpty)];
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, refresh) {
            final term = search.text.trim().toLowerCase();
            final filtered = events.where((event) {
              final matchesAction = action == 'Tutte' || event['action'] == action;
              final haystack = [
                event['action'], event['actorUserId'], event['targetUserId'],
                event['details'], event['createdAt'],
              ].join(' ').toLowerCase();
              return matchesAction && (term.isEmpty || haystack.contains(term));
            }).toList();
            return AlertDialog(
              title: const Text('Registro sicurezza'),
              content: SizedBox(
                width: 560,
                height: 520,
                child: Column(
                  children: [
                    TextField(
                      controller: search,
                      decoration: const InputDecoration(
                        labelText: 'Cerca azione, attore, account o dettagli',
                        prefixIcon: Icon(Icons.search),
                      ),
                      onChanged: (_) => refresh(() {}),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: action,
                      decoration: const InputDecoration(labelText: 'Filtra per azione'),
                      items: actions.map((value) => DropdownMenuItem(value: value, child: Text(value))).toList(),
                      onChanged: (value) => refresh(() => action = value ?? 'Tutte'),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text('${filtered.length} eventi · massimo 100 più recenti'),
                    ),
                    const Divider(),
                    Expanded(
                      child: filtered.isEmpty
                          ? const Center(child: Text('Nessun evento corrispondente.'))
                          : ListView.builder(
                              itemCount: filtered.length,
                              itemBuilder: (context, index) {
                                final item = filtered[index];
                                final timestamp = int.tryParse(item['createdAt']?.toString() ?? '');
                                final date = timestamp == null
                                    ? 'Data non disponibile'
                                    : DateTime.fromMillisecondsSinceEpoch(timestamp * 1000).toLocal().toString();
                                return ListTile(
                                  dense: true,
                                  leading: const Icon(Icons.security),
                                  title: Text(item['action']?.toString() ?? ''),
                                  subtitle: Text('Attore: ${item['actorUserId'] ?? 'sistema'}\nDestinatario: ${item['targetUserId'] ?? 'sistema'}\n$date'),
                                  isThreeLine: true,
                                  onTap: () => showDialog<void>(
                                    context: context,
                                    builder: (detailContext) => AlertDialog(
                                      title: Text(item['action']?.toString() ?? 'Evento'),
                                      content: SingleChildScrollView(
                                        child: SelectableText(
                                          'ID: ${item['eventId']}\nAttore: ${item['actorUserId']}\nDestinatario: ${item['targetUserId']}\nData: $date\nDettagli: ${item['details']}',
                                        ),
                                      ),
                                      actions: [TextButton(onPressed: () => Navigator.pop(detailContext), child: const Text('Chiudi'))],
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                    if (hasMore)
                      Align(
                        alignment: Alignment.center,
                        child: TextButton.icon(
                          onPressed: loadingMore ? null : () async {
                            refresh(() => loadingMore = true);
                            try {
                              final next = await api.request(
                                'GET',
                                '/v1/owner/audit?limit=100&offset=${events.length}',
                              );
                              final added = (next['events'] as List? ?? const [])
                                  .whereType<Map>()
                                  .map((event) => Map<String, dynamic>.from(event))
                                  .toList();
                              refresh(() {
                                events = [...events, ...added];
                                hasMore = next['hasMore'] == true;
                                loadingMore = false;
                              });
                            } catch (error) {
                              refresh(() => loadingMore = false);
                              _notify(error.toString());
                            }
                          },
                          icon: loadingMore
                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.expand_more),
                          label: Text(loadingMore ? 'Caricamento…' : 'Carica altri eventi'),
                        ),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Chiudi')),
              ],
            );
          },
        ),
      );
      search.dispose();
    } catch (error) {
      _notify(error.toString());
    }
  }

  Future<void> _managePremium(Map<String, dynamic> account) async {
    final api = _api;
    if (api == null || !_isOwner) return;
    final userId = Uri.encodeComponent(account['userId']?.toString() ?? '');
    if (userId.isEmpty) return;
    try {
      var response = await api.request('GET', '/v1/owner/accounts/$userId/premium-grants?limit=100');
      var grants = (response['grants'] as List? ?? const [])
          .whereType<Map>()
          .map((grant) => Map<String, dynamic>.from(grant))
          .toList();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, refresh) => AlertDialog(
            title: Text('Premium · ${account['username']}'),
            content: SizedBox(
              width: 520,
              height: 440,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton.icon(
                      onPressed: () async {
                        final grant = await _promptPremiumGrant();
                        if (grant == null) return;
                        try {
                          await api.request('POST', '/v1/owner/accounts/$userId/premium-grants', body: grant);
                          response = await api.request('GET', '/v1/owner/accounts/$userId/premium-grants?limit=100');
                          grants = (response['grants'] as List? ?? const [])
                              .whereType<Map>()
                              .map((item) => Map<String, dynamic>.from(item))
                              .toList();
                          refresh(() {});
                          _notify('Concessione Premium registrata e auditata.');
                        } catch (error) {
                          _notify(error.toString());
                        }
                      },
                      icon: const Icon(Icons.workspace_premium),
                      label: const Text('Concedi Premium'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Flexible(
                    child: grants.isEmpty
                        ? const Center(child: Text('Nessuna concessione Premium registrata.'))
                        : ListView.builder(
                            shrinkWrap: true,
                            itemCount: grants.length,
                            itemBuilder: (context, index) {
                              final grant = grants[index];
                              final revoked = grant['revoked_at'] != null;
                              final expiry = grant['expires_at'];
                              final expiryLabel = expiry == null
                                  ? 'Senza scadenza'
                                  : DateTime.fromMillisecondsSinceEpoch(
                                      (int.tryParse(expiry.toString()) ?? 0) * 1000,
                                    ).toLocal().toString();
                              return ListTile(
                                dense: true,
                                title: Text('${grant['plan'] == 'family' ? 'Premium famiglia' : 'Premium individuale'} · ${revoked ? 'revocato' : 'registrato'}'),
                                subtitle: Text('Dal: ${grant['starts_at']}\nScadenza: $expiryLabel\nMotivo: ${grant['reason'] ?? ''}'),
                                isThreeLine: true,
                                trailing: revoked
                                    ? const Icon(Icons.block, color: Colors.grey)
                                    : IconButton(
                                        tooltip: 'Revoca concessione',
                                        icon: const Icon(Icons.remove_circle_outline),
                                        onPressed: () async {
                                          final grantId = grant['grant_id']?.toString() ?? '';
                                          if (grantId.isEmpty) return;
                                          final confirmed = await showDialog<bool>(
                                            context: context,
                                            builder: (confirmContext) => AlertDialog(
                                              title: const Text('Revocare Premium?'),
                                              content: const Text('L’accesso Premium concesso da questa promozione verrà revocato.'),
                                              actions: [
                                                TextButton(onPressed: () => Navigator.pop(confirmContext, false), child: const Text('Annulla')),
                                                FilledButton(onPressed: () => Navigator.pop(confirmContext, true), child: const Text('Revoca')),
                                              ],
                                            ),
                                          );
                                          if (confirmed != true) return;
                                          try {
                                            await api.request('DELETE', '/v1/owner/accounts/$userId/premium-grants/${Uri.encodeComponent(grantId)}');
                                            response = await api.request('GET', '/v1/owner/accounts/$userId/premium-grants?limit=100');
                                            grants = (response['grants'] as List? ?? const [])
                                                .whereType<Map>()
                                                .map((item) => Map<String, dynamic>.from(item))
                                                .toList();
                                            refresh(() {});
                                            _notify('Concessione Premium revocata.');
                                          } catch (error) {
                                            _notify(error.toString());
                                          }
                                        },
                                      ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
            actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Chiudi'))],
          ),
        ),
      );
    } catch (error) {
      _notify(error.toString());
    }
  }

  Future<Map<String, Object?>?> _promptPremiumGrant() async {
    var plan = 'premium';
    var duration = '30';
    final reason = TextEditingController(text: 'Promozione concessa dal Proprietario');
    final result = await showDialog<Map<String, Object?>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, refresh) => AlertDialog(
          title: const Text('Nuova concessione Premium'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: plan,
                decoration: const InputDecoration(labelText: 'Piano'),
                items: const [
                  DropdownMenuItem(value: 'premium', child: Text('Premium individuale')),
                  DropdownMenuItem(value: 'family', child: Text('Premium famiglia')),
                ],
                onChanged: (value) => refresh(() => plan = value ?? plan),
              ),
              DropdownButtonFormField<String>(
                initialValue: duration,
                decoration: const InputDecoration(labelText: 'Durata'),
                items: const [
                  DropdownMenuItem(value: '30', child: Text('30 giorni')),
                  DropdownMenuItem(value: '90', child: Text('90 giorni')),
                  DropdownMenuItem(value: '365', child: Text('1 anno')),
                  DropdownMenuItem(value: '0', child: Text('Senza scadenza')),
                ],
                onChanged: (value) => refresh(() => duration = value ?? duration),
              ),
              TextField(
                controller: reason,
                maxLength: 240,
                decoration: const InputDecoration(labelText: 'Motivo / riferimento'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Annulla')),
            FilledButton(
              onPressed: () {
                if (reason.text.trim().isEmpty) return;
                final days = int.parse(duration);
                Navigator.pop(dialogContext, {
                  'plan': plan,
                  'reason': reason.text.trim(),
                  'expiresAt': days == 0
                      ? null
                      : DateTime.now().millisecondsSinceEpoch ~/ 1000 + days * 86400,
                });
              },
              child: const Text('Conferma'),
            ),
          ],
        ),
      ),
    );
    reason.dispose();
    return result;
  }

  Future<void> _startTotpSetup() async {
    final api = _api;
    if (api == null || !_isOwner) return;
    final password = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Attiva verifica in due passaggi'),
        content: TextField(controller: password, obscureText: true, decoration: const InputDecoration(labelText: 'Password attuale')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annulla')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Continua')),
        ],
      ),
    );
    if (accepted != true) {
      password.dispose();
      return;
    }
    try {
      final setup = await api.request('POST', '/v1/owner/security/totp/setup', body: {'password': password.text});
      password.dispose();
      if (!mounted) return;
      final secret = setup['secret']?.toString() ?? '';
      final uri = setup['otpauthUri']?.toString() ?? '';
      final code = TextEditingController();
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Configura l’app autenticatore'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Aggiungi questo account all’app autenticatore usando il codice o l’indirizzo seguente.'),
                const SizedBox(height: 8),
                SelectableText(secret, style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                SelectableText(uri),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => Clipboard.setData(ClipboardData(text: uri)),
                    icon: const Icon(Icons.copy),
                    label: const Text('Copia indirizzo'),
                  ),
                ),
                TextField(controller: code, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Codice a 6 cifre')),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annulla')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Conferma')),
          ],
        ),
      );
      if (confirm == true) {
        final response = await api.request(
          'POST',
          '/v1/owner/security/totp/setup/confirm',
          body: {'code': code.text.trim()},
        );
        final codes = (response['recoveryCodes'] as List? ?? const []).join('\n');
        if (mounted) {
          await showDialog<void>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Codici di recupero: salvali ora'),
              content: SelectableText(codes),
              actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Ho salvato i codici'))],
            ),
          );
          // Enrollment revokes all existing sessions; prompt a fresh 2FA login.
          await _sessions.clear();
          _api?.close();
          setState(() {
            _api = null;
            _user = null;
            _totpEnabled = true;
            _needsTotp = true;
            _password.clear();
            _loginCode.clear();
            _error = 'Verifica in due passaggi attivata. Accedi nuovamente con il codice.';
          });
        }
      }
      code.dispose();
    } catch (error) {
      password.dispose();
      _notify(error.toString());
    }
  }

  Future<void> _disableTotp() async {
    final api = _api;
    if (api == null || !_isOwner) return;
    final password = TextEditingController();
    final code = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Disattiva verifica in due passaggi'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: password, obscureText: true, decoration: const InputDecoration(labelText: 'Password attuale')),
            TextField(
              controller: code,
              keyboardType: TextInputType.visiblePassword,
              textCapitalization: TextCapitalization.characters,
              autocorrect: false,
              decoration: const InputDecoration(labelText: 'Codice autenticatore o codice di recupero'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annulla')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Disattiva')),
        ],
      ),
    );
    if (accepted == true) {
      try {
        await api.request('DELETE', '/v1/owner/security/totp', body: {
          'password': password.text,
          'code': code.text.trim(),
        });
        await _sessions.clear();
        if (mounted) {
          setState(() {
            _user = null;
            _api?.close();
            _api = null;
          });
          _notify('2FA disattivata. Per sicurezza, accedi nuovamente.');
        }
      } catch (error) {
        _notify(error.toString());
      }
    }
    password.dispose();
    code.dispose();
  }

  void _notify(String message) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _loginPanel() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Accedi all’account', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            TextField(controller: _username, textInputAction: TextInputAction.next, decoration: const InputDecoration(labelText: 'Nome utente')),
            TextField(controller: _password, obscureText: true, decoration: const InputDecoration(labelText: 'Password')),
            if (_needsTotp)
              TextField(
                controller: _loginCode,
                keyboardType: TextInputType.visiblePassword,
                textCapitalization: TextCapitalization.characters,
                autocorrect: false,
                decoration: const InputDecoration(labelText: 'Codice 2FA o codice di recupero'),
              ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _busy ? null : _login,
              child: Text(_busy ? 'Accesso…' : 'Accedi'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _passwordChangePanel() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Cambio password obbligatorio', style: TextStyle(fontWeight: FontWeight.bold)),
            const Text('Prima di usare le funzioni protette devi impostare una password personale di almeno 12 caratteri.'),
            if (!_mustChangePassword)
              TextField(controller: _password, obscureText: true, decoration: const InputDecoration(labelText: 'Password attuale')),
            TextField(controller: _newPassword, obscureText: true, decoration: const InputDecoration(labelText: 'Nuova password')),
            FilledButton(onPressed: _busy ? null : _changePassword, child: const Text('Aggiorna password')),
          ],
        ),
      ),
    );
  }

  Widget _sessionTile(Map<String, dynamic> session) {
    final current = session['current'] == true;
    final created = int.tryParse(session['createdAt']?.toString() ?? '');
    final expires = int.tryParse(session['expiresAt']?.toString() ?? '');
    final createdLabel = created == null
        ? 'Data non disponibile'
        : DateTime.fromMillisecondsSinceEpoch(created * 1000).toLocal().toString();
    final expiresLabel = expires == null
        ? 'Scadenza non disponibile'
        : DateTime.fromMillisecondsSinceEpoch(expires * 1000).toLocal().toString();
    return ListTile(
      leading: Icon(current ? Icons.phone_android : Icons.devices_other),
      title: Text(current ? 'Sessione corrente' : 'Altra sessione'),
      subtitle: Text('Accesso: $createdLabel\nScade: $expiresLabel'),
      isThreeLine: true,
      trailing: current
          ? const Chip(label: Text('Questa'))
          : IconButton(
              tooltip: 'Revoca sessione',
              onPressed: () => _revokeSession(session),
              icon: const Icon(Icons.logout),
            ),
    );
  }

  Widget _accountTile(Map<String, dynamic> account) {
    final role = account['role']?.toString() ?? 'user';
    final disabled = account['disabled'] == true;
    final id = account['userId']?.toString() ?? '';
    return Card(
      child: ListTile(
        title: Text(account['username']?.toString() ?? id),
        subtitle: Text('$role · ${disabled ? 'sospeso' : 'attivo'}'),
        trailing: PopupMenuButton<String>(
          onSelected: (action) {
            if (action == 'reset') _resetPassword(account);
            if (action == 'role') _setRole(account);
            if (action == 'disable') _setDisabled(account, true);
            if (action == 'enable') _setDisabled(account, false);
            if (action == 'permissions') _showPermissions(account);
            if (action == 'premium') _managePremium(account);
          },
          itemBuilder: (context) => [
            if (_canReset && role != 'owner' && (_isOwner || role != 'admin'))
              const PopupMenuItem(value: 'reset', child: Text('Reimposta password')),
            if (_canManage && role != 'owner' && (_isOwner || role != 'admin'))
              const PopupMenuItem(value: 'role', child: Text('Modifica ruolo')),
            if (_canManage && role != 'owner' && (_isOwner || role != 'admin') && !disabled)
              const PopupMenuItem(value: 'disable', child: Text('Sospendi account')),
            if (_canManage && role != 'owner' && (_isOwner || role != 'admin') && disabled)
              const PopupMenuItem(value: 'enable', child: Text('Riattiva account')),
            if (_isOwner)
              const PopupMenuItem(value: 'permissions', child: Text('Permessi effettivi')),
            if (_isOwner)
              const PopupMenuItem(value: 'premium', child: Text('Gestisci Premium')),
          ],
        ),
      ),
    );
  }

  Widget _adminMetric(String label, Object? value) {
    return SizedBox(
      width: 145,
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value?.toString() ?? '—',
                  style: Theme.of(context).textTheme.headlineSmall),
              Text(label, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_baseUri == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Configura MEDIA_API_URL con l’indirizzo HTTPS del backend per attivare account e sicurezza. Per sviluppo locale è consentito localhost o 10.0.2.2.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      );
    }
    if (_user == null) return ListView(
      padding: const EdgeInsets.all(8),
      children: [
        _loginPanel(),
        if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
      ],
    );
    if (_mustChangePassword) return ListView(
      padding: const EdgeInsets.all(8),
      children: [
        _passwordChangePanel(),
        if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
      ],
    );

    return ListView(
      padding: const EdgeInsets.all(8),
      children: [
        Card(
          child: ListTile(
            leading: const Icon(Icons.verified_user_outlined),
            title: Text(_user?['username']?.toString() ?? 'Account'),
            subtitle: Text('Ruolo: ${_user?['role'] ?? 'user'}'),
            trailing: TextButton(onPressed: _logout, child: const Text('Esci')),
          ),
        ),
        Card(
          child: ListTile(
            leading: Icon(
              _isOwner ? Icons.admin_panel_settings : _canManage ? Icons.manage_accounts : Icons.account_circle_outlined,
              size: 30,
            ),
            title: Text(_rolePanelTitle, style: Theme.of(context).textTheme.titleLarge),
            subtitle: Text(_rolePanelDescription),
          ),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text('Sessioni attive', style: Theme.of(context).textTheme.titleMedium),
                    ),
                    IconButton(
                      onPressed: _refreshSessions,
                      tooltip: 'Aggiorna sessioni',
                      icon: const Icon(Icons.refresh),
                    ),
                  ],
                ),
                if (_activeSessions.isEmpty)
                  const Text('Nessuna sessione attiva trovata.')
                else
                  ..._activeSessions.map(_sessionTile),
              ],
            ),
          ),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.support_agent),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(_isSupportStaff ? 'Console Assistenza' : 'Le mie richieste',
                          style: Theme.of(context).textTheme.titleLarge),
                    ),
                    IconButton(onPressed: _refreshSupportTickets,
                        tooltip: 'Aggiorna ticket', icon: const Icon(Icons.refresh)),
                    IconButton(onPressed: _createSupportTicket,
                        tooltip: 'Nuovo ticket', icon: const Icon(Icons.add_comment_outlined)),
                  ],
                ),
                Text(_isSupportStaff
                    ? 'Gestisci le richieste, rispondi e aggiorna lo stato. I contenuti restano isolati per ticket.'
                    : 'Apri una richiesta e consulta lo storico delle risposte dell’assistenza.'),
                const SizedBox(height: 8),
                if (_supportTickets.isEmpty)
                  const Text('Nessuna richiesta presente.')
                else
                  ..._supportTickets.map((ticket) => ListTile(
                    leading: const Icon(Icons.confirmation_number_outlined),
                    title: Text(ticket['subject']?.toString() ?? 'Ticket'),
                    subtitle: Text(
                      'Stato: ${ticket['status']}' +
                      ((_isOwner || _isAdmin) && ticket['assignedToUserId'] != null
                        ? ' • Assegnato'
                        : ''),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _openSupportTicket(ticket),
                  )),
              ],
            ),
          ),
        ),
        if (_isAdmin) ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.admin_panel_settings_outlined),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text('Dashboard Amministratore',
                            style: Theme.of(context).textTheme.titleLarge),
                      ),
                      IconButton(
                        tooltip: 'Aggiorna statistiche',
                        onPressed: _loadAdminDashboard,
                        icon: const Icon(Icons.refresh),
                      ),
                    ],
                  ),
                  const Text('Statistiche aggregate: nessun dato personale o credenziale è esposto in questa scheda.'),
                  const SizedBox(height: 12),
                  if (_adminStats == null)
                    const LinearProgressIndicator()
                  else
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        _adminMetric('Account totali', _adminStats!['totalAccounts']),
                        _adminMetric('Attivi', _adminStats!['activeAccounts']),
                        _adminMetric('Sospesi', _adminStats!['disabledAccounts']),
                        _adminMetric('Nuovi · 30 giorni', _adminStats!['createdLast30Days']),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ],
        if (_isOwner) Card(
          child: ListTile(
            leading: Icon(_totpEnabled ? Icons.lock : Icons.lock_open),
            title: const Text('Verifica in due passaggi'),
            subtitle: Text(_totpEnabled ? 'Attiva · TOTP e codici di recupero' : 'Non ancora attiva'),
            trailing: TextButton(
              onPressed: _busy ? null : (_totpEnabled ? _disableTotp : _startTotpSetup),
              child: Text(_totpEnabled ? 'Disattiva' : 'Attiva'),
            ),
          ),
        ),
        if (_isOwner)
          OutlinedButton.icon(
            onPressed: _showAudit,
            icon: const Icon(Icons.receipt_long),
            label: const Text('Registro sicurezza'),
          ),
        if (_canReset) ...[
          const SizedBox(height: 12),
          Text(
            _isOwner ? 'Console Proprietario · Gestione completa' : 'Console Amministratore · Gestione consentita',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text('Gestione account', style: Theme.of(context).textTheme.titleLarge),
              ),
              if (_canManage)
                IconButton(onPressed: _createAccount, icon: const Icon(Icons.person_add_alt_1), tooltip: 'Crea account'),
              IconButton(onPressed: _refreshAccounts, icon: const Icon(Icons.refresh), tooltip: 'Aggiorna'),
            ],
          ),
          TextField(
            controller: _search,
            decoration: InputDecoration(
              labelText: 'Cerca account',
              suffixIcon: IconButton(onPressed: _refreshAccounts, icon: const Icon(Icons.search)),
            ),
            onSubmitted: (_) => _refreshAccounts(),
          ),
          const SizedBox(height: 8),
          ..._accounts.map(_accountTile),
        ],
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
      ],
    );
  }
}
