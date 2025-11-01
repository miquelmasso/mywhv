import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'email_extractor.dart';
import 'careers_extractor.dart';
import 'facebook_extractor.dart';
import 'firestore_helper.dart';
import 'http_client.dart';

class GooglePlacesService {
  static const _apiKey = 'AIzaSyCq0y5wPxOt9oZR6Z0-b0fR5fmQq3BiivI';
  final EmailExtractor _emailExtractor = EmailExtractor();
  final CareersExtractor _careersExtractor = CareersExtractor();
  final FacebookExtractor _facebookExtractor = FacebookExtractor();
  final FirestoreHelper _firestoreHelper = FirestoreHelper();

  /// 🔍 Cerca i desa fins a 2 negocis d'hospitality (restaurants, bars, cafés...) per codi postal
  Future<List<Map<String, dynamic>>> SaveTwoRestaurantsForPostcode(int postcode) async {
    final firestore = FirebaseFirestore.instance;
    final postcodeDisplay = postcode.toString().padLeft(4, '0');
    print('🔍 Iniciant cerca per postcode $postcodeDisplay');

    final isNT = (postcode >= 800 && postcode <= 999);
    final region = isNT ? 'Northern Territory, Australia' : 'Australia';

    // 🔎 Llista d’activitats a buscar
    final List<String> businessTypes = [
      'restaurant',
      'cafe',
      'bar',
      'pub',
      'tavern',
      'takeaway food',
      'catering service',
      'hospitality club',
    ];

    final saved = <Map<String, dynamic>>[];
    final triedNames = <String>{};

    // 🔁 Cerca per cada tipus de negoci
    for (final type in businessTypes) {
      if (saved.length >= 2) break;

      final searchUrl = Uri.parse('https://places.googleapis.com/v1/places:searchText');
      final resp = await ioClient.post(
        searchUrl,
        headers: {
          'Content-Type': 'application/json',
          'X-Goog-Api-Key': _apiKey,
          'X-Goog-FieldMask':
              'places.id,places.displayName,places.location,places.formattedAddress',
        },
        body: jsonEncode({
          'textQuery': '$type in $postcodeDisplay, $region',
          'maxResultCount': 10,
        }),
      );

      if (resp.statusCode != 200) {
        print('⚠️ Error cercant "$type" ($postcodeDisplay): ${resp.statusCode}');
        continue;
      }

      final data = jsonDecode(resp.body);
      final List places = (data['places'] ?? []);
      if (places.isEmpty) continue;

      for (final place in places) {
        if (saved.length >= 2) break;
        final id = place['id'];
        if (id == null) continue;

        // 🔹 Obtenir detalls del lloc
        final details = await _getPlaceDetails(id);
        if (details == null) continue;

        final name = (details['displayName']?['text'] ?? 'Unnamed').toString();
        if (triedNames.contains(name)) continue;
        triedNames.add(name);

        // 🔹 Evita duplicats al Firestore
        if (await _firestoreHelper.existsRestaurant(name)) continue;

        final address = details['formattedAddress'] ?? '';
        if (!_matchesPostcode(address, postcodeDisplay)) continue;

        // 🌐 --- Busca EMAIL, FACEBOOK i CAREERS PAGE ---
        final website = details['websiteUri'] ?? '';
        String? email;
        String? careersPage;
        String? facebookUrl;

        if (website.isNotEmpty) {
  email = await _emailExtractor.extract(website);
  careersPage = await _careersExtractor.find(website);

  // ✅ Retorna un Map amb {link, score} → n’extraiem només el link
  final fbResult = await _facebookExtractor.find(
    baseUrl: website,
    businessName: name,
    address: address,
    phone: details['internationalPhoneNumber'] ?? '',
  );
  facebookUrl = fbResult != null ? fbResult['link'] as String? : null;
}


        // 🧩 Dades a desar
        final restaurant = _firestoreHelper.buildRestaurantData(
          name: name,
          postcode: postcode,
          address: address,
          details: details,
          email: email,
          placeId: id,
          facebookUrl: facebookUrl,
          careersPage: careersPage,
        );

        await _firestoreHelper.saveRestaurant(restaurant, name);
        saved.add(restaurant);
      }
    }

    print('🎯 S’han guardat ${saved.length} negocis per $postcodeDisplay');
    return saved;
  }

  // -------------------------------
  // 🔧 Helpers
  // -------------------------------

  Future<Map<String, dynamic>?> _getPlaceDetails(String placeId) async {
    final url = Uri.parse('https://places.googleapis.com/v1/places/$placeId');
    final resp = await ioClient.get(url, headers: {
      'Content-Type': 'application/json',
      'X-Goog-Api-Key': _apiKey,
      'X-Goog-FieldMask':
          'displayName,location,formattedAddress,internationalPhoneNumber,websiteUri',
    });
    if (resp.statusCode != 200) return null;
    return jsonDecode(resp.body);
  }

  bool _matchesPostcode(String address, String target) {
    final re = RegExp(r'\b0?\d{3,4}\b');
    final matches = re.allMatches(address).map((m) => m.group(0)).toList();
    return matches.contains(target);
  }
}
