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
      maxNrOfCacheObjects:
          12000, // more tiles cached for faster high-zoom near cities
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
    const maxZoom =
        12; // include closer city-level zooms for faster initial loads
    final futures = <Future<void>>[];

    for (int z = minZoom; z <= maxZoom; z++) {
      final range = _tileRangeForBounds(
        south: south,
        west: west,
        north: north,
        east: east,
        zoom: z,
      );
      for (int x = range.minX; x <= range.maxX; x++) {
        for (int y = range.minY; y <= range.maxY; y++) {
          final url = 'https://tile.openstreetmap.org/$z/$x/$y.png';
          futures.add(
            _cache!
                .downloadFile(url, key: url, force: false)
                .then((_) {}, onError: (_) {}),
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
    final y = ((1.0 - log(tan(latRad) + 1 / cos(latRad)) / pi) / 2.0 * n)
        .floor();
    return _TileXY(x, y);
  }

  String _tileUrlFromTemplate(String template, int z, int x, int y) {
    return template
        .replaceAll('{z}', '$z')
        .replaceAll('{x}', '$x')
        .replaceAll('{y}', '$y');
  }

  Future<void> prefetchArea(
    LatLng center,
    int zoom, {
    String urlTemplate = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    double spanDeg = 2.0,
    int maxTiles = 200,
  }) async {
    if (_cache == null) return;
    // Quantize key to avoid spamming same area
    final qLat = (center.latitude / 0.5).round() * 0.5;
    final qLon = (center.longitude / 0.5).round() * 0.5;
    final key = '${urlTemplate.hashCode}_${zoom}_${qLat}_$qLon';
    if (_areaPrefetched.contains(key)) return;
    _areaPrefetched.add(key);

    final south = center.latitude - spanDeg;
    final north = center.latitude + spanDeg;
    final west = center.longitude - spanDeg;
    final east = center.longitude + spanDeg;

    final range = _tileRangeForBounds(
      south: south,
      west: west,
      north: north,
      east: east,
      zoom: zoom,
    );

    int count = 0;
    for (int x = range.minX; x <= range.maxX; x++) {
      for (int y = range.minY; y <= range.maxY; y++) {
        if (count >= maxTiles) return;
        final url = _tileUrlFromTemplate(urlTemplate, zoom, x, y);
        unawaited(
          _cache!
              .downloadFile(url, key: url, force: false)
              .then((_) {}, onError: (_) {}),
        );
        count++;
      }
    }
  }

  ({int minX, int maxX, int minY, int maxY}) _tileRangeForBounds({
    required double south,
    required double west,
    required double north,
    required double east,
    required int zoom,
  }) {
    final southWest = _latLngToTile(south, west, zoom);
    final northEast = _latLngToTile(north, east, zoom);
    return (
      minX: min(southWest.x, northEast.x),
      maxX: max(southWest.x, northEast.x),
      minY: min(southWest.y, northEast.y),
      maxY: max(southWest.y, northEast.y),
    );
  }
}

class _TileXY {
  final int x;
  final int y;
  const _TileXY(this.x, this.y);
}
