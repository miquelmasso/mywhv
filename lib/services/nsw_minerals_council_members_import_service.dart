import 'dart:convert';

import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/construction_domain_records.dart';
import 'map_markers_service.dart';

class NswMineralsCouncilMember {
  const NswMineralsCouncilMember({required this.name, this.website = ''});

  final String name;
  final String website;

  Map<String, dynamic> toJson() => {'name': name, 'website': website};

  factory NswMineralsCouncilMember.fromJson(Map<String, dynamic> json) =>
      NswMineralsCouncilMember(
        name: (json['name'] ?? '').toString(),
        website: (json['website'] ?? '').toString(),
      );
}

class NswMineralsCouncilMembersImportResult {
  const NswMineralsCouncilMembersImportResult({
    required this.members,
    required this.added,
    required this.updated,
    required this.usedCache,
  });

  final int members;
  final int added;
  final int updated;
  final bool usedCache;
}

/// Imports only full NSW Minerals Council members as local employer-discovery
/// records. Associate members are deliberately excluded because that section
/// also contains advisers, universities and other non-employers.
///
/// Membership corroborates a company identity and its linked official website;
/// it does not corroborate an operator-to-worksite relationship. Consequently
/// these rows remain off the public map until a separate source supplies one.
class NswMineralsCouncilMembersImportService {
  NswMineralsCouncilMembersImportService({http.Client? client})
    : _client = client ?? http.Client();

  static const sourceUrl = 'https://nswmining.com.au/who-we-are/our-members/';
  static const _cacheKey = 'nsw_minerals_council_full_members_v1';
  static const _cacheTimeKey =
      'nsw_minerals_council_full_members_checked_at_v1';
  static const _cacheDuration = Duration(days: 30);

  final http.Client _client;

  Future<NswMineralsCouncilMembersImportResult> importLocal({
    bool forceRefresh = false,
  }) async {
    final loaded = await _loadMembers(forceRefresh: forceRefresh);
    final existing = await MapMarkersService.loadConstructionCompanies(
      lightweight: false,
      syncFromFirebaseIfNeeded: false,
    );
    final existingBySourceId = <String, Map<String, dynamic>>{
      for (final row in existing)
        if ((row['source_place_id'] ?? '').toString().isNotEmpty)
          (row['source_place_id'] ?? '').toString(): row,
    };
    final rows = <Map<String, dynamic>>[];
    for (final member in loaded.members) {
      final key = ConstructionDomainRecords.normalizeIdentity(member.name);
      if (key.isEmpty) continue;
      final sourceId = 'nsw_minerals_council:member:$key';
      final previous = existingBySourceId[sourceId];
      final website = _validWebsite(member.website)
          ? member.website
          : (previous?['website'] ?? '').toString();
      final row = <String, dynamic>{
        'id': 'nsw_minerals_council_member_$key',
        'docId': 'nsw_minerals_council_member_$key',
        'source_place_id': sourceId,
        'source': 'nsw_minerals_council_full_member',
        'name': member.name,
        'company_id': 'company:name:$key',
        'state': 'NSW',
        'website': website,
        'construction_category': 'mining_company',
        'entity_kind': 'employer',
        'classification_confidence': 90,
        'classification_reason':
            'Current full member of the NSW Minerals Council',
        'classification_source': 'open_data_corroboration',
        'company_identity_evidence':
            'NSW Minerals Council full-member directory',
        'review_status': 'ready_for_contact_enrichment',
        'catalog_sources': const ['nsw_minerals_council_full_members'],
        'source_url': sourceUrl,
        'source_attribution': 'NSW Minerals Council full-member directory',
        'location_role': 'company',
        'place_type': 'construction',
        'marker_kind': 'construction',
        'contact_enrichment_status':
            (previous?['contact_enrichment_status'] ?? 'pending').toString(),
      };
      _preserveExistingEnrichment(row, previous);
      rows.add(row);
    }
    final write = await MapMarkersService.upsertLocalConstructionCompanies(
      rows,
    );
    return NswMineralsCouncilMembersImportResult(
      members: rows.length,
      added: write.added,
      updated: write.updated,
      usedCache: loaded.cached,
    );
  }

  Future<({List<NswMineralsCouncilMember> members, bool cached})> _loadMembers({
    required bool forceRefresh,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final cached = _readCache(prefs);
    final checkedAt = DateTime.tryParse(prefs.getString(_cacheTimeKey) ?? '');
    final fresh =
        checkedAt != null &&
        DateTime.now().difference(checkedAt) < _cacheDuration;
    if (!forceRefresh && fresh && cached.isNotEmpty) {
      return (members: cached, cached: true);
    }
    try {
      final response = await _client
          .get(
            Uri.parse(sourceUrl),
            headers: const {
              'User-Agent':
                  'WorkyDay public-data importer (infrequent local refresh)',
              'Accept': 'text/html,application/xhtml+xml',
            },
          )
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        throw StateError(
          'NSW Minerals Council returned HTTP ${response.statusCode}.',
        );
      }
      final parsed = parseMembersHtml(response.body);
      if (parsed.isEmpty) {
        throw const FormatException(
          'NSW Minerals Council full-member directory was empty.',
        );
      }
      await prefs.setString(
        _cacheKey,
        jsonEncode(parsed.map((member) => member.toJson()).toList()),
      );
      await prefs.setString(_cacheTimeKey, DateTime.now().toIso8601String());
      return (members: parsed, cached: false);
    } catch (_) {
      if (cached.isNotEmpty) return (members: cached, cached: true);
      rethrow;
    }
  }

  static List<NswMineralsCouncilMember> parseMembersHtml(String source) {
    final document = html_parser.parse(source);
    final fullMembers = document.querySelector('#section1');
    if (fullMembers == null) return const [];
    final byIdentity = <String, NswMineralsCouncilMember>{};
    for (final card in fullMembers.querySelectorAll('.logo-h')) {
      final name = card.querySelector('.text')?.text.trim() ?? '';
      final key = ConstructionDomainRecords.normalizeIdentity(name);
      if (key.isEmpty) continue;
      var website = '';
      if (card.localName == 'a') {
        final href = card.attributes['href']?.trim() ?? '';
        if (_validWebsite(href)) website = href;
      }
      byIdentity[key] = NswMineralsCouncilMember(name: name, website: website);
    }
    return byIdentity.values.toList(growable: false);
  }

  static List<NswMineralsCouncilMember> _readCache(SharedPreferences prefs) {
    try {
      final decoded = jsonDecode(prefs.getString(_cacheKey) ?? '[]');
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map(
            (row) => NswMineralsCouncilMember.fromJson(
              Map<String, dynamic>.from(row),
            ),
          )
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  static bool _validWebsite(String value) {
    final uri = Uri.tryParse(value.trim());
    return (uri?.scheme == 'http' || uri?.scheme == 'https') &&
        (uri?.host.contains('.') ?? false);
  }

  static void _preserveExistingEnrichment(
    Map<String, dynamic> target,
    Map<String, dynamic>? previous,
  ) {
    if (previous == null) return;
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
      final value = previous[field];
      if (value != null && value.toString().isNotEmpty) target[field] = value;
    }
  }
}
