import 'package:cloud_firestore/cloud_firestore.dart';

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
  }) {
    final lat = details['location']?['latitude'];
    final lng = details['location']?['longitude'];
    final phone = details['internationalPhoneNumber'] ?? '';
    final website = details['websiteUri'] ?? '';

    return {
      'name': name,
      'postcode': postcode,
      'postcode_display': postcode.toString().padLeft(4, '0'),
      'address': address,
      'latitude': lat,
      'longitude': lng,
      'phone': phone,
      'website': website,
      'email': email ?? '',
      'facebook_url': facebookUrl ?? '',
      'careers_page': careersPage ?? '', // 👈 afegim-lo aquí
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
}
