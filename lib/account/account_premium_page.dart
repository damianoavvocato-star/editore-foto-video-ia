import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'account_premium_screen.dart';
import '../models/account_entitlement.dart';
import '../services/account_api.dart';

/// Connects the Premium presentation to the authenticated server entitlement.
/// Billing stays explicitly unavailable until a payment provider is integrated;
/// referral rewards are issued only by the authenticated server.
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
  late Future<({String? userId, UserEntitlement? entitlement, String? referralCode, Map<String, dynamic>? usageSummary, int? creditBalance})> _load;

  @override
  void initState() {
    super.initState();
    _load = _loadEntitlement();
  }

  Future<({String? userId, UserEntitlement? entitlement, String? referralCode, Map<String, dynamic>? usageSummary, int? creditBalance})>
      _loadEntitlement() async {
    final baseUrl = widget.apiBaseUrl.trim();
    if (baseUrl.isEmpty) return (userId: null, entitlement: null, referralCode: null, usageSummary: null, creditBalance: null);

    final token = await const AccountSessionStore().readToken();
    if (token == null || token.isEmpty) {
      return (userId: null, entitlement: null, referralCode: null, usageSummary: null, creditBalance: null);
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
      String? referralCode;
      Map<String, dynamic>? usageSummary;
      int? creditBalance;
      try {
        final credits = await api.request('GET', '/v1/account/credits');
        final balance = credits['balance'];
        if (balance is Map<String, dynamic> && balance['balance'] is int) {
          creditBalance = balance['balance'] as int;
        }
      } on AccountApiException {
        // Credit ledger can be unavailable independently of the Premium status.
      }
      try {
        usageSummary = await api.request('GET', '/v1/account/usage');
      } on AccountApiException {
        // Do not block Premium status if quota telemetry is temporarily unavailable.
      }
      try {
        final referral = await api.request('GET', '/v1/account/referrals');
        referralCode = referral['code'] as String?;
      } on AccountApiException {
        // Entitlement remains usable if the referral endpoint is temporarily unavailable.
      }
      return (userId: userId, entitlement: entitlement, referralCode: referralCode, usageSummary: usageSummary, creditBalance: creditBalance);
    } finally {
      api.close();
    }
  }

  Future<void> _shareReferral(String? code) async {
    if (code == null || code.isEmpty) {
      _notice('Il codice invito non è disponibile.');
      return;
    }
    await Clipboard.setData(ClipboardData(text: code));
    _notice('Codice invito copiato.');
  }

  Future<void> _redeemReferral(String code) async {
    final token = await const AccountSessionStore().readToken();
    if (token == null || token.isEmpty || widget.apiBaseUrl.trim().isEmpty) {
      _notice('Accedi e configura il server per riscattare un invito.');
      return;
    }
    final api = RemoteAccountApi(
      baseUri: Uri.parse(widget.apiBaseUrl.trim()),
      bearerToken: token,
    );
    try {
      final result = await api.request(
        'POST',
        '/v1/account/referrals/claim',
        body: {'code': code.trim().toUpperCase()},
      );
      final eligibleAt = result['eligibleAt'];
      _notice(eligibleAt is int
          ? 'Invito registrato. Entrambi riceverete 30 giorni Premium dopo 7 giorni di verifica.'
          : 'Invito registrato e in verifica.');
      if (mounted) setState(() => _load = _loadEntitlement());
    } on AccountApiException catch (error) {
      _notice(error.message);
    } catch (_) {
      _notice('Impossibile riscattare il codice. Riprova.');
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
    return FutureBuilder<({String? userId, UserEntitlement? entitlement, String? referralCode, Map<String, dynamic>? usageSummary, int? creditBalance})>(
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
          referralCode: data.referralCode,
          usageSummary: data.usageSummary,
          creditBalance: data.creditBalance,
          onSignIn: widget.onSignIn,
          onUpgrade: () => _notice(
            'Acquisti Premium non ancora attivi: il sistema di pagamento '
            'non è stato collegato.',
          ),
          onRestore: () => _notice(
            'Ripristino acquisti non disponibile finché non viene collegato '
            'il sistema di pagamento.',
          ),
          onShareReferral: () => _shareReferral(data.referralCode),
          onRedeemReferral: _redeemReferral,
        );
      },
    );
  }
}
