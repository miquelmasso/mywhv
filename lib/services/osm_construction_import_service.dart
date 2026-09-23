import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/osm_import_config.dart';
import '../models/construction_category.dart';
import 'careers_extractor.dart';
import 'construction_application_contact_classifier.dart';
import 'construction_company_identity_matcher.dart';
import 'construction_email_domain_verifier.dart';
import 'construction_sqlite_store.dart';
import 'construction_publication_policy.dart';
import 'construction_validation_catalog_service.dart';
import 'contact_html_fetcher.dart';
import 'email_extractor.dart';
import 'facebook_extractor.dart';
import 'instagram_extractor.dart';
import 'map_markers_service.dart';
import 'postcode_state_helper.dart';

class OsmConstructionImportResult {
  const OsmConstructionImportResult({
    required this.postcode,
    required this.discovered,
    required this.added,
    required this.updated,
    required this.total,
    required this.skippedByCooldown,
    this.skippedDuplicates = 0,
    this.enriched = 0,
    this.changedConstructionIds = const <String>[],
    this.summary = const OsmConstructionImportSummary.empty(),
    this.message,
  });

  final String postcode;
  final int discovered;
  final int added;
  final int updated;
  final int total;
  final bool skippedByCooldown;
  final int skippedDuplicates;
  final int enriched;
  final List<String> changedConstructionIds;
  final OsmConstructionImportSummary summary;
  final String? message;
}

class OsmConstructionImportSummary {
  const OsmConstructionImportSummary({
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
    required this.websiteFromProbableDomain,
    required this.emailContacts,
    required this.categoryCounts,
    required this.entityCounts,
  });

  const OsmConstructionImportSummary.empty()
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
      websiteFromProbableDomain = 0,
      emailContacts = const <OsmConstructionEmailContact>[],
      categoryCounts = const <String, int>{},
      entityCounts = const <String, int>{};

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
  final int websiteFromProbableDomain;
  final List<OsmConstructionEmailContact> emailContacts;
  final Map<String, int> categoryCounts;
  final Map<String, int> entityCounts;
}

class OsmConstructionEmailContact {
  const OsmConstructionEmailContact({required this.name, required this.email});

  final String name;
  final String email;
}

class ConstructionContactEnrichmentResult {
  const ConstructionContactEnrichmentResult({
    required this.checked,
    required this.enriched,
    required this.remaining,
  });

  final int checked;
  final int enriched;
  final int remaining;
}

class ConstructionContactEnrichmentQueueResult {
  const ConstructionContactEnrichmentQueueResult({
    required this.checked,
    required this.enriched,
    required this.remaining,
    required this.cancelled,
    required this.skipped,
  });

  final int checked;
  final int enriched;
  final int remaining;
  final bool cancelled;
  final int skipped;
}

class ConstructionContactEnrichmentControl {
  bool _stopRequested = false;
  Completer<_ConstructionEnrichmentAction>? _activeSignal;
  String? _activeEntityKey;
  final Set<String> _skippedEntityKeys = <String>{};
  final Set<String> _handledEntityKeys = <String>{};

  bool get stopRequested => _stopRequested;
  int get skippedCount => _skippedEntityKeys.length;
  Set<String> get excludedEntityKeys => Set.unmodifiable(_handledEntityKeys);

  bool skipCurrentCompany() {
    final signal = _activeSignal;
    final key = _activeEntityKey;
    if (signal == null || signal.isCompleted || key == null) return false;
    _skippedEntityKeys.add(key);
    signal.complete(_ConstructionEnrichmentAction.skip);
    return true;
  }

  void stopAndSave() {
    _stopRequested = true;
    final signal = _activeSignal;
    if (signal != null && !signal.isCompleted) {
      signal.complete(_ConstructionEnrichmentAction.stop);
    }
  }

  Future<_ConstructionEnrichmentAction> _activate(String entityKey) {
    _activeEntityKey = entityKey;
    final signal = Completer<_ConstructionEnrichmentAction>();
    _activeSignal = signal;
    if (_stopRequested) signal.complete(_ConstructionEnrichmentAction.stop);
    return signal.future;
  }

  void _finish(String entityKey) {
    if (_activeEntityKey != entityKey) return;
    _handledEntityKeys.add(entityKey);
    _activeEntityKey = null;
    _activeSignal = null;
  }

  void _beginTransientRetryPass() {
    _handledEntityKeys
      ..clear()
      ..addAll(_skippedEntityKeys);
  }
}

enum _ConstructionEnrichmentAction { completed, skip, stop }

class _ConstructionEnrichmentOutcome {
  const _ConstructionEnrichmentOutcome(this.action, {this.changed = false});

  final _ConstructionEnrichmentAction action;
  final bool changed;
}

typedef OsmConstructionImportProgressCallback =
    void Function(OsmConstructionImportProgress progress);

class OsmConstructionImportProgress {
  const OsmConstructionImportProgress({
    required this.postcode,
    required this.stage,
    this.companyName,
    this.companyIndex,
    this.companyTotal,
    this.message,
  });

  final String postcode;
  final String stage;
  final String? companyName;
  final int? companyIndex;
  final int? companyTotal;
  final String? message;
}

class OsmConstructionImportService {
  OsmConstructionImportService({
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

  static const _postcodeCenterCachePrefix = 'osm_postcode_center_v1_';
  static const _postcodeScanPrefix = 'osm_construction_scan_v1_';
  static const _constructionRadiusMeters = 12000;
  static const _overpassQueryTimeoutSeconds = 120;
  static DateTime? _lastOverpassRequestAt;
  static DateTime? _lastNominatimRequestAt;
  static const _knownConstructionBrandContacts = <String, Map<String, String>>{
    'bunningswarehouse': {
      'website': 'https://www.bunnings.com.au',
      'careers_page': 'https://www.bunnings.com.au/jobs',
      'email': 'jobs@bunnings.com.au',
    },
  };

  final http.Client _client;
  final EmailExtractor _emailExtractor;
  final CareersExtractor _careersExtractor;
  final FacebookExtractor _facebookExtractor;
  final InstagramExtractor _instagramExtractor;
  static const int _websiteDiscoveryAlgorithmVersion = 4;
  // v3 repeats the careers pass after fixing null-valued fields that made a
  // successfully discovered URL look as though a value was already stored.
  static const int _careersDiscoveryAlgorithmVersion = 3;
  static const int _websiteIdentityAlgorithmVersion = 3;
  static final Map<String, Future<bool>> _dnsResolutionCache = {};
  static Future<String?>? _commonCrawlCollection;

  /// Runs the same public-contact discovery used by Hospitality/OSM against
  /// companies already verified by an official source. It is intentionally
  /// bounded and local-only; callers decide if/when reviewed rows are later
  /// published.
  Future<ConstructionContactEnrichmentResult> enrichVerifiedOfficialCompanies({
    int limit = 25,
    String? state,
    OsmConstructionImportProgressCallback? onProgress,
    ConstructionContactEnrichmentControl? control,
    Set<String> excludedEntityKeys = const <String>{},
    bool includeAllCandidates = false,
    bool includeRetryLater = false,
  }) async {
    final allRows = await MapMarkersService.loadConstructionCompanies(
      lightweight: false,
      syncFromFirebaseIfNeeded: false,
    );
    final candidateGroups = <String, Map<String, dynamic>>{};
    for (final row in allRows.where(
      (row) => _needsVerifiedContactEnrichment(
        row,
        state: state,
        includeAll: includeAllCandidates,
        includeRetryLater: includeRetryLater,
      ),
    )) {
      final key = _contactEntityKey(row);
      if (excludedEntityKeys.contains(key)) continue;
      final current = candidateGroups[key];
      if (current == null ||
          _contactCompleteness(row) > _contactCompleteness(current)) {
        candidateGroups[key] = row;
      }
    }
    final candidates = candidateGroups.values.toList()
      ..sort((a, b) => _contactEntityKey(a).compareTo(_contactEntityKey(b)));
    final selected = candidates.take(limit.clamp(1, 100).toInt()).toList();
    if (selected.isEmpty) {
      return const ConstructionContactEnrichmentResult(
        checked: 0,
        enriched: 0,
        remaining: 0,
      );
    }
    for (final row in selected) {
      final entityKey = _contactEntityKey(row);
      final verifiedSiblings = allRows
          .where(
            (candidate) =>
                !identical(candidate, row) &&
                _sharesCompanyIdentity(candidate, row) &&
                (candidate['website'] ?? '').toString().trim().isNotEmpty &&
                _isVerifiedCompanyWebsite(candidate) &&
                ConstructionPublicationPolicy.hasReliableContactAssociation(
                  candidate,
                ),
          )
          .toList(growable: false);
      final verifiedHosts = verifiedSiblings
          .map(
            (candidate) => Uri.tryParse(
              (candidate['website'] ?? '').toString(),
            )?.host.toLowerCase().replaceFirst(RegExp(r'^www\.'), ''),
          )
          .whereType<String>()
          .where((host) => host.isNotEmpty)
          .toSet();
      final verifiedSibling = verifiedHosts.length == 1
          ? verifiedSiblings.first
          : null;
      if (verifiedSibling != null) {
        row['known_company_website'] = verifiedSibling['website'];
        row['known_company_website_evidence'] =
            'verified_other_location:${verifiedSibling['docId'] ?? verifiedSibling['id']}';
      } else if (verifiedHosts.length > 1) {
        row['website_discovery_source'] = 'multiple_plausible_domains';
        row['website_discovery_candidates'] = verifiedSiblings
            .map((candidate) => (candidate['website'] ?? '').toString())
            .where((website) => website.isNotEmpty)
            .toSet()
            .toList(growable: false);
      }
      row['company_identity_aliases'] = allRows
          .where((candidate) => _sharesCompanyIdentity(candidate, row))
          .expand(_companyIdentityAliases)
          .where((alias) => alias.trim().isNotEmpty)
          .toSet()
          .toList(growable: false);
    }
    final indexes = List<int>.generate(selected.length, (index) => index);
    final enriched = await _enrichImportedRows(
      selected,
      indexes,
      postcode: 'official',
      onProgress: onProgress,
      control: control,
    );
    const contactFields = <String>[
      'website',
      'phone',
      'email',
      'careers_page',
      'facebook_url',
      'instagram_url',
    ];
    const metadataFields = <String>[
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
      'contact_enrichment_status',
      'contact_enrichment_source',
      'contact_enrichment_error',
      'contact_enrichment_stage',
      'contact_enrichment_failure_kind',
      'contact_enrichment_timeout_stage',
      'contact_enrichment_timeout_stages',
      'contact_enrichment_homepage_verified',
      'careers_discovery_checked_at',
      'careers_discovery_algorithm_version',
      'website_identity_status',
      'website_identity_algorithm_version',
      'website_identity_evidence',
      'rejected_website_candidate',
      'rejected_careers_candidate',
      'rejected_email_candidate',
      'email_officially_published',
      'email_verification_status',
      'email_source_url',
      'email_public_eligible',
      'email_identity_status',
    ];
    final selectedByKey = <String, Map<String, dynamic>>{
      for (final row in selected) _contactEntityKey(row): row,
    };
    final affected = <Map<String, dynamic>>[...selected];
    for (final row in allRows) {
      final enrichedCompany = selectedByKey[_contactEntityKey(row)];
      if (enrichedCompany == null || identical(row, enrichedCompany)) continue;
      for (final field in contactFields) {
        row[field] = enrichedCompany[field] ?? '';
      }
      for (final field in metadataFields) {
        row[field] = enrichedCompany[field] ?? '';
      }
      affected.add(row);
    }
    await MapMarkersService.upsertLocalConstructionCompanies(affected);
    return ConstructionContactEnrichmentResult(
      checked: selected.length,
      enriched: enriched,
      remaining: candidates.length - selected.length,
    );
  }

  Future<ConstructionContactEnrichmentQueueResult>
  enrichAllVerifiedOfficialCompanies({
    bool retryIncomplete = false,
    bool force = false,
    String? state,
    OsmConstructionImportProgressCallback? onProgress,
    bool Function()? shouldCancel,
    ConstructionContactEnrichmentControl? control,
  }) async {
    final queueControl = control ?? ConstructionContactEnrichmentControl();

    var checked = 0;
    var enriched = 0;
    var remaining = 0;
    final initialRows = await MapMarkersService.loadConstructionCompanies(
      lightweight: false,
      syncFromFirebaseIfNeeded: false,
    );
    final totalCompanies = initialRows
        .where(
          (row) => _needsVerifiedContactEnrichment(
            row,
            state: state,
            includeAll: force,
            includeRetryLater: retryIncomplete || force,
          ),
        )
        .map(_contactEntityKey)
        .toSet()
        .length;
    // One press processes every company once, then makes two bounded passes
    // over transient timeout/network failures. Companies are still saved one
    // at a time so Skip, Stop and crash recovery remain immediate.
    final maximumPasses = retryIncomplete || force ? 3 : 1;
    for (
      var pass = 0;
      pass < maximumPasses &&
          !queueControl.stopRequested &&
          shouldCancel?.call() != true;
      pass++
    ) {
      if (pass > 0) queueControl._beginTransientRetryPass();
      while (!queueControl.stopRequested && shouldCancel?.call() != true) {
        final result = await enrichVerifiedOfficialCompanies(
          // A one-company checkpoint makes Skip/Stop immediate and ensures a
          // crash never loses a larger completed batch.
          limit: 1,
          state: state,
          control: queueControl,
          excludedEntityKeys: queueControl.excludedEntityKeys,
          includeAllCandidates: pass == 0 && force,
          includeRetryLater: retryIncomplete || force,
          onProgress: onProgress == null
              ? null
              : (progress) => onProgress(
                  OsmConstructionImportProgress(
                    postcode: 'official',
                    stage: progress.stage,
                    companyName: progress.companyName,
                    companyIndex: checked + (progress.companyIndex ?? 0),
                    companyTotal: totalCompanies,
                    message: pass == 0
                        ? progress.message
                        : '${progress.message} · automatic retry ${pass + 1}/$maximumPasses',
                  ),
                ),
        );
        checked += result.checked;
        enriched += result.enriched;
        remaining = result.remaining;
        if (result.checked == 0 || remaining == 0) break;
      }
      final passRows = await MapMarkersService.loadConstructionCompanies(
        lightweight: false,
        syncFromFirebaseIfNeeded: false,
      );
      final transientRemaining = passRows
          .where(
            (row) =>
                _isVerifiedEnrichmentCandidate(row, state: state) &&
                (row['contact_enrichment_status'] ?? '').toString() ==
                    'retry_later' &&
                !queueControl._skippedEntityKeys.contains(
                  _contactEntityKey(row),
                ),
          )
          .map(_contactEntityKey)
          .toSet();
      if (transientRemaining.isEmpty) break;
    }
    if (shouldCancel?.call() == true) queueControl.stopAndSave();
    final finalRows = await MapMarkersService.loadConstructionCompanies(
      lightweight: false,
      syncFromFirebaseIfNeeded: false,
    );
    remaining = finalRows
        .where(
          (row) => _needsVerifiedContactEnrichment(
            row,
            state: state,
            includeRetryLater: true,
          ),
        )
        .map(_contactEntityKey)
        .toSet()
        .length;
    return ConstructionContactEnrichmentQueueResult(
      checked: checked,
      enriched: enriched,
      remaining: remaining,
      cancelled: queueControl.stopRequested,
      skipped: queueControl.skippedCount,
    );
  }

  bool _needsVerifiedContactEnrichment(
    Map<String, dynamic> row, {
    String? state,
    bool includeAll = false,
    bool includeRetryLater = false,
  }) {
    if (!_isVerifiedEnrichmentCandidate(row, state: state)) return false;
    if (includeAll) return true;
    final status = (row['contact_enrichment_status'] ?? 'pending').toString();
    final discoveryVersion =
        int.tryParse(
          (row['website_discovery_algorithm_version'] ?? '').toString(),
        ) ??
        0;
    final careersVersion =
        int.tryParse(
          (row['careers_discovery_algorithm_version'] ?? '').toString(),
        ) ??
        0;
    final identityVersion =
        int.tryParse(
          (row['website_identity_algorithm_version'] ?? '').toString(),
        ) ??
        0;
    final needsWebsiteIdentityPass =
        (row['website'] ?? '').toString().trim().isNotEmpty &&
        identityVersion < _websiteIdentityAlgorithmVersion;
    final needsCurrentCareersPass =
        status == 'completed' &&
        (row['careers_page'] ?? '').toString().trim().isEmpty &&
        careersVersion < _careersDiscoveryAlgorithmVersion;
    return status == 'pending' ||
        needsWebsiteIdentityPass ||
        needsCurrentCareersPass ||
        ((status == 'no_verified_website' || status == 'identity_unresolved') &&
            discoveryVersion < _websiteDiscoveryAlgorithmVersion) ||
        (includeRetryLater && status == 'retry_later');
  }

  bool _isVerifiedEnrichmentCandidate(
    Map<String, dynamic> row, {
    String? state,
  }) {
    if (state != null &&
        state.isNotEmpty &&
        (row['state'] ?? '').toString().toUpperCase() != state.toUpperCase()) {
      return false;
    }
    return ConstructionPublicationPolicy.isRelevantEmployer(row);
  }

  bool _isMissingAnyEnrichmentField(Map<String, dynamic> row) {
    const fields = <String>[
      'website',
      'careers_page',
      'email',
      'phone',
      'facebook_url',
      'instagram_url',
    ];
    return fields.any((field) => (row[field] ?? '').toString().trim().isEmpty);
  }

  String _contactEntityKey(Map<String, dynamic> row) {
    final companyId = (row['company_id'] ?? '').toString().trim();
    if (companyId.isNotEmpty) return companyId;
    final operatorCode = (row['operator_code'] ?? '').toString().trim();
    if (operatorCode.isNotEmpty) return 'operator:$operatorCode';
    final normalizedName =
        ConstructionValidationCatalogService.normalizeCompanyName(
          (row['name'] ?? '').toString(),
        );
    return normalizedName.isNotEmpty
        ? 'name:$normalizedName'
        : 'id:${row['docId'] ?? row['id'] ?? row['source_place_id']}';
  }

  Iterable<String> _companyIdentityAliases(Map<String, dynamic> row) sync* {
    for (final key in const [
      'name',
      'trading_name',
      'parent_company_name',
      'subsidiary_name',
      'osm_brand',
      'osm_operator',
      'osm_company',
    ]) {
      final value = (row[key] ?? '').toString().trim();
      if (value.isNotEmpty) yield value;
    }
    for (final key in const ['operator_names', 'company_identity_aliases']) {
      final values = row[key];
      if (values is List) {
        yield* values
            .map((value) => value.toString().trim())
            .where((value) => value.isNotEmpty);
      }
    }
  }

  bool _sharesCompanyIdentity(
    Map<String, dynamic> first,
    Map<String, dynamic> second,
  ) {
    if (_contactEntityKey(first) == _contactEntityKey(second)) return true;
    final firstAliases = _companyIdentityAliases(first)
        .map(ConstructionValidationCatalogService.normalizeCompanyName)
        .where((value) => value.length >= 5)
        .toSet();
    final secondAliases = _companyIdentityAliases(second)
        .map(ConstructionValidationCatalogService.normalizeCompanyName)
        .where((value) => value.length >= 5)
        .toSet();
    return firstAliases.intersection(secondAliases).isNotEmpty;
  }

  int _contactCompleteness(Map<String, dynamic> row) {
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

  bool _isOfficialVerifiedRow(Map<String, dynamic> row) =>
      ConstructionPublicationPolicy.isVerifiedEnrichmentCandidate(row);

  Future<OsmConstructionImportResult> importForPostcode(
    String rawPostcode, {
    bool force = false,
    bool enrichWebContacts = OsmImportConfig.enrichWebContactsByDefault,
    bool uploadChangedToFirebase = true,
    OsmConstructionImportProgressCallback? onProgress,
  }) async {
    final postcode = rawPostcode.trim().padLeft(4, '0');
    if (!RegExp(r'^\d{4}$').hasMatch(postcode)) {
      throw ArgumentError.value(
        rawPostcode,
        'postcode',
        'Use a 4 digit postcode',
      );
    }

    final prefs = await SharedPreferences.getInstance();
    if (!force && _isScanCoolingDown(prefs, postcode)) {
      final rows = await MapMarkersService.loadConstructionCompanies();
      return OsmConstructionImportResult(
        postcode: postcode,
        discovered: 0,
        added: 0,
        updated: 0,
        total: rows.length,
        skippedByCooldown: true,
        message:
            'This postcode was already scanned recently. Use force import to scan again.',
      );
    }

    onProgress?.call(
      OsmConstructionImportProgress(
        postcode: postcode,
        stage: 'locating_postcode',
        message: 'Finding postcode area',
      ),
    );
    final area = await _resolvePostcodeCenter(postcode, prefs);
    if (area == null) {
      return OsmConstructionImportResult(
        postcode: postcode,
        discovered: 0,
        added: 0,
        updated: 0,
        total: (await MapMarkersService.loadConstructionCompanies()).length,
        skippedByCooldown: false,
        message: 'Could not find this postcode in OpenStreetMap.',
      );
    }

    onProgress?.call(
      OsmConstructionImportProgress(
        postcode: postcode,
        stage: 'querying_osm',
        message: 'Finding construction places in OSM',
      ),
    );
    final elements = await _queryOverpass(area);
    final candidates = elements
        .map(
          (element) => _normalizeElement(element, requestedPostcode: postcode),
        )
        .whereType<Map<String, dynamic>>()
        .take(OsmImportConfig.maxResultsPerPostcode)
        .toList(growable: false);

    final store = ConstructionSqliteStore.instance;
    await store.init();
    final existing = await MapMarkersService.loadConstructionCompanies();
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
      final candidateName = (candidate['name'] ?? '').toString();
      final evidence = await ConstructionValidationCatalogService.instance
          .findOpenDataEvidence(candidateName);
      final validated =
          evidence != null ||
          await ConstructionValidationCatalogService.instance
              .isValidatedCompanyName(candidateName);
      candidate['company_validation_status'] = validated
          ? 'validated_active_company'
          : 'osm_only_needs_review';
      candidate['company_validation_source'] = validated
          ? 'asic_companies'
          : 'osm';
      if (evidence != null &&
          candidate['entity_kind'] != 'supplier_retail' &&
          candidate['entity_kind'] != 'project_site') {
        final categories = evidence['construction_categories'];
        if (categories is List && categories.isNotEmpty) {
          final corroborated = ConstructionCategory.fromId(categories.first);
          candidate['construction_category'] = corroborated.id;
          candidate['construction_category_label'] = corroborated.label;
        }
        candidate['entity_kind'] = 'employer';
        candidate['classification_confidence'] = 90;
        candidate['classification_reason'] =
            'company and category corroborated by open-data sources';
        candidate['classification_source'] = 'open_data_corroboration';
        candidate['review_status'] = 'ready_for_map';
        candidate['catalog_sources'] = <String>[
          'osm',
          'asic_companies',
          if ((evidence['source_id'] ?? '').toString().isNotEmpty)
            evidence['source_id'].toString(),
        ];
      }
      final sourceId = candidate['source_place_id'].toString();
      final existingIndex = indexBySource[sourceId];
      if (existingIndex != null) {
        merged[existingIndex] = _mergeConstructionCompany(
          merged[existingIndex],
          candidate,
        );
        importedIndexes.add(existingIndex);
        updated++;
        continue;
      }

      final duplicateIndex = _findNearbyDuplicateIndex(merged, candidate);
      if (duplicateIndex != null) {
        merged[duplicateIndex] = _mergeConstructionCompany(
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
    final changedCompanies = uniqueImportedIndexes
        .where((index) => index >= 0 && index < merged.length)
        .map((index) => Map<String, dynamic>.from(merged[index]))
        .toList(growable: false);
    if (added > 0 || updated > 0 || enriched > 0) {
      await MapMarkersService.replaceLocalConstructionCompanies(merged);
      if (uploadChangedToFirebase) {
        await MapMarkersService.upsertConstructionCompaniesToFirebase(
          changedCompanies,
        );
      }
    }
    await prefs.setString(
      '$_postcodeScanPrefix$postcode',
      DateTime.now().toUtc().toIso8601String(),
    );

    return OsmConstructionImportResult(
      postcode: postcode,
      discovered: candidates.length,
      added: added,
      updated: updated,
      skippedDuplicates: skippedDuplicates,
      total: merged.length,
      enriched: enriched,
      changedConstructionIds: uniqueImportedIndexes
          .where((index) => index >= 0 && index < merged.length)
          .map((index) => (merged[index]['id'] ?? '').toString())
          .where((id) => id.trim().isNotEmpty)
          .toSet()
          .toList(growable: false),
      summary: summary,
      skippedByCooldown: false,
      message: candidates.isEmpty
          ? 'No construction places were found for this postcode.'
          : null,
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
    await _waitForPublicServiceSlot(
      lastRequestAt: _lastNominatimRequestAt,
      minimumGap: const Duration(
        milliseconds: OsmImportConfig.nominatimMinimumRequestGapMilliseconds,
      ),
    );
    _lastNominatimRequestAt = DateTime.now();
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
        : '(around:$_constructionRadiusMeters,${area.latitude},${area.longitude})';
    final query =
        '''
[out:json][timeout:$_overpassQueryTimeoutSeconds];
(
  nwr["craft"="builder"]$spatialFilter;
  nwr["craft"="carpenter"]$spatialFilter;
  nwr["craft"="electrician"]$spatialFilter;
  nwr["craft"="plumber"]$spatialFilter;
  nwr["craft"="roofer"]$spatialFilter;
  nwr["craft"="painter"]$spatialFilter;
  nwr["craft"="tiler"]$spatialFilter;
  nwr["craft"="stonemason"]$spatialFilter;
  nwr["craft"="joiner"]$spatialFilter;
  nwr["office"="architect"]$spatialFilter;
  nwr["office"="engineer"]$spatialFilter;
  nwr["office"="surveyor"]$spatialFilter;
  nwr["office"="construction"]$spatialFilter;
  nwr["industrial"="construction"]$spatialFilter;
  nwr["craft"="excavation"]$spatialFilter;
  nwr["craft"="drilling"]$spatialFilter;
  nwr["office"="telecommunication"]$spatialFilter;
  nwr["office"="employment_agency"]["name"~"(construction|mining|industrial|trades|labour|labor)",i]$spatialFilter;
  nwr["industrial"="mine"]$spatialFilter;
  nwr["industrial"="oil"]$spatialFilter;
  nwr["industrial"="gas"]$spatialFilter;
  nwr["landuse"="quarry"]$spatialFilter;
  nwr["man_made"="mineshaft"]$spatialFilter;
  nwr["power"="plant"]["plant:source"~"^(solar|wind)\$"]$spatialFilter;
  nwr["power"="generator"]["generator:source"~"^(solar|wind)\$"]$spatialFilter;
);
out tags center qt ${OsmImportConfig.maxResultsPerPostcode};
''';

    return _runOverpassQuery(query);
  }

  Future<List<Map<String, dynamic>>> _runOverpassQuery(String query) async {
    Object? lastError;
    for (
      var attempt = 0;
      attempt < OsmImportConfig.overpassMaximumAttempts;
      attempt++
    ) {
      final endpoint =
          OsmImportConfig.overpassEndpoints[attempt %
              OsmImportConfig.overpassEndpoints.length];
      try {
        await _waitForPublicServiceSlot(
          lastRequestAt: _lastOverpassRequestAt,
          minimumGap: const Duration(
            milliseconds: OsmImportConfig.overpassMinimumRequestGapMilliseconds,
          ),
        );
        _lastOverpassRequestAt = DateTime.now();
        final response = await _client
            .post(
              Uri.parse(endpoint),
              headers: {
                ..._requestHeaders(),
                'Content-Type': 'application/x-www-form-urlencoded',
              },
              body: {'data': query},
            )
            .timeout(const Duration(seconds: _overpassQueryTimeoutSeconds + 5));
        if (response.statusCode != 200) {
          lastError = StateError(
            'Overpass returned HTTP ${response.statusCode}.',
          );
          if (!_isRetryableOverpassStatus(response.statusCode)) break;
        } else {
          final decoded = jsonDecode(response.body);
          final elements = decoded is Map ? decoded['elements'] : null;
          if (elements is! List) return const [];
          return elements
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList(growable: false);
        }
      } catch (error) {
        lastError = error;
      }
      if (attempt + 1 < OsmImportConfig.overpassMaximumAttempts) {
        final backoffSeconds = math.min(12, 2 * (1 << attempt));
        final jitterMilliseconds = math.Random().nextInt(750);
        await Future<void>.delayed(
          Duration(seconds: backoffSeconds, milliseconds: jitterMilliseconds),
        );
      }
    }
    throw StateError('All Overpass endpoints failed: $lastError');
  }

  bool _isRetryableOverpassStatus(int statusCode) {
    return statusCode == 408 ||
        statusCode == 429 ||
        statusCode == 500 ||
        statusCode == 502 ||
        statusCode == 503 ||
        statusCode == 504;
  }

  Future<void> _waitForPublicServiceSlot({
    required DateTime? lastRequestAt,
    required Duration minimumGap,
  }) async {
    if (lastRequestAt == null) return;
    final remaining = minimumGap - DateTime.now().difference(lastRequestAt);
    if (remaining > Duration.zero) await Future<void>.delayed(remaining);
  }

  Map<String, dynamic>? _normalizeElement(
    Map<String, dynamic> element, {
    required String requestedPostcode,
  }) {
    final type = (element['type'] ?? '').toString();
    final osmId = (element['id'] ?? '').toString();
    final tags = element['tags'];
    if (type.isEmpty || osmId.isEmpty || tags is! Map) return null;

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

    final sourceId = 'osm:$type:$osmId';
    final osmUrl = 'https://www.openstreetmap.org/$type/$osmId';
    final website = _normalizeWebsiteUrl(
      _firstTag(tags, const [
        'website',
        'contact:website',
        'url',
        'contact:url',
        'official_website',
        'operator:website',
      ]),
    );
    final hasOsmWebsite = website.isNotEmpty;
    final phone = _firstTag(tags, const [
      'phone',
      'contact:phone',
      'mobile',
      'contact:mobile',
    ]);
    final classification = ConstructionCategory.classifyDetailed(
      tags: tags,
      name: name,
    );

    return {
      'id': 'osm_construction_${type}_$osmId',
      'docId': 'osm_construction_${type}_$osmId',
      'name': name,
      'address': _buildAddress(tags, requestedPostcode),
      'postcode': requestedPostcode,
      'postcode_display': requestedPostcode,
      'state': getStateFromPostcode(requestedPostcode),
      'latitude': lat,
      'longitude': lng,
      'phone': phone,
      'website': website,
      'email': _firstTag(tags, const ['email', 'contact:email']),
      'facebook_url': _normalizeSocialUrl(
        _firstTag(tags, const ['contact:facebook', 'facebook']),
        'facebook.com',
      ),
      'instagram_url': _normalizeSocialUrl(
        _firstTag(tags, const ['contact:instagram', 'instagram']),
        'instagram.com',
      ),
      'careers_page': '',
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
      'osm_brand': _firstTag(tags, const ['brand', 'operator']),
      'osm_description': (tags['description'] ?? '').toString(),
      'osm_operator': (tags['operator'] ?? '').toString(),
      'osm_company': (tags['company'] ?? '').toString(),
      'osm_service': _firstTag(tags, const ['service', 'services']),
      'osm_product': (tags['product'] ?? '').toString(),
      'osm_industry': (tags['industry'] ?? '').toString(),
      'website_discovery_source': hasOsmWebsite ? 'osm_tag' : '',
      'website_discovery_confidence': hasOsmWebsite ? 100 : 0,
      'website_discovery_checked_at': '',
      'website_checked_at': '',
      'contact_enrichment_error': '',
      'source': 'osm',
      'source_place_id': sourceId,
      'source_osm_id': osmId,
      'source_osm_type': type,
      'osm_url': osmUrl,
      'osm_office': (tags['office'] ?? '').toString(),
      'osm_craft': (tags['craft'] ?? '').toString(),
      'osm_shop': (tags['shop'] ?? '').toString(),
      'osm_industrial': (tags['industrial'] ?? '').toString(),
      'osm_landuse': (tags['landuse'] ?? '').toString(),
      'osm_man_made': (tags['man_made'] ?? '').toString(),
      'osm_power': (tags['power'] ?? '').toString(),
      'construction_category': classification.category.id,
      'construction_category_label': classification.category.label,
      'entity_kind': classification.entityKindId,
      'classification_confidence': classification.confidence,
      'classification_reason': classification.reason,
      'classification_source': 'osm_tags',
      'review_status':
          classification.isEmployer && classification.confidence >= 70
          ? 'ready_for_map'
          : 'needs_review',
      'employer_relevance_score': _categoryRelevanceScore(
        classification.category,
      ),
      'place_type': 'construction',
      'marker_kind': 'construction',
      'worked_here_count': 0,
      'blocked': false,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
    };
  }

  Future<int> _enrichImportedRows(
    List<Map<String, dynamic>> rows,
    List<int> indexes, {
    required String postcode,
    OsmConstructionImportProgressCallback? onProgress,
    ConstructionContactEnrichmentControl? control,
  }) async {
    if (indexes.isEmpty) return 0;

    var enriched = 0;
    final total = indexes.length;
    final concurrency = OsmImportConfig.constructionEnrichmentConcurrency.clamp(
      1,
      8,
    );
    for (var offset = 0; offset < indexes.length; offset += concurrency) {
      final chunk = indexes
          .skip(offset)
          .take(concurrency)
          .toList(growable: false);
      final results = await Future.wait(
        chunk.asMap().entries.map((entry) {
          final position = offset + entry.key + 1;
          final index = entry.value;
          final row = rows[index];
          final working = Map<String, dynamic>.from(row);
          final companyName = (row['name'] ?? '').toString();
          final entityKey = _contactEntityKey(row);
          final controlSignal = control?._activate(entityKey);
          onProgress?.call(
            OsmConstructionImportProgress(
              postcode: postcode,
              stage: 'enriching_construction_company',
              companyName: companyName,
              companyIndex: position,
              companyTotal: total,
              message: 'Searching contact data',
            ),
          );
          final enrichment = _enrichConstructionRowInBackground(working)
              .timeout(
                const Duration(
                  seconds: OsmImportConfig
                      .constructionContactEnrichmentTimeoutSeconds,
                ),
                onTimeout: () {
                  working['contact_enrichment_error'] = 'timeout';
                  final activeStage =
                      (working['contact_enrichment_stage'] ?? 'homepage')
                          .toString();
                  final timeoutStage = switch (activeStage) {
                    'contact_page' => 'contact_page',
                    'careers_page' => 'careers_page',
                    'social_extraction' => 'social_extraction',
                    _ => 'homepage',
                  };
                  _recordTimeoutStage(working, timeoutStage);
                  working['contact_enrichment_stage'] = 'timeout_$timeoutStage';
                  working['website_checked_at'] = DateTime.now()
                      .toUtc()
                      .toIso8601String();
                  return <String, dynamic>{'changed': false, 'row': working};
                },
              )
              .then((backgroundResult) {
                final backgroundRow = backgroundResult['row'];
                if (backgroundRow is Map) {
                  working
                    ..clear()
                    ..addAll(Map<String, dynamic>.from(backgroundRow));
                }
                return _ConstructionEnrichmentOutcome(
                  _ConstructionEnrichmentAction.completed,
                  changed: backgroundResult['changed'] == true,
                );
              });
          final outcome = control == null
              ? enrichment
              : Future.any<_ConstructionEnrichmentOutcome>([
                  enrichment,
                  controlSignal!.then(
                    (action) => _ConstructionEnrichmentOutcome(action),
                  ),
                ]);
          return outcome.then((result) {
            control?._finish(entityKey);
            if (result.action != _ConstructionEnrichmentAction.completed) {
              row['website_checked_at'] = '';
              row['contact_enrichment_status'] = 'pending';
              row['contact_enrichment_error'] = '';
              row['contact_enrichment_failure_kind'] = '';
              row['contact_enrichment_stage'] =
                  result.action == _ConstructionEnrichmentAction.skip
                  ? 'skipped_by_user'
                  : 'stopped_by_user';
              onProgress?.call(
                OsmConstructionImportProgress(
                  postcode: postcode,
                  stage: row['contact_enrichment_stage'].toString(),
                  companyName: companyName,
                  companyIndex: position,
                  companyTotal: total,
                  message: result.action == _ConstructionEnrichmentAction.skip
                      ? 'Company skipped; existing data preserved'
                      : 'Stopped; existing data preserved',
                ),
              );
              return false;
            }
            final changed = result.changed;
            working['website_checked_at'] =
                (working['website_checked_at'] ?? '').toString().isEmpty
                ? DateTime.now().toUtc().toIso8601String()
                : working['website_checked_at'];
            _assignContactEnrichmentStatus(working);
            ConstructionApplicationContactClassifier.applyDerivedFields(
              working,
            );
            row
              ..clear()
              ..addAll(working);
            onProgress?.call(
              OsmConstructionImportProgress(
                postcode: postcode,
                stage: changed
                    ? 'construction_company_enriched'
                    : 'construction_company_checked',
                companyName: companyName,
                companyIndex: position,
                companyTotal: total,
                message: changed ? 'New data found' : 'No new data found',
              ),
            );
            return changed;
          });
        }),
      );
      enriched += results.where((changed) => changed).length;
    }
    return enriched;
  }

  Future<Map<String, dynamic>> _enrichConstructionRowInBackground(
    Map<String, dynamic> source,
  ) => Isolate.run(() async {
    final isolatedRow = Map<String, dynamic>.from(source);
    final isolatedService = OsmConstructionImportService();
    var changed = await isolatedService._enrichImportedRow(isolatedRow);
    final verificationBefore = jsonEncode({
      'email_domain_status': isolatedRow['email_domain_status'],
      'email_public_eligible': isolatedRow['email_public_eligible'],
      'careers_public_eligible': isolatedRow['careers_public_eligible'],
    });
    await ConstructionEmailDomainVerifier().apply(isolatedRow);
    final verificationAfter = jsonEncode({
      'email_domain_status': isolatedRow['email_domain_status'],
      'email_public_eligible': isolatedRow['email_public_eligible'],
      'careers_public_eligible': isolatedRow['careers_public_eligible'],
    });
    changed = changed || verificationBefore != verificationAfter;
    return <String, dynamic>{'changed': changed, 'row': isolatedRow};
  });

  Future<bool> _enrichImportedRow(Map<String, dynamic> row) async {
    final before = _contactFingerprint(row);
    final name = (row['name'] ?? '').toString().trim();
    if (name.isEmpty) return false;
    // Every run gets a clean diagnostic state. A timeout from a previous run
    // must not keep classifying a successfully retried company as retry_later.
    row['contact_enrichment_error'] = '';
    row['contact_enrichment_failure_kind'] = '';
    row['contact_enrichment_timeout_stage'] = '';
    row['contact_enrichment_timeout_stages'] = <String>[];
    row['contact_enrichment_homepage_verified'] = false;
    row['contact_enrichment_stage'] = 'known_brand_lookup';
    _applyKnownConstructionBrandContacts(row);
    final address = (row['address'] ?? '').toString().trim();
    final postcode = (row['postcode'] ?? '').toString().trim();
    final locality = _extractLocality(address, postcode);

    var website = _normalizeWebsiteUrl((row['website'] ?? '').toString());
    var changed = false;
    if (website.isEmpty && OsmImportConfig.discoverMissingWebsitesByDefault) {
      row['contact_enrichment_stage'] = 'website_discovery';
      row['website_discovery_attempted'] = true;
      row['website_discovery_algorithm_version'] =
          _websiteDiscoveryAlgorithmVersion;
      row['website_discovery_checked_at'] = DateTime.now()
          .toUtc()
          .toIso8601String();
      final discovery = await _discoverWebsite(row, locality: locality);
      if (discovery != null) {
        row['website_discovery_source'] = discovery.source;
        row['website_discovery_confidence'] = discovery.confidence;
        row['website_discovery_candidates'] = discovery.candidates;
        if (discovery.url.isNotEmpty) {
          website = discovery.url;
          row['website'] = website;
          changed = true;
        }
      }
    }

    if (website.isEmpty || _isDirectoryWebsite(website)) {
      row['contact_enrichment_stage'] = 'identity_unresolved';
      _copySocialWebsiteToContact(row, website);
      final email = await _selectBestVerifiedEmail(
        row: row,
        existingEmail: (row['email'] ?? '').toString(),
        website: '',
        businessName: name,
        locationName: locality,
      );
      if (email.isNotEmpty && (row['email'] ?? '').toString().trim() != email) {
        if ((row['email'] ?? '').toString().trim().isEmpty) {
          row['email'] = email;
          changed = true;
        }
      }
      row['website_checked_at'] = DateTime.now().toUtc().toIso8601String();
      row['contact_enrichment_source'] = 'public_company_website';
      row['contact_enrichment_error'] = '';
      return changed || _contactFingerprint(row) != before;
    }

    final cleanedWebsite = _cleanBaseUrl(website);
    if (cleanedWebsite != website) {
      website = cleanedWebsite;
      row['website'] = website;
      changed = true;
    }

    try {
      row['contact_enrichment_stage'] = 'homepage';
      final homepageResult = await _fetchConstructionHomepage(
        website,
        timeout: const Duration(seconds: 10),
      );
      final homepage = homepageResult.html;
      if (homepage == null || homepage.isEmpty) {
        final failure = homepageResult.failure.isNotEmpty
            ? homepageResult.failure
            : (ContactHtmlFetcher.lastFailureReason(website) ?? '');
        row['contact_enrichment_error'] = failure;
        if (failure.contains('timeout')) {
          _recordTimeoutStage(row, 'homepage');
          row['contact_enrichment_stage'] = 'timeout_homepage';
        }
        row['website_checked_at'] = DateTime.now().toUtc().toIso8601String();
        return changed || _contactFingerprint(row) != before;
      }
      row['contact_enrichment_homepage_verified'] = true;

      if (!_websiteIdentityIsStrong(
        homepage,
        website,
        businessName: name,
        identityAliases: _websiteIdentityNames(row),
        officialEmail: (row['email'] ?? '').toString(),
        officialPhone: (row['phone'] ?? '').toString(),
        discoverySource: (row['website_discovery_source'] ?? '').toString(),
      )) {
        // Keep the original source values for audit/review, but quarantine
        // them from public contact fields so a similarly named unrelated
        // company can never donate its website or careers page.
        row['rejected_website_candidate'] = website;
        row['website_identity_status'] = 'rejected_mismatch';
        row['website_identity_algorithm_version'] =
            _websiteIdentityAlgorithmVersion;
        row['website_identity_evidence'] =
            'Homepage did not match the full company/trading identity or an official email/phone.';
        final existingCareers = (row['careers_page'] ?? '').toString().trim();
        if (existingCareers.isNotEmpty) {
          row['rejected_careers_candidate'] = existingCareers;
          row['careers_page'] = '';
          row['careers_verification_status'] = 'rejected_identity_mismatch';
          row['careers_public_eligible'] = false;
        }
        final rejectedHost =
            Uri.tryParse(
              website,
            )?.host.toLowerCase().replaceFirst(RegExp(r'^www\.'), '') ??
            '';
        final emailSourceHost =
            Uri.tryParse(
              (row['email_source_url'] ?? '').toString(),
            )?.host.toLowerCase().replaceFirst(RegExp(r'^www\.'), '') ??
            '';
        if (rejectedHost.isNotEmpty && emailSourceHost == rejectedHost) {
          final rejectedEmail = (row['email'] ?? '').toString().trim();
          if (rejectedEmail.isNotEmpty) {
            row['rejected_email_candidate'] = rejectedEmail;
          }
          row['email'] = '';
          row['email_officially_published'] = false;
          row['email_verification_status'] = 'rejected_identity_mismatch';
          row['email_public_eligible'] = false;
          row['email_identity_status'] = 'unverified_domain_mismatch';
        }
        row['website'] = '';
        // Make the next normal Build/update pass search for a replacement.
        // The rejected value remains in rejected_website_candidate and the
        // stronger matcher prevents it from being accepted again.
        row['website_discovery_algorithm_version'] = 0;
        row['contact_enrichment_homepage_verified'] = false;
        row['contact_enrichment_status'] = 'identity_unresolved';
        row['contact_enrichment_stage'] = 'identity_mismatch';
        row['website_checked_at'] = DateTime.now().toUtc().toIso8601String();

        // Repair in the same company job. A single guarded retry prevents a
        // bad pair of candidate domains from causing a discovery loop.
        final repairAttempts =
            int.tryParse(
              (row['website_identity_repair_attempts_this_run'] ?? '0')
                  .toString(),
            ) ??
            0;
        if (repairAttempts == 0) {
          row['website_identity_repair_attempts_this_run'] = 1;
          row['contact_enrichment_stage'] = 'website_replacement_discovery';
          final replacement = await _discoverWebsite(row, locality: locality);
          final replacementUrl = _cleanBaseUrl(replacement?.url ?? '');
          final rejectedHost = Uri.tryParse(website)?.host.toLowerCase() ?? '';
          final replacementHost =
              Uri.tryParse(replacementUrl)?.host.toLowerCase() ?? '';
          if (replacementUrl.isNotEmpty &&
              replacementHost.isNotEmpty &&
              replacementHost != rejectedHost) {
            row['website'] = replacementUrl;
            row['website_discovery_source'] = replacement!.source;
            row['website_discovery_confidence'] = replacement.confidence;
            row['website_discovery_candidates'] = replacement.candidates;
            return _enrichImportedRow(row);
          }
        }
        row.remove('website_identity_repair_attempts_this_run');
        return true;
      }
      row['website_identity_status'] = 'verified';
      row['website_identity_algorithm_version'] =
          _websiteIdentityAlgorithmVersion;
      row.remove('website_identity_repair_attempts_this_run');

      await _extractCorporateIdentityEvidence(
        row,
        website: website,
        homepage: homepage,
      );

      row['contact_enrichment_stage'] = 'contact_page';
      final contactValues = await _runOptionalConstructionStage<List<dynamic>>(
        row: row,
        website: website,
        stage: 'contact_page',
        timeout: const Duration(seconds: 35),
        fallback: const <dynamic>['', ''],
        operation: () => Future.wait<dynamic>([
          _selectBestVerifiedEmail(
            row: row,
            existingEmail: (row['email'] ?? '').toString(),
            website: website,
            businessName: name,
            locationName: locality,
          ),
          _extractPhoneFromWebsite(website),
        ]),
      );
      final email = (contactValues[0] ?? '').toString().trim();
      final phone = (contactValues[1] ?? '').toString().trim();

      if (email.isNotEmpty && (row['email'] ?? '').toString().trim() != email) {
        if ((row['email'] ?? '').toString().trim().isEmpty) {
          row['email'] = email;
          changed = true;
        }
      }
      if (phone.isNotEmpty && (row['phone'] ?? '').toString().trim() != phone) {
        if ((row['phone'] ?? '').toString().trim().isEmpty) {
          row['phone'] = phone;
          changed = true;
        }
      }

      row['contact_enrichment_stage'] = 'careers_page';
      row['careers_discovery_checked_at'] = DateTime.now()
          .toUtc()
          .toIso8601String();
      row['careers_discovery_algorithm_version'] =
          _careersDiscoveryAlgorithmVersion;
      final careers = await _runOptionalConstructionStage<String?>(
        row: row,
        website: website,
        stage: 'careers_page',
        timeout: const Duration(seconds: 45),
        fallback: null,
        operation: () =>
            _careersExtractor.findConstruction(website, homepageHtml: homepage),
      );
      if ((careers ?? '').trim().isNotEmpty &&
          (row['careers_page'] ?? '').toString().trim().isEmpty) {
        row['careers_page'] = careers!.trim();
        row['careers_verification_status'] = 'verified';
        row['careers_verified_at'] = DateTime.now().toUtc().toIso8601String();
        changed = true;
      }

      row['contact_enrichment_stage'] = 'social_extraction';
      final socialValues = await _runOptionalConstructionStage<List<dynamic>>(
        row: row,
        website: website,
        stage: 'social_extraction',
        timeout: const Duration(seconds: 30),
        fallback: const <dynamic>[null, null],
        operation: () => Future.wait<dynamic>([
          _facebookExtractor.find(
            baseUrl: website,
            businessName: name,
            address: address,
            phone: (row['phone'] ?? '').toString(),
          ),
          _instagramExtractor.find(baseUrl: website, businessName: name),
        ]),
      );
      final facebook = socialValues[0] as Map<String, dynamic>?;
      final instagram = socialValues[1] as Map<String, dynamic>?;
      final facebookLink = (facebook?['link'] ?? '').toString().trim();
      if (facebookLink.isNotEmpty &&
          (row['facebook_url'] ?? '').toString().trim().isEmpty) {
        row['facebook_url'] = facebookLink;
        changed = true;
      }
      final instagramLink = (instagram?['link'] ?? '').toString().trim();
      if (instagramLink.isNotEmpty &&
          (row['instagram_url'] ?? '').toString().trim().isEmpty) {
        row['instagram_url'] = instagramLink;
        changed = true;
      }

      row['website_checked_at'] = DateTime.now().toUtc().toIso8601String();
      row['contact_enrichment_source'] = 'public_company_website';
      row['contact_enrichment_error'] = '';
      row['contact_enrichment_stage'] = 'completed';
    } catch (error) {
      row['contact_enrichment_error'] = error.toString();
      row['contact_enrichment_stage'] = 'contact_extraction_failed';
    }

    return changed || _contactFingerprint(row) != before;
  }

  /// Corporate homepages sometimes deliver all useful HTML quickly and then
  /// keep a connection open for slow trailing analytics. Construction accepts
  /// a substantial partial document as a verified homepage instead of losing
  /// it to a whole-response timeout. This is deliberately not shared with the
  /// Hospitality importer.
  Future<({String? html, String failure})> _fetchConstructionHomepage(
    String website, {
    required Duration timeout,
  }) async {
    final uri = Uri.tryParse(website);
    if (uri == null || !uri.hasAuthority) {
      return (html: null, failure: 'invalid_url');
    }
    final client = HttpClient()
      ..connectionTimeout = timeout
      ..badCertificateCallback = (_, _, _) => true;
    final bytes = BytesBuilder(copy: false);
    final stopwatch = Stopwatch()..start();
    var timedOut = false;
    try {
      final request = await client.getUrl(uri).timeout(timeout);
      request.followRedirects = true;
      request.headers.set(
        HttpHeaders.userAgentHeader,
        'Mozilla/5.0 (compatible; WorkyDayConstructionImporter/1.0)',
      );
      request.headers.set(
        HttpHeaders.acceptHeader,
        'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      );
      final response = await request.close().timeout(timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return (
          html: null,
          failure: response.statusCode == 403
              ? 'http_403_blocked'
              : 'http_${response.statusCode}',
        );
      }
      const maximumBytes = 2 * 1024 * 1024;
      try {
        await for (final chunk in response.timeout(timeout)) {
          final remaining = maximumBytes - bytes.length;
          if (remaining <= 0) break;
          bytes.add(
            chunk.length <= remaining ? chunk : chunk.sublist(0, remaining),
          );
          if (bytes.length >= maximumBytes || stopwatch.elapsed >= timeout) {
            timedOut = stopwatch.elapsed >= timeout;
            break;
          }
        }
      } on TimeoutException {
        timedOut = true;
      }
      final collected = bytes.takeBytes();
      if (timedOut && collected.length < 512) {
        return (html: null, failure: 'timeout_retry_later');
      }
      if (collected.isEmpty) return (html: null, failure: 'empty_response');
      return (html: utf8.decode(collected, allowMalformed: true), failure: '');
    } on TimeoutException {
      return (html: null, failure: 'timeout_retry_later');
    } on SocketException catch (error) {
      return (html: null, failure: 'network_retry_later: ${error.message}');
    } catch (error) {
      return (html: null, failure: error.toString());
    } finally {
      client.close(force: true);
    }
  }

  Future<T> _runOptionalConstructionStage<T>({
    required Map<String, dynamic> row,
    required String website,
    required String stage,
    required Duration timeout,
    required T fallback,
    required Future<T> Function() operation,
  }) async {
    try {
      final result = await operation().timeout(
        timeout,
        onTimeout: () {
          _recordTimeoutStage(row, stage);
          return fallback;
        },
      );
      final failure = ContactHtmlFetcher.lastFailureReason(website) ?? '';
      if (failure.contains('timeout')) _recordTimeoutStage(row, stage);
      return result;
    } catch (error) {
      row['contact_enrichment_optional_error_$stage'] = error.toString();
      return fallback;
    }
  }

  void _recordTimeoutStage(Map<String, dynamic> row, String stage) {
    final existing = row['contact_enrichment_timeout_stages'];
    final stages = existing is List
        ? existing.map((value) => value.toString()).toSet()
        : <String>{};
    stages.add(stage);
    row['contact_enrichment_timeout_stage'] = stage;
    row['contact_enrichment_timeout_stages'] = stages.toList(growable: false);
  }

  void _assignContactEnrichmentStatus(Map<String, dynamic> row) {
    final website = (row['website'] ?? '').toString().trim();
    final fetchFailure = website.isEmpty
        ? ''
        : (ContactHtmlFetcher.lastFailureReason(website) ?? '');
    final error = '${row['contact_enrichment_error'] ?? ''} $fetchFailure'
        .toString()
        .toLowerCase();
    final homepageVerified =
        row['contact_enrichment_homepage_verified'] == true;
    if (homepageVerified) {
      row['contact_enrichment_status'] = 'completed';
      row['contact_enrichment_failure_kind'] = '';
      row['contact_enrichment_stage'] = 'completed';
      return;
    }
    if (error.contains('robots') || error.contains('403')) {
      row['contact_enrichment_status'] = 'blocked_by_website';
      row['contact_enrichment_failure_kind'] = '';
      return;
    }
    final failureKind = _contactEnrichmentFailureKind(error);
    if (failureKind.isNotEmpty) {
      row['contact_enrichment_status'] = 'retry_later';
      row['contact_enrichment_failure_kind'] = failureKind;
      return;
    }
    row['contact_enrichment_failure_kind'] = '';
    final source = (row['website_discovery_source'] ?? '').toString();
    if (source == 'multiple_plausible_domains') {
      row['contact_enrichment_status'] = 'needs_review';
      return;
    }
    if (website.isEmpty || _isDirectoryWebsite(website)) {
      row['contact_enrichment_status'] =
          row['no_public_website_confirmed'] == true
          ? 'no_public_website'
          : 'identity_unresolved';
      return;
    }
    final confidence =
        int.tryParse((row['website_discovery_confidence'] ?? '').toString()) ??
        0;
    if (source == 'probable_domain' && confidence < 80) {
      row['contact_enrichment_status'] = 'needs_review';
      return;
    }
    if (source == 'multiple_plausible_domains') {
      row['contact_enrichment_status'] = 'needs_review';
      return;
    }
    row['contact_enrichment_status'] = 'completed';
  }

  String _contactEnrichmentFailureKind(String error) {
    if (error.contains('timeout')) return 'timeout';
    if (error.contains('429')) return 'http_429';
    if (RegExp(r'(?:http_|http )5\d\d').hasMatch(error)) return 'http_5xx';
    if (error.contains('socket') ||
        error.contains('network') ||
        error.contains('dns') ||
        error.contains('host lookup') ||
        error.contains('failed host')) {
      return 'network_dns';
    }
    return '';
  }

  Future<void> _prefetchPriorityContactPages(String website) async {
    final urls = <String>{
      website,
      _combineUrl(website, 'contact'),
      _combineUrl(website, 'contact-us'),
      _combineUrl(website, 'about'),
      _combineUrl(website, 'about-us'),
      _combineUrl(website, 'services'),
      _combineUrl(website, 'projects'),
      _combineUrl(website, 'careers'),
      _combineUrl(website, 'jobs'),
    };
    await ContactHtmlFetcher.prefetchAll(
      urls,
      timeout: const Duration(seconds: 8),
    );
  }

  Future<String> _selectBestVerifiedEmail({
    required Map<String, dynamic> row,
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
    final extracted = website.isEmpty || _isDirectoryWebsite(website)
        ? null
        : await _emailExtractor.extractVerified(
            website,
            businessName: businessName,
            locationName: locationName,
          );

    final candidates = [?existing, ?extracted];
    if (candidates.isEmpty) return '';
    candidates.sort((a, b) => b.score.compareTo(a.score));
    final best = candidates.first;
    final publishedOnOfficialWebsite =
        extracted != null &&
        extracted.email.toLowerCase() == best.email.toLowerCase();
    if (publishedOnOfficialWebsite) {
      row['email_officially_published'] = true;
      row['email_verification_status'] = 'officially_published';
      row['email_source_url'] = extracted.origin;
      row['email_verification_score'] = extracted.score;
      row['email_verified_at'] = DateTime.now().toUtc().toIso8601String();
      final websiteHost = Uri.tryParse(
        website,
      )?.host.toLowerCase().replaceFirst(RegExp(r'^www\.'), '');
      final emailDomain = best.email.toLowerCase().substring(
        best.email.lastIndexOf('@') + 1,
      );
      if (websiteHost != null &&
          websiteHost.isNotEmpty &&
          websiteHost != emailDomain) {
        // Exact publication on the already verified official website is
        // direct evidence that its parent/ATS/related email domain belongs to
        // this company. The evidence URL is retained for later auditing.
        row['email_domain_relationship_corroborated'] = true;
        row['email_domain_relationship_evidence'] = extracted.origin;
      }
    } else if (row['email_officially_published'] != true) {
      row['email_officially_published'] = false;
      row['email_verification_status'] = 'source_only';
      row['email_source_url'] = (row['source'] ?? 'government_source')
          .toString();
    }
    return best.email;
  }

  Future<String> _extractPhoneFromWebsite(String website) async {
    final candidates = <String>{};
    for (final url in <String>{
      website,
      _combineUrl(website, 'contact'),
      _combineUrl(website, 'contact-us'),
      _combineUrl(website, 'about'),
      _combineUrl(website, 'about-us'),
      _combineUrl(website, 'services'),
    }) {
      final html = await ContactHtmlFetcher.fetch(
        url,
        timeout: const Duration(seconds: 8),
      );
      if (html == null || html.isEmpty) continue;
      candidates.addAll(_extractPhoneCandidates(html));
      if (candidates.isNotEmpty) break;
    }
    if (candidates.isEmpty) return '';
    return candidates.first;
  }

  Set<String> _extractPhoneCandidates(String html) {
    final normalized = html
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&#160;', ' ')
        .replaceAll(RegExp(r'<[^>]+>'), ' ');
    final found = <String>{};
    final pattern = RegExp(
      r'(?:(?:\+?61|0)\s?)(?:\(?[2378]\)?|\d{2})[\s.-]?\d{3,4}[\s.-]?\d{3,4}',
      caseSensitive: false,
    );
    for (final match in pattern.allMatches(normalized)) {
      final phone = _normalizeAustralianPhone(match.group(0) ?? '');
      if (phone.isNotEmpty) found.add(phone);
    }
    return found;
  }

  String _normalizeAustralianPhone(String raw) {
    var value = raw.replaceAll(RegExp(r'[^\d+]'), '');
    if (value.startsWith('+61')) {
      value = '0${value.substring(3)}';
    } else if (value.startsWith('61') && value.length >= 10) {
      value = '0${value.substring(2)}';
    }
    if (value.length < 10 || value.length > 11) return '';
    return value;
  }

  Future<_WebsiteDiscovery?> _discoverWebsite(
    Map<String, dynamic> row, {
    required String locality,
  }) async {
    final fromOfficialEmail = await _discoverWebsiteFromOfficialEmail(row);
    if (fromOfficialEmail != null) return fromOfficialEmail;
    final reused = _discoverReusedCompanyWebsite(row);
    if (reused != null) return reused;
    final wikidataId = _extractWikidataId(row);
    if (wikidataId.isNotEmpty) {
      final fromWikidata = await _discoverWebsiteFromWikidata(wikidataId);
      if (fromWikidata != null) return fromWikidata;
    }
    final fromWikidataSearch = await _discoverWebsiteFromWikidataSearch(row);
    if (fromWikidataSearch != null) return fromWikidataSearch;
    return _discoverProbableDomain(row, locality: locality);
  }

  _WebsiteDiscovery? _discoverReusedCompanyWebsite(Map<String, dynamic> row) {
    final website = _normalizeWebsiteUrl(
      (row['known_company_website'] ?? '').toString(),
    );
    if (website.isEmpty || _isDirectoryWebsite(website)) return null;
    return _WebsiteDiscovery(
      url: _cleanBaseUrl(website),
      source: 'verified_company_identity',
      confidence: 100,
      candidates: [website],
    );
  }

  Future<_WebsiteDiscovery?> _discoverWebsiteFromOfficialEmail(
    Map<String, dynamic> row,
  ) async {
    final candidates = <String>[];
    for (final domain in _corporateEmailDomains(row)) {
      candidates.add('https://$domain');
      candidates.add('https://www.$domain');
    }
    for (final candidate in candidates.toSet()) {
      final html = await ContactHtmlFetcher.fetch(
        candidate,
        timeout: const Duration(
          seconds: OsmImportConfig.websiteDiscoveryTimeoutSeconds,
        ),
      );
      if (html == null || html.isEmpty) continue;
      // MINEDEX identifies this email as the operator's public contact. Its
      // domain is therefore strong parent/trading-company evidence even when
      // the legal operator name is different from the website brand.
      return _WebsiteDiscovery(
        url: _cleanBaseUrl(candidate),
        source: 'official_email_domain',
        confidence: 95,
        candidates: [candidate],
      );
    }
    return null;
  }

  Set<String> _corporateEmailDomains(Map<String, dynamic> row) {
    final domains = <String>{};
    final emailPattern = RegExp(
      r'[A-Z0-9._%+\-]+@([A-Z0-9.\-]+\.[A-Z]{2,})',
      caseSensitive: false,
    );
    void collect(Object? value) {
      if (value is String) {
        for (final match in emailPattern.allMatches(value)) {
          final domain = (match.group(1) ?? '').toLowerCase().replaceFirst(
            RegExp(r'^www\.'),
            '',
          );
          if (domain.isNotEmpty && !_isGenericEmailDomain(domain)) {
            domains.add(domain);
          }
        }
      } else if (value is List) {
        for (final item in value) {
          collect(item);
        }
      }
    }

    for (final entry in row.entries) {
      if (entry.key == 'raw_json') continue;
      collect(entry.value);
    }
    return domains;
  }

  Future<_WebsiteDiscovery?> _discoverWebsiteFromWikidataSearch(
    Map<String, dynamic> row,
  ) async {
    final aliases = _companyIdentityAliases(row).toSet().take(4);
    final plausible = <_WebsiteDiscovery>[];
    final seenIds = <String>{};
    for (final alias in aliases) {
      final uri = Uri.https('www.wikidata.org', '/w/api.php', {
        'action': 'wbsearchentities',
        'search': alias,
        'language': 'en',
        'format': 'json',
        'limit': '3',
        'type': 'item',
      });
      try {
        final response = await _client
            .get(uri, headers: _requestHeaders())
            .timeout(const Duration(seconds: 8));
        if (response.statusCode != 200) continue;
        final decoded = jsonDecode(response.body);
        final results = decoded is Map ? decoded['search'] : null;
        if (results is! List) continue;
        for (final result in results.whereType<Map>()) {
          final id = (result['id'] ?? '').toString();
          if (!RegExp(r'^Q\d+$').hasMatch(id) || !seenIds.add(id)) continue;
          final candidate = await _discoverWebsiteFromWikidata(id);
          if (candidate == null) continue;
          final verified = await _validateProbableWebsite(
            candidate.url,
            businessName: (row['name'] ?? '').toString(),
            identityAliases: _websiteIdentityNames(row),
            locality: _extractLocality(
              (row['address'] ?? '').toString(),
              (row['postcode'] ?? '').toString(),
            ),
            officialEmail: (row['email'] ?? '').toString(),
            officialPhone: (row['phone'] ?? '').toString(),
          );
          if (verified != null) {
            plausible.add(
              _WebsiteDiscovery(
                url: verified.url,
                source: 'wikidata_name_search:$id',
                confidence: verified.confidence,
                candidates: [verified.url],
              ),
            );
          }
        }
      } catch (_) {
        continue;
      }
    }
    if (plausible.isEmpty) return null;
    plausible.sort((a, b) => b.confidence.compareTo(a.confidence));
    final best = plausible.first;
    final competing = plausible
        .skip(1)
        .where(
          (candidate) =>
              candidate.url != best.url &&
              best.confidence - candidate.confidence <= 10,
        )
        .toList(growable: false);
    if (competing.isNotEmpty) {
      return _WebsiteDiscovery(
        url: '',
        source: 'multiple_plausible_domains',
        confidence: best.confidence,
        candidates: [best.url, ...competing.map((item) => item.url)],
      );
    }
    return best;
  }

  Future<_WebsiteDiscovery?> _discoverWebsiteFromWikidata(
    String wikidataId,
  ) async {
    final uri = Uri.parse(
      'https://www.wikidata.org/wiki/Special:EntityData/$wikidataId.json',
    );
    try {
      final response = await _client
          .get(uri, headers: _requestHeaders())
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) return null;
      final entities = decoded['entities'];
      if (entities is! Map) return null;
      final entity = entities[wikidataId];
      if (entity is! Map) return null;
      final url = _extractWikidataStringClaim(entity, 'P856');
      final normalized = _normalizeWebsiteUrl(url);
      if (normalized.isEmpty || _isDirectoryWebsite(normalized)) return null;
      return _WebsiteDiscovery(
        url: _cleanBaseUrl(normalized),
        source: 'wikidata',
        confidence: 95,
        candidates: [normalized],
      );
    } catch (_) {
      return null;
    }
  }

  String _extractWikidataStringClaim(Map entity, String property) {
    final claims = entity['claims'];
    if (claims is! Map) return '';
    final values = claims[property];
    if (values is! List || values.isEmpty) return '';
    for (final claim in values) {
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

  Future<_WebsiteDiscovery?> _discoverProbableDomain(
    Map<String, dynamic> row, {
    required String locality,
  }) async {
    final name = (row['name'] ?? '').toString();
    final candidates = _probableDomainCandidates(row, locality)
        .take(OsmImportConfig.websiteDiscoveryMaxCandidatesPerBusiness)
        .toList(growable: false);
    final plausible = <_WebsiteDiscovery>[];
    for (final candidate in candidates) {
      final discovery = await _validateProbableWebsite(
        candidate,
        businessName: name,
        identityAliases: _websiteIdentityNames(row),
        locality: locality,
        officialEmail: (row['email'] ?? '').toString(),
        officialPhone: (row['phone'] ?? '').toString(),
      );
      if (discovery == null) continue;
      plausible.add(discovery);
    }
    if (plausible.isEmpty) {
      return _discoverFromCommonCrawl(
        row,
        candidates: candidates.take(2).toList(growable: false),
        locality: locality,
      );
    }
    plausible.sort((a, b) => b.confidence.compareTo(a.confidence));
    final best = plausible.first;
    final competing = plausible
        .skip(1)
        .where((candidate) => best.confidence - candidate.confidence <= 10)
        .toList(growable: false);
    if (competing.isNotEmpty) {
      return _WebsiteDiscovery(
        url: '',
        source: 'multiple_plausible_domains',
        confidence: best.confidence,
        candidates: [best.url, ...competing.map((candidate) => candidate.url)],
      );
    }
    return best;
  }

  Iterable<String> _probableDomainCandidates(
    Map<String, dynamic> row,
    String locality,
  ) {
    final name = (row['name'] ?? '').toString();
    final tokens = _meaningfulTokens(name);
    if (tokens.isEmpty) return const <String>[];
    final aliases = <String>{name};
    final identityAliases = row['company_identity_aliases'];
    if (identityAliases is List) {
      aliases.addAll(identityAliases.map((value) => value.toString()));
    }
    for (final key in const [
      'trading_name',
      'parent_company_name',
      'subsidiary_name',
      'osm_brand',
      'osm_operator',
    ]) {
      final alias = (row[key] ?? '').toString().trim();
      if (alias.isNotEmpty) aliases.add(alias);
    }
    final operatorNames = row['operator_names'];
    if (operatorNames is List) {
      aliases.addAll(operatorNames.map((value) => value.toString()));
    }
    final slugs = <String>{};
    for (final alias in aliases) {
      final aliasTokens = _meaningfulTokens(alias);
      if (aliasTokens.isEmpty) continue;
      slugs.add(aliasTokens.join());
      slugs.add(aliasTokens.join('-'));
      if (aliasTokens.length > 1) {
        slugs.add(aliasTokens.take(2).join());
        slugs.add(aliasTokens.take(2).join('-'));
        final acronym = aliasTokens.map((token) => token[0]).join();
        if (acronym.length >= 3) slugs.add(acronym);
      }
      if (aliasTokens.length > 2) slugs.add(aliasTokens.take(3).join());
    }
    final domains = <String>[];
    for (final slug in slugs.where((slug) => slug.length >= 3)) {
      domains.add('https://$slug.com.au');
      domains.add('https://$slug.au');
      domains.add('https://$slug.com');
    }
    return domains;
  }

  Future<_WebsiteDiscovery?> _validateProbableWebsite(
    String url, {
    required String businessName,
    Iterable<String> identityAliases = const <String>[],
    required String locality,
    required String officialEmail,
    required String officialPhone,
  }) async {
    try {
      if (!await _domainResolves(url)) return null;
      final html = await ContactHtmlFetcher.fetch(
        url,
        timeout: const Duration(
          seconds: OsmImportConfig.websiteDiscoveryTimeoutSeconds,
        ),
      );
      if (html == null || html.isEmpty) return null;
      final names = <String>{businessName, ...identityAliases}
        ..removeWhere((name) => name.trim().isEmpty);
      if (!_websiteIdentityIsStrong(
        html,
        url,
        businessName: businessName,
        identityAliases: names,
        officialEmail: officialEmail,
        officialPhone: officialPhone,
        discoverySource: 'probable_domain',
      )) {
        return null;
      }
      final score = names
          .map(
            (name) => _scoreWebsiteMatch(
              html,
              url,
              businessName: name,
              locality: locality,
              officialEmail: officialEmail,
              officialPhone: officialPhone,
            ),
          )
          .fold<int>(0, math.max);
      if (score < 65) return null;
      return _WebsiteDiscovery(
        url: _cleanBaseUrl(url),
        source: 'probable_domain',
        confidence: score.clamp(0, 100),
        candidates: [url],
      );
    } catch (_) {
      return null;
    }
  }

  Future<bool> _domainResolves(String url) {
    final host = Uri.tryParse(url)?.host.toLowerCase() ?? '';
    if (host.isEmpty) return Future.value(false);
    return _dnsResolutionCache.putIfAbsent(host, () async {
      try {
        return (await InternetAddress.lookup(
          host,
        ).timeout(const Duration(seconds: 3))).isNotEmpty;
      } catch (_) {
        return false;
      }
    });
  }

  Future<void> _extractCorporateIdentityEvidence(
    Map<String, dynamic> row, {
    required String website,
    required String homepage,
  }) async {
    final pages = <MapEntry<String, String>>[MapEntry(website, homepage)];
    for (final url in _identityPageUrls(website, homepage).take(3)) {
      try {
        final html = await ContactHtmlFetcher.fetch(
          url,
          timeout: const Duration(seconds: 6),
        );
        if ((html ?? '').isNotEmpty) pages.add(MapEntry(url, html!));
      } catch (_) {
        // Corporate identity pages are optional.
      }
    }
    final aliases = _companyIdentityAliases(row).toSet();
    final evidence = <Map<String, String>>[];
    for (final page in pages) {
      for (final alias in _structuredCorporateNames(page.value)) {
        if (_meaningfulTokens(alias).isEmpty) continue;
        aliases.add(alias);
        evidence.add({
          'kind': 'structured_company_name',
          'value': alias,
          'url': page.key,
        });
      }
      for (final domain in _structuredLinkedDomains(page.value)) {
        evidence.add({
          'kind': 'structured_linked_domain',
          'value': domain,
          'url': page.key,
        });
      }
    }
    row['company_identity_aliases'] = aliases.toList(growable: false);
    if (evidence.isNotEmpty) {
      row['corporate_identity_evidence'] = evidence;
      row['corporate_identity_checked_at'] = DateTime.now()
          .toUtc()
          .toIso8601String();
    }
  }

  Iterable<String> _identityPageUrls(String website, String homepage) sync* {
    final base = Uri.tryParse(website);
    if (base == null) return;
    final seen = <String>{};
    final hrefPattern = RegExp(
      r'''href\s*=\s*["']([^"'#]+)["']''',
      caseSensitive: false,
    );
    for (final match in hrefPattern.allMatches(homepage)) {
      final href = match.group(1) ?? '';
      if (!RegExp(
        r'(about|company|corporate|operations|projects|locations|acquisition)',
        caseSensitive: false,
      ).hasMatch(href)) {
        continue;
      }
      final resolved = base.resolve(href);
      if (resolved.host != base.host ||
          !const {'http', 'https'}.contains(resolved.scheme)) {
        continue;
      }
      final url = resolved.replace(fragment: '').toString();
      if (seen.add(url)) yield url;
    }
  }

  Set<String> _structuredCorporateNames(String html) {
    final names = <String>{};
    final fieldPattern = RegExp(
      r'''["'](?:legalName|alternateName)["']\s*:\s*["']([^"']{3,160})["']''',
      caseSensitive: false,
    );
    for (final match in fieldPattern.allMatches(html)) {
      final value = (match.group(1) ?? '').trim();
      if (value.isNotEmpty) names.add(value);
    }
    final relationshipPattern = RegExp(
      r'''["'](?:parentOrganization|subOrganization)["']\s*:\s*\{.{0,500}?["']name["']\s*:\s*["']([^"']{3,160})["']''',
      caseSensitive: false,
      dotAll: true,
    );
    for (final match in relationshipPattern.allMatches(html)) {
      final value = (match.group(1) ?? '').trim();
      if (value.isNotEmpty) names.add(value);
    }
    return names;
  }

  Set<String> _structuredLinkedDomains(String html) {
    final domains = <String>{};
    final sameAsBlock = RegExp(
      r'''["']sameAs["']\s*:\s*(\[[^\]]{0,2000}\]|["'][^"']+["'])''',
      caseSensitive: false,
      dotAll: true,
    );
    final urlPattern = RegExp(r'''https?://[^"'\s<>,]+''');
    for (final block in sameAsBlock.allMatches(html)) {
      for (final match in urlPattern.allMatches(block.group(1) ?? '')) {
        final host =
            Uri.tryParse(match.group(0) ?? '')?.host.toLowerCase() ?? '';
        if (host.isNotEmpty &&
            !host.contains('facebook.com') &&
            !host.contains('instagram.com') &&
            !host.contains('linkedin.com') &&
            !host.contains('youtube.com')) {
          domains.add(host.replaceFirst(RegExp(r'^www\.'), ''));
        }
      }
    }
    return domains;
  }

  Future<_WebsiteDiscovery?> _discoverFromCommonCrawl(
    Map<String, dynamic> row, {
    required List<String> candidates,
    required String locality,
  }) async {
    if (candidates.isEmpty) return null;
    final collection = await (_commonCrawlCollection ??=
        _loadLatestCommonCrawlCollection());
    if (collection == null) return null;
    for (final candidate in candidates) {
      final host = Uri.tryParse(candidate)?.host.toLowerCase() ?? '';
      if (host.isEmpty) continue;
      row['common_crawl_checked_at'] = DateTime.now().toUtc().toIso8601String();
      row['common_crawl_lookup_count'] =
          (int.tryParse((row['common_crawl_lookup_count'] ?? '0').toString()) ??
              0) +
          1;
      final capture = await _latestCommonCrawlCapture(collection, host);
      if (capture == null) continue;
      final archived = await _loadCommonCrawlCapture(capture);
      if (archived.isEmpty) continue;
      final historicalScore = _scoreWebsiteMatch(
        archived,
        candidate,
        businessName: (row['name'] ?? '').toString(),
        locality: locality,
        officialEmail: (row['email'] ?? '').toString(),
        officialPhone: (row['phone'] ?? '').toString(),
      );
      final historicalAliasScore = _websiteIdentityNames(row)
          .map(
            (name) => _scoreWebsiteMatch(
              archived,
              candidate,
              businessName: name,
              locality: locality,
              officialEmail: (row['email'] ?? '').toString(),
              officialPhone: (row['phone'] ?? '').toString(),
            ),
          )
          .fold<int>(historicalScore, math.max);
      if (historicalAliasScore < 65) continue;
      row['historical_domain_evidence'] = {
        'domain': host,
        'capture': capture['timestamp']?.toString() ?? '',
        'source': 'common_crawl',
      };
      for (final liveCandidate in _linkedWebsiteCandidates(
        archived,
        excludingHost: host,
      ).take(5)) {
        final verified = await _validateProbableWebsite(
          liveCandidate,
          businessName: (row['name'] ?? '').toString(),
          identityAliases: _websiteIdentityNames(row),
          locality: locality,
          officialEmail: (row['email'] ?? '').toString(),
          officialPhone: (row['phone'] ?? '').toString(),
        );
        if (verified == null) continue;
        return _WebsiteDiscovery(
          url: verified.url,
          source: 'common_crawl_historical_link',
          confidence: verified.confidence,
          candidates: [candidate, verified.url],
        );
      }
    }
    return null;
  }

  Future<String?> _loadLatestCommonCrawlCollection() async {
    try {
      final response = await _client
          .get(
            Uri.parse('https://index.commoncrawl.org/collinfo.json'),
            headers: _requestHeaders(),
          )
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(response.body);
      if (decoded is! List || decoded.isEmpty || decoded.first is! Map) {
        return null;
      }
      final id = ((decoded.first as Map)['id'] ?? '').toString();
      return id.isEmpty ? null : id;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> _latestCommonCrawlCapture(
    String collection,
    String host,
  ) async {
    try {
      final uri = Uri.https('index.commoncrawl.org', '/$collection-index', {
        'url': '$host/*',
        'output': 'json',
        'filter': 'status:200',
        'collapse': 'urlkey',
        'limit': '1',
      });
      final response = await _client
          .get(uri, headers: _requestHeaders())
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200 || response.body.trim().isEmpty) {
        return null;
      }
      final decoded = jsonDecode(response.body.trim().split('\n').first);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
    } catch (_) {
      return null;
    }
  }

  Future<String> _loadCommonCrawlCapture(Map<String, dynamic> capture) async {
    final filename = (capture['filename'] ?? '').toString();
    final offset = int.tryParse((capture['offset'] ?? '').toString());
    final length = int.tryParse((capture['length'] ?? '').toString());
    if (filename.isEmpty || offset == null || length == null || length <= 0) {
      return '';
    }
    try {
      final response = await _client
          .get(
            Uri.parse('https://data.commoncrawl.org/$filename'),
            headers: {
              ..._requestHeaders(),
              'Range': 'bytes=$offset-${offset + length - 1}',
            },
          )
          .timeout(const Duration(seconds: 12));
      if (response.statusCode != 200 && response.statusCode != 206) return '';
      final decoded = utf8.decode(
        gzip.decode(response.bodyBytes),
        allowMalformed: true,
      );
      final firstHeaders = decoded.indexOf('\r\n\r\n');
      if (firstHeaders < 0) return decoded;
      final httpHeaders = decoded.indexOf('\r\n\r\n', firstHeaders + 4);
      return httpHeaders < 0 ? decoded : decoded.substring(httpHeaders + 4);
    } catch (_) {
      return '';
    }
  }

  Iterable<String> _linkedWebsiteCandidates(
    String html, {
    required String excludingHost,
  }) sync* {
    final seen = <String>{};
    final pattern = RegExp(r'''https?://[^\s"'<>]+''', caseSensitive: false);
    final excluded = excludingHost.replaceFirst(RegExp(r'^www\.'), '');
    for (final match in pattern.allMatches(html)) {
      final uri = Uri.tryParse(match.group(0) ?? '');
      if (uri == null || uri.host.isEmpty) continue;
      final host = uri.host.toLowerCase().replaceFirst(RegExp(r'^www\.'), '');
      if (host == excluded ||
          _isDirectoryWebsite(uri.toString()) ||
          _isSocialWebsite(uri.toString()) ||
          host.contains('commoncrawl.org') ||
          host.contains('schema.org')) {
        continue;
      }
      final candidate = 'https://$host';
      if (seen.add(candidate)) yield candidate;
    }
  }

  int _scoreWebsiteMatch(
    String html,
    String url, {
    required String businessName,
    required String locality,
    String officialEmail = '',
    String officialPhone = '',
  }) {
    final content = '${_stripHtml(html)} $url'.toLowerCase();
    var score = 0;
    final tokens = _meaningfulTokens(businessName);
    var matchedTokens = 0;
    for (final token in tokens) {
      if (content.contains(token)) {
        score += 18;
        matchedTokens++;
      }
    }
    if (tokens.length >= 2 && matchedTokens == tokens.length) {
      score += 25;
    }
    final compactName = tokens.join();
    final host = Uri.tryParse(url)?.host.toLowerCase() ?? '';
    final compactHost = _domainSlug(host);
    if (compactName.length >= 4 && compactHost.contains(compactName)) {
      score += 35;
    }
    final emailDomain = _emailDomain(officialEmail);
    if (emailDomain.isNotEmpty &&
        !_isGenericEmailDomain(emailDomain) &&
        (host == emailDomain || host.endsWith('.$emailDomain'))) {
      score += 70;
    }
    final normalizedOfficialPhone = _normalizeAustralianPhone(officialPhone);
    if (normalizedOfficialPhone.isNotEmpty) {
      final pagePhones = _extractPhoneCandidates(content);
      if (pagePhones.contains(normalizedOfficialPhone)) score += 35;
    }
    final localityToken = _domainSlug(locality);
    if (localityToken.isNotEmpty && content.contains(localityToken)) score += 8;
    if (content.contains('construction') ||
        content.contains('builder') ||
        content.contains('building') ||
        content.contains('contractor') ||
        content.contains('carpentry') ||
        content.contains('carpenter') ||
        content.contains('electrician') ||
        content.contains('electrical') ||
        content.contains('plumber') ||
        content.contains('plumbing') ||
        content.contains('roofing') ||
        content.contains('roof') ||
        content.contains('painting') ||
        content.contains('painter') ||
        content.contains('tiling') ||
        content.contains('tiles') ||
        content.contains('architect') ||
        content.contains('engineering') ||
        content.contains('surveyor') ||
        content.contains('renovation') ||
        content.contains('concreting') ||
        content.contains('civil') ||
        content.contains('mining') ||
        content.contains('minerals') ||
        content.contains('resources') ||
        content.contains('drilling') ||
        content.contains('earthmoving') ||
        content.contains('excavating') ||
        content.contains('earthworks')) {
      score += 8;
    }
    if (content.contains('australia') || content.contains('.com.au')) {
      score += 5;
    }
    if (RegExp(
      r'"@type"\s*:\s*"(?:Organization|Corporation|LocalBusiness)"',
      caseSensitive: false,
    ).hasMatch(html)) {
      score += 20;
    }
    if (content.contains('about us') ||
        content.contains('our company') ||
        content.contains('corporate profile')) {
      score += 10;
    }
    return score;
  }

  bool _websiteIdentityIsStrong(
    String html,
    String url, {
    required String businessName,
    Iterable<String> identityAliases = const <String>[],
    String officialEmail = '',
    String officialPhone = '',
    String discoverySource = '',
  }) {
    return ConstructionCompanyIdentityMatcher.matchesWebsite(
      html: html,
      url: url,
      businessName: businessName,
      aliases: identityAliases,
    );
  }

  List<String> _websiteIdentityNames(Map<String, dynamic> row) {
    final names = _sourceIdentityAliases(row)
        .map((name) => name.trim())
        .where((name) => name.isNotEmpty)
        .toSet()
        .toList(growable: false);
    names.sort((first, second) {
      final firstTokens = _meaningfulTokens(first).length;
      final secondTokens = _meaningfulTokens(second).length;
      return secondTokens.compareTo(firstTokens);
    });
    return names.take(8).toList(growable: false);
  }

  Iterable<String> _sourceIdentityAliases(Map<String, dynamic> row) sync* {
    for (final key in const [
      'name',
      'trading_name',
      'parent_company_name',
      'subsidiary_name',
      'osm_brand',
      'osm_operator',
      'osm_company',
    ]) {
      final value = (row[key] ?? '').toString().trim();
      if (value.isNotEmpty) yield value;
    }
    final operatorNames = row['operator_names'];
    if (operatorNames is List) {
      yield* operatorNames
          .map((value) => value.toString().trim())
          .where((value) => value.isNotEmpty);
    }
  }

  bool _isVerifiedCompanyWebsite(Map<String, dynamic> row) {
    final source = (row['website_discovery_source'] ?? '').toString();
    final confidence =
        int.tryParse((row['website_discovery_confidence'] ?? '').toString()) ??
        0;
    return source == 'official_source' ||
        source == 'official_email_domain' ||
        source == 'verified_company_identity' ||
        (row['contact_enrichment_homepage_verified'] == true &&
            confidence >= 80);
  }

  String _stripHtml(String html) => html
      .replaceAll(RegExp(r'<script[^>]*>.*?</script>', dotAll: true), ' ')
      .replaceAll(RegExp(r'<style[^>]*>.*?</style>', dotAll: true), ' ')
      .replaceAll(RegExp(r'<[^>]+>'), ' ')
      .replaceAll('&amp;', '&')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  List<String> _meaningfulTokens(String value) {
    const ignored = {
      'the',
      'and',
      'pty',
      'ltd',
      'limited',
      'co',
      'company',
      'group',
      'services',
      'service',
      'solutions',
      'australia',
      'australian',
      'construction',
      'constructions',
      'builders',
      'building',
      'contractors',
      'contractor',
      'plumbing',
      'electrical',
      'roofing',
      'carpentry',
      'painting',
      'tiling',
      'hardware',
      'operations',
      'operation',
      'holdings',
      'holding',
      'resources',
      'resource',
      'minerals',
      'mineral',
      'mining',
      'gold',
      'iron',
      'ore',
      'project',
      'projects',
      'trustee',
      'trust',
      'unit',
    };
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
        .split(RegExp(r'\s+'))
        .where((token) => token.length >= 3 && !ignored.contains(token))
        .toList(growable: false);
  }

  String _domainSlug(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '').trim();

  String _emailDomain(String email) {
    final normalized = email.trim().toLowerCase();
    final at = normalized.lastIndexOf('@');
    if (at <= 0 || at == normalized.length - 1) return '';
    return normalized.substring(at + 1).replaceFirst(RegExp(r'^www\.'), '');
  }

  bool _isGenericEmailDomain(String domain) {
    const generic = <String>{
      'gmail.com',
      'googlemail.com',
      'outlook.com',
      'hotmail.com',
      'hotmail.com.au',
      'live.com',
      'live.com.au',
      'icloud.com',
      'me.com',
      'yahoo.com',
      'yahoo.com.au',
      'bigpond.com',
      'bigpond.net.au',
    };
    return generic.contains(domain.toLowerCase());
  }

  void _applyKnownConstructionBrandContacts(Map<String, dynamic> row) {
    final candidates = [
      (row['osm_brand'] ?? '').toString(),
      (row['name'] ?? '').toString(),
    ];
    Map<String, String>? profile;
    for (final candidate in candidates) {
      final normalized = _domainSlug(candidate);
      for (final entry in _knownConstructionBrandContacts.entries) {
        if (normalized == entry.key || normalized.contains(entry.key)) {
          profile = entry.value;
          break;
        }
      }
      if (profile != null) break;
    }
    if (profile == null) return;
    profile.forEach((key, value) {
      if ((row[key] ?? '').toString().trim().isEmpty) row[key] = value;
    });
    row['careers_verification_status'] = 'verified';
    row['email_officially_published'] = true;
    row['email_verification_status'] = 'officially_published';
    row['email_source_url'] = profile['careers_page'] ?? profile['website'];
  }

  String _extractLocality(String address, String postcode) {
    final parts = address
        .split(',')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
    for (final part in parts.reversed) {
      if (part == postcode) continue;
      if (part.length == 2 || part.length == 3) continue;
      return part;
    }
    return '';
  }

  String _extractWikidataId(Map<String, dynamic> row) {
    final direct = (row['osm_wikidata'] ?? '').toString().trim();
    if (RegExp(r'^Q\d+$', caseSensitive: false).hasMatch(direct)) {
      return direct.toUpperCase();
    }
    final wikipedia = (row['osm_wikipedia'] ?? '').toString();
    final match = RegExp(r'Q\d+', caseSensitive: false).firstMatch(wikipedia);
    return match?.group(0)?.toUpperCase() ?? '';
  }

  void _copySocialWebsiteToContact(Map<String, dynamic> row, String website) {
    if (website.isEmpty) return;
    final lower = website.toLowerCase();
    if (lower.contains('facebook.com') &&
        (row['facebook_url'] ?? '').toString().trim().isEmpty) {
      row['facebook_url'] = website;
    }
    if (lower.contains('instagram.com') &&
        (row['instagram_url'] ?? '').toString().trim().isEmpty) {
      row['instagram_url'] = website;
    }
  }

  bool _isDirectoryWebsite(String website) {
    final host = Uri.tryParse(website)?.host.toLowerCase() ?? website;
    const directoryHosts = [
      'google.',
      'facebook.com/pages',
      'instagram.com',
      'yellowpages',
      'truelocal',
      'hipages',
      'oneflare',
      'wordofmouth',
      'localsearch',
      'yelp',
      'tripadvisor',
      'openstreetmap.org',
      'osm.org',
      'whitepages',
      'hotfrog',
      'aussieweb',
    ];
    return directoryHosts.any((item) => host.contains(item));
  }

  Map<String, String> _requestHeaders() {
    return const {
      'Accept': 'application/json',
      'User-Agent':
          'WorkyDay/1.0 (OpenStreetMap construction import; contact: support@workyday.com)',
    };
  }

  String _buildAddress(Map tags, String postcode) {
    final houseNumber = (tags['addr:housenumber'] ?? '').toString().trim();
    final street = (tags['addr:street'] ?? '').toString().trim();
    final suburb = _firstTag(tags, const [
      'addr:suburb',
      'addr:city',
      'addr:town',
      'addr:locality',
    ]);
    final state = getStateFromPostcode(postcode);
    final parts = <String>[
      [houseNumber, street].where((part) => part.isNotEmpty).join(' '),
      suburb,
      state,
      postcode,
    ].where((part) => part.trim().isNotEmpty).toList(growable: false);
    return parts.join(', ');
  }

  String _firstTag(Map tags, List<String> keys) {
    for (final key in keys) {
      final value = (tags[key] ?? '').toString().trim();
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  String _normalizeWebsiteUrl(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return '';
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return value;
    }
    return 'https://$value';
  }

  String _cleanBaseUrl(String raw) {
    final uri = Uri.tryParse(_normalizeWebsiteUrl(raw));
    if (uri == null || uri.host.isEmpty) return '';
    return Uri(
      scheme: uri.scheme.isEmpty ? 'https' : uri.scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
    ).toString();
  }

  String _combineUrl(String baseUrl, String path) {
    final base = Uri.tryParse(baseUrl);
    if (base == null) return baseUrl;
    return base.resolve(path).toString();
  }

  String _normalizeSocialUrl(String raw, String host) {
    final value = raw.trim();
    if (value.isEmpty) return '';
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return value;
    }
    if (value.contains(host)) return 'https://$value';
    return 'https://$host/${value.replaceFirst('@', '')}';
  }

  Map<String, dynamic> _mergeConstructionCompany(
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
    merged['company_validation_status'] = incoming['company_validation_status'];
    merged['company_validation_source'] = incoming['company_validation_source'];
    for (final key in const [
      'construction_category',
      'construction_category_label',
      'entity_kind',
      'classification_confidence',
      'classification_reason',
      'classification_source',
      'review_status',
      'catalog_sources',
      'osm_description',
      'osm_operator',
      'osm_company',
      'osm_service',
      'osm_product',
      'osm_industry',
      'osm_landuse',
      'osm_man_made',
      'osm_power',
    ]) {
      if (incoming[key] != null) merged[key] = incoming[key];
    }
    return merged;
  }

  OsmConstructionImportSummary _buildImportSummary(
    List<Map<String, dynamic>> rows,
    List<int> indexes,
  ) {
    final seenEmails = <String>{};
    final emailContacts = <OsmConstructionEmailContact>[];
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
    var websiteFromProbableDomain = 0;
    final categoryCounts = <String, int>{};
    final entityCounts = <String, int>{};

    for (final index in indexes) {
      if (index < 0 || index >= rows.length) continue;
      final row = rows[index];
      final website = (row['website'] ?? '').toString().trim();
      final phone = (row['phone'] ?? '').toString().trim();
      final email = (row['email'] ?? '').toString().trim();
      final facebook = (row['facebook_url'] ?? '').toString().trim();
      final instagram = (row['instagram_url'] ?? '').toString().trim();
      final careers = (row['careers_page'] ?? '').toString().trim();
      final category = ConstructionCategory.classifyRow(row);
      final entityKind = ConstructionCategory.classifyRowDetailed(
        row,
      ).entityKindId;
      categoryCounts.update(
        category.id,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
      entityCounts.update(entityKind, (count) => count + 1, ifAbsent: () => 1);
      final discoverySource = (row['website_discovery_source'] ?? '')
          .toString()
          .trim();
      final discoveryChecked = (row['website_discovery_checked_at'] ?? '')
          .toString()
          .trim();

      if (website.isNotEmpty) {
        withWebsite++;
        if (discoverySource.isEmpty || discoverySource == 'osm_tag') {
          websiteFromOsm++;
        } else {
          websiteDiscovered++;
          if (discoverySource == 'wikidata' ||
              discoverySource.startsWith('wikidata:')) {
            websiteFromWikidata++;
          } else if (discoverySource == 'probable_domain') {
            websiteFromProbableDomain++;
          }
        }
      }
      if (phone.isNotEmpty) withPhone++;
      if (email.isNotEmpty) {
        withEmail++;
        final key = email.toLowerCase();
        if (seenEmails.add(key)) {
          emailContacts.add(
            OsmConstructionEmailContact(
              name: (row['name'] ?? '').toString(),
              email: email,
            ),
          );
        }
      }
      if (facebook.isNotEmpty) withFacebook++;
      if (instagram.isNotEmpty) withInstagram++;
      if (careers.isNotEmpty) withCareers++;
      if ((row['website_discovery_attempted'] ?? false) == true ||
          discoveryChecked.isNotEmpty) {
        websiteDiscoveryAttempted++;
      }
    }

    return OsmConstructionImportSummary(
      processed: indexes.length,
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
      websiteFromProbableDomain: websiteFromProbableDomain,
      emailContacts: emailContacts,
      categoryCounts: categoryCounts,
      entityCounts: entityCounts,
    );
  }

  int? _findNearbyDuplicateIndex(
    List<Map<String, dynamic>> existing,
    Map<String, dynamic> candidate,
  ) {
    final candidateName = _normalizeName(candidate['name']);
    final candidateLat = _asDouble(candidate['latitude']);
    final candidateLng = _asDouble(candidate['longitude']);
    if (candidateName.isEmpty || candidateLat == null || candidateLng == null) {
      return null;
    }

    for (var index = 0; index < existing.length; index++) {
      final row = existing[index];
      if (_normalizeName(row['name']) != candidateName) continue;
      final rowLat = _asDouble(row['latitude'] ?? row['lat']);
      final rowLng = _asDouble(row['longitude'] ?? row['lng']);
      if (rowLat == null || rowLng == null) continue;
      if (_distanceMeters(candidateLat, candidateLng, rowLat, rowLng) <= 120) {
        return index;
      }
    }
    return null;
  }

  int _categoryRelevanceScore(ConstructionCategory category) {
    if (category == ConstructionCategory.miningContractor) return 98;
    if (category == ConstructionCategory.civil) return 95;
    if (category == ConstructionCategory.residentialCommercial) return 92;
    if (category == ConstructionCategory.engineeringEpc) return 88;
    if (category == ConstructionCategory.infrastructure) return 86;
    if (category == ConstructionCategory.labourHire) return 84;
    if (category == ConstructionCategory.miningCompany) return 82;
    if (category == ConstructionCategory.renewables) return 80;
    if (category == ConstructionCategory.oilGasEnergy) return 78;
    return 50;
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

  bool _isSocialWebsite(String url) {
    final lower = url.toLowerCase();
    return lower.contains('facebook.com') ||
        lower.contains('instagram.com') ||
        lower.contains('tiktok.com') ||
        lower.contains('linkedin.com');
  }

  double? _asDouble(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse((value ?? '').toString());
  }
}

class _WebsiteDiscovery {
  const _WebsiteDiscovery({
    required this.url,
    required this.source,
    required this.confidence,
    this.candidates = const <String>[],
  });

  final String url;
  final String source;
  final int confidence;
  final List<String> candidates;
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
      south != null && west != null && north != null && east != null;
}
