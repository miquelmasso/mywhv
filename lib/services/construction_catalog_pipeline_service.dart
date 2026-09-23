import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/construction_category.dart';
import 'construction_publication_policy.dart';
import 'construction_pending_publish_service.dart';
import 'construction_sqlite_store.dart';
import 'construction_validation_catalog_service.dart';
import 'map_markers_service.dart';
import 'osm_construction_import_service.dart';
import 'visa_postcodes_sqlite_store.dart';
import 'wa_minedex_import_service.dart';

enum ConstructionPipelineStage {
  loadingSources,
  importingOfficialSources,
  enrichingOfficialContacts,
  scanningOsm,
  reconciling,
  complete,
}

class ConstructionPipelineProgress {
  const ConstructionPipelineProgress({
    required this.stage,
    required this.processed,
    required this.total,
    required this.message,
    this.postcode,
    this.companyName,
  });

  final ConstructionPipelineStage stage;
  final int processed;
  final int total;
  final String message;
  final String? postcode;
  final String? companyName;
}

class ConstructionPipelineResult {
  const ConstructionPipelineResult({
    required this.postcodesProcessed,
    required this.postcodesFailed,
    required this.osmDiscovered,
    required this.localCompanies,
    required this.validatedMatches,
    required this.mapEligible,
    required this.hiddenWithoutContact,
    required this.hiddenWithoutCoordinates,
    required this.unlinkedWorksites,
    required this.officialWorksitesImported,
    required this.officialContactsChecked,
    required this.officialContactsEnriched,
    required this.enrichmentCancelled,
    required this.enrichmentSkipped,
    required this.enrichmentRemaining,
    required this.enrichmentStatusCounts,
    required this.needsReview,
  });

  final int postcodesProcessed;
  final int postcodesFailed;
  final int osmDiscovered;
  final int localCompanies;
  final int validatedMatches;
  final int mapEligible;
  final int hiddenWithoutContact;
  final int hiddenWithoutCoordinates;
  final int unlinkedWorksites;
  final int officialWorksitesImported;
  final int officialContactsChecked;
  final int officialContactsEnriched;
  final bool enrichmentCancelled;
  final int enrichmentSkipped;
  final int enrichmentRemaining;
  final Map<String, int> enrichmentStatusCounts;
  final List<Map<String, dynamic>> needsReview;
}

typedef ConstructionPipelineProgressCallback =
    void Function(ConstructionPipelineProgress progress);

class ConstructionCatalogPipelineService {
  ConstructionCatalogPipelineService({OsmConstructionImportService? osm})
    : _osm = osm ?? OsmConstructionImportService();

  static const _snapshotAsset = 'export/construction_open_data_snapshot.json';

  final OsmConstructionImportService _osm;

  Future<ConstructionPipelineResult> runNational({
    bool forceOsm = false,
    bool includeOsmGapScan = false,
    bool enrichOfficialContacts = true,
    bool retryIncompleteEnrichment = false,
    bool forceEnrichment = false,
    ConstructionPipelineProgressCallback? onProgress,
    bool Function()? shouldCancel,
    ConstructionContactEnrichmentControl? enrichmentControl,
  }) async {
    onProgress?.call(
      const ConstructionPipelineProgress(
        stage: ConstructionPipelineStage.loadingSources,
        processed: 0,
        total: 0,
        message: 'Loading sanitized open-data snapshot',
      ),
    );
    final snapshot = await _loadSnapshot();
    onProgress?.call(
      const ConstructionPipelineProgress(
        stage: ConstructionPipelineStage.importingOfficialSources,
        processed: 0,
        total: 1,
        message: 'Importing verified official operator/worksite sources',
      ),
    );
    final waOfficial = await const WaMinedexImportService().importLocal();
    var officialContactsChecked = 0;
    var officialContactsEnriched = 0;
    var enrichmentCancelled = false;
    var enrichmentSkipped = 0;
    var enrichmentRemaining = 0;
    if (enrichOfficialContacts && shouldCancel?.call() != true) {
      onProgress?.call(
        const ConstructionPipelineProgress(
          stage: ConstructionPipelineStage.enrichingOfficialContacts,
          processed: 0,
          total: 25,
          message: 'Enriching a controlled batch from public company websites',
        ),
      );
      final enrichment = await _osm.enrichAllVerifiedOfficialCompanies(
        retryIncomplete: retryIncompleteEnrichment,
        force: forceEnrichment,
        shouldCancel: shouldCancel,
        control: enrichmentControl,
        onProgress: (progress) => onProgress?.call(
          ConstructionPipelineProgress(
            stage: ConstructionPipelineStage.enrichingOfficialContacts,
            processed: progress.companyIndex ?? 0,
            total: progress.companyTotal ?? 0,
            message: progress.message ?? progress.stage,
            companyName: progress.companyName,
          ),
        ),
      );
      officialContactsChecked = enrichment.checked;
      officialContactsEnriched = enrichment.enriched;
      enrichmentCancelled = enrichment.cancelled;
      enrichmentSkipped = enrichment.skipped;
      enrichmentRemaining = enrichment.remaining;
    }
    final postcodes = includeOsmGapScan && !enrichmentCancelled
        ? await _loadConfiguredNationalPostcodes()
        : const <String>[];
    var failed = 0;
    var discovered = 0;
    var processed = 0;

    for (var index = 0; index < postcodes.length; index++) {
      if (shouldCancel?.call() == true) break;
      final postcode = postcodes[index];
      onProgress?.call(
        ConstructionPipelineProgress(
          stage: ConstructionPipelineStage.scanningOsm,
          processed: index,
          total: postcodes.length,
          postcode: postcode,
          message: 'Scanning OSM and enriching public business contacts',
        ),
      );
      try {
        final result = await _osm.importForPostcode(
          postcode,
          force: forceOsm,
          enrichWebContacts: true,
          uploadChangedToFirebase: false,
        );
        discovered += result.discovered;
      } catch (_) {
        failed++;
      }
      processed++;
    }

    onProgress?.call(
      ConstructionPipelineProgress(
        stage: ConstructionPipelineStage.reconciling,
        processed: processed,
        total: postcodes.length,
        message: 'Reconciling OSM with ASIC and open-data evidence',
      ),
    );
    final result = await _reconcile(
      snapshot,
      postcodesProcessed: processed,
      postcodesFailed: failed,
      osmDiscovered: discovered,
      officialWorksitesImported: waOfficial.officialLinks,
      officialContactsChecked: officialContactsChecked,
      officialContactsEnriched: officialContactsEnriched,
      enrichmentCancelled: enrichmentCancelled,
      enrichmentSkipped: enrichmentSkipped,
      enrichmentRemaining: enrichmentRemaining,
    );
    onProgress?.call(
      ConstructionPipelineProgress(
        stage: ConstructionPipelineStage.complete,
        processed: processed,
        total: postcodes.length,
        message: 'Local construction catalogue complete',
      ),
    );
    return result;
  }

  Future<_OpenDataSnapshot> _loadSnapshot() async {
    final decoded = jsonDecode(await rootBundle.loadString(_snapshotAsset));
    if (decoded is! Map || decoded['companies'] is! List) {
      throw const FormatException('Invalid construction open-data snapshot.');
    }
    final companies = <String, Map<String, dynamic>>{};
    for (final raw in (decoded['companies'] as List).whereType<Map>()) {
      final company = Map<String, dynamic>.from(raw);
      final key = ConstructionValidationCatalogService.normalizeCompanyName(
        (company['name'] ?? '').toString(),
      );
      if (key.isNotEmpty) companies[key] = company;
    }
    final worksites = decoded['unlinked_worksites'] is List
        ? (decoded['unlinked_worksites'] as List).length
        : 0;
    return _OpenDataSnapshot(
      companies: companies,
      unlinkedWorksites: worksites,
    );
  }

  Future<List<String>> _loadConfiguredNationalPostcodes() async {
    final store = VisaPostcodesSqliteStore.instance;
    await store.init();
    await store.importSeedAssetIfEmpty();
    final postcodes = <String>{};
    for (final row in await store.getAll()) {
      final industry = (row['industry'] ?? row['id'] ?? '')
          .toString()
          .toLowerCase();
      if (!industry.contains('regional australia')) continue;
      final values = row['postcodes'];
      if (values is! List) continue;
      for (final value in values) {
        final postcode = value.toString().padLeft(4, '0');
        if (RegExp(r'^\d{4}$').hasMatch(postcode)) postcodes.add(postcode);
      }
    }
    return postcodes.toList()..sort();
  }

  Future<ConstructionPipelineResult> _reconcile(
    _OpenDataSnapshot snapshot, {
    required int postcodesProcessed,
    required int postcodesFailed,
    required int osmDiscovered,
    required int officialWorksitesImported,
    required int officialContactsChecked,
    required int officialContactsEnriched,
    required bool enrichmentCancelled,
    required int enrichmentSkipped,
    required int enrichmentRemaining,
  }) async {
    final store = ConstructionSqliteStore.instance;
    await store.init();
    final rows = await store.getAll();
    var validated = 0;
    var mapEligible = 0;
    var noContact = 0;
    var noCoordinates = 0;
    final enrichmentStatusCounts = <String, int>{};
    final needsReviewRows = <Map<String, dynamic>>[];

    for (final row in rows) {
      var classification = ConstructionCategory.classifyRowDetailed(row);
      final officialVerified =
          (row['classification_source'] ?? '').toString() ==
          'wa_minedex_official_join';
      if (officialVerified) {
        final status = (row['contact_enrichment_status'] ?? 'pending')
            .toString();
        enrichmentStatusCounts.update(
          status,
          (count) => count + 1,
          ifAbsent: () => 1,
        );
        final failureKind = (row['contact_enrichment_failure_kind'] ?? '')
            .toString();
        if (failureKind.isNotEmpty) {
          enrichmentStatusCounts.update(
            'failure_$failureKind',
            (count) => count + 1,
            ifAbsent: () => 1,
          );
        }
        if (status == 'needs_review') {
          needsReviewRows.add(Map<String, dynamic>.from(row));
        }
      }
      final key = ConstructionValidationCatalogService.normalizeCompanyName(
        (row['name'] ?? '').toString(),
      );
      final evidence = snapshot.companies[key];
      if (officialVerified) {
        validated++;
        row['company_validation_status'] = 'official_operator_worksite_link';
        row['map_eligible'] = ConstructionPublicationPolicy.canAppearOnMap(row);
      } else if (evidence != null) {
        validated++;
        row['company_validation_status'] = 'validated_active_company';
        row['company_validation_source'] = 'asic_companies';
        final sources = <String>{
          ...(row['catalog_sources'] is List
              ? (row['catalog_sources'] as List).map((e) => e.toString())
              : const <String>[]),
          (evidence['source_id'] ?? '').toString(),
          'asic_companies',
          'osm',
        }..removeWhere((source) => source.isEmpty);
        row['catalog_sources'] = sources.toList()..sort();
        final categories = evidence['construction_categories'];
        if (classification.entityKind !=
                ConstructionEntityKind.supplierRetail &&
            classification.entityKind != ConstructionEntityKind.projectSite &&
            categories is List &&
            categories.isNotEmpty) {
          final category = ConstructionCategory.fromId(categories.first);
          row['construction_category'] = category.id;
          row['construction_category_label'] = category.label;
          row['entity_kind'] = 'employer';
          row['classification_confidence'] = 90;
          row['classification_reason'] =
              'company and category corroborated by open-data sources';
          row['classification_source'] = 'open_data_corroboration';
          row['review_status'] = 'ready_for_map';
        }
      } else {
        row['company_validation_status'] = 'osm_only_needs_review';
        row['company_validation_source'] = 'osm';
        row['catalog_sources'] = const ['osm'];
        row['construction_category'] = classification.category.id;
        row['construction_category_label'] = classification.category.label;
        row['entity_kind'] = classification.entityKindId;
        row['classification_confidence'] = classification.confidence;
        row['classification_reason'] = classification.reason;
        row['classification_source'] = 'osm_tags';
        row['review_status'] =
            classification.isEmployer && classification.confidence >= 70
            ? 'ready_for_map'
            : 'needs_review';
      }

      final hasContact = ConstructionPublicationPolicy.hasPublicContact(row);
      final hasCoordinates = ConstructionPublicationPolicy.hasMapCoordinates(
        row,
      );
      final mapReady = ConstructionPublicationPolicy.canAppearOnMap(row);
      row['map_eligible'] = mapReady;
      if (!hasContact) {
        noContact++;
      } else if (!hasCoordinates) {
        noCoordinates++;
      } else if (mapReady) {
        mapEligible++;
      }
    }
    await MapMarkersService.replaceLocalConstructionCompanies(rows);
    await ConstructionPendingPublishService.instance.markPending(
      rows
          .where(ConstructionPublicationPolicy.canAppearOnMap)
          .map((row) => (row['docId'] ?? row['id'] ?? '').toString()),
    );
    return ConstructionPipelineResult(
      postcodesProcessed: postcodesProcessed,
      postcodesFailed: postcodesFailed,
      osmDiscovered: osmDiscovered,
      localCompanies: rows.length,
      validatedMatches: validated,
      mapEligible: mapEligible,
      hiddenWithoutContact: noContact,
      hiddenWithoutCoordinates: noCoordinates,
      unlinkedWorksites: snapshot.unlinkedWorksites,
      officialWorksitesImported: officialWorksitesImported,
      officialContactsChecked: officialContactsChecked,
      officialContactsEnriched: officialContactsEnriched,
      enrichmentCancelled: enrichmentCancelled,
      enrichmentSkipped: enrichmentSkipped,
      enrichmentRemaining: enrichmentRemaining,
      enrichmentStatusCounts: enrichmentStatusCounts,
      needsReview: needsReviewRows,
    );
  }
}

class _OpenDataSnapshot {
  const _OpenDataSnapshot({
    required this.companies,
    required this.unlinkedWorksites,
  });

  final Map<String, Map<String, dynamic>> companies;
  final int unlinkedWorksites;
}
