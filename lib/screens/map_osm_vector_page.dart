import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_marker_cluster/flutter_map_marker_cluster.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:vector_map_tiles/vector_map_tiles.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';

import '../config/maptiler_config.dart';
import '../widgets/map_place_popup.dart';
import '../services/harvest_places_service.dart';
import '../services/map_markers_service.dart';
import '../services/overlay_helper.dart';
import '../services/favorites_service.dart';
import '../services/email_sender_service.dart';
import 'favorites_screen.dart';
import 'mail_setup_page.dart';
import 'report_message_page.dart';
import 'admin_page.dart';
import '../config/admin_config.dart';
import 'package:mywhv/screens/_pin_tail_painter.dart';

enum MapStyleChoice { streets, minimal }

enum Category { hospitality, farm }

enum _RestaurantMarkerKind { standard, night, cafe }

class MapOSMVectorPage extends StatefulWidget {
  const MapOSMVectorPage({super.key});

  @override
  State<MapOSMVectorPage> createState() => MapOSMVectorPageState();
}

final Map<String, Style> _styleCache = {};
final Map<String, TileProviders> _tileProvidersCache = {};

class MapOSMVectorPageState extends State<MapOSMVectorPage>
    with TickerProviderStateMixin {
  final MapController _mapController = MapController();
  static const LatLng _defaultCenter = LatLng(-25.0, 133.0);
  static const double _defaultZoom = 4.5;
  LatLng _initialCenter = _defaultCenter;
  double _initialZoom = _defaultZoom;
  final bool _showAllRestaurants = false;
  bool _farmMapEnabled = false;
  late final String streetsStyleUrl;
  late final String minimalStyleUrl;

  List<Map<String, Object?>> _restaurantLocations = [];
  List<Map<String, Object?>> _visibleRestaurantLocations = [];
  final List<Map<String, Object?>> _harvestLocations = [];
  List<Marker> _markers = [];
  bool _isHospitality = true;
  bool _isLoadingData = true;
  bool _isTileLoading = true;
  Timer? _tileLoadingTimeout;
  DateTime? _tileLoadingStartedAt;
  LatLng _currentCenter = _defaultCenter;
  double _currentZoom = _defaultZoom;
  bool _mapReady = false;
  LatLng? _pendingCenter;
  double? _pendingZoom;
  Set<String> _favoritePlaces = {};
  StreamSubscription<Set<String>>? _favoritesSub;
  bool _isLocating = false;
  Timer? _zoomPrefetchDebounce;
  bool _isZoomPrefetchRunning = false;
  final Queue<String> _prefetchedTileKeysQueue = Queue<String>();
  final Set<String> _prefetchedTileKeysSet = <String>{};
  final Set<String> _selectedSources = {};
  dynamic _originalOnError;
  Timer? _persistDebounce;
  final List<Map<String, dynamic>> _sourceOptions = const [
    {'key': 'gmail', 'label': 'Gmail', 'icon': Icons.email},
    {'key': 'facebook', 'label': 'Facebook', 'icon': Icons.facebook},
    {'key': 'instagram', 'label': 'IG', 'icon': Icons.camera_alt},
    {'key': 'careers', 'label': 'Careers', 'icon': Icons.work},
  ];
  final LayerLink _filterLink = LayerLink();
  OverlayEntry? _filterOverlay;
  late final AnimationController _kangarooController;
  late final AnimationController _tooltipController;
  late final AnimationController _pulseController;
  late final Widget _markerFavoriteIcon;
  late final Widget _markerFavoriteSelectedIcon;
  late final Widget _markerNightIcon;
  late final Widget _markerNightSelectedIcon;
  late final Widget _markerCafeIcon;
  late final Widget _markerCafeSelectedIcon;
  late final Widget _markerStandardIcon;
  late final Widget _markerStandardSelectedIcon;
  late final Widget _markerHarvestIcon;
  OverlayEntry? _profileTooltip;
  Timer? _tooltipTimer;
  final GlobalKey _profileButtonKey = GlobalKey();
  final GlobalKey _categorySwitchKey = GlobalKey();

  Map<String, dynamic>? _selectedRestaurant;
  HarvestPlace? _selectedHarvest;
  Future<Style>? _styleFuture;
  final MapStyleChoice _styleChoice = MapStyleChoice.streets;
  String get _selectedStyleUrl => _styleChoice == MapStyleChoice.streets
      ? streetsStyleUrl
      : minimalStyleUrl;
  bool _didKickstartRender = false;
  Future<Directory>? _vectorCacheFolderFuture;
  static const int _maxPrefetchTilesPerZoom = 28;
  static const int _maxPrefetchedTileKeys = 2400;

  bool _isOfflineError(Object? error) {
    final msg = error.toString().toLowerCase();
    return msg.contains('socketexception') ||
        msg.contains('failed host lookup') ||
        msg.contains('no address associated with hostname') ||
        msg.contains('internet');
  }

  bool _setEquals(Set<String> a, Set<String> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (final value in a) {
      if (!b.contains(value)) return false;
    }
    return true;
  }

  TileProviders _optimizedTileProviders(Style style) {
    final styleKey = _selectedStyleUrl;
    return _tileProvidersCache.putIfAbsent(styleKey, () {
      final bySource = <String, VectorTileProvider>{};
      style.providers.tileProviderBySource.forEach((source, provider) {
        if (provider.type == TileProviderType.vector) {
          bySource[source] = MemoryCacheVectorTileProvider(
            delegate: provider,
            maxSizeBytes: 12 * 1024 * 1024,
          );
        } else {
          bySource[source] = provider;
        }
      });
      return TileProviders(bySource);
    });
  }

  int _lonToTileX(double lon, int zoom) {
    final n = 1 << zoom;
    final x = ((lon + 180.0) / 360.0 * n).floor();
    return x.clamp(0, n - 1).toInt();
  }

  int _latToTileY(double lat, int zoom) {
    final clampedLat = lat.clamp(-85.05112878, 85.05112878).toDouble();
    final latRad = clampedLat * math.pi / 180.0;
    final n = 1 << zoom;
    final y =
        ((1.0 - math.log(math.tan(latRad) + 1 / math.cos(latRad)) / math.pi) /
                2.0 *
                n)
            .floor();
    return y.clamp(0, n - 1).toInt();
  }

  ({int minX, int maxX, int minY, int maxY}) _tileRangeForBounds(
    LatLngBounds bounds,
    int zoom, {
    int padding = 0,
  }) {
    final n = 1 << zoom;
    final minX = (_lonToTileX(bounds.west, zoom) - padding).clamp(0, n - 1);
    final maxX = (_lonToTileX(bounds.east, zoom) + padding).clamp(0, n - 1);
    final minY = (_latToTileY(bounds.north, zoom) - padding).clamp(0, n - 1);
    final maxY = (_latToTileY(bounds.south, zoom) + padding).clamp(0, n - 1);
    return (
      minX: minX.toInt(),
      maxX: maxX.toInt(),
      minY: minY.toInt(),
      maxY: maxY.toInt(),
    );
  }

  void _rememberPrefetchedTileKey(String key) {
    if (!_prefetchedTileKeysSet.add(key)) return;
    _prefetchedTileKeysQueue.addLast(key);
    if (_prefetchedTileKeysQueue.length <= _maxPrefetchedTileKeys) return;
    final evicted = _prefetchedTileKeysQueue.removeFirst();
    _prefetchedTileKeysSet.remove(evicted);
  }

  void _scheduleAdjacentZoomPrefetch(TileProviders tileProviders) {
    if (!_isHospitality || !_mapReady) return;
    _zoomPrefetchDebounce?.cancel();
    _zoomPrefetchDebounce = Timer(const Duration(milliseconds: 650), () {
      unawaited(_prefetchAdjacentZoomTiles(tileProviders));
    });
  }

  Future<void> _prefetchAdjacentZoomTiles(TileProviders tileProviders) async {
    if (!_mapReady || !_isHospitality || _isZoomPrefetchRunning) return;
    _isZoomPrefetchRunning = true;
    try {
      final camera = _mapController.camera;
      if (camera.nonRotatedSize.x <= 0 || camera.nonRotatedSize.y <= 0) return;

      final bounds = camera.visibleBounds;
      final currentZoom = camera.zoom.round().clamp(3, 18);
      final targetZooms = <int>{
        (currentZoom - 1).clamp(3, 18).toInt(),
        (currentZoom + 1).clamp(3, 18).toInt(),
      }..remove(currentZoom);

      for (final zoom in targetZooms) {
        final range = _tileRangeForBounds(bounds, zoom, padding: 1);
        int queuedTiles = 0;

        for (
          int x = range.minX;
          x <= range.maxX && queuedTiles < _maxPrefetchTilesPerZoom;
          x++
        ) {
          for (
            int y = range.minY;
            y <= range.maxY && queuedTiles < _maxPrefetchTilesPerZoom;
            y++
          ) {
            final tile = TileIdentity(zoom, x, y).normalize();
            var requestedForTile = false;

            for (final entry in tileProviders.tileProviderBySource.entries) {
              final provider = entry.value;
              if (provider.type != TileProviderType.vector) continue;

              final key =
                  '$_selectedStyleUrl|${entry.key}|$zoom|${tile.x}|${tile.y}';
              if (_prefetchedTileKeysSet.contains(key)) continue;

              _rememberPrefetchedTileKey(key);
              requestedForTile = true;
              unawaited(provider.provide(tile).then((_) {}, onError: (_) {}));
            }

            if (requestedForTile) queuedTiles++;
          }
        }
      }
    } finally {
      _isZoomPrefetchRunning = false;
    }
  }

  @override
  void initState() {
    super.initState();
    streetsStyleUrl =
        'https://api.maptiler.com/maps/base-v4/style.json?key=$mapTilerKey';
    minimalStyleUrl =
        'https://api.maptiler.com/maps/bright/style.json?key=$mapTilerKey';
    _kangarooController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
      lowerBound: 0.9,
      upperBound: 1.05,
    )..repeat(reverse: true);
    _tooltipController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
      lowerBound: 0.94,
      upperBound: 1.08,
    );
    _markerFavoriteIcon = _pinMarker(
      fill: Colors.pinkAccent,
      icon: Icons.favorite,
      iconSize: 15,
    );
    _markerFavoriteSelectedIcon = _pinMarker(
      fill: Colors.pinkAccent,
      icon: Icons.favorite,
      iconSize: 15,
      outlineColor: const Color(0xFFE53935),
    );
    _markerNightIcon = _pinMarker(
      fill: const Color(0xFF6D28D9),
      icon: Icons.local_bar,
      iconSize: 16,
    );
    _markerNightSelectedIcon = _pinMarker(
      fill: const Color(0xFF6D28D9),
      icon: Icons.local_bar,
      iconSize: 16,
      outlineColor: const Color(0xFFE53935),
    );
    _markerCafeIcon = _pinMarker(
      fill: const Color(0xFF111827),
      icon: Icons.local_cafe,
      iconSize: 16,
    );
    _markerCafeSelectedIcon = _pinMarker(
      fill: const Color(0xFF111827),
      icon: Icons.local_cafe,
      iconSize: 16,
      outlineColor: const Color(0xFFE53935),
    );
    _markerStandardIcon = _pinMarker(
      fill: const Color(0xFFFF8A00),
      icon: Icons.restaurant,
      iconSize: 16,
    );
    _markerStandardSelectedIcon = _pinMarker(
      fill: const Color(0xFFFF8A00),
      icon: Icons.restaurant,
      iconSize: 16,
      outlineColor: const Color(0xFFE53935),
    );
    _markerHarvestIcon = Icon(
      Icons.location_on,
      color: Colors.green.shade700,
      size: 26,
    );
    _originalOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.exceptionAsString().contains('Cancelled')) {
        return; // silence benign cancellation logs
      }
      _originalOnError?.call(details);
    };
    _styleFuture = _loadStyle();
    _loadFavorites();
    _favoritesSub = FavoritesService.changes.listen((ids) {
      if (_setEquals(_favoritePlaces, ids)) return;
      _favoritePlaces = ids;
      _updateMarkers();
    });
    _loadLastMapPosition();
    _loadInitialData();
  }

  @override
  void dispose() {
    _kangarooController.dispose();
    _tooltipController.dispose();
    _pulseController.dispose();
    _removeProfileTooltip();
    _persistDebounce?.cancel();
    _tileLoadingTimeout?.cancel();
    _zoomPrefetchDebounce?.cancel();
    _favoritesSub?.cancel();
    _closeFilterOverlay();
    FlutterError.onError = _originalOnError;
    super.dispose();
  }

  Widget _kangarooLoader({double size = 48, bool animate = true}) {
    final child = SizedBox(
      height: size,
      width: size,
      child: Image.asset(
        'assets/source.gif',
        fit: BoxFit.contain,
        gaplessPlayback: false,
      ),
    );
    if (!animate) return child;
    return ScaleTransition(scale: _kangarooController, child: child);
  }

  Future<Style> _loadStyle() async {
    if (!hasMapTilerKey) {
      throw Exception(
        'Missing MAPTILER_KEY. Run: flutter run --dart-define=MAPTILER_KEY=xxxx',
      );
    }
    final styleUrl = _selectedStyleUrl;
    if (_styleCache.containsKey(styleUrl)) return _styleCache[styleUrl]!;
    try {
      final style = await StyleReader(uri: styleUrl).read();
      _styleCache[styleUrl] = style;
      return style;
    } catch (e) {
      throw Exception('Could not load the MapTiler style: $e');
    }
  }

  Future<Directory> _resolveVectorCacheFolder() {
    return _vectorCacheFolderFuture ??= () async {
      final root = await getApplicationSupportDirectory();
      final folder = Directory('${root.path}/vector_map_cache');
      if (!folder.existsSync()) {
        await folder.create(recursive: true);
      }
      return folder;
    }();
  }

  void _reloadStyle() {
    setState(() {
      _styleFuture = _loadStyle();
    });
  }

  Future<void> _loadInitialData() async {
    setState(() => _isLoadingData = true);
    await _loadData(fromServer: false);
    if (mounted) {
      setState(() {
        _isLoadingData = false;
        _isTileLoading = false;
      });
    }
  }

  Future<void> _loadFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList('favorite_places') ?? [];
    final next = list.toSet();
    if (_setEquals(_favoritePlaces, next)) return;
    _favoritePlaces = next;
    _updateMarkers();
  }

  Future<void> _loadLastMapPosition() async {
    final prefs = await SharedPreferences.getInstance();
    final lat = prefs.getDouble('map_last_lat');
    final lng = prefs.getDouble('map_last_lng');
    final zoom = prefs.getDouble('map_last_zoom');

    if (lat != null && lng != null && zoom != null) {
      final clampedZoom = zoom.clamp(6.0, 12.0).toDouble();
      final center = LatLng(lat, lng);
      setState(() {
        _initialCenter = center;
        _initialZoom = clampedZoom;
        _currentCenter = center;
        _currentZoom = clampedZoom;
        _pendingCenter = center;
        _pendingZoom = clampedZoom;
      });
      if (_mapReady) {
        _mapController.move(center, clampedZoom);
        _pendingCenter = null;
        _pendingZoom = null;
      }
    }
  }

  Future<void> _saveLastMapPosition(LatLng center, double zoom) async {
    final prefs = await SharedPreferences.getInstance();
    final clampedZoom = zoom.clamp(6.0, 12.0).toDouble();
    await prefs.setDouble('map_last_lat', center.latitude);
    await prefs.setDouble('map_last_lng', center.longitude);
    await prefs.setDouble('map_last_zoom', clampedZoom);
  }

  Future<void> _loadData({required bool fromServer}) async {
    try {
      final restaurantDocs = await MapMarkersService.loadRestaurants(
        fromServer: fromServer,
      );
      if (restaurantDocs.isNotEmpty) {
        _restaurantLocations = _buildRestaurantLocations(restaurantDocs);
      } else if (!fromServer) {
        final seeded = await _loadSeedRestaurantsFromAsset();
        if (seeded.isNotEmpty) {
          _restaurantLocations = _buildRestaurantLocations(seeded);
        }
      }
    } catch (e) {
      debugPrint('❌ Error restaurants OSM vector: $e');
    }

    // Harvest loading paused

    _recomputeVisibleRestaurants();
    _updateMarkers();
  }

  List<Map<String, Object?>> _buildRestaurantLocations(
    List<Map<String, dynamic>> docs,
  ) {
    final List<Map<String, Object?>> locations = [];

    for (final data in docs) {
      final double? lat = (data['latitude'] ?? data['lat'])?.toDouble();
      final double? lng = (data['longitude'] ?? data['lng'])?.toDouble();
      if (lat == null || lng == null) continue;

      final docId = (data['docId'] ?? '').toString();
      if (docId.isEmpty) continue;
      if (data['blocked'] == true) continue;
      final hasData =
          ((data['facebook_url'] ?? '').toString().isNotEmpty ||
          (data['instagram_url'] ?? '').toString().isNotEmpty ||
          (data['email'] ?? '').toString().isNotEmpty ||
          (data['careers_page'] ?? '').toString().isNotEmpty);
      if (!_showAllRestaurants && !hasData) continue;

      locations.add({
        'id': docId,
        'lat': lat,
        'lng': lng,
        'data': data,
        'worked_here_count': data['worked_here_count'] ?? 0,
        'sources': _extractSources(data),
        'marker_kind': _classifyRestaurantMarker(data),
      });
    }
    return locations;
  }

  Future<List<Map<String, dynamic>>> _loadSeedRestaurantsFromAsset() async {
    try {
      final raw = await rootBundle.loadString(
        'assets/data/restaurants_seed.json',
      );
      final data = jsonDecode(raw);
      final List list;
      if (data is List) {
        list = data;
      } else if (data is Map && data['restaurants'] is List) {
        list = data['restaurants'] as List;
      } else {
        return [];
      }
      return list
          .map((e) => Map<String, dynamic>.from(e as Map))
          .map((e) {
            e['docId'] ??= e['id'];
            return e;
          })
          .where((e) => (e['docId'] ?? '').toString().isNotEmpty)
          .toList();
    } catch (e) {
      debugPrint('ℹ️ Cap seed local de restaurants (optional): $e');
    }
    return [];
  }

  void _recomputeVisibleRestaurants() {
    if (_selectedSources.isEmpty) {
      _visibleRestaurantLocations = _restaurantLocations;
      return;
    }
    _visibleRestaurantLocations = _restaurantLocations
        .where(_passesFilter)
        .toList(growable: false);
  }

  _RestaurantMarkerKind _classifyRestaurantMarker(Map<String, dynamic> data) {
    final name = (data['name'] ?? '').toString().toLowerCase();
    final isNight =
        name.contains('bar') ||
        name.contains('pub') ||
        name.contains('disco') ||
        name.contains('club');
    if (isNight) return _RestaurantMarkerKind.night;
    final isCafe = name.contains('cafe') || name.contains('cafeteria');
    if (isCafe) return _RestaurantMarkerKind.cafe;
    return _RestaurantMarkerKind.standard;
  }

  Widget _restaurantMarkerIcon(
    _RestaurantMarkerKind kind, {
    required bool isFavorite,
    required bool isSelected,
  }) {
    if (isFavorite) {
      return isSelected ? _markerFavoriteSelectedIcon : _markerFavoriteIcon;
    }
    return switch (kind) {
      _RestaurantMarkerKind.night =>
        isSelected ? _markerNightSelectedIcon : _markerNightIcon,
      _RestaurantMarkerKind.cafe =>
        isSelected ? _markerCafeSelectedIcon : _markerCafeIcon,
      _RestaurantMarkerKind.standard =>
        isSelected ? _markerStandardSelectedIcon : _markerStandardIcon,
    };
  }

  void _clearTemporarySelection() {
    if (_selectedRestaurant == null && _selectedHarvest == null) return;
    _selectedRestaurant = null;
    _selectedHarvest = null;
    _updateMarkers();
  }

  void _zoomToCluster(MarkerClusterNode cluster) {
    _clearTemporarySelection();
    var splitNode = cluster;
    while (splitNode.children.length == 1) {
      final onlyChild = splitNode.children.first;
      if (onlyChild is! MarkerClusterNode) break;
      splitNode = onlyChild;
    }
    final targetZoom = (splitNode.zoom + 1.05).clamp(3.0, 18.2).toDouble();
    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: splitNode.bounds,
        padding: const EdgeInsets.fromLTRB(56, 96, 56, 180),
        minZoom: targetZoom,
        maxZoom: targetZoom,
      ),
    );
  }

  bool get hasTransientSelection =>
      _selectedRestaurant != null || _selectedHarvest != null;

  bool consumeBackPress() {
    if (!hasTransientSelection) return false;
    _clearTemporarySelection();
    return true;
  }

  void _selectRestaurantMarker(Map<String, Object?> marker) {
    _selectedHarvest = null;
    _selectedRestaurant = Map<String, dynamic>.from(marker['data'] as Map);
    _updateMarkers();
  }

  void _selectHarvestMarker(Map<String, Object?> marker) {
    _selectedRestaurant = null;
    _selectedHarvest = marker['data'] as HarvestPlace;
    _updateMarkers();
  }

  void _updateMarkers() {
    final selectedRestaurantId = (_selectedRestaurant?['docId'] ?? '')
        .toString();
    final source = _isHospitality
        ? _visibleRestaurantLocations
        : _harvestLocations;
    final nextMarkers = source
        .map((r) {
          final markerId = (r['id'] ?? '').toString();
          return Marker(
            point: LatLng(
              (r['lat'] as num).toDouble(),
              (r['lng'] as num).toDouble(),
            ),
            width: 28,
            height: 28,
            child: GestureDetector(
              onTap: () {
                if (_isHospitality) {
                  _selectRestaurantMarker(r);
                } else {
                  _selectHarvestMarker(r);
                }
              },
              child: _isHospitality
                  ? _restaurantMarkerIcon(
                      (r['marker_kind'] as _RestaurantMarkerKind?) ??
                          _RestaurantMarkerKind.standard,
                      isFavorite: _favoritePlaces.contains(markerId),
                      isSelected:
                          markerId.isNotEmpty &&
                          markerId == selectedRestaurantId,
                    )
                  : _markerHarvestIcon,
            ),
          );
        })
        .toList(growable: false);

    if (!mounted) {
      _markers = nextMarkers;
      return;
    }
    setState(() {
      _markers = nextMarkers;
    });
  }

  Widget _pinMarker({
    required Color fill,
    required IconData icon,
    double iconSize = 16,
    Color? outlineColor,
  }) {
    const double circleSize = 20;
    const double tailHeight = 6;
    const double outlineWidth = 2.0;
    final hasOutline = outlineColor != null;
    return SizedBox(
      width: circleSize + 6,
      height: circleSize + tailHeight + 2,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.topCenter,
        children: [
          Positioned(
            top: 0,
            child: Container(
              width: circleSize,
              height: circleSize,
              decoration: BoxDecoration(
                color: fill,
                shape: BoxShape.circle,
                border: hasOutline
                    ? Border.all(color: outlineColor, width: outlineWidth)
                    : null,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 7,
                    spreadRadius: 0,
                    offset: const Offset(0, 2),
                  ),
                  if (hasOutline)
                    BoxShadow(
                      color: outlineColor.withValues(alpha: 0.16),
                      blurRadius: 6,
                      spreadRadius: 0,
                      offset: const Offset(0, 1),
                    ),
                ],
              ),
              alignment: Alignment.center,
              child: Icon(icon, size: iconSize, color: Colors.white),
            ),
          ),
          Positioned(
            top: circleSize - 2,
            child: CustomPaint(
              size: const Size(10, tailHeight),
              painter: PinTailPainter(
                color: fill,
                borderColor: outlineColor,
                borderWidth: outlineWidth * 0.9,
                drawTopBorder: !hasOutline,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _toggleCategory(bool hospitality) {
    if (_isHospitality == hospitality) return;
    _zoomPrefetchDebounce?.cancel();
    _isHospitality = hospitality;
    _selectedRestaurant = null;
    _selectedHarvest = null;
    _closeFilterOverlay();
    _updateMarkers();
  }

  void setFarmMapEnabled(bool enabled) {
    setState(() {
      _farmMapEnabled = enabled;
    });
  }

  Future<void> _copyToClipboard(String value, String label) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    await OverlayHelper.showCopiedOverlay(context, this, label);
  }

  void _openMailSetup() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const MailSetupPage()));
  }

  void _openFavorites() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const FavoritesScreen()));
  }

  void _openReports() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const ReportMessagePage()));
  }

  void _openAdmin() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const AdminPage()));
  }

  Future<void> showProfileTooltipIfNeeded() => _maybeShowProfileTooltip();

  Future<void> _maybeShowProfileTooltip() async {
    final prefs = await SharedPreferences.getInstance();
    const key = 'seen_map_profile_tooltip';
    final seen = prefs.getBool(key) ?? false;
    if (seen) return;
    await prefs.setBool(key, true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 220), _showProfileTooltip);
    });
  }

  void _showProfileTooltip() {
    _removeProfileTooltip();
    final overlay = Overlay.of(context);

    final profileRenderBox =
        _profileButtonKey.currentContext?.findRenderObject() as RenderBox?;
    final switchRenderBox =
        _categorySwitchKey.currentContext?.findRenderObject() as RenderBox?;
    if (profileRenderBox == null || switchRenderBox == null) return;
    final targetOffset = profileRenderBox.localToGlobal(Offset.zero);
    final targetSize = profileRenderBox.size;
    final targetRect = targetOffset & targetSize;
    final anchorOffset = switchRenderBox.localToGlobal(Offset.zero);
    final anchorRect = anchorOffset & switchRenderBox.size;

    final animation = CurvedAnimation(
      parent: _tooltipController,
      curve: Curves.easeOut,
    );
    _tooltipController.forward(from: 0);
    _pulseController.repeat(reverse: true);

    _profileTooltip = OverlayEntry(
      builder: (context) {
        return Positioned.fill(
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (_) => _removeProfileTooltip(),
            child: IgnorePointer(
              child: ProfileTooltipOverlay(
                anchorRect: anchorRect,
                targetRect: targetRect,
                fadeSlide: animation,
                pulse: _pulseController,
              ),
            ),
          ),
        );
      },
    );
    overlay.insert(_profileTooltip!);
    _tooltipTimer?.cancel();
    _tooltipTimer = Timer(const Duration(seconds: 3), _removeProfileTooltip);
  }

  void _removeProfileTooltip() {
    _tooltipTimer?.cancel();
    _tooltipTimer = null;
    _profileTooltip?.remove();
    _profileTooltip = null;
    _pulseController.stop();
  }

  void _showProfilePopup() {
    final isAdmin = isAdminSession;
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Perfil',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (context, _, _) {
        return SafeArea(
          child: Align(
            alignment: Alignment.topLeft,
            child: Padding(
              padding: const EdgeInsets.only(left: 16, top: 70, right: 16),
              child: _ProfilePopupMenu(
                onMail: () {
                  Navigator.of(context).pop();
                  _openMailSetup();
                },
                onReports: () {
                  Navigator.of(context).pop();
                  _openReports();
                },
                onFavorites: () {
                  Navigator.of(context).pop();
                  _openFavorites();
                },
                onAdmin: () {
                  Navigator.of(context).pop();
                  _openAdmin();
                },
                showAdmin: isAdmin,
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, secondary, child) {
        final curved = Curves.easeOutCubic.transform(animation.value);
        return FadeTransition(
          opacity: animation,
          child: Transform.scale(scale: 0.95 + 0.05 * curved, child: child),
        );
      },
    );
  }

  Future<void> _openUrl(String url) async {
    if (url.isEmpty) return;
    final uri = Uri.parse(url);
    final canOpen = await canLaunchUrl(uri);
    if (!mounted) return;
    if (canOpen) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Could not open the link')));
    }
  }

  Future<void> _toggleFavorite(String restaurantId) async {
    if (restaurantId.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error: el restaurant no té ID vàlid.')),
      );
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final current = Set<String>.from(_favoritePlaces);

    if (current.contains(restaurantId)) {
      current.remove(restaurantId);
    } else {
      current.add(restaurantId);
    }

    await prefs.setStringList('favorite_places', current.toList());
    _favoritePlaces = current;
    _updateMarkers();
    FavoritesService.broadcast(_favoritePlaces);
  }

  void _updateLocalWorkedHere(String restaurantId, int delta) {
    for (final loc in _restaurantLocations) {
      if (loc['id'] == restaurantId) {
        final raw = loc['worked_here_count'] ?? 0;
        final current = (raw is num)
            ? raw.toInt()
            : int.tryParse(raw.toString()) ?? 0;
        loc['worked_here_count'] = current + delta;
      }
    }
    if (_selectedRestaurant != null &&
        _selectedRestaurant?['docId'] == restaurantId) {
      final raw = _selectedRestaurant?['worked_here_count'] ?? 0;
      final current = (raw is num)
          ? raw.toInt()
          : int.tryParse(raw.toString()) ?? 0;
      _selectedRestaurant!['worked_here_count'] = current + delta;
    }
  }

  Future<void> _showWorkedDialog(
    String restaurantId,
    String restaurantName,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final workedList = prefs.getStringList('worked_places') ?? [];
    if (!mounted) return;

    if (restaurantId.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error: el restaurant no té ID vàlid.')),
      );
      return;
    }

    if (workedList.contains(restaurantId)) {
      final undo = await _showDecisionDialog(
        title: 'You want to undo?',
        subtitle: 'Your feedback helps other users.',
        yesLabel: 'Yes',
        noLabel: 'No',
        yesColor: Colors.green,
      );

      if (undo == true) {
        try {
          await FirebaseFirestore.instance
              .collection('restaurants')
              .doc(restaurantId)
              .update({'worked_here_count': FieldValue.increment(-1)});
          workedList.remove(restaurantId);
          await prefs.setStringList('worked_places', workedList);
          _updateLocalWorkedHere(restaurantId, -1);
          if (mounted) setState(() {});
        } catch (e) {
          if (!mounted) return;
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('❌ Error en desfer: $e')));
        }
      }
      return;
    }

    final result = await _showDecisionDialog(
      title: 'Have you worked here?',
      subtitle: 'Your feedback helps other users.',
      yesLabel: 'Yes',
      noLabel: 'No',
      yesColor: Colors.green,
    );

    if (result == true) {
      try {
        await FirebaseFirestore.instance
            .collection('restaurants')
            .doc(restaurantId)
            .update({'worked_here_count': FieldValue.increment(1)});
        workedList.add(restaurantId);
        await prefs.setStringList('worked_places', workedList);
        _updateLocalWorkedHere(restaurantId, 1);
        if (mounted) setState(() {});
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Error en registrar el teu vot: $e')),
        );
      }
    }
  }

  Future<bool?> _showDecisionDialog({
    required String title,
    required String subtitle,
    required String yesLabel,
    required String noLabel,
    Color yesColor = Colors.green,
  }) {
    final borderRadius = BorderRadius.circular(24);
    return showDialog<bool>(
      context: context,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: borderRadius),
          elevation: 8,
          backgroundColor: const Color(0xFFFFF7F5),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Icon(
                  Icons.handshake_outlined,
                  size: 28,
                  color: Colors.black54,
                ),
                const SizedBox(height: 10),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.black.withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.black87,
                          side: BorderSide(color: Colors.grey.shade400),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        onPressed: () => Navigator.pop(context, false),
                        child: Text(noLabel),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: yesColor,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        onPressed: () => Navigator.pop(context, true),
                        child: Text(yesLabel),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showEmailOptions(String email) {
    final overlay = Overlay.of(context);
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) {
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onTap: () => entry.remove(),
                child: Container(color: Colors.black.withValues(alpha: 0.3)),
              ),
            ),
            Positioned(
              bottom: 120,
              left: MediaQuery.of(context).size.width * 0.2,
              right: MediaQuery.of(context).size.width * 0.2,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.15),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.grey.shade200,
                          foregroundColor: Colors.black87,
                          minimumSize: const Size(double.infinity, 42),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        onPressed: () async {
                          await Clipboard.setData(ClipboardData(text: email));
                          entry.remove();
                          if (!context.mounted) return;
                          OverlayHelper.showCopiedOverlay(
                            context,
                            this,
                            'copied email',
                          );
                        },
                        child: const Text('Copy email'),
                      ),
                      const SizedBox(height: 8),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.redAccent,
                          foregroundColor: Colors.white,
                          minimumSize: const Size(double.infinity, 42),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        onPressed: () async {
                          final saved =
                              (await EmailSenderService.getSavedEmailContent())
                                  ?.trim();
                          if (!context.mounted) return;
                          if (saved == null || saved.isEmpty) {
                            entry.remove();
                            if (context.mounted) {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const MailSetupPage(),
                                ),
                              );
                            }
                            return;
                          }
                          await EmailSenderService.sendEmail(
                            context: context,
                            email: email,
                          );
                          entry.remove();
                        },
                        child: const Text('Send email'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
    overlay.insert(entry);
  }

  void _zoomOut() {
    final newZoom = (_currentZoom - 1).clamp(3.0, 18.0);
    _mapController.move(_currentCenter, newZoom);
  }

  Future<void> _goToUserLocation() async {
    if (_isLocating) return;
    setState(() => _isLocating = true);
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() => _isLocating = false);
        return;
      }
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        setState(() => _isLocating = false);
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      final target = LatLng(pos.latitude, pos.longitude);
      _mapController.move(target, 15);
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  void _setTileLoading(bool value) {
    if (!mounted) return;
    if (value) {
      final now = DateTime.now();
      if (_isTileLoading &&
          _tileLoadingStartedAt != null &&
          now.difference(_tileLoadingStartedAt!).inMilliseconds < 400) {
        return; // evita reposicionar si ja està mostrant-se recentment
      }
      _tileLoadingTimeout?.cancel();
      setState(() {
        _isTileLoading = true;
        _tileLoadingStartedAt = now;
      });
      _tileLoadingTimeout = Timer(const Duration(milliseconds: 1400), () {
        if (mounted) {
          setState(() => _isTileLoading = false);
          _tileLoadingStartedAt = null;
        }
      });
    } else {
      _tileLoadingTimeout?.cancel();
      if (_isTileLoading) {
        setState(() {
          _isTileLoading = false;
          _tileLoadingStartedAt = null;
        });
      }
    }
  }

  Widget _buildRestaurantPopup() {
    if (_selectedRestaurant == null) return const SizedBox.shrink();
    final r = _selectedRestaurant!;
    final docId = r['docId'] ?? '';
    return MapRestaurantPopup(
      data: r,
      workedCount: (r['worked_here_count'] ?? 0) as int,
      isFavorite: _favoritePlaces.contains(docId),
      onClose: _clearTemporarySelection,
      onWorkedHere: () => _showWorkedDialog(docId, r['name'] ?? 'this place'),
      onCopyPhone: () => _copyToClipboard(r['phone'], 'copied phone'),
      onEmail: () => _showEmailOptions(r['email']),
      onFacebook: () => _openUrl(r['facebook_url']),
      onCareers: () => _openUrl(r['careers_page']),
      onInstagram: () => _openUrl(r['instagram_url']),
      onFavorite: () => _toggleFavorite(docId),
    );
  }

  Widget _buildHarvestPopup() {
    if (_selectedHarvest == null) return const SizedBox.shrink();
    final data = _selectedHarvest!;
    return MapHarvestPopup(
      name: data.name,
      postcode: data.postcode,
      state: data.state,
      description: data.description,
      onClose: () => setState(() => _selectedHarvest = null),
    );
  }

  bool get _allSelected => _selectedSources.isEmpty;

  void _setSourceSelection(String sourceKey, bool selected) {
    if (sourceKey == 'all') {
      _selectedSources.clear();
    } else {
      if (selected) {
        _selectedSources.add(sourceKey);
      } else {
        _selectedSources.remove(sourceKey);
      }
      if (_selectedSources.isEmpty) _selectedSources.clear();
    }
    _selectedRestaurant = null;
    _recomputeVisibleRestaurants();
    _updateMarkers();
  }

  void _closeFilterOverlay() {
    _filterOverlay?.remove();
    _filterOverlay = null;
  }

  void _toggleFilterOverlay() {
    if (!_isHospitality) return;
    if (_filterOverlay != null) {
      _closeFilterOverlay();
      return;
    }

    final overlay = Overlay.of(context);

    const double sheetWidth = 240;

    _filterOverlay = OverlayEntry(
      builder: (context) {
        return Material(
          type: MaterialType.transparency,
          child: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  onTap: _closeFilterOverlay,
                  child: Container(color: Colors.black.withValues(alpha: 0.25)),
                ),
              ),
              CompositedTransformFollower(
                link: _filterLink,
                showWhenUnlinked: false,
                offset: Offset(-(sheetWidth - 44), 56),
                child: StatefulBuilder(
                  builder: (context, setPopoverState) {
                    return Material(
                      type: MaterialType.transparency,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Transform.translate(
                            offset: const Offset(-12, -2),
                            child: CustomPaint(
                              size: const Size(18, 10),
                              painter: _TrianglePainter(color: Colors.white),
                            ),
                          ),
                          Material(
                            color: Colors.white,
                            elevation: 6,
                            borderRadius: BorderRadius.circular(14),
                            child: Container(
                              width: sheetWidth,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(14),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.12),
                                    blurRadius: 12,
                                    offset: const Offset(0, 6),
                                  ),
                                ],
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  ListTile(
                                    leading: const Icon(Icons.select_all),
                                    title: const Text(
                                      'All',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    trailing: Checkbox(
                                      value: _allSelected,
                                      onChanged: (_) {
                                        _setSourceSelection('all', true);
                                        setPopoverState(() {});
                                      },
                                    ),
                                  ),
                                  const Divider(height: 1),
                                  ..._sourceOptions.map((option) {
                                    final key = option['key'] as String;
                                    final label = option['label'] as String;
                                    final icon = option['icon'] as IconData;
                                    final selected = _selectedSources.contains(
                                      key,
                                    );
                                    return CheckboxListTile(
                                      value: selected,
                                      onChanged: (_) {
                                        _setSourceSelection(key, !selected);
                                        setPopoverState(() {});
                                      },
                                      controlAffinity:
                                          ListTileControlAffinity.trailing,
                                      secondary: Icon(
                                        icon,
                                        color: selected
                                            ? Colors.blueAccent
                                            : Colors.black54,
                                      ),
                                      title: Text(label),
                                    );
                                  }),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );

    overlay.insert(_filterOverlay!);
  }

  Set<String> _extractSources(Map<String, dynamic> data) {
    final sources = <String>{};
    final dynamic rawSource = data['source'] ?? data['platform'];

    String normalize(String value) {
      final v = value.toLowerCase().trim();
      if (v.contains('facebook') || v == 'fb') return 'facebook';
      if (v.contains('insta') || v == 'ig') return 'instagram';
      if (v.contains('career') || v.contains('jobs')) return 'careers';
      if (v.contains('mail')) return 'gmail';
      return v;
    }

    void addSource(dynamic value) {
      if (value == null) return;
      final normalized = normalize(value.toString());
      if (normalized.isNotEmpty) sources.add(normalized);
    }

    if (rawSource is String && rawSource.trim().isNotEmpty) {
      addSource(rawSource);
    } else if (rawSource is Iterable) {
      for (final value in rawSource) {
        addSource(value);
      }
    }

    bool hasText(dynamic value) =>
        value != null && value.toString().trim().isNotEmpty;

    if (hasText(data['email'])) sources.add('gmail');
    if (hasText(data['facebook_url']) || hasText(data['facebook'])) {
      sources.add('facebook');
    }
    if (hasText(data['instagram_url']) || hasText(data['instagram'])) {
      sources.add('instagram');
    }
    if (hasText(data['careers_page']) || hasText(data['careers'])) {
      sources.add('careers');
    }

    return sources;
  }

  bool _passesFilter(Map<String, Object?> location) {
    if (!_isHospitality) return true;
    if (_selectedSources.isEmpty) return true;

    final dynamic rawSources = location['sources'];
    final Iterable<String> sources = rawSources is Set<String>
        ? rawSources
        : rawSources is Iterable
        ? rawSources.whereType<String>()
        : const Iterable.empty();

    if (sources.isEmpty) return false;
    return sources.any(_selectedSources.contains);
  }

  @override
  Widget build(BuildContext context) {
    if (!hasMapTilerKey) {
      return Scaffold(
        appBar: AppBar(title: const Text('Map OSM')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Missing MAPTILER_KEY. Run: flutter run --dart-define=MAPTILER_KEY=xxxx',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    _styleFuture ??= _loadStyle();

    return FutureBuilder<Style>(
      future: _styleFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(body: Center(child: _kangarooLoader(size: 52)));
        }
        if (snapshot.hasError || !snapshot.hasData) {
          debugPrint('❌ Error carregant estil: ${snapshot.error}');
          final isOffline = _isOfflineError(snapshot.error);
          if (isOffline) {
            return Scaffold(
              body: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('You are offline, mate 🐨'),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: () {
                        setState(() {
                          _styleFuture = _loadStyle();
                          _loadInitialData();
                        });
                      },
                      icon: const Icon(Icons.refresh),
                      label: const Text('Reintentar'),
                    ),
                  ],
                ),
              ),
            );
          } else {
            return Scaffold(
              appBar: AppBar(title: const Text('Map OSM')),
              body: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Could not load the map style:\n${snapshot.error}',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: _reloadStyle,
                      child: const Text('Reintentar'),
                    ),
                  ],
                ),
              ),
            );
          }
        }

        final style = snapshot.data!;
        final tileProviders = _optimizedTileProviders(style);

        if (!_didKickstartRender) {
          _didKickstartRender = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            // Força petició inicial de tiles al centre d'Austràlia
            _mapController.move(_initialCenter, _initialZoom);
          });
        }

        // Mantenim el centre inicial d'Austràlia; no auto-fit a marcadors

        if (!_isHospitality) {
          // restore Farm map view when ready; placeholder for now.
          return const Scaffold(appBar: null, body: FarmPlaceholderView());
        }

        return Scaffold(
          appBar: null,
          body: Stack(
            children: [
              FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: _initialCenter,
                  initialZoom: _initialZoom,
                  minZoom: 3.0,
                  maxZoom: 18.2,
                  onMapReady: () {
                    _mapReady = true;
                    if (_pendingCenter != null && _pendingZoom != null) {
                      _mapController.move(_pendingCenter!, _pendingZoom!);
                      _pendingCenter = null;
                      _pendingZoom = null;
                    }
                    _scheduleAdjacentZoomPrefetch(tileProviders);
                  },
                  interactionOptions: const InteractionOptions(
                    flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                  ),
                  onTap: (tapPosition, point) {
                    _clearTemporarySelection();
                  },
                  onPositionChanged: (position, _) {
                    final rotation = position.rotation;
                    if (rotation.abs() > 0.0001) _mapController.rotate(0);
                    _currentCenter = position.center;
                    final newZoom = position.zoom;
                    if ((newZoom - _currentZoom).abs() > 0.02) {
                      _setTileLoading(true);
                    }
                    _currentZoom = newZoom;
                    _pendingCenter = _currentCenter;
                    _pendingZoom = _currentZoom;
                    _persistDebounce?.cancel();
                    _persistDebounce = Timer(
                      const Duration(milliseconds: 500),
                      () {
                        _saveLastMapPosition(_currentCenter, _currentZoom);
                      },
                    );
                    _scheduleAdjacentZoomPrefetch(tileProviders);
                  },
                ),
                children: [
                  VectorTileLayer(
                    theme: style.theme,
                    sprites: style.sprites,
                    tileProviders: tileProviders,
                    cacheFolder: _resolveVectorCacheFolder,
                    fileCacheTtl: const Duration(days: 45),
                    fileCacheMaximumSizeInBytes: 160 * 1024 * 1024,
                    memoryTileCacheMaxSize: 24 * 1024 * 1024,
                    memoryTileDataCacheMaxSize: 80,
                    textCacheMaxSize: 180,
                    maximumTileSubstitutionDifference: 3,
                    concurrency: 6,
                    tileOffset: TileOffset.mapbox,
                  ),
                  MarkerClusterLayerWidget(
                    options: MarkerClusterLayerOptions(
                      markers: _markers,
                      zoomToBoundsOnClick: false,
                      centerMarkerOnClick: false,
                      spiderfyCluster: false,
                      onClusterTap: _zoomToCluster,
                      maxClusterRadius:
                          28, // clusters a bit tighter for faster zoom redraws
                      size: const Size(30, 30),
                      padding: const EdgeInsets.all(20),
                      disableClusteringAtZoom:
                          17, // avoid heavy re-clustering when zoomed in
                      showPolygon:
                          false, // evita dibuixar el polígon verd del clúster
                      builder: (context, cluster) {
                        return Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFF111827),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.25),
                                blurRadius: 8,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            cluster.length.toString(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
              if (_isTileLoading)
                Positioned(
                  right: 10,
                  bottom: 302,
                  child: IgnorePointer(
                    child: _kangarooLoader(size: 72, animate: false),
                  ),
                ),
              Positioned(
                top: 16,
                left: 12,
                right: 12,
                child: SafeArea(
                  child: Row(
                    children: [
                      Material(
                        elevation: 4,
                        shape: const CircleBorder(),
                        color: Colors.white,
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: _showProfilePopup,
                          child: SizedBox(
                            key: _profileButtonKey,
                            height: 48,
                            width: 48,
                            child: const Icon(
                              Icons.person_outline,
                              color: Colors.black87,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: CompactCategorySwitch(
                          key: _categorySwitchKey,
                          selected: _isHospitality
                              ? Category.hospitality
                              : Category.farm,
                          onChanged: (cat) =>
                              _toggleCategory(cat == Category.hospitality),
                          farmEnabled: _farmMapEnabled,
                        ),
                      ),
                      const SizedBox(width: 10),
                      CompositedTransformTarget(
                        link: _filterLink,
                        child: Material(
                          elevation: 4,
                          shape: const CircleBorder(),
                          color: Colors.white,
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: _toggleFilterOverlay,
                            child: const SizedBox(
                              height: 48,
                              width: 48,
                              child: Icon(
                                Icons.filter_list,
                                color: Colors.black87,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_isLoadingData) Center(child: _kangarooLoader(size: 48)),
              _buildRestaurantPopup(),
              _buildHarvestPopup(),
              if (_isHospitality)
                Positioned(
                  bottom: 240,
                  right: 16,
                  child: FloatingActionButton(
                    onPressed: _isLocating ? null : _goToUserLocation,
                    heroTag: 'fab_location',
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.blueGrey.shade700,
                    child: _isLocating
                        ? _kangarooLoader(size: 20)
                        : const Icon(Icons.my_location),
                  ),
                ),
              if (_isHospitality)
                Positioned(
                  bottom: 180,
                  right: 16,
                  child: FloatingActionButton(
                    heroTag: 'fab_zoom_out',
                    onPressed: _zoomOut,
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.blueGrey.shade700,
                    child: const Icon(Icons.zoom_out),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class CompactCategorySwitch extends StatelessWidget {
  const CompactCategorySwitch({
    super.key,
    required this.selected,
    required this.onChanged,
    this.farmEnabled = false,
  });

  final Category selected;
  final ValueChanged<Category> onChanged;
  final bool farmEnabled;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final pillWidth = constraints.maxWidth.clamp(0, 420).toDouble();
        const animDuration = Duration(milliseconds: 180);
        const baseTextStyle = TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 13,
        );

        Widget buildSegment({
          required Category category,
          required String label,
          String? badge,
          bool enabled = true,
        }) {
          final isSelected = selected == category;
          return Expanded(
            child: AnimatedContainer(
              duration: animDuration,
              curve: Curves.easeOutCubic,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: isSelected ? Colors.blueAccent : Colors.transparent,
                borderRadius: BorderRadius.circular(22),
              ),
              child: InkWell(
                onTap: enabled ? () => onChanged(category) : null,
                borderRadius: BorderRadius.circular(22),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: baseTextStyle.copyWith(
                              color: isSelected ? Colors.white : Colors.black87,
                              fontWeight: isSelected
                                  ? FontWeight.w700
                                  : FontWeight.w600,
                            ),
                          ),
                          if (badge != null && pillWidth >= 200)
                            Padding(
                              padding: const EdgeInsets.only(left: 6, top: 1),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 5,
                                  vertical: 1.5,
                                ),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? Colors.white24
                                      : Colors.grey.shade300.withValues(
                                          alpha: 0.75,
                                        ),
                                  borderRadius: BorderRadius.circular(9),
                                ),
                                child: Text(
                                  badge,
                                  style: TextStyle(
                                    fontSize: 9,
                                    color: isSelected
                                        ? Colors.white70
                                        : Colors.black54,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        }

        return Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: pillWidth,
              minHeight: 48,
              maxHeight: 48,
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: Colors.blueGrey.withValues(alpha: 0.2),
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  buildSegment(
                    category: Category.hospitality,
                    label: 'Hospitality',
                    enabled: true,
                  ),
                  buildSegment(
                    category: Category.farm,
                    label: 'Farm',
                    badge: 'SOON',
                    enabled: farmEnabled,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class FarmPlaceholderView extends StatelessWidget {
  const FarmPlaceholderView({super.key});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: Image.asset(
            'assets/farm_placeholder_map.png',
            fit: BoxFit.cover,
          ),
        ),
        Positioned.fill(
          child: Container(color: Colors.white.withValues(alpha: 0.12)),
        ),
        Positioned(
          top: 12,
          left: 12,
          child: SafeArea(
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black87,
                elevation: 2,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
              ),
              onPressed: () => Navigator.of(context).maybePop(),
              child: const Text('Enrere'),
            ),
          ),
        ),
      ],
    );
  }
}

class _TooltipArrowPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white;
    final path = Path()
      ..moveTo(size.width / 2, 0)
      ..lineTo(0, size.height)
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(path, paint);

    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.08)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawPath(path.shift(const Offset(0, 1)), shadowPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class ProfileTooltipOverlay extends StatelessWidget {
  const ProfileTooltipOverlay({
    super.key,
    required this.anchorRect,
    required this.targetRect,
    required this.fadeSlide,
    required this.pulse,
  });

  final Rect anchorRect;
  final Rect targetRect;
  final Animation<double> fadeSlide;
  final Animation<double> pulse;

  @override
  Widget build(BuildContext context) {
    final bubbleTop = anchorRect.bottom + 12;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final horizontalInset = 18.0;
    final maxBubbleWidth = 320.0;
    final arrowWidth = 18.0;
    final availableWidth = screenWidth - (horizontalInset * 2);
    final bubbleWidth = math.min(maxBubbleWidth, availableWidth);
    final maxBubbleLeft = screenWidth - bubbleWidth - horizontalInset;
    final bubbleLeft = math.max(
      horizontalInset,
      math.min(targetRect.left, maxBubbleLeft),
    );
    final preferredArrowLeft =
        targetRect.center.dx - bubbleLeft - (arrowWidth / 2);
    final arrowLeft = math.max(
      -(arrowWidth / 2),
      math.min(preferredArrowLeft, bubbleWidth - (arrowWidth / 2)),
    );
    return Stack(
      children: [
        Positioned.fill(child: Container(color: Colors.transparent)),
        Positioned(
          left: targetRect.center.dx - (targetRect.width + 6) / 2,
          top: targetRect.center.dy - (targetRect.height + 6) / 2,
          child: AnimatedBuilder(
            animation: pulse,
            builder: (context, child) {
              return Transform.scale(scale: pulse.value, child: child);
            },
            child: Container(
              width: targetRect.width + 6,
              height: targetRect.height + 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.blueAccent.withValues(alpha: 0.12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.blueAccent.withValues(alpha: 0.25),
                    blurRadius: 12,
                    spreadRadius: 0,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          top: bubbleTop,
          left: bubbleLeft,
          width: bubbleWidth,
          child: FadeTransition(
            opacity: fadeSlide,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, -0.08),
                end: Offset.zero,
              ).animate(fadeSlide),
              child: _EnhancedTooltip(arrowLeft: arrowLeft),
            ),
          ),
        ),
      ],
    );
  }
}

class _EnhancedTooltip extends StatelessWidget {
  const _EnhancedTooltip({required this.arrowLeft});

  final double arrowLeft;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.98),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFDBEAFE), width: 1.2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.max,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.mail_outline,
                    size: 18,
                    color: Color(0xFF2563EB),
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Set up your email',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Colors.black87,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Tap the profile button above.',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF4B5563),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            top: -10,
            left: arrowLeft,
            child: CustomPaint(
              size: const Size(18, 10),
              painter: _TooltipArrowPainter(),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfilePopupMenu extends StatelessWidget {
  const _ProfilePopupMenu({
    required this.onMail,
    required this.onReports,
    required this.onFavorites,
    required this.onAdmin,
    required this.showAdmin,
  });

  final VoidCallback onMail;
  final VoidCallback onReports;
  final VoidCallback onFavorites;
  final VoidCallback onAdmin;
  final bool showAdmin;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        width: 260,
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 18,
              spreadRadius: 1,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ProfileTile(
              icon: Icons.email_outlined,
              iconColor: Colors.redAccent,
              iconBg: Colors.redAccent.withValues(alpha: 0.12),
              text: 'Automatic email editing',
              onTap: onMail,
            ),
            const SizedBox(height: 14),
            _ProfileTile(
              icon: Icons.favorite_outline,
              iconColor: Colors.pinkAccent,
              iconBg: Colors.pinkAccent.withValues(alpha: 0.12),
              text: 'Favourites',
              onTap: onFavorites,
            ),
            const SizedBox(height: 14),
            _ProfileTile(
              icon: Icons.flag_outlined,
              iconColor: const Color(0xFFB45309),
              iconBg: const Color(0xFFFDEBD3),
              text: 'Send report',
              onTap: onReports,
            ),
            if (showAdmin) ...[
              const SizedBox(height: 14),
              _ProfileTile(
                icon: Icons.admin_panel_settings,
                iconColor: Colors.black87,
                iconBg: Colors.grey.shade200,
                text: 'Admin',
                onTap: onAdmin,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ProfileTile extends StatelessWidget {
  const _ProfileTile({
    required this.icon,
    required this.text,
    this.iconColor = Colors.black87,
    this.iconBg = Colors.black12,
    required this.onTap,
  });

  final IconData icon;
  final String text;
  final Color iconColor;
  final Color iconBg;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
          decoration: BoxDecoration(
            color: Colors.grey.shade100.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: iconBg,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: iconColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  text,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.black45),
            ],
          ),
        ),
      ),
    );
  }
}

class _TrianglePainter extends CustomPainter {
  final Color color;

  _TrianglePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final path = ui.Path()
      ..moveTo(0, size.height)
      ..lineTo(size.width / 2, 0)
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
