import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'harvest_places_sqlite_store.dart';

class HarvestAdminImportService {
  static const _assetPath = 'assets/data/harvest_places_2025.json';

  Future<int> importHarvestPlacesFromAsset() async {
    final store = HarvestPlacesSqliteStore.instance;
    await store.init();

    final content = await rootBundle.loadString(_assetPath);
    final decoded = jsonDecode(content);
    final states = (decoded['states'] as List?) ?? [];
    final year = decoded['year'] ?? 2025;
    final sourceUrl = decoded['source_url']?.toString() ?? '';

    final entries = <Map<String, dynamic>>[];

    for (final stateEntry in states) {
      if (stateEntry is! Map) continue;
      final stateCode = (stateEntry['state'] ?? '').toString().toUpperCase();
      final places = (stateEntry['places'] as List?) ?? [];

      for (final place in places) {
        if (place is! Map) continue;
        final name = (place['name'] ?? '').toString().trim();
        final postcode = (place['postcode'] ?? '').toString().trim();

        if (name.isEmpty) continue;
        if (!_isValidPostcode(postcode)) continue;

        final mapUrl = (place['map_url'] ?? '').toString();
        final docId = _buildId(stateCode, postcode, name);
        entries.add({
          'id': docId,
          'name': name,
          'postcode': postcode,
          'state': stateCode,
          'year': year,
          'map_url': mapUrl,
          'source_url': sourceUrl.isEmpty ? 'asset:$_assetPath' : sourceUrl,
          'created_at': DateTime.now().toUtc().toIso8601String(),
        });
      }
    }

    await store.replaceAll(entries);
    // ignore: avoid_print
    debugPrint('Imported ${entries.length} harvest places to SQLite');
    return entries.length;
  }

  bool _isValidPostcode(String postcode) {
    final re = RegExp(r'^\d{4}$');
    return re.hasMatch(postcode);
  }

  String _buildId(String state, String postcode, String name) {
    final slug = name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return '${state}_${postcode}_$slug';
  }
}
