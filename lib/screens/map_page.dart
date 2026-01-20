import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter/services.dart'
    show rootBundle, Clipboard, ClipboardData;
import '../services/map_markers_service.dart';
import '../services/harvest_places_service.dart';
import '../services/email_sender_service.dart';
import '../services/overlay_helper.dart';
import '../services/favorites_service.dart';
import '../widgets/harvest_months_radial_overlay.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'favorites_screen.dart';
import 'mail_setup_page.dart';
import 'admin_page.dart';
//import '../widgets/filter_button.dart';

class MapPage extends StatefulWidget {
  const MapPage({super.key});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> with TickerProviderStateMixin {
  GoogleMapController? _controller;
  String? _mapStyle;
  final Set<Marker> _markers = {};
  List<Map<String, Object?>> _restaurantLocations = [];
  List<Map<String, Object?>> _harvestLocations = [];
  bool _isHospitality = true; // false → Harvest
  Set<String> _favoritePlaces = {};
  Map<String, dynamic>? _selectedRestaurant;
  HarvestPlace? _selectedHarvest;
  double _currentZoom = 4.5;
  final bool _showAllRestaurants = false; // posar true per mostrar tots

  final Set<String> _selectedSources = {}; // buit -> All
  final List<Map<String, dynamic>> _sourceOptions = const [
    {'key': 'gmail', 'label': 'Gmail', 'icon': Icons.email},
    {'key': 'facebook', 'label': 'Facebook', 'icon': Icons.facebook},
    {'key': 'instagram', 'label': 'IG', 'icon': Icons.camera_alt},
    {'key': 'careers', 'label': 'Careers', 'icon': Icons.work},
  ];

  final LayerLink _filterLink = LayerLink();
  OverlayEntry? _filterOverlay;

  final Map<int, BitmapDescriptor> _iconCache = {};
  Offset? _harvestScreenOffset;
  bool _pendingCameraUpdate = false;
  Timer? _cameraDebounce;
  StreamSubscription<Set<String>>? _favoritesSub;

  Future<BitmapDescriptor> _getCachedIcon(int count) async {
    if (_iconCache.containsKey(count)) return _iconCache[count]!;
    final icon = await OverlayHelper.createWorkCountMarker(count);
    _iconCache[count] = icon;
    return icon;
  }

  static final LatLngBounds _australiaBounds = LatLngBounds(
    southwest: const LatLng(-44.0, 111.0),
    northeast: const LatLng(-9.0, 155.0),
  );

  static const double _minZoom = 3.8;
  static const double _maxZoom = 20;

  Widget _buildCategoryPill({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final baseStyle = TextStyle(
      color: selected ? Colors.white : Colors.black87,
      fontWeight: FontWeight.w600,
    );

    TextStyle secondaryStyle = baseStyle;
    const double height = 42;

    Widget textWidget;
    final lower = label.toLowerCase();
    if (lower.contains('(soon)')) {
      final mainText = label.replaceAll(RegExp(r'\s*\(soon\)', caseSensitive: false), '');
      textWidget = RichText(
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        text: TextSpan(
          style: baseStyle,
          children: [
            TextSpan(text: mainText.trim()),
            const TextSpan(text: ' '),
            TextSpan(
              text: '(soon)',
              style: secondaryStyle.copyWith(
                fontSize: baseStyle.fontSize != null ? baseStyle.fontSize! - 1 : null,
                color: baseStyle.color?.withOpacity(0.7),
              ),
            ),
          ],
        ),
      );
    } else {
      textWidget = Text(
        label,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
        style: baseStyle,
      );
    }

    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          constraints: const BoxConstraints(
            minHeight: height,
            maxHeight: height,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: selected ? Colors.blueAccent : Colors.transparent,
            borderRadius: BorderRadius.circular(24),
          ),
          alignment: Alignment.center,
          child: textWidget,
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _loadMapStyle();
    _listenMarkers();
    _loadFavorites();
    _favoritesSub = FavoritesService.changes.listen((ids) {
      setState(() => _favoritePlaces = ids);
      _updateMarkers(_currentZoom);
    });
  }

  Future<void> _loadMapStyle() async {
    _mapStyle = await rootBundle.loadString('assets/map_style_clean.json');
  }

  Future<void> _loadFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList('favorite_places') ?? [];
    setState(() {
      _favoritePlaces = list.toSet();
    });
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
              child: ProfilePopupMenu(
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
                showAdmin: true, // Mateixa condició que l'accés anterior (ara era sempre visible).
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

  void _listenMarkers() {
    MapMarkersService.getMarkers(_showRestaurantDetails).listen((newMarkers) async {
      final firestore = FirebaseFirestore.instance;
      final snapshot = await firestore.collection('restaurants').get();
      final Map<String, Map<String, dynamic>> restaurantMap = {
        for (var doc in snapshot.docs) doc.id: doc.data(),
      };

      _restaurantLocations = [];
      for (final m in newMarkers) {
        final data = restaurantMap[m.markerId.value];
        if (data == null) continue;
        if (data['blocked'] == true) continue;

        final hasData =
            ((data['facebook_url'] ?? '').toString().isNotEmpty ||
                (data['instagram_url'] ?? '').toString().isNotEmpty ||
                (data['email'] ?? '').toString().isNotEmpty ||
                (data['careers_page'] ?? '').toString().isNotEmpty);
        if (!_showAllRestaurants && !hasData) continue;

        _restaurantLocations.add({
          'id': m.markerId.value,
          'lat': m.position.latitude,
          'lng': m.position.longitude,
          'data': m,
          'worked_here_count': data['worked_here_count'] ?? 0,
          'sources': _extractSources(data),
        });
      }

      _updateMarkers(_currentZoom);
    });

    HarvestPlacesService.streamHarvestPlaces().listen((places) async {
      _harvestLocations = [];
      for (final p in places) {
        final marker = Marker(
          markerId: MarkerId(p.id),
          position: LatLng(p.latitude, p.longitude),
          infoWindow: const InfoWindow(title: ''),
          onTap: () => _showHarvestDetails({'data': p}),
        );
        _harvestLocations.add({
          'id': p.id,
          'lat': p.latitude,
          'lng': p.longitude,
          'data': marker,
          'worked_here_count': 0,
        });
      }
      _updateMarkers(_currentZoom);
    });
  }

  Future<void> _updateMarkers(double zoom) async {
    if (!_isHospitality) {
      // 🔹 Mode Harvest
      if (_harvestLocations.isEmpty) {
        setState(() {
          _markers.clear();
          _selectedRestaurant = null;
          _selectedHarvest = null;
        });
        return;
      }
      await _updateMarkersFor(_harvestLocations, zoom);
      return;
    }

    // 🔹 Mode Hospitality
    if (_restaurantLocations.isEmpty) return;

    final filteredRestaurants =
        _restaurantLocations.where(_passesFilter).toList();

    if (filteredRestaurants.isEmpty) {
      setState(() {
        _markers.clear();
        _selectedRestaurant = null;
      });
      return;
    }

    await _updateMarkersFor(filteredRestaurants, zoom);
  }

  Future<void> _updateMarkersFor(
    List<Map<String, Object?>> locations,
    double zoom,
  ) async {

  // 🔹 2. Genera els marcadors (i clústers) amb totes les localitzacions
  final newMarkers = await OverlayHelper.generateClusterMarkers(
    locations: locations,
    zoom: zoom,
  );

    final Set<Marker> updatedMarkers = {};

    // 🔹 3. Actualitza els marcadors normals amb la icona de “worked_here_count”
    for (final marker in newMarkers) {
      if (!marker.markerId.value.startsWith('cluster_')) {
        final id = marker.markerId.value;
        final baseId = _baseMarkerId(id);
      final locationData = locations.cast<Map<String, Object?>>().firstWhere(
            (loc) => loc['id'] == baseId,
            orElse: () => <String, Object?>{},
          );

        if (locationData.isEmpty) {
          updatedMarkers.add(marker);
          continue;
        }

        final rawCount = locationData['worked_here_count'];
        final workedCount = (rawCount is int)
            ? rawCount
            : (rawCount is num)
                ? rawCount.toInt()
                : int.tryParse(rawCount.toString()) ?? 0;

        final isFavorite = _favoritePlaces.contains(baseId);
        final customIcon = isFavorite
            ? await _getFavoriteHeartMarkerIcon()
            : await _getCachedIcon(workedCount);

        updatedMarkers.add(marker.copyWith(iconParam: customIcon));
      } else {
        updatedMarkers.add(marker);
      }
    }

    // 🔹 4. Mostra els resultats
    setState(() {
      _markers
        ..clear()
        ..addAll(updatedMarkers);
    });
  }

  /// Retorna l'ID original encara que vingui d'un split de clúster
  /// (p.ex. "abc123_A"). Així evitem perdre l'estat de favorits o els comptadors.
  String _baseMarkerId(String markerId) {
    const suffixes = ['_A', '_B'];

    for (final suffix in suffixes) {
      if (markerId.endsWith(suffix)) {
        final candidate = markerId.substring(0, markerId.length - suffix.length);
        final exists = _currentLocations().any((loc) => loc['id'] == candidate);
        if (exists) return candidate;
      }
    }

    return markerId;
  }

  List<Map<String, Object?>> _currentLocations() =>
      _isHospitality ? _restaurantLocations : _harvestLocations;

  bool get _allSelected => _selectedSources.isEmpty;

  void _setCategory(bool isHospitality) {
    if (_isHospitality == isHospitality) return;
    _closeFilterOverlay();
    setState(() {
      _isHospitality = isHospitality;
      _selectedRestaurant = null;
      _selectedHarvest = null;
    });

    _updateMarkers(_currentZoom);
  }

  void _selectAllSources() {
    setState(() {
      _selectedSources.clear();
      _selectedRestaurant = null;
    });
    _updateMarkers(_currentZoom);
  }

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
        // si no queda cap seleccionat, tornem a All (concepte)
        if (_selectedSources.isEmpty) _selectedSources.clear();
      }
      _selectedRestaurant = null;
    });
    _updateMarkers(_currentZoom);
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
                offset: Offset(-(sheetWidth - 44), 56), // aligns popover to icon
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

  void _showRestaurantDetails(Map<String, dynamic> data) {
    setState(() {
      _selectedRestaurant = data;
      _selectedHarvest = null;
    });
  }

  void _showHarvestDetails(Map<String, dynamic> data) {
    if (data['data'] is HarvestPlace) {
      setState(() {
        _selectedHarvest = data['data'] as HarvestPlace;
        _selectedRestaurant = null;
        _updateHarvestScreenOffset();
      });
    }
  }

  Future<BitmapDescriptor> _getFavoriteHeartMarkerIcon() async {
    const int size = 120;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final center = Offset(size / 2, size / 2);

    final textPainter = TextPainter(
      text: const TextSpan(
        text: '❤',
        style: TextStyle(
          fontSize: 72,
          color: Colors.redAccent,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final offset = center -
        Offset(textPainter.width / 2, textPainter.height / 2);
    textPainter.paint(canvas, offset);

    final img = await recorder.endRecording().toImage(size, size);
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.fromBytes(data!.buffer.asUint8List());
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
    debugPrint('❤️ Toggle favorite $restaurantId -> $added; total=${current.length}');
    setState(() => _favoritePlaces = current);
    _updateMarkers(_currentZoom);
    FavoritesService.broadcast(_favoritePlaces);

    // No Snackbar: l'usuari veu el cor canviat i manté la lògica de preferits.
  }

  Future<void> _copyToClipboard(String text, String label) async {
    await Clipboard.setData(ClipboardData(text: text));
    OverlayHelper.showCopiedOverlay(context, this, '$label copiat');
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
                        child: const Text(
                          'Copiar correu',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
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
                        child: const Text(
                          'Enviar correu',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
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

  // ---------- 🔹 Truncate de titol ----------
  String _truncateTitle(String title) {
    title = title.trim();
    while (title.endsWith('.') || title.endsWith('-') || title.endsWith('&')) {
      title = title.substring(0, title.length - 1).trim();
    }
    if (title.length <= 26) return title;

    final words = title.split(' ');
    String result = '';
    for (final word in words) {
      if ((result + (result.isEmpty ? '' : ' ') + word).length > 26) break;
      result += (result.isEmpty ? '' : ' ') + word;
    }
    result = result.trim();
    while (result.endsWith('.') ||
        result.endsWith('-') ||
        result.endsWith('&')) {
      result = result.substring(0, result.length - 1).trim();
    }
    return result;
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No s’ha pogut obrir l’enllaç')),
      );
    }
  }

  Future<void> _showWorkedDialog(
    String restaurantId,
    String restaurantName,
  ) async {
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

  @override
  void dispose() {
    _closeFilterOverlay();
    _cameraDebounce?.cancel();
    _favoritesSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: const CameraPosition(
              target: LatLng(-25.0, 133.0),
              zoom: 4.5,
            ),
            onMapCreated: (controller) async {
              _controller = controller;
              if (_mapStyle != null) await controller.setMapStyle(_mapStyle);
            },
            onCameraMove: (pos) {
              _currentZoom = pos.zoom;
              if (!_isHospitality && _selectedHarvest != null) {
                _pendingCameraUpdate = true;
                _cameraDebounce?.cancel();
                _cameraDebounce = Timer(const Duration(milliseconds: 120), () {
                  if (_pendingCameraUpdate) {
                    _pendingCameraUpdate = false;
                    _updateHarvestScreenOffset();
                  }
                });
              }
            },
            onCameraIdle: () {
              _updateMarkers(_currentZoom);
              if (!_isHospitality && _selectedHarvest != null) {
                _updateHarvestScreenOffset();
              }
            },
            onTap: (_) => setState(() {
              _selectedRestaurant = null;
              _selectedHarvest = null;
              _harvestScreenOffset = null;
            }),
            markers: _markers,
            mapType: MapType.normal,
            minMaxZoomPreference: const MinMaxZoomPreference(
              _minZoom,
              _maxZoom,
            ),
            cameraTargetBounds: CameraTargetBounds(_australiaBounds),
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
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
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        _buildCategoryPill(
                          label: 'Hospitality',
                          selected: _isHospitality,
                          onTap: () => _setCategory(true),
                        ),
                        _buildCategoryPill(
                          label: 'Farm (soon)',
                          selected: !_isHospitality,
                          onTap: () => _setCategory(false),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
/*
          Positioned(
            top: 50,
            right: 15,
            child: FilterButton(
              onChanged: (value) {
                setState(() => _showAllRestaurants = value);
                _updateMarkers(
                  _currentZoom,
                ); // 🔄 aplica el filtre automàticament
              },
            ),
          ),
*/
          if (!_isHospitality && _selectedHarvest != null && _harvestScreenOffset != null)
            HarvestMonthsRadialOverlay(
              centerScreen: _harvestScreenOffset!,
              radius: 52,
              visible: true,
            ),
          // ---------- 🔹 POP up Restaurant ----------
          if (_selectedRestaurant != null) _buildRestaurantPopup(),
          // ---------- 🔹 POP up Harvest ----------
          if (_selectedHarvest != null) _buildHarvestPopup(),
        ],
      ),
    );
  }

  Widget _buildRestaurantPopup() {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 14,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 8,
              offset: const Offset(0, -2),
            ),
          ],
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    _truncateTitle(
                      _selectedRestaurant!['name'] ?? 'Sense nom',
                    ),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Stack(
                  alignment: Alignment.center,
                  children: [
                    IconButton(
                      icon: const Icon(
                        Icons.person,
                        color: Colors.grey,
                      ),
                      tooltip: 'He treballat aquí',
                      onPressed: () => _showWorkedDialog(
                        _selectedRestaurant!['docId'] ?? '',
                        _selectedRestaurant!['name'] ?? 'aquest lloc',
                      ),
                    ),
                    if ((_selectedRestaurant!['worked_here_count'] ?? 0) > 0)
                      Positioned(
                        right: 8,
                        top: 8,
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: const BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            '${_selectedRestaurant!['worked_here_count']}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                if ((_selectedRestaurant!['phone'] ?? '').isNotEmpty)
                  IconButton(
                    icon: const Icon(
                      Icons.phone,
                      color: Colors.blueAccent,
                    ),
                    tooltip: 'Copiar telèfon',
                    onPressed: () => _copyToClipboard(
                      _selectedRestaurant!['phone'],
                      'Telèfon',
                    ),
                  ),
                if ((_selectedRestaurant!['email'] ?? '').isNotEmpty)
                  IconButton(
                    icon: const Icon(
                      Icons.email_outlined,
                      color: Colors.redAccent,
                    ),
                    tooltip: 'Opcions de correu',
                    onPressed: () => _showEmailOptions(
                      _selectedRestaurant!['email'],
                    ),
                  ),
                if ((_selectedRestaurant!['facebook_url'] ?? '').isNotEmpty)
                  IconButton(
                    icon: const Icon(
                      Icons.facebook,
                      color: Colors.blue,
                    ),
                    tooltip: 'Obrir Facebook',
                    onPressed: () => _openUrl(_selectedRestaurant!['facebook_url']),
                  ),
                if ((_selectedRestaurant!['careers_page'] ?? '').isNotEmpty)
                  IconButton(
                    icon: const Icon(
                      Icons.work_outline,
                      color: Colors.green,
                    ),
                    tooltip: 'Veure ofertes de feina',
                    onPressed: () => _openUrl(_selectedRestaurant!['careers_page']),
                  ),
                if ((_selectedRestaurant!['instagram_url'] ?? '').toString().isNotEmpty)
                  IconButton(
                    icon: const FaIcon(FontAwesomeIcons.instagram, color: Colors.purple),
                    tooltip: 'Obrir Instagram',
                    onPressed: () => _openUrl(
                      _selectedRestaurant!['instagram_url'],
                    ),
                  ),
                const Spacer(),
                Builder(
                  builder: (context) {
                    final id = _selectedRestaurant!['docId'] ?? '';
                    final isFav = _favoritePlaces.contains(id);
                    return IconButton(
                      icon: Icon(
                        isFav ? Icons.favorite : Icons.favorite_border,
                        color: isFav ? Colors.red : Colors.grey,
                        size: 28,
                      ),
                      tooltip: 'Preferit',
                      onPressed: () => _toggleFavorite(id),
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHarvestPopup() {
    if (_selectedHarvest == null) return const SizedBox.shrink();
    final harvest = _selectedHarvest!;
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 8,
              offset: const Offset(0, -2),
            ),
          ],
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _truncateTitle(harvest.name),
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Postcode: ${harvest.postcode} • ${harvest.state}',
              style: const TextStyle(color: Colors.black54),
            ),
            if (harvest.description != null && harvest.description!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                harvest.description!,
                style: const TextStyle(color: Colors.black87),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _monthChip(int index, int value) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    Color bg;
    if (value >= 2) {
      bg = Colors.green.shade400;
    } else if (value == 1) {
      bg = Colors.orange.shade400;
    } else {
      bg = Colors.grey.shade300;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        months[index],
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }
  void _updateHarvestScreenOffset() async {
    if (_selectedHarvest == null || _controller == null) return;
    final latLng = LatLng(_selectedHarvest!.latitude, _selectedHarvest!.longitude);
    final sc = await _controller!.getScreenCoordinate(latLng);
    setState(() {
      _harvestScreenOffset = Offset(sc.x.toDouble(), sc.y.toDouble() - 8); // slight lift
    });
  }
}

class _TrianglePainter extends CustomPainter {
  final Color color;

  _TrianglePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final path = Path()
      ..moveTo(0, size.height)
      ..lineTo(size.width / 2, 0)
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class ProfilePopupMenu extends StatelessWidget {
  const ProfilePopupMenu({
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
