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
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';

import '../config/osm_vector_map_config.dart';
import '../widgets/map_place_popup.dart';
import '../services/harvest_places_service.dart';
import '../services/app_error_dialog_service.dart';
import '../services/donation_service.dart';
import '../services/external_link_service.dart';
import '../services/local_vector_style_service.dart';
import '../services/location_settings_service.dart';
import '../services/map_markers_service.dart';
import '../services/overlay_helper.dart';
import '../services/favorites_service.dart';
import '../services/remote_config_service.dart';
import '../services/review_service.dart';
import '../utils/australia_map_viewport.dart';
import '../services/email_sender_service.dart';
import '../services/admin_button_visibility_service.dart';
import '../widgets/location_fab_icon.dart';
import '../widgets/map_notice_card.dart';
import '../widgets/profile_button_icon.dart';
import 'favorites_screen.dart';
import 'mail_setup_page.dart';
import 'report_message_page.dart';
import 'admin_page.dart';
import '../config/admin_config.dart';
import 'package:mywhv/screens/_pin_tail_painter.dart';

enum Category { hospitality, farm }

enum _RestaurantMarkerKind { standard, night, cafe }

class MapOSMVectorPage extends StatefulWidget {
  const MapOSMVectorPage({
    super.key,
    this.initialCenter = const LatLng(-25.0, 133.0),
    this.initialZoom = 3.8,
    this.styleAssetPath = osmVectorStyleAssetPath,
  });

  final LatLng initialCenter;
  final double initialZoom;
  final String styleAssetPath;

  @override
  State<MapOSMVectorPage> createState() => MapOSMVectorPageState();
}

final Map<String, Style> _styleCache = {};
final Map<String, TileProviders> _tileProvidersCache = {};

class MapOSMVectorPageState extends State<MapOSMVectorPage>
    with TickerProviderStateMixin {
  static const Color _mapOceanBackgroundColor = Color(0xFFCFE1EC);
  static const Color _restaurantMarkerColor = Color(0xFFE58C7C);
  static const Color _cafeMarkerColor = Color(0xFFD9B45F);
  static const Color _barMarkerColor = Color(0xFFB8A7E8);
  static const Color _clusterMarkerColor = Color(0xFF6FA8A3);
  static const Color _selectedMarkerOutlineColor = Color(0xFFD97A6C);
  static const Color _restaurantIconColor = Color(0xFFFFFFFF);
  static const Color _cafeIconColor = Color(0xFFFFFFFF);
  static const Color _barIconColor = Color(0xFFFFFFFF);
  static const bool _showZoomOutButton = false;
  static const double _locationFabBottom = kMapPopupDockOffset + 172;
  static const double _initialKangarooBottomOffset = 212;
  static const double _zoomOutStep = 1.2;
  static const double _clusterZoomStep = 2.2;
  static const String _styleAssetCacheKey = 'osm_vector_self_hosted';
  static const String _dismissedLocationFabBadgeKey =
      'dismissed_map_location_fab_badge';
  static const String _hospitalityCameraPrefix = 'map_hospitality_last';
  static const String _harvestCameraPrefix = 'map_harvest_last';
  static final LatLngBounds _australiaViewportBounds = LatLngBounds(
    const LatLng(
      AustraliaMapViewport.viewportSouth,
      AustraliaMapViewport.viewportWest,
    ),
    const LatLng(
      AustraliaMapViewport.viewportNorth,
      AustraliaMapViewport.viewportEast,
    ),
  );

  final MapController _mapController = MapController();
  late LatLng _initialCenter;
  late double _initialZoom;
  bool _farmMapEnabled = true;

  List<Map<String, Object?>> _restaurantLocations = [];
  List<Map<String, Object?>> _visibleRestaurantLocations = [];
  List<Map<String, Object?>> _harvestLocations = [];
  List<Marker> _markers = [];
  bool _isHospitality = true;
  bool _isLoadingData = true;
  bool _isTileLoading = true;
  Timer? _tileLoadingTimeout;
  DateTime? _tileLoadingStartedAt;
  late LatLng _currentCenter;
  late double _currentZoom;
  late LatLng _hospitalityCenter;
  late double _hospitalityZoom;
  late LatLng _harvestCenter;
  late double _harvestZoom;
  bool _mapReady = false;
  LatLng? _pendingCenter;
  double? _pendingZoom;
  Set<String> _favoritePlaces = {};
  final ValueNotifier<Set<String>> _favoritePlacesNotifier =
      ValueNotifier<Set<String>>(<String>{});
  final ValueNotifier<String?> _selectedRestaurantIdNotifier =
      ValueNotifier<String?>(null);
  StreamSubscription<Set<String>>? _favoritesSub;
  bool _isLocating = false;
  bool _showLocationFabBadge = true;
  bool _showInitialKangarooHint = false;
  Timer? _zoomPrefetchDebounce;
  Timer? _initialKangarooTimer;
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
  OverlayEntry? _locationPermissionNotice;
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
  final GlobalKey _mapAreaKey = GlobalKey();
  final GlobalKey _profileButtonKey = GlobalKey();
  final GlobalKey _categorySwitchKey = GlobalKey();
  final GlobalKey _automaticEmailTileKey = GlobalKey();
  bool _showOnboardingEmailPreview = false;

  Map<String, dynamic>? _selectedRestaurant;
  HarvestPlace? _selectedHarvest;
  Future<Style>? _styleFuture;
  bool _didKickstartRender = false;
  bool _didCheckInitialKangarooHint = false;
  Future<Directory>? _vectorCacheFolderFuture;
  static const int _maxPrefetchTilesPerZoom = 28;
  static const int _maxPrefetchedTileKeys = 2400;
  late final Listenable _markerVisualStateListenable = Listenable.merge([
    _favoritePlacesNotifier,
    _selectedRestaurantIdNotifier,
  ]);

  String get _styleCacheKey =>
      '$_styleAssetCacheKey|${widget.styleAssetPath}|$osmVectorTilesUrlTemplateOrEmpty';

  bool _setEquals(Set<String> a, Set<String> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (final value in a) {
      if (!b.contains(value)) return false;
    }
    return true;
  }

  TileProviders _optimizedTileProviders(Style style) {
    final styleKey = _styleCacheKey;
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
                  '$_styleCacheKey|${entry.key}|$zoom|${tile.x}|${tile.y}';
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
    _initialCenter = widget.initialCenter;
    _initialZoom = widget.initialZoom;
    _currentCenter = widget.initialCenter;
    _currentZoom = widget.initialZoom;
    _hospitalityCenter = widget.initialCenter;
    _hospitalityZoom = widget.initialZoom;
    _harvestCenter = widget.initialCenter;
    _harvestZoom = widget.initialZoom;
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
      outlineColor: _selectedMarkerOutlineColor,
    );
    _markerNightIcon = _pinMarker(
      fill: _barMarkerColor,
      icon: Icons.local_bar,
      iconSize: 16,
      iconColor: _barIconColor,
    );
    _markerNightSelectedIcon = _pinMarker(
      fill: _barMarkerColor,
      icon: Icons.local_bar,
      iconSize: 16,
      iconColor: _barIconColor,
      outlineColor: _selectedMarkerOutlineColor,
    );
    _markerCafeIcon = _pinMarker(
      fill: _cafeMarkerColor,
      icon: Icons.local_cafe,
      iconSize: 16,
      iconColor: _cafeIconColor,
    );
    _markerCafeSelectedIcon = _pinMarker(
      fill: _cafeMarkerColor,
      icon: Icons.local_cafe,
      iconSize: 16,
      iconColor: _cafeIconColor,
      outlineColor: _selectedMarkerOutlineColor,
    );
    _markerStandardIcon = _pinMarker(
      fill: _restaurantMarkerColor,
      icon: Icons.restaurant,
      iconSize: 16,
      iconColor: _restaurantIconColor,
    );
    _markerStandardSelectedIcon = _pinMarker(
      fill: _restaurantMarkerColor,
      icon: Icons.restaurant,
      iconSize: 16,
      iconColor: _restaurantIconColor,
      outlineColor: _selectedMarkerOutlineColor,
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
    _loadLocationFabBadgeState();
    _favoritesSub = FavoritesService.changes.listen((ids) {
      if (_setEquals(_favoritePlaces, ids)) return;
      _setFavoritePlaces(ids);
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
    _removeLocationPermissionNotice();
    _persistDebounce?.cancel();
    _tileLoadingTimeout?.cancel();
    _zoomPrefetchDebounce?.cancel();
    _initialKangarooTimer?.cancel();
    _favoritesSub?.cancel();
    _favoritePlacesNotifier.dispose();
    _selectedRestaurantIdNotifier.dispose();
    _closeFilterOverlay();
    FlutterError.onError = _originalOnError;
    super.dispose();
  }

  Widget _kangarooLoader({double size = 48, bool animate = true}) {
    final child = SizedBox(
      height: size,
      width: size,
      child: Image.asset(
        'assets/icons/source.gif',
        fit: BoxFit.contain,
        gaplessPlayback: false,
      ),
    );
    if (!animate) return child;
    return ScaleTransition(scale: _kangarooController, child: child);
  }

  Future<Style> _loadStyle() async {
    final styleKey = _styleCacheKey;
    if (_styleCache.containsKey(styleKey)) return _styleCache[styleKey]!;
    try {
      final style = await LocalVectorStyleService.instance.loadFromAsset(
        assetPath: widget.styleAssetPath,
        replacements: hasOsmVectorTilesUrlTemplate
            ? <String, String>{
                '{{OSM_VECTOR_TILES_URL_TEMPLATE}}':
                    osmVectorTilesUrlTemplateOrEmpty,
              }
            : const <String, String>{},
      );
      _styleCache[styleKey] = style;
      return style;
    } catch (e) {
      throw StateError('Could not load the self-hosted OSM vector style.');
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
    _styleCache.remove(_styleCacheKey);
    _tileProvidersCache.remove(_styleCacheKey);
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
    _setFavoritePlaces(next);
  }

  void _setFavoritePlaces(Set<String> favorites) {
    if (_setEquals(_favoritePlaces, favorites)) return;
    final next = Set<String>.from(favorites);
    _favoritePlaces = next;
    _favoritePlacesNotifier.value = next;
  }

  void _setSelectedRestaurantId(String? restaurantId) {
    if (_selectedRestaurantIdNotifier.value == restaurantId) return;
    _selectedRestaurantIdNotifier.value = restaurantId;
  }

  Future<void> _loadLastMapPosition() async {
    final prefs = await SharedPreferences.getInstance();
    final legacyLat = prefs.getDouble('map_last_lat');
    final legacyLng = prefs.getDouble('map_last_lng');
    final legacyZoom = prefs.getDouble('map_last_zoom');
    final hospitalityCamera = _readSavedCamera(
      prefs,
      _hospitalityCameraPrefix,
      fallbackLat: legacyLat,
      fallbackLng: legacyLng,
      fallbackZoom: legacyZoom,
    );
    final harvestCamera = _readSavedCamera(prefs, _harvestCameraPrefix);

    if (!mounted) return;
    setState(() {
      if (hospitalityCamera != null) {
        _hospitalityCenter = hospitalityCamera.$1;
        _hospitalityZoom = hospitalityCamera.$2;
      }
      if (harvestCamera != null) {
        _harvestCenter = harvestCamera.$1;
        _harvestZoom = harvestCamera.$2;
      }
      _initialCenter = _hospitalityCenter;
      _initialZoom = _hospitalityZoom;
      _currentCenter = _hospitalityCenter;
      _currentZoom = _hospitalityZoom;
      _pendingCenter = _hospitalityCenter;
      _pendingZoom = _hospitalityZoom;
    });
    if (_mapReady) {
      _mapController.move(_hospitalityCenter, _hospitalityZoom);
      _pendingCenter = null;
      _pendingZoom = null;
    }
  }

  (LatLng, double)? _readSavedCamera(
    SharedPreferences prefs,
    String prefix, {
    double? fallbackLat,
    double? fallbackLng,
    double? fallbackZoom,
  }) {
    final lat = prefs.getDouble('${prefix}_lat') ?? fallbackLat;
    final lng = prefs.getDouble('${prefix}_lng') ?? fallbackLng;
    final zoom = prefs.getDouble('${prefix}_zoom') ?? fallbackZoom;
    if (lat == null || lng == null || zoom == null) return null;
    return (
      _clampToAustraliaBounds(LatLng(lat, lng)),
      zoom.clamp(6.0, 12.0).toDouble(),
    );
  }

  Future<void> _loadLocationFabBadgeState() async {
    final prefs = await SharedPreferences.getInstance();
    final dismissed = prefs.getBool(_dismissedLocationFabBadgeKey) ?? false;
    if (!mounted || dismissed == !_showLocationFabBadge) return;
    setState(() {
      _showLocationFabBadge = !dismissed;
    });
  }

  Future<void> _dismissLocationFabBadge() async {
    if (!_showLocationFabBadge) return;
    if (mounted) {
      setState(() => _showLocationFabBadge = false);
    } else {
      _showLocationFabBadge = false;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_dismissedLocationFabBadgeKey, true);
  }

  Future<void> _saveLastMapPosition(
    LatLng center,
    double zoom, {
    required bool hospitality,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final clampedZoom = zoom.clamp(6.0, 12.0).toDouble();
    final clampedCenter = _clampToAustraliaBounds(center);
    final prefix = hospitality
        ? _hospitalityCameraPrefix
        : _harvestCameraPrefix;
    await prefs.setDouble('${prefix}_lat', clampedCenter.latitude);
    await prefs.setDouble('${prefix}_lng', clampedCenter.longitude);
    await prefs.setDouble('${prefix}_zoom', clampedZoom);
  }

  LatLng _clampToAustraliaCoreBounds(LatLng center) {
    return LatLng(
      AustraliaMapViewport.clampLatitude(center.latitude),
      AustraliaMapViewport.clampLongitude(center.longitude),
    );
  }

  LatLng _clampToAustraliaBounds(LatLng center) {
    return LatLng(
      AustraliaMapViewport.clampViewportLatitude(center.latitude),
      AustraliaMapViewport.clampViewportLongitude(center.longitude),
    );
  }

  bool _isInsideAustraliaCoreBounds(LatLng point) {
    return point.latitude >= AustraliaMapViewport.south &&
        point.latitude <= AustraliaMapViewport.north &&
        point.longitude >= AustraliaMapViewport.west &&
        point.longitude <= AustraliaMapViewport.east;
  }

  double _minimumVisibleAustraliaZoom(Size viewportSize) {
    return AustraliaMapViewport.minimumViewportZoom(
      viewportSize,
    ).clamp(AustraliaMapViewport.fallbackMinZoom, 18.2).toDouble();
  }

  Future<void> _maybeShowInitialKangarooHint() async {
    if (_didCheckInitialKangarooHint) return;
    _didCheckInitialKangarooHint = true;

    final prefs = await SharedPreferences.getInstance();
    const key = 'seen_map_initial_kangaroo_hint';
    final seen = prefs.getBool(key) ?? false;
    if (seen || !mounted || !_isHospitality) return;

    await prefs.setBool(key, true);
    if (!mounted || !_isHospitality) return;

    setState(() => _showInitialKangarooHint = true);
    _initialKangarooTimer?.cancel();
    _initialKangarooTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted) return;
      setState(() => _showInitialKangarooHint = false);
    });
  }

  Future<void> _loadData({required bool fromServer}) async {
    try {
      final restaurantDocs = await MapMarkersService.loadRestaurants(
        fromServer: fromServer,
        lightweight: true,
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

    try {
      final harvestPlaces =
          await HarvestPlacesService.loadCompleteHarvestPlaces();
      _harvestLocations = _buildHarvestLocations(harvestPlaces);
    } catch (e) {
      debugPrint('❌ Error harvest OSM vector: $e');
    }

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
      if (!hasData) continue;

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

  List<Map<String, Object?>> _buildHarvestLocations(List<HarvestPlace> places) {
    return places
        .where(
          (place) =>
              place.id.isNotEmpty &&
              place.latitude != 0 &&
              place.longitude != 0,
        )
        .map(
          (place) => <String, Object?>{
            'id': place.id,
            'lat': place.latitude,
            'lng': place.longitude,
            'data': place,
            'worked_here_count': 0,
          },
        )
        .toList(growable: false);
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
    setState(() {
      _selectedRestaurant = null;
      _selectedHarvest = null;
    });
    _setSelectedRestaurantId(null);
  }

  void _zoomToCluster(MarkerClusterNode cluster) {
    _clearTemporarySelection();
    var splitNode = cluster;
    while (splitNode.children.length == 1) {
      final onlyChild = splitNode.children.first;
      if (onlyChild is! MarkerClusterNode) break;
      splitNode = onlyChild;
    }
    final targetZoom = math
        .max(
          _currentZoom + (_clusterZoomStep - 0.3),
          splitNode.zoom + _clusterZoomStep,
        )
        .clamp(3.0, 18.2)
        .toDouble();
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

  void activateMapView() {
    if (!mounted) return;

    final targetCenter = _pendingCenter ?? _currentCenter;
    final targetZoom = _pendingZoom ?? _currentZoom;
    _pendingCenter = targetCenter;
    _pendingZoom = targetZoom;

    void triggerMove() {
      if (!mounted || !_mapReady) return;
      try {
        _mapController.move(targetCenter, targetZoom);
      } catch (_) {
        // The map can still be laying out inside the IndexedStack.
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      triggerMove();
      Future<void>.delayed(const Duration(milliseconds: 80), triggerMove);
      Future<void>.delayed(const Duration(milliseconds: 220), triggerMove);
    });
  }

  Rect? _globalRectForKey(GlobalKey key) {
    final renderObject = key.currentContext?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) {
      return null;
    }
    final offset = renderObject.localToGlobal(Offset.zero);
    return offset & renderObject.size;
  }

  Rect? get onboardingMapAreaRect => _globalRectForKey(_mapAreaKey);
  Rect? get onboardingCategorySwitchRect =>
      _globalRectForKey(_categorySwitchKey);
  Rect? get onboardingProfileButtonRect => _globalRectForKey(_profileButtonKey);
  Rect? get onboardingMailTileRect => _globalRectForKey(_automaticEmailTileKey);

  void setOnboardingEmailPreviewVisible(bool visible) {
    if (_showOnboardingEmailPreview == visible || !mounted) {
      return;
    }
    setState(() {
      _showOnboardingEmailPreview = visible;
    });
  }

  void _selectRestaurantMarker(Map<String, Object?> marker) {
    final selectedRestaurant = Map<String, dynamic>.from(marker['data'] as Map);
    final restaurantId = (selectedRestaurant['docId'] ?? '').toString();
    setState(() {
      _selectedHarvest = null;
      _selectedRestaurant = selectedRestaurant;
    });
    _setSelectedRestaurantId(restaurantId.isEmpty ? null : restaurantId);
    unawaited(
      _handlePositiveReviewAction(ReviewService.actionWorkplaceDetailOpened),
    );
  }

  void _selectHarvestMarker(Map<String, Object?> marker) {
    setState(() {
      _selectedRestaurant = null;
      _selectedHarvest = marker['data'] as HarvestPlace;
    });
    _setSelectedRestaurantId(null);
  }

  void _updateMarkers() {
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
                  ? AnimatedBuilder(
                      animation: _markerVisualStateListenable,
                      builder: (context, child) {
                        final selectedRestaurantId =
                            _selectedRestaurantIdNotifier.value;
                        return _restaurantMarkerIcon(
                          (r['marker_kind'] as _RestaurantMarkerKind?) ??
                              _RestaurantMarkerKind.standard,
                          isFavorite: _favoritePlacesNotifier.value.contains(
                            markerId,
                          ),
                          isSelected:
                              markerId.isNotEmpty &&
                              markerId == selectedRestaurantId,
                        );
                      },
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
    Color iconColor = Colors.white,
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
                    color: Colors.black.withValues(alpha: 0.18),
                    blurRadius: 9,
                    spreadRadius: 0,
                    offset: const Offset(0, 3),
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
              child: Icon(icon, size: iconSize, color: iconColor),
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
    if (_isHospitality) {
      _hospitalityCenter = _currentCenter;
      _hospitalityZoom = _currentZoom;
    } else {
      _harvestCenter = _currentCenter;
      _harvestZoom = _currentZoom;
    }
    final targetCenter = hospitality ? _hospitalityCenter : _harvestCenter;
    final targetZoom = hospitality ? _hospitalityZoom : _harvestZoom;
    setState(() {
      _isHospitality = hospitality;
      _currentCenter = targetCenter;
      _currentZoom = targetZoom;
      _pendingCenter = targetCenter;
      _pendingZoom = targetZoom;
      _selectedRestaurant = null;
      _selectedHarvest = null;
    });
    _setSelectedRestaurantId(null);
    _closeFilterOverlay();
    _updateMarkers();
    if (_mapReady) {
      _mapController.move(targetCenter, targetZoom);
      _pendingCenter = null;
      _pendingZoom = null;
    }
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
    unawaited(
      _handlePositiveReviewAction(
        ReviewService.actionContactOrExternalLinkTapped,
      ),
    );
  }

  // Centralizes review tracking so future triggers can reuse the same path.
  Future<void> _handlePositiveReviewAction(String actionType) async {
    await ReviewService.instance.registerPositiveAction(actionType: actionType);
    if (!mounted) return;
    await ReviewService.instance.maybeAskForReview(context);
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
    final isAdmin =
        isAdminSession || AdminButtonVisibilityService.instance.enabled.value;
    final parentContext = context;
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
                onSupport: () {
                  Navigator.of(context).pop();
                  DonationService.instance.showSupportPopup(parentContext);
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
    final opened = await ExternalLinkService.open(context, url);
    if (!mounted) return;
    if (opened) {
      unawaited(
        _handlePositiveReviewAction(
          ReviewService.actionContactOrExternalLinkTapped,
        ),
      );
    }
  }

  Future<void> _toggleFavorite(String restaurantId) async {
    if (restaurantId.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error: this place has no valid ID.')),
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
    _setFavoritePlaces(current);
    FavoritesService.broadcast(_favoritePlaces);
    if (current.contains(restaurantId)) {
      unawaited(_handlePositiveReviewAction(ReviewService.actionFavoriteSaved));
    }
  }

  void _updateLocalWorkedHere(String restaurantId, int delta) {
    for (final loc in _restaurantLocations) {
      if (loc['id'] == restaurantId) {
        final raw = loc['worked_here_count'] ?? 0;
        final current = (raw is num)
            ? raw.toInt()
            : int.tryParse(raw.toString()) ?? 0;
        loc['worked_here_count'] = math.max(0, current + delta);
      }
    }
    if (_selectedRestaurant != null &&
        _selectedRestaurant?['docId'] == restaurantId) {
      final raw = _selectedRestaurant?['worked_here_count'] ?? 0;
      final current = (raw is num)
          ? raw.toInt()
          : int.tryParse(raw.toString()) ?? 0;
      _selectedRestaurant!['worked_here_count'] = math.max(0, current + delta);
    }
  }

  int _currentWorkedHereCount(String restaurantId) {
    if (_selectedRestaurant != null &&
        _selectedRestaurant?['docId'] == restaurantId) {
      final raw = _selectedRestaurant?['worked_here_count'] ?? 0;
      return raw is num ? raw.toInt() : int.tryParse(raw.toString()) ?? 0;
    }

    for (final loc in _restaurantLocations) {
      if (loc['id'] != restaurantId) continue;
      final raw = loc['worked_here_count'] ?? 0;
      return raw is num ? raw.toInt() : int.tryParse(raw.toString()) ?? 0;
    }

    return 0;
  }

  Future<void> _showWorkedDialog(
    String restaurantId,
    String restaurantName,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final workedPlaces = Set<String>.from(
      prefs.getStringList('worked_places') ?? const <String>[],
    );
    if (!mounted) return;

    if (restaurantId.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error: this place has no valid ID.')),
      );
      return;
    }

    if (workedPlaces.contains(restaurantId)) {
      await _showAlreadyWorkedDialog(restaurantName);
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
      workedPlaces.add(restaurantId);
      final nextWorkedHereCount = _currentWorkedHereCount(restaurantId) + 1;
      try {
        await prefs.setStringList('worked_places', workedPlaces.toList());
        await MapMarkersService.rememberLocalWorkedHereCount(
          restaurantId,
          nextWorkedHereCount,
        );
        _updateLocalWorkedHere(restaurantId, 1);
        if (mounted) setState(() {});
        await MapMarkersService.incrementWorkedHere(restaurantId);
        await MapMarkersService.updateWorkedHereCache(restaurantId, 1);
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Saved on this device. Sync with the server can happen later.',
            ),
          ),
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

  Future<void> _showAlreadyWorkedDialog(String restaurantName) {
    final borderRadius = BorderRadius.circular(24);
    return showDialog<void>(
      context: context,
      builder: (dialogContext) {
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
                  Icons.info_outline_rounded,
                  size: 28,
                  color: Colors.black54,
                ),
                const SizedBox(height: 10),
                const Text(
                  'Already marked',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '$restaurantName is already in your worked list.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.black.withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.blueAccent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text('OK'),
                  ),
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
                          unawaited(
                            _handlePositiveReviewAction(
                              ReviewService.actionContactOrExternalLinkTapped,
                            ),
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
                          unawaited(
                            _handlePositiveReviewAction(
                              ReviewService.actionContactOrExternalLinkTapped,
                            ),
                          );
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
    final newZoom = (_currentZoom - _zoomOutStep).clamp(3.0, 18.0);
    _mapController.move(_currentCenter, newZoom);
  }

  Future<void> _goToUserLocation() async {
    if (_isLocating) return;
    setState(() => _isLocating = true);
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _showLocationServicesMessage();
        return;
      }
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        await _handleDeniedLocationPermission(permission);
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      final userTarget = LatLng(pos.latitude, pos.longitude);
      if (!_isInsideAustraliaCoreBounds(userTarget)) {
        if (!mounted) return;
        final fallbackCenter = _clampToAustraliaCoreBounds(_currentCenter);
        final minimumVisibleZoom = _minimumVisibleAustraliaZoom(
          MediaQuery.sizeOf(context),
        );
        final fallbackZoom = _currentZoom
            .clamp(minimumVisibleZoom, 18.2)
            .toDouble();
        _mapController.move(fallbackCenter, fallbackZoom);
        return;
      }
      _mapController.move(userTarget, 15);
    } catch (_) {
      _showLocationGenericError();
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  void _handleLocationFabPressed() {
    _removeLocationPermissionNotice();
    unawaited(_dismissLocationFabBadge());
    unawaited(_goToUserLocation());
  }

  Future<void> _handleDeniedLocationPermission(
    LocationPermission permission,
  ) async {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();

    if (permission == LocationPermission.deniedForever) {
      _showLocationPermissionNotice();
      return;
    }

    _removeLocationPermissionNotice();
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Location access denied. Tap again to allow it.'),
      ),
    );
  }

  void _showLocationServicesMessage() {
    if (!mounted) return;
    _removeLocationPermissionNotice();
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: const Text('Location services are turned off.'),
        action: SnackBarAction(
          label: 'Settings',
          onPressed: () {
            unawaited(Geolocator.openLocationSettings());
          },
        ),
      ),
    );
  }

  void _showLocationGenericError() {
    if (!mounted) return;
    _removeLocationPermissionNotice();
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      const SnackBar(
        content: Text('We could not get your location right now.'),
      ),
    );
  }

  void _showLocationPermissionNotice() {
    if (!mounted) return;
    _removeLocationPermissionNotice();

    final overlay = Overlay.of(context);

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) {
        return Stack(
          children: [
            const Positioned.fill(
              child: IgnorePointer(child: SizedBox.expand()),
            ),
            Positioned.fill(
              child: SafeArea(
                child: Align(
                  alignment: const Alignment(0, -0.1),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: MapNoticeCard(
                      message:
                          'Location access is blocked. Open settings, then go to Permissions > Location.',
                      actionLabel: 'Settings',
                      onAction: () {
                        _removeLocationPermissionNotice();
                        unawaited(_openLocationPermissionSettings());
                      },
                      onClose: _removeLocationPermissionNotice,
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );

    _locationPermissionNotice = entry;
    overlay.insert(entry);
  }

  void _removeLocationPermissionNotice() {
    _locationPermissionNotice?.remove();
    _locationPermissionNotice = null;
  }

  Future<void> _openLocationPermissionSettings() async {
    final opened =
        await LocationSettingsService.openLocationPermissionSettings();
    if (opened || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      const SnackBar(content: Text('Could not open location settings.')),
    );
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
    return ValueListenableBuilder<Set<String>>(
      valueListenable: _favoritePlacesNotifier,
      builder: (context, favoritePlaces, child) {
        return MapRestaurantPopup(
          data: r,
          workedCount: (r['worked_here_count'] ?? 0) as int,
          isFavorite: favoritePlaces.contains(docId),
          bottomOffset: kMapRestaurantPopupBottomOffset,
          onClose: _clearTemporarySelection,
          onWorkedHere: () =>
              _showWorkedDialog(docId, r['name'] ?? 'this place'),
          onCopyPhone: () => _copyToClipboard(r['phone'], 'copied phone'),
          onEmail: () => _showEmailOptions(r['email']),
          onFacebook: () => _openUrl(r['facebook_url']),
          onCareers: () => _openUrl(r['careers_page']),
          onInstagram: () => _openUrl(r['instagram_url']),
          onFavorite: () => _toggleFavorite(docId),
        );
      },
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
      activeMonths: data.activeMonths,
      crops: data.crops,
      cropsByMonth: data.cropsByMonth,
      bottomOffset: kMapPopupDockOffset,
      onClose: () {
        setState(() => _selectedHarvest = null);
        _setSelectedRestaurantId(null);
      },
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
    _setSelectedRestaurantId(null);
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
    _styleFuture ??= _loadStyle();

    return FutureBuilder<Style>(
      future: _styleFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError || !snapshot.hasData) {
          debugPrint('Map style load failed: ${snapshot.error}');
          return Scaffold(
            backgroundColor: _mapOceanBackgroundColor,
            body: AppCriticalErrorState(
              title: 'Map could not load',
              message:
                  'A required map resource could not load correctly. Please try again in a moment.',
              onRetry: () {
                _reloadStyle();
                _loadInitialData();
              },
            ),
          );
        }

        final style = snapshot.data!;
        final tileProviders = _optimizedTileProviders(style);

        return LayoutBuilder(
          builder: (context, constraints) {
            final minimumVisibleZoom = _minimumVisibleAustraliaZoom(
              Size(constraints.maxWidth, constraints.maxHeight),
            );
            final effectiveInitialCenter = _clampToAustraliaBounds(
              _initialCenter,
            );
            final effectiveInitialZoom = math.max(
              _initialZoom,
              minimumVisibleZoom,
            );

            if (!_didKickstartRender) {
              _didKickstartRender = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                _mapController.move(
                  effectiveInitialCenter,
                  effectiveInitialZoom,
                );
                unawaited(_maybeShowInitialKangarooHint());
              });
            }

            return Scaffold(
              backgroundColor: _mapOceanBackgroundColor,
              appBar: null,
              body: Stack(
                children: [
                  const Positioned.fill(
                    child: ColoredBox(color: _mapOceanBackgroundColor),
                  ),
                  SizedBox.expand(
                    key: _mapAreaKey,
                    child: FlutterMap(
                      mapController: _mapController,
                      options: MapOptions(
                        initialCenter: effectiveInitialCenter,
                        initialZoom: effectiveInitialZoom,
                        minZoom: minimumVisibleZoom,
                        maxZoom: 18.2,
                        cameraConstraint: CameraConstraint.contain(
                          bounds: _australiaViewportBounds,
                        ),
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
                          if (_isHospitality) {
                            _hospitalityCenter = _currentCenter;
                            _hospitalityZoom = _currentZoom;
                          } else {
                            _harvestCenter = _currentCenter;
                            _harvestZoom = _currentZoom;
                          }
                          _pendingCenter = _currentCenter;
                          _pendingZoom = _currentZoom;
                          final hospitality = _isHospitality;
                          final centerToPersist = _currentCenter;
                          final zoomToPersist = _currentZoom;
                          _persistDebounce?.cancel();
                          _persistDebounce = Timer(
                            const Duration(milliseconds: 500),
                            () {
                              _saveLastMapPosition(
                                centerToPersist,
                                zoomToPersist,
                                hospitality: hospitality,
                              );
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
                                  color: _clusterMarkerColor,
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: 0.22,
                                      ),
                                      blurRadius: 10,
                                      offset: const Offset(0, 4),
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
                              child: ValueListenableBuilder<AppUpdateNotice?>(
                                valueListenable: RemoteConfigService
                                    .instance
                                    .softUpdateNoticeListenable,
                                builder: (context, notice, _) {
                                  return SizedBox(
                                    key: _profileButtonKey,
                                    height: 48,
                                    width: 48,
                                    child: ProfileButtonIcon(
                                      showBadge: notice != null,
                                    ),
                                  );
                                },
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
                  if (_showOnboardingEmailPreview)
                    Positioned(
                      left: 0,
                      right: 0,
                      top: 0,
                      child: SafeArea(
                        child: Padding(
                          padding: const EdgeInsets.only(
                            left: 16,
                            top: 70,
                            right: 16,
                          ),
                          child: Align(
                            alignment: Alignment.topLeft,
                            child: IgnorePointer(
                              child: _ProfilePopupMenu(
                                onMail: () {},
                                onReports: () {},
                                onSupport: () {},
                                onFavorites: () {},
                                onAdmin: () {},
                                showAdmin: false,
                                automaticEmailTileKey: _automaticEmailTileKey,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (_isLoadingData)
                    const Center(child: CircularProgressIndicator()),
                  if (_isHospitality && _showInitialKangarooHint)
                    Positioned(
                      bottom: _initialKangarooBottomOffset,
                      right: 18,
                      child: IgnorePointer(
                        child: _kangarooLoader(size: 56, animate: true),
                      ),
                    ),
                  Positioned(
                    bottom: _locationFabBottom,
                    right: 16,
                    child: FloatingActionButton(
                      onPressed: _isLocating ? null : _handleLocationFabPressed,
                      heroTag: 'fab_location',
                      shape: const CircleBorder(),
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.blueGrey.shade700,
                      child: LocationFabIcon(
                        showBadge: _showLocationFabBadge,
                        isLoading: _isLocating,
                      ),
                    ),
                  ),
                  _buildRestaurantPopup(),
                  _buildHarvestPopup(),
                  if (_isHospitality && _showZoomOutButton)
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
  static const Color _hospitalityAccentColor = Color(0xFF9CAF9F);

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
                color: isSelected
                    ? _hospitalityAccentColor
                    : Colors.transparent,
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
                    label: 'Harvest',
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
            'assets/icons/farm_placeholder_map.png',
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
    required this.onSupport,
    required this.onFavorites,
    required this.onAdmin,
    required this.showAdmin,
    this.automaticEmailTileKey,
  });

  final VoidCallback onMail;
  final VoidCallback onReports;
  final VoidCallback onSupport;
  final VoidCallback onFavorites;
  final VoidCallback onAdmin;
  final bool showAdmin;
  final Key? automaticEmailTileKey;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: ValueListenableBuilder<AppUpdateNotice?>(
        valueListenable:
            RemoteConfigService.instance.softUpdateNoticeListenable,
        builder: (context, notice, _) {
          final showSoftUpdateMessage = notice != null;
          return Container(
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
                  tileKey: automaticEmailTileKey,
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
                const SizedBox(height: 14),
                _ProfileTile(
                  icon: Icons.local_cafe_outlined,
                  iconColor: const Color(0xFFB2872B),
                  iconBg: const Color(0xFFFFF3C4),
                  text: 'Buy me a coffe',
                  onTap: onSupport,
                ),
                if (showSoftUpdateMessage) ...[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 11,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF2F0),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: EdgeInsets.only(top: 4),
                          child: _ProfileUpdateDot(),
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'New version available',
                            style: TextStyle(
                              color: Color(0xFFCC6F6A),
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
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
          );
        },
      ),
    );
  }
}

class _ProfileUpdateDot extends StatelessWidget {
  const _ProfileUpdateDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: const BoxDecoration(
        color: Color(0xFFE53935),
        shape: BoxShape.circle,
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
    this.tileKey,
  });

  final IconData icon;
  final String text;
  final Color iconColor;
  final Color iconBg;
  final VoidCallback onTap;
  final Key? tileKey;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        key: tileKey,
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
