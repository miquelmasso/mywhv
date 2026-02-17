import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MapMarkersService {
  static final _firestore = FirebaseFirestore.instance;
  static const _cacheKeyJson = 'restaurants_cache_json';
  static const _cacheKeySynced = 'restaurants_cache_synced';

  static Future<List<Map<String, dynamic>>> loadRestaurants({
    required bool fromServer,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    // 1) Serve from cache if available and not forcing server
    if (!fromServer) {
      final cachedJson = prefs.getString(_cacheKeyJson);
      final cacheSynced = prefs.getBool(_cacheKeySynced) ?? false;
      if (cacheSynced && cachedJson != null && cachedJson.isNotEmpty) {
        try {
          final decoded = jsonDecode(cachedJson) as List<dynamic>;
          final cachedList = decoded
              .whereType<Map<String, dynamic>>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
          debugPrint('📦 CACHE restaurants loaded: ${cachedList.length}');
          return cachedList;
        } catch (e) {
          debugPrint('⚠️ Error decoding restaurant cache: $e');
        }
      }
    }

    // 2) Fetch from server (no limits), filter valid entries, then cache
    final snapshot = await _firestore
        .collection('restaurants')
        .get(const GetOptions(source: Source.server));
    debugPrint('🌐 SERVER restaurants fetched: ${snapshot.size}');

    final filtered = <Map<String, dynamic>>[];
    for (final doc in snapshot.docs) {
      final data = doc.data();
      data['docId'] = doc.id;
      if (_isValidRestaurant(data)) {
        filtered.add(data);
      }
    }

    debugPrint('✅ Valid restaurants after filter: ${filtered.length}');

    try {
      final jsonStr = jsonEncode(filtered);
      await prefs.setString(_cacheKeyJson, jsonStr);
      await prefs.setBool(_cacheKeySynced, true);
    } catch (e) {
      debugPrint('⚠️ Error caching restaurants: $e');
    }

    return filtered;
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

  static bool _isValidRestaurant(Map<String, dynamic> data) {
    bool hasNonEmpty(String key) {
      final value = data[key];
      if (value == null) return false;
      final str = value.toString().trim();
      return str.isNotEmpty;
    }

    return hasNonEmpty('email') ||
        hasNonEmpty('facebook_url') ||
        hasNonEmpty('instagram_url') ||
        hasNonEmpty('careers_page') ||
        hasNonEmpty('jobPage');
  }
}
