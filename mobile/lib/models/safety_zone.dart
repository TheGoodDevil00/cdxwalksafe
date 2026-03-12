enum SafetyLevel { risky, cautious, safe }

class SafetyZone {
  const SafetyZone({
    required this.id,
    required this.latitude,
    required this.longitude,
    required this.safetyScore,
    this.radiusMeters = 120,
    this.classification,
  });

  final String id;
  final double latitude;
  final double longitude;
  final double safetyScore;
  final double radiusMeters;
  final String? classification;

  factory SafetyZone.fromJson(Map<String, dynamic> json) {
    double parseDouble(Object? value, {double fallback = 0}) {
      if (value is num) {
        return value.toDouble();
      }
      if (value is String) {
        return double.tryParse(value) ?? fallback;
      }
      return fallback;
    }

    return SafetyZone(
      id: '${json['id'] ?? ''}',
      latitude: parseDouble(json['lat'] ?? json['latitude']),
      longitude: parseDouble(json['lon'] ?? json['longitude']),
      safetyScore: parseDouble(json['score'] ?? json['safetyScore']),
      radiusMeters: parseDouble(
        json['radius_meters'] ?? json['radiusMeters'],
        fallback: 120,
      ),
      classification: json['classification']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'lat': latitude,
      'lon': longitude,
      'score': safetyScore,
      'radius_meters': radiusMeters,
      'classification': classification,
    };
  }

  // Converts a numeric score into one of three safety classes.
  SafetyLevel get safetyLevel {
    final String normalized = (classification ?? '').toUpperCase();
    if (normalized == 'SAFE') {
      return SafetyLevel.safe;
    }
    if (normalized == 'CAUTIOUS') {
      return SafetyLevel.cautious;
    }
    if (normalized == 'RISKY') {
      return SafetyLevel.risky;
    }

    if (safetyScore < 40) {
      return SafetyLevel.risky;
    }
    if (safetyScore < 70) {
      return SafetyLevel.cautious;
    }
    return SafetyLevel.safe;
  }
}
