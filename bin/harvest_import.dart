// ignore_for_file: avoid_print
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html;

/// One-shot importer for Harvest Guide 2025 (Backpacker Job Board)
/// Run locally: `dart run bin/harvest_import.dart`
Future<void> main() async {
  await Firebase.initializeApp();
  final firestore = FirebaseFirestore.instance;
  const url = 'https://www.backpackerjobboard.com.au/harvest/';

  print('🔍 Descarregant Harvest Guide 2025...');
  final resp = await http.get(Uri.parse(url));
  if (resp.statusCode != 200) {
    print('❌ Error descarregant: ${resp.statusCode} ${resp.body}');
    return;
  }

  final document = html.parse(resp.body);
  final sections = document.querySelectorAll('div.harvest-section');
  if (sections.isEmpty) {
    print('⚠️ No s\'han trobat seccions harvest-section. HTML pot haver canviat.');
  }

  int saved = 0;
  for (final section in sections) {
    final stateTitle = section.querySelector('h2')?.text.trim() ?? '';
    if (stateTitle.isEmpty) continue;
    final state = stateTitle.split(' ').first.toUpperCase();

    final regions = section.querySelectorAll('div.harvest-region');
    for (final region in regions) {
      final link = region.querySelector('a');
      if (link == null) continue;
      final regionName = link.text.trim();
      final mapUrl = link.attributes['href'] ?? '';
      final postcode = _extractPostcode(region.text) ?? '';
      final latLng = _extractLatLng(mapUrl);

      final cropsTables = region.querySelectorAll('table');
      final crops = <Map<String, dynamic>>[];
      for (final table in cropsTables) {
        final rows = table.querySelectorAll('tr');
        if (rows.isEmpty) continue;
        for (final row in rows.skip(1)) {
          final cells = row.querySelectorAll('td');
          if (cells.length < 13) continue;
          final cropName = cells.first.text.trim();
          final months = cells
              .skip(1)
              .take(12)
              .map((c) => _monthValue(c.text))
              .toList();
          crops.add({'crop': cropName, 'months': months});
        }
      }

      final docId = _buildId(state, postcode, regionName);
      final data = {
        'state': state,
        'region_name': regionName,
        'postcode': postcode,
        'map_url': mapUrl,
        'crops': crops,
        'timestamp': FieldValue.serverTimestamp(),
        if (latLng != null) 'latitude': latLng.$1,
        if (latLng != null) 'longitude': latLng.$2,
      };

      await firestore.collection('harvest_calendar').doc(docId).set(
            data,
            SetOptions(merge: true),
          );
      saved++;
    }
  }

  print('🎯 Import completat. Docs guardats/actualitzats: $saved');
}

String _buildId(String state, String postcode, String region) {
  final safeRegion = region
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .trim()
      .replaceAll(RegExp(r'^_+|_+$'), '');
  final pc = postcode.isEmpty ? 'nopc' : postcode;
  return '${state}_$pc_$safeRegion';
}

String? _extractPostcode(String text) {
  final re = RegExp(r'\b(\d{4})\b');
  final m = re.firstMatch(text);
  return m?.group(1);
}

(double, double)? _extractLatLng(String url) {
  try {
    final uri = Uri.parse(url);
    final query = uri.queryParameters['q'] ?? uri.queryParameters['query'];
    final target = query ?? uri.pathSegments.join(',');
    final re = RegExp(r'(-?\d{1,3}\.\d+)[, ]+(-?\d{1,3}\.\d+)');
    final m = re.firstMatch(target);
    if (m != null) {
      final lat = double.parse(m.group(1)!);
      final lng = double.parse(m.group(2)!);
      return (lat, lng);
    }
  } catch (_) {}
  return null;
}

int _monthValue(String raw) {
  final l = raw.toLowerCase();
  if (l.contains('high')) return 2;
  if (l.contains('med')) return 1;
  return 0;
}
