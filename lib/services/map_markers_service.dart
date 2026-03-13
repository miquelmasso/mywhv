import 'dart:convert';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MapMarkersService {
  static final _firestore = FirebaseFirestore.instance;
  static const _cacheKeyJson = 'restaurants_cache_json';
  static const _cacheKeySynced = 'restaurants_cache_synced';
  static const _cacheKeyAppVersion = 'restaurants_cache_app_version';
  static List<Map<String, dynamic>>? _memoryRestaurants;
  static bool _memorySynced = false;
  static String? _memoryCacheVersion;

  static Future<List<Map<String, dynamic>>> loadRestaurants({
    required bool fromServer,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final cachedJson = prefs.getString(_cacheKeyJson);
    final cacheSynced = prefs.getBool(_cacheKeySynced) ?? false;
    final cachedAppVersion = prefs.getString(_cacheKeyAppVersion);
    final currentAppVersion = await _readCurrentAppVersion();
    final needsVersionRefresh =
        currentAppVersion != null && cachedAppVersion != currentAppVersion;

    final canUseMemoryCache =
        !fromServer &&
        _memoryRestaurants != null &&
        _memorySynced &&
        _memoryCacheVersion == currentAppVersion &&
        !needsVersionRefresh;
    if (canUseMemoryCache) {
      return _memoryRestaurants!;
    }

    final canUsePersistentCache =
        !fromServer &&
        cacheSynced &&
        cachedJson != null &&
        cachedJson.isNotEmpty &&
        !needsVersionRefresh;
    if (canUsePersistentCache) {
      try {
        final cachedList = _decodeCachedList(cachedJson);
        _primeMemoryCache(
          cachedList,
          synced: true,
          appVersion: cachedAppVersion,
        );
        debugPrint('📦 CACHE restaurants loaded: ${cachedList.length}');
        return cachedList;
      } catch (e) {
        debugPrint('⚠️ Error decoding restaurant cache: $e');
      }
    }

    try {
      final filtered = await _fetchRestaurantsFromServer();
      await _persistRestaurantsCache(
        prefs,
        filtered,
        appVersion: currentAppVersion,
      );
      return filtered;
    } catch (e) {
      if (!fromServer && cachedJson != null && cachedJson.isNotEmpty) {
        try {
          final cachedList = _decodeCachedList(cachedJson);
          _primeMemoryCache(
            cachedList,
            synced: cacheSynced,
            appVersion: cachedAppVersion,
          );
          debugPrint(
            '📦 Using stale restaurants cache after server error: ${cachedList.length}',
          );
          return cachedList;
        } catch (cacheError) {
          debugPrint('⚠️ Error decoding stale restaurant cache: $cacheError');
        }
      }
      rethrow;
    }
  }

  static Future<void> updateWorkedHereCache(String docId, int delta) async {
    if (docId.trim().isEmpty || delta == 0) return;

    final prefs = await SharedPreferences.getInstance();
    final cachedJson = prefs.getString(_cacheKeyJson);
    final sourceList = _memoryRestaurants != null
        ? _memoryRestaurants!
        : (cachedJson != null && cachedJson.isNotEmpty)
        ? _decodeCachedList(cachedJson)
        : null;
    if (sourceList == null || sourceList.isEmpty) return;

    final updatedList = sourceList
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);

    var updated = false;
    for (final restaurant in updatedList) {
      final candidateId = (restaurant['docId'] ?? restaurant['id'] ?? '')
          .toString();
      if (candidateId != docId) continue;
      restaurant['worked_here_count'] = math.max(
        0,
        _asInt(restaurant['worked_here_count']) + delta,
      );
      updated = true;
      break;
    }
    if (!updated) return;

    await _persistRestaurantsCache(
      prefs,
      updatedList,
      appVersion: _memoryCacheVersion ?? prefs.getString(_cacheKeyAppVersion),
    );
  }

  static List<Map<String, dynamic>> _decodeCachedList(String cachedJson) {
    final decoded = jsonDecode(cachedJson) as List<dynamic>;
    return decoded
        .whereType<Map<String, dynamic>>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList(growable: false);
  }

  static Set<Marker> buildMarkers(
    List<Map<String, dynamic>> docs,
    Function(Map<String, dynamic>) onTap,
  ) {
    return docs
        .map((data) {
          final double? lat = (data['latitude'] ?? data['lat'])?.toDouble();
          final double? lng = (data['longitude'] ?? data['lng'])?.toDouble();
          if (lat == null || lng == null) return null;
          final docId = data['docId']?.toString() ?? '';
          if (docId.isEmpty) return null;
          return Marker(
            markerId: MarkerId(docId),
            position: LatLng(lat, lng),
            infoWindow: const InfoWindow(title: ''),
            onTap: () => onTap(data),
          );
        })
        .whereType<Marker>()
        .toSet();
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
        debugPrint('Inicialitzat worked_here_count per ${data['name']}');
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

  static Future<List<Map<String, dynamic>>>
  _fetchRestaurantsFromServer() async {
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
    return filtered;
  }

  static Future<void> _persistRestaurantsCache(
    SharedPreferences prefs,
    List<Map<String, dynamic>> restaurants, {
    String? appVersion,
  }) async {
    _primeMemoryCache(restaurants, synced: true, appVersion: appVersion);
    try {
      final sanitized = restaurants.map(_sanitizeForJson).toList();
      final jsonStr = jsonEncode(sanitized);
      await prefs.setString(_cacheKeyJson, jsonStr);
      await prefs.setBool(_cacheKeySynced, true);
      if (appVersion != null && appVersion.isNotEmpty) {
        await prefs.setString(_cacheKeyAppVersion, appVersion);
      }
    } catch (e) {
      debugPrint('⚠️ Error caching restaurants: $e');
    }
  }

  static void _primeMemoryCache(
    List<Map<String, dynamic>> restaurants, {
    required bool synced,
    required String? appVersion,
  }) {
    _memoryRestaurants = restaurants
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
    _memorySynced = synced;
    _memoryCacheVersion = appVersion;
  }

  static int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static Future<String?> _readCurrentAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final version = info.version.trim();
      final build = info.buildNumber.trim();
      if (version.isEmpty && build.isEmpty) return null;
      if (build.isEmpty) return version;
      if (version.isEmpty) return build;
      return '$version+$build';
    } catch (e) {
      debugPrint('⚠️ Error reading app version for restaurants cache: $e');
      return null;
    }
  }

  static Map<String, dynamic> _sanitizeForJson(Map<String, dynamic> src) {
    final out = <String, dynamic>{};
    src.forEach((key, value) {
      out[key] = _convertValue(value);
    });
    return out;
  }

  static dynamic _convertValue(dynamic value) {
    if (value is Timestamp) return value.toDate().toIso8601String();
    if (value is DateTime) return value.toIso8601String();
    if (value is GeoPoint) {
      return {'lat': value.latitude, 'lng': value.longitude};
    }
    if (value is Map) {
      return value.map((k, v) => MapEntry(k.toString(), _convertValue(v)));
    }
    if (value is Iterable) {
      return value.map(_convertValue).toList();
    }
    return value;
  }
}
