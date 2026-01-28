import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class MapMarkersService {
  static final _firestore = FirebaseFirestore.instance;

  static Future<List<Map<String, dynamic>>> loadRestaurants({
    required bool fromServer,
  }) async {
    final source = fromServer ? Source.server : Source.cache;
    final snapshot = await _firestore
        .collection('restaurants')
        .get(GetOptions(source: source));
    debugPrint(
        '${fromServer ? '🌐 SERVER' : '📦 CACHE'} restaurants: ${snapshot.size}');
    return snapshot.docs.map((doc) {
      final data = doc.data();
      data['docId'] = doc.id;
      return data;
    }).toList();
  }

  static Set<Marker> buildMarkers(
    List<Map<String, dynamic>> docs,
    Function(Map<String, dynamic>) onTap,
  ) {
    return docs.map((data) {
      final double? lat = (data['latitude'] ?? data['lat'])?.toDouble();
      final double? lng = (data['longitude'] ?? data['lng'])?.toDouble();
      if (lat == null || lng == null) return null;
      final docId = data['docId']?.toString() ?? '';
      return Marker(
        markerId: MarkerId(docId),
        position: LatLng(lat, lng),
        infoWindow: const InfoWindow(title: ''),
        onTap: () => onTap(data),
      );
    }).whereType<Marker>().toSet();
  }

  // 🔹 Incrementa el comptador "worked_here_count"
  static Future<void> incrementWorkedHere(String docId) async {
    if (docId.trim().isEmpty) {
      throw ArgumentError('Document ID buit o invàlid');
    }

    final docRef = _firestore.collection('restaurants').doc(docId);

    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(docRef);
      final current = snapshot.data()?['worked_here_count'] ?? 0;
      transaction.update(docRef, {'worked_here_count': current + 1});
    });
  }

  // 🔹 Redueix el comptador "worked_here_count" si algú vol treure-ho
  static Future<void> decrementWorkedHere(String docId) async {
    if (docId.trim().isEmpty) {
      throw ArgumentError('Document ID buit o invàlid');
    }

    final docRef = _firestore.collection('restaurants').doc(docId);

    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(docRef);
      final current = snapshot.data()?['worked_here_count'] ?? 0;
      final newValue = (current > 0) ? current - 1 : 0;
      transaction.update(docRef, {'worked_here_count': newValue});
    });
  }

  // 🔹 Inicialitza el camp "worked_here_count" si no existeix
  static Future<void> ensureWorkedHereField() async {
    final snapshot = await _firestore.collection('restaurants').get();
    for (final doc in snapshot.docs) {
      final data = doc.data();
      if (!data.containsKey('worked_here_count')) {
        await doc.reference.update({'worked_here_count': 0});
        print('Inicialitzat worked_here_count per ${data['name']}');
      }
    }
  }
}
