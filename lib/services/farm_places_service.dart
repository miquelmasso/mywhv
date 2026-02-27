import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'email_extractor.dart';
import 'careers_extractor.dart';
import 'facebook_extractor.dart';
import 'farm_firestore_helper.dart';
import 'http_client.dart';

class FarmPlacesService {
  static const _apiKey = 'AIzaSyCq0y5wPxOt9oZR6Z0-b0fR5fmQq3BiivI';
  final EmailExtractor _emailExtractor = EmailExtractor();
  final CareersExtractor _careersExtractor = CareersExtractor();
  final FacebookExtractor _facebookExtractor = FacebookExtractor();
  final FarmFirestoreHelper _firestoreHelper = FarmFirestoreHelper();
  final Set<String> _sessionPlaceIds = {};
  final Set<String> _sessionAltKeys = {};
  static const double _searchRadiusMeters = 45000; // 45 km

  static const Map<String, List<Map<String, double>>> _ruralPivots = {
    'QLD': [
      {'lat': -16.9203, 'lng': 145.7700}, // Cairns
      {'lat': -24.8700, 'lng': 152.3500}, // Bundaberg
      {'lat': -27.5600, 'lng': 151.9500}, // Toowoomba
    ],
    'NSW': [
      {'lat': -33.2800, 'lng': 149.1000}, // Orange
      {'lat': -35.1200, 'lng': 147.3700}, // Wagga Wagga
      {'lat': -30.3000, 'lng': 153.1000}, // Coffs Harbour
    ],
    'VIC': [
      {'lat': -36.3800, 'lng': 145.4000}, // Shepparton
      {'lat': -34.2000, 'lng': 142.1000}, // Mildura
      {'lat': -38.3800, 'lng': 142.4800}, // Warrnambool
    ],
    'SA': [
      {'lat': -34.2000, 'lng': 140.9900}, // Riverland
      {'lat': -37.8300, 'lng': 140.7800}, // Mount Gambier
    ],
    'WA': [
      {'lat': -33.9500, 'lng': 115.0700}, // Margaret River
      {'lat': -28.7700, 'lng': 114.6100}, // Geraldton
      {'lat': -35.0000, 'lng': 117.9000}, // Albany
    ],
    'TAS': [
      {'lat': -41.1800, 'lng': 146.3500}, // Devonport
      {'lat': -43.0300, 'lng': 147.0000}, // Huonville
    ],
    'NT': [
      {'lat': -14.4500, 'lng': 132.2700}, // Katherine
      {'lat': -23.7000, 'lng': 133.8700}, // Alice Springs
      {'lat': -12.4600, 'lng': 130.8400}, // Darwin rural
    ],
  };

  /// 🔍 Cerca i desa farms/agri work per codi postal
  /// maxToSave = 0 → sense límit
  Future<List<Map<String, dynamic>>> saveFarmsForPostcode(
    int postcode, {
    int maxToSave = 0,
    required bool isRemote462,
  }) async {
    final startedAt = DateTime.now();
    final postcodeDisplay = postcode.toString().padLeft(4, '0');
    debugPrint('🌾 Iniciant cerca de farms per postcode $postcodeDisplay');

    final List<String> farmKeywords = [
      'orchard',
      'farm',
      'station',
      'vineyard',
      'dairy farm',
      'cattle farm',
      'packing shed',
      'shearing shed',
      'market garden',
    ];

    final existingKeys =
        await _firestoreHelper.loadExistingKeysForPostcode(postcodeDisplay);
    final seenPlaceIds = <String>{..._sessionPlaceIds, ...existingKeys.placeIds};
    final seenAltKeys = <String>{..._sessionAltKeys, ...existingKeys.altKeys};

    final saved = <Map<String, dynamic>>[];
    final triedNames = <String>{};
    final batch = FirebaseFirestore.instance.batch();
    final hasLimit = maxToSave > 0;
    int totalFound = 0;
    int skippedByPlaceId = 0;
    int skippedByAltKey = 0;
    int skippedByPostcode = 0;
    int failedDetails = 0;

    for (final keyword in farmKeywords) {
      if (hasLimit && saved.length >= maxToSave) break;

      final places = await _searchPlacesWithRetry(
        query: '$keyword near $postcodeDisplay, Australia',
      );
      totalFound += places.length;
      if (places.isEmpty) continue;

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
          'category': _categoryFromKeyword(keyword),
        });
      }

      final detailsResults = await _processCandidatesWithLimit(
        candidates,
        postcode: postcode,
        postcodeDisplay: postcodeDisplay,
        triedNames: triedNames,
        limit: 3,
        isRemote462: isRemote462,
        onFailedDetails: () => failedDetails++,
      );

      for (final farm in detailsResults) {
        if (hasLimit && saved.length >= maxToSave) break;
        _firestoreHelper.addFarmToBatch(
          batch,
          farm,
          farm['name'] ?? 'farm',
        );
        saved.add(farm);
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
      '📊 Farms $postcodeDisplay → trobats=$totalFound, dupId=$skippedByPlaceId, '
      'dupAlt=$skippedByAltKey, postcodeKO=$skippedByPostcode, '
      'detallsKO=$failedDetails, guardats=${saved.length}, '
      'temps=${elapsedSeconds.toStringAsFixed(2)}s',
    );
    debugPrint(
      '🎯 S’han guardat ${saved.length} farms per $postcodeDisplay '
      'en ${elapsedSeconds.toStringAsFixed(2)}s',
    );
    return saved;
  }

  /// 🔍 Cerca i desa farms per estat amb pivots rurals i filtres estrictes
  Future<List<Map<String, dynamic>>> saveFarmsForState(
    String stateCode, {
    required Set<String> allowedPostcodes,
  }) async {
    final startedAt = DateTime.now();
    final pivots = _ruralPivots[stateCode.toUpperCase()];
    if (pivots == null || pivots.isEmpty) {
      debugPrint('⚠️ Sense pivots rurals definits per $stateCode');
      return [];
    }

    final queries = [
      'orchard',
      'vineyard',
      'fruit farm',
      'vegetable farm',
      'dairy farm',
      'cattle farm',
      'sheep farm',
      'packing shed',
      'produce farm',
      'farm stay',
    ];

    final saved = <Map<String, dynamic>>[];
    final triedNames = <String>{};
    final seenPlaceIds = <String>{..._sessionPlaceIds};
    final seenAltKeys = <String>{..._sessionAltKeys};
    int totalFound = 0;
    int skippedByAlt = 0;
    int skippedByType = 0;
    int skippedByPostcode = 0;
    int failedDetails = 0;

    final batch = FirebaseFirestore.instance.batch();

    for (final pivot in pivots) {
      for (final query in queries) {
        final places = await _searchNearbyWithRetry(
          lat: pivot['lat']!,
          lng: pivot['lng']!,
          query: query,
        );
        totalFound += places.length;

        for (final place in places) {
          final id = place['id'] as String?;
          if (id == null) continue;
          if (seenPlaceIds.contains(id)) continue;

          final displayName =
              (place['displayName']?['text'] ?? '').toString().trim();
          final lat = place['location']?['latitude'];
          final lng = place['location']?['longitude'];
          final altKey = _buildAltKey(
            name: displayName,
            postcodeDisplay: '',
            lat: lat,
            lng: lng,
          );
          if (altKey != null && seenAltKeys.contains(altKey)) {
            skippedByAlt++;
            continue;
          }

          final details = await _getPlaceDetailsWithRetry(id);
          if (details == null) {
            failedDetails++;
            continue;
          }

          final postcodeDisplay = _extractPostcode(details['formattedAddress']);
          if (postcodeDisplay == null || !allowedPostcodes.contains(postcodeDisplay)) {
            skippedByPostcode++;
            continue;
          }

          final name =
              (details['displayName']?['text'] ?? 'Unnamed').toString().trim();
          if (name.isEmpty || triedNames.contains(name)) continue;
          triedNames.add(name);

          if (!_isLikelyRealFarm(
            name: name,
            details: details,
            website: details['websiteUri'] ?? '',
            categoryHint: query,
          )) {
            skippedByType++;
            continue;
          }

          final address = details['formattedAddress'] ?? '';
          final website = details['websiteUri'] ?? '';
          String? email;
          String? careersPage;
          String? facebookUrl;
          String? instagramUrl;
          final host = Uri.tryParse(website)?.host.toLowerCase() ?? '';
          final isSocial =
              host.contains('facebook.com') || host.contains('instagram.com');

          if (website.isNotEmpty && !isSocial) {
            email = await _emailExtractor.extract(website);
            careersPage = await _careersExtractor.find(website);
          }

          if (careersPage != null && _isGenericSocialCareer(careersPage)) {
            careersPage = null;
          }

          final fbResult = await _facebookExtractor.find(
            baseUrl: website.isNotEmpty ? website : address,
            businessName: name,
            address: address,
            phone: details['internationalPhoneNumber'] ?? '',
          );
          final candidateFb = fbResult != null ? fbResult['link'] as String? : null;
          facebookUrl = _isValidFacebookPage(candidateFb) ? candidateFb : null;

          if (host.contains('instagram.com')) {
            instagramUrl = website;
          }

          final latD = (details['location']?['latitude'] as num?)?.toDouble();
          final lngD = (details['location']?['longitude'] as num?)?.toDouble();
          if (latD == null || lngD == null) continue;

          final farm = _firestoreHelper.buildFarmData(
            name: name,
            address: address,
            postcodeDisplay: postcodeDisplay,
            postcode: int.parse(postcodeDisplay),
            latitude: latD,
            longitude: lngD,
            phone: details['internationalPhoneNumber'] ?? '',
            website: website,
            email: email,
            facebookUrl: facebookUrl,
            instagramUrl: instagramUrl,
            careersPage: careersPage,
            placeId: id,
            isRemote462: true,
            category: 'farm',
          );

          _firestoreHelper.addFarmToBatch(batch, farm, farm['name'] ?? 'farm');
          saved.add(farm);
          seenPlaceIds.add(id);
          if (altKey != null) seenAltKeys.add(altKey);
        }
      }
    }

    if (saved.isNotEmpty) {
      await batch.commit();
      _sessionPlaceIds.addAll(saved.map((r) => r['source_place_id'] as String));
      for (final r in saved) {
        final altKey = _buildAltKey(
          name: r['name'] ?? '',
          postcodeDisplay: r['postcode_display'] ?? '',
          lat: r['latitude'],
          lng: r['longitude'],
        );
        if (altKey != null) _sessionAltKeys.add(altKey);
      }
    }

    final elapsedSeconds =
        DateTime.now().difference(startedAt).inMilliseconds / 1000;
    debugPrint(
      '📊 Farms $stateCode → trobats=$totalFound, guardats=${saved.length}, '
      'altDup=$skippedByAlt, typeSkip=$skippedByType, pcSkip=$skippedByPostcode, '
      'detallsKO=$failedDetails, temps=${elapsedSeconds.toStringAsFixed(2)}s',
    );
    return saved;
  }

  // ---------------- Helpers ----------------

  Future<Map<String, dynamic>?> _getPlaceDetailsWithRetry(String placeId) async {
    final url = Uri.parse('https://places.googleapis.com/v1/places/$placeId');
    final resp = await _retryHttp(() {
      return ioClient.get(url, headers: {
        'Content-Type': 'application/json',
        'X-Goog-Api-Key': _apiKey,
        'X-Goog-FieldMask':
            'displayName,location,formattedAddress,internationalPhoneNumber,websiteUri,types,primaryType,shortFormattedAddress',
      });
    });
    if (resp == null || resp.statusCode != 200) return null;
    return jsonDecode(resp.body);
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

  Future<List<Map<String, dynamic>>> _searchNearbyWithRetry({
    required double lat,
    required double lng,
    required String query,
  }) async {
    final int radius = _searchRadiusMeters.clamp(1, 50000).toInt();
    final results = <Map<String, dynamic>>[];
    String? pageToken;
    int page = 0;

    do {
      final params = {
        'location': '$lat,$lng',
        'radius': radius.toString(),
        'keyword': query,
        'key': _apiKey,
      };

      if (pageToken != null) {
        params['pagetoken'] = pageToken;
      }

      final uri = Uri.https(
        'maps.googleapis.com',
        '/maps/api/place/nearbysearch/json',
        params,
      );

      http.Response resp;
      try {
        resp = await ioClient.get(uri);
      } catch (e) {
        debugPrint('⚠️ GET nearby error $query @ $lat,$lng → $e');
        break;
      }

      if (resp.statusCode != 200) {
        debugPrint(
          '⚠️ GET nearby ${uri.replace(queryParameters: {...params, 'key': '***'})} '
          'status=${resp.statusCode} body=${resp.body}',
        );
        break;
      }

      final data = jsonDecode(resp.body);
      if (data['status'] != 'OK' && data['status'] != 'ZERO_RESULTS') {
        debugPrint(
          '⚠️ Nearby status=${data['status']} '
          'message=${data['error_message'] ?? ''} '
          'query=$query lat=$lat lng=$lng',
        );
        break;
      }

      final List raw = (data['results'] ?? []);
      results.addAll(raw.map((r) {
        final latR = r['geometry']?['location']?['lat'];
        final lngR = r['geometry']?['location']?['lng'];
        return {
          'id': r['place_id'],
          'displayName': {'text': r['name']},
          'location': {'latitude': latR, 'longitude': lngR},
          'formattedAddress': r['vicinity'] ?? r['formatted_address'] ?? '',
        };
      }).where((m) => m['id'] != null));

      pageToken = data['next_page_token'];
      page++;
      if (pageToken != null && page < 3) {
        await Future.delayed(const Duration(seconds: 2));
      } else {
        pageToken = null;
      }
    } while (pageToken != null);

    return results;
  }

  Future<List<Map<String, dynamic>>> _processCandidatesWithLimit(
    List<Map<String, dynamic>> candidates, {
    required int postcode,
    required String postcodeDisplay,
    required Set<String> triedNames,
    required int limit,
    required bool isRemote462,
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

        if (!_isLikelyRealFarm(
          name: name,
          details: details,
          website: details['websiteUri'] ?? '',
          categoryHint: candidate['category'] ?? '',
        )) {
          return null;
        }

        final address = details['formattedAddress'] ?? candidate['address'] ?? '';
        if (!_matchesPostcode(address, postcodeDisplay)) {
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

        if (website.isNotEmpty && !isSocial) {
          email = await _emailExtractor.extract(website);
          careersPage = await _careersExtractor.find(website);
        }

        if (careersPage != null && _isGenericSocialCareer(careersPage)) {
          careersPage = null;
        }

        final fbResult = await _facebookExtractor.find(
          baseUrl: website.isNotEmpty ? website : candidate['address'] ?? '',
          businessName: name,
          address: address,
          phone: details['internationalPhoneNumber'] ?? '',
        );
        final candidateFb = fbResult != null ? fbResult['link'] as String? : null;
        facebookUrl = _isValidFacebookPage(candidateFb) ? candidateFb : null;

        if (host.contains('instagram.com')) {
          instagramUrl = website;
        }

        final lat = details['location']?['latitude'];
        final lng = details['location']?['longitude'];
        if (lat == null || lng == null) return null;

        return _firestoreHelper.buildFarmData(
          name: name,
          address: address,
          postcodeDisplay: postcodeDisplay,
          postcode: postcode,
          latitude: (lat as num).toDouble(),
          longitude: (lng as num).toDouble(),
          phone: details['internationalPhoneNumber'] ?? '',
          website: website,
          email: email,
          facebookUrl: facebookUrl,
          instagramUrl: instagramUrl,
          careersPage: careersPage,
          placeId: candidate['id'],
          isRemote462: isRemote462,
          category: candidate['category'] ?? 'farm_work',
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

  bool _matchesPostcode(String address, String target) {
    final re = RegExp(r'\b0?\d{3,4}\b');
    final matches = re.allMatches(address).map((m) => m.group(0)).toList();
    return matches.contains(target);
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
    final last =
        uri.pathSegments.isNotEmpty ? uri.pathSegments.last.toLowerCase() : '';
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

  bool _isGenericSocialCareer(String? url) {
    if (url == null || url.isEmpty) return false;
    Uri? uri;
    try {
      uri = Uri.parse(url);
    } catch (_) {
      return false;
    }
    final host = uri.host.toLowerCase();
    if (!(host.contains('facebook.com') || host.contains('fb.com') || host.contains('instagram.com'))) {
      return false;
    }
    final path = uri.path.toLowerCase();
    return path.contains('/careers') || path.contains('/jobs') || path.contains('/work-with-us');
  }

  String? _extractPostcode(String? address) {
    if (address == null) return null;
    final re = RegExp(r'\b0?\d{3,4}\b');
    final match = re.allMatches(address).map((m) => m.group(0)).toList();
    if (match.isEmpty) return null;
    return match.last?.padLeft(4, '0');
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

  String _categoryFromKeyword(String keyword) {
    final lower = keyword.toLowerCase();
    if (lower.contains('orchard')) return 'orchard';
    if (lower.contains('vineyard')) return 'vineyard';
    if (lower.contains('station')) return 'station';
    if (lower.contains('packing')) return 'packing_shed';
    if (lower.contains('labour')) return 'labour_hire';
    if (lower.contains('harvest')) return 'harvest';
    if (lower.contains('fruit')) return 'fruit_picking';
    return 'farm_work';
  }

  bool _isLikelyRealFarm({
    required String name,
    required Map<String, dynamic> details,
    required String website,
    required String categoryHint,
  }) {
    final lowerName = name.toLowerCase();
    final lowerWebsite = website.toLowerCase();
    final types = (details['types'] as List?)?.map((e) => '$e'.toLowerCase()).toList() ?? [];
    final primaryType = (details['primaryType'] ?? '').toString().toLowerCase();

    final rejectTerms = [
      'labour hire',
      'recruit',
      'employment',
      'staffing',
      'workforce',
      'work skil',
      'workski',
      'agency',
      'recruitment',
      'temp agency',
      'hr ',
      'training',
      'rto',
      'institute',
      'apprenticeship',
      'career services',
      'workforce australia',
      'migration',
      'visa service',
      'adecco',
      'randstad',
      'hays',
      'workskil',
    ];

    for (final term in rejectTerms) {
      if (lowerName.contains(term) ||
          lowerWebsite.contains(term) ||
          types.any((t) => t.contains('agency') || t.contains('recruit'))) {
        return false;
      }
    }
    if (primaryType.contains('agency') || primaryType.contains('recruit')) {
      return false;
    }

    final acceptTerms = [
      'farm',
      'farms',
      'station',
      'orchard',
      'vineyard',
      'grove',
      'plantation',
      'pastoral',
      'dairy',
      'stud',
      'cattle',
      'shearing',
      'piggery',
      'poultry',
      'apiary',
      'berry',
      'mango',
      'banana',
      'citrus',
      'avocado',
      'macadamia',
      'cotton',
      'sugar',
      'nursery',
      'market garden',
      'horse',
      'ranch',
      'farmstay',
    ];

    int score = 0;
    int positives = 0;
    if (acceptTerms.any((t) => lowerName.contains(t))) {
      score += 3;
      positives++;
    }
    if (types.any((t) => t.contains('farm') || t.contains('ranch') || t.contains('agricult'))) {
      score += 2;
      positives++;
    }
    if (primaryType.contains('farm')) score += 2;
    if (categoryHint.toString().contains('farm')) score += 2;
    if (categoryHint.toString().contains('orchard') || categoryHint.toString().contains('vineyard')) {
      score += 2;
    }

    // Hard reject if any reject type in types
    if (types.any((t) => t.contains('employment') || t.contains('agency') || t.contains('recruit'))) {
      return false;
    }
    if (primaryType.contains('employment') || primaryType.contains('agency')) {
      return false;
    }

    return score >= 3 && positives >= 2;
  }
}
