import 'package:flutter/material.dart';

import '../models/account_entitlement.dart';

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
