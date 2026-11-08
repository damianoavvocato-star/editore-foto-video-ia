import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:editore_foto_video_ia/account/account_security_screen.dart';

void main() {
  testWidgets('account security screen explains backend configuration when unset',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: AccountSecurityScreen(apiBaseUrl: ''),
      ),
    ));

    expect(find.textContaining('Configura MEDIA_API_URL'), findsOneWidget);
  });
}
