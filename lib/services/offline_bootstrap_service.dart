import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'dart:io';

import 'offline_state.dart';
import 'restaurant_local_store.dart';

class OfflineBootstrapService {
  OfflineBootstrapService._();
  static final OfflineBootstrapService instance = OfflineBootstrapService._();

  static const _prefsFirstLaunchKey = 'first_launch_completed_v2';

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final store = RestaurantLocalStore.instance;
    await store.init();

    final connectivity = await Connectivity().checkConnectivity();
    final hasInternet = connectivity.any((r) => r != ConnectivityResult.none);

    final wasCompleted = prefs.getBool(_prefsFirstLaunchKey) ?? false;
    OfflineState.instance.isFirstLaunchDone = wasCompleted;
    OfflineState.instance.isOfflineMode = !hasInternet;

    if (!wasCompleted && hasInternet) {
      await _preloadRestaurants();
      await prefs.setBool(_prefsFirstLaunchKey, true);
      OfflineState.instance.isFirstLaunchDone = true;
    }

    await _ensureTileCache();
  }

  Future<void> _preloadRestaurants() async {
    final firestore = FirebaseFirestore.instance;
    final snapshot = await firestore.collection('restaurants').get();

    final restaurants = snapshot.docs.map((doc) {
      final data = doc.data();
      data['id'] = doc.id;
      return RestaurantLocal.fromJson(data);
    }).where((r) => r.hasContact).toList();

    if (restaurants.isNotEmpty) {
      await RestaurantLocalStore.instance.saveAll(restaurants);
    }
  }

  Future<void> _ensureTileCache() async {
    final dir = await getApplicationSupportDirectory();
    final tilesDir = Directory(p.join(dir.path, 'osm_tiles'));
    if (!tilesDir.existsSync()) {
      await tilesDir.create(recursive: true);
    }
    OfflineState.instance.tileCachePath = tilesDir.path;

    final connectivity = await Connectivity().checkConnectivity();
    final hasInternet = connectivity.any((r) => r != ConnectivityResult.none);
    if (!hasInternet) return;

    // Prefetch tiles for Australia (moderate zooms) in background.
    unawaited(_prefetchAustraliaTiles(tilesDir));
  }

  Future<void> _prefetchAustraliaTiles(Directory tilesDir) async {
    final client = http.Client();
    // Moderate zooms to keep size reasonable but avoid grey patches.
    const minZoom = 3;
    const maxZoom = 10;
    // Rough Australia bounds.
    const latMin = -45.0;
    const latMax = -9.0;
    const lonMin = 110.0;
    const lonMax = 155.0;

    try {
      await _prefetchBox(client, tilesDir,
          lonMin: lonMin,
          lonMax: lonMax,
          latMin: latMin,
          latMax: latMax,
          minZoom: minZoom,
          maxZoom: maxZoom,
          maxTiles: 4500);

      // Focused higher-zoom around main populated east/south regions.
      const focusBoxes = [
        // Sydney
        {'latMin': -35.0, 'latMax': -32.5, 'lonMin': 149.0, 'lonMax': 152.5},
        // Melbourne
        {'latMin': -39.5, 'latMax': -36.5, 'lonMin': 143.5, 'lonMax': 146.5},
        // Brisbane/Gold Coast
        {'latMin': -29.5, 'latMax': -25.5, 'lonMin': 151.0, 'lonMax': 154.5},
        // Perth
        {'latMin': -33.5, 'latMax': -30.0, 'lonMin': 114.5, 'lonMax': 116.5},
      ];
      for (final box in focusBoxes) {
        await _prefetchBox(
          client,
          tilesDir,
          lonMin: box['lonMin'] as double,
          lonMax: box['lonMax'] as double,
          latMin: box['latMin'] as double,
          latMax: box['latMax'] as double,
          minZoom: 11,
          maxZoom: 13,
          maxTiles: 2200,
        );
      }
    } finally {
      client.close();
    }
  }

  Future<void> _prefetchBox(
    http.Client client,
    Directory tilesDir, {
    required double lonMin,
    required double lonMax,
    required double latMin,
    required double latMax,
    required int minZoom,
    required int maxZoom,
    required int maxTiles,
  }) async {
    int fetched = 0;
    for (var z = minZoom; z <= maxZoom; z++) {
      final xMin = _lon2tile(lonMin, z);
      final xMax = _lon2tile(lonMax, z);
      final yMin = _lat2tile(latMax, z); // note: lat max to min inverted
      final yMax = _lat2tile(latMin, z);

      for (var x = xMin; x <= xMax; x++) {
        for (var y = yMin; y <= yMax; y++) {
          if (fetched >= maxTiles) return;
          final file = File(p.join(tilesDir.path, '$z', '$x', '$y.png'));
          if (file.existsSync()) continue;
          try {
            final url = 'https://tile.openstreetmap.org/$z/$x/$y.png';
            final resp = await client.get(Uri.parse(url)).timeout(const Duration(seconds: 8));
            if (resp.statusCode == 200) {
              await file.parent.create(recursive: true);
              await file.writeAsBytes(resp.bodyBytes, flush: true);
              fetched++;
            }
          } catch (_) {
            // Ignore single tile failures.
          }
        }
      }
    }
  }

  int _lon2tile(double lon, int zoom) =>
      ((lon + 180.0) / 360.0 * (1 << zoom)).floor();
  int _lat2tile(double lat, int zoom) {
    final rad = lat * pi / 180.0;
    return ((1.0 - log(tan(rad) + 1 / cos(rad)) / pi) / 2.0 * (1 << zoom))
        .floor();
  }
}
