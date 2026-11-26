import 'package:editore_foto_video_ia/account/account_premium_screen.dart';
import 'package:editore_foto_video_ia/models/account_entitlement.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _secureStorageChannel =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorageChannel, (call) async => null);
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorageChannel, null);
  });
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
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

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
