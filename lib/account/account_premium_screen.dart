import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/account_entitlement.dart';
import '../services/account_api.dart';

/// Presentational account screen. Data/actions are injected by the app layer,
/// keeping authentication and billing provider independent.
class AccountPremiumScreen extends StatelessWidget {
  const AccountPremiumScreen({
    super.key,
    required this.userId,
    required this.entitlement,
    required this.referralCode,
    required this.onSignIn,
    required this.onUpgrade,
    required this.onRestore,
    required this.onShareReferral,
    required this.onRedeemReferral,
    this.usageSummary,
    this.creditBalance,
    this.apiBaseUrl = '',
  });

  final String? userId;
  final UserEntitlement? entitlement;
  final String? referralCode;
  final VoidCallback onSignIn;
  final VoidCallback onUpgrade;
  final VoidCallback onRestore;
  final VoidCallback onShareReferral;
  final ValueChanged<String> onRedeemReferral;
  final Map<String, dynamic>? usageSummary;
  final int? creditBalance;
  final String apiBaseUrl;

  @override
  Widget build(BuildContext context) {
    final signedIn = userId != null && userId!.isNotEmpty;
    final premium = entitlement?.isPremium ?? false;
    final planLabel = entitlement?.plan == 'family'
        ? 'Premium famiglia'
        : entitlement?.plan == 'premium'
            ? 'Premium individuale'
            : 'Piano gratuito';
    final expiry = entitlement?.validUntil;
    return Scaffold(
      appBar: AppBar(title: const Text('Account e Premium')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: Icon(premium ? Icons.workspace_premium : Icons.person_outline),
              title: Text(signedIn ? 'Account collegato' : 'Usa il tuo account'),
              subtitle: Text(premium
                  ? expiry == null
                      ? '$planLabel · accesso senza scadenza indicata'
                      : '$planLabel · valido fino al ${MaterialLocalizations.of(context).formatMediumDate(expiry.toLocal())}'
                  : signedIn
                      ? 'Piano gratuito'
                      : 'Accedi per sincronizzare progetti e vantaggi'),
              trailing: signedIn
                  ? null
                  : FilledButton(onPressed: onSignIn, child: const Text('Accedi')),
            ),
          ),
          if (signedIn && creditBalance != null) ...[
            const SizedBox(height: 12),
            Card(
              child: ListTile(
                leading: const Icon(Icons.toll_outlined),
                title: const Text('Crediti IA'),
                subtitle: const Text('Saldo disponibile nel portafoglio account'),
                trailing: Text('$creditBalance', style: Theme.of(context).textTheme.titleLarge),
              ),
            ),
          ],
          if (signedIn && usageSummary != null) ...[
            const SizedBox(height: 12),
            _UsageSummaryCard(summary: usageSummary!),
          ],
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Passa a Premium',
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  const Text(
                    'Sblocca strumenti IA avanzati, elaborazioni più complesse '
                    'e opzioni aggiuntive. I dettagli del piano saranno mostrati '
                    'prima dell’acquisto.',
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: premium ? null : onUpgrade,
                    icon: const Icon(Icons.auto_awesome),
                    label: Text(premium ? 'Premium attivo' : 'Scopri Premium'),
                  ),
                  TextButton(
                    onPressed: onRestore,
                    child: const Text('Ripristina acquisti'),
                  ),
                ],
              ),
            ),
          ),
          if (signedIn) ...[
            const SizedBox(height: 12),
            _FamilyManagementCard(
              apiBaseUrl: apiBaseUrl,
              widget.canCreateFamily: entitlement?.plan == 'family',
            ),
          ],
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Invita un amico',
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  const Text(
                    'Quando un nuovo utente usa il tuo codice e il server '
                    'conferma l’idoneità, entrambi possono ricevere un mese '
                    'di Premium secondo le condizioni del programma.',
                  ),
                  if (referralCode != null) ...[
                    const SizedBox(height: 12),
                    SelectableText(
                      referralCode!,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: onShareReferral,
                        icon: const Icon(Icons.share),
                        label: const Text('Condividi codice'),
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  _ReferralRedeem(onRedeem: onRedeemReferral),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReferralRedeem extends StatefulWidget {
  const _ReferralRedeem({required this.onRedeem});

  final ValueChanged<String> onRedeem;

  @override
  State<_ReferralRedeem> createState() => _ReferralRedeemState();
}

class _ReferralRedeemState extends State<_ReferralRedeem> {
  final controller = TextEditingController();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Codice invito',
                hintText: 'ABC123XY',
              ),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: () {
              final code = controller.text.trim();
              if (code.isNotEmpty) widget.onRedeem(code);
            },
            child: const Text('Riscatta'),
          ),
        ],
      );
}


class _UsageSummaryCard extends StatelessWidget {
  const _UsageSummaryCard({required this.summary});

  final Map<String, dynamic> summary;

  @override
  Widget build(BuildContext context) {
    final used = summary['used'];
    final limit = summary['limit'];
    final remaining = summary['remaining'];
    final period = summary['period'];
    if (used is! int || limit is! int || remaining is! int || period is! String) {
      return const SizedBox.shrink();
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Utilizzo IA mensile',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text('$used di $limit elaborazioni · $remaining rimanenti'),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: limit == 0 ? 0 : (used / limit).clamp(0.0, 1.0).toDouble(),
            ),
            const SizedBox(height: 6),
            Text('Periodo: $period',
                style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}


class _FamilyManagementCard extends StatefulWidget {
  const _FamilyManagementCard({required this.apiBaseUrl, required this.widget.canCreateFamily});
  final String apiBaseUrl;
  final bool widget.canCreateFamily;
  @override
  State<_FamilyManagementCard> createState() => _FamilyManagementCardState();
}
class _FamilyManagementCardState extends State<_FamilyManagementCard> {
  final _invite = TextEditingController();
  Map<String, dynamic>? _family;
  List<dynamic> _invitations = [];
  String? _createdToken;
  String? _error;
  bool _busy = false;
  bool _loading = true;
  Future<T> _api<T>(Future<T> Function(RemoteAccountApi api) run) async {
    final token = await const AccountSessionStore().readToken();
    if (token == null || token.isEmpty || widget.apiBaseUrl.trim().isEmpty) {
      throw const AccountApiException(401, 'Accedi per gestire la famiglia.');
    }
    final api = RemoteAccountApi(baseUri: Uri.parse(widget.apiBaseUrl.trim()), bearerToken: token);
    try { return await run(api); } finally { api.close(); }
  }
  @override
  void initState() { super.initState(); _refresh(); }
  @override
  void dispose() { _invite.dispose(); super.dispose(); }
  Future<void> _refresh() async {
    try {
      final family = await _api((api) => api.request('GET', '/v1/account/family'));
      var invitations = <dynamic>[];
      if (family['isOwner'] == true) {
        final result = await _api((api) => api.request('GET', '/v1/account/family/invitations'));
        invitations = result['invitations'] is List ? result['invitations'] as List : [];
      }
      if (mounted) setState(() { _family = family; _invitations = invitations; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e is AccountApiException ? e.message : 'Famiglia non disponibile.'; _loading = false; });
    }
  }
  Future<void> _action(Future<void> Function() run) async {
    if (_busy) return;
    setState(() { _busy = true; _error = null; });
    try { await run(); await _refresh(); }
    catch (e) { if (mounted) setState(() => _error = e is AccountApiException ? e.message : 'Operazione non riuscita.'); }
    finally { if (mounted) setState(() => _busy = false); }
  }
  @override
  Widget build(BuildContext context) {
    final family = _family;
    final members = family?['members'] is List ? family!['members'] as List : const [];
    final owner = family?['isOwner'] == true;
    final hasFamily = family?['familyId'] is String;
    return Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(
      crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Premium famiglia', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 6),
        const Text('Invita familiari, controlla i posti e gestisci gli accessi condivisi.'),
        if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        if (_loading) const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Center(child: CircularProgressIndicator())),
        if (!_loading && !hasFamily) ...[
          Text(widget.canCreateFamily
              ? 'Il tuo piano famiglia è attivo. Crea il gruppo e genera il primo invito.'
              : 'Non fai ancora parte di una famiglia Premium. Per crearla serve un piano famiglia attivo.'),
          if (widget.canCreateFamily) ...[
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _busy ? null : () => _action(() async {
                final result = await _api((api) => api.request('POST', '/v1/account/family/invitations'));
                if (mounted) setState(() => _createdToken = result['token'] as String?);
              }),
              icon: const Icon(Icons.group_add_outlined),
              label: const Text('Crea famiglia e primo invito'),
            ),
          ],
        ],
        if (hasFamily) ...[
          Text(members.length.toString() + ' di ' + (family?['seatLimit'] ?? '?').toString() + ' posti occupati'),
          ...members.map((m) {
            final id = m is Map ? m['user_id']?.toString() ?? '' : '';
            final isOwner = id == family?['ownerUserId'];
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(isOwner ? Icons.workspace_premium : Icons.person_outline),
              title: Text(isOwner ? 'Titolare' : 'Membro famiglia'),
              subtitle: SelectableText(id),
              trailing: owner && !isOwner ? IconButton(
                tooltip: 'Rimuovi membro',
                onPressed: _busy ? null : () => _action(() async {
                  await _api((api) => api.request('DELETE', '/v1/account/family/members/' + id));
                }),
                icon: const Icon(Icons.person_remove_outlined),
              ) : null,
            );
          }),
          if (owner) ...[
            FilledButton.icon(
              onPressed: _busy ? null : () => _action(() async {
                final result = await _api((api) => api.request('POST', '/v1/account/family/invitations'));
                if (mounted) setState(() => _createdToken = result['token'] as String?);
              }),
              icon: const Icon(Icons.person_add_alt), label: const Text('Crea invito'),
            ),
            if (_createdToken != null) ...[
              const Text('Codice da condividere:'),
              SelectableText(_createdToken!),
              TextButton.icon(
                onPressed: () => Clipboard.setData(ClipboardData(text: _createdToken!)),
                icon: const Icon(Icons.copy), label: const Text('Copia codice'),
              ),
            ],
            if (_invitations.isNotEmpty) ...[
              const Divider(), const Text('Inviti emessi'),
              ..._invitations.whereType<Map>().map((i) {
                final id = i['invitation_id']?.toString() ?? '';
                final accepted = i['accepted_at'] != null;
                final revoked = i['revoked_at'] != null;
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(accepted ? 'Accettato' : revoked ? 'Revocato' : 'In attesa'),
                  subtitle: Text('Scadenza: ' + (i['expires_at'] ?? '—').toString()),
                  trailing: !accepted && !revoked ? IconButton(
                    tooltip: 'Revoca invito',
                    onPressed: _busy ? null : () => _action(() async {
                      await _api((api) => api.request('DELETE', '/v1/account/family/invitations/' + id));
                    }),
                    icon: const Icon(Icons.link_off),
                  ) : null,
                );
              }),
            ],
          ] else
            TextButton.icon(
              onPressed: _busy ? null : () => _action(() async {
                await _api((api) => api.request('POST', '/v1/account/family/leave'));
              }),
              icon: const Icon(Icons.logout), label: const Text('Esci dalla famiglia'),
            ),
        ],
        const Divider(),
        TextField(controller: _invite, decoration: const InputDecoration(labelText: 'Codice invito ricevuto')),
        TextButton(
          onPressed: _busy ? null : () => _action(() async {
            final code = _invite.text.trim();
            if (code.isEmpty) return;
            await _api((api) => api.request('POST', '/v1/account/family/invitations/accept', body: {'token': code}));
            _invite.clear();
            if (mounted) setState(() => _createdToken = null);
          }),
          child: const Text('Accetta invito'),
        ),
      ],
    )));
  }
}
