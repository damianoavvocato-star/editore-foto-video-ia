import 'package:editore_foto_video_ia/account/account_premium_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows referral history status and reward eligibility',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AccountPremiumScreen(
          userId: null,
          entitlement: null,
          referralCode: 'AB12CD34EF',
          referralClaims: [
            {
              'role': 'inviter',
              'status': 'pending',
              'eligibleAt': 1799990000,
            },
            {
              'role': 'invitee',
              'status': 'rewarded',
              'eligibleAt': 1790000000,
            },
            {
              'role': 'inviter',
              'status': 'rejected',
              'eligibleAt': 1780000000,
            },
          ],
          onSignIn: _noop,
          onUpgrade: _noop,
          onRestore: _noop,
          onShareReferral: _noop,
          onRedeemReferral: (_) {},
        ),
      ),
    );

    expect(find.text('Storico inviti'), findsOneWidget);
    expect(find.text('Invitato da te'), findsNWidgets(2));
    expect(find.text('Hai utilizzato un invito'), findsOneWidget);
    expect(find.textContaining('In verifica · premio dopo 7 giorni'), findsOneWidget);
    expect(find.textContaining('Premio assegnato · 30 giorni Premium'), findsOneWidget);
    expect(find.textContaining('Non idoneo al premio'), findsOneWidget);
  });
}

void _noop() {}
