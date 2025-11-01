import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class MapMarkersService {
  static final _firestore = FirebaseFirestore.instance;

  // 🔹 Retorna un Stream amb tots els markers, amb cache i actualització automàtica
  static Stream<Set<Marker>> getMarkers(Function(Map<String, dynamic>) onTap) {
    final controller = StreamController<Set<Marker>>();

    // 🔸 Escolta els canvis a Firestore, amb suport de cache local
    _firestore.collection('restaurants').snapshots().listen((snapshot) {
      final markers = snapshot.docs.map((doc) {
        final data = doc.data();

        // Afegim l’ID del document
        data['docId'] = doc.id;

        // 🔹 Dades bàsiques
        final String name = data['name'] ?? 'Sense nom';
        final double? lat = (data['latitude'] ?? data['lat'])?.toDouble();
        final double? lng = (data['longitude'] ?? data['lng'])?.toDouble();

        if (lat == null || lng == null) return null;

        return Marker(
          markerId: MarkerId(doc.id),
          position: LatLng(lat, lng),
          // 🔹 Evitem mostrar el text sobre el marcador
          infoWindow: const InfoWindow(title: ''),
          onTap: () => onTap(data),
        );
      }).whereType<Marker>().toSet();

      controller.add(markers);
    });

    return controller.stream;
  }

  // 🔹 Carrega tots els restaurants (una sola vegada) amb cache local
  static Future<List<Map<String, dynamic>>> getAllRestaurantsOnce() async {
    QuerySnapshot<Map<String, dynamic>> snapshot;

    try {
      // 1️⃣ Intenta carregar des de la cache
      snapshot = await _firestore
          .collection('restaurants')
          .get(const GetOptions(source: Source.cache));

      if (snapshot.docs.isNotEmpty) {
        print('🗂️ Carregats ${snapshot.docs.length} restaurants des del cache local.');
        return snapshot.docs.map((doc) => doc.data()).toList();
      }
    } catch (_) {
      // Ignora errors de cache buida
    }

    // 2️⃣ Si el cache està buit, carrega del servidor i es guardarà automàticament
    snapshot = await _firestore
        .collection('restaurants')
        .get(const GetOptions(source: Source.server));

    print('🌐 Carregats ${snapshot.docs.length} restaurants del servidor.');
    return snapshot.docs.map((doc) => doc.data()).toList();
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
