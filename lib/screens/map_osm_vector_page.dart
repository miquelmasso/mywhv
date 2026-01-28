import 'dart:async';
import 'dart:convert';
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

import '../config/maptiler_config.dart';
import '../widgets/map_place_popup.dart';
import '../services/harvest_places_service.dart';
import '../services/map_markers_service.dart';
import '../services/overlay_helper.dart';
import '../services/favorites_service.dart';
import '../services/email_sender_service.dart';
import 'favorites_screen.dart';
import 'mail_setup_page.dart';
import 'admin_page.dart';

enum MapStyleChoice { streets, minimal }

class MapOSMVectorPage extends StatefulWidget {
  const MapOSMVectorPage({super.key});

  @override
  State<MapOSMVectorPage> createState() => _MapOSMVectorPageState();
}

final Map<String, Style> _styleCache = {};

class _MapOSMVectorPageState extends State<MapOSMVectorPage>
    with TickerProviderStateMixin {
  final MapController _mapController = MapController();
  static const LatLng _initialCenter = LatLng(-25.0, 133.0);
  static const double _initialZoom = 4.5;
  final bool _showAllRestaurants = false;
  late final String streetsStyleUrl;
  late final String minimalStyleUrl;

  List<Map<String, Object?>> _restaurantLocations = [];
  List<Map<String, Object?>> _harvestLocations = [];
  List<Marker> _markers = [];
  bool _isHospitality = true;
  bool _isLoadingData = true;
  String? _dataStatusMessage;
  LatLng _currentCenter = _initialCenter;
  bool _didFitBounds = false;
  final ValueNotifier<bool> _tilesReady = ValueNotifier<bool>(false);
  bool _isUserMoving = false;
  Timer? _moveDebounce;
  Set<String> _favoritePlaces = {};
  StreamSubscription<Set<String>>? _favoritesSub;
  final Set<String> _selectedSources = {};
  final List<Map<String, dynamic>> _sourceOptions = const [
    {'key': 'gmail', 'label': 'Gmail', 'icon': Icons.email},
    {'key': 'facebook', 'label': 'Facebook', 'icon': Icons.facebook},
    {'key': 'instagram', 'label': 'IG', 'icon': Icons.camera_alt},
    {'key': 'careers', 'label': 'Careers', 'icon': Icons.work},
  ];
  final LayerLink _filterLink = LayerLink();
  OverlayEntry? _filterOverlay;

  Map<String, dynamic>? _selectedRestaurant;
  HarvestPlace? _selectedHarvest;
  Future<Style>? _styleFuture;
  MapStyleChoice _styleChoice = MapStyleChoice.streets;
  String get _selectedStyleUrl =>
      _styleChoice == MapStyleChoice.streets ? streetsStyleUrl : minimalStyleUrl;
  bool _didKickstartRender = false;

  @override
  void initState() {
    super.initState();
    streetsStyleUrl = 'https://api.maptiler.com/maps/base-v4/style.json?key=$mapTilerKey';
    _styleFuture = _loadStyle();
    _loadFavorites();
    _favoritesSub = FavoritesService.changes.listen((ids) {
      setState(() => _favoritePlaces = ids);
      _updateMarkers();
    });
    _loadInitialData();
  }

  @override
  void dispose() {
    _moveDebounce?.cancel();
    _favoritesSub?.cancel();
    _closeFilterOverlay();
    super.dispose();
  }

  void _changeStyle(MapStyleChoice choice) {
    setState(() {
      _styleChoice = choice;
      _didFitBounds = false;
      _reloadStyle();
      _tilesReady.value = false;
    });
  }

  Future<Style> _loadStyle() async {
    if (!hasMapTilerKey) {
      throw Exception('Missing MAPTILER_KEY. Run: flutter run --dart-define=MAPTILER_KEY=xxxx');
    }
    final styleUrl = _selectedStyleUrl;
    if (_styleCache.containsKey(styleUrl)) return _styleCache[styleUrl]!;
    try {
      final style = await StyleReader(uri: styleUrl).read();
      _styleCache[styleUrl] = style;
      return style;
    } catch (e) {
      throw Exception('No s’ha pogut carregar l’estil MapTiler: $e');
    }
  }

  void _reloadStyle() {
    setState(() {
      _styleFuture = _loadStyle();
    });
  }

  Future<void> _loadInitialData() async {
    setState(() => _isLoadingData = true);
    await _loadData(fromServer: false);
    if (mounted) setState(() => _isLoadingData = false);
  }

  Future<void> _loadFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList('favorite_places') ?? [];
    setState(() => _favoritePlaces = list.toSet());
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
          _restaurantLocations = _buildRestaurantLocations(seeded);
        }
      }
    } catch (e) {
      debugPrint('❌ Error restaurants OSM vector: $e');
    }

    try {
      final harvestPlaces =
          await HarvestPlacesService.loadHarvestPlaces(fromServer: fromServer);
      if (harvestPlaces.isNotEmpty) {
        _harvestLocations = _buildHarvestLocations(harvestPlaces);
      } else if (!fromServer) {
        final seeded = await _loadSeedHarvestFromAsset();
        if (seeded.isNotEmpty) {
          _harvestLocations = _buildHarvestLocations(seeded);
        }
      }
    } catch (e) {
      debugPrint('❌ Error harvest OSM vector: $e');
    }

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

      final docId = (data['docId'] ?? '').toString();
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
        'worked_here_count': data['worked_here_count'] ?? 0,
        'sources': _extractSources(data),
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
    final source = _isHospitality
        ? _restaurantLocations.where(_passesFilter).toList()
        : _harvestLocations;
    _markers = source
        .map((r) => Marker(
              point: LatLng((r['lat'] as num).toDouble(), (r['lng'] as num).toDouble()),
              width: 40,
              height: 40,
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
                child: Icon(
                  _favoritePlaces.contains(r['id'])
                      ? Icons.favorite
                      : Icons.location_on,
                  color: _favoritePlaces.contains(r['id'])
                      ? Colors.pinkAccent
                      : (_isHospitality ? Colors.redAccent : Colors.green.shade700),
                  size: _favoritePlaces.contains(r['id']) ? 28 : 32,
                ),
              ),
            ))
        .toList();
    if (mounted) {
      setState(() {
        _didFitBounds = false; // dataset changed; allow refit
      });
    }
  }

  void _toggleCategory(bool hospitality) {
    setState(() {
      _isHospitality = hospitality;
      _selectedRestaurant = null;
      _selectedHarvest = null;
      _closeFilterOverlay();
      _updateMarkers();
    });
  }

  void _copyToClipboard(String value, String label) {
    Clipboard.setData(ClipboardData(text: value));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label copiat al porta-retalls')),
    );
  }

  void _openMailSetup() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const MailSetupPage()),
    );
  }

  void _openFavorites() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const FavoritesScreen()),
    );
  }

  void _openAdmin() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AdminPage()),
    );
  }

  void _showProfilePopup() {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Perfil',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (context, _, __) {
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
                onFavorites: () {
                  Navigator.of(context).pop();
                  _openFavorites();
                },
                onAdmin: () {
                  Navigator.of(context).pop();
                  _openAdmin();
                },
                showAdmin: true,
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, secondary, child) {
        final curved = Curves.easeOutCubic.transform(animation.value);
        return FadeTransition(
          opacity: animation,
          child: Transform.scale(
            scale: 0.95 + 0.05 * curved,
            child: child,
          ),
        );
      },
    );
  }

  Future<void> _openUrl(String url) async {
    if (url.isEmpty) return;
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No s’ha pogut obrir l’enllaç')),
      );
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
    bool added;

    if (current.contains(restaurantId)) {
      current.remove(restaurantId);
      added = false;
    } else {
      current.add(restaurantId);
      added = true;
    }

    await prefs.setStringList('favorite_places', current.toList());
    setState(() => _favoritePlaces = current);
    _updateMarkers(); // refresca icones al mapa
    FavoritesService.broadcast(_favoritePlaces);
  }

  void _updateLocalWorkedHere(String restaurantId, int delta) {
    for (final loc in _restaurantLocations) {
      if (loc['id'] == restaurantId) {
        final raw = loc['worked_here_count'] ?? 0;
        final current = (raw is num) ? raw.toInt() : int.tryParse(raw.toString()) ?? 0;
        loc['worked_here_count'] = current + delta;
      }
    }
    if (_selectedRestaurant != null && _selectedRestaurant?['docId'] == restaurantId) {
      final raw = _selectedRestaurant?['worked_here_count'] ?? 0;
      final current = (raw is num) ? raw.toInt() : int.tryParse(raw.toString()) ?? 0;
      _selectedRestaurant!['worked_here_count'] = current + delta;
    }
  }

  Future<void> _showWorkedDialog(String restaurantId, String restaurantName) async {
    final prefs = await SharedPreferences.getInstance();
    final workedList = prefs.getStringList('worked_places') ?? [];

    if (restaurantId.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error: el restaurant no té ID vàlid.')),
      );
      return;
    }

    if (workedList.contains(restaurantId)) {
      final undo = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text(
            'Vols desfer?',
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          actionsAlignment: MainAxisAlignment.spaceEvenly,
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text(
                'No',
                style: TextStyle(
                  color: Colors.redAccent,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueAccent,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Sí'),
            ),
          ],
        ),
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
          _updateMarkers();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '❎ Has tret $restaurantName de la teva llista de llocs on has treballat.',
              ),
            ),
          );
        } catch (e) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('❌ Error en desfer: $e')));
        }
      }
      return;
    }

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(
          'Has treballat aquí?',
          textAlign: TextAlign.center,
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actionsAlignment: MainAxisAlignment.spaceEvenly,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(
              'No',
              style: TextStyle(
                color: Colors.redAccent,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sí'),
          ),
        ],
      ),
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
        _updateMarkers();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '✅ Gràcies! Hem afegit $restaurantName com a lloc on has treballat.',
            ),
          ),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Error en registrar el teu vot: $e')),
        );
      }
    }
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
                child: Container(color: Colors.black.withOpacity(0.3)),
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
                        color: Colors.black.withOpacity(0.15),
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
                          OverlayHelper.showCopiedOverlay(
                            context,
                            this,
                            'Correu copiat',
                          );
                        },
                        child: const Text('Copiar correu'),
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
                          await EmailSenderService.sendEmail(
                            context: context,
                            email: email,
                          );
                          entry.remove();
                        },
                        child: const Text('Enviar correu'),
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

  void _recenter() {
    _mapController.move(_initialCenter, _initialZoom);
  }

  Widget _buildRestaurantPopup() {
    if (_selectedRestaurant == null) return const SizedBox.shrink();
    final r = _selectedRestaurant!;
    final docId = r['docId'] ?? '';
    return MapRestaurantPopup(
      data: r,
      workedCount: (r['worked_here_count'] ?? 0) as int,
      isFavorite: _favoritePlaces.contains(docId),
      onClose: () => setState(() => _selectedRestaurant = null),
      onWorkedHere: () => _showWorkedDialog(docId, r['name'] ?? 'aquest lloc'),
      onCopyPhone: () => _copyToClipboard(r['phone'], 'Telèfon'),
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
    setState(() {
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
    });
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
    if (overlay == null) return;

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
                  child: Container(
                    color: Colors.black.withOpacity(0.25),
                  ),
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
                                    color: Colors.black.withOpacity(0.12),
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
                                      style: TextStyle(fontWeight: FontWeight.w600),
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
                                    final selected = _selectedSources.contains(key);
                                    return CheckboxListTile(
                                      value: selected,
                                      onChanged: (_) {
                                        _setSourceSelection(key, !selected);
                                        setPopoverState(() {});
                                      },
                                      controlAffinity: ListTileControlAffinity.trailing,
                                      secondary: Icon(
                                        icon,
                                        color: selected
                                            ? Colors.blueAccent
                                            : Colors.black54,
                                      ),
                                      title: Text(label),
                                    );
                                  }).toList(),
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
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (snapshot.hasError || !snapshot.hasData) {
          debugPrint('❌ Error carregant estil: ${snapshot.error}');
          return Scaffold(
            appBar: AppBar(title: const Text('Map OSM')),
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'No s’ha pogut carregar l’estil del mapa:\n${snapshot.error}',
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

        final style = snapshot.data!;
        assert(() {
          debugPrint('✅ OSM: Style loaded.');
          return true;
        }());
        final hasProviders = true;

        if (!_didKickstartRender) {
          _didKickstartRender = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            assert(() {
              debugPrint('🌀 OSM: kickstart render');
              return true;
            }());
            // Força petició inicial de tiles al centre d'Austràlia
            _mapController.move(_initialCenter, _initialZoom);
          });
        }

        // Mantenim el centre inicial d'Austràlia; no auto-fit a marcadors

        return Scaffold(
          appBar: null,
          body: Stack(
            children: [
              FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: _initialCenter,
                  initialZoom: _initialZoom,
                  interactionOptions: const InteractionOptions(
                    flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                  ),
                  onTap: (_, __) {
                    setState(() {
                      _selectedRestaurant = null;
                      _selectedHarvest = null;
                    });
                  },
                  onPositionChanged: (position, _) {
                    final rotation = position.rotation ?? 0;
                    if (rotation.abs() > 0.0001) _mapController.rotate(0);
                    if (position.center != null) {
                      _currentCenter = position.center!;
                    }
                    _isUserMoving = true;
                    _moveDebounce?.cancel();
                    _moveDebounce = Timer(const Duration(milliseconds: 250), () {
                      _isUserMoving = false;
                    });
                  },
                ),
                children: [
                  if (hasProviders)
                    VectorTileLayer(
                      theme: style.theme,
                      tileProviders: style.providers,
                    )
                  else
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.mywhv.app',
                    ),
                  MarkerClusterLayerWidget(
                    options: MarkerClusterLayerOptions(
                      markers: _markers,
                      maxClusterRadius: 45,
                      size: const Size(46, 46),
                      padding: const EdgeInsets.all(50),
                      showPolygon: false, // evita dibuixar el polígon verd del clúster
                      builder: (context, cluster) {
                        return Container(
                          decoration: BoxDecoration(
                            color: _isHospitality ? Colors.redAccent : Colors.green.shade700,
                            shape: BoxShape.circle,
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            cluster.length.toString(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  RichAttributionWidget(
                    alignment: AttributionAlignment.bottomRight,
                    attributions: const [
                      TextSourceAttribution('© OpenStreetMap contributors'),
                      TextSourceAttribution('Map tiles © MapTiler'),
                    ],
                  ),
                ],
              ),
              if (!_isHospitality)
                Positioned.fill(
                  child: AbsorbPointer(
                    absorbing: true,
                    child: BackdropFilter(
                      filter: ui.ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                      child: Container(
                        color: Colors.white.withOpacity(0.55),
                        alignment: Alignment.center,
                        child: const Text(
                          'he dit soon',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
          Positioned(
            top: 16,
            left: 16,
            child: SafeArea(
              child: Material(
                elevation: 4,
                shape: const CircleBorder(),
                color: Colors.white,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: _showProfilePopup,
                  child: const SizedBox(
                    height: 48,
                    width: 48,
                    child: Icon(
                      Icons.person_outline,
                      color: Colors.black87,
                    ),
                  ),
                ),
              ),
            ),
          ),
              Positioned(
            top: 16,
            right: 16,
            child: SafeArea(
              child: CompositedTransformTarget(
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
            ),
          ),
          Positioned(
            top: 16,
            left: 80,
            right: 80,
            child: SafeArea(
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    ),
                  ],
                  border: Border.all(color: Colors.blue.shade100, width: 2),
                ),
                child: Row(
                  children: [
                    _CategoryPill(
                      label: 'Hospitality',
                      selected: _isHospitality,
                      onTap: () => _toggleCategory(true),
                    ),
                    _CategoryPill(
                      label: 'Farm (soon)',
                      selected: !_isHospitality,
                      onTap: () => _toggleCategory(false),
                    ),
                  ],
                ),
              ),
            ),
          ),
              if (_isLoadingData)
                const Center(
                  child: CircularProgressIndicator(),
                ),
              if (_dataStatusMessage != null)
                Positioned(
                  top: 100,
                  left: 16,
                  right: 16,
                  child: SafeArea(
                    child: Material(
                      elevation: 4,
                      borderRadius: BorderRadius.circular(12),
                      color: Colors.white,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        child: Row(
                          children: [
                            const Icon(Icons.offline_pin, color: Colors.blueAccent),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _dataStatusMessage!,
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              _buildRestaurantPopup(),
              _buildHarvestPopup(),
              if (_isHospitality)
                Positioned(
                  bottom: 180,
                  right: 16,
                  child: FloatingActionButton(
                    onPressed: _recenter,
                    child: const Icon(Icons.my_location),
                  ),
                ),
            ],
          ),
        );
      },
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? Colors.blueAccent : Colors.transparent,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.transparent),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : Colors.black87,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _ProfilePopupMenu extends StatelessWidget {
  const _ProfilePopupMenu({
    super.key,
    required this.onMail,
    required this.onFavorites,
    required this.onAdmin,
    required this.showAdmin,
  });

  final VoidCallback onMail;
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
              color: Colors.black.withOpacity(0.08),
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
              iconBg: Colors.redAccent.withOpacity(0.12),
              text: 'Configurar correu automàtic',
              onTap: onMail,
            ),
            const SizedBox(height: 14),
            _ProfileTile(
              icon: Icons.favorite_outline,
              iconColor: Colors.pinkAccent,
              iconBg: Colors.pinkAccent.withOpacity(0.12),
              text: 'Preferits',
              onTap: onFavorites,
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
            color: Colors.grey.shade100.withOpacity(0.5),
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
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
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
