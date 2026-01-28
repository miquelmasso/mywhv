import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class FarmMarkersService {
  static final _firestore = FirebaseFirestore.instance;

  static Future<Set<Marker>> loadFarmMarkers({
    required bool fromServer,
    required Function(Map<String, dynamic>) onTap,
  }) async {
    final source = fromServer ? Source.server : Source.cache;
    final snapshot =
        await _firestore.collection('farms').get(GetOptions(source: source));
    debugPrint(
        '${fromServer ? '🌐 SERVER' : '📦 CACHE'} farms: ${snapshot.size}');

    return snapshot.docs.map((doc) {
      final data = doc.data();
      data['docId'] = doc.id;

      final double? lat = (data['latitude'] ?? data['lat'])?.toDouble();
      final double? lng = (data['longitude'] ?? data['lng'])?.toDouble();

      if (lat == null || lng == null) return null;

      return Marker(
        markerId: MarkerId(doc.id),
        position: LatLng(lat, lng),
        infoWindow: const InfoWindow(title: ''),
        onTap: () => onTap(data),
      );
    }).whereType<Marker>().toSet();
  }
}
