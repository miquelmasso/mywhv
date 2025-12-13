import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class HarvestMarkersService {
  static final _firestore = FirebaseFirestore.instance;

  static Stream<Set<Marker>> getMarkers(
    Function(Map<String, dynamic>) onTap,
  ) {
    final controller = StreamController<Set<Marker>>();

    _firestore.collection('harvest_calendar').snapshots().listen((snapshot) {
      final markers = snapshot.docs.map((doc) {
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

      controller.add(markers);
    });

    return controller.stream;
  }
}
