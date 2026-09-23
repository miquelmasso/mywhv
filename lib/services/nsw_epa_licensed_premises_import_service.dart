import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/construction_domain_records.dart';
import 'map_markers_service.dart';

class NswEpaLicensedPremisesImportResult {
  const NswEpaLicensedPremisesImportResult({
    required this.premises,
    required this.employerLinks,
    required this.spatialPremises,
    required this.added,
    required this.updated,
    required this.usedCache,
  });

  final int premises;
  final int employerLinks;
  final int spatialPremises;
  final int added;
  final int updated;
  final bool usedCache;
}

class NswEpaLicensedPremise {
  const NswEpaLicensedPremise({
    required this.licenceNumber,
    required this.holderName,
    required this.locationName,
    required this.activity,
    required this.address,
    required this.suburb,
    required this.postcode,
    required this.latitude,
    required this.longitude,
    this.tradingName = '',
    this.verifiedAt = '',
  });

  final String licenceNumber;
  final String holderName;
  final String tradingName;
  final String locationName;
  final String activity;
  final String address;
  final String suburb;
  final String postcode;
  final double? latitude;
  final double? longitude;
  final String verifiedAt;

  Map<String, dynamic> toJson() => {
    'licence_number': licenceNumber,
    'holder_name': holderName,
    'trading_name': tradingName,
    'location_name': locationName,
    'activity': activity,
    'address': address,
    'suburb': suburb,
    'postcode': postcode,
    'latitude': latitude,
    'longitude': longitude,
    'verified_at': verifiedAt,
  };

  factory NswEpaLicensedPremise.fromJson(Map<String, dynamic> json) =>
      NswEpaLicensedPremise(
        licenceNumber: (json['licence_number'] ?? '').toString(),
        holderName: (json['holder_name'] ?? '').toString(),
        tradingName: (json['trading_name'] ?? '').toString(),
        locationName: (json['location_name'] ?? '').toString(),
        activity: (json['activity'] ?? '').toString(),
        address: (json['address'] ?? '').toString(),
        suburb: (json['suburb'] ?? '').toString(),
        postcode: (json['postcode'] ?? '').toString(),
        latitude: _asDouble(json['latitude']),
        longitude: _asDouble(json['longitude']),
        verifiedAt: (json['verified_at'] ?? '').toString(),
      );
}

/// Adds current NSW EPA licensed construction premises as an independent,
/// official source. The licence holder is linked as the premises operator only
/// when it is clearly a corporate entity. Other holders are retained as local
/// worksites without being presented as employers.
class NswEpaLicensedPremisesImportService {
  NswEpaLicensedPremisesImportService({http.Client? client})
    : _client = client ?? http.Client();

  static const sourcePageUrl =
      'https://data.nsw.gov.au/data/dataset/poeo-public-register';
  static const sourceDataUrl =
      'https://mapprod2.environment.nsw.gov.au/arcgis/rest/services/'
      'EPA/Environment_Protection_Licences/FeatureServer/2/query';
  static const _cacheKey = 'nsw_epa_construction_premises_v1';
  static const _cacheTimeKey = 'nsw_epa_construction_premises_checked_at_v1';
  static const _cacheDuration = Duration(days: 30);
  static const _pageSize = 1000;

  static const constructionActivities = <String>{
    'Mining for coal',
    'Mining for minerals',
    'Other extractive activities',
    'Concrete works',
    'Crushing, grinding or separating',
    'Road construction',
    'Road construction (<50,000T)',
    'Road construction (>=50,000T & road to be constructed <10km)',
    'Road construction (>=50,000T & road to be constructed >10km & <30km)',
    'Railway infrastructure construction (>=50,000T & track to be constructed <=10km)',
    'Railway infrastructure construction (>=50,000T & track to be constructed>30km)',
    'Railway systems activities',
  };

  final http.Client _client;

  Future<NswEpaLicensedPremisesImportResult> importLocal({
    bool forceRefresh = false,
  }) async {
    final loaded = await _loadPremises(forceRefresh: forceRefresh);
    final existing = await MapMarkersService.loadConstructionCompanies(
      lightweight: false,
      syncFromFirebaseIfNeeded: false,
    );
    final rows = buildRows(loaded.premises, existing);
    final write = await MapMarkersService.upsertLocalConstructionCompanies(
      rows,
    );
    return NswEpaLicensedPremisesImportResult(
      premises: loaded.premises.length,
      employerLinks: rows
          .where(
            (row) =>
                (row['company_worksite_role'] ?? '').toString() == 'operator',
          )
          .length,
      spatialPremises: loaded.premises
          .where(
            (premise) => premise.latitude != null && premise.longitude != null,
          )
          .length,
      added: write.added,
      updated: write.updated,
      usedCache: loaded.cached,
    );
  }

  Future<({List<NswEpaLicensedPremise> premises, bool cached})> _loadPremises({
    required bool forceRefresh,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final cached = _readCache(prefs);
    final checkedAt = DateTime.tryParse(prefs.getString(_cacheTimeKey) ?? '');
    final isFresh =
        checkedAt != null &&
        DateTime.now().difference(checkedAt) < _cacheDuration;
    if (!forceRefresh && isFresh && cached.isNotEmpty) {
      return (premises: cached, cached: true);
    }

    try {
      final premises = <NswEpaLicensedPremise>[];
      var offset = 0;
      while (true) {
        final uri = Uri.parse(sourceDataUrl).replace(
          queryParameters: {
            'where': _activityWhereClause(),
            'outFields':
                'OBJECTID,EPL,APName,TradingName,LocationName,Address,'
                'Suburb,Postcode,State,PrimaryFeebasedActivity,'
                'PrimarySchedActivity,VerDate',
            'returnGeometry': 'true',
            'outSR': '4326',
            'orderByFields': 'OBJECTID',
            'resultOffset': '$offset',
            'resultRecordCount': '$_pageSize',
            'f': 'json',
          },
        );
        final response = await _client
            .get(
              uri,
              headers: const {
                'User-Agent':
                    'WorkyDay public-data importer (infrequent local refresh)',
                'Accept': 'application/json',
              },
            )
            .timeout(const Duration(seconds: 45));
        if (response.statusCode != 200) {
          throw StateError(
            'NSW EPA licensed premises returned HTTP ${response.statusCode}.',
          );
        }
        final decoded = jsonDecode(response.body);
        if (decoded is! Map || decoded['error'] != null) {
          throw const FormatException('Invalid NSW EPA premises response.');
        }
        final page = recordsFromArcGis(Map<String, dynamic>.from(decoded));
        premises.addAll(page);
        final exceeded = decoded['exceededTransferLimit'] == true;
        if (!exceeded || page.isEmpty) break;
        offset += page.length;
      }
      if (premises.isEmpty) {
        throw const FormatException(
          'NSW EPA construction premises were empty.',
        );
      }
      await prefs.setString(
        _cacheKey,
        jsonEncode(premises.map((premise) => premise.toJson()).toList()),
      );
      await prefs.setString(_cacheTimeKey, DateTime.now().toIso8601String());
      return (premises: premises, cached: false);
    } catch (_) {
      if (cached.isNotEmpty) return (premises: cached, cached: true);
      rethrow;
    }
  }

  static List<NswEpaLicensedPremise> recordsFromArcGis(
    Map<String, dynamic> decoded,
  ) {
    final features = decoded['features'];
    if (features is! List) {
      throw const FormatException('Invalid NSW EPA premises features.');
    }
    final premises = <NswEpaLicensedPremise>[];
    for (final rawFeature in features.whereType<Map>()) {
      final feature = Map<String, dynamic>.from(rawFeature);
      final rawAttributes = feature['attributes'];
      if (rawAttributes is! Map) continue;
      final attributes = Map<String, dynamic>.from(rawAttributes);
      final licenceNumber = (attributes['EPL'] ?? '').toString().trim();
      final holderName = (attributes['APName'] ?? '').toString().trim();
      final activity = (attributes['PrimaryFeebasedActivity'] ?? '')
          .toString()
          .trim();
      if (licenceNumber.isEmpty ||
          holderName.isEmpty ||
          !constructionActivities.contains(activity)) {
        continue;
      }
      final center = _polygonCenter(feature['geometry']);
      final verifiedMillis = _asInt(attributes['VerDate']);
      premises.add(
        NswEpaLicensedPremise(
          licenceNumber: licenceNumber,
          holderName: holderName,
          tradingName: (attributes['TradingName'] ?? '').toString().trim(),
          locationName: (attributes['LocationName'] ?? '').toString().trim(),
          activity: activity,
          address: (attributes['Address'] ?? '').toString().trim(),
          suburb: (attributes['Suburb'] ?? '').toString().trim(),
          postcode: (attributes['Postcode'] ?? '').toString().trim(),
          latitude: center?.$2,
          longitude: center?.$1,
          verifiedAt: verifiedMillis == null
              ? ''
              : DateTime.fromMillisecondsSinceEpoch(
                  verifiedMillis,
                  isUtc: true,
                ).toIso8601String(),
        ),
      );
    }
    return premises;
  }

  static List<Map<String, dynamic>> buildRows(
    List<NswEpaLicensedPremise> premises,
    List<Map<String, dynamic>> existing,
  ) {
    final contactsByCompanyId = <String, Map<String, dynamic>>{};
    final aliasesByCompanyId = <String, Set<String>>{};
    for (final row in existing) {
      final companyId = ConstructionDomainRecords.companyId(row);
      if (companyId.isEmpty) continue;
      final aliases = aliasesByCompanyId.putIfAbsent(companyId, () => {});
      for (final key in const [
        'name',
        'trading_name',
        'parent_company_name',
        'subsidiary_name',
        'osm_brand',
        'osm_operator',
      ]) {
        final alias = (row[key] ?? '').toString().trim();
        if (alias.isNotEmpty) aliases.add(alias);
      }
      if (_contactScore(row) == 0) continue;
      final previous = contactsByCompanyId[companyId];
      if (previous == null || _contactScore(row) > _contactScore(previous)) {
        contactsByCompanyId[companyId] = row;
      }
    }

    return premises
        .map((premise) {
          final isCompany = _isCorporateHolder(premise.holderName);
          final identityName = premise.tradingName.isNotEmpty
              ? premise.tradingName
              : premise.holderName;
          final identityKey = ConstructionDomainRecords.normalizeIdentity(
            premise.holderName,
          );
          final companyId = isCompany && identityKey.isNotEmpty
              ? 'company:name:$identityKey'
              : '';
          final worksiteName = premise.locationName.isNotEmpty
              ? premise.locationName
              : '${premise.activity} · EPL ${premise.licenceNumber}';
          final address = <String>[
            premise.address,
            premise.suburb,
            premise.postcode,
          ].where((part) => part.isNotEmpty).join(', ');
          final isMining = _isMiningActivity(premise.activity);
          final identityAliases = <String>{
            premise.holderName,
            if (premise.tradingName.isNotEmpty) premise.tradingName,
            ...?aliasesByCompanyId[companyId],
          }.toList(growable: false);
          final row = <String, dynamic>{
            'id': 'nsw_epa_licensed_premise_${premise.licenceNumber}',
            'docId': 'nsw_epa_licensed_premise_${premise.licenceNumber}',
            'source_place_id':
                'nsw:epa:licensed_premise:${premise.licenceNumber}',
            'source': 'nsw_epa_licensed_premises',
            'name': isCompany ? identityName : worksiteName,
            'worksite_name': worksiteName,
            'worksite_id':
                'worksite:nsw_epa_licensed_premise:${premise.licenceNumber}',
            'state': 'NSW',
            if (premise.latitude != null) 'latitude': premise.latitude,
            if (premise.longitude != null) 'longitude': premise.longitude,
            'address': address,
            'postcode': premise.postcode,
            'postcode_display': premise.postcode,
            'trading_name': premise.tradingName,
            'epa_licence_number': premise.licenceNumber,
            'epa_primary_activity': premise.activity,
            'epa_spatial_verified_at': premise.verifiedAt,
            'worksite_stage': 'Licensed premises',
            'record_type': 'construction_worksite',
            'company_id': companyId,
            'company_worksite_role': isCompany ? 'operator' : '',
            'relationship_role': isCompany ? 'licensed_operator' : '',
            'link_corroborated': isCompany,
            'company_worksite_evidence': isCompany
                ? 'NSW EPA licence explicitly associates the corporate licence holder with this licensed premises and activity'
                : '',
            'construction_category': isMining
                ? 'mining_company'
                : 'civil_construction',
            'entity_kind': isCompany ? 'employer' : 'project_site',
            'classification_confidence': isCompany ? 96 : 100,
            'classification_reason': isCompany
                ? 'Official NSW EPA licence identifies a corporate holder responsible for a construction, extractive, mining, road or rail premises'
                : 'Premises retained locally without inferring that a personal or public-sector licence holder is a construction employer',
            'classification_source': 'open_data_corroboration',
            'review_status': isCompany
                ? 'ready_for_contact_enrichment'
                : 'local_worksite_only',
            'catalog_sources': const <String>['nsw_epa_public_register'],
            'source_url': sourcePageUrl,
            'source_data_url': sourceDataUrl,
            'source_license': 'CC BY 4.0',
            'source_attribution':
                'NSW Environment Protection Authority public register',
            'location_role': 'worksite',
            'place_type': 'construction',
            'marker_kind': 'construction',
            'contact_enrichment_status': isCompany
                ? 'pending'
                : 'not_applicable_unlinked_worksite',
            if (companyId.isNotEmpty)
              'company_identity_aliases': identityAliases,
          };
          if (companyId.isNotEmpty) {
            _copyContacts(row, contactsByCompanyId[companyId]);
          }
          return row;
        })
        .toList(growable: false);
  }

  static List<NswEpaLicensedPremise> _readCache(SharedPreferences prefs) {
    try {
      final decoded = jsonDecode(prefs.getString(_cacheKey) ?? '[]');
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map(
            (row) =>
                NswEpaLicensedPremise.fromJson(Map<String, dynamic>.from(row)),
          )
          .where(
            (premise) =>
                premise.licenceNumber.isNotEmpty &&
                premise.holderName.isNotEmpty &&
                constructionActivities.contains(premise.activity),
          )
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  static String _activityWhereClause() {
    final values = constructionActivities
        .map((activity) => "'${activity.replaceAll("'", "''")}'")
        .join(',');
    return 'PrimaryFeebasedActivity IN ($values)';
  }

  static bool _isMiningActivity(String activity) {
    final lower = activity.toLowerCase();
    return lower.contains('mining') ||
        lower.contains('extractive') ||
        lower.contains('crushing');
  }

  static bool _isCorporateHolder(String value) {
    final upper = value.toUpperCase().replaceAll(RegExp(r'\s+'), ' ').trim();
    if (upper.isEmpty ||
        RegExp(
          r'\b(COUNCIL|MINISTER|DEPARTMENT|GOVERNMENT|CITY OF|SHIRE OF)\b',
        ).hasMatch(upper)) {
      return false;
    }
    return RegExp(
      r'\b(PTY|LIMITED|LTD|CORPORATION|CORP|INCORPORATED|INC|COMPANY|CO-OPERATIVE)\b',
    ).hasMatch(upper);
  }

  static (double, double)? _polygonCenter(Object? rawGeometry) {
    if (rawGeometry is! Map) return null;
    final rings = rawGeometry['rings'];
    if (rings is! List) return null;
    (double, double, double)? best;
    for (final rawRing in rings.whereType<List>()) {
      final points = rawRing
          .whereType<List>()
          .map((point) {
            if (point.length < 2) return null;
            final x = _asDouble(point[0]);
            final y = _asDouble(point[1]);
            return x == null || y == null ? null : (x, y);
          })
          .whereType<(double, double)>()
          .toList(growable: false);
      if (points.length < 3) continue;
      var twiceArea = 0.0;
      var weightedX = 0.0;
      var weightedY = 0.0;
      for (var index = 0; index < points.length; index++) {
        final current = points[index];
        final next = points[(index + 1) % points.length];
        final cross = current.$1 * next.$2 - next.$1 * current.$2;
        twiceArea += cross;
        weightedX += (current.$1 + next.$1) * cross;
        weightedY += (current.$2 + next.$2) * cross;
      }
      if (twiceArea.abs() < 1e-12) continue;
      final centerX = weightedX / (3 * twiceArea);
      final centerY = weightedY / (3 * twiceArea);
      final candidate = (twiceArea.abs(), centerX, centerY);
      if (best == null || candidate.$1 > best.$1) best = candidate;
    }
    if (best != null && best.$2.isFinite && best.$3.isFinite) {
      return (best.$2, best.$3);
    }

    final points = rings
        .whereType<List>()
        .expand((ring) => ring.whereType<List>())
        .where((point) => point.length >= 2)
        .map((point) => (_asDouble(point[0]), _asDouble(point[1])))
        .where((point) => point.$1 != null && point.$2 != null)
        .toList(growable: false);
    if (points.isEmpty) return null;
    final minX = points.map((point) => point.$1!).reduce(math.min);
    final maxX = points.map((point) => point.$1!).reduce(math.max);
    final minY = points.map((point) => point.$2!).reduce(math.min);
    final maxY = points.map((point) => point.$2!).reduce(math.max);
    return ((minX + maxX) / 2, (minY + maxY) / 2);
  }

  static int _contactScore(Map<String, dynamic> row) {
    const fields = <String>[
      'website',
      'phone',
      'email',
      'careers_page',
      'facebook_url',
      'instagram_url',
    ];
    return fields
        .where((field) => (row[field] ?? '').toString().trim().isNotEmpty)
        .length;
  }

  static void _copyContacts(
    Map<String, dynamic> target,
    Map<String, dynamic>? source,
  ) {
    if (source == null) return;
    const fields = <String>[
      'website',
      'phone',
      'email',
      'careers_page',
      'facebook_url',
      'instagram_url',
      'website_checked_at',
      'website_discovery_checked_at',
      'website_discovery_source',
      'website_discovery_confidence',
      'website_discovery_candidates',
      'known_company_website',
      'known_company_website_evidence',
      'application_contact_type',
      'application_contact_confidence',
      'application_contact_evidence',
      'contact_enrichment_status',
      'contact_enrichment_source',
      'contact_enrichment_error',
      'contact_enrichment_stage',
      'contact_enrichment_failure_kind',
    ];
    for (final field in fields) {
      final value = source[field];
      if (value != null && value.toString().isNotEmpty) target[field] = value;
    }
  }
}

double? _asDouble(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse((value ?? '').toString());
}

int? _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse((value ?? '').toString());
}
