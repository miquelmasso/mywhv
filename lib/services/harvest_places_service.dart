import 'package:cloud_firestore/cloud_firestore.dart';

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
  static final _firestore = FirebaseFirestore.instance;

  static Stream<List<HarvestPlace>> streamHarvestPlaces() {
    return _firestore.collection('harvest_places').snapshots().map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data();
        final lat = (data['latitude'] ?? data['lat'])?.toDouble();
        final lng = (data['longitude'] ?? data['lng'])?.toDouble();
        if (lat == null || lng == null) return null;
        return HarvestPlace(
          id: doc.id,
          name: (data['name'] ?? '').toString(),
          postcode: (data['postcode'] ?? '').toString(),
          state: (data['state'] ?? '').toString(),
          latitude: lat,
          longitude: lng,
          description: data['description']?.toString(),
        );
      }).whereType<HarvestPlace>().toList();
    });
  }
}
