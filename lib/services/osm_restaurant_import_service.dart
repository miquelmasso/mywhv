import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/osm_import_config.dart';
import 'careers_extractor.dart';
import 'email_extractor.dart';
import 'facebook_extractor.dart';
import 'instagram_extractor.dart';
import 'map_markers_service.dart';
import 'postcode_state_helper.dart';
import 'restaurant_sqlite_store.dart';
import 'contact_html_fetcher.dart';

class OsmRestaurantImportResult {
  const OsmRestaurantImportResult({
    required this.postcode,
    required this.discovered,
    required this.added,
    required this.updated,
    required this.skippedDuplicates,
    required this.skippedByCooldown,
    required this.enriched,
    this.changedRestaurantIds = const <String>[],
    this.summary = const OsmRestaurantImportSummary.empty(),
    this.message,
  });

  final String postcode;
  final int discovered;
  final int added;
  final int updated;
  final int skippedDuplicates;
  final bool skippedByCooldown;
  final int enriched;
  final List<String> changedRestaurantIds;
  final OsmRestaurantImportSummary summary;
  final String? message;
}

class OsmRestaurantImportSummary {
  const OsmRestaurantImportSummary({
    required this.processed,
    required this.withWebsite,
    required this.withPhone,
    required this.withEmail,
    required this.withFacebook,
    required this.withInstagram,
    required this.withCareers,
    required this.websiteDiscoveryAttempted,
    required this.websiteDiscovered,
    required this.websiteFromOsm,
    required this.websiteFromWikidata,
    required this.websiteFromKnownBrand,
    required this.websiteFromProbableDomain,
    required this.emailContacts,
  });

  const OsmRestaurantImportSummary.empty()
    : processed = 0,
      withWebsite = 0,
      withPhone = 0,
      withEmail = 0,
      withFacebook = 0,
      withInstagram = 0,
      withCareers = 0,
      websiteDiscoveryAttempted = 0,
      websiteDiscovered = 0,
      websiteFromOsm = 0,
      websiteFromWikidata = 0,
      websiteFromKnownBrand = 0,
      websiteFromProbableDomain = 0,
      emailContacts = const <OsmRestaurantEmailContact>[];

  final int processed;
  final int withWebsite;
  final int withPhone;
  final int withEmail;
  final int withFacebook;
  final int withInstagram;
  final int withCareers;
  final int websiteDiscoveryAttempted;
  final int websiteDiscovered;
  final int websiteFromOsm;
  final int websiteFromWikidata;
  final int websiteFromKnownBrand;
  final int websiteFromProbableDomain;
  final List<OsmRestaurantEmailContact> emailContacts;
}

class OsmRestaurantEmailContact {
  const OsmRestaurantEmailContact({required this.name, required this.email});

  final String name;
  final String email;
}

typedef OsmRestaurantImportProgressCallback =
    void Function(OsmRestaurantImportProgress progress);

class OsmRestaurantImportProgress {
  const OsmRestaurantImportProgress({
    required this.postcode,
    required this.stage,
    this.restaurantName,
    this.restaurantIndex,
    this.restaurantTotal,
    this.message,
  });

  final String postcode;
  final String stage;
  final String? restaurantName;
  final int? restaurantIndex;
  final int? restaurantTotal;
  final String? message;
}

class OsmRestaurantImportService {
  OsmRestaurantImportService({
    http.Client? client,
    EmailExtractor? emailExtractor,
    CareersExtractor? careersExtractor,
    FacebookExtractor? facebookExtractor,
    InstagramExtractor? instagramExtractor,
  }) : _client = client ?? http.Client(),
       _emailExtractor = emailExtractor ?? EmailExtractor(),
       _careersExtractor = careersExtractor ?? CareersExtractor(),
       _facebookExtractor = facebookExtractor ?? FacebookExtractor(),
       _instagramExtractor = instagramExtractor ?? InstagramExtractor();

  static const _amenityPattern =
      'restaurant|cafe|bar|pub|fast_food|food_court|biergarten|ice_cream';
  static const _postcodeCenterCachePrefix = 'osm_postcode_center_v1_';
  static const _postcodeScanPrefix = 'osm_restaurant_scan_v1_';
  static const _knownBrandWebsites = <String, String>{
    'mcdonalds': 'https://mcdonalds.com.au/',
    'kfc': 'https://www.kfc.com.au/',
    'subway': 'https://www.subway.com/en-au',
    'dominos': 'https://www.dominos.com.au/',
    'dominos pizza': 'https://www.dominos.com.au/',
    'hungry jacks': 'https://www.hungryjacks.com.au/',
    'red rooster': 'https://www.redrooster.com.au/',
    'oporto': 'https://www.oporto.com.au/',
    'zambrero': 'https://www.zambrero.com.au/',
    'guzman y gomez': 'https://www.guzmanygomez.com.au/',
    'gyg': 'https://www.guzmanygomez.com.au/',
    'the coffee club': 'https://www.coffeeclub.com.au/',
    'gloria jeans': 'https://www.gloriajeanscoffees.com.au/',
    'zarraffas': 'https://zarraffas.com/',
    'boost juice': 'https://www.boostjuice.com.au/',
    'nandos': 'https://www.nandos.com.au/',
    'sushi sushi': 'https://www.sushisushi.com.au/',
    'roll d': 'https://rolld.com.au/',
    'grilld': 'https://www.grilld.com.au/',
    'hog s breath cafe': 'https://www.hogsbreath.com.au/',
    'coffee club': 'https://www.coffeeclub.com.au/',
    'starbucks': 'https://www.starbucks.com.au/',
    '7 eleven': 'https://www.7eleven.com.au/',
    'caltex': 'https://www.caltex.com.au/',
    'ampol': 'https://www.ampol.com.au/',
  };
  static const _directoryHosts = <String>[
    'google.',
    'facebook.com',
    'instagram.com',
    'tripadvisor.',
    'ubereats.',
    'doordash.',
    'menulog.',
    'deliveroo.',
    'yellowpages.',
    'yelp.',
    'zomato.',
    'opentable.',
    'thefork.',
    'whereis.',
    'whitepages.',
    'localbusinessguide.',
    'australia247.',
    'restaurantguru.',
  ];

  final http.Client _client;
  final EmailExtractor _emailExtractor;
  final CareersExtractor _careersExtractor;
  final FacebookExtractor _facebookExtractor;
  final InstagramExtractor _instagramExtractor;

  Future<OsmRestaurantImportResult> importForPostcode(
    String rawPostcode, {
    bool force = false,
    bool enrichWebContacts = OsmImportConfig.enrichWebContactsByDefault,
    bool uploadChangedToFirebase = true,
    OsmRestaurantImportProgressCallback? onProgress,
  }) async {
    final postcode = rawPostcode.trim().padLeft(4, '0');
    if (!RegExp(r'^\d{4}$').hasMatch(postcode)) {
      throw const FormatException('A valid 4-digit postcode is required.');
    }

    final prefs = await SharedPreferences.getInstance();
    if (!force && _isScanCoolingDown(prefs, postcode)) {
      return OsmRestaurantImportResult(
        postcode: postcode,
        discovered: 0,
        added: 0,
        updated: 0,
        skippedDuplicates: 0,
        skippedByCooldown: true,
        enriched: 0,
        message:
            'This postcode was scanned recently. Use force refresh to scan it again.',
      );
    }

    onProgress?.call(
      OsmRestaurantImportProgress(
        postcode: postcode,
        stage: 'locating_postcode',
        message: 'Locating postcode',
      ),
    );
    final center = await _resolvePostcodeCenter(postcode, prefs);
    if (center == null) {
      return OsmRestaurantImportResult(
        postcode: postcode,
        discovered: 0,
        added: 0,
        updated: 0,
        skippedDuplicates: 0,
        skippedByCooldown: false,
        enriched: 0,
        message: 'The postcode could not be located with Nominatim.',
      );
    }

    onProgress?.call(
      OsmRestaurantImportProgress(
        postcode: postcode,
        stage: 'querying_osm',
        message: 'Finding restaurants in OSM',
      ),
    );
    final elements = await _queryOverpass(center);
    final candidates = elements
        .map(
          (element) => _normalizeElement(element, requestedPostcode: postcode),
        )
        .whereType<Map<String, dynamic>>()
        .take(OsmImportConfig.maxResultsPerPostcode)
        .toList(growable: false);

    final store = RestaurantSqliteStore.instance;
    await store.init();
    final existing = await store.getAll();
    final merged = existing
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: true);
    final indexBySource = <String, int>{};

    for (var i = 0; i < merged.length; i++) {
      final row = merged[i];
      final sourceId = (row['source_place_id'] ?? '').toString();
      if (sourceId.isNotEmpty) indexBySource[sourceId] = i;
    }

    var added = 0;
    var updated = 0;
    var skippedDuplicates = 0;
    final importedIndexes = <int>[];

    for (final candidate in candidates) {
      final sourceId = candidate['source_place_id'].toString();
      final existingIndex = indexBySource[sourceId];
      if (existingIndex != null) {
        merged[existingIndex] = _mergeRestaurant(
          merged[existingIndex],
          candidate,
        );
        importedIndexes.add(existingIndex);
        updated++;
        continue;
      }

      final duplicateIndex = _findNearbyDuplicateIndex(merged, candidate);
      if (duplicateIndex != null) {
        merged[duplicateIndex] = _mergeRestaurant(
          merged[duplicateIndex],
          candidate,
        );
        importedIndexes.add(duplicateIndex);
        indexBySource[sourceId] = duplicateIndex;
        skippedDuplicates++;
        updated++;
        continue;
      }

      merged.add(candidate);
      final newIndex = merged.length - 1;
      indexBySource[sourceId] = newIndex;
      importedIndexes.add(newIndex);
      added++;
    }

    final uniqueImportedIndexes = importedIndexes.toSet().toList();
    var enriched = 0;
    if (enrichWebContacts && uniqueImportedIndexes.isNotEmpty) {
      enriched = await _enrichImportedRows(
        merged,
        uniqueImportedIndexes,
        postcode: postcode,
        onProgress: onProgress,
      );
    }

    final summary = _buildImportSummary(merged, uniqueImportedIndexes);

    if (added > 0 || updated > 0 || enriched > 0) {
      await MapMarkersService.replaceLocalRestaurants(merged);
      final changedRestaurants = uniqueImportedIndexes
          .where((index) => index >= 0 && index < merged.length)
          .map((index) => Map<String, dynamic>.from(merged[index]))
          .toList(growable: false);
      if (uploadChangedToFirebase) {
        await MapMarkersService.upsertRestaurantsToFirebase(changedRestaurants);
      }
    }
    await prefs.setString(
      '$_postcodeScanPrefix$postcode',
      DateTime.now().toUtc().toIso8601String(),
    );

    return OsmRestaurantImportResult(
      postcode: postcode,
      discovered: candidates.length,
      added: added,
      updated: updated,
      skippedDuplicates: skippedDuplicates,
      skippedByCooldown: false,
      enriched: enriched,
      changedRestaurantIds: uniqueImportedIndexes
          .where((index) => index >= 0 && index < merged.length)
          .map(
            (index) => (merged[index]['docId'] ?? merged[index]['id'] ?? '')
                .toString(),
          )
          .where((id) => id.trim().isNotEmpty)
          .toSet()
          .toList(growable: false),
      summary: summary,
    );
  }

  bool _isScanCoolingDown(SharedPreferences prefs, String postcode) {
    final raw = prefs.getString('$_postcodeScanPrefix$postcode');
    final scannedAt = DateTime.tryParse(raw ?? '');
    if (scannedAt == null) return false;
    return DateTime.now().toUtc().difference(scannedAt).inDays <
        OsmImportConfig.scanCooldownDays;
  }

  Future<_OsmPostcodeArea?> _resolvePostcodeCenter(
    String postcode,
    SharedPreferences prefs,
  ) async {
    final cacheKey = '$_postcodeCenterCachePrefix$postcode';
    final cachedRaw = prefs.getString(cacheKey);
    if (cachedRaw != null) {
      final cached = jsonDecode(cachedRaw);
      if (cached is Map) {
        final cachedAt = DateTime.tryParse(
          (cached['cached_at'] ?? '').toString(),
        );
        final lat = cached['lat'] as num?;
        final lng = cached['lng'] as num?;
        if (cachedAt != null &&
            lat != null &&
            lng != null &&
            DateTime.now().toUtc().difference(cachedAt).inDays <
                OsmImportConfig.postcodeCenterCacheDays) {
          return _OsmPostcodeArea(
            latitude: lat.toDouble(),
            longitude: lng.toDouble(),
            south: _asDouble(cached['south']),
            west: _asDouble(cached['west']),
            north: _asDouble(cached['north']),
            east: _asDouble(cached['east']),
          );
        }
      }
    }

    final uri = Uri.parse('${OsmImportConfig.nominatimBaseUrl}/search').replace(
      queryParameters: {
        'postalcode': postcode,
        'country': 'Australia',
        'countrycodes': 'au',
        'format': 'jsonv2',
        'limit': '1',
      },
    );
    final response = await _client
        .get(uri, headers: _requestHeaders())
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw StateError('Nominatim returned HTTP ${response.statusCode}.');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! List || decoded.isEmpty || decoded.first is! Map) {
      return null;
    }
    final first = decoded.first as Map;
    final lat = double.tryParse((first['lat'] ?? '').toString());
    final lng = double.tryParse((first['lon'] ?? '').toString());
    if (lat == null || lng == null) return null;
    final boundingBox = first['boundingbox'];
    final south = boundingBox is List && boundingBox.length >= 4
        ? double.tryParse(boundingBox[0].toString())
        : null;
    final north = boundingBox is List && boundingBox.length >= 4
        ? double.tryParse(boundingBox[1].toString())
        : null;
    final west = boundingBox is List && boundingBox.length >= 4
        ? double.tryParse(boundingBox[2].toString())
        : null;
    final east = boundingBox is List && boundingBox.length >= 4
        ? double.tryParse(boundingBox[3].toString())
        : null;

    await prefs.setString(
      cacheKey,
      jsonEncode({
        'lat': lat,
        'lng': lng,
        'south': south,
        'west': west,
        'north': north,
        'east': east,
        'cached_at': DateTime.now().toUtc().toIso8601String(),
      }),
    );
    return _OsmPostcodeArea(
      latitude: lat,
      longitude: lng,
      south: south,
      west: west,
      north: north,
      east: east,
    );
  }

  Future<List<Map<String, dynamic>>> _queryOverpass(
    _OsmPostcodeArea area,
  ) async {
    final spatialFilter = area.hasBounds
        ? '(${area.south},${area.west},${area.north},${area.east})'
        : '(around:${OsmImportConfig.searchRadiusMeters},${area.latitude},${area.longitude})';
    final query =
        '''
[out:json][timeout:${OsmImportConfig.overpassTimeoutSeconds}];
(
  nwr["amenity"~"^($_amenityPattern)\$"]$spatialFilter;
);
out center tags;
''';

    Object? lastError;
    for (final endpoint in OsmImportConfig.overpassEndpoints) {
      try {
        final response = await _client
            .post(
              Uri.parse(endpoint),
              headers: {
                ..._requestHeaders(),
                'Content-Type': 'application/x-www-form-urlencoded',
              },
              body: {'data': query},
            )
            .timeout(
              Duration(seconds: OsmImportConfig.overpassTimeoutSeconds + 10),
            );
        if (response.statusCode != 200) {
          lastError = StateError(
            'Overpass returned HTTP ${response.statusCode}.',
          );
          continue;
        }
        final decoded = jsonDecode(response.body);
        final elements = decoded is Map ? decoded['elements'] : null;
        if (elements is! List) return const [];
        return elements
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList(growable: false);
      } catch (error) {
        lastError = error;
      }
    }
    throw StateError('All Overpass endpoints failed: $lastError');
  }

  Map<String, dynamic>? _normalizeElement(
    Map<String, dynamic> element, {
    required String requestedPostcode,
  }) {
    final type = (element['type'] ?? '').toString();
    final osmId = (element['id'] ?? '').toString();
    final tags = element['tags'];
    if (type.isEmpty || osmId.isEmpty || tags is! Map) return null;
    final lifecycleStatus = [
      tags['disused'],
      tags['abandoned'],
      tags['demolished'],
      tags['removed'],
    ].map((value) => value?.toString().toLowerCase()).toSet();
    if (lifecycleStatus.contains('yes')) return null;

    final name = (tags['name'] ?? '').toString().trim();
    if (name.isEmpty) return null;
    final center = element['center'];
    final lat = _asDouble(
      element['lat'] ?? (center is Map ? center['lat'] : null),
    );
    final lng = _asDouble(
      element['lon'] ?? (center is Map ? center['lon'] : null),
    );
    if (lat == null || lng == null) return null;

    final taggedPostcode = (tags['addr:postcode'] ?? '').toString().trim();
    if (taggedPostcode.isNotEmpty &&
        taggedPostcode.padLeft(4, '0') != requestedPostcode) {
      return null;
    }

    final postcode = taggedPostcode.isEmpty
        ? requestedPostcode
        : taggedPostcode.padLeft(4, '0');
    final sourceId = 'osm:$type:$osmId';
    final website = _normalizeWebsiteUrl(
      _firstTag(tags, const [
        'website',
        'contact:website',
        'url',
        'contact:url',
        'official_website',
        'brand:website',
        'operator:website',
        'network:website',
      ]),
    );
    final facebook = _normalizeSocialUrl(
      _firstTag(tags, const [
        'contact:facebook',
        'facebook',
        'brand:facebook',
        'operator:facebook',
      ]),
      'facebook.com',
    );
    final instagram = _normalizeSocialUrl(
      _firstTag(tags, const [
        'contact:instagram',
        'instagram',
        'brand:instagram',
        'operator:instagram',
      ]),
      'instagram.com',
    );

    return {
      'id': 'osm_${type}_$osmId',
      'docId': 'osm_${type}_$osmId',
      'name': name,
      'address': _buildAddress(tags, postcode),
      'postcode': postcode,
      'postcode_display': postcode,
      'state': getStateFromPostcode(postcode),
      'latitude': lat,
      'longitude': lng,
      'phone': _firstTag(tags, const ['phone', 'contact:phone']),
      'website': website,
      'email': _firstTag(tags, const ['email', 'contact:email']),
      'facebook_url': facebook,
      'instagram_url': instagram,
      'careers_page': '',
      'source': 'osm',
      'source_place_id': sourceId,
      'source_osm_id': osmId,
      'source_osm_type': type,
      'osm_amenity': (tags['amenity'] ?? '').toString(),
      'osm_brand': _firstTag(tags, const ['brand', 'operator', 'network']),
      'osm_wikidata': _firstTag(tags, const [
        'wikidata',
        'brand:wikidata',
        'operator:wikidata',
      ]),
      'osm_wikipedia': _firstTag(tags, const [
        'wikipedia',
        'brand:wikipedia',
        'operator:wikipedia',
      ]),
      'source_checked_at': DateTime.now().toUtc().toIso8601String(),
      'website_checked_at': '',
      'website_discovery_checked_at': '',
      'website_discovery_source': '',
      'worked_here_count': 0,
      'blocked': false,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
    };
  }

  Future<int> _enrichImportedRows(
    List<Map<String, dynamic>> rows,
    List<int> indexes, {
    required String postcode,
    OsmRestaurantImportProgressCallback? onProgress,
  }) async {
    var enriched = 0;
    final total = indexes.length;
    for (
      var offset = 0;
      offset < indexes.length;
      offset += OsmImportConfig.enrichmentConcurrency
    ) {
      final chunk = indexes
          .skip(offset)
          .take(OsmImportConfig.enrichmentConcurrency)
          .toList(growable: false);
      final results = await Future.wait(
        chunk.asMap().entries.map((entry) {
          final position = offset + entry.key + 1;
          final index = entry.value;
          final row = rows[index];
          final workingRow = Map<String, dynamic>.from(row);
          final restaurantName = (row['name'] ?? '').toString();
          onProgress?.call(
            OsmRestaurantImportProgress(
              postcode: postcode,
              stage: 'enriching_restaurant',
              restaurantName: restaurantName,
              restaurantIndex: position,
              restaurantTotal: total,
              message: 'Searching contact data',
            ),
          );
          return _enrichImportedRow(workingRow)
              .timeout(
                const Duration(
                  seconds:
                      OsmImportConfig.restaurantContactEnrichmentTimeoutSeconds,
                ),
                onTimeout: () {
                  row['contact_enrichment_error'] = 'timeout';
                  row['website_checked_at'] = DateTime.now()
                      .toUtc()
                      .toIso8601String();
                  onProgress?.call(
                    OsmRestaurantImportProgress(
                      postcode: postcode,
                      stage: 'restaurant_timeout',
                      restaurantName: restaurantName,
                      restaurantIndex: position,
                      restaurantTotal: total,
                      message: 'Skipped after 3 minutes without new data',
                    ),
                  );
                  return false;
                },
              )
              .then((changed) {
                if (changed) {
                  row
                    ..clear()
                    ..addAll(workingRow);
                }
                onProgress?.call(
                  OsmRestaurantImportProgress(
                    postcode: postcode,
                    stage: changed
                        ? 'restaurant_enriched'
                        : 'restaurant_checked',
                    restaurantName: restaurantName,
                    restaurantIndex: position,
                    restaurantTotal: total,
                    message: changed ? 'New data found' : 'No new data found',
                  ),
                );
                return changed;
              });
        }),
      );
      enriched += results.where((value) => value).length;
    }
    return enriched;
  }

  Future<bool> _enrichImportedRow(Map<String, dynamic> row) async {
    final before = _contactFingerprint(row);
    var website = _normalizeWebsiteUrl((row['website'] ?? '').toString());
    if (_isSocialWebsite(website)) {
      _copySocialWebsiteToContact(row, website);
      website = '';
    }
    var attemptedWebsiteDiscovery = false;
    if (website.isEmpty && OsmImportConfig.discoverMissingWebsitesByDefault) {
      attemptedWebsiteDiscovery = true;
      final discovered = await _discoverWebsite(row);
      if (discovered != null) {
        website = discovered.url;
        row['website'] = discovered.url;
        row['website_discovery_source'] = discovered.source;
        row['website_discovery_confidence'] = discovered.confidence;
      }
    }
    if (attemptedWebsiteDiscovery) {
      row['website_discovery_checked_at'] = DateTime.now()
          .toUtc()
          .toIso8601String();
    }
    if (website.isEmpty || _isSocialWebsite(website)) {
      row['email'] = await _selectBestVerifiedEmail(
        existingEmail: (row['email'] ?? '').toString(),
        website: '',
        businessName: (row['name'] ?? '').toString(),
        locationName: (row['address'] ?? '').toString(),
      );
      return _contactFingerprint(row) != before;
    }

    row['website'] = website;
    final name = (row['name'] ?? '').toString();
    final address = (row['address'] ?? '').toString();
    final phone = (row['phone'] ?? '').toString();
    await _prefetchPriorityContactPages(website);
    final emailFuture = _selectBestVerifiedEmail(
      existingEmail: (row['email'] ?? '').toString(),
      website: website,
      businessName: name,
      locationName: address,
    );
    final phoneFuture = phone.trim().isEmpty
        ? _extractPhoneFromWebsite(website)
        : Future<String>.value(phone);
    final careersFuture = (row['careers_page'] ?? '').toString().isNotEmpty
        ? Future<String>.value(row['careers_page'].toString())
        : _careersExtractor.find(website).then((value) => value ?? '');
    final facebookFuture = (row['facebook_url'] ?? '').toString().isEmpty
        ? _facebookExtractor
              .find(
                baseUrl: website,
                businessName: name,
                address: address,
                phone: phone,
              )
              .then((value) => value?['link']?.toString() ?? '')
        : Future<String>.value(row['facebook_url'].toString());
    final instagramFuture = (row['instagram_url'] ?? '').toString().isEmpty
        ? _instagramExtractor
              .find(baseUrl: website, businessName: name)
              .then((value) => value?['link']?.toString() ?? '')
        : Future<String>.value(row['instagram_url'].toString());

    final results = await Future.wait<String>([
      emailFuture,
      phoneFuture,
      careersFuture,
      facebookFuture,
      instagramFuture,
    ]);

    row['email'] = results[0];
    row['phone'] = results[1];
    row['careers_page'] = results[2];
    row['facebook_url'] = results[3];
    row['instagram_url'] = results[4];
    row['contact_enrichment_error'] = '';
    row['website_checked_at'] = DateTime.now().toUtc().toIso8601String();
    return _contactFingerprint(row) != before;
  }

  Future<void> _prefetchPriorityContactPages(String website) async {
    final cleanedBase = _cleanBaseUrl(website);
    await ContactHtmlFetcher.prefetchAll([
      cleanedBase,
      _combineUrl(cleanedBase, 'contact'),
      _combineUrl(cleanedBase, 'contact-us'),
      _combineUrl(cleanedBase, 'about'),
      _combineUrl(cleanedBase, 'about-us'),
    ], timeout: const Duration(seconds: 8));
  }

  Future<String> _selectBestVerifiedEmail({
    required String existingEmail,
    required String website,
    required String businessName,
    required String locationName,
  }) async {
    final existing = _emailExtractor.verifyCandidate(
      existingEmail,
      website: website,
      businessName: businessName,
      locationName: locationName,
      originUrl: 'osm',
    );
    final extracted = website.isEmpty || _isSocialWebsite(website)
        ? null
        : await _emailExtractor.extractVerified(
            website,
            businessName: businessName,
            locationName: locationName,
          );

    final candidates = [?existing, ?extracted];
    if (candidates.isEmpty) return '';
    candidates.sort((a, b) => b.score.compareTo(a.score));
    return candidates.first.email;
  }

  Future<String> _extractPhoneFromWebsite(String website) async {
    final cleanedBase = _cleanBaseUrl(website);
    final urls = <String>{
      cleanedBase,
      _combineUrl(cleanedBase, 'contact'),
      _combineUrl(cleanedBase, 'contact-us'),
      _combineUrl(cleanedBase, 'about'),
      _combineUrl(cleanedBase, 'about-us'),
      _combineUrl(cleanedBase, 'reservations'),
      _combineUrl(cleanedBase, 'bookings'),
      _combineUrl(cleanedBase, 'functions'),
      _combineUrl(cleanedBase, 'events'),
    };
    final candidates = <String>{};
    for (final url in urls) {
      final html = await ContactHtmlFetcher.fetch(url);
      if (html == null || html.isEmpty) continue;
      candidates.addAll(_extractPhoneCandidates(html));
      if (candidates.isNotEmpty) break;
    }
    if (candidates.isEmpty) return '';
    final sorted = candidates.toList()
      ..sort((a, b) => _scorePhone(b).compareTo(_scorePhone(a)));
    return sorted.first;
  }

  Set<String> _extractPhoneCandidates(String html) {
    final candidates = <String>{};
    final telRegex = RegExp(
      r'href\s*=\s*["'
      ']tel:([^"'
      ']+)["'
      ']',
      caseSensitive: false,
    );
    for (final match in telRegex.allMatches(html)) {
      final phone = _normalizeAustralianPhone(match.group(1) ?? '');
      if (phone.isNotEmpty) candidates.add(phone);
    }

    final text = _stripHtml(html);
    final phoneRegex = RegExp(r'(\+?61\s?|\(?0)[2-8](?:[\s().-]*\d){8}');
    for (final match in phoneRegex.allMatches(text)) {
      final phone = _normalizeAustralianPhone(match.group(0) ?? '');
      if (phone.isNotEmpty) candidates.add(phone);
    }
    return candidates;
  }

  String _normalizeAustralianPhone(String value) {
    final original = value.trim();
    if (original.isEmpty) return '';
    var digits = original.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('61') && digits.length == 11) {
      digits = '0${digits.substring(2)}';
    }
    if (digits.length != 10 || !digits.startsWith('0')) return '';
    if (!RegExp(r'^0[2-8]\d{8}$').hasMatch(digits)) return '';
    return '${digits.substring(0, 2)} ${digits.substring(2, 6)} ${digits.substring(6)}';
  }

  int _scorePhone(String phone) {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('04')) return 4;
    if (digits.startsWith('02') ||
        digits.startsWith('03') ||
        digits.startsWith('07') ||
        digits.startsWith('08')) {
      return 6;
    }
    return 1;
  }

  Map<String, dynamic> _mergeRestaurant(
    Map<String, dynamic> existing,
    Map<String, dynamic> incoming,
  ) {
    final merged = Map<String, dynamic>.from(existing);
    incoming.forEach((key, value) {
      final current = merged[key];
      final incomingIsUseful =
          value != null && (value is! String || value.trim().isNotEmpty);
      final currentIsEmpty =
          current == null || (current is String && current.trim().isEmpty);
      final shouldReplaceBadWebsite =
          key == 'website' &&
          incomingIsUseful &&
          current is String &&
          current.trim().isNotEmpty &&
          (_isSocialWebsite(current) || _isDirectoryWebsite(current));
      if ((currentIsEmpty || shouldReplaceBadWebsite) && incomingIsUseful) {
        merged[key] = value;
      }
    });
    merged['source_checked_at'] = incoming['source_checked_at'];
    merged['latitude'] = incoming['latitude'];
    merged['longitude'] = incoming['longitude'];
    return merged;
  }

  OsmRestaurantImportSummary _buildImportSummary(
    List<Map<String, dynamic>> rows,
    List<int> indexes,
  ) {
    final uniqueIndexes = indexes.toSet().toList(growable: false);
    var withWebsite = 0;
    var withPhone = 0;
    var withEmail = 0;
    var withFacebook = 0;
    var withInstagram = 0;
    var withCareers = 0;
    var websiteDiscoveryAttempted = 0;
    var websiteDiscovered = 0;
    var websiteFromOsm = 0;
    var websiteFromWikidata = 0;
    var websiteFromKnownBrand = 0;
    var websiteFromProbableDomain = 0;
    final emailContacts = <OsmRestaurantEmailContact>[];

    for (final index in uniqueIndexes) {
      if (index < 0 || index >= rows.length) continue;
      final row = rows[index];
      final website = (row['website'] ?? '').toString().trim();
      final phone = (row['phone'] ?? '').toString().trim();
      final email = (row['email'] ?? '').toString().trim();
      final facebook = (row['facebook_url'] ?? '').toString().trim();
      final instagram = (row['instagram_url'] ?? '').toString().trim();
      final careers = (row['careers_page'] ?? '').toString().trim();
      final discoveryChecked = (row['website_discovery_checked_at'] ?? '')
          .toString()
          .trim();
      final discoverySource = (row['website_discovery_source'] ?? '')
          .toString()
          .trim();

      if (website.isNotEmpty) withWebsite++;
      if (phone.isNotEmpty) withPhone++;
      if (email.isNotEmpty) {
        withEmail++;
        emailContacts.add(
          OsmRestaurantEmailContact(
            name: (row['name'] ?? 'Unknown').toString(),
            email: email,
          ),
        );
      }
      if (facebook.isNotEmpty) withFacebook++;
      if (instagram.isNotEmpty) withInstagram++;
      if (careers.isNotEmpty) withCareers++;
      if (discoveryChecked.isNotEmpty) websiteDiscoveryAttempted++;

      if (website.isNotEmpty) {
        if (discoverySource.isEmpty || discoverySource == 'osm_tag') {
          websiteFromOsm++;
        } else {
          websiteDiscovered++;
          if (discoverySource.startsWith('wikidata:')) {
            websiteFromWikidata++;
          } else if (discoverySource.startsWith('known_brand:')) {
            websiteFromKnownBrand++;
          } else if (discoverySource == 'probable_domain') {
            websiteFromProbableDomain++;
          }
        }
      }
    }

    return OsmRestaurantImportSummary(
      processed: uniqueIndexes.length,
      withWebsite: withWebsite,
      withPhone: withPhone,
      withEmail: withEmail,
      withFacebook: withFacebook,
      withInstagram: withInstagram,
      withCareers: withCareers,
      websiteDiscoveryAttempted: websiteDiscoveryAttempted,
      websiteDiscovered: websiteDiscovered,
      websiteFromOsm: websiteFromOsm,
      websiteFromWikidata: websiteFromWikidata,
      websiteFromKnownBrand: websiteFromKnownBrand,
      websiteFromProbableDomain: websiteFromProbableDomain,
      emailContacts: emailContacts,
    );
  }

  Map<String, String> _requestHeaders() {
    final contactEmail = dotenv.env['OSM_IMPORT_CONTACT_EMAIL']?.trim() ?? '';
    final suffix = contactEmail.isEmpty ? '' : ' ($contactEmail)';
    return {
      'Accept': 'application/json',
      'User-Agent': 'WorkyDay-OSM-Importer/1.0$suffix',
    };
  }

  String _buildAddress(Map tags, String postcode) {
    final parts = <String>[
      [
        (tags['addr:housenumber'] ?? '').toString().trim(),
        (tags['addr:street'] ?? '').toString().trim(),
      ].where((value) => value.isNotEmpty).join(' '),
      (tags['addr:suburb'] ?? tags['addr:city'] ?? tags['addr:town'] ?? '')
          .toString()
          .trim(),
      (tags['addr:state'] ?? getStateFromPostcode(postcode)).toString().trim(),
      postcode,
    ].where((value) => value.isNotEmpty).toList(growable: false);
    return parts.join(', ');
  }

  String _firstTag(Map tags, List<String> keys) {
    for (final key in keys) {
      final value = (tags[key] ?? '').toString().trim();
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  Future<_WebsiteDiscovery?> _discoverWebsite(Map<String, dynamic> row) async {
    final taggedWebsite = _normalizeWebsiteUrl(
      (row['website'] ?? '').toString(),
    );
    if (taggedWebsite.isNotEmpty && !_isSocialWebsite(taggedWebsite)) {
      return _WebsiteDiscovery(
        url: taggedWebsite,
        source: 'osm_tag',
        confidence: 100,
      );
    }

    final fromWikidata = await _discoverWebsiteFromWikidata(row);
    if (fromWikidata != null) return fromWikidata;

    final fromBrand = _discoverKnownBrandWebsite(row);
    if (fromBrand != null) return fromBrand;

    return _discoverProbableDomain(row);
  }

  Future<_WebsiteDiscovery?> _discoverWebsiteFromWikidata(
    Map<String, dynamic> row,
  ) async {
    final wikidataId = _extractWikidataId(
      (row['osm_wikidata'] ?? '').toString(),
    );
    if (wikidataId.isEmpty) return null;

    try {
      final uri = Uri.parse(
        'https://www.wikidata.org/wiki/Special:EntityData/$wikidataId.json',
      );
      final response = await _client
          .get(uri, headers: _requestHeaders())
          .timeout(
            Duration(seconds: OsmImportConfig.websiteDiscoveryTimeoutSeconds),
          );
      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) return null;
      final entities = decoded['entities'];
      if (entities is! Map) return null;
      final entity = entities[wikidataId];
      if (entity is! Map) return null;
      final claims = entity['claims'];
      if (claims is! Map) return null;

      final website = _extractWikidataStringClaim(claims['P856']);
      final normalizedWebsite = _normalizeWebsiteUrl(website);
      if (normalizedWebsite.isNotEmpty &&
          !_isSocialWebsite(normalizedWebsite) &&
          !_isDirectoryWebsite(normalizedWebsite)) {
        return _WebsiteDiscovery(
          url: normalizedWebsite,
          source: 'wikidata:P856',
          confidence: 92,
        );
      }

      final facebookHandle = _extractWikidataStringClaim(claims['P2013']);
      if ((row['facebook_url'] ?? '').toString().isEmpty &&
          facebookHandle.trim().isNotEmpty) {
        row['facebook_url'] = _normalizeSocialUrl(
          facebookHandle,
          'facebook.com',
        );
      }
      final instagramHandle = _extractWikidataStringClaim(claims['P2003']);
      if ((row['instagram_url'] ?? '').toString().isEmpty &&
          instagramHandle.trim().isNotEmpty) {
        row['instagram_url'] = _normalizeSocialUrl(
          instagramHandle,
          'instagram.com',
        );
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  _WebsiteDiscovery? _discoverKnownBrandWebsite(Map<String, dynamic> row) {
    final candidates = <String>[
      (row['osm_brand'] ?? '').toString(),
      (row['name'] ?? '').toString(),
    ];
    for (final candidate in candidates) {
      final brandKey = _knownBrandKey(candidate);
      if (brandKey.isEmpty) continue;
      final website = _knownBrandWebsites[brandKey];
      if (website == null || website.isEmpty) continue;
      return _WebsiteDiscovery(
        url: website,
        source: 'known_brand:$brandKey',
        confidence: 80,
      );
    }
    return null;
  }

  Future<_WebsiteDiscovery?> _discoverProbableDomain(
    Map<String, dynamic> row,
  ) async {
    final candidates = _probableDomainCandidates(row)
        .where((url) => !_isDirectoryWebsite(url))
        .take(OsmImportConfig.websiteDiscoveryMaxCandidatesPerBusiness)
        .toList(growable: false);
    for (final candidate in candidates) {
      final validation = await _validateProbableWebsite(candidate, row);
      if (validation != null && validation.confidence >= 65) {
        return validation;
      }
    }
    return null;
  }

  List<String> _probableDomainCandidates(Map<String, dynamic> row) {
    final name = (row['name'] ?? '').toString();
    final locality = _extractLocality(row);
    final base = _domainSlug(name);
    if (base.length < 4) return const <String>[];

    final localitySlug = _domainSlug(locality);
    final variants = <String>{
      base,
      if (localitySlug.isNotEmpty) '$base$localitySlug',
      if (localitySlug.isNotEmpty) '$base-$localitySlug',
    };
    final urls = <String>[];
    for (final variant in variants) {
      urls.add('https://www.$variant.com.au/');
      urls.add('https://$variant.com.au/');
      urls.add('https://www.$variant.com/');
      urls.add('https://$variant.com/');
    }
    return urls;
  }

  Future<_WebsiteDiscovery?> _validateProbableWebsite(
    String candidateUrl,
    Map<String, dynamic> row,
  ) async {
    try {
      final uri = Uri.parse(candidateUrl);
      final response = await _client
          .get(uri, headers: _htmlRequestHeaders())
          .timeout(
            Duration(seconds: OsmImportConfig.websiteDiscoveryTimeoutSeconds),
          );
      if (response.statusCode < 200 || response.statusCode >= 400) {
        return null;
      }
      final contentType = response.headers['content-type']?.toLowerCase() ?? '';
      if (contentType.isNotEmpty && !contentType.contains('text/html')) {
        return null;
      }
      final finalUrl = _normalizeWebsiteUrl(
        response.request?.url.toString() ?? candidateUrl,
      );
      if (finalUrl.isEmpty ||
          _isSocialWebsite(finalUrl) ||
          _isDirectoryWebsite(finalUrl)) {
        return null;
      }
      final body = response.body;
      final lowerBody = _stripHtml(body).toLowerCase();
      final name = (row['name'] ?? '').toString();
      final postcode = (row['postcode_display'] ?? row['postcode'] ?? '')
          .toString();
      final locality = _extractLocality(row);
      final phone = (row['phone'] ?? '').toString();
      final score = _scoreWebsiteMatch(
        content: lowerBody,
        host: Uri.tryParse(finalUrl)?.host.toLowerCase() ?? '',
        name: name,
        postcode: postcode,
        locality: locality,
        phone: phone,
      );
      if (score < 65) return null;
      return _WebsiteDiscovery(
        url: finalUrl,
        source: 'probable_domain',
        confidence: score,
      );
    } catch (_) {
      return null;
    }
  }

  int _scoreWebsiteMatch({
    required String content,
    required String host,
    required String name,
    required String postcode,
    required String locality,
    required String phone,
  }) {
    var score = 0;
    final nameTokens = _meaningfulTokens(name);
    if (nameTokens.isEmpty) return 0;

    final matchedNameTokens = nameTokens
        .where((token) => content.contains(token) || host.contains(token))
        .length;
    score += (matchedNameTokens / nameTokens.length * 55).round();
    if (host.contains(_domainSlug(name))) score += 20;
    if (postcode.trim().isNotEmpty && content.contains(postcode.trim())) {
      score += 20;
    }
    final localityTokens = _meaningfulTokens(locality);
    if (localityTokens.isNotEmpty &&
        localityTokens.any((token) => content.contains(token))) {
      score += 12;
    }
    final phoneDigits = phone.replaceAll(RegExp(r'\D'), '');
    if (phoneDigits.length >= 8 &&
        content
            .replaceAll(RegExp(r'\D'), '')
            .contains(phoneDigits.substring(phoneDigits.length - 8))) {
      score += 25;
    }
    if (content.contains('restaurant') ||
        content.contains('cafe') ||
        content.contains('menu') ||
        content.contains('book a table') ||
        content.contains('takeaway')) {
      score += 8;
    }
    return score.clamp(0, 100).toInt();
  }

  String _stripHtml(String html) {
    return html
        .replaceAll(
          RegExp(r'<script[\s\S]*?</script>', caseSensitive: false),
          ' ',
        )
        .replaceAll(
          RegExp(r'<style[\s\S]*?</style>', caseSensitive: false),
          ' ',
        )
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ');
  }

  List<String> _meaningfulTokens(String value) {
    const ignored = {
      'the',
      'and',
      'cafe',
      'restaurant',
      'bar',
      'pub',
      'pizza',
      'grill',
      'takeaway',
      'food',
      'coffee',
      'shop',
      'kitchen',
      'australia',
      'australian',
    };
    return value
        .toLowerCase()
        .replaceAll('&', ' and ')
        .split(RegExp(r'[^a-z0-9]+'))
        .where((token) => token.length >= 3 && !ignored.contains(token))
        .toList(growable: false);
  }

  String _domainSlug(String value) {
    return value
        .toLowerCase()
        .replaceAll('&', 'and')
        .replaceAll(RegExp(r'\b(pty|ltd|limited|trading|co|company)\b'), '')
        .replaceAll(RegExp(r'[^a-z0-9]+'), '')
        .trim();
  }

  String _extractLocality(Map<String, dynamic> row) {
    final explicit = (row['locality'] ?? row['suburb'] ?? row['city'] ?? '')
        .toString()
        .trim();
    if (explicit.isNotEmpty) return explicit;
    final address = (row['address'] ?? '').toString();
    final parts = address
        .split(',')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
    if (parts.length >= 4) return parts[1];
    if (parts.length >= 3) return parts.first;
    return '';
  }

  String _knownBrandKey(String value) {
    final normalized = value
        .toLowerCase()
        .replaceAll('&', 'and')
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .trim();
    if (normalized.isEmpty) return '';
    final compact = _normalizeName(normalized);
    for (final key in _knownBrandWebsites.keys) {
      final compactKey = _normalizeName(key);
      if (normalized == key ||
          normalized.startsWith('$key ') ||
          compact == compactKey ||
          compact.startsWith(compactKey)) {
        return key;
      }
    }
    return '';
  }

  String _extractWikidataId(String value) {
    final match = RegExp(r'Q\d+', caseSensitive: false).firstMatch(value);
    return match?.group(0)?.toUpperCase() ?? '';
  }

  String _extractWikidataStringClaim(dynamic rawClaims) {
    if (rawClaims is! List || rawClaims.isEmpty) return '';
    for (final claim in rawClaims) {
      if (claim is! Map) continue;
      final mainsnak = claim['mainsnak'];
      if (mainsnak is! Map) continue;
      final datavalue = mainsnak['datavalue'];
      if (datavalue is! Map) continue;
      final value = datavalue['value'];
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    return '';
  }

  void _copySocialWebsiteToContact(Map<String, dynamic> row, String website) {
    final host = Uri.tryParse(website)?.host.toLowerCase() ?? '';
    if (host.contains('facebook.com') &&
        (row['facebook_url'] ?? '').toString().isEmpty) {
      row['facebook_url'] = website;
    }
    if (host.contains('instagram.com') &&
        (row['instagram_url'] ?? '').toString().isEmpty) {
      row['instagram_url'] = website;
    }
  }

  String _normalizeSocialUrl(String value, String domain) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return '';
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }
    final handle = trimmed.replaceFirst(RegExp(r'^@'), '');
    return 'https://$domain/$handle';
  }

  int? _findNearbyDuplicateIndex(
    List<Map<String, dynamic>> existing,
    Map<String, dynamic> candidate,
  ) {
    final candidateName = _normalizeName(candidate['name']);
    final candidatePostcode = (candidate['postcode_display'] ?? '')
        .toString()
        .padLeft(4, '0');
    final candidateLat = _asDouble(candidate['latitude']);
    final candidateLng = _asDouble(candidate['longitude']);
    if (candidateName.isEmpty || candidateLat == null || candidateLng == null) {
      return null;
    }

    for (var index = 0; index < existing.length; index++) {
      final row = existing[index];
      if (_normalizeName(row['name']) != candidateName) continue;
      final rowPostcode = (row['postcode_display'] ?? row['postcode'] ?? '')
          .toString()
          .padLeft(4, '0');
      if (rowPostcode != candidatePostcode) continue;
      final rowLat = _asDouble(row['latitude'] ?? row['lat']);
      final rowLng = _asDouble(row['longitude'] ?? row['lng']);
      if (rowLat == null || rowLng == null) continue;
      if (_distanceMeters(candidateLat, candidateLng, rowLat, rowLng) <= 120) {
        return index;
      }
    }
    return null;
  }

  String _normalizeName(dynamic name) {
    return name.toString().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  double _distanceMeters(double lat1, double lng1, double lat2, double lng2) {
    const earthRadiusMeters = 6371000.0;
    final latDelta = (lat2 - lat1) * math.pi / 180;
    final lngDelta = (lng2 - lng1) * math.pi / 180;
    final a =
        math.sin(latDelta / 2) * math.sin(latDelta / 2) +
        math.cos(lat1 * math.pi / 180) *
            math.cos(lat2 * math.pi / 180) *
            math.sin(lngDelta / 2) *
            math.sin(lngDelta / 2);
    return earthRadiusMeters * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  bool _isSocialWebsite(String website) {
    final host = Uri.tryParse(website)?.host.toLowerCase() ?? '';
    return host.contains('facebook.com') ||
        host.contains('instagram.com') ||
        host.contains('tiktok.com');
  }

  bool _isDirectoryWebsite(String website) {
    final host = Uri.tryParse(website)?.host.toLowerCase() ?? '';
    if (host.isEmpty) return true;
    return _directoryHosts.any(host.contains);
  }

  Map<String, String> _htmlRequestHeaders() {
    return {
      ..._requestHeaders(),
      'Accept':
          'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
    };
  }

  String _normalizeWebsiteUrl(String value) {
    var normalized = value.trim();
    if (normalized.isEmpty) return '';
    if (!RegExp(r'^https?://', caseSensitive: false).hasMatch(normalized)) {
      normalized = 'https://$normalized';
    }
    final uri = Uri.tryParse(normalized);
    if (uri == null || uri.host.trim().isEmpty) return '';
    if (uri.scheme != 'http' && uri.scheme != 'https') return '';
    return uri.replace(fragment: '').toString();
  }

  String _cleanBaseUrl(String value) {
    final normalized = _normalizeWebsiteUrl(value);
    final uri = Uri.tryParse(normalized);
    if (uri == null || uri.host.isEmpty) return normalized;
    return uri.replace(path: '', query: '', fragment: '').toString();
  }

  String _combineUrl(String base, String path) {
    if (path.startsWith('http')) return path;
    if (base.endsWith('/')) return '$base$path';
    return '$base/$path';
  }

  String _contactFingerprint(Map<String, dynamic> row) {
    return [
      row['website'],
      row['phone'],
      row['email'],
      row['facebook_url'],
      row['instagram_url'],
      row['careers_page'],
    ].map((value) => (value ?? '').toString().trim()).join('|');
  }

  double? _asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }
}

class _WebsiteDiscovery {
  const _WebsiteDiscovery({
    required this.url,
    required this.source,
    required this.confidence,
  });

  final String url;
  final String source;
  final int confidence;
}

class _OsmPostcodeArea {
  const _OsmPostcodeArea({
    required this.latitude,
    required this.longitude,
    this.south,
    this.west,
    this.north,
    this.east,
  });

  final double latitude;
  final double longitude;
  final double? south;
  final double? west;
  final double? north;
  final double? east;

  bool get hasBounds =>
      south != null &&
      west != null &&
      north != null &&
      east != null &&
      south! < north! &&
      west! < east!;
}
