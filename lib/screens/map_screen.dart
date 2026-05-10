import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' as latlng;
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supercluster/supercluster.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/admin_config.dart';
import '../services/email_sender_service.dart';
import '../services/favorites_service.dart';
import '../services/location_settings_service.dart';
import '../services/map_markers_service.dart';
import '../services/overlay_helper.dart';
import '../services/remote_config_service.dart';
import '../services/review_service.dart';
import '../services/runtime_device_service.dart';
import '../utils/australia_map_viewport.dart';
import '../widgets/location_fab_icon.dart';
import '../widgets/map_notice_card.dart';
import '../widgets/map_place_popup.dart';
import '../widgets/profile_button_icon.dart';
import 'admin_page.dart';
import 'favorites_screen.dart';
import 'mail_setup_page.dart';
import 'map_osm_vector_page.dart' show MapOSMVectorPage, MapOSMVectorPageState;
import 'map_renderer_selector.dart';
import 'report_message_page.dart';

enum Category { hospitality, farm }

enum _RestaurantMarkerKind { standard, night, cafe }

class _RestaurantMapPoint {
  const _RestaurantMapPoint(this.location);

  final Map<String, Object?> location;

  String get id => (location['id'] ?? '').toString();

  double get lat => (location['lat'] as num).toDouble();

  double get lng => (location['lng'] as num).toDouble();

  LatLng get latLng => LatLng(lat, lng);
}

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => MapScreenState();
}

class MapScreenState extends State<MapScreen> with TickerProviderStateMixin {
  static const String _defaultStyleAssetPath = 'assets/map/style.json';
  static const bool _enablePmtilesDiagnostics = false;
  static const Color _mapOceanBackgroundColor = Color(0xFFCFE1EC);
  static const String _vectorSourceId = 'australia';
  static const List<String> _diagnosticSourceLayers = <String>[
    'earth',
    'water',
    'roads',
    'places',
  ];
  static const double _defaultZoom = 3.8;
  static const double _maxMapZoom = 18.2;
  static const bool _showZoomOutButton = false;
  static const double _locationFabBottom = 144;
  static const double _initialKangarooBottomOffset = 212;
  static const double _zoomOutStep = 1.2;
  static const String _favoriteMarkerImageName = 'workyday-marker-favorite';
  static const String _favoriteSelectedMarkerImageName =
      'workyday-marker-favorite-selected';
  static const String _nightMarkerImageName = 'workyday-marker-night';
  static const String _nightSelectedMarkerImageName =
      'workyday-marker-night-selected';
  static const String _cafeMarkerImageName = 'workyday-marker-cafe';
  static const String _cafeSelectedMarkerImageName =
      'workyday-marker-cafe-selected';
  static const String _standardMarkerImageName = 'workyday-marker-standard';
  static const String _standardSelectedMarkerImageName =
      'workyday-marker-standard-selected';
  static const String _seenInitialKangarooHintKey =
      'seen_map_initial_kangaroo_hint';
  static const String _seenProfileTooltipKey = 'seen_map_profile_tooltip';
  static const String _dismissedLocationFabBadgeKey =
      'dismissed_map_location_fab_badge';
  static const LatLng _australiaCenter = LatLng(-25.0, 133.0);
  static final LatLngBounds _defaultSearchBounds = LatLngBounds(
    southwest: const LatLng(
      AustraliaMapViewport.south,
      AustraliaMapViewport.west,
    ),
    northeast: const LatLng(
      AustraliaMapViewport.north,
      AustraliaMapViewport.east,
    ),
  );
  static final LatLngBounds _mapCameraBounds = LatLngBounds(
    southwest: const LatLng(
      AustraliaMapViewport.viewportSouth,
      AustraliaMapViewport.viewportWest,
    ),
    northeast: const LatLng(
      AustraliaMapViewport.viewportNorth,
      AustraliaMapViewport.viewportEast,
    ),
  );
  late final MapRendererKind _rendererKind = resolveMapRendererKind();

  final GlobalKey _mapAreaKey = GlobalKey();
  final GlobalKey _profileButtonKey = GlobalKey();
  final GlobalKey _categorySwitchKey = GlobalKey();
  final GlobalKey _automaticEmailTileKey = GlobalKey();
  final GlobalKey<MapOSMVectorPageState> _fallbackMapKey =
      GlobalKey<MapOSMVectorPageState>();
  final LayerLink _filterLink = LayerLink();

  late Future<String> _styleFuture = _loadStyleString();
  late final AnimationController _kangarooController;
  late final AnimationController _tooltipController;
  late final AnimationController _pulseController;
  final ValueNotifier<Set<String>> _favoritePlacesNotifier =
      ValueNotifier<Set<String>>(<String>{});
  final ValueNotifier<String?> _selectedRestaurantIdNotifier =
      ValueNotifier<String?>(null);
  final List<Map<String, dynamic>> _sourceOptions = const [
    {'key': 'gmail', 'label': 'Gmail', 'icon': Icons.email},
    {'key': 'facebook', 'label': 'Facebook', 'icon': Icons.facebook},
    {'key': 'instagram', 'label': 'IG', 'icon': Icons.camera_alt},
    {'key': 'careers', 'label': 'Careers', 'icon': Icons.work},
  ];

  MapLibreMapController? _mapController;
  StreamSubscription<Set<String>>? _favoritesSub;
  OverlayEntry? _profileTooltip;
  OverlayEntry? _filterOverlay;
  OverlayEntry? _locationPermissionNotice;
  Timer? _tooltipTimer;
  Timer? _persistDebounce;
  Timer? _initialKangarooTimer;

  LatLng _initialCenter = _australiaCenter;
  double _initialZoom = _defaultZoom;
  LatLng _currentCenter = _australiaCenter;
  double _currentZoom = _defaultZoom;

  bool _isStyleLoaded = false;
  bool _isLoadingData = true;
  bool _isLocating = false;
  bool _showOnboardingEmailPreview = false;
  bool _showInitialKangarooHint = false;
  bool _didCheckInitialKangarooHint = false;
  bool _showLocationFabBadge = true;
  bool _annotationRefreshRunning = false;
  bool _annotationRefreshQueued = false;
  bool _farmMapEnabled = false;
  bool _isHospitality = true;

  Set<String> _favoritePlaces = <String>{};
  final Set<String> _selectedSources = <String>{};
  final Set<String> _addedStyleImages = <String>{};
  final Map<int, String> _clusterImageNames = <int, String>{};
  final Map<String, Map<String, dynamic>> _restaurantDataById =
      <String, Map<String, dynamic>>{};
  final Map<String, Map<String, Object?>> _restaurantLocationById =
      <String, Map<String, Object?>>{};

  List<Map<String, Object?>> _restaurantLocations = <Map<String, Object?>>[];
  List<Map<String, Object?>> _visibleRestaurantLocations =
      <Map<String, Object?>>[];
  SuperclusterImmutable<_RestaurantMapPoint>? _restaurantClusterIndex;
  Map<String, dynamic>? _selectedRestaurant;

  String get _styleAssetPath => _defaultStyleAssetPath;
  bool get _useVectorPmtilesFallback =>
      _rendererKind == MapRendererKind.vectorPmtilesFallback;
  MapOSMVectorPageState? get _fallbackMapState => _fallbackMapKey.currentState;

  @override
  void initState() {
    super.initState();
    _logRendererSelection();
    if (_useVectorPmtilesFallback) {
      return;
    }
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
    unawaited(_loadFavorites());
    _favoritesSub = FavoritesService.changes.listen((ids) {
      if (_setEquals(_favoritePlaces, ids)) return;
      _setFavoritePlaces(ids);
      unawaited(_scheduleAnnotationRefresh());
    });
    unawaited(_loadLocationFabBadgeState());
    unawaited(_loadLastMapPosition());
    unawaited(_loadInitialData());
  }

  @override
  void dispose() {
    if (_useVectorPmtilesFallback) {
      super.dispose();
      return;
    }
    _favoritesSub?.cancel();
    _persistDebounce?.cancel();
    _tooltipTimer?.cancel();
    _initialKangarooTimer?.cancel();
    _removeProfileTooltip();
    _closeFilterOverlay();
    _removeLocationPermissionNotice();
    _favoritePlacesNotifier.dispose();
    _selectedRestaurantIdNotifier.dispose();
    _kangarooController.dispose();
    _tooltipController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  Future<String> _loadStyleString() async {
    final styleText = await rootBundle.loadString(_styleAssetPath);
    _logStyleAssetSummary(styleText);
    return styleText;
  }

  void _logRendererSelection() {
    final rendererLabel = mapRendererLabel(_rendererKind);
    if (_useVectorPmtilesFallback) {
      final fallbackPlatform = RuntimeDeviceService.instance.isIosSimulator
          ? 'iOS Simulator'
          : defaultTargetPlatform == TargetPlatform.iOS
          ? 'iOS'
          : defaultTargetPlatform == TargetPlatform.android
          ? 'Android'
          : 'this platform';
      debugPrint(
        '🧭 Map renderer selected: $rendererLabel fallback on $fallbackPlatform.',
      );
      debugPrint(
        '🧭 Using vector_map_tiles_pmtiles for this screen because MapLibre is not rendering the PMTiles map correctly on $fallbackPlatform.',
      );
      return;
    }

    debugPrint(
      '🧭 Map renderer selected: $rendererLabel with local style asset $_styleAssetPath.',
    );
  }

  void _logStyleAssetSummary(String styleText) {
    if (!_enablePmtilesDiagnostics) return;
    try {
      final decoded = jsonDecode(styleText);
      if (decoded is! Map<String, dynamic>) {
        debugPrint('🧭 MapLibre style asset is not a JSON object');
        return;
      }
      final sources = decoded['sources'];
      String? sourceUrl;
      String? sourceType;
      if (sources is Map) {
        final source = sources[_vectorSourceId];
        if (source is Map) {
          sourceUrl = source['url']?.toString();
          sourceType = source['type']?.toString();
        }
      }
      debugPrint(
        '🧭 Loading MapLibre style asset=$_styleAssetPath source=$_vectorSourceId type=$sourceType url=$sourceUrl',
      );
      if (sourceUrl != null && sourceUrl.startsWith('pmtiles://')) {
        debugPrint(
          '🧭 PMTiles source detected. If only the background renders, inspect native PMTiles runtime support and tile loading logs.',
        );
      }
    } catch (error) {
      debugPrint('🧭 Could not inspect MapLibre style asset: $error');
    }
  }

  bool _setEquals(Set<String> a, Set<String> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (final value in a) {
      if (!b.contains(value)) return false;
    }
    return true;
  }

  int _parseCount(dynamic raw) {
    return switch (raw) {
      int value => value,
      num value => value.toInt(),
      _ => int.tryParse(raw?.toString() ?? '') ?? 0,
    };
  }

  Rect? _globalRectForKey(GlobalKey key) {
    final renderObject = key.currentContext?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) {
      return null;
    }
    final offset = renderObject.localToGlobal(Offset.zero);
    return offset & renderObject.size;
  }

  Rect? get onboardingMapAreaRect => _useVectorPmtilesFallback
      ? _fallbackMapState?.onboardingMapAreaRect
      : _globalRectForKey(_mapAreaKey);

  Rect? get onboardingMailTileRect => _useVectorPmtilesFallback
      ? _fallbackMapState?.onboardingMailTileRect
      : _globalRectForKey(_automaticEmailTileKey);

  bool get hasTransientSelection => _useVectorPmtilesFallback
      ? (_fallbackMapState?.hasTransientSelection ?? false)
      : _selectedRestaurant != null;

  bool consumeBackPress() {
    if (_useVectorPmtilesFallback) {
      return _fallbackMapState?.consumeBackPress() ?? false;
    }
    if (!hasTransientSelection) return false;
    _clearTemporarySelection();
    return true;
  }

  void activateMapView() {
    if (_useVectorPmtilesFallback) {
      _fallbackMapState?.activateMapView();
      return;
    }
    final controller = _mapController;
    if (controller == null || !mounted) return;
    final targetCenter = _currentCenter;
    final targetZoom = _currentZoom;

    void triggerRefresh() {
      if (!mounted) return;
      unawaited(
        controller.animateCamera(
          CameraUpdate.newLatLngZoom(targetCenter, targetZoom),
        ),
      );
      unawaited(_scheduleAnnotationRefresh());
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      triggerRefresh();
      Future<void>.delayed(const Duration(milliseconds: 120), triggerRefresh);
    });
  }

  Future<void> showProfileTooltipIfNeeded() {
    if (_useVectorPmtilesFallback) {
      return _fallbackMapState?.showProfileTooltipIfNeeded() ??
          Future<void>.value();
    }
    return _maybeShowProfileTooltip();
  }

  void setOnboardingEmailPreviewVisible(bool visible) {
    if (_useVectorPmtilesFallback) {
      _fallbackMapState?.setOnboardingEmailPreviewVisible(visible);
      return;
    }
    if (_showOnboardingEmailPreview == visible || !mounted) return;
    setState(() {
      _showOnboardingEmailPreview = visible;
    });
  }

  Future<void> _loadLastMapPosition() async {
    final prefs = await SharedPreferences.getInstance();
    final lat = prefs.getDouble('map_last_lat');
    final lng = prefs.getDouble('map_last_lng');
    final zoom = prefs.getDouble('map_last_zoom');

    if (lat == null || lng == null || zoom == null) {
      return;
    }

    final clampedZoom = zoom.clamp(6.0, 12.0).toDouble();
    final center = _clampToAustraliaBounds(LatLng(lat, lng));
    if (!mounted) return;
    setState(() {
      _initialCenter = center;
      _initialZoom = clampedZoom;
      _currentCenter = center;
      _currentZoom = clampedZoom;
    });
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
      setState(() {
        _showLocationFabBadge = false;
      });
    } else {
      _showLocationFabBadge = false;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_dismissedLocationFabBadgeKey, true);
  }

  Future<void> _saveLastMapPosition(LatLng center, double zoom) async {
    final prefs = await SharedPreferences.getInstance();
    final clampedZoom = zoom.clamp(6.0, 12.0).toDouble();
    final clampedCenter = _clampToAustraliaBounds(center);
    await prefs.setDouble('map_last_lat', clampedCenter.latitude);
    await prefs.setDouble('map_last_lng', clampedCenter.longitude);
    await prefs.setDouble('map_last_zoom', clampedZoom);
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
    ).clamp(AustraliaMapViewport.fallbackMinZoom, _maxMapZoom).toDouble();
  }

  Future<void> _loadFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList('favorite_places') ?? const <String>[];
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

  Future<void> _loadInitialData() async {
    if (mounted) {
      setState(() => _isLoadingData = true);
    }
    await _loadData(fromServer: false);
    if (!mounted) return;
    setState(() => _isLoadingData = false);
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
    } catch (error) {
      debugPrint('❌ Error carregant restaurants MapLibre: $error');
    }

    _recomputeVisibleRestaurants();
    _rebuildRestaurantClusterIndex();
    await _scheduleAnnotationRefresh();
  }

  List<Map<String, Object?>> _buildRestaurantLocations(
    List<Map<String, dynamic>> docs,
  ) {
    final locations = <Map<String, Object?>>[];
    _restaurantDataById.clear();
    _restaurantLocationById.clear();

    for (final data in docs) {
      final lat = (data['latitude'] ?? data['lat']) as num?;
      final lng = (data['longitude'] ?? data['lng']) as num?;
      if (lat == null || lng == null) continue;

      final docId = (data['docId'] ?? '').toString();
      if (docId.isEmpty || data['blocked'] == true) continue;

      final hasData =
          (data['facebook_url'] ?? '').toString().isNotEmpty ||
          (data['instagram_url'] ?? '').toString().isNotEmpty ||
          (data['email'] ?? '').toString().isNotEmpty ||
          (data['careers_page'] ?? '').toString().isNotEmpty;
      if (!hasData) continue;

      final location = <String, Object?>{
        'id': docId,
        'lat': lat.toDouble(),
        'lng': lng.toDouble(),
        'data': data,
        'worked_here_count': _parseCount(data['worked_here_count']),
        'sources': _extractSources(data),
        'marker_kind': _classifyRestaurantMarker(data),
      };
      _restaurantDataById[docId] = Map<String, dynamic>.from(data);
      _restaurantLocationById[docId] = location;
      locations.add(location);
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
        return const <Map<String, dynamic>>[];
      }
      return list
          .map((e) => Map<String, dynamic>.from(e as Map))
          .map((e) {
            e['docId'] ??= e['id'];
            return e;
          })
          .where((e) => (e['docId'] ?? '').toString().isNotEmpty)
          .toList();
    } catch (error) {
      debugPrint('ℹ️ Cap seed local de restaurants: $error');
      return const <Map<String, dynamic>>[];
    }
  }

  void _recomputeVisibleRestaurants() {
    if (_selectedSources.isEmpty) {
      _visibleRestaurantLocations = _restaurantLocations;
    } else {
      _visibleRestaurantLocations = _restaurantLocations
          .where(_passesFilter)
          .toList(growable: false);
    }
  }

  void _rebuildRestaurantClusterIndex() {
    final points = _visibleRestaurantLocations
        .map((location) => _RestaurantMapPoint(location))
        .toList(growable: false);
    if (points.isEmpty) {
      _restaurantClusterIndex = null;
      return;
    }
    final clusterIndex = SuperclusterImmutable<_RestaurantMapPoint>(
      getX: (point) => point.lng,
      getY: (point) => point.lat,
      maxZoom: 16,
      radius: 54,
    )..load(points);
    _restaurantClusterIndex = clusterIndex;
  }

  Future<void> _scheduleAnnotationRefresh() async {
    if (_annotationRefreshRunning) {
      _annotationRefreshQueued = true;
      return;
    }

    _annotationRefreshRunning = true;
    try {
      do {
        _annotationRefreshQueued = false;
        await _refreshMapAnnotationsInternal();
      } while (_annotationRefreshQueued && mounted);
    } finally {
      _annotationRefreshRunning = false;
    }
  }

  Future<void> _refreshMapAnnotationsInternal() async {
    final controller = _mapController;
    if (!mounted || controller == null || !_isStyleLoaded) return;

    try {
      if (!_isHospitality) {
        await controller.clearSymbols();
        return;
      }

      await _ensureStyleImagesLoaded();
      final clusterIndex = _restaurantClusterIndex;
      if (clusterIndex == null) {
        await controller.clearSymbols();
        return;
      }

      LatLngBounds visibleBounds;
      try {
        visibleBounds = await controller.getVisibleRegion();
      } catch (_) {
        visibleBounds = _defaultSearchBounds;
      }

      final west = visibleBounds.southwest.longitude;
      final south = visibleBounds.southwest.latitude;
      final east = visibleBounds.northeast.longitude;
      final north = visibleBounds.northeast.latitude;
      final searchBounds = east < west
          ? _defaultSearchBounds
          : LatLngBounds(
              southwest: LatLng(south, west),
              northeast: LatLng(north, east),
            );

      final elements = clusterIndex.search(
        searchBounds.southwest.longitude,
        searchBounds.southwest.latitude,
        searchBounds.northeast.longitude,
        searchBounds.northeast.latitude,
        _currentZoom.floor(),
      );

      final options = <SymbolOptions>[];
      final data = <Map<String, dynamic>>[];

      for (final element in elements) {
        switch (element) {
          case ImmutableLayerCluster<_RestaurantMapPoint> cluster:
            final count = cluster.childPointCount;
            final imageName = await _ensureClusterStyleImage(count);
            options.add(
              SymbolOptions(
                geometry: LatLng(cluster.latitude, cluster.longitude),
                iconImage: imageName,
                iconAnchor: 'center',
              ),
            );
            data.add({
              'type': 'cluster',
              'clusterId': cluster.id,
              'latitude': cluster.latitude,
              'longitude': cluster.longitude,
            });
          case ImmutableLayerPoint<_RestaurantMapPoint> point:
            final imageName = _markerImageNameForLocation(
              point.originalPoint.location,
            );
            options.add(
              SymbolOptions(
                geometry: point.originalPoint.latLng,
                iconImage: imageName,
                iconAnchor: 'bottom',
              ),
            );
            data.add({
              'type': 'restaurant',
              'restaurantId': point.originalPoint.id,
            });
        }
      }

      await controller.clearSymbols();
      if (options.isNotEmpty) {
        await controller.addSymbols(options, data);
      }
    } catch (error) {
      debugPrint('❌ Error refrescant anotacions MapLibre: $error');
    }
  }

  Future<void> _ensureStyleImagesLoaded() async {
    final controller = _mapController;
    if (controller == null || !_isStyleLoaded) return;

    await _ensureNamedStyleImage(
      _favoriteMarkerImageName,
      await _buildPinIconBytes(
        fill: Colors.pinkAccent,
        icon: Icons.favorite,
        iconSize: 15,
      ),
    );
    await _ensureNamedStyleImage(
      _favoriteSelectedMarkerImageName,
      await _buildPinIconBytes(
        fill: Colors.pinkAccent,
        icon: Icons.favorite,
        iconSize: 15,
        outlineColor: const Color(0xFFE53935),
      ),
    );
    await _ensureNamedStyleImage(
      _nightMarkerImageName,
      await _buildPinIconBytes(
        fill: const Color(0xFF6D28D9),
        icon: Icons.local_bar,
        iconSize: 16,
      ),
    );
    await _ensureNamedStyleImage(
      _nightSelectedMarkerImageName,
      await _buildPinIconBytes(
        fill: const Color(0xFF6D28D9),
        icon: Icons.local_bar,
        iconSize: 16,
        outlineColor: const Color(0xFFE53935),
      ),
    );
    await _ensureNamedStyleImage(
      _cafeMarkerImageName,
      await _buildPinIconBytes(
        fill: const Color(0xFF111827),
        icon: Icons.local_cafe,
        iconSize: 16,
      ),
    );
    await _ensureNamedStyleImage(
      _cafeSelectedMarkerImageName,
      await _buildPinIconBytes(
        fill: const Color(0xFF111827),
        icon: Icons.local_cafe,
        iconSize: 16,
        outlineColor: const Color(0xFFE53935),
      ),
    );
    await _ensureNamedStyleImage(
      _standardMarkerImageName,
      await _buildPinIconBytes(
        fill: const Color(0xFFFF8A00),
        icon: Icons.restaurant,
        iconSize: 16,
      ),
    );
    await _ensureNamedStyleImage(
      _standardSelectedMarkerImageName,
      await _buildPinIconBytes(
        fill: const Color(0xFFFF8A00),
        icon: Icons.restaurant,
        iconSize: 16,
        outlineColor: const Color(0xFFE53935),
      ),
    );
  }

  Future<void> _ensureNamedStyleImage(String name, Uint8List bytes) async {
    final controller = _mapController;
    if (controller == null || _addedStyleImages.contains(name)) return;
    await controller.addImage(name, bytes);
    _addedStyleImages.add(name);
  }

  Future<String> _ensureClusterStyleImage(int count) async {
    final imageName = _clusterImageNames[count] ??= 'workyday-cluster-$count';
    if (_addedStyleImages.contains(imageName)) {
      return imageName;
    }
    await _ensureNamedStyleImage(
      imageName,
      await _buildClusterIconBytes(count),
    );
    return imageName;
  }

  String _markerImageNameForLocation(Map<String, Object?> location) {
    final markerId = (location['id'] ?? '').toString();
    final isFavorite = _favoritePlacesNotifier.value.contains(markerId);
    final isSelected =
        markerId.isNotEmpty && markerId == _selectedRestaurantIdNotifier.value;
    if (isFavorite) {
      return isSelected
          ? _favoriteSelectedMarkerImageName
          : _favoriteMarkerImageName;
    }

    return switch ((location['marker_kind'] as _RestaurantMarkerKind?) ??
        _RestaurantMarkerKind.standard) {
      _RestaurantMarkerKind.night =>
        isSelected ? _nightSelectedMarkerImageName : _nightMarkerImageName,
      _RestaurantMarkerKind.cafe =>
        isSelected ? _cafeSelectedMarkerImageName : _cafeMarkerImageName,
      _RestaurantMarkerKind.standard =>
        isSelected
            ? _standardSelectedMarkerImageName
            : _standardMarkerImageName,
    };
  }

  Future<Uint8List> _buildPinIconBytes({
    required Color fill,
    required IconData icon,
    required double iconSize,
    Color? outlineColor,
  }) async {
    const width = 48.0;
    const height = 58.0;
    const circleRadius = 14.0;
    const tailHalfWidth = 7.0;
    const tailHeight = 10.0;
    const outlineWidth = 2.0;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    const circleCenter = Offset(width / 2, 18);
    final hasOutline = outlineColor != null;

    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.20)
      ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 6);
    canvas.drawCircle(
      Offset(circleCenter.dx, circleCenter.dy + 3),
      circleRadius,
      shadowPaint,
    );

    final tailPath = ui.Path()
      ..moveTo(circleCenter.dx, circleCenter.dy + circleRadius + tailHeight)
      ..lineTo(
        circleCenter.dx - tailHalfWidth,
        circleCenter.dy + circleRadius - 2,
      )
      ..lineTo(
        circleCenter.dx + tailHalfWidth,
        circleCenter.dy + circleRadius - 2,
      )
      ..close();
    canvas.drawPath(
      tailPath.shift(const Offset(0, 3)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.12)
        ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 6),
    );

    final fillPaint = Paint()..color = fill;
    canvas.drawCircle(circleCenter, circleRadius, fillPaint);
    canvas.drawPath(tailPath, fillPaint);

    if (hasOutline) {
      final outlinePaint = Paint()
        ..color = outlineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = outlineWidth
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round;
      canvas.drawCircle(circleCenter, circleRadius, outlinePaint);
      final tailOutlinePath = ui.Path()
        ..moveTo(circleCenter.dx, circleCenter.dy + circleRadius + tailHeight)
        ..lineTo(
          circleCenter.dx - tailHalfWidth,
          circleCenter.dy + circleRadius - 2,
        )
        ..moveTo(circleCenter.dx, circleCenter.dy + circleRadius + tailHeight)
        ..lineTo(
          circleCenter.dx + tailHalfWidth,
          circleCenter.dy + circleRadius - 2,
        );
      canvas.drawPath(tailOutlinePath, outlinePaint);
    }

    final iconPainter = TextPainter(
      textDirection: TextDirection.ltr,
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontSize: iconSize,
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          color: Colors.white,
        ),
      ),
    )..layout();
    iconPainter.paint(
      canvas,
      Offset(
        circleCenter.dx - (iconPainter.width / 2),
        circleCenter.dy - (iconPainter.height / 2),
      ),
    );

    final image = await recorder.endRecording().toImage(
      width.ceil(),
      height.ceil(),
    );
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  }

  Future<Uint8List> _buildClusterIconBytes(int count) async {
    const size = 46.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final center = const Offset(size / 2, size / 2);
    final radius = size / 2 - 3;

    canvas.drawCircle(
      Offset(center.dx, center.dy + 2),
      radius,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.18)
        ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 7),
    );
    canvas.drawCircle(center, radius, Paint()..color = const Color(0xFF111827));
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = Colors.white.withValues(alpha: 0.26),
    );

    final label = count.toString();
    final fontSize = switch (label.length) {
      <= 2 => 17.0,
      3 => 15.0,
      _ => 13.0,
    };
    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: Colors.white,
          fontSize: fontSize,
          fontWeight: FontWeight.w800,
        ),
      ),
    )..layout();
    textPainter.paint(
      canvas,
      Offset(
        center.dx - (textPainter.width / 2),
        center.dy - (textPainter.height / 2),
      ),
    );

    final image = await recorder.endRecording().toImage(
      size.ceil(),
      size.ceil(),
    );
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  }

  void _handleMapCreated(MapLibreMapController controller) {
    _mapController = controller;
    if (_enablePmtilesDiagnostics) {
      debugPrint(
        '🧭 MapLibre controller created for style asset=$_styleAssetPath',
      );
    }
    controller.onSymbolTapped.add(_handleSymbolTapped);
  }

  void _handleSymbolTapped(Symbol symbol) {
    final payload = Map<String, dynamic>.from(
      symbol.data ?? const <String, dynamic>{},
    );
    final type = (payload['type'] ?? '').toString();
    if (type == 'restaurant') {
      _selectRestaurantById((payload['restaurantId'] ?? '').toString());
      return;
    }
    if (type == 'cluster') {
      final clusterId = payload['clusterId'] as int?;
      final latitude = payload['latitude'] as double?;
      final longitude = payload['longitude'] as double?;
      if (clusterId == null || latitude == null || longitude == null) return;
      unawaited(_expandCluster(clusterId, LatLng(latitude, longitude)));
    }
  }

  Future<void> _handleStyleLoaded() async {
    _isStyleLoaded = true;
    _addedStyleImages.clear();
    _clusterImageNames.clear();
    unawaited(_runPmtilesDiagnostics());
    await _ensureStyleImagesLoaded();
    await _mapController?.symbolManager?.setIconAllowOverlap(true);
    await _mapController?.symbolManager?.setIconIgnorePlacement(true);
    await _scheduleAnnotationRefresh();
    unawaited(_maybeShowInitialKangarooHint());
  }

  Future<void> _runPmtilesDiagnostics() async {
    if (!_enablePmtilesDiagnostics) return;
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await _logPmtilesDiagnostics(stage: 'style-loaded');
    await Future<void>.delayed(const Duration(seconds: 2));
    await _logPmtilesDiagnostics(stage: 'style-loaded+2s');
  }

  Future<void> _logPmtilesDiagnostics({required String stage}) async {
    if (!mounted || !_isStyleLoaded) return;
    final controller = _mapController;
    if (controller == null) return;

    try {
      final sourceIds = await controller.getSourceIds();
      final layerIds = await controller.getLayerIds();
      debugPrint('🧭 [$stage] sourceIds=$sourceIds');
      debugPrint(
        '🧭 [$stage] layerCount=${layerIds.length} firstLayers=${layerIds.take(8).toList()}',
      );

      var totalFeatures = 0;
      for (final sourceLayer in _diagnosticSourceLayers) {
        final features = await controller.querySourceFeatures(
          _vectorSourceId,
          sourceLayer,
          null,
        );
        totalFeatures += features.length;
        debugPrint(
          '🧭 [$stage] source=$_vectorSourceId source-layer=$sourceLayer featureCount=${features.length}',
        );
      }

      final renderObject = _mapAreaKey.currentContext?.findRenderObject();
      if (renderObject is RenderBox && renderObject.hasSize) {
        final size = renderObject.size;
        final visibleFeatures = await controller.queryRenderedFeaturesInRect(
          Rect.fromLTWH(0, 0, size.width, size.height),
          const <String>[
            'earth',
            'water-fill',
            'roads-major',
            'roads-highway',
            'earth-debug',
            'water-debug',
            'roads-debug',
          ],
          null,
        );
        debugPrint(
          '🧭 [$stage] renderedFeatureCount=${visibleFeatures.length} viewport=${size.width.toStringAsFixed(1)}x${size.height.toStringAsFixed(1)}',
        );
      }

      if (sourceIds.contains(_vectorSourceId) && totalFeatures == 0) {
        debugPrint(
          '⚠️ [$stage] Source "$_vectorSourceId" is present in the style, but no source features were returned. This usually means the PMTiles archive is not being read by the native runtime yet.',
        );
      }
    } catch (error) {
      debugPrint('❌ [$stage] PMTiles diagnostics failed: $error');
    }
  }

  void _handleCameraMove(CameraPosition cameraPosition) {
    _currentCenter = cameraPosition.target;
    _currentZoom = cameraPosition.zoom;
  }

  void _handleCameraIdle() {
    _persistDebounce?.cancel();
    _persistDebounce = Timer(const Duration(milliseconds: 350), () {
      unawaited(_saveLastMapPosition(_currentCenter, _currentZoom));
    });
    unawaited(_scheduleAnnotationRefresh());
  }

  void _clearTemporarySelection() {
    if (_selectedRestaurant == null) return;
    setState(() {
      _selectedRestaurant = null;
    });
    _setSelectedRestaurantId(null);
    unawaited(_scheduleAnnotationRefresh());
  }

  void _selectRestaurantById(String restaurantId) {
    final restaurant = _restaurantDataById[restaurantId];
    if (restaurant == null) return;
    setState(() {
      _selectedRestaurant = Map<String, dynamic>.from(restaurant);
    });
    _setSelectedRestaurantId(restaurantId);
    unawaited(_scheduleAnnotationRefresh());
    unawaited(
      _handlePositiveReviewAction(ReviewService.actionWorkplaceDetailOpened),
    );
  }

  Future<void> _expandCluster(int clusterId, LatLng target) async {
    _clearTemporarySelection();
    final controller = _mapController;
    final clusterIndex = _restaurantClusterIndex;
    if (controller == null || clusterIndex == null) return;

    final expansionZoom = clusterIndex
        .expansionZoomOf(clusterId)
        .toDouble()
        .clamp((_currentZoom + 1).floorToDouble(), _maxMapZoom);
    await controller.animateCamera(
      CameraUpdate.newLatLngZoom(target, expansionZoom),
      duration: const Duration(milliseconds: 250),
    );
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

  Set<String> _extractSources(Map<String, dynamic> data) {
    final sources = <String>{};
    final rawSource = data['source'] ?? data['platform'];

    String normalize(String value) {
      final normalized = value.toLowerCase().trim();
      if (normalized.contains('facebook') || normalized == 'fb') {
        return 'facebook';
      }
      if (normalized.contains('insta') || normalized == 'ig') {
        return 'instagram';
      }
      if (normalized.contains('career') || normalized.contains('jobs')) {
        return 'careers';
      }
      if (normalized.contains('mail')) {
        return 'gmail';
      }
      return normalized;
    }

    void addSource(dynamic value) {
      if (value == null) return;
      final normalized = normalize(value.toString());
      if (normalized.isNotEmpty) {
        sources.add(normalized);
      }
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
    if (_selectedSources.isEmpty) return true;
    final rawSources = location['sources'];
    final sources = rawSources is Set<String>
        ? rawSources
        : rawSources is Iterable
        ? rawSources.whereType<String>()
        : const Iterable<String>.empty();
    if (sources.isEmpty) return false;
    return sources.any(_selectedSources.contains);
  }

  bool get _allSelected => _selectedSources.isEmpty;

  void _setSourceSelection(String sourceKey, bool selected) {
    if (sourceKey == 'all') {
      _selectedSources.clear();
    } else if (selected) {
      _selectedSources.add(sourceKey);
    } else {
      _selectedSources.remove(sourceKey);
    }

    _selectedRestaurant = null;
    _setSelectedRestaurantId(null);
    _recomputeVisibleRestaurants();
    _rebuildRestaurantClusterIndex();
    if (mounted) {
      setState(() {});
    }
    unawaited(_scheduleAnnotationRefresh());
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
    const sheetWidth = 240.0;

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
                offset: const Offset(-(sheetWidth - 44), 56),
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

  void _toggleCategory(bool hospitality) {
    if (_isHospitality == hospitality) return;
    setState(() {
      _isHospitality = hospitality;
      _selectedRestaurant = null;
    });
    _setSelectedRestaurantId(null);
    _closeFilterOverlay();
    if (hospitality) {
      unawaited(_scheduleAnnotationRefresh());
    } else {
      unawaited(_mapController?.clearSymbols() ?? Future<void>.value());
    }
  }

  void setFarmMapEnabled(bool enabled) {
    if (_useVectorPmtilesFallback) {
      _fallbackMapState?.setFarmMapEnabled(enabled);
      return;
    }
    if (_farmMapEnabled == enabled) return;
    setState(() => _farmMapEnabled = enabled);
  }

  Future<void> _maybeShowInitialKangarooHint() async {
    if (_didCheckInitialKangarooHint) return;
    _didCheckInitialKangarooHint = true;

    final prefs = await SharedPreferences.getInstance();
    final seen = prefs.getBool(_seenInitialKangarooHintKey) ?? false;
    if (seen || !mounted || !_isHospitality) return;

    await prefs.setBool(_seenInitialKangarooHintKey, true);
    if (!mounted || !_isHospitality) return;

    setState(() => _showInitialKangarooHint = true);
    _initialKangarooTimer?.cancel();
    _initialKangarooTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted) return;
      setState(() => _showInitialKangarooHint = false);
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

  Future<void> _maybeShowProfileTooltip() async {
    final prefs = await SharedPreferences.getInstance();
    final seen = prefs.getBool(_seenProfileTooltipKey) ?? false;
    if (seen) return;
    await prefs.setBool(_seenProfileTooltipKey, true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future<void>.delayed(
        const Duration(milliseconds: 220),
        _showProfileTooltip,
      );
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
    final targetRect = targetOffset & profileRenderBox.size;
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
    final showAdmin = isAdminSession;
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
                showAdmin: showAdmin,
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, secondary, child) {
        final curved = Curves.easeOutCubic.transform(animation.value);
        return FadeTransition(
          opacity: animation,
          child: Transform.scale(scale: 0.95 + (0.05 * curved), child: child),
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
      unawaited(
        _handlePositiveReviewAction(
          ReviewService.actionContactOrExternalLinkTapped,
        ),
      );
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
    _setFavoritePlaces(current);
    FavoritesService.broadcast(_favoritePlaces);
    if (current.contains(restaurantId)) {
      unawaited(_handlePositiveReviewAction(ReviewService.actionFavoriteSaved));
    }
    unawaited(_scheduleAnnotationRefresh());
  }

  void _updateLocalWorkedHere(String restaurantId, int delta) {
    for (final location in _restaurantLocations) {
      if (location['id'] != restaurantId) continue;
      final current = _parseCount(location['worked_here_count']);
      location['worked_here_count'] = math.max(0, current + delta);
      final data = location['data'];
      if (data is Map<String, dynamic>) {
        data['worked_here_count'] = math.max(0, current + delta);
      }
      break;
    }

    if (_selectedRestaurant?['docId'] == restaurantId) {
      final current = _parseCount(_selectedRestaurant?['worked_here_count']);
      _selectedRestaurant!['worked_here_count'] = math.max(0, current + delta);
    }

    final storedRestaurant = _restaurantDataById[restaurantId];
    if (storedRestaurant != null) {
      final current = _parseCount(storedRestaurant['worked_here_count']);
      storedRestaurant['worked_here_count'] = math.max(0, current + delta);
    }
  }

  int _currentWorkedHereCount(String restaurantId) {
    if (_selectedRestaurant?['docId'] == restaurantId) {
      return _parseCount(_selectedRestaurant?['worked_here_count']);
    }
    final location = _restaurantLocationById[restaurantId];
    if (location == null) return 0;
    return _parseCount(location['worked_here_count']);
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
        const SnackBar(content: Text('Error: el restaurant no té ID vàlid.')),
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

    if (result != true) return;

    workedPlaces.add(restaurantId);
    final nextWorkedHereCount = _currentWorkedHereCount(restaurantId) + 1;
    try {
      await prefs.setStringList('worked_places', workedPlaces.toList());
      await MapMarkersService.rememberLocalWorkedHereCount(
        restaurantId,
        nextWorkedHereCount,
      );
      _updateLocalWorkedHere(restaurantId, 1);
      if (mounted) {
        setState(() {});
      }
      await MapMarkersService.incrementWorkedHere(restaurantId);
      await MapMarkersService.updateWorkedHereCache(restaurantId, 1);
      await _scheduleAnnotationRefresh();
    } catch (_) {
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
                          await OverlayHelper.showCopiedOverlay(
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

  Future<void> _goToUserLocation() async {
    if (_isLocating) return;
    setState(() => _isLocating = true);
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _showLocationServicesMessage();
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        await _handleDeniedLocationPermission(permission);
        return;
      }
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      final controller = _mapController;
      if (controller == null) return;
      final userTarget = LatLng(position.latitude, position.longitude);
      if (!_isInsideAustraliaCoreBounds(userTarget)) {
        if (!mounted) return;
        final fallbackCenter = _clampToAustraliaCoreBounds(_currentCenter);
        final minimumVisibleZoom = _minimumVisibleAustraliaZoom(
          MediaQuery.sizeOf(context),
        );
        final fallbackZoom = _currentZoom
            .clamp(minimumVisibleZoom, _maxMapZoom)
            .toDouble();
        await controller.animateCamera(
          CameraUpdate.newLatLngZoom(fallbackCenter, fallbackZoom),
        );
        return;
      }
      await controller.animateCamera(
        CameraUpdate.newLatLngZoom(userTarget, 15),
      );
    } catch (_) {
      _showLocationGenericError();
    } finally {
      if (mounted) {
        setState(() => _isLocating = false);
      }
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

  void _zoomOut() {
    final controller = _mapController;
    if (controller == null) return;
    unawaited(controller.animateCamera(CameraUpdate.zoomBy(-_zoomOutStep)));
  }

  Widget _buildRestaurantPopup() {
    if (_selectedRestaurant == null) {
      return const SizedBox.shrink();
    }
    final restaurant = _selectedRestaurant!;
    final docId = (restaurant['docId'] ?? '').toString();
    return ValueListenableBuilder<Set<String>>(
      valueListenable: _favoritePlacesNotifier,
      builder: (context, favoritePlaces, child) {
        return MapRestaurantPopup(
          data: restaurant,
          workedCount: _parseCount(restaurant['worked_here_count']),
          isFavorite: favoritePlaces.contains(docId),
          onClose: _clearTemporarySelection,
          onWorkedHere: () => _showWorkedDialog(
            docId,
            (restaurant['name'] ?? 'this place').toString(),
          ),
          onCopyPhone: () => _copyToClipboard(
            (restaurant['phone'] ?? '').toString(),
            'copied phone',
          ),
          onEmail: () =>
              _showEmailOptions((restaurant['email'] ?? '').toString()),
          onFacebook: () =>
              _openUrl((restaurant['facebook_url'] ?? '').toString()),
          onCareers: () =>
              _openUrl((restaurant['careers_page'] ?? '').toString()),
          onInstagram: () =>
              _openUrl((restaurant['instagram_url'] ?? '').toString()),
          onFavorite: () => _toggleFavorite(docId),
        );
      },
    );
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

  Widget _buildMapLibreRenderer() {
    return FutureBuilder<String>(
      future: _styleFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasError || !snapshot.hasData) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'You are offline mate 🦘',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: () {
                        setState(() {
                          _styleFuture = _loadStyleString();
                          _isStyleLoaded = false;
                        });
                      },
                      icon: const Icon(Icons.refresh),
                      label: const Text('try again'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        if (!_isHospitality) {
          return const Scaffold(body: FarmPlaceholderView());
        }

        return Scaffold(
          backgroundColor: _mapOceanBackgroundColor,
          body: Stack(
            children: [
              const Positioned.fill(
                child: ColoredBox(color: _mapOceanBackgroundColor),
              ),
              Positioned.fill(
                key: _mapAreaKey,
                child: LayoutBuilder(
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

                    return MapLibreMap(
                      initialCameraPosition: CameraPosition(
                        target: effectiveInitialCenter,
                        zoom: effectiveInitialZoom,
                      ),
                      cameraTargetBounds: CameraTargetBounds(_mapCameraBounds),
                      minMaxZoomPreference: MinMaxZoomPreference(
                        minimumVisibleZoom,
                        _maxMapZoom,
                      ),
                      styleString: snapshot.data!,
                      compassEnabled: true,
                      rotateGesturesEnabled: false,
                      trackCameraPosition: true,
                      onMapCreated: _handleMapCreated,
                      onStyleLoadedCallback: () {
                        // ignore: avoid_print
                        print('Map style loaded correctly');
                        unawaited(_handleStyleLoaded());
                      },
                      onMapClick: (point, coordinates) =>
                          _clearTemporarySelection(),
                      onCameraMove: _handleCameraMove,
                      onCameraIdle: _handleCameraIdle,
                    );
                  },
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
                          onChanged: (category) =>
                              _toggleCategory(category == Category.hospitality),
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
              _buildRestaurantPopup(),
              if (_showInitialKangarooHint)
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
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.blueGrey.shade700,
                  child: LocationFabIcon(
                    showBadge: _showLocationFabBadge,
                    isLoading: _isLocating,
                  ),
                ),
              ),
              if (_showZoomOutButton)
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

  @override
  Widget build(BuildContext context) {
    return MapRendererSelector(
      rendererKind: _rendererKind,
      mapLibreBuilder: (_) => _buildMapLibreRenderer(),
      vectorPmtilesBuilder: (_) => MapOSMVectorPage(
        key: _fallbackMapKey,
        initialCenter: latlng.LatLng(
          _clampToAustraliaBounds(_initialCenter).latitude,
          _clampToAustraliaBounds(_initialCenter).longitude,
        ),
        initialZoom: _initialZoom,
        styleAssetPath: _styleAssetPath,
      ),
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
    const horizontalInset = 18.0;
    const maxBubbleWidth = 320.0;
    const arrowWidth = 18.0;
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
    this.automaticEmailTileKey,
  });

  final VoidCallback onMail;
  final VoidCallback onReports;
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
                    iconBg: Colors.black12,
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
    required this.onTap,
    this.iconColor = Colors.black87,
    this.iconBg = Colors.black12,
    this.tileKey,
  });

  final IconData icon;
  final String text;
  final VoidCallback onTap;
  final Color iconColor;
  final Color iconBg;
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
  _TrianglePainter({required this.color});

  final Color color;

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
