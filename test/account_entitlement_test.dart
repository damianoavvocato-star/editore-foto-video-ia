import 'package:flutter_test/flutter_test.dart';
import 'package:editore_foto_video_ia/models/account_entitlement.dart';

void main() {
  test('referral claim normalizes and validates code', () {
    const claim = ReferralClaim(referralCode: 'ab12cd34', inviteeUserId: 'user-9');
    expect(claim.validate, returnsNormally);
    expect(claim.normalizedReferralCode, 'AB12CD34');
  });

  test('referral claim rejects non-ASCII codes and invalid invitee IDs', () {
    const unicodeCode = ReferralClaim(
      referralCode: 'ÀB12CD34',
      inviteeUserId: 'user-9',
    );
    expect(unicodeCode.validate, throwsA(isA<FormatException>()));

    const emptyInvitee = ReferralClaim(
      referralCode: 'AB12CD34',
      inviteeUserId: '   ',
    );
    expect(emptyInvitee.validate, throwsA(isA<ArgumentError>()));

    final oversizedInvitee = ReferralClaim(
      referralCode: 'AB12CD34',
      inviteeUserId: 'u' * 129,
    );
    expect(oversizedInvitee.validate, throwsA(isA<ArgumentError>()));
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

  test('malformed account entitlement fields return format errors', () {
    expect(
      () => UserEntitlement.fromJson({'userId': 'u', 'tier': 'enterprise'}),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => UserEntitlement.fromJson({'userId': 'u', 'tier': 'free', 'source': 42}),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => UserEntitlement.fromJson({'userId': 'u', 'tier': 'free', 'validUntil': 42}),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => UserEntitlement.fromJson({'userId': '  ', 'tier': 'free'}),
      throwsA(isA<FormatException>()),
    );
  });

  test('malformed expiry timestamp is rejected as a format error', () {
    expect(
      () => UserEntitlement.fromJson({
        'userId': 'user-invalid-date',
        'tier': 'premium',
        'validUntil': 'not-a-date',
      }),
      throwsA(isA<FormatException>()),
    );
  });

  test('Premium entitlement expires exactly at its validity boundary', () {
    final boundary = DateTime.utc(2027, 1, 1);
    final entitlement = UserEntitlement(
      userId: 'user-boundary',
      tier: SubscriptionTier.premium,
      validUntil: boundary,
    );
    expect(entitlement.isPremiumAt(boundary.subtract(const Duration(microseconds: 1))), isTrue);
    expect(entitlement.isPremiumAt(boundary), isFalse);
    expect(entitlement.isPremiumAt(boundary.add(const Duration(microseconds: 1))), isFalse);
  });

  test('free entitlement never becomes Premium regardless of expiry', () {
    final entitlement = UserEntitlement(
      userId: 'user-free',
      tier: SubscriptionTier.free,
      validUntil: DateTime.utc(2099),
    );
    expect(entitlement.isPremiumAt(DateTime.utc(2026)), isFalse);
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
