import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../config/google_services_config.dart';
import '../services/postcode_state_helper.dart';

class RestaurantCollector {
  static const _apiKey = 'AIzaSyCq0y5wPxOt9oZR6Z0-b0fR5fmQq3BiivI';
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// 🔹 Funció principal: descarrega i desa restaurants per codis postals de Tourism & Hospitality
  static Future<void> fetchAndSaveTourismRestaurants() async {
    if (!GoogleServicesConfig.enableLegacyGoogleImports) {
      debugPrint(
        'ℹ️ Legacy Google imports paused: skipping tourism restaurant collection.',
      );
      return;
    }

    debugPrint(
      '🚀 Iniciant recollida de restaurants per zones Tourism & Hospitality...',
    );

    // 1️⃣ Obtenim tots els codis postals de Tourism & Hospitality del 417 i del 462
    final postcodes417 = await _getTourismPostcodes('visa_417_industries');
    final postcodes462 = await _getTourismPostcodes('visa_462_industries');

    // 2️⃣ Fusionem i eliminem duplicats
    final allPostcodes = {...postcodes417, ...postcodes462}.toList();
    debugPrint(
      '📍 Found ${allPostcodes.length} unique Tourism & Hospitality postcodes.',
    );

    // 3️⃣ Recorrem cada codi postal
    for (final code in allPostcodes) {
      final existing = await _firestore
          .collection('restaurants')
          .where('postcode', isEqualTo: code)
          .limit(1)
          .get();

      if (existing.docs.isNotEmpty) {
        debugPrint(
          '⏭️ Ja existeixen dades pel codi $code, s’omet la consulta.',
        );
        continue;
      }

      final restaurants = await _fetchRestaurantsForPostcode(code);

      if (restaurants.isEmpty) {
        debugPrint('⚠️ Cap restaurant trobat per $code.');
        continue;
      }

      for (var r in restaurants.take(10)) {
        final computedState = getStateFromPostcode(code.toString());
        await _firestore.collection('restaurants').add({
          'name': r['name'],
          'latitude': r['lat'],
          'longitude': r['lng'],
          'phone': r['phone'],
          'postcode': code,
          'visa_types': _getVisaTypes(code, postcodes417, postcodes462),
          'worked_here_count': 0,
          'state': computedState,
        });
      }

      debugPrint('✅ ${restaurants.length} restaurants guardats per $code.');
      await Future.delayed(
        const Duration(seconds: 2),
      ); // petit delay per no saturar l’API
    }

    debugPrint(
      '🎉 Tots els restaurants de Tourism & Hospitality guardats correctament!',
    );
  }

  /// 🔸 Obté els codis postals de la indústria "Tourism and Hospitality" d’una col·lecció (417 o 462)
  static Future<List<int>> _getTourismPostcodes(String collectionName) async {
    final snapshot = await _firestore.collection(collectionName).get();
    final tourismDoc = snapshot.docs.firstWhere(
      (d) => d.id.toLowerCase().contains('tourism'),
      orElse: () =>
          throw Exception('❌ Tourism industry not found in $collectionName'),
    );
    return List<int>.from(tourismDoc['postcodes']);
  }

  /// 🔸 Determina per quins tipus de visa és vàlid un codi postal
  static List<String> _getVisaTypes(
    int code,
    List<int> codes417,
    List<int> codes462,
  ) {
    final visas = <String>[];
    if (codes417.contains(code)) visas.add('417');
    if (codes462.contains(code)) visas.add('462');
    return visas;
  }

  /// 🔸 Fa la crida a Google Places per un codi postal concret
  static Future<List<Map<String, dynamic>>> _fetchRestaurantsForPostcode(
    int postcode,
  ) async {
    if (!GoogleServicesConfig.enableLegacyGoogleImports) {
      debugPrint(
        'ℹ️ Legacy Google imports paused: skipping Places request for $postcode.',
      );
      return <Map<String, dynamic>>[];
    }

    final url = Uri.parse(
      'https://maps.googleapis.com/maps/api/place/textsearch/json'
      '?query=restaurants+in+Australia+$postcode&key=$_apiKey',
    );

    final response = await http.get(url);
    if (response.statusCode != 200) {
      debugPrint('❌ Error Places API ($postcode): ${response.statusCode}');
      return [];
    }

    final data = jsonDecode(response.body);
    final results = data['results'] as List? ?? [];

    final restaurants = <Map<String, dynamic>>[];

    for (final place in results.take(10)) {
      final details = await _fetchPlaceDetails(place['place_id']);
      restaurants.add({
        'name': place['name'],
        'lat': place['geometry']['location']['lat'],
        'lng': place['geometry']['location']['lng'],
        'phone': details['phone'] ?? 'N/A',
      });
    }

    return restaurants;
  }

  /// 🔸 Crida secundària per obtenir el telèfon
  static Future<Map<String, dynamic>> _fetchPlaceDetails(String placeId) async {
    if (!GoogleServicesConfig.enableLegacyGoogleImports) {
      debugPrint(
        'ℹ️ Legacy Google imports paused: skipping place details request.',
      );
      return <String, dynamic>{};
    }

    final url = Uri.parse(
      'https://maps.googleapis.com/maps/api/place/details/json'
      '?place_id=$placeId&fields=name,formatted_phone_number&key=$_apiKey',
    );

    final response = await http.get(url);
    if (response.statusCode != 200) return {};
    final data = jsonDecode(response.body);
    return {'phone': data['result']?['formatted_phone_number']};
  }
}
