import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'google_places_service.dart';

class GeocodeResult {
  final int updated;
  final int skipped;
  final int errors;
  GeocodeResult({
    required this.updated,
    required this.skipped,
    required this.errors,
  });
}

class HarvestImportOutcome {
  final int docs; // places touched/imported
  final int monthsUpdated; // month docs touched/created
  final int errors;
  HarvestImportOutcome({
    required this.docs,
    required this.monthsUpdated,
    required this.errors,
  });
}

class HarvestCombinedResult {
  final HarvestImportOutcome importOutcome;
  final GeocodeResult geocodeResult;
  HarvestCombinedResult({
    required this.importOutcome,
    required this.geocodeResult,
  });
}

class HarvestGeocodeService {
  static const _collection = 'harvest_places';
  // Reuse the same API key mechanism as restaurants/places
  static String get _apiKey => GooglePlacesService.apiKey;
  static const _assetPath = 'assets/data/harvest_places_2025.json';

  Future<HarvestCombinedResult> importAndGeocodeFromAsset() async {
    final importOutcome = await importFromAssetWithMonths();
    final geocodeRes = await geocodeMissingHarvestPlaces();
    return HarvestCombinedResult(importOutcome: importOutcome, geocodeResult: geocodeRes);
  }

  Future<HarvestImportOutcome> importFromAssetWithMonths() async {
    final firestore = FirebaseFirestore.instance;
    final content = await rootBundle.loadString(_assetPath);
    final decoded = jsonDecode(content);
    final states = (decoded['states'] as List?) ?? [];
    final year = decoded['year'] ?? 2025;
    final sourceUrl = decoded['source_url']?.toString() ?? '';

    // Load existing IDs to avoid overriding created_at
    final existingSnapshot = await firestore.collection(_collection).get();
    final existingIds = existingSnapshot.docs.map((d) => d.id).toSet();

    WriteBatch batch = firestore.batch();
    int batchCount = 0;
    int docs = 0;
    int monthsUpdated = 0;
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
      final places = (stateEntry['places'] as List?) ?? [];

      for (final place in places) {
        if (place is! Map) continue;
        final name = (place['name'] ?? place['place'] ?? '').toString();
        final postcode = (place['postcode'] ?? '').toString();
        final explicitId = (place['id'] ?? '').toString();
        if (name.trim().isEmpty || !_validPostcode(postcode) || stateCode.isEmpty) continue;
        final docId = explicitId.isNotEmpty ? explicitId : _buildId(stateCode, postcode, name);
        final isNew = !existingIds.contains(docId);

        final data = {
          'name': name,
          'postcode': postcode,
          'state': stateCode,
          'year': year,
          'source_url': sourceUrl,
          'updated_at': FieldValue.serverTimestamp(),
          'latitude': (place['latitude'] as num?)?.toDouble() ?? 0.0,
          'longitude': (place['longitude'] as num?)?.toDouble() ?? 0.0,
          'coords_placeholder': ((place['latitude'] ?? 0) == 0 || (place['longitude'] ?? 0) == 0),
        };
        if (isNew) {
          data['created_at'] = FieldValue.serverTimestamp();
        }

        batch.set(
          firestore.collection(_collection).doc(docId),
          data,
          SetOptions(merge: true),
        );
        docs++;
        batchCount++;

        // Months subcollection from JSON if provided
        final months = (place['months'] as List?) ?? [];
        if (months.isEmpty) {
          for (int m = 1; m <= 12; m++) {
            final mm = m.toString().padLeft(2, '0');
            batch.set(
              firestore.collection(_collection).doc(docId).collection('months').doc(mm),
              {
                'month': m,
                'fruits': [],
                'vegetables': [],
                'other': [],
                'updated_at': FieldValue.serverTimestamp(),
              },
              SetOptions(merge: true),
            );
            batchCount++;
            monthsUpdated++;
            if (batchCount >= 400) {
              await commitBatch();
            }
          }
        } else {
          // ensure missing months are still created empty
          final seenMonths = <int>{};
          for (final mObj in months) {
            if (mObj is! Map) continue;
            final mInt = _parseInt(mObj['month']);
            if (mInt == null || mInt < 1 || mInt > 12) continue;
            seenMonths.add(mInt);
            final mm = mInt.toString().padLeft(2, '0');
            final fruits = _cleanListOfMaps(mObj['fruits']);
            final vegetables = _cleanListOfMaps(mObj['vegetables']);
            final other = _cleanListOfMaps(mObj['other']);

            batch.set(
              firestore.collection(_collection).doc(docId).collection('months').doc(mm),
              {
                'month': mInt,
                if (mObj['month_label'] != null)
                  'month_label': mObj['month_label'].toString(),
                'fruits': fruits,
                'vegetables': vegetables,
                'other': other,
                'updated_at': FieldValue.serverTimestamp(),
              },
              SetOptions(merge: true),
            );
            batchCount++;
            monthsUpdated++;
            if (batchCount >= 400) {
              await commitBatch();
            }
          }
          // create missing months empty
          for (int m = 1; m <= 12; m++) {
            if (seenMonths.contains(m)) continue;
            final mm = m.toString().padLeft(2, '0');
            batch.set(
              firestore.collection(_collection).doc(docId).collection('months').doc(mm),
              {
                'month': m,
                'fruits': [],
                'vegetables': [],
                'other': [],
                'updated_at': FieldValue.serverTimestamp(),
              },
              SetOptions(merge: true),
            );
            batchCount++;
            monthsUpdated++;
            if (batchCount >= 400) {
              await commitBatch();
            }
          }
        }

        if (batchCount >= 400) {
          await commitBatch();
        }
      }
    }

    await commitBatch();
    return HarvestImportOutcome(docs: docs, monthsUpdated: monthsUpdated, errors: errors);
  }

  Future<GeocodeResult> initHarvestCoords() async {
    final firestore = FirebaseFirestore.instance;
    final snapshot = await firestore.collection(_collection).get();
    WriteBatch batch = firestore.batch();
    int batchCount = 0;
    int updated = 0;
    int skipped = 0;
    int errors = 0;

    Future<void> commitBatch() async {
      if (batchCount == 0) return;
      await batch.commit();
      batch = firestore.batch();
      batchCount = 0;
    }

    for (final doc in snapshot.docs) {
      final data = doc.data();
      final lat = data['latitude'];
      final lng = data['longitude'];
      final isPlaceholder = data['coords_placeholder'] == true;

      if (lat != null && lng != null && !isPlaceholder) {
        skipped++;
        continue;
      }

      batch.set(
        doc.reference,
        {
          'latitude': 0.0,
          'longitude': 0.0,
          'coords_placeholder': true,
          'coords_init_at': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      batchCount++;
      updated++;

      if (batchCount >= 400) {
        await commitBatch();
      }
    }

    await commitBatch();
    return GeocodeResult(updated: updated, skipped: skipped, errors: errors);
  }

  Future<GeocodeResult> geocodeMissingHarvestPlaces({bool runImport = false}) async {
    if (runImport) {
      // Ensure fruits/vegetables/other per month are loaded before geocoding.
      await importFromAssetWithMonths();
    }
    final firestore = FirebaseFirestore.instance;
    // Firestore doesn't support "field missing OR null", so fetch all and filter.
    final snapshot = await firestore.collection(_collection).get();

    int updated = 0;
    int skipped = 0;
    int errors = 0;
    int logCount = 0;

    for (final doc in snapshot.docs) {
      final data = doc.data();
      final latVal = data['latitude'];
      final lngVal = data['longitude'];
      final placeholder = data['coords_placeholder'] == true;
      final hasLatLng = latVal != null &&
          lngVal != null &&
          !(latVal == 0.0 && lngVal == 0.0) &&
          !placeholder;
      if (hasLatLng) {
        skipped++;
        continue;
      }

      final name = (data['name'] ?? '').toString();
      final postcode = (data['postcode'] ?? '').toString();
      final state = (data['state'] ?? '').toString();

      if (!_validPostcode(postcode) || state.isEmpty) {
        skipped++;
        continue;
      }

      final queries = <_GeoQuery>[
        _GeoQuery.components(postcode: postcode, state: state),
        _GeoQuery.address('$name $postcode $state Australia'),
      ];

      bool success = false;
      for (final q in queries) {
        final res = await _geocode(q);
        if (res.status == _GeoStatus.ok && res.lat != null && res.lng != null) {
          await doc.reference.set({
            'latitude': res.lat,
            'longitude': res.lng,
            'geocode_query': q.raw,
            'geocode_source': 'google_geocoding',
            'geocoded_at': FieldValue.serverTimestamp(),
            'geocode_failed': FieldValue.delete(),
            'geocode_failed_reason': FieldValue.delete(),
          }, SetOptions(merge: true));
          if (logCount < 10) {
            // ignore: avoid_print
            debugPrint(
                'UPDATE ${doc.id} name="$name" pc=$postcode state=$state status=${res.status.name}');
            logCount++;
          }
          updated++;
          success = true;
          break;
        } else if (res.status == _GeoStatus.requestDenied) {
          if (logCount < 10) {
            // ignore: avoid_print
            debugPrint('FAIL ${doc.id} REQUEST_DENIED');
          }
          errors++;
          return GeocodeResult(updated: updated, skipped: skipped, errors: errors);
        } else if (res.status == _GeoStatus.overLimit) {
          await Future.delayed(const Duration(seconds: 2));
          continue;
        }
        await Future.delayed(const Duration(milliseconds: 120));
      }
      if (!success) {
        await doc.reference.set(
          {
            'geocode_failed': true,
            'geocode_failed_reason': 'NO_RESULTS',
            'geocoded_at': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
        if (logCount < 10) {
          // ignore: avoid_print
          debugPrint('FAIL ${doc.id} pc=$postcode state=$state status=NO_RESULTS');
          logCount++;
        }
        errors++;
      }
    }

    return GeocodeResult(updated: updated, skipped: skipped, errors: errors);
  }

  Future<_GeoResponse> _geocode(_GeoQuery q) async {
    final uri = q.isComponents
        ? Uri.https('maps.googleapis.com', '/maps/api/geocode/json', {
            'components': q.raw,
            'key': _apiKey,
            'region': 'au',
          })
        : Uri.https('maps.googleapis.com', '/maps/api/geocode/json', {
            'address': q.raw,
            'key': _apiKey,
            'region': 'au',
          });
    try {
      final resp = await http.get(uri);
      if (resp.statusCode == 429) {
        return _GeoResponse(status: _GeoStatus.overLimit);
      }
      if (resp.statusCode != 200) {
        return _GeoResponse(status: _GeoStatus.error);
      }
      final data = jsonDecode(resp.body);
      final status = (data['status'] ?? '').toString();
      if (status == 'OVER_QUERY_LIMIT') {
        return _GeoResponse(status: _GeoStatus.overLimit);
      }
      if (status == 'REQUEST_DENIED') {
        return _GeoResponse(status: _GeoStatus.requestDenied);
      }
      if (status != 'OK') {
        return _GeoResponse(status: _GeoStatus.error);
      }
      final results = data['results'] as List?;
      if (results == null || results.isEmpty) {
        return _GeoResponse(status: _GeoStatus.error);
      }
      final loc = results.first['geometry']?['location'];
      final lat = (loc['lat'] as num?)?.toDouble();
      final lng = (loc['lng'] as num?)?.toDouble();
      return _GeoResponse(status: _GeoStatus.ok, lat: lat, lng: lng);
    } catch (_) {
      return _GeoResponse(status: _GeoStatus.error);
    }
  }

  // Accepts exactly 4 digits (e.g., "0870"). Single backslash so \d works.
  bool _validPostcode(String pc) => RegExp(r'^\d{4}$').hasMatch(pc);
  int? _parseInt(dynamic v) => v is int ? v : int.tryParse('$v');

  List<Map<String, dynamic>> _cleanListOfMaps(dynamic raw) {
    if (raw is! List) return [];
    return raw
        .whereType<Map>()
        .map((m) => m.map((k, v) => MapEntry(k.toString(), v)))
        .toList();
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

enum _GeoStatus { ok, overLimit, requestDenied, error }

class _GeoResponse {
  final _GeoStatus status;
  final double? lat;
  final double? lng;
  _GeoResponse({required this.status, this.lat, this.lng});
}

class _GeoQuery {
  final String raw;
  final bool isComponents;
  _GeoQuery._(this.raw, this.isComponents);
  factory _GeoQuery.components({required String postcode, required String state}) {
    return _GeoQuery._('country:AU|postal_code:$postcode|administrative_area:$state', true);
  }

  factory _GeoQuery.address(String address) {
    return _GeoQuery._(address, false);
  }
}
