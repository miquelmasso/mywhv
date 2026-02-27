import 'dart:async';

import 'package:hive_flutter/hive_flutter.dart';

/// Simple local model for offline restaurants.
class RestaurantLocal {
  RestaurantLocal({
    required this.id,
    required this.name,
    required this.city,
    required this.latitude,
    required this.longitude,
    this.email,
    this.facebookUrl,
    this.instagramUrl,
    this.website,
  });

  final String id;
  final String name;
  final String city;
  final double latitude;
  final double longitude;
  final String? email;
  final String? facebookUrl;
  final String? instagramUrl;
  final String? website;

  bool get hasContact =>
      (email ?? '').isNotEmpty ||
      (facebookUrl ?? '').isNotEmpty ||
      (instagramUrl ?? '').isNotEmpty ||
      (website ?? '').isNotEmpty;

  Map<String, dynamic> toJson() => {
        'id': id,
        'docId': id,
        'name': name,
        'city': city,
        'latitude': latitude,
        'longitude': longitude,
        'email': email,
        'facebook_url': facebookUrl,
        'instagram_url': instagramUrl,
        'website': website,
      };

  factory RestaurantLocal.fromJson(Map<String, dynamic> map) {
    return RestaurantLocal(
      id: (map['id'] ?? map['docId'] ?? '').toString(),
      name: (map['name'] ?? '').toString(),
      city: (map['city'] ?? '').toString(),
      latitude: (map['latitude'] ?? map['lat'] ?? 0).toDouble(),
      longitude: (map['longitude'] ?? map['lng'] ?? 0).toDouble(),
      email: (map['email'] ?? map['mail'])?.toString(),
      facebookUrl: (map['facebook_url'] ?? map['facebook'])?.toString(),
      instagramUrl: (map['instagram_url'] ?? map['instagram'])?.toString(),
      website: (map['website'] ?? map['careers_page'])?.toString(),
    );
  }
}

class RestaurantLocalStore {
  RestaurantLocalStore._();
  static final RestaurantLocalStore instance = RestaurantLocalStore._();

  static const _boxName = 'restaurants_box';
  bool _isInitialized = false;

  Future<void> init() async {
    if (_isInitialized) return;
    await Hive.initFlutter();
    if (!Hive.isBoxOpen(_boxName)) {
      await Hive.openBox<Map>(_boxName);
    }
    _isInitialized = true;
  }

  Future<void> clear() async {
    final box = Hive.box<Map>(_boxName);
    await box.clear();
  }

  Future<void> saveAll(List<RestaurantLocal> restaurants) async {
    final box = Hive.box<Map>(_boxName);
    final entries = <String, Map<String, dynamic>>{};
    for (final r in restaurants) {
      entries[r.id] = r.toJson();
    }
    await box.putAll(entries);
  }

  Future<List<Map<String, dynamic>>> getAll() async {
    final box = Hive.box<Map>(_boxName);
    return box.values
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  bool get hasData {
    if (!Hive.isBoxOpen(_boxName)) return false;
    final box = Hive.box<Map>(_boxName);
    return box.isNotEmpty;
  }
}
