import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'email_extractor.dart';
import 'careers_extractor.dart';
import 'facebook_extractor.dart';
import 'firestore_helper.dart';
import 'http_client.dart';

class GooglePlacesService {
  static const _apiKey = 'AIzaSyCq0y5wPxOt9oZR6Z0-b0fR5fmQq3BiivI';
  static String get apiKey => _apiKey;
  final EmailExtractor _emailExtractor = EmailExtractor();
  final CareersExtractor _careersExtractor = CareersExtractor();
  final FacebookExtractor _facebookExtractor = FacebookExtractor();
  final FirestoreHelper _firestoreHelper = FirestoreHelper();
  final Set<String> _sessionPlaceIds = {};
  final Set<String> _sessionAltKeys = {};

  /// 🔍 Cerca i desa negocis d'hospitality (restaurants, bars, cafés...) per codi postal
  /// [maxToSave] = 0 o negatiu → sense límit
  Future<List<Map<String, dynamic>>> saveTwoRestaurantsForPostcode(
    int postcode, {
    int maxToSave = 2,
  }) async {
    final startedAt = DateTime.now();
    final postcodeDisplay = postcode.toString().padLeft(4, '0');
    debugPrint('🔍 Iniciant cerca per postcode $postcodeDisplay');

    final isNT = (postcode >= 800 && postcode <= 999);
    final region = isNT ? 'Northern Territory, Australia' : 'Australia';

    // 🔎 Llista d’activitats a buscar
    final List<String> businessTypes = [
      'restaurant',
      'cafe',
      'bar',
      'pub',
      'tavern',
      'takeaway food',
      'catering service',
      'hospitality club',
    ];

    // 🔹 Cache local per aquesta importació
    final existingKeys =
        await _firestoreHelper.loadExistingKeysForPostcode(postcodeDisplay);
    final seenPlaceIds = <String>{..._sessionPlaceIds, ...existingKeys.placeIds};
    final seenAltKeys = <String>{..._sessionAltKeys, ...existingKeys.altKeys};

    final saved = <Map<String, dynamic>>[];
    final triedNames = <String>{};
    final batch = FirebaseFirestore.instance.batch();
    int totalFound = 0;
    int skippedByPlaceId = 0;
    int skippedByAltKey = 0;
    int skippedByPostcode = 0;
    int failedDetails = 0;

    // 🔁 Cerca per cada tipus de negoci
    for (final type in businessTypes) {
      final hasLimit = maxToSave > 0;
      if (hasLimit && saved.length >= maxToSave) break;

      final places = await _searchPlacesWithRetry(
        query: '$type in $postcodeDisplay, $region',
      );
      totalFound += places.length;
      if (places.isEmpty) continue;

      // Pre-filtratge sense detalls per evitar crides innecessàries
      final candidates = <Map<String, dynamic>>[];
      for (final place in places) {
        if (hasLimit && saved.length + candidates.length >= maxToSave) break;
        final id = place['id'] as String?;
        if (id == null) continue;
        if (seenPlaceIds.contains(id)) {
          skippedByPlaceId++;
          continue;
        }

        final displayName =
            (place['displayName']?['text'] ?? '').toString().trim();
        final lat = place['location']?['latitude'];
        final lng = place['location']?['longitude'];
        final altKey = _buildAltKey(
          name: displayName,
          postcodeDisplay: postcodeDisplay,
          lat: lat,
          lng: lng,
        );
        if (altKey != null && seenAltKeys.contains(altKey)) {
          skippedByAltKey++;
          continue;
        }

        final address = place['formattedAddress'] ?? '';
        if (!_matchesPostcode(address, postcodeDisplay)) {
          skippedByPostcode++;
          continue;
        }

        seenPlaceIds.add(id);
        if (altKey != null) seenAltKeys.add(altKey);
        candidates.add({
          'id': id,
          'displayName': displayName,
          'address': address,
          'lat': lat,
          'lng': lng,
        });
      }

      // 🔄 Obtenir detalls amb límit de concurrència + retry
      final detailsResults = await _processCandidatesWithLimit(
        candidates,
        postcode: postcode,
        triedNames: triedNames,
        limit: 3,
        onFailedDetails: () => failedDetails++,
      );

      for (final restaurant in detailsResults) {
        if (hasLimit && saved.length >= maxToSave) break;
        _firestoreHelper.addRestaurantToBatch(
          batch,
          restaurant,
          restaurant['name'] ?? 'restaurant',
        );
        saved.add(restaurant);
      }
    }

    if (saved.isNotEmpty) {
      await batch.commit();
      _sessionPlaceIds.addAll(saved.map((r) => r['source_place_id'] as String));
      for (final r in saved) {
        final altKey = _buildAltKey(
          name: r['name'] ?? '',
          postcodeDisplay: r['postcode_display'] ?? postcodeDisplay,
          lat: r['latitude'],
          lng: r['longitude'],
        );
        if (altKey != null) _sessionAltKeys.add(altKey);
      }
    }

    final elapsedSeconds =
        DateTime.now().difference(startedAt).inMilliseconds / 1000;
    debugPrint(
      '📊 $postcodeDisplay → trobats=$totalFound, dupId=$skippedByPlaceId, '
      'dupAlt=$skippedByAltKey, postcodeKO=$skippedByPostcode, '
      'detallsKO=$failedDetails, guardats=${saved.length}',
    );
    debugPrint(
      '🎯 S’han guardat ${saved.length} negocis per $postcodeDisplay '
      'en ${elapsedSeconds.toStringAsFixed(2)}s',
    );
    return saved;
  }

  // -------------------------------
  // 🔧 Helpers
  // -------------------------------

  Future<Map<String, dynamic>?> _getPlaceDetailsWithRetry(String placeId) async {
    final url = Uri.parse('https://places.googleapis.com/v1/places/$placeId');
    final resp = await _retryHttp(() {
      return ioClient.get(url, headers: {
        'Content-Type': 'application/json',
        'X-Goog-Api-Key': _apiKey,
        'X-Goog-FieldMask':
            'displayName,location,formattedAddress,internationalPhoneNumber,websiteUri',
      });
    });
    if (resp == null || resp.statusCode != 200) return null;
    return jsonDecode(resp.body);
  }

  bool _matchesPostcode(String address, String target) {
    final re = RegExp(r'\b0?\d{3,4}\b');
    final matches = re.allMatches(address).map((m) => m.group(0)).toList();
    return matches.contains(target);
  }

  bool _isGenericFacebookCareersUrl(String? url) {
    if (url == null || url.isEmpty) return false;
    Uri? uri;
    try {
      uri = Uri.parse(url);
    } catch (_) {
      return false;
    }
    final host = uri.host.toLowerCase();
    if (!(host.contains('facebook.com') || host.contains('fb.com'))) {
      return false;
    }
    final path = uri.path.toLowerCase();
    return path == '/careers' ||
        path == '/careers/' ||
        path == '/jobs' ||
        path == '/jobs/';
  }

  bool _isValidFacebookPage(String? url) {
    if (url == null || url.isEmpty) return false;
    Uri? uri;
    try {
      uri = Uri.parse(url);
    } catch (_) {
      return false;
    }

    final host = uri.host.toLowerCase();
    if (!host.contains('facebook.com') && !host.contains('fb.com')) {
      return false;
    }

    if (uri.path.isEmpty || uri.path == '/') return false;

    const badLastSegments = {
      'tr',
      'sharer.php',
      'plugins',
      'dialog',
      'events',
      'help',
      'login',
      'l.php',
    };
    final last = uri.pathSegments.isNotEmpty ? uri.pathSegments.last.toLowerCase() : '';
    if (badLastSegments.contains(last)) return false;

    if (uri.path == '/profile.php') {
      final id = uri.queryParameters['id'];
      return id != null && id.trim().isNotEmpty;
    }

    if (uri.pathSegments.isNotEmpty) {
      final first = uri.pathSegments.first.trim();
      if (first.isEmpty) return false;
      if (first.endsWith('.php')) return false;
      return true;
    }

    return false;
  }

  Future<List<Map<String, dynamic>>> _searchPlacesWithRetry({
    required String query,
  }) async {
    final searchUrl = Uri.parse('https://places.googleapis.com/v1/places:searchText');
    final resp = await _retryHttp(() {
      return ioClient.post(
        searchUrl,
        headers: {
          'Content-Type': 'application/json',
          'X-Goog-Api-Key': _apiKey,
          'X-Goog-FieldMask':
              'places.id,places.displayName,places.location,places.formattedAddress',
        },
        body: jsonEncode({
          'textQuery': query,
          'maxResultCount': 10,
        }),
      );
    });

    if (resp == null || resp.statusCode != 200) {
      debugPrint('⚠️ Error cercant "$query": ${resp?.statusCode}');
      return [];
    }

    final data = jsonDecode(resp.body);
    final List places = (data['places'] ?? []);
    return places.cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> _processCandidatesWithLimit(
    List<Map<String, dynamic>> candidates, {
    required int postcode,
    required Set<String> triedNames,
    required int limit,
    required void Function() onFailedDetails,
  }) async {
    final results = <Map<String, dynamic>>[];
    for (var i = 0; i < candidates.length; i += limit) {
      final chunk = candidates.skip(i).take(limit);
      final futures = chunk.map((candidate) async {
        final details = await _getPlaceDetailsWithRetry(candidate['id']);
        if (details == null) {
          onFailedDetails();
          return null;
        }

        final name =
            (details['displayName']?['text'] ?? 'Unnamed').toString().trim();
        if (name.isEmpty || triedNames.contains(name)) return null;
        triedNames.add(name);

        final address = details['formattedAddress'] ?? candidate['address'] ?? '';
        if (!_matchesPostcode(address, postcode.toString().padLeft(4, '0'))) {
          return null;
        }

        final website = details['websiteUri'] ?? '';
        String? email;
        String? careersPage;
        String? facebookUrl;
        String? instagramUrl;
        final host = Uri.tryParse(website)?.host.toLowerCase() ?? '';
        final isSocial =
            host.contains('facebook.com') || host.contains('instagram.com');

        if (website.isNotEmpty) {
          if (!isSocial) {
            email = await _emailExtractor.extract(website);
          }
          careersPage = await _careersExtractor.find(website);
          if (_isGenericFacebookCareersUrl(careersPage)) {
            careersPage = null;
          }

          final fbResult = await _facebookExtractor.find(
            baseUrl: website,
            businessName: name,
            address: address,
            phone: details['internationalPhoneNumber'] ?? '',
          );
          final candidateFb = fbResult != null ? fbResult['link'] as String? : null;
          facebookUrl = _isValidFacebookPage(candidateFb) ? candidateFb : null;

          if (host.contains('instagram.com')) {
            instagramUrl = website;
          }
        }

        return _firestoreHelper.buildRestaurantData(
          name: name,
          postcode: postcode,
          address: address,
          details: details,
          email: email,
          placeId: candidate['id'],
          facebookUrl: facebookUrl,
          careersPage: careersPage,
          instagramUrl: instagramUrl,
        );
      }).toList();

      final chunkResults = await Future.wait(futures);
      results.addAll(chunkResults.whereType<Map<String, dynamic>>());
    }

    return results;
  }

  Future<http.Response?> _retryHttp(
    Future<http.Response> Function() request,
  ) async {
    const delays = [0.5, 1, 2, 4]; // segons
    http.Response? last;

    for (var i = 0; i < delays.length; i++) {
      try {
        final resp = await request();
        if (resp.statusCode == 429 || resp.statusCode >= 500) {
          last = resp;
          final delay = delays[i];
          debugPrint('⏳ Retry HTTP (${resp.statusCode}) in ${delay}s');
          await Future.delayed(Duration(milliseconds: (delay * 1000).toInt()));
          continue;
        }
        return resp;
      } catch (e) {
        debugPrint('⚠️ Error HTTP: $e');
        if (i == delays.length - 1) rethrow;
        final delay = delays[i];
        await Future.delayed(Duration(milliseconds: (delay * 1000).toInt()));
      }
    }

    return last;
  }

  String? _buildAltKey({
    required String name,
    required String postcodeDisplay,
    required dynamic lat,
    required dynamic lng,
  }) {
    final double? latD = lat is num ? lat.toDouble() : double.tryParse('$lat');
    final double? lngD = lng is num ? lng.toDouble() : double.tryParse('$lng');
    if (latD == null || lngD == null) return null;
    final normalizedName = name.trim().toLowerCase();
    return '$normalizedName|$postcodeDisplay|${latD.toStringAsFixed(5)}|${lngD.toStringAsFixed(5)}';
  }
}
