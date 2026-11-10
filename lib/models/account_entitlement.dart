enum SubscriptionTier { free, premium }

enum EntitlementSource { subscription, referralReward, promotion }

class UserEntitlement {
  const UserEntitlement({
    required this.userId,
    this.tier = SubscriptionTier.free,
    this.validUntil,
    this.source,
    this.plan,
  });

  final String userId;
  final SubscriptionTier tier;
  final DateTime? validUntil;
  final EntitlementSource? source;
  final String? plan;

  bool get isPremium => isPremiumAt(DateTime.now());

  /// Evaluates the entitlement against an explicit instant.
  ///
  /// This keeps expiry checks deterministic for callers and tests while the
  /// server remains the authority that grants or revokes Premium access.
  bool isPremiumAt(DateTime instant) {
    if (tier != SubscriptionTier.premium) return false;
    return validUntil == null || validUntil!.isAfter(instant);
  }

  Map<String, Object?> toJson() => {
        'userId': userId,
        'tier': tier.name,
        'validUntil': validUntil?.toUtc().toIso8601String(),
        'source': source?.name,
        'plan': plan,
      };

  factory UserEntitlement.fromJson(Map<String, Object?> json) {
    return UserEntitlement(
      userId: json['userId'] as String,
      tier: SubscriptionTier.values.byName(json['tier'] as String),
      validUntil: json['validUntil'] == null
          ? null
          : DateTime.parse(json['validUntil'] as String).toUtc(),
      source: json['source'] == null
          ? null
          : EntitlementSource.values.byName(json['source'] as String),
      plan: json['plan'] == null ? null : _validatedPlan(json['plan']),
    );
  }
}

String _validatedPlan(Object? value) {
  if (value is! String || !const {'premium', 'family'}.contains(value)) {
    throw const FormatException('Piano Premium non valido.');
  }
  return value;
}

class ReferralClaim {
  const ReferralClaim({
    required this.referralCode,
    required this.inviteeUserId,
  });

  final String referralCode;
  final String inviteeUserId;

  void validate() {
    final code = referralCode.trim().toUpperCase();
    if (!RegExp(r'^[A-Z0-9]{6,12}$').hasMatch(code)) {
      throw const FormatException('Codice invito non valido.');
    }
    if (inviteeUserId.trim().isEmpty) {
      throw ArgumentError('L’ID dell’utente invitato è obbligatorio.');
    }
  }
}
