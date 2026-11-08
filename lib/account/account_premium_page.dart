import 'package:flutter/material.dart';

import 'account_premium_screen.dart';
import '../models/account_entitlement.dart';
import '../services/account_api.dart';

/// Connects the Premium presentation to the authenticated server entitlement.
/// Billing and referrals stay explicitly unavailable until their providers and
/// server workflows are implemented; the client never grants Premium itself.
class AccountPremiumPage extends StatefulWidget {
  const AccountPremiumPage({
    super.key,
    required this.apiBaseUrl,
    required this.onSignIn,
  });

  final String apiBaseUrl;
  final VoidCallback onSignIn;

  @override
  State<AccountPremiumPage> createState() => _AccountPremiumPageState();
}

class _AccountPremiumPageState extends State<AccountPremiumPage> {
  late Future<({String? userId, UserEntitlement? entitlement})> _load;

  @override
  void initState() {
    super.initState();
    _load = _loadEntitlement();
  }

  Future<({String? userId, UserEntitlement? entitlement})>
      _loadEntitlement() async {
    final baseUrl = widget.apiBaseUrl.trim();
    if (baseUrl.isEmpty) return (userId: null, entitlement: null);

    final token = await const AccountSessionStore().readToken();
    if (token == null || token.isEmpty) {
      return (userId: null, entitlement: null);
    }

    final api = RemoteAccountApi(
      baseUri: Uri.parse(baseUrl),
      bearerToken: token,
    );
    try {
      final accountResponse = await api.request('GET', '/v1/auth/me');
      final account = accountResponse['user'];
      if (account is! Map<String, dynamic> ||
          account['userId'] is! String ||
          (account['userId'] as String).isEmpty) {
        throw const FormatException('Profilo account non valido.');
      }
      final userId = account['userId'] as String;
      final response = await api.request('GET', '/v1/account/entitlement');
      final validUntilValue = response['validUntil'];
      final sourceValue = response['source'];
      final source = sourceValue == 'promotion'
          ? EntitlementSource.promotion
          : sourceValue == 'subscription'
              ? EntitlementSource.subscription
              : sourceValue == 'referralReward'
                  ? EntitlementSource.referralReward
                  : null;
      final entitlement = UserEntitlement(
        userId: userId,
        tier: response['tier'] == 'premium'
            ? SubscriptionTier.premium
            : SubscriptionTier.free,
        plan: response['plan'] as String?,
        validUntil: validUntilValue is String
            ? DateTime.parse(validUntilValue).toUtc()
            : null,
        source: source,
      );
      return (userId: userId, entitlement: entitlement);
    } finally {
      api.close();
    }
  }

  void _notice(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<({String? userId, UserEntitlement? entitlement})>(
      future: _load,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Scaffold(
            appBar: AppBar(title: const Text('Account e Premium')),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.cloud_off_outlined, size: 40),
                    const SizedBox(height: 12),
                    const Text(
                      'Non è stato possibile verificare il piano sul server. '
                      'Riprova quando la connessione è disponibile.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: () => setState(() {
                        _load = _loadEntitlement();
                      }),
                      child: const Text('Riprova'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final data = snapshot.data!;
        return AccountPremiumScreen(
          userId: data.userId,
          entitlement: data.entitlement,
          referralCode: null,
          onSignIn: widget.onSignIn,
          onUpgrade: () => _notice(
            'Acquisti Premium non ancora attivi: il sistema di pagamento '
            'non è stato collegato.',
          ),
          onRestore: () => _notice(
            'Ripristino acquisti non disponibile finché non viene collegato '
            'il sistema di pagamento.',
          ),
          onShareReferral: () => _notice(
            'Il programma inviti sarà disponibile dopo l’attivazione '
            'del servizio referral.',
          ),
          onRedeemReferral: (_) => _notice(
            'Il riscatto dei codici invito non è ancora attivo sul server.',
          ),
        );
      },
    );
  }
}
