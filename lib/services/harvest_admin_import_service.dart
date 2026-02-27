import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';

class HarvestAdminImportService {
  static const _assetPath = 'assets/data/harvest_places_2025.json';

  Future<int> importHarvestPlacesFromAsset() async {
    await _ensureFirebase();
    final firestore = FirebaseFirestore.instance;

    final content = await rootBundle.loadString(_assetPath);
    final decoded = jsonDecode(content);
    final states = (decoded['states'] as List?) ?? [];
    final year = decoded['year'] ?? 2025;
    final sourceUrl = decoded['source_url']?.toString() ?? '';

    WriteBatch batch = firestore.batch();
    int batchCount = 0;
    int written = 0;

    Future<void> commitBatch() async {
      if (batchCount == 0) return;
      await batch.commit();
      batch = firestore.batch();
      batchCount = 0;
    }

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
        final data = {
          'name': name,
          'postcode': postcode,
          'state': stateCode,
          'year': year,
          'map_url': mapUrl,
          'source_url': sourceUrl.isEmpty ? 'asset:$_assetPath' : sourceUrl,
          'created_at': FieldValue.serverTimestamp(),
        };

        batch.set(
          firestore.collection('harvest_places').doc(docId),
          data,
          SetOptions(merge: true),
        );
        batchCount++;
        written++;

        if (batchCount >= 450) {
          await commitBatch();
        }
      }
    }

    await commitBatch();
    // ignore: avoid_print
    debugPrint('Imported $written harvest places');
    return written;
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

  Future<void> _ensureFirebase() async {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }
  }
}
