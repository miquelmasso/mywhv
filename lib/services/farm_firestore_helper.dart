import 'package:cloud_firestore/cloud_firestore.dart';
import 'postcode_state_helper.dart';

class ExistingFarmKeys {
  final Set<String> placeIds;
  final Set<String> altKeys;
  const ExistingFarmKeys({
    required this.placeIds,
    required this.altKeys,
  });
}

class FarmFirestoreHelper {
  final firestore = FirebaseFirestore.instance;

  Future<ExistingFarmKeys> loadExistingKeysForPostcode(
    String postcodeDisplay,
  ) async {
    final postcodeNum = int.tryParse(postcodeDisplay);
    final queries = <Future<QuerySnapshot<Map<String, dynamic>>>>[
      firestore
          .collection('farms')
          .where('postcode_display', isEqualTo: postcodeDisplay)
          .get(),
    ];

    if (postcodeNum != null) {
      queries.add(
        firestore
            .collection('farms')
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

    return ExistingFarmKeys(placeIds: placeIds, altKeys: altKeys);
  }

  Map<String, dynamic> buildFarmData({
    required String name,
    required String address,
    required String postcodeDisplay,
    required int postcode,
    required double latitude,
    required double longitude,
    required String? phone,
    required String? website,
    required String? email,
    required String? facebookUrl,
    required String? instagramUrl,
    required String? careersPage,
    required String placeId,
    required bool isRemote462,
    required String category,
  }) {
    final state = getStateFromPostcode(postcodeDisplay);

    return {
      'name': name,
      'address': address,
      'state': state,
      'postcode': postcode,
      'postcode_display': postcodeDisplay,
      'latitude': latitude,
      'longitude': longitude,
      'phone': phone ?? '',
      'website': website ?? '',
      'email': email ?? '',
      'facebook_url': facebookUrl ?? '',
      'instagram_url': instagramUrl ?? '',
      'careers_page': careersPage ?? '',
      'source_place_id': placeId,
      'timestamp': FieldValue.serverTimestamp(),
      'worked_here_count': 0,
      'is_remote_462': isRemote462,
      'category': category,
    };
  }

  void addFarmToBatch(
    WriteBatch batch,
    Map<String, dynamic> data,
    String name,
  ) {
    final id = name
        .replaceAll(RegExp(r'[\/.#\$\[\]]'), '-')
        .replaceAll(' ', '_')
        .replaceAll(RegExp(r'_{2,}'), '_');
    batch.set(firestore.collection('farms').doc(id), data);
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
