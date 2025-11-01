import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class Map462Page extends StatefulWidget {
  const Map462Page({super.key});

  @override
  State<Map462Page> createState() => _Map462PageState();
}

class _Map462PageState extends State<Map462Page> {
  GoogleMapController? _mapController;

  static const LatLng _centerAustralia = LatLng(-25.0, 134.0);

  static final LatLngBounds _australiaBounds = LatLngBounds(
    southwest: LatLng(-44.0, 111.0),
    northeast: LatLng(-9.0, 155.0),
  );

  static const double _minZoom = 4.5;
  static const double _maxZoom = 12.5;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Visa 462 Eligible Areas'),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          GoogleMap(
            mapType: MapType.normal,
            initialCameraPosition: const CameraPosition(
              target: _centerAustralia,
              zoom: _minZoom,
            ),
            onMapCreated: (controller) {
              _mapController = controller;
              _mapController!.moveCamera(
                CameraUpdate.newLatLngBounds(_australiaBounds, 0),
              );
            },
            cameraTargetBounds: CameraTargetBounds(_australiaBounds),
            minMaxZoomPreference: const MinMaxZoomPreference(_minZoom, _maxZoom),
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            compassEnabled: false,
            buildingsEnabled: false,
          ),

          // 🔍 Botons de zoom personalitzats
          Positioned(
            right: 10,
            bottom: 30,
            child: Column(
              children: [
                FloatingActionButton(
                  heroTag: 'zoomIn462',
                  mini: true,
                  backgroundColor: Colors.green.shade700,
                  onPressed: () => _mapController?.animateCamera(CameraUpdate.zoomIn()),
                  child: const Icon(Icons.add, color: Colors.white),
                ),
                const SizedBox(height: 8),
                FloatingActionButton(
                  heroTag: 'zoomOut462',
                  mini: true,
                  backgroundColor: Colors.green.shade700,
                  onPressed: () => _mapController?.animateCamera(CameraUpdate.zoomOut()),
                  child: const Icon(Icons.remove, color: Colors.white),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
