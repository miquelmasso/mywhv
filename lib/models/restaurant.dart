class Restaurant {
  final String name;
  final String city;
  final double latitude;
  final double longitude;

  Restaurant({
    required this.name,
    required this.city,
    required this.latitude,
    required this.longitude,
  });

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'city': city,
      'latitude': latitude,
      'longitude': longitude,
    };
  }

  factory Restaurant.fromMap(Map<String, dynamic> map) {
    return Restaurant(
      name: map['name'] ?? '',
      city: map['city'] ?? '',
      latitude: (map['latitude'] ?? 0).toDouble(),
      longitude: (map['longitude'] ?? 0).toDouble(),
    );
  }
}
