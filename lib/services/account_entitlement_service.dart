import '../models/account_entitlement.dart';

/// Server-backed contract. Client-side code must never grant Premium itself.
/// The server should atomically enforce one claim per invitee, inviter != invitee,
/// referral attribution, abuse checks and reward eligibility.
abstract interface class AccountEntitlementBackend {
  Future<UserEntitlement> fetchEntitlement(String userId);
  Future<void> submitReferralClaim(ReferralClaim claim);
  Future<String> createReferralCode(String userId);
  Future<void> restorePurchases(String userId);
}

class AccountEntitlementService {
  const AccountEntitlementService(this.backend);

  final AccountEntitlementBackend backend;

  Future<UserEntitlement> refresh(String userId) {
    if (userId.trim().isEmpty) {
      throw ArgumentError('L’ID utente è obbligatorio.');
    }
    return backend.fetchEntitlement(userId);
  }

  Future<void> claimReferral({
    required String code,
    required String inviteeUserId,
  }) async {
    final claim = ReferralClaim(
      referralCode: code.trim().toUpperCase(),
      inviteeUserId: inviteeUserId,
    );
    claim.validate();
    await backend.submitReferralClaim(claim);
  }

  Future<String> referralCodeFor(String userId) {
    if (userId.trim().isEmpty) {
      throw ArgumentError('L’ID utente è obbligatorio.');
    }
    return backend.createReferralCode(userId);
  }

  Future<void> restore(String userId) {
    if (userId.trim().isEmpty) {
      throw ArgumentError('L’ID utente è obbligatorio.');
    }
    return backend.restorePurchases(userId);
  }
}
