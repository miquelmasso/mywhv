import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:google_maps_cluster_manager/google_maps_cluster_manager.dart'
    as cluster;

void main() => runApp(const ClusterTestApp());

class ClusterTestApp extends StatelessWidget {
  const ClusterTestApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: ClusterTestPage(),
    );
  }
}

class ClusterTestPage extends StatefulWidget {
  const ClusterTestPage({super.key});

  @override
  State<ClusterTestPage> createState() => _ClusterTestPageState();
}

class _ClusterTestPageState extends State<ClusterTestPage> {
  GoogleMapController? _controller;
  late cluster.ClusterManager<TestItem> _clusterManager;
  Set<Marker> _markers = {};

  @override
  void initState() {
    super.initState();
    _clusterManager = cluster.ClusterManager<TestItem>(
      _generateItems(),
      _updateMarkers,
      markerBuilder: (dynamic clusterData) =>
          _markerBuilder(clusterData as cluster.Cluster<TestItem>),
      stopClusteringZoom: 17,
    );
  }

  List<TestItem> _generateItems() {
    return List.generate(
      50,
      (i) => TestItem(LatLng(-33.86 + i * 0.02, 151.20 + i * 0.02)),
    );
  }

  Future<Marker> _markerBuilder(cluster.Cluster<TestItem> clusterData) async {
    if (clusterData.isMultiple) {
      return Marker(
        markerId: MarkerId(clusterData.getId()),
        position: clusterData.location,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        onTap: () {
          _controller?.animateCamera(CameraUpdate.zoomIn());
        },
      );
    } else {
      final item = clusterData.items.first;
      return Marker(
        markerId: MarkerId(item.hashCode.toString()),
        position: item.location,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
      );
    }
  }

  void _updateMarkers(Set<Marker> markers) {
    setState(() => _markers = markers);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cluster Test ✅')),
      body: GoogleMap(
        initialCameraPosition: const CameraPosition(
          target: LatLng(-33.86, 151.20),
          zoom: 5,
        ),
        markers: _markers,
        onMapCreated: (controller) {
          _controller = controller;
        },
        onCameraMove: _clusterManager.onCameraMove,
        onCameraIdle: _clusterManager.updateClusters,
      ),
    );
  }
}

class TestItem extends cluster.ClusterItem {
  TestItem(LatLng latLng) : super(latLng);
}
