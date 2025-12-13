import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';

class HarvestAssetImportResult {
  final int docsWritten;
  final int errors;
  HarvestAssetImportResult({
    required this.docsWritten,
    required this.errors,
  });
}

class HarvestImportFromAssetService {
  static const _assetPath = 'assets/harvest/harvest_2025.json';

  Future<HarvestAssetImportResult> importFromAsset() async {
    await _ensureFirebase();
    final firestore = FirebaseFirestore.instance;

    final content = await rootBundle.loadString(_assetPath);
    final decoded = jsonDecode(content);
    final states = (decoded['states'] as List?) ?? [];
    final year = decoded['year'] ?? 2025;

    WriteBatch batch = firestore.batch();
    int batchCount = 0;
    int written = 0;
    int errors = 0;

    Future<void> commitBatch() async {
      if (batchCount == 0) return;
      await batch.commit();
      batch = firestore.batch();
      batchCount = 0;
    }

    for (final stateEntry in states) {
      if (stateEntry is! Map) continue;
      final stateCode = (stateEntry['state'] ?? '').toString().toUpperCase();
      final regions = (stateEntry['regions'] as List?) ?? [];
      for (final region in regions) {
        if (region is! Map) continue;
        final regionName = (region['region_name'] ?? '').toString();
        final postcode = (region['postcode'] ?? '').toString();
        final mapUrl = (region['map_url'] ?? '').toString();
        final cropsRaw = (region['crops'] as List?) ?? [];
        final crops = <Map<String, dynamic>>[];

        for (final c in cropsRaw) {
          if (c is! Map) continue;
          final cropName = (c['name'] ?? c['crop'] ?? '').toString();
          final months = (c['months'] as List?)?.map((e) => _toInt(e)).toList() ?? List.filled(12, 0);
          crops.add({'crop': cropName, 'months': months});
        }

        final docId = _buildId(stateCode, postcode, regionName);
        final data = {
          'state': stateCode,
          'region_name': regionName,
          'postcode': postcode,
          'map_url': mapUrl,
          'crops': crops,
          'year': year,
          'source_url': 'asset:$_assetPath',
          'timestamp': FieldValue.serverTimestamp(),
        };

        batch.set(
          firestore.collection('harvest_calendar').doc(docId),
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
    return HarvestAssetImportResult(docsWritten: written, errors: errors);
  }

  String _buildId(String state, String postcode, String region) {
    final safeRegion = region
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .trim()
        .replaceAll(RegExp(r'^_+|_+$'), '');
    final pc = postcode.isEmpty ? 'nopc' : postcode;
    return '${state}_${pc}_$safeRegion';
  }

  int _toInt(dynamic v) => v is int ? v : int.tryParse('$v') ?? 0;

  Future<void> _ensureFirebase() async {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }
  }
}
