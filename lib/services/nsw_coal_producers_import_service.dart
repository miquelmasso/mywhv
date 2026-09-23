import 'dart:convert';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/construction_domain_records.dart';
import 'map_markers_service.dart';

class NswCoalProducerEntry {
  const NswCoalProducerEntry({
    required this.producerName,
    required this.mineName,
    this.operatorName = '',
    this.website = '',
    this.contactUrl = '',
    this.phone = '',
    this.email = '',
  });

  final String producerName;
  final String mineName;
  final String operatorName;
  final String website;
  final String contactUrl;
  final String phone;
  final String email;

  Map<String, dynamic> toJson() => {
    'producer_name': producerName,
    'mine_name': mineName,
    'operator_name': operatorName,
    'website': website,
    'contact_url': contactUrl,
    'phone': phone,
    'email': email,
  };

  factory NswCoalProducerEntry.fromJson(Map<String, dynamic> json) {
    return NswCoalProducerEntry(
      producerName: (json['producer_name'] ?? '').toString(),
      mineName: (json['mine_name'] ?? '').toString(),
      operatorName: (json['operator_name'] ?? '').toString(),
      website: (json['website'] ?? '').toString(),
      contactUrl: (json['contact_url'] ?? '').toString(),
      phone: (json['phone'] ?? '').toString(),
      email: (json['email'] ?? '').toString(),
    );
  }
}

class NswCoalProducersImportResult {
  const NswCoalProducersImportResult({
    required this.directoryMines,
    required this.linkedWorksites,
    required this.unmatchedWorksites,
    required this.added,
    required this.updated,
    required this.usedCachedDirectory,
  });

  final int directoryMines;
  final int linkedWorksites;
  final int unmatchedWorksites;
  final int added;
  final int updated;
  final bool usedCachedDirectory;
}

/// Corroborates NSW coal-mine employers from the public Coal Services
/// producers directory. Parsed results are cached for 30 days so enrichment
/// runs do not repeatedly request the source page.
class NswCoalProducersImportService {
  NswCoalProducersImportService({http.Client? client})
    : _client = client ?? http.Client();

  static const directoryUrl =
      'https://www.coalservices.com.au/statistics/'
      'nsw-black-coal-producers-directory/';
  static const _cacheKey = 'nsw_coal_producers_directory_v1';
  static const _cacheTimeKey = 'nsw_coal_producers_directory_checked_at_v1';
  static const _cacheDuration = Duration(days: 30);

  final http.Client _client;

  Future<NswCoalProducersImportResult> importLocal({
    bool forceRefresh = false,
  }) async {
    final directory = await _loadDirectory(forceRefresh: forceRefresh);
    final existing = await MapMarkersService.loadConstructionCompanies(
      lightweight: false,
      syncFromFirebaseIfNeeded: false,
    );
    final nswWorksites = existing
        .where((row) {
          return (row['state'] ?? '').toString().toUpperCase() == 'NSW' &&
              (row['source'] ?? '').toString() == 'nsw_major_operating_mines';
        })
        .toList(growable: false);
    final rows = buildCorroboratedRows(directory.entries, nswWorksites);
    final existingBySourceId = <String, Map<String, dynamic>>{
      for (final row in existing)
        if ((row['source_place_id'] ?? '').toString().isNotEmpty)
          (row['source_place_id'] ?? '').toString(): row,
    };
    const preservedContactFields = <String>[
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
    for (final row in rows) {
      final previous =
          existingBySourceId[(row['source_place_id'] ?? '').toString()];
      if (previous == null) continue;
      for (final field in preservedContactFields) {
        final value = previous[field];
        if (field == 'website' && !_isValidPublicWebsite(value?.toString())) {
          continue;
        }
        if (value != null && value.toString().isNotEmpty) row[field] = value;
      }
    }
    final write = await MapMarkersService.upsertLocalConstructionCompanies(
      rows,
    );
    return NswCoalProducersImportResult(
      directoryMines: directory.entries.length,
      linkedWorksites: rows.length,
      unmatchedWorksites: nswWorksites.length - rows.length,
      added: write.added,
      updated: write.updated,
      usedCachedDirectory: directory.cached,
    );
  }

  Future<({List<NswCoalProducerEntry> entries, bool cached})> _loadDirectory({
    required bool forceRefresh,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final cached = _readCache(prefs);
    final checkedAt = DateTime.tryParse(prefs.getString(_cacheTimeKey) ?? '');
    final fresh =
        checkedAt != null &&
        DateTime.now().difference(checkedAt) < _cacheDuration;
    if (!forceRefresh && fresh && cached.isNotEmpty) {
      return (entries: cached, cached: true);
    }
    try {
      final response = await _client
          .get(
            Uri.parse(directoryUrl),
            headers: const {
              'User-Agent':
                  'WorkyDay public-data importer (infrequent local refresh)',
              'Accept': 'text/html,application/xhtml+xml',
            },
          )
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        throw StateError('Coal Services returned HTTP ${response.statusCode}.');
      }
      final parsed = parseDirectoryHtml(response.body);
      if (parsed.isEmpty) {
        throw const FormatException('Coal Services directory was empty.');
      }
      await prefs.setString(
        _cacheKey,
        jsonEncode(parsed.map((entry) => entry.toJson()).toList()),
      );
      await prefs.setString(_cacheTimeKey, DateTime.now().toIso8601String());
      return (entries: parsed, cached: false);
    } catch (_) {
      if (cached.isNotEmpty) return (entries: cached, cached: true);
      rethrow;
    }
  }

  static List<NswCoalProducerEntry> _readCache(SharedPreferences prefs) {
    try {
      final decoded = jsonDecode(prefs.getString(_cacheKey) ?? '[]');
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map(
            (row) =>
                NswCoalProducerEntry.fromJson(Map<String, dynamic>.from(row)),
          )
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  static List<NswCoalProducerEntry> parseDirectoryHtml(String source) {
    final document = html_parser.parse(source);
    final entries = <NswCoalProducerEntry>[];
    for (final item in document.querySelectorAll('.accordion__item')) {
      final producer =
          item.querySelector('.accordion__label')?.text.trim() ?? '';
      final body = item.querySelector('.accordion__body');
      if (producer.isEmpty || body == null) continue;
      final paragraphs = body.querySelectorAll('p');
      if (paragraphs.length < 2) continue;
      final companyWebsite = _firstWebUrl(paragraphs.first);
      final companyPhone = _firstPhone(paragraphs.first);
      for (final paragraph in paragraphs.skip(1)) {
        final lines = _paragraphLines(paragraph);
        if (lines.isEmpty) continue;
        var mineName = lines.first;
        var operatorName = producer;
        if (_looksLikeCompany(lines.first) && lines.length > 1) {
          operatorName = lines.first;
          mineName = lines[1];
        }
        mineName = mineName.trim();
        if (mineName.isEmpty) continue;
        entries.add(
          NswCoalProducerEntry(
            producerName: producer,
            operatorName: operatorName,
            mineName: mineName,
            website: companyWebsite,
            contactUrl: _firstWebUrl(paragraph),
            phone: _firstPhone(paragraph).isNotEmpty
                ? _firstPhone(paragraph)
                : companyPhone,
            email: _firstEmail(paragraph),
          ),
        );
      }
    }
    return entries;
  }

  static List<Map<String, dynamic>> buildCorroboratedRows(
    List<NswCoalProducerEntry> entries,
    List<Map<String, dynamic>> worksites,
  ) {
    final candidatesByAlias = <String, List<NswCoalProducerEntry>>{};
    for (final entry in entries) {
      for (final alias in _mineAliases(entry.mineName)) {
        candidatesByAlias.putIfAbsent(alias, () => []).add(entry);
      }
    }
    final rows = <Map<String, dynamic>>[];
    for (final worksite in worksites) {
      final worksiteName = (worksite['worksite_name'] ?? worksite['name'] ?? '')
          .toString();
      final aliases = _mineAliases(worksiteName);
      final matches = <NswCoalProducerEntry>{};
      for (final alias in aliases) {
        matches.addAll(candidatesByAlias[alias] ?? const []);
      }
      if (matches.length != 1) continue;
      final match = matches.single;
      final operatorName = match.operatorName.trim().isNotEmpty
          ? match.operatorName.trim()
          : match.producerName.trim();
      final companyKey = ConstructionDomainRecords.normalizeIdentity(
        operatorName,
      );
      final worksiteId = (worksite['worksite_id'] ?? '').toString().trim();
      final occurrenceId = (worksite['source_place_id'] ?? '')
          .toString()
          .split(':')
          .last;
      if (companyKey.isEmpty || worksiteId.isEmpty || occurrenceId.isEmpty) {
        continue;
      }
      final id = 'nsw_coal_services_${occurrenceId}_$companyKey';
      rows.add({
        'id': id,
        'docId': id,
        'source_place_id': 'coal_services:$occurrenceId:$companyKey',
        'source': 'nsw_coal_services_operator_link',
        'name': operatorName,
        'trading_name': match.producerName,
        'worksite_name': worksiteName,
        'worksite_id': worksiteId,
        'state': 'NSW',
        'latitude': worksite['latitude'],
        'longitude': worksite['longitude'],
        'postcode': worksite['postcode'] ?? '',
        'postcode_display': worksite['postcode_display'] ?? '',
        'commodities': worksite['commodities'] ?? 'COAL',
        'worksite_stage': worksite['worksite_stage'] ?? 'Operating',
        'company_id': 'company:name:$companyKey',
        'company_worksite_role': 'operator',
        'relationship_role': 'current_operator',
        'link_corroborated': true,
        'company_worksite_evidence':
            'Coal Services NSW Black Coal Producers Directory mine-to-producer listing',
        'website': match.website,
        if (match.contactUrl.isNotEmpty) 'source_contact_url': match.contactUrl,
        if (match.phone.isNotEmpty) 'phone': match.phone,
        if (match.email.isNotEmpty) 'email': match.email,
        'construction_category': 'mining_company',
        'entity_kind': 'employer',
        'classification_confidence': 95,
        'classification_reason':
            'NSW operating mine matched uniquely to its listed coal producer',
        'classification_source': 'nsw_coal_services_official_join',
        'review_status': 'ready_for_contact_enrichment',
        'catalog_sources': const [
          'nsw_major_operating_mines',
          'nsw_coal_services_producers_directory',
        ],
        'source_url': directoryUrl,
        'source_attribution':
            'Coal Services NSW Black Coal Producers Directory',
        'location_role': 'worksite',
        'place_type': 'construction',
        'marker_kind': 'construction',
        'contact_enrichment_status': 'pending',
      });
    }
    return rows;
  }

  static List<String> _paragraphLines(Element paragraph) {
    return paragraph.innerHtml
        .split(RegExp(r'<br\s*/?>', caseSensitive: false))
        .map((part) => html_parser.parseFragment(part).text?.trim() ?? '')
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
  }

  static String _firstWebUrl(Element element) {
    for (final anchor in element.querySelectorAll('a[href]')) {
      final href = anchor.attributes['href']?.trim() ?? '';
      if (href.startsWith('http://') || href.startsWith('https://')) {
        final uri = Uri.tryParse(href);
        final host = uri?.host.toLowerCase() ?? '';
        if (host.contains('.') && RegExp(r'[a-z]').hasMatch(host)) return href;
      }
    }
    return '';
  }

  static bool _isValidPublicWebsite(String? value) {
    final uri = Uri.tryParse((value ?? '').trim());
    final host = uri?.host.toLowerCase() ?? '';
    return (uri?.scheme == 'http' || uri?.scheme == 'https') &&
        host.contains('.') &&
        RegExp(r'[a-z]').hasMatch(host);
  }

  static String _firstEmail(Element element) {
    for (final anchor in element.querySelectorAll('a[href]')) {
      final href = anchor.attributes['href']?.trim() ?? '';
      if (href.toLowerCase().startsWith('mailto:')) {
        return href.substring(7).split('?').first.trim();
      }
    }
    return '';
  }

  static String _firstPhone(Element element) {
    for (final anchor in element.querySelectorAll('a[href]')) {
      final href = anchor.attributes['href']?.trim() ?? '';
      if (href.toLowerCase().startsWith('tel:')) {
        return anchor.text.trim();
      }
    }
    return '';
  }

  static bool _looksLikeCompany(String value) => RegExp(
    r'\b(pty|limited|ltd|resources|holdings)\b',
    caseSensitive: false,
  ).hasMatch(value);

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
          r'\b(underground|open\s*cut|open\s*pit|colliery|collieries|coal|mine|mines|operation|operations|complex|project|proposal|joint\s+venture)\b',
        ),
        ' ',
      )
      .replaceAll(RegExp(r'[^a-z0-9]+'), '')
      .trim();
}
