import 'package:cloud_firestore/cloud_firestore.dart';
import 'postcode_state_helper.dart';

class ExistingRestaurantKeys {
  final Set<String> placeIds;
  final Set<String> altKeys;
  const ExistingRestaurantKeys({
    required this.placeIds,
    required this.altKeys,
  });
}

class FirestoreHelper {
  final firestore = FirebaseFirestore.instance;

  Future<bool> existsRestaurant(String name) async {
    final snap = await firestore
        .collection('restaurants')
        .where('name', isEqualTo: name)
        .limit(1)
        .get();
    if (snap.docs.isNotEmpty) {
      print('ℹ️ Ja existeix a Firestore: $name');
      return true;
    }
    return false;
  }

  Map<String, dynamic> buildRestaurantData({
    required String name,
    required int postcode,
    required String address,
    required Map<String, dynamic> details,
    required String? email,
    required String placeId,
    String? facebookUrl,
    String? careersPage, // 👈 nou paràmetre
    String? instagramUrl,
  }) {
    final lat = details['location']?['latitude'];
    final lng = details['location']?['longitude'];
    final phone = details['internationalPhoneNumber'] ?? '';
    final website = details['websiteUri'] ?? '';
    final state = getStateFromPostcode(postcode);

    return {
      'name': name,
      'postcode': postcode,
      'postcode_display': postcode.toString().padLeft(4, '0'),
      'state': state,
      'address': address,
      'latitude': lat,
      'longitude': lng,
      'phone': phone,
      'website': website,
      'email': email ?? '',
      'facebook_url': facebookUrl ?? '',
      'careers_page': careersPage ?? '', // 👈 afegim-lo aquí
      'instagram_url': instagramUrl ?? '',
      'source_place_id': placeId,
      'timestamp': DateTime.now(),
    };
  }

  Future<void> saveRestaurant(Map<String, dynamic> data, String name) async {
    final id = name
        .replaceAll(RegExp(r'[\/.#\$\[\]]'), '-')
        .replaceAll(' ', '_')
        .replaceAll(RegExp(r'_{2,}'), '_');
    await firestore.collection('restaurants').doc(id).set(data);
    print('✅ Guardat: ${data['name']} (ID: $id)');
  }

  /// 🔍 Carrega una vegada els identificadors existents per un postcode,
  /// per evitar duplicats abans de cridar Places o fer detalls.
  Future<ExistingRestaurantKeys> loadExistingKeysForPostcode(
    String postcodeDisplay,
  ) async {
    final postcodeNum = int.tryParse(postcodeDisplay);
    final queries = <Future<QuerySnapshot<Map<String, dynamic>>>>[
      firestore
          .collection('restaurants')
          .where('postcode_display', isEqualTo: postcodeDisplay)
          .get(),
    ];

    // Alguns docs antics poden no tenir postcode_display, així que fem una
    // segona consulta per integer si és possible.
    if (postcodeNum != null) {
      queries.add(
        firestore
            .collection('restaurants')
            .where('postcode', isEqualTo: postcodeNum)
            .get(),
      );
    }

    final snapshots = await Future.wait(queries);
    final placeIds = <String>{};
    final altKeys = <String>{};

    for (final snap in snapshots) {
      for (final doc in snap.docs) {
        final data = doc.data();
        final placeId = (data['source_place_id'] ?? '').toString();
        if (placeId.isNotEmpty) placeIds.add(placeId);

        final name = (data['name'] ?? '').toString();
        final lat = (data['latitude'] ?? data['lat']);
        final lng = (data['longitude'] ?? data['lng']);
        final alt = _buildAltKey(
          name: name,
          postcodeDisplay: postcodeDisplay,
          lat: lat,
          lng: lng,
        );
        if (alt != null) altKeys.add(alt);
      }
    }

    return ExistingRestaurantKeys(placeIds: placeIds, altKeys: altKeys);
  }

  /// Afegeix al WriteBatch mantenint el mateix esquema d'ID que saveRestaurant.
  void addRestaurantToBatch(
    WriteBatch batch,
    Map<String, dynamic> data,
    String name,
  ) {
    final id = name
        .replaceAll(RegExp(r'[\/.#\$\[\]]'), '-')
        .replaceAll(' ', '_')
        .replaceAll(RegExp(r'_{2,}'), '_');
    batch.set(firestore.collection('restaurants').doc(id), data);
    print('📦 Pending batch write: ${data['name']} (ID: $id)');
  }

  String? _buildAltKey({
    required String name,
    required String postcodeDisplay,
    required dynamic lat,
    required dynamic lng,
  }) {
    final double? latD = lat is num ? lat.toDouble() : double.tryParse('$lat');
    final double? lngD = lng is num ? lng.toDouble() : double.tryParse('$lng');
    if (latD == null || lngD == null) return null;
    final normalizedName = name.trim().toLowerCase();
    return '$normalizedName|$postcodeDisplay|${latD.toStringAsFixed(5)}|${lngD.toStringAsFixed(5)}';
  }
}
