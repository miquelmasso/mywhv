import 'dart:convert';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'restaurant_sqlite_store.dart';

class MapMarkersService {
  static const _cacheKeyJson = 'restaurants_cache_json';
  static const _cacheKeySynced = 'restaurants_cache_synced';
  static const _cacheKeyAppVersion = 'restaurants_cache_app_version';
  static const _localWorkedHereMinCountsKey =
      'worked_here_local_min_counts_json';
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static List<Map<String, dynamic>>? _memoryRestaurants;
  static String? _memoryCacheVersion;
  static List<Map<String, dynamic>>? _memoryMapRestaurants;
  static String? _memoryMapCacheVersion;

  static Future<List<Map<String, dynamic>>> loadRestaurants({
    required bool fromServer,
    bool lightweight = false,
  }) async {
    if (fromServer) {
      debugPrint(
        'ℹ️ loadRestaurants(fromServer: true) ignored: local SQLite mode',
      );
    }
    final prefs = await SharedPreferences.getInstance();
    final sqliteStore = RestaurantSqliteStore.instance;
    await sqliteStore.init();
    final cachedJson = prefs.getString(_cacheKeyJson);
    final cacheSynced = prefs.getBool(_cacheKeySynced) ?? false;
    final cachedAppVersion = prefs.getString(_cacheKeyAppVersion);
    final localWorkedHereMinCounts = _readLocalWorkedHereMinCounts(prefs);
    final currentAppVersion = await _readCurrentAppVersion();
    final needsVersionRefresh =
        currentAppVersion != null && cachedAppVersion != currentAppVersion;

    final canUseMemoryCache = lightweight
        ? _memoryMapRestaurants != null &&
              _memoryMapCacheVersion == currentAppVersion &&
              !needsVersionRefresh
        : _memoryRestaurants != null &&
              _memoryCacheVersion == currentAppVersion &&
              !needsVersionRefresh;
    if (canUseMemoryCache) {
      return lightweight
          ? _applyLocalWorkedHereMinCounts(
              _memoryMapRestaurants!,
              localWorkedHereMinCounts,
            )
          : _memoryRestaurants!;
    }

    final canUsePersistentCache =
        cacheSynced &&
        cachedJson != null &&
        cachedJson.isNotEmpty &&
        !needsVersionRefresh;

    try {
      final sqliteRestaurants = lightweight
          ? await sqliteStore.getAllForMap()
          : await sqliteStore.getAll();
      if (sqliteRestaurants.isNotEmpty) {
        if (lightweight) {
          _primeMapMemoryCache(
            _applyLocalWorkedHereMinCounts(
              sqliteRestaurants,
              localWorkedHereMinCounts,
            ),
            appVersion: currentAppVersion ?? cachedAppVersion,
          );
        } else {
          _primeMemoryCache(
            sqliteRestaurants,
            synced: true,
            appVersion: currentAppVersion ?? cachedAppVersion,
          );
          _primeMapMemoryCache(
            _applyLocalWorkedHereMinCounts(
              _toMapRestaurantList(sqliteRestaurants),
              localWorkedHereMinCounts,
            ),
            appVersion: currentAppVersion ?? cachedAppVersion,
          );
          if (!canUsePersistentCache || needsVersionRefresh) {
            await _persistRestaurantsCache(
              prefs,
              sqliteRestaurants,
              appVersion: currentAppVersion,
            );
          }
        }
        debugPrint(
          '🗄️ SQLITE restaurants loaded${lightweight ? ' (lightweight)' : ''}: ${sqliteRestaurants.length}',
        );
        return sqliteRestaurants;
      }
    } catch (e) {
      debugPrint('⚠️ Error loading restaurants from SQLite: $e');
    }
    if (canUsePersistentCache) {
      try {
        final cachedList = _decodeCachedList(cachedJson);
        await sqliteStore.replaceAll(cachedList);
        final mapList = _toMapRestaurantList(cachedList);
        _primeMemoryCache(
          cachedList,
          synced: true,
          appVersion: cachedAppVersion,
        );
        _primeMapMemoryCache(
          _applyLocalWorkedHereMinCounts(mapList, localWorkedHereMinCounts),
          appVersion: cachedAppVersion,
        );
        debugPrint(
          '📦 CACHE restaurants loaded${lightweight ? ' (lightweight)' : ''}: ${lightweight ? mapList.length : cachedList.length}',
        );
        return lightweight
            ? _applyLocalWorkedHereMinCounts(mapList, localWorkedHereMinCounts)
            : cachedList;
      } catch (e) {
        debugPrint('⚠️ Error decoding restaurant cache: $e');
      }
    }

    if (cachedJson != null && cachedJson.isNotEmpty) {
      try {
        final cachedList = _decodeCachedList(cachedJson);
        final mapList = _toMapRestaurantList(cachedList);
        _primeMemoryCache(
          cachedList,
          synced: cacheSynced,
          appVersion: cachedAppVersion,
        );
        _primeMapMemoryCache(
          _applyLocalWorkedHereMinCounts(mapList, localWorkedHereMinCounts),
          appVersion: cachedAppVersion,
        );
        debugPrint(
          '📦 Using stale restaurants cache after SQLite miss${lightweight ? ' (lightweight)' : ''}: ${lightweight ? mapList.length : cachedList.length}',
        );
        return lightweight
            ? _applyLocalWorkedHereMinCounts(mapList, localWorkedHereMinCounts)
            : cachedList;
      } catch (cacheError) {
        debugPrint('⚠️ Error decoding stale restaurant cache: $cacheError');
      }
    }

    debugPrint('⚠️ No local restaurants found in SQLite or cache');
    return const <Map<String, dynamic>>[];
  }

  static Future<void> updateWorkedHereCache(String docId, int delta) async {
    if (docId.trim().isEmpty || delta == 0) return;
    final sqliteStore = RestaurantSqliteStore.instance;
    await sqliteStore.init();
    await sqliteStore.updateWorkedHereCount(docId, delta);

    final prefs = await SharedPreferences.getInstance();
    final localWorkedHereMinCounts = _readLocalWorkedHereMinCounts(prefs);
    final cachedJson = prefs.getString(_cacheKeyJson);
    final sourceList = _memoryRestaurants != null
        ? _memoryRestaurants!
        : (cachedJson != null && cachedJson.isNotEmpty)
        ? _decodeCachedList(cachedJson)
        : null;
    final effectiveSourceList = sourceList ?? await sqliteStore.getAll();
    if (effectiveSourceList.isEmpty) return;

    final updatedList = _updatedWorkedHereList(
      effectiveSourceList,
      docId,
      delta,
    );
    if (updatedList == null) return;

    await _persistRestaurantsCache(
      prefs,
      updatedList,
      appVersion: _memoryCacheVersion ?? prefs.getString(_cacheKeyAppVersion),
      localWorkedHereMinCounts: localWorkedHereMinCounts,
    );
  }

  static Future<void> rememberLocalWorkedHereCount(
    String docId,
    int minCount,
  ) async {
    if (docId.trim().isEmpty || minCount < 0) return;
    final prefs = await SharedPreferences.getInstance();
    final counts = _readLocalWorkedHereMinCounts(prefs);
    final current = counts[docId] ?? 0;
    if (minCount <= current) return;
    counts[docId] = minCount;
    await prefs.setString(_localWorkedHereMinCountsKey, jsonEncode(counts));

    if (_memoryMapRestaurants != null) {
      _memoryMapRestaurants = _applyLocalWorkedHereMinCounts(
        _memoryMapRestaurants!,
        counts,
      );
    }
  }

  static Future<void> replaceLocalRestaurants(
    List<Map<String, dynamic>> restaurants,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await _persistRestaurantsCache(
      prefs,
      restaurants,
      appVersion: await _readCurrentAppVersion(),
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
    await _firestore.collection('restaurants').doc(docId).set({
      'worked_here_count': FieldValue.increment(1),
      'worked_here_updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // 🔹 Redueix el comptador "worked_here_count" si algú vol treure-ho
  static Future<void> decrementWorkedHere(String docId) async {
    if (docId.trim().isEmpty) {
      throw ArgumentError('Document ID buit o invàlid');
    }
    debugPrint('ℹ️ decrementWorkedHere skipped: local SQLite mode');
  }

  // 🔹 Inicialitza el camp "worked_here_count" si no existeix
  static Future<void> ensureWorkedHereField() async {
    debugPrint('ℹ️ ensureWorkedHereField skipped: local SQLite mode');
  }

  static Future<void> _persistRestaurantsCache(
    SharedPreferences prefs,
    List<Map<String, dynamic>> restaurants, {
    String? appVersion,
    Map<String, int>? localWorkedHereMinCounts,
  }) async {
    _primeMemoryCache(restaurants, synced: true, appVersion: appVersion);
    final localCounts =
        localWorkedHereMinCounts ?? _readLocalWorkedHereMinCounts(prefs);
    _primeMapMemoryCache(
      _applyLocalWorkedHereMinCounts(
        _toMapRestaurantList(restaurants),
        localCounts,
      ),
      appVersion: appVersion,
    );
    try {
      final sqliteStore = RestaurantSqliteStore.instance;
      await sqliteStore.init();
      await sqliteStore.replaceAll(restaurants);
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
    _memoryCacheVersion = appVersion;
  }

  static void _primeMapMemoryCache(
    List<Map<String, dynamic>> restaurants, {
    required String? appVersion,
  }) {
    _memoryMapRestaurants = restaurants
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
    _memoryMapCacheVersion = appVersion;
  }

  static List<Map<String, dynamic>> _toMapRestaurantList(
    List<Map<String, dynamic>> restaurants,
  ) {
    return restaurants
        .map(
          (restaurant) => <String, dynamic>{
            'id': (restaurant['docId'] ?? restaurant['id'] ?? '').toString(),
            'docId': (restaurant['docId'] ?? restaurant['id'] ?? '').toString(),
            'name': (restaurant['name'] ?? '').toString(),
            'address': (restaurant['address'] ?? '').toString(),
            'postcode': (restaurant['postcode'] ?? '').toString(),
            'postcode_display': (restaurant['postcode_display'] ?? '')
                .toString(),
            'state': (restaurant['state'] ?? '').toString(),
            'latitude': _asDouble(restaurant['latitude'] ?? restaurant['lat']),
            'longitude': _asDouble(
              restaurant['longitude'] ?? restaurant['lng'],
            ),
            'lat': _asDouble(restaurant['latitude'] ?? restaurant['lat']),
            'lng': _asDouble(restaurant['longitude'] ?? restaurant['lng']),
            'phone': (restaurant['phone'] ?? '').toString(),
            'email': (restaurant['email'] ?? '').toString(),
            'facebook_url': (restaurant['facebook_url'] ?? '').toString(),
            'instagram_url': (restaurant['instagram_url'] ?? '').toString(),
            'careers_page': (restaurant['careers_page'] ?? '').toString(),
            'website': (restaurant['website'] ?? '').toString(),
            'blocked':
                restaurant['blocked'] == true ||
                _asInt(restaurant['blocked']) > 0,
            'worked_here_count': _asInt(restaurant['worked_here_count']),
            'timestamp': restaurant['timestamp']?.toString() ?? '',
          },
        )
        .where(
          (restaurant) => (restaurant['docId'] ?? '').toString().isNotEmpty,
        )
        .toList(growable: false);
  }

  static List<Map<String, dynamic>> _applyLocalWorkedHereMinCounts(
    List<Map<String, dynamic>> restaurants,
    Map<String, int> localWorkedHereMinCounts,
  ) {
    if (localWorkedHereMinCounts.isEmpty) {
      return restaurants
          .map((item) => Map<String, dynamic>.from(item))
          .toList(growable: false);
    }

    return restaurants
        .map((restaurant) {
          final next = Map<String, dynamic>.from(restaurant);
          final docId = (next['docId'] ?? next['id'] ?? '').toString();
          final minCount = localWorkedHereMinCounts[docId];
          if (minCount != null) {
            next['worked_here_count'] = math.max(
              _asInt(next['worked_here_count']),
              minCount,
            );
          }
          return next;
        })
        .toList(growable: false);
  }

  static List<Map<String, dynamic>>? _updatedWorkedHereList(
    List<Map<String, dynamic>>? sourceList,
    String docId,
    int delta,
  ) {
    if (sourceList == null || sourceList.isEmpty) {
      return null;
    }

    var updated = false;
    final updatedList = sourceList
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);

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

    return updated ? updatedList : null;
  }

  static int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static double? _asDouble(dynamic value) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

  static Map<String, int> _readLocalWorkedHereMinCounts(
    SharedPreferences prefs,
  ) {
    final raw = prefs.getString(_localWorkedHereMinCountsKey);
    if (raw == null || raw.trim().isEmpty) {
      return <String, int>{};
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return <String, int>{};
      }
      final result = <String, int>{};
      decoded.forEach((key, value) {
        final docId = key.toString().trim();
        if (docId.isEmpty) return;
        result[docId] = _asInt(value);
      });
      return result;
    } catch (_) {
      return <String, int>{};
    }
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
