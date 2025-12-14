import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
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

class HarvestGeocodeService {
  static const _collection = 'harvest_places';
  // Reuse the same API key mechanism as restaurants/places
  static String get _apiKey => GooglePlacesService.apiKey;

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

  Future<GeocodeResult> geocodeMissingHarvestPlaces() async {
    final firestore = FirebaseFirestore.instance;
    // Init placeholders first
    await initHarvestCoords();
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
            print(
                'UPDATE ${doc.id} name="$name" pc=$postcode state=$state status=${res.status.name}');
            logCount++;
          }
          updated++;
          success = true;
          break;
        } else if (res.status == _GeoStatus.requestDenied) {
          if (logCount < 10) {
            // ignore: avoid_print
            print('FAIL ${doc.id} REQUEST_DENIED');
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
          print('FAIL ${doc.id} pc=$postcode state=$state status=NO_RESULTS');
          logCount++;
        }
        errors++;
      }
    }

    return GeocodeResult(updated: updated, skipped: skipped, errors: errors);
  }

  Future<_GeoResponse> _geocode(_GeoQuery q) async {
    Uri uri;
    if (q.isComponents) {
      uri = Uri.https('maps.googleapis.com', '/maps/api/geocode/json', {
        'components': q.raw,
        'key': _apiKey,
        'region': 'au',
      });
    } else {
      uri = Uri.https('maps.googleapis.com', '/maps/api/geocode/json', {
        'address': q.raw,
        'key': _apiKey,
        'region': 'au',
      });
    }
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
