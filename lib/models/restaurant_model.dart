class Restaurant {
  final String id;
  final String name;
  final String city;
  final String phone;
  final double lat;
  final double lng;

  Restaurant({
    required this.id,
    required this.name,
    required this.city,
    required this.phone,
    required this.lat,
    required this.lng,
  });

  factory Restaurant.fromMap(String id, Map<String, dynamic> data) {
    return Restaurant(
      id: id,
      name: data['name']?.toString() ?? '',
      city: data['city']?.toString() ?? '',
      phone: data['phone']?.toString() ?? '',
      lat: (data['lat'] is int)
          ? (data['lat'] as int).toDouble()
          : (data['lat'] ?? 0.0).toDouble(),
      lng: (data['lng'] is int)
          ? (data['lng'] as int).toDouble()
          : (data['lng'] ?? 0.0).toDouble(),
    );
  }
}
