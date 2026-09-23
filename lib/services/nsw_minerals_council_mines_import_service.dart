import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/construction_domain_records.dart';
import 'map_markers_service.dart';

class NswMineralsCouncilMine {
  const NswMineralsCouncilMine({
    required this.id,
    required this.name,
    required this.operatorName,
    required this.latitude,
    required this.longitude,
    required this.status,
    this.address = '',
    this.postcode = '',
    this.commodity = '',
    this.projectUrl = '',
  });

  final String id;
  final String name;
  final String operatorName;
  final double latitude;
  final double longitude;
  final String status;
  final String address;
  final String postcode;
  final String commodity;
  final String projectUrl;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'operator_name': operatorName,
    'latitude': latitude,
    'longitude': longitude,
    'status': status,
    'address': address,
    'postcode': postcode,
    'commodity': commodity,
    'project_url': projectUrl,
  };

  factory NswMineralsCouncilMine.fromJson(Map<String, dynamic> json) =>
      NswMineralsCouncilMine(
        id: (json['id'] ?? '').toString(),
        name: (json['name'] ?? '').toString(),
        operatorName: (json['operator_name'] ?? '').toString(),
        latitude: _mineAsDouble(json['latitude']) ?? 0,
        longitude: _mineAsDouble(json['longitude']) ?? 0,
        status: (json['status'] ?? '').toString(),
        address: (json['address'] ?? '').toString(),
        postcode: (json['postcode'] ?? '').toString(),
        commodity: (json['commodity'] ?? '').toString(),
        projectUrl: (json['project_url'] ?? '').toString(),
      );
}

double? _mineAsDouble(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse((value ?? '').toString());
}

class NswMineralsCouncilMinesImportResult {
  const NswMineralsCouncilMinesImportResult({
    required this.operatingMines,
    required this.employerLinks,
    required this.added,
    required this.updated,
    required this.usedCache,
  });

  final int operatingMines;
  final int employerLinks;
  final int added;
  final int updated;
  final bool usedCache;
}

/// Imports the NSW Minerals Council public mine map as an industry-source
/// operator/worksite relationship. Only records explicitly marked Operating
/// are eligible. Proposed, closed, and care-and-maintenance sites are retained
/// by the upstream source but are intentionally not imported as hiring links.
class NswMineralsCouncilMinesImportService {
  NswMineralsCouncilMinesImportService({http.Client? client})
    : _client = client ?? http.Client();

  static const sourcePageUrl =
      'https://nswmining.com.au/mining-in-nsw/map-of-nsw-mines/';
  static const sourceDataUrl =
      'https://nswmining.com.au/wp-admin/admin-ajax.php'
      '?action=store_search&lat=-31.253218&lng=146.921099'
      '&max_results=100&search_radius=2000&autoload=1';
  static const _cacheKey = 'nsw_minerals_council_operating_mines_v1';
  static const _cacheTimeKey =
      'nsw_minerals_council_operating_mines_checked_at_v1';
  static const _cacheDuration = Duration(days: 30);

  final http.Client _client;

  Future<NswMineralsCouncilMinesImportResult> importLocal({
    bool forceRefresh = false,
  }) async {
    final loaded = await _loadMines(forceRefresh: forceRefresh);
    final existing = await MapMarkersService.loadConstructionCompanies(
      lightweight: false,
      syncFromFirebaseIfNeeded: false,
    );
    final rows = buildCorroboratedRows(loaded.mines, existing);
    final write = await MapMarkersService.upsertLocalConstructionCompanies(
      rows,
    );
    return NswMineralsCouncilMinesImportResult(
      operatingMines: loaded.mines.length,
      employerLinks: rows.length,
      added: write.added,
      updated: write.updated,
      usedCache: loaded.cached,
    );
  }

  Future<({List<NswMineralsCouncilMine> mines, bool cached})> _loadMines({
    required bool forceRefresh,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final cached = _readCache(prefs);
    final checkedAt = DateTime.tryParse(prefs.getString(_cacheTimeKey) ?? '');
    final fresh =
        checkedAt != null &&
        DateTime.now().difference(checkedAt) < _cacheDuration;
    if (!forceRefresh && fresh && cached.isNotEmpty) {
      return (mines: cached, cached: true);
    }
    try {
      final response = await _client
          .get(
            Uri.parse(sourceDataUrl),
            headers: const {
              'User-Agent':
                  'WorkyDay public-data importer (infrequent local refresh)',
              'Accept': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        throw StateError(
          'NSW Minerals Council mine map returned HTTP ${response.statusCode}.',
        );
      }
      final mines = recordsFromJson(response.body);
      if (mines.isEmpty) {
        throw const FormatException(
          'NSW Minerals Council operating-mine map was empty.',
        );
      }
      await prefs.setString(
        _cacheKey,
        jsonEncode(mines.map((mine) => mine.toJson()).toList()),
      );
      await prefs.setString(_cacheTimeKey, DateTime.now().toIso8601String());
      return (mines: mines, cached: false);
    } catch (_) {
      if (cached.isNotEmpty) return (mines: cached, cached: true);
      rethrow;
    }
  }

  static List<NswMineralsCouncilMine> recordsFromJson(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! List) {
      throw const FormatException('Invalid NSW Minerals Council mine map.');
    }
    final mines = <NswMineralsCouncilMine>[];
    for (final raw in decoded.whereType<Map>()) {
      final row = Map<String, dynamic>.from(raw);
      final status = _htmlText(row['status']).trim();
      if (status.toLowerCase() != 'operating') continue;
      final id = (row['id'] ?? '').toString().trim();
      final name = _htmlText(row['store']).trim();
      final operatorName = _htmlText(row['subtitle']).trim();
      final latitude = _asDouble(row['lat']);
      final longitude = _asDouble(row['lng']);
      if (id.isEmpty ||
          name.isEmpty ||
          operatorName.isEmpty ||
          latitude == null ||
          longitude == null) {
        continue;
      }
      mines.add(
        NswMineralsCouncilMine(
          id: id,
          name: name,
          operatorName: operatorName,
          latitude: latitude,
          longitude: longitude,
          status: status,
          address: _htmlText(row['address']).trim(),
          postcode: (row['zip'] ?? '').toString().trim().isNotEmpty
              ? (row['zip'] ?? '').toString().trim()
              : _postcodeFromAddress(_htmlText(row['address'])),
          commodity: _htmlText(row['type']).trim(),
          projectUrl: (row['url'] ?? '').toString().trim(),
        ),
      );
    }
    return mines;
  }

  static List<Map<String, dynamic>> buildCorroboratedRows(
    List<NswMineralsCouncilMine> mines,
    List<Map<String, dynamic>> existing,
  ) {
    final officialWorksitesByName = <String, List<Map<String, dynamic>>>{};
    final contactsByCompanyId = <String, Map<String, dynamic>>{};
    for (final row in existing) {
      final companyId = (row['company_id'] ?? '').toString().trim();
      if (companyId.isNotEmpty && _contactScore(row) > 0) {
        final previous = contactsByCompanyId[companyId];
        if (previous == null || _contactScore(row) > _contactScore(previous)) {
          contactsByCompanyId[companyId] = row;
        }
      }
      if ((row['state'] ?? '').toString().toUpperCase() != 'NSW' ||
          (row['source'] ?? '').toString() != 'nsw_major_operating_mines') {
        continue;
      }
      final name = (row['worksite_name'] ?? row['name'] ?? '').toString();
      for (final alias in _mineAliases(name)) {
        officialWorksitesByName.putIfAbsent(alias, () => []).add(row);
      }
    }

    final rows = <Map<String, dynamic>>[];
    for (final mine in mines) {
      final matchingWorksites = <Map<String, dynamic>>{};
      for (final alias in _mineAliases(mine.name)) {
        matchingWorksites.addAll(officialWorksitesByName[alias] ?? const []);
      }
      final official = matchingWorksites.length == 1
          ? matchingWorksites.single
          : null;
      for (final operator in _operatorNames(mine.operatorName)) {
        final key = ConstructionDomainRecords.normalizeIdentity(operator);
        if (key.isEmpty) continue;
        final companyId = 'company:name:$key';
        final previous = contactsByCompanyId[companyId];
        final sourceId = 'nsw_minerals_council_mine:${mine.id}:$key';
        final worksiteId = official == null
            ? 'worksite:nsw_minerals_council_map:${mine.id}'
            : (official['worksite_id'] ?? '').toString();
        final row = <String, dynamic>{
          'id': 'nsw_minerals_council_mine_${mine.id}_$key',
          'docId': 'nsw_minerals_council_mine_${mine.id}_$key',
          'source_place_id': sourceId,
          'source': 'nsw_minerals_council_operator_link',
          'name': operator,
          'worksite_name': mine.name,
          'worksite_id': worksiteId,
          'state': 'NSW',
          'latitude': official?['latitude'] ?? mine.latitude,
          'longitude': official?['longitude'] ?? mine.longitude,
          'address': mine.address,
          'postcode': official?['postcode'] ?? mine.postcode,
          'postcode_display': official?['postcode_display'] ?? mine.postcode,
          'commodities': official?['commodities'] ?? mine.commodity,
          'worksite_stage': 'Operating',
          'company_id': companyId,
          'company_worksite_role': 'operator',
          'relationship_role': 'current_operator',
          'link_corroborated': true,
          'company_worksite_evidence': official == null
              ? 'NSW Minerals Council public mine map company-to-operating-mine listing'
              : 'NSW Minerals Council company-to-mine listing matched to the official NSW operating-mine worksite',
          if (mine.projectUrl.isNotEmpty) 'source_project_url': mine.projectUrl,
          'construction_category': 'mining_company',
          'entity_kind': 'employer',
          'classification_confidence': official == null ? 90 : 96,
          'classification_reason':
              'Industry mine map explicitly identifies the current operator of an operating NSW mine',
          'classification_source': 'open_data_corroboration',
          'review_status': 'ready_for_contact_enrichment',
          'catalog_sources': <String>[
            'nsw_minerals_council_mine_map',
            if (official != null) 'nsw_major_operating_mines',
          ],
          'source_url': sourcePageUrl,
          'source_attribution': 'NSW Minerals Council Map of NSW Mines',
          'location_role': 'worksite',
          'place_type': 'construction',
          'marker_kind': 'construction',
          'contact_enrichment_status':
              (previous?['contact_enrichment_status'] ?? 'pending').toString(),
        };
        _copyContacts(row, previous);
        rows.add(row);
      }
    }
    return rows;
  }

  static List<NswMineralsCouncilMine> _readCache(SharedPreferences prefs) {
    try {
      final decoded = jsonDecode(prefs.getString(_cacheKey) ?? '[]');
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map(
            (row) =>
                NswMineralsCouncilMine.fromJson(Map<String, dynamic>.from(row)),
          )
          .where(
            (mine) =>
                mine.id.isNotEmpty &&
                mine.name.isNotEmpty &&
                mine.operatorName.isNotEmpty,
          )
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  static Iterable<String> _operatorNames(String value) sync* {
    for (final part in value.split('/')) {
      final operator = part.trim();
      if (operator.isNotEmpty) yield operator;
    }
  }

  static Set<String> _mineAliases(String value) {
    final variants = <String>{value};
    variants.addAll(value.split(RegExp(r'\s*(?:/|&|\band\b|[–—])\s*')));
    return variants.map(_normalizeMineName).where((v) => v.isNotEmpty).toSet();
  }

  static String _normalizeMineName(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r"[’']"), '')
      .replaceAll(RegExp(r'\bmount\b'), 'mt')
      .replaceAll(
        RegExp(
          r'\b(underground|open\s*cut|open\s*pit|colliery|coal|mine|mines|operation|operations|complex|project|proposal|joint\s+venture)\b',
        ),
        ' ',
      )
      .replaceAll(RegExp(r'[^a-z0-9]+'), '')
      .trim();

  static String _htmlText(Object? value) => (value ?? '')
      .toString()
      .replaceAll('&#038;', '&')
      .replaceAll('&amp;', '&');

  static String _postcodeFromAddress(String address) =>
      RegExp(r'\b(2\d{3})\b').firstMatch(address)?.group(1) ?? '';

  static double? _asDouble(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse((value ?? '').toString());
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
      'company_identity_aliases',
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
