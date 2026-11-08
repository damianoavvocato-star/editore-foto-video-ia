import 'package:editore_foto_video_ia/account/account_premium_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows monthly quota and reached-limit warning', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AccountPremiumScreen(
          userId: 'user-1',
          entitlement: null,
          referralCode: null,
          usageSummary: const {
            'used': 20,
            'limit': 20,
            'remaining': 0,
            'period': '2026-11',
            'exhausted': true,
          },
          onSignIn: _noop,
          onUpgrade: _noop,
          onRestore: _noop,
          onShareReferral: _noop,
          onRedeemReferral: (_) {},
        ),
      ),
    );

    expect(find.text('Utilizzo IA mensile'), findsOneWidget);
    expect(find.text('20 di 20 elaborazioni · 0 rimanenti'), findsOneWidget);
    expect(find.textContaining('Limite mensile raggiunto'), findsOneWidget);
  });
}

void _noop() {}
