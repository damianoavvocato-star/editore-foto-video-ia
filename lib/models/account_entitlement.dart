enum SubscriptionTier { free, premium }

enum EntitlementSource { subscription, referralReward, promotion }

class UserEntitlement {
  const UserEntitlement({
    required this.userId,
    this.tier = SubscriptionTier.free,
    this.validUntil,
    this.source,
  });

  final String userId;
  final SubscriptionTier tier;
  final DateTime? validUntil;
  final EntitlementSource? source;

  bool get isPremium {
    if (tier != SubscriptionTier.premium) return false;
    return validUntil == null || validUntil!.isAfter(DateTime.now());
  }

  Map<String, Object?> toJson() => {
        'userId': userId,
        'tier': tier.name,
        'validUntil': validUntil?.toUtc().toIso8601String(),
        'source': source?.name,
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
    );
  }
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
