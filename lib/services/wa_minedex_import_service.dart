import 'dart:convert';

import 'package:flutter/services.dart';

import 'construction_publication_policy.dart';
import 'map_markers_service.dart';

class WaMinedexImportResult {
  const WaMinedexImportResult({
    required this.officialLinks,
    required this.added,
    required this.updated,
    required this.mapReady,
    required this.regionalMapReady,
  });

  final int officialLinks;
  final int added;
  final int updated;
  final int mapReady;
  final int regionalMapReady;
}

/// Imports the compact catalogue generated from official CC BY 4.0 MINEDEX
/// exports. This is local-only: it never contacts Firebase or a remote API.
class WaMinedexImportService {
  const WaMinedexImportService();

  static const assetPath = 'assets/open_data/wa_minedex/worksites.json';

  Future<WaMinedexImportResult> importLocal() async {
    final decoded = jsonDecode(await rootBundle.loadString(assetPath));
    if (decoded is! Map || decoded['records'] is! List) {
      throw const FormatException('Invalid WA MINEDEX catalogue asset.');
    }
    final records = (decoded['records'] as List)
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
    final existing = await MapMarkersService.loadConstructionCompanies(
      lightweight: false,
      syncFromFirebaseIfNeeded: false,
    );
    final existingBySourceId = <String, Map<String, dynamic>>{
      for (final row in existing)
        if ((row['source_place_id'] ?? '').toString().isNotEmpty)
          (row['source_place_id'] ?? '').toString(): row,
    };
    const preservedEnrichmentFields = <String>[
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
      'website_discovery_algorithm_version',
      'company_identity_aliases',
      'known_company_website',
      'known_company_website_evidence',
      'corporate_identity_evidence',
      'corporate_identity_checked_at',
      'historical_domain_evidence',
      'common_crawl_checked_at',
      'common_crawl_lookup_count',
      'application_contact_type',
      'application_contact_confidence',
      'application_contact_evidence',
      'contact_enrichment_status',
      'contact_enrichment_source',
      'contact_enrichment_error',
      'contact_enrichment_stage',
      'contact_enrichment_failure_kind',
    ];
    for (final record in records) {
      final previous =
          existingBySourceId[(record['source_place_id'] ?? '').toString()];
      if (previous == null) continue;
      for (final field in preservedEnrichmentFields) {
        final value = previous[field];
        if (value != null && value.toString().isNotEmpty) {
          record[field] = value;
        }
      }
    }
    final write = await MapMarkersService.upsertLocalConstructionCompanies(
      records,
    );
    final mapReady = records
        .where(ConstructionPublicationPolicy.canAppearOnMap)
        .length;
    final regionalMapReady = records.where((row) {
      return row['regional_work_eligible'] == true &&
          ConstructionPublicationPolicy.canAppearOnMap(row);
    }).length;
    return WaMinedexImportResult(
      officialLinks: records.length,
      added: write.added,
      updated: write.updated,
      mapReady: mapReady,
      regionalMapReady: regionalMapReady,
    );
  }
}
