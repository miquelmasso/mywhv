import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;

class RestaurantFetcher {
  static const String _apiKey = "AIzaSyCq0y5wPxOt9oZR6Z0-b0fR5fmQq3BiivI";
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// 🔍 Obté 10 restaurants dins TOT el codi postal (malla 3x3)
  static Future<List<Map<String, dynamic>>> _fetchRestaurants(int postcode) async {
    try {
      final geoUrl = Uri.parse(
        "https://maps.googleapis.com/maps/api/geocode/json?"
        "address=$postcode,Australia&key=$_apiKey",
      );

      final geoRes = await http.get(geoUrl);
      final geoData = jsonDecode(geoRes.body);
      if (geoData["results"].isEmpty) return [];

      final viewport = geoData["results"][0]["geometry"]["viewport"];
      final north = viewport["northeast"]["lat"];
      final east = viewport["northeast"]["lng"];
      final south = viewport["southwest"]["lat"];
      final west = viewport["southwest"]["lng"];

      final stepLat = (north - south) / 3;
      final stepLng = (east - west) / 3;

      final List<Map<String, double>> gridPoints = [];
      for (int i = 0; i < 3; i++) {
        for (int j = 0; j < 3; j++) {
          gridPoints.add({
            "lat": south + (i + 0.5) * stepLat,
            "lng": west + (j + 0.5) * stepLng,
          });
        }
      }

      final Set<String> seen = {};
      final List<Map<String, dynamic>> allRestaurants = [];

      for (final point in gridPoints) {
        final lat = point["lat"];
        final lng = point["lng"];

        final placesUrl = Uri.parse(
          "https://maps.googleapis.com/maps/api/place/nearbysearch/json?"
          "location=$lat,$lng&radius=15000&type=restaurant&key=$_apiKey",
        );

        final placesRes = await http.get(placesUrl);
        final data = jsonDecode(placesRes.body);
        if (data["results"] == null) continue;

        for (var place in data["results"]) {
          final name = place["name"];
          if (name != null && !seen.contains(name)) {
            seen.add(name);
            allRestaurants.add({
              "postcode": postcode,
              "name": name,
              "address": place["vicinity"] ?? "",
              "rating": place["rating"],
              "location": {
                "lat": place["geometry"]["location"]["lat"],
                "lng": place["geometry"]["location"]["lng"],
              },
              "timestamp": DateTime.now(),
            });
          }
        }
      }

      return allRestaurants.take(10).toList();
    } catch (e) {
      print("❌ Error amb el codi $postcode: $e");
      return [];
    }
  }

  /// 🔄 Evita duplicats i guarda als dos col·leccions (417 i 462)
  static Future<void> populateRestaurantsForVisas() async {
    final snap417 = await _firestore
        .collection('visa_417_postcodes')
        .where('industry',
            isEqualTo:
                'Tourism and Hospitality (Remote & Very Remote Australia)')
        .get();

    final snap462 = await _firestore
        .collection('visa_462_postcodes')
        .where('industry',
            isEqualTo:
                'Tourism and Hospitality (Remote & Very Remote Australia)')
        .get();

    // Combina i elimina codis repetits
    final allPostcodes = <int>{
      ...snap417.docs.map((d) => d['postcode']),
      ...snap462.docs.map((d) => d['postcode']),
    }.toList();

    print("🚀 Trobats ${allPostcodes.length} codis únics per 417 i 462");

    for (final postcode in allPostcodes) {
      final restaurants = await _fetchRestaurants(postcode);
      if (restaurants.isEmpty) continue;

      final batch = _firestore.batch();
      final ref417 = _firestore.collection('restaurants_417');
      final ref462 = _firestore.collection('restaurants_462');

      for (final r in restaurants) {
        batch.set(ref417.doc(), r);
        batch.set(ref462.doc(), r);
      }
      await batch.commit();
      print("✅ ${restaurants.length} restaurants guardats per $postcode");

      await Future.delayed(const Duration(seconds: 1));
    }

    print("🎉 Finalitzat: tots els restaurants guardats a 417 i 462");
  }
}
