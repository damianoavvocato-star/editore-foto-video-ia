import 'package:editore_foto_video_ia/account/account_premium_screen.dart';
import 'package:editore_foto_video_ia/models/account_entitlement.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('family plan owner can start family creation without an existing group',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AccountPremiumScreen(
          userId: 'owner-1',
          entitlement: const UserEntitlement(
            userId: 'owner-1',
            tier: SubscriptionTier.premium,
            plan: 'family',
          ),
          referralCode: null,
          apiBaseUrl: '',
          onSignIn: _noop,
          onUpgrade: _noop,
          onRestore: _noop,
          onShareReferral: _noop,
          onRedeemReferral: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Crea famiglia e primo invito'), findsOneWidget);
    expect(find.textContaining('Il tuo piano famiglia è attivo'), findsOneWidget);
  });

  testWidgets('individual plan does not show family creation action',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AccountPremiumScreen(
          userId: 'user-1',
          entitlement: const UserEntitlement(
            userId: 'user-1',
            tier: SubscriptionTier.premium,
            plan: 'premium',
          ),
          referralCode: null,
          apiBaseUrl: '',
          onSignIn: _noop,
          onUpgrade: _noop,
          onRestore: _noop,
          onShareReferral: _noop,
          onRedeemReferral: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Crea famiglia e primo invito'), findsNothing);
  });
}

void _noop() {}
