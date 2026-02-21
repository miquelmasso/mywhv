import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_marker_cluster/flutter_map_marker_cluster.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:io';

import '../services/map_markers_service.dart';
import '../services/harvest_places_service.dart';
import '../services/offline_state.dart';
import '../services/offline_tile_provider.dart';
import 'package:mywhv/screens/_pin_tail_painter.dart';

class MapPageOSM extends StatefulWidget {
  const MapPageOSM({super.key});

  @override
  State<MapPageOSM> createState() => _MapPageOSMState();
}

class _MapPageOSMState extends State<MapPageOSM> with SingleTickerProviderStateMixin {
  final MapController _mapController = MapController();
  static const LatLng _initialCenter = LatLng(-25.0, 133.0);
  static const double _initialZoom = 4.5;
  final bool _showAllRestaurants = false; // mantenir mateix filtre que al MapPage

  List<Map<String, Object?>> _restaurantLocations = [];
  List<Map<String, Object?>> _harvestLocations = [];
  List<Marker> _markers = [];
  bool _isHospitality = true; // false -> harvest
  bool _isLoadingData = true;
  String? _dataStatusMessage;
  LatLng _currentCenter = _initialCenter;

  Map<String, dynamic>? _selectedRestaurant;
  HarvestPlace? _selectedHarvest;
  late final AnimationController _kangarooController;

  @override
  void initState() {
    super.initState();
    _kangarooController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
      lowerBound: 0.9,
      upperBound: 1.05,
    )..repeat(reverse: true);
    _loadInitialData();
  }

  @override
  void dispose() {
    _kangarooController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    setState(() => _isLoadingData = true);
    await _loadData(fromServer: false);
    if (mounted) setState(() => _isLoadingData = false);
  }

  Future<void> _loadData({required bool fromServer}) async {
    try {
      final restaurantDocs =
          await MapMarkersService.loadRestaurants(fromServer: fromServer);
      if (restaurantDocs.isNotEmpty) {
        _restaurantLocations = _buildRestaurantLocations(restaurantDocs);
      } else if (!fromServer) {
        final seeded = await _loadSeedRestaurantsFromAsset();
        if (seeded.isNotEmpty) {
          debugPrint('🌱 Restaurants carregats des de seed local: ${seeded.length}');
          _restaurantLocations = _buildRestaurantLocations(seeded);
        }
      }
    } catch (e) {
      debugPrint('❌ Error carregant restaurants OSM (${fromServer ? 'server' : 'cache'}): $e');
    }

    // Harvest loading paused

    if (!fromServer &&
        _restaurantLocations.isEmpty &&
        _harvestLocations.isEmpty &&
        _markers.isEmpty) {
      _dataStatusMessage =
          'Sense dades locals. Prem “Actualitzar” quan tinguis internet o inclou un seed JSON.';
    } else if (_restaurantLocations.isNotEmpty || _harvestLocations.isNotEmpty) {
      _dataStatusMessage = null;
    }

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

      final docId = (data['docId'] ?? data['id'] ?? '').toString();
      if (docId.isEmpty) continue;
      if (data['blocked'] == true) continue;
      final hasData = ((data['facebook_url'] ?? '').toString().isNotEmpty ||
          (data['instagram_url'] ?? '').toString().isNotEmpty ||
          (data['email'] ?? '').toString().isNotEmpty ||
          (data['careers_page'] ?? '').toString().isNotEmpty);
      if (!_showAllRestaurants && !hasData) continue;

      locations.add({
        'id': docId,
        'lat': lat,
        'lng': lng,
        'data': data,
      });
    }
    return locations;
  }

  List<Map<String, Object?>> _buildHarvestLocations(
    List<HarvestPlace> places,
  ) {
    return places
        .map((p) => {
              'id': p.id,
              'lat': p.latitude,
              'lng': p.longitude,
              'data': p,
            })
        .toList();
  }

  Future<List<Map<String, dynamic>>> _loadSeedRestaurantsFromAsset() async {
    try {
      final raw = await rootBundle.loadString('assets/data/restaurants_seed.json');
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

  Future<List<HarvestPlace>> _loadSeedHarvestFromAsset() async {
    try {
      final raw = await rootBundle.loadString('assets/data/harvest_places_2025.json');
      final data = jsonDecode(raw);
      if (data is List) {
        return data
            .map((entry) => HarvestPlace(
                  id: entry['id']?.toString() ?? '',
                  name: (entry['name'] ?? '').toString(),
                  postcode: (entry['postcode'] ?? '').toString(),
                  state: (entry['state'] ?? '').toString(),
                  latitude: (entry['latitude'] ?? entry['lat'])?.toDouble() ?? 0,
                  longitude: (entry['longitude'] ?? entry['lng'])?.toDouble() ?? 0,
                  description: entry['description']?.toString(),
                ))
            .where((p) => p.id.isNotEmpty)
            .toList();
      }
    } catch (e) {
      debugPrint('ℹ️ Cap seed local de harvest (optional): $e');
    }
    return [];
  }

  void _updateMarkers() {
    final source = _isHospitality ? _restaurantLocations : _harvestLocations;
    _markers = source
        .map((r) => Marker(
              point: LatLng((r['lat'] as num).toDouble(), (r['lng'] as num).toDouble()),
              width: 28,
              height: 28,
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    if (_isHospitality) {
                      _selectedHarvest = null;
                      _selectedRestaurant = Map<String, dynamic>.from(r['data'] as Map);
                    } else {
                      _selectedRestaurant = null;
                      _selectedHarvest = r['data'] as HarvestPlace;
                    }
                  });
                },
                child: _isHospitality
                    ? _restaurantMarkerIcon(r['data'] as Map<String, dynamic>)
                    : Icon(
                        Icons.location_on,
                        color: Colors.green.shade700,
                        size: 26,
                      ),
              ),
            ))
        .toList();
    if (mounted) setState(() {});
  }

  Widget _restaurantMarkerIcon(Map<String, dynamic> data) {
    final name = (data['name'] ?? '').toString().toLowerCase();
    final isNight =
        name.contains('bar') || name.contains('pub') || name.contains('disco') || name.contains('club');
    final isCafe = name.contains('cafe') || name.contains('cafeteria');

    if (isNight) {
      return _pinMarker(
        fill: const Color(0xFF6D28D9),
        badgeColor: const Color(0xFFFBBF24),
        icon: Icons.local_bar,
      );
    }
    if (isCafe) {
      return _pinMarker(
        fill: const Color(0xFF111827),
        badgeColor: const Color(0xFF60A5FA),
        icon: Icons.local_cafe,
      );
    }
    return _pinMarker(
      fill: const Color(0xFFFF8A00),
      badgeColor: Colors.white,
      icon: Icons.restaurant,
    );
  }

  Widget _pinMarker({
    required Color fill,
    required Color badgeColor,
    required IconData icon,
  }) {
    const double circleSize = 20;
    const double tailHeight = 6;
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
                border: Border.all(color: Colors.white, width: 1.6),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.28),
                    blurRadius: 9,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: Icon(icon, size: 16, color: Colors.white),
            ),
          ),
          Positioned(
            top: circleSize - 2,
            child: CustomPaint(
              size: const Size(10, tailHeight),
              painter: PinTailPainter(color: fill, borderColor: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  void _toggleCategory(bool hospitality) {
    setState(() {
      _isHospitality = hospitality;
      _selectedRestaurant = null;
      _selectedHarvest = null;
      _updateMarkers();
    });
  }

  void _recenter() {
    _mapController.move(_initialCenter, _initialZoom);
  }

  Widget _buildRestaurantPopup() {
    if (_selectedRestaurant == null) return const SizedBox.shrink();
    final data = _selectedRestaurant!;
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Material(
        elevation: 12,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(18),
          topRight: Radius.circular(18),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      (data['name'] ?? 'Sense nom').toString(),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() => _selectedRestaurant = null),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if ((data['email'] ?? '').toString().isNotEmpty)
                Text('Email: ${data['email']}'),
              if ((data['facebook_url'] ?? '').toString().isNotEmpty)
                Text('Facebook: ${data['facebook_url']}'),
              if ((data['instagram_url'] ?? '').toString().isNotEmpty)
                Text('Instagram: ${data['instagram_url']}'),
              if ((data['careers_page'] ?? '').toString().isNotEmpty)
                Text('Feina: ${data['careers_page']}'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHarvestPopup() {
    if (_selectedHarvest == null) return const SizedBox.shrink();
    final data = _selectedHarvest!;
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Material(
        elevation: 12,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(18),
          topRight: Radius.circular(18),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      data.name,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() => _selectedHarvest = null),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text('Postcode: ${data.postcode}  ·  ${data.state}'),
              if ((data.description ?? '').isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(data.description!),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _initialCenter,
              initialZoom: _initialZoom,
              minZoom: 3.0,
              maxZoom: 20,
              onTap: (_, __) {
                setState(() {
                  _selectedRestaurant = null;
                  _selectedHarvest = null;
                });
              },
              onPositionChanged: (position, _) {
                if (position.center != null) {
                  _currentCenter = position.center!;
                }
                if (position.zoom != null) {
                  final z = position.zoom!;
                  if (z < 3.0) {
                    Future.microtask(
                      () => _mapController.move(_currentCenter, 3.0),
                    );
                  } else if (z > 20) {
                    Future.microtask(
                      () => _mapController.move(_currentCenter, 18.5),
                    );
                  }
                }
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.mywhv',
                maxZoom: 18.5,
                minZoom: 3.0,
                retinaMode: true,
                maxNativeZoom: 19,
                keepBuffer: 4,
                panBuffer: 2,
                tileDisplay: const TileDisplay.fadeIn(
                  duration: Duration(milliseconds: 120),
                  startOpacity: 0.2,
                ),
                tileProvider: OfflineTileProvider(
                  OfflineState.instance.tileCachePath != null
                      ? Directory(OfflineState.instance.tileCachePath!)
                      : Directory.systemTemp,
                ),
              ),
              MarkerClusterLayerWidget(
                options: MarkerClusterLayerOptions(
                  markers: _markers,
                  maxClusterRadius: 50,
                  size: const Size(34, 34),
                  padding: const EdgeInsets.all(26),
                  disableClusteringAtZoom: 17,
                  builder: (context, markers) {
                    return Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF111827),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.25),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        markers.length.toString(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    );
                  },
                ),
              ),
              
            ],
          ),
          Positioned(
            top: 20,
            left: 16,
            right: 16,
            child: SafeArea(
              child: Builder(builder: (context) {
                debugPrint('Rendering Contacts for regional work overlay');
                return Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.95),
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.15),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _CategoryPill(
                              label: 'Hospitality',
                              selected: _isHospitality,
                              onTap: () => _toggleCategory(true),
                            ),
                            const SizedBox(width: 8),
                            _CategoryPill(
                              label: 'Harvest',
                              selected: !_isHospitality,
                              onTap: () => _toggleCategory(false),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Contacts for regional work',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: Colors.black87.withOpacity(_isHospitality ? 0.6 : 1.0),
                            letterSpacing: 0.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ),
          if (_isLoadingData)
            Center(
              child: ScaleTransition(
                scale: _kangarooController,
                child: const Text(
                  '🦘',
                  style: TextStyle(fontSize: 48),
                ),
              ),
            ),
          _buildRestaurantPopup(),
          _buildHarvestPopup(),
          Positioned(
            bottom: 24,
            right: 16,
            child: FloatingActionButton.extended(
              onPressed: _recenter,
              icon: const Icon(Icons.my_location),
              label: const Text('Recentrar'),
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryPill extends StatelessWidget {
  const _CategoryPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? Colors.black87 : Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.black12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : Colors.black87,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
