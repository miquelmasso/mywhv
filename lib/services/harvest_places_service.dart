import 'package:flutter/foundation.dart';

import 'harvest_places_sqlite_store.dart';

class HarvestPlace {
  final String id;
  final String name;
  final String postcode;
  final String state;
  final double latitude;
  final double longitude;
  final String? description;

  HarvestPlace({
    required this.id,
    required this.name,
    required this.postcode,
    required this.state,
    required this.latitude,
    required this.longitude,
    this.description,
  });
}

class HarvestPlacesService {
  static Future<List<HarvestPlace>> loadHarvestPlaces({
    required bool fromServer,
  }) async {
    if (fromServer) {
      debugPrint(
        'ℹ️ loadHarvestPlaces(fromServer: true) ignored: local SQLite mode',
      );
    }
    final store = HarvestPlacesSqliteStore.instance;
    await store.init();
    final places = await store.getAll();
    debugPrint('🗄️ SQLITE harvest loaded: ${places.length}');
    return places
        .map((data) {
          final lat = (data['latitude'] ?? data['lat'])?.toDouble();
          final lng = (data['longitude'] ?? data['lng'])?.toDouble();
          if (lat == null || lng == null) return null;
          return HarvestPlace(
            id: (data['id'] ?? data['docId'] ?? '').toString(),
            name: (data['name'] ?? '').toString(),
            postcode: (data['postcode'] ?? '').toString(),
            state: (data['state'] ?? '').toString(),
            latitude: lat,
            longitude: lng,
            description: data['description']?.toString(),
          );
        })
        .whereType<HarvestPlace>()
        .toList();
  }
}
