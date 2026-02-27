import 'dart:async';
import 'dart:math';

import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TileCacheService {
  TileCacheService._();
  static final TileCacheService instance = TileCacheService._();

  static const _cacheKey = 'osmTileCache';
  static const _prefetchDoneKey = 'osm_prefetch_done';

  BaseCacheManager? _cache;
  Future<BaseCacheManager>? _initFuture;
  final Set<String> _areaPrefetched = {};

  Future<BaseCacheManager> init() {
    _initFuture ??= _createCache();
    return _initFuture!;
  }

  Future<BaseCacheManager> _createCache() async {
    final config = Config(
      _cacheKey,
      stalePeriod: const Duration(days: 30),
      maxNrOfCacheObjects: 12000, // more tiles cached for faster high-zoom near cities
      repo: JsonCacheInfoRepository(databaseName: '$_cacheKey.db'),
      fileService: HttpFileService(),
    );
    _cache = CacheManager(config);
    unawaited(_prefetchAustraliaIfNeeded());
    return _cache!;
  }

  BaseCacheManager? get cache => _cache;

  Future<void> _prefetchAustraliaIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    final done = prefs.getBool(_prefetchDoneKey) ?? false;
    if (done) return;

    const west = 112.0;
    const south = -44.0;
    const east = 154.0;
    const north = -10.0;
    const minZoom = 4;
    const maxZoom = 12; // include closer city-level zooms for faster initial loads
    final futures = <Future<void>>[];

    for (int z = minZoom; z <= maxZoom; z++) {
      final topLeft = _latLngToTile(south, west, z);
      final bottomRight = _latLngToTile(north, east, z);
      for (int x = topLeft.x; x <= bottomRight.x; x++) {
        for (int y = topLeft.y; y <= bottomRight.y; y++) {
          final url = 'https://tile.openstreetmap.org/$z/$x/$y.png';
          futures.add(
            _cache!.downloadFile(url, key: url, force: false).then((_) {}, onError: (_) {}),
          );
        }
      }
    }

    await Future.wait(futures, eagerError: false);
    await prefs.setBool(_prefetchDoneKey, true);
  }

  _TileXY _latLngToTile(double lat, double lon, int zoom) {
    final latRad = lat * pi / 180;
    final n = pow(2.0, zoom);
    final x = ((lon + 180.0) / 360.0 * n).floor();
    final y = ((1.0 - log(tan(latRad) + 1 / cos(latRad)) / pi) / 2.0 * n).floor();
    return _TileXY(x, y);
  }

  Future<void> prefetchArea(LatLng center, int zoom, {double spanDeg = 2.0, int maxTiles = 200}) async {
    if (_cache == null) return;
    // Quantize key to avoid spamming same area
    final qLat = (center.latitude / 0.5).round() * 0.5;
    final qLon = (center.longitude / 0.5).round() * 0.5;
    final key = '${zoom}_${qLat}_$qLon';
    if (_areaPrefetched.contains(key)) return;
    _areaPrefetched.add(key);

    final south = center.latitude - spanDeg;
    final north = center.latitude + spanDeg;
    final west = center.longitude - spanDeg;
    final east = center.longitude + spanDeg;

    final topLeft = _latLngToTile(south, west, zoom);
    final bottomRight = _latLngToTile(north, east, zoom);

    int count = 0;
    for (int x = topLeft.x; x <= bottomRight.x; x++) {
      for (int y = topLeft.y; y <= bottomRight.y; y++) {
        if (count >= maxTiles) return;
        final url = 'https://tile.openstreetmap.org/$zoom/$x/$y.png';
        unawaited(_cache!.downloadFile(url, key: url, force: false).then((_) {}, onError: (_) {}));
        count++;
      }
    }
  }
}

class _TileXY {
  final int x;
  final int y;
  const _TileXY(this.x, this.y);
}
