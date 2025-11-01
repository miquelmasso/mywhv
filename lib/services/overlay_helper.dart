// ------------------------------------------------------------
//
// Funcions disponibles:
// 1️⃣ showCopiedOverlay → Mostra un missatge temporal “copiat” al centre de la pantalla.

// 2️⃣ generateClusterMarkers → Agrupa els marcadors propers del mapa en un únic marcador (clustering).
// 🔹 Funcions internes de suport al clustering:
//     - _distanceKm: calcula la distància en km entre dues coordenades.
//     - _degToRad: converteix graus a radians.
//     - _createClusterIcon: genera una icona circular amb el número d’elements agrupats.
//
// ------------------------------------------------------------

import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class OverlayHelper {
  // ---------- 🔹 Mostra un missatge flotant “copiat” ----------
  static Future<void> showCopiedOverlay(
      BuildContext context, TickerProvider vsync, String label) async {
    final overlay = Overlay.of(context);
    final animationController = AnimationController(
      vsync: vsync,
      duration: const Duration(milliseconds: 250),
    );

    late OverlayEntry overlayEntry;

    overlayEntry = OverlayEntry(
      builder: (context) => FadeTransition(
        opacity: animationController,
        child: Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFF9F5EF),
                borderRadius: BorderRadius.circular(22),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.15),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Text(
                label,
                style: const TextStyle(
                  color: Colors.black87,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    overlay.insert(overlayEntry);
    await animationController.forward();
    await Future.delayed(const Duration(seconds: 1));
    await animationController.reverse();
    overlayEntry.remove();
    animationController.dispose();
  }

 // ---------- 🔹 Agrupació de marcadors (Clustering amb colors dinàmics) ----------
static Future<Set<Marker>> generateClusterMarkers({
  required List<Map<String, dynamic>> locations,
  required double zoom,
}) async {
  double clusterDistanceKm;

  if (zoom < 5) {
    clusterDistanceKm = 200;
  } else if (zoom < 7) {
    clusterDistanceKm = 50;
  } else if (zoom < 9) {
    clusterDistanceKm = 20;
  } else if (zoom < 11) {
    clusterDistanceKm = 5;
  } else if (zoom < 13) {
    clusterDistanceKm = 1;
  } else if (zoom < 15) {
    clusterDistanceKm = 0.2;
  } else if (zoom < 17) {
    clusterDistanceKm = 0.05;
  } else {
    clusterDistanceKm = 0.01;
  }

  final clusters = <List<Map<String, dynamic>>>[];
  final visited = List<bool>.filled(locations.length, false);

  for (int i = 0; i < locations.length; i++) {
    if (visited[i]) continue;
    final cluster = [locations[i]];
    visited[i] = true;

    for (int j = i + 1; j < locations.length; j++) {
      if (visited[j]) continue;
      final dist = _distanceKm(
        locations[i]['lat'],
        locations[i]['lng'],
        locations[j]['lat'],
        locations[j]['lng'],
      );
      if (dist < clusterDistanceKm) {
        cluster.add(locations[j]);
        visited[j] = true;
      }
    }
    clusters.add(cluster);
  }

  final Set<Marker> newMarkers = {};

  for (final cluster in clusters) {
    final avgLat =
        cluster.map((e) => e['lat']).reduce((a, b) => a + b) / cluster.length;
    final avgLng =
        cluster.map((e) => e['lng']).reduce((a, b) => a + b) / cluster.length;
    final count = cluster.length;

    if (count == 1) {
      newMarkers.add(cluster.first['data']);
    } else if (count == 2 && zoom >= 18) {
      double offset = 0.0002;
      newMarkers.add(Marker(
        markerId: MarkerId('${cluster[0]['id']}_A'),
        position: LatLng(cluster[0]['lat'] + offset, cluster[0]['lng'] - offset),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
        onTap: cluster[0]['data'].onTap,
      ));
      newMarkers.add(Marker(
        markerId: MarkerId('${cluster[1]['id']}_B'),
        position: LatLng(cluster[1]['lat'] - offset, cluster[1]['lng'] + offset),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
        onTap: cluster[1]['data'].onTap,
      ));
    } else {
      // 🔸 Tria el color segons la mida del clúster
      Color color;
      if (count <= 10) {
        color = Colors.green;
      } else if (count <= 50) {
        color = Colors.orange;
      } else {
        color = Colors.redAccent;
      }

      final icon = await _createClusterIcon(count, color);
      newMarkers.add(Marker(
        markerId: MarkerId('cluster_${avgLat}_$avgLng'),
        position: LatLng(avgLat, avgLng),
        icon: icon,
        infoWindow: InfoWindow(title: '$count llocs agrupats'),
      ));
    }
  }

  return newMarkers;
}

// ---------- 🔹 Cercle negre per icona ----------

static Future<BitmapDescriptor> createBlackCircleIcon() async {
  const int size = 100;
  final ui.PictureRecorder recorder = ui.PictureRecorder();
  final Canvas canvas = Canvas(recorder);

  final Paint paint = Paint()
    ..color = Colors.black
    ..style = PaintingStyle.fill;

  // Dibuixa un cercle negre simple
  canvas.drawCircle(const Offset(size / 2, size / 2), size / 2.5, paint);

  // Opcional: petit contorn blanc per contrast sobre mapes clars
  final Paint borderPaint = Paint()
    ..color = Colors.white
    ..style = PaintingStyle.stroke
    ..strokeWidth = 4;
  canvas.drawCircle(const Offset(size / 2, size / 2), size / 2.5, borderPaint);

  final img = await recorder.endRecording().toImage(size, size);
  final data = await img.toByteData(format: ui.ImageByteFormat.png);
  return BitmapDescriptor.fromBytes(data!.buffer.asUint8List());
}

static Future<BitmapDescriptor> createWorkCountMarker(int count) async {
  const int size = 130;
  final ui.PictureRecorder recorder = ui.PictureRecorder();
  final Canvas canvas = Canvas(recorder);

  // Colors segons el nombre de persones
  Color color;
  if (count >= 100) {
    color = Colors.redAccent;
  } else if (count >= 50) {
    color = Colors.orangeAccent;
  } else {
    color = Colors.green;
  }

  final Paint paint = Paint()
    ..color = color
    ..style = PaintingStyle.fill;

  // 🔹 Dibuix de la gota (forma bàsica de marcador)
  final Path path = Path();
  path.moveTo(size / 2, size.toDouble());
  path.quadraticBezierTo(size * 0.1, size * 0.65, size / 2, size * 0.15);
  path.quadraticBezierTo(size * 0.9, size * 0.65, size / 2, size.toDouble());
  canvas.drawPath(path, paint);

  // 🔹 Dibuix del cercle central blanc
  final Paint innerCircle = Paint()
    ..color = Colors.white
    ..style = PaintingStyle.fill;
  canvas.drawCircle(Offset(size / 2, size * 0.5), size * 0.22, innerCircle);

  // 🔹 Text amb el número al centre
  final textPainter = TextPainter(
    text: TextSpan(
      text: count.toString(),
      style: const TextStyle(
        color: Colors.black,
        fontSize: 40,
        fontWeight: FontWeight.bold,
      ),
    ),
    textDirection: TextDirection.ltr,
    textAlign: TextAlign.center,
  )..layout();

  textPainter.paint(
    canvas,
    Offset(
      (size - textPainter.width) / 2,
      (size * 0.5 - textPainter.height / 2),
    ),
  );

  final img = await recorder.endRecording().toImage(size, size);
  final data = await img.toByteData(format: ui.ImageByteFormat.png);
  return BitmapDescriptor.fromBytes(data!.buffer.asUint8List());
}

// ---------- 🔹 Funcions internes de càlcul i gràfics ----------
static double _distanceKm(double lat1, double lng1, double lat2, double lng2) {
  const R = 6371;
  final dLat = _degToRad(lat2 - lat1);
  final dLng = _degToRad(lng2 - lng1);
  final a = sin(dLat / 2) * sin(dLat / 2) +
      cos(_degToRad(lat1)) *
          cos(_degToRad(lat2)) *
          sin(dLng / 2) *
          sin(dLng / 2);
  final c = 2 * atan2(sqrt(a), sqrt(1 - a));
  return R * c;
}

static double _degToRad(double deg) => deg * pi / 180;

// 🔹 Crea una icona circular amb color depenent de la mida del clúster
static Future<BitmapDescriptor> _createClusterIcon(
    int count, Color color) async {
  const int size = 110;
  final ui.PictureRecorder recorder = ui.PictureRecorder();
  final Canvas canvas = Canvas(recorder);

  final Paint paint = Paint()
    ..color = color
    ..style = PaintingStyle.fill;

  canvas.drawCircle(const Offset(size / 2, size / 2), size / 2.8, paint);

  final textPainter = TextPainter(
    text: TextSpan(
      text: count.toString(),
      style: const TextStyle(
        color: Colors.white,
        fontSize: 38,
        fontWeight: FontWeight.bold,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();

  textPainter.paint(
    canvas,
    Offset((size - textPainter.width) / 2, (size - textPainter.height) / 2),
  );

  final img = await recorder.endRecording().toImage(size, size);
  final data = await img.toByteData(format: ui.ImageByteFormat.png);
  return BitmapDescriptor.fromBytes(data!.buffer.asUint8List());
}
}
