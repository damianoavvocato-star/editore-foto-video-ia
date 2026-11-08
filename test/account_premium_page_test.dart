import 'package:editore_foto_video_ia/account/account_premium_page.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';

void main() {
  testWidgets('shows signed-out state when API configuration is absent',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: AccountPremiumPage(
          apiBaseUrl: '',
          onSignIn: _noop,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Usa il tuo account'), findsOneWidget);
    expect(find.text('Piano gratuito'), findsOneWidget);
    expect(find.text('Scopri Premium'), findsOneWidget);
    expect(find.text('Condividi codice'), findsNothing);
  });

  testWidgets('does not claim that billing is active', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: AccountPremiumPage(
          apiBaseUrl: '',
          onSignIn: _noop,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Scopri Premium'));
    await tester.pump();

    expect(
      find.textContaining('Acquisti Premium non ancora attivi'),
      findsOneWidget,
    );
  });
}

void _noop() {}
