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
    final userId = json['userId'];
    if (userId is! String || userId.trim().isEmpty) {
      throw const FormatException('ID utente mancante o non valido.');
    }
    final rawTier = json['tier'];
    final tier = SubscriptionTier.values.where((value) => value.name == rawTier);
    if (rawTier is! String || tier.isEmpty) {
      throw const FormatException('Livello account non valido.');
    }

    final rawExpiry = json['validUntil'];
    DateTime? validUntil;
    if (rawExpiry != null) {
      if (rawExpiry is! String) {
        throw const FormatException('Scadenza Premium non valida.');
      }
      validUntil = DateTime.parse(rawExpiry).toUtc();
    }

    final rawSource = json['source'];
    EntitlementSource? source;
    if (rawSource != null) {
      if (rawSource is! String) {
        throw const FormatException('Origine del diritto non valida.');
      }
      final matches = EntitlementSource.values.where((value) => value.name == rawSource);
      if (matches.isEmpty) {
        throw const FormatException('Origine del diritto sconosciuta.');
      }
      source = matches.first;
    }

    return UserEntitlement(
      userId: userId.trim(),
      tier: tier.first,
      validUntil: validUntil,
      source: source,
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

  String get normalizedReferralCode => referralCode.trim().toUpperCase();

  void validate() {
    if (!RegExp(r'^[A-Z0-9]{6,12}
}
).hasMatch(normalizedReferralCode)) {
      throw const FormatException('Codice invito non valido.');
    }
    final inviteeId = inviteeUserId.trim();
    if (inviteeId.isEmpty || inviteeId.length > 128) {
      throw ArgumentError('L’ID dell’utente invitato non è valido.');
    }
  }
}
