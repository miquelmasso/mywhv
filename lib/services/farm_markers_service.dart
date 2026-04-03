import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'farm_sqlite_store.dart';

class FarmMarkersService {
  static Future<Set<Marker>> loadFarmMarkers({
    required bool fromServer,
    required Function(Map<String, dynamic>) onTap,
  }) async {
    if (fromServer) {
      debugPrint(
        'ℹ️ loadFarmMarkers(fromServer: true) ignored: local SQLite mode',
      );
    }

    final store = FarmSqliteStore.instance;
    await store.init();
    final farms = await store.getAll();
    debugPrint('🗄️ SQLITE farms loaded: ${farms.length}');

    return farms
        .map((data) {
          data['docId'] ??= data['id'];

          final double? lat = (data['latitude'] ?? data['lat'])?.toDouble();
          final double? lng = (data['longitude'] ?? data['lng'])?.toDouble();

          if (lat == null || lng == null) return null;
          final docId = (data['docId'] ?? '').toString();
          if (docId.isEmpty) return null;

          return Marker(
            markerId: MarkerId(docId),
            position: LatLng(lat, lng),
            infoWindow: const InfoWindow(title: ''),
            onTap: () => onTap(data),
          );
        })
        .whereType<Marker>()
        .toSet();
  }
}
