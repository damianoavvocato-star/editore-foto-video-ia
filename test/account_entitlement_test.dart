import 'package:flutter_test/flutter_test.dart';
import 'package:editore_foto_video_ia/models/account_entitlement.dart';

void main() {
  test('referral claim normalizes and validates code', () {
    const claim = ReferralClaim(referralCode: 'ab12cd34', inviteeUserId: 'user-9');
    expect(claim.validate, returnsNormally);
  });

  test('referral claim rejects malformed code', () {
    const claim = ReferralClaim(referralCode: 'bad!', inviteeUserId: 'user-9');
    expect(claim.validate, throwsA(isA<FormatException>()));
  });

  test('Premium plan metadata round trips from the account API', () {
    final entitlement = UserEntitlement.fromJson({
      'userId': 'user-2',
      'tier': 'premium',
      'isPremium': true,
      'plan': 'family',
      'validUntil': '2027-01-01T00:00:00Z',
      'source': 'promotion',
    });
    expect(entitlement.plan, 'family');
    expect(entitlement.source, EntitlementSource.promotion);
    expect(entitlement.toJson()['plan'], 'family');
  });

  test('unknown Premium plan metadata is rejected', () {
    expect(
      () => UserEntitlement.fromJson({
        'userId': 'user-3',
        'tier': 'premium',
        'plan': 'enterprise',
      }),
      throwsA(isA<FormatException>()),
    );
  });

  test('expired premium entitlement is not active', () {
    final entitlement = UserEntitlement(
      userId: 'user-1',
      tier: SubscriptionTier.premium,
      validUntil: DateTime.utc(2020),
      source: EntitlementSource.referralReward,
    );
    expect(entitlement.isPremium, isFalse);
  });
}
