import 'dart:convert';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'restaurant_sqlite_store.dart';
import 'offline_bootstrap_service.dart';
import 'offline_state.dart';

class RestaurantsFirebaseSyncResult {
  const RestaurantsFirebaseSyncResult({
    required this.remoteCount,
    required this.localCount,
    required this.mergedCount,
    required this.didRun,
  });

  final int remoteCount;
  final int localCount;
  final int mergedCount;
  final bool didRun;
}

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

    if (needsVersionRefresh) {
      await _refreshRestaurantsFromBundledSeed(
        prefs,
        sqliteStore,
        currentAppVersion: currentAppVersion,
        localWorkedHereMinCounts: localWorkedHereMinCounts,
      );
    }

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

      if (!OfflineState.instance.isFirstLaunchDone) {
        await OfflineBootstrapService.instance.init();
        final bootstrapRestaurants = lightweight
            ? await sqliteStore.getAllForMap()
            : await sqliteStore.getAll();
        if (bootstrapRestaurants.isNotEmpty) {
          if (lightweight) {
            _primeMapMemoryCache(
              _applyLocalWorkedHereMinCounts(
                bootstrapRestaurants,
                localWorkedHereMinCounts,
              ),
              appVersion: currentAppVersion ?? cachedAppVersion,
            );
          } else {
            _primeMemoryCache(
              bootstrapRestaurants,
              synced: true,
              appVersion: currentAppVersion ?? cachedAppVersion,
            );
            _primeMapMemoryCache(
              _applyLocalWorkedHereMinCounts(
                _toMapRestaurantList(bootstrapRestaurants),
                localWorkedHereMinCounts,
              ),
              appVersion: currentAppVersion ?? cachedAppVersion,
            );
            if (!canUsePersistentCache || needsVersionRefresh) {
              await _persistRestaurantsCache(
                prefs,
                bootstrapRestaurants,
                appVersion: currentAppVersion,
              );
            }
          }
          debugPrint(
            '🗄️ SQLITE restaurants loaded after bootstrap${lightweight ? ' (lightweight)' : ''}: ${bootstrapRestaurants.length}',
          );
          return bootstrapRestaurants;
        }
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

  static Future<void> _refreshRestaurantsFromBundledSeed(
    SharedPreferences prefs,
    RestaurantSqliteStore store, {
    required String? currentAppVersion,
    required Map<String, int> localWorkedHereMinCounts,
  }) async {
    try {
      final seedRestaurants = await store.loadSeedAssetRestaurants();
      if (seedRestaurants.isEmpty) {
        debugPrint('⚠️ Bundled restaurants seed is empty; keeping local data');
        return;
      }

      await _persistRestaurantsCache(
        prefs,
        seedRestaurants,
        appVersion: currentAppVersion,
        localWorkedHereMinCounts: localWorkedHereMinCounts,
      );
      debugPrint(
        '📦 Bundled restaurants refreshed for app version $currentAppVersion: ${seedRestaurants.length}',
      );
    } catch (e) {
      debugPrint('⚠️ Bundled restaurants refresh skipped: $e');
    }
  }

  static Future<RestaurantsFirebaseSyncResult>
  syncRestaurantsFromFirebaseIfNeeded({bool force = false}) async {
    if (!force) {
      final store = RestaurantSqliteStore.instance;
      await store.init();
      final localCount = await store.count();
      return RestaurantsFirebaseSyncResult(
        remoteCount: 0,
        localCount: localCount,
        mergedCount: localCount,
        didRun: false,
      );
    }

    final prefs = await SharedPreferences.getInstance();
    final currentAppVersion = await _readCurrentAppVersion();
    final store = RestaurantSqliteStore.instance;
    await store.init();
    if (!await store.hasData) {
      await OfflineBootstrapService.instance.init();
    }

    final localRestaurants = await store.getAll();
    final remoteRestaurants = await _loadRestaurantsFromFirebase();
    final merged = mergeRestaurantLists(
      localRestaurants,
      remoteRestaurants,
      incomingWins: true,
    );

    await _persistRestaurantsCache(
      prefs,
      merged,
      appVersion: currentAppVersion,
    );

    debugPrint(
      '☁️ Restaurants Firebase sync: remote ${remoteRestaurants.length}, local ${localRestaurants.length}, merged ${merged.length}',
    );

    return RestaurantsFirebaseSyncResult(
      remoteCount: remoteRestaurants.length,
      localCount: localRestaurants.length,
      mergedCount: merged.length,
      didRun: true,
    );
  }

  static Future<void> upsertRestaurantsToFirebase(
    List<Map<String, dynamic>> restaurants,
  ) async {
    final rows = restaurants
        .map((item) => Map<String, dynamic>.from(item))
        .where((item) => _firebaseDocIdForRestaurant(item).isNotEmpty)
        .toList(growable: false);
    if (rows.isEmpty) return;

    for (var start = 0; start < rows.length; start += 450) {
      final end = math.min(start + 450, rows.length);
      final batch = _firestore.batch();
      for (final row in rows.sublist(start, end)) {
        final docId = _firebaseDocIdForRestaurant(row);
        if (docId.isEmpty) continue;
        final data = _sanitizeForJson(row);
        data.removeWhere(
          (key, value) =>
              value is String &&
              value.trim().isEmpty &&
              key != 'id' &&
              key != 'docId',
        );
        data['id'] = docId;
        data['docId'] = docId;
        data['updated_at'] = FieldValue.serverTimestamp();
        data['synced_from'] = (data['source'] ?? '').toString().isEmpty
            ? 'app'
            : data['source'];
        batch.set(
          _firestore.collection('restaurants').doc(docId),
          data,
          SetOptions(merge: true),
        );
      }
      await batch.commit();
    }
  }

  static Future<List<Map<String, dynamic>>>
  _loadRestaurantsFromFirebase() async {
    final snapshot = await _firestore.collection('restaurants').get();
    return snapshot.docs
        .map((doc) {
          final data = Map<String, dynamic>.from(doc.data());
          data['id'] = (data['id'] ?? doc.id).toString();
          data['docId'] = doc.id;
          return _sanitizeForJson(data);
        })
        .toList(growable: false);
  }

  static List<Map<String, dynamic>> mergeRestaurantLists(
    List<Map<String, dynamic>> base,
    List<Map<String, dynamic>> incoming, {
    bool incomingWins = false,
  }) {
    final merged = base
        .map((item) => Map<String, dynamic>.from(item))
        .where((item) => _localIdForRestaurant(item).isNotEmpty)
        .toList(growable: true);
    final indexById = <String, int>{};
    final indexBySource = <String, int>{};

    for (var i = 0; i < merged.length; i++) {
      final id = _localIdForRestaurant(merged[i]);
      if (id.isNotEmpty) indexById[id] = i;
      final sourceId = (merged[i]['source_place_id'] ?? '').toString();
      if (sourceId.isNotEmpty) indexBySource[sourceId] = i;
    }

    for (final row in incoming) {
      final normalized = Map<String, dynamic>.from(row);
      final incomingId = _localIdForRestaurant(normalized);
      if (incomingId.isNotEmpty) {
        normalized['id'] = incomingId;
        normalized['docId'] = incomingId;
      }
      final sourceId = (normalized['source_place_id'] ?? '').toString();
      final existingIndex =
          (sourceId.isNotEmpty ? indexBySource[sourceId] : null) ??
          (incomingId.isNotEmpty ? indexById[incomingId] : null) ??
          _findNearbyDuplicateIndex(merged, normalized);

      if (existingIndex != null) {
        merged[existingIndex] = _mergeRestaurantRecord(
          merged[existingIndex],
          normalized,
          incomingWins: incomingWins,
        );
        final mergedId = _localIdForRestaurant(merged[existingIndex]);
        if (mergedId.isNotEmpty) indexById[mergedId] = existingIndex;
        final mergedSourceId = (merged[existingIndex]['source_place_id'] ?? '')
            .toString();
        if (mergedSourceId.isNotEmpty) {
          indexBySource[mergedSourceId] = existingIndex;
        }
        continue;
      }

      if (incomingId.isEmpty) continue;
      final nextIndex = merged.length;
      merged.add(normalized);
      indexById[incomingId] = nextIndex;
      if (sourceId.isNotEmpty) indexBySource[sourceId] = nextIndex;
    }

    return merged;
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
      throw ArgumentError('Document ID is empty or invalid');
    }
    await _firestore.collection('restaurants').doc(docId).set({
      'worked_here_count': FieldValue.increment(1),
      'worked_here_updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // 🔹 Redueix el comptador "worked_here_count" si algú vol treure-ho
  static Future<void> decrementWorkedHere(String docId) async {
    if (docId.trim().isEmpty) {
      throw ArgumentError('Document ID is empty or invalid');
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
            'source_place_id': (restaurant['source_place_id'] ?? '').toString(),
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

  static String _firebaseDocIdForRestaurant(Map<String, dynamic> restaurant) {
    final preferred = _localIdForRestaurant(restaurant);
    final raw = preferred.isNotEmpty
        ? preferred
        : (restaurant['name'] ?? '').toString();
    return raw
        .trim()
        .replaceAll(RegExp(r'[\/.#\$\[\]]'), '-')
        .replaceAll(RegExp(r'\s+'), '_')
        .replaceAll(RegExp(r'_{2,}'), '_');
  }

  static String _localIdForRestaurant(Map<String, dynamic> restaurant) {
    return (restaurant['docId'] ?? restaurant['id'] ?? '').toString().trim();
  }

  static Map<String, dynamic> _mergeRestaurantRecord(
    Map<String, dynamic> existing,
    Map<String, dynamic> incoming, {
    required bool incomingWins,
  }) {
    final merged = Map<String, dynamic>.from(existing);
    incoming.forEach((key, value) {
      if (key == 'id' || key == 'docId') {
        if (_localIdForRestaurant(merged).isEmpty && _isUsefulValue(value)) {
          merged[key] = value;
        }
        return;
      }

      if (key == 'worked_here_count') {
        merged[key] = math.max(_asInt(merged[key]), _asInt(value));
        return;
      }

      final current = merged[key];
      final incomingIsUseful = _isUsefulValue(value);
      if (!incomingIsUseful) return;

      final currentIsEmpty = !_isUsefulValue(current);
      final shouldReplace =
          incomingWins ||
          currentIsEmpty ||
          _shouldReplaceWeakValue(key, current);
      if (shouldReplace) {
        merged[key] = value;
      }
    });

    final id = _localIdForRestaurant(merged);
    if (id.isNotEmpty) {
      merged['id'] = id;
      merged['docId'] = id;
    }
    return merged;
  }

  static bool _isUsefulValue(dynamic value) {
    if (value == null) return false;
    if (value is String) return value.trim().isNotEmpty;
    if (value is Iterable) return value.isNotEmpty;
    if (value is Map) return value.isNotEmpty;
    return true;
  }

  static bool _shouldReplaceWeakValue(String key, dynamic current) {
    if (key != 'website' || current is! String) return false;
    final lower = current.toLowerCase();
    return lower.contains('facebook.com') ||
        lower.contains('instagram.com') ||
        lower.contains('tripadvisor.') ||
        lower.contains('ubereats.') ||
        lower.contains('doordash.') ||
        lower.contains('menulog.') ||
        lower.contains('yellowpages.') ||
        lower.contains('restaurantguru.');
  }

  static int? _findNearbyDuplicateIndex(
    List<Map<String, dynamic>> existing,
    Map<String, dynamic> candidate,
  ) {
    final candidateName = _normalizeRestaurantName(candidate['name']);
    final candidatePostcode =
        (candidate['postcode_display'] ?? candidate['postcode'] ?? '')
            .toString()
            .padLeft(4, '0');
    final candidateLat = _asDouble(candidate['latitude'] ?? candidate['lat']);
    final candidateLng = _asDouble(candidate['longitude'] ?? candidate['lng']);
    if (candidateName.isEmpty || candidateLat == null || candidateLng == null) {
      return null;
    }

    for (var index = 0; index < existing.length; index++) {
      final row = existing[index];
      if (_normalizeRestaurantName(row['name']) != candidateName) continue;
      final rowPostcode = (row['postcode_display'] ?? row['postcode'] ?? '')
          .toString()
          .padLeft(4, '0');
      if (rowPostcode != candidatePostcode) continue;
      final rowLat = _asDouble(row['latitude'] ?? row['lat']);
      final rowLng = _asDouble(row['longitude'] ?? row['lng']);
      if (rowLat == null || rowLng == null) continue;
      if (_distanceMeters(candidateLat, candidateLng, rowLat, rowLng) <= 120) {
        return index;
      }
    }
    return null;
  }

  static String _normalizeRestaurantName(dynamic name) {
    return name.toString().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  static double _distanceMeters(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    const earthRadiusMeters = 6371000.0;
    final latDelta = (lat2 - lat1) * math.pi / 180;
    final lngDelta = (lng2 - lng1) * math.pi / 180;
    final a =
        math.sin(latDelta / 2) * math.sin(latDelta / 2) +
        math.cos(lat1 * math.pi / 180) *
            math.cos(lat2 * math.pi / 180) *
            math.sin(lngDelta / 2) *
            math.sin(lngDelta / 2);
    return earthRadiusMeters * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
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
