import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter/services.dart'
    show rootBundle, Clipboard, ClipboardData;
import '../services/map_markers_service.dart';
import '../services/email_sender_service.dart';
import '../services/overlay_helper.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
  List<Map<String, Object?>> _locations = [];
  bool _isHospitality = true;
  Set<String> _favoritePlaces = {};
  Map<String, dynamic>? _selectedRestaurant;
  double _currentZoom = 4.5;
  final bool _showAllRestaurants = false; // posar true per mostrar tots

  final Map<int, BitmapDescriptor> _iconCache = {};

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

  @override
  void initState() {
    super.initState();
    _loadMapStyle();
    _listenMarkers();
    _loadFavorites();
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

  void _listenMarkers() {
    MapMarkersService.getMarkers(_showRestaurantDetails)
        .listen((newMarkers) async {
      final firestore = FirebaseFirestore.instance;
      final snapshot = await firestore.collection('restaurants').get();

      // 🔹 Prepara un map ràpid per evitar loops lents
      final Map<String, Map<String, dynamic>> restaurantMap = {
        for (var doc in snapshot.docs) doc.id: doc.data(),
      };

      // 🔹 Construeix la llista de localitzacions amb filtratge eficient
      _locations = [];
      for (final m in newMarkers) {
        final data = restaurantMap[m.markerId.value];

        if (data == null) continue; // si no hi ha doc, salta
        if (data['blocked'] == true) continue;

        final hasData =
            ((data['facebook_url'] ?? '').toString().isNotEmpty ||
                (data['instagram_url'] ?? '').toString().isNotEmpty ||
                (data['email'] ?? '').toString().isNotEmpty ||
                (data['careers_page'] ?? '').toString().isNotEmpty);

        // 🔹 Només afegeix si té dades o si showAll està actiu
        if (!_showAllRestaurants && !hasData) continue;

        _locations.add({
          'id': m.markerId.value,
          'lat': m.position.latitude,
          'lng': m.position.longitude,
          'data': m,
          'worked_here_count': data['worked_here_count'] ?? 0,
        });
      }

      // 🔹 Crida optimitzada (ja amb filtratge aplicat)
      _updateMarkers(_currentZoom);
    });
  }

  Future<void> _updateMarkers(double zoom) async {
  if (!_isHospitality) {
    setState(() {
      _markers.clear();
      _selectedRestaurant = null;
    });
    return;
  }

  // 🔹 1. Si no hi ha localitzacions, sortim ràpid
  if (_locations.isEmpty) return;

  // 🔹 2. Genera els marcadors (i clústers) amb totes les localitzacions
  final newMarkers = await OverlayHelper.generateClusterMarkers(
    locations: _locations,
    zoom: zoom,
  );

  final Set<Marker> updatedMarkers = {};

  // 🔹 3. Actualitza els marcadors normals amb la icona de “worked_here_count”
  for (final marker in newMarkers) {
    if (!marker.markerId.value.startsWith('cluster_')) {
      final id = marker.markerId.value;
      final locationData = _locations.cast<Map<String, Object?>>().firstWhere(
        (loc) => loc['id'] == id,
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

      final isFavorite = _favoritePlaces.contains(id);
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

  void _setCategory(bool isHospitality) {
    if (_isHospitality == isHospitality) return;
    setState(() {
      _isHospitality = isHospitality;
      _selectedRestaurant = null;
    });

    if (_isHospitality) {
      _updateMarkers(_currentZoom);
    } else {
      setState(() => _markers.clear());
    }
  }

  void _showRestaurantDetails(Map<String, dynamic> data) {
    setState(() => _selectedRestaurant = data);
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
    setState(() => _favoritePlaces = current);
    _updateMarkers(_currentZoom);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          added ? 'Afegit a preferits' : 'Eliminat de preferits',
        ),
      ),
    );
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
            onCameraMove: (pos) => _currentZoom = pos.zoom,
            onCameraIdle: () => _updateMarkers(_currentZoom),
            onTap: (_) => setState(() => _selectedRestaurant = null),
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
            right: 16,
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
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => _setCategory(true),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(
                            vertical: 10,
                            horizontal: 12,
                          ),
                          decoration: BoxDecoration(
                            color: _isHospitality
                                ? Colors.blueAccent
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(24),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            'Hospitality',
                            style: TextStyle(
                              color: _isHospitality
                                  ? Colors.white
                                  : Colors.black87,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => _setCategory(false),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(
                            vertical: 10,
                            horizontal: 12,
                          ),
                          decoration: BoxDecoration(
                            color: !_isHospitality
                                ? Colors.blueAccent
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(24),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            'Farm',
                            style: TextStyle(
                              color: !_isHospitality
                                  ? Colors.white
                                  : Colors.black87,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
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
          // ---------- 🔹 POP up  amb mail tlf fb i worked here ----------
          if (_selectedRestaurant != null)
            Positioned(
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
                            if ((_selectedRestaurant!['worked_here_count'] ??
                                    0) >
                                0)
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
                        if ((_selectedRestaurant!['facebook_url'] ?? '')
                            .isNotEmpty)
                          IconButton(
                            icon: const Icon(
                              Icons.facebook,
                              color: Colors.blue,
                            ),
                            tooltip: 'Obrir Facebook',
                            onPressed: () =>
                                _openUrl(_selectedRestaurant!['facebook_url']),
                          ),
                        if ((_selectedRestaurant!['careers_page'] ?? '')
                            .isNotEmpty)
                          IconButton(
                            icon: const Icon(
                              Icons.work_outline,
                              color: Colors.green,
                            ),
                            tooltip: 'Veure ofertes de feina',
                            onPressed: () =>
                                _openUrl(_selectedRestaurant!['careers_page']),
                          ),
                        if ((_selectedRestaurant!['instagram_url'] ?? '')
                            .toString()
                            .isNotEmpty)
                          IconButton(
                            icon: const FaIcon(FontAwesomeIcons.instagram,
                                color: Colors.purple),
                            tooltip: 'Obrir Instagram',
                            onPressed: () => _openUrl(
                              _selectedRestaurant!['instagram_url'],
                            ),
                          ),
                        const Spacer(),
                        IconButton(
                          icon: Icon(
                            _favoritePlaces
                                    .contains(_selectedRestaurant!['docId'] ?? '')
                                ? Icons.favorite
                                : Icons.favorite_border,
                            color: Colors.redAccent,
                          ),
                          tooltip: 'Preferit',
                          onPressed: () => _toggleFavorite(
                            _selectedRestaurant!['docId'] ?? '',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

          // ---------- 🔹 Fi popup ----------
        ],
      ),
    );
  }
}
