import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter/services.dart'
    show rootBundle, Clipboard, ClipboardData;
import '../services/map_markers_service.dart';
import '../services/email_sender_service.dart';
import '../services/overlay_helper.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/filter_button.dart';


class Map417Page extends StatefulWidget {
  const Map417Page({super.key});

  @override
  State<Map417Page> createState() => _Map417PageState();
}

class _Map417PageState extends State<Map417Page> with TickerProviderStateMixin {
  GoogleMapController? _controller;
  String? _mapStyle;
  final Set<Marker> _markers = {};
  List<Map<String, Object?>> _locations = [];
  Map<String, dynamic>? _selectedRestaurant;
  double _currentZoom = 4.5;
  bool _showAllRestaurants = true;


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
  }

  Future<void> _loadMapStyle() async {
    _mapStyle = await rootBundle.loadString('assets/map_style_clean.json');
  }

  void _listenMarkers() {
    MapMarkersService.getMarkers(_showRestaurantDetails).listen((
      newMarkers,
    ) async {
      // 1️⃣ Primer, transforma els markers en la teva llista de localitzacions
      _locations = newMarkers.map((m) {
        return {
          'id': m.markerId.value,
          'lat': m.position.latitude,
          'lng': m.position.longitude,
          'data': m,
          'worked_here_count': 0, // Inicialitzem temporalment
        };
      }).toList();

      // 2️⃣ Després, agafa els valors reals de Firestore
      final snapshot = await FirebaseFirestore.instance
          .collection('restaurants')
          .get();

      for (final doc in snapshot.docs) {
        final index = _locations.indexWhere((loc) => loc['id'] == doc.id);
        if (index != -1) {
          _locations[index]['worked_here_count'] =
              doc.data()['worked_here_count'] ?? 0;
        }
      }

      // 3️⃣ Actualitza els marcadors amb els nous valors
      _updateMarkers(_currentZoom);
    });
  }

 Future<void> _updateMarkers(double zoom) async {
  // 🔹 1. Filtra les localitzacions segons el valor del filtre
  List<Map<String, Object?>> visibleLocations = [];

  if (_showAllRestaurants) {
    visibleLocations = _locations;
  } else {
    for (final loc in _locations) {
      final id = loc['id']?.toString() ?? '';
      if (id.isEmpty) continue;

      try {
        final doc = await FirebaseFirestore.instance
            .collection('restaurants')
            .doc(id)
            .get();

        final data = doc.data() ?? {};
        final hasContact = (data['email'] ?? '').toString().isNotEmpty ||
            (data['facebook_url'] ?? '').toString().isNotEmpty ||
            (data['careers_page'] ?? '').toString().isNotEmpty;

        if (hasContact) visibleLocations.add(loc);
      } catch (_) {
        // Si hi ha error, simplement ignorem aquest lloc
      }
    }
  }

  // 🔹 2. Genera els marcadors (i clústers) només amb les localitzacions filtrades
  final newMarkers = await OverlayHelper.generateClusterMarkers(
    locations: visibleLocations,
    zoom: zoom,
  );

  // 🔹 3. Si no hi ha localitzacions, buida el mapa
  if (visibleLocations.isEmpty) {
    setState(() {
      _markers
        ..clear()
        ..addAll(newMarkers);
    });
    return;
  }

  final Set<Marker> updatedMarkers = {};

  // 🔹 4. Actualitza els marcadors normals amb la icona de “worked_here_count”
  for (final marker in newMarkers) {
    if (!marker.markerId.value.startsWith('cluster_')) {
      final locationData = visibleLocations
          .cast<Map<String, Object?>>()
          .firstWhere(
            (loc) => loc['id'] == marker.markerId.value,
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

      final customIcon =
          await OverlayHelper.createWorkCountMarker(workedCount);

      updatedMarkers.add(marker.copyWith(iconParam: customIcon));
    } else {
      updatedMarkers.add(marker);
    }
  }

  // 🔹 5. Mostra els resultats
  setState(() {
    _markers
      ..clear()
      ..addAll(updatedMarkers);
  });
}

  void _showRestaurantDetails(Map<String, dynamic> data) {
    setState(() => _selectedRestaurant = data);
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
          content: Text(
            'Ja havies indicat que has treballat a $restaurantName.\nVols treure-ho?',
            textAlign: TextAlign.center,
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
  top: 50,
  right: 20,
  child: FilterButton(
    showAll: _showAllRestaurants,
    onChanged: (value) {
      setState(() => _showAllRestaurants = value);
      _updateMarkers(_currentZoom);
    },
  ),
),


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
