import 'dart:async';

import 'package:flutter/material.dart';

import '../config/osm_import_config.dart';
import '../models/construction_category.dart';
import '../models/construction_domain_records.dart';
import '../services/construction_catalogue_review_service.dart';
import '../services/construction_import_diagnostics_service.dart';
import '../services/construction_pending_publish_service.dart';
import '../services/construction_publication_policy.dart';
import '../services/construction_sqlite_store.dart';
import '../services/construction_source_models.dart';
import '../services/construction_state_builder_service.dart';
import '../services/geoscience_australia_mines_import_service.dart';
import '../services/nsw_major_operating_mines_import_service.dart';
import '../services/nsw_coal_producers_import_service.dart';
import '../services/nsw_epa_licensed_premises_import_service.dart';
import '../services/nsw_minerals_council_members_import_service.dart';
import '../services/nsw_minerals_council_mines_import_service.dart';
import '../services/osm_construction_import_service.dart';
import '../services/postcode_state_helper.dart';
import '../services/visa_postcodes_sqlite_store.dart';
import '../services/wa_minedex_import_service.dart';
import 'construction_edit_page.dart';

class AddConstructionByStatePage extends StatefulWidget {
  const AddConstructionByStatePage({super.key});

  @override
  State<AddConstructionByStatePage> createState() =>
      _AddConstructionByStatePageState();
}

class _AddConstructionByStatePageState
    extends State<AddConstructionByStatePage> {
  final OsmConstructionImportService _importService =
      OsmConstructionImportService();
  final VisaPostcodesSqliteStore _visaStore = VisaPostcodesSqliteStore.instance;
  final ConstructionImportDiagnosticsService _diagnostics =
      ConstructionImportDiagnosticsService.instance;
  final ConstructionCatalogueReviewService _catalogueReviewService =
      ConstructionCatalogueReviewService.instance;
  final GeoscienceAustraliaMinesImportService _nationalMinesService =
      GeoscienceAustraliaMinesImportService();
  final NswMajorOperatingMinesImportService _nswMinesService =
      NswMajorOperatingMinesImportService();
  final NswCoalProducersImportService _nswCoalProducersService =
      NswCoalProducersImportService();
  final NswEpaLicensedPremisesImportService _nswEpaPremisesService =
      NswEpaLicensedPremisesImportService();
  final NswMineralsCouncilMembersImportService _nswMembersService =
      NswMineralsCouncilMembersImportService();
  final NswMineralsCouncilMinesImportService _nswCouncilMinesService =
      NswMineralsCouncilMinesImportService();

  final List<String> _states = const [
    'QLD',
    'VIC',
    'NSW',
    'SA',
    'WA',
    'TAS',
    'NT',
  ];

  String? _selectedState;
  bool _isImporting = false;
  bool _forceRefresh = false;
  bool _didChange = false;
  bool _isReviewingCatalogue = false;
  bool _isImportingMinedex = false;
  WaMinedexImportResult? _minedexResult;
  GeoscienceAustraliaMinesImportResult? _nationalMinesResult;
  NswMajorOperatingMinesImportResult? _nswMinesResult;
  NswCoalProducersImportResult? _nswCoalProducersResult;
  NswEpaLicensedPremisesImportResult? _nswEpaPremisesResult;
  NswMineralsCouncilMembersImportResult? _nswMembersResult;
  NswMineralsCouncilMinesImportResult? _nswCouncilMinesResult;
  Map<String, int> _enrichmentStatusCounts = const <String, int>{};
  List<Map<String, dynamic>> _needsReviewRows = const [];
  int _uniqueEmployersAnalysed = 0;
  int _readyStateRecords = 0;
  int _pendingPublishCount = 0;
  Map<String, int> _domainMetrics = const <String, int>{};
  int _processed = 0;
  int _total = 0;
  int? _selectedStatePostcodeCount;
  int _savedFailedCount = 0;
  String? _currentPostcode;
  String? _currentCompanyName;
  int? _currentCompanyIndex;
  int? _currentCompanyTotal;
  String? _currentStatus;
  _ConstructionStateTotals? _latestTotals;
  ConstructionCatalogueReviewResult? _catalogueReview;
  Completer<void>? _skipCompleter;
  ConstructionContactEnrichmentControl? _enrichmentControl;
  bool _stopRequested = false;
  bool _isBuilding = false;
  ConstructionBuildControl? _builderControl;
  ConstructionBuildStage? _builderStage;
  final ConstructionStateBuilderService _stateBuilder =
      ConstructionStateBuilderService();

  @override
  void initState() {
    super.initState();
    _reviewCatalogue(linkOperators: true);
  }

  Future<void> _reviewCatalogue({required bool linkOperators}) async {
    if (_isReviewingCatalogue) return;
    setState(() => _isReviewingCatalogue = true);
    try {
      final result = linkOperators
          ? await _catalogueReviewService.reviewAndLinkOperators()
          : await _catalogueReviewService.summarize();
      if (result.operatorCompanyIds.isNotEmpty) {
        await ConstructionPendingPublishService.instance.markPending(
          result.operatorCompanyIds,
        );
      }
      final pending = await ConstructionPendingPublishService.instance
          .getPublishablePendingIds();
      final domainMetrics = await ConstructionSqliteStore.instance
          .getDomainMetrics();
      if (!mounted) return;
      setState(() {
        _catalogueReview = result;
        _pendingPublishCount = pending.length;
        _domainMetrics = domainMetrics;
        if (result.operatorCompaniesCreated > 0) _didChange = true;
      });
    } finally {
      if (mounted) setState(() => _isReviewingCatalogue = false);
    }
  }

  Future<void> _importWaMinedex() async {
    if (_isImportingMinedex) return;
    setState(() => _isImportingMinedex = true);
    try {
      final result = await const WaMinedexImportService().importLocal();
      if (!mounted) return;
      setState(() {
        _minedexResult = result;
        _didChange = true;
      });
      final store = ConstructionSqliteStore.instance;
      await store.init();
      final storedRows = await store.getAll();
      final readyOfficialIds = storedRows
          .where(
            (row) =>
                (row['source'] ?? '').toString() ==
                    'wa_minedex_site_operator' &&
                ConstructionPublicationPolicy.canAppearOnMap(row),
          )
          .map((row) => (row['docId'] ?? row['id'] ?? '').toString())
          .toList(growable: false);
      final storedMapReady = storedRows
          .where(
            (row) =>
                (row['state'] ?? '').toString().toUpperCase() == 'WA' &&
                ConstructionPublicationPolicy.canAppearOnMap(row),
          )
          .length;
      final pending = await ConstructionPendingPublishService.instance
          .markPending(readyOfficialIds);
      if (mounted) {
        setState(() {
          _pendingPublishCount = pending;
          _readyStateRecords = storedMapReady;
        });
      }
      await _reviewCatalogue(linkOperators: false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${result.mapReady} verified WA operator/worksite links are now available locally on the map.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'The local WA MINEDEX catalogue could not be imported.',
          ),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (mounted) setState(() => _isImportingMinedex = false);
    }
  }

  Future<void> _runStateWorkflow({
    required bool force,
    required bool retryIncomplete,
    required bool scanOsm,
  }) async {
    final state = _selectedState;
    if (state == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Select a state first.')));
      return;
    }
    _stopRequested = false;
    if (state == 'WA') await _importWaMinedex();
    if (_stopRequested || !mounted) return;
    if (state != 'WA') {
      setState(() {
        _isImportingMinedex = true;
        _currentStatus = 'Importing national operating-mine worksites…';
      });
      try {
        final nationalResult = await _nationalMinesService.importState(state);
        NswMajorOperatingMinesImportResult? nswResult;
        NswCoalProducersImportResult? nswCoalResult;
        NswEpaLicensedPremisesImportResult? nswEpaResult;
        NswMineralsCouncilMembersImportResult? nswMembersResult;
        NswMineralsCouncilMinesImportResult? nswCouncilMinesResult;
        if (state == 'NSW') {
          if (mounted) {
            setState(
              () => _currentStatus =
                  'Importing official NSW operating-mine worksites…',
            );
          }
          try {
            nswResult = await _nswMinesService.importLocal();
          } catch (_) {
            // The state overlay is additive. A temporary NSW WFS failure must
            // not discard the verified national import or block enrichment.
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'The NSW overlay is temporarily unavailable. National worksites were kept and enrichment will continue.',
                  ),
                ),
              );
            }
          }
          if (nswResult != null) {
            if (mounted) {
              setState(
                () => _currentStatus =
                    'Corroborating NSW coal producers and worksites…',
              );
            }
            try {
              nswCoalResult = await _nswCoalProducersService.importLocal(
                forceRefresh: force,
              );
            } catch (_) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Coal producer corroboration is temporarily unavailable. NSW worksites were kept and enrichment will continue.',
                    ),
                  ),
                );
              }
            }
          }
          if (mounted) {
            setState(
              () =>
                  _currentStatus = 'Importing additional NSW mining employers…',
            );
          }
          try {
            nswMembersResult = await _nswMembersService.importLocal(
              forceRefresh: force,
            );
          } catch (_) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'The additional NSW employer list is temporarily unavailable. Existing NSW records were kept.',
                  ),
                ),
              );
            }
          }
          if (mounted) {
            setState(
              () => _currentStatus =
                  'Linking additional NSW operators to operating mines…',
            );
          }
          try {
            nswCouncilMinesResult = await _nswCouncilMinesService.importLocal(
              forceRefresh: force,
            );
          } catch (_) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'The additional NSW mine-to-employer links are temporarily unavailable. Existing records were kept.',
                  ),
                ),
              );
            }
          }
          if (mounted) {
            setState(
              () => _currentStatus =
                  'Importing official NSW licensed construction premises…',
            );
          }
          try {
            nswEpaResult = await _nswEpaPremisesService.importLocal(
              forceRefresh: force,
            );
          } catch (_) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'The NSW EPA premises layer is temporarily unavailable. Existing NSW records were kept and enrichment will continue.',
                  ),
                ),
              );
            }
          }
        }
        if (mounted) {
          setState(() {
            _nationalMinesResult = nationalResult;
            _nswMinesResult = nswResult;
            _nswCoalProducersResult = nswCoalResult;
            _nswEpaPremisesResult = nswEpaResult;
            _nswMembersResult = nswMembersResult;
            _nswCouncilMinesResult = nswCouncilMinesResult;
            _didChange = true;
          });
        }
      } finally {
        if (mounted) setState(() => _isImportingMinedex = false);
      }
    }
    if (!mounted || _stopRequested) return;
    setState(() {
      _latestTotals = null;
      _processed = 0;
      _total = 0;
      _enrichmentStatusCounts = const <String, int>{};
    });
    if (scanOsm) {
      setState(() => _forceRefresh = force);
      await _startImport(showSummary: false);
      if (!mounted || _stopRequested) return;
    }

    setState(() {
      _isImporting = true;
      _currentStatus = 'Enriching every missing public contact for $state...';
    });
    final enrichmentControl = ConstructionContactEnrichmentControl();
    _enrichmentControl = enrichmentControl;
    try {
      final queueResult = await _importService
          .enrichAllVerifiedOfficialCompanies(
            state: state,
            force: force,
            retryIncomplete: retryIncomplete,
            onProgress: _handleProgress,
            control: enrichmentControl,
          );
      final store = ConstructionSqliteStore.instance;
      await store.init();
      final stateRows = (await store.getAll())
          .where(
            (row) => (row['state'] ?? '').toString().toUpperCase() == state,
          )
          .toList(growable: false);
      final counts = <String, int>{};
      final readyIds = <String>[];
      final employersByKey = <String, Map<String, dynamic>>{};
      for (final row in stateRows) {
        final operatorCode = (row['operator_code'] ?? '').toString().trim();
        final employerKey = operatorCode.isNotEmpty
            ? 'operator:$operatorCode'
            : (row['name'] ?? '').toString().trim().toLowerCase();
        if (employerKey.isNotEmpty &&
            ConstructionPublicationPolicy.isVerifiedEnrichmentCandidate(row)) {
          final current = employersByKey[employerKey];
          if (current == null ||
              _enrichmentStatusPriority(row) >
                  _enrichmentStatusPriority(current)) {
            employersByKey[employerKey] = row;
          }
        }
        if (ConstructionPublicationPolicy.canAppearOnMap(row)) {
          readyIds.add((row['docId'] ?? row['id'] ?? '').toString());
        }
      }
      for (final row in employersByKey.values) {
        final status = (row['contact_enrichment_status'] ?? 'pending')
            .toString();
        counts.update(status, (value) => value + 1, ifAbsent: () => 1);
        final failureKind = (row['contact_enrichment_failure_kind'] ?? '')
            .toString();
        if (failureKind.isNotEmpty) {
          counts.update(
            'failure_$failureKind',
            (value) => value + 1,
            ifAbsent: () => 1,
          );
        }
      }
      final pending = await ConstructionPendingPublishService.instance
          .markPending(readyIds);
      if (!mounted) return;
      setState(() {
        _enrichmentStatusCounts = counts;
        _needsReviewRows = employersByKey.values
            .where(
              (row) =>
                  (row['contact_enrichment_status'] ?? '').toString() ==
                  'needs_review',
            )
            .map((row) => Map<String, dynamic>.from(row))
            .toList(growable: false);
        _pendingPublishCount = pending;
        _uniqueEmployersAnalysed = employersByKey.length;
        _readyStateRecords = readyIds.length;
        _didChange = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            queueResult.cancelled
                ? '$state stopped safely: ${queueResult.checked} processed, ${queueResult.skipped} skipped and ${queueResult.remaining} resumable.'
                : '$state completed: ${stateRows.length} local records analysed, ${readyIds.length} eligible for the map and publication queue.',
          ),
        ),
      );
      await _showEnrichmentSummary(
        state: state,
        uniqueEmployers: employersByKey.length,
        readyRecords: readyIds.length,
        counts: counts,
        queueResult: queueResult,
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Contact enrichment stopped: $error'),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isImporting = false;
          _forceRefresh = false;
          _clearCurrentProgress();
        });
      }
      _enrichmentControl = null;
    }
  }

  void _skipCurrentCompany() {
    final skipped = _enrichmentControl?.skipCurrentCompany() ?? false;
    if (!mounted) return;
    setState(() {
      _currentStatus = skipped
          ? 'Skipping $_currentCompanyName and saving existing data...'
          : 'This company has already finished; moving to the next one...';
    });
  }

  void _stopAndSaveEnrichment() {
    _stopRequested = true;
    _builderControl?.stopAndSave();
    _enrichmentControl?.stopAndSave();
    final postcodeSignal = _skipCompleter;
    if (postcodeSignal != null && !postcodeSignal.isCompleted) {
      postcodeSignal.complete();
    }
    if (!mounted) return;
    setState(() {
      _currentStatus =
          'Stopping safely… Completed companies and postcodes are saved.';
    });
  }

  Future<void> _buildOrUpdateState({bool forceDiscovery = false}) async {
    final state = _selectedState;
    if (state == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Select a state first.')));
      return;
    }
    final control = ConstructionBuildControl();
    _builderControl = control;
    setState(() => _isBuilding = true);
    try {
      final report = await _stateBuilder.buildOrUpdate(
        state: state,
        control: control,
        forceDiscovery: forceDiscovery,
        onProgress: (stage, message) {
          if (mounted) {
            setState(() {
              _builderStage = stage;
              _currentStatus = message;
            });
          }
        },
        // The established adapters are retained for WA/NSW and the national
        // layer. The builder wraps them in a resumable, audited job.
        runSpecialAdapters: (_) => _runStateWorkflow(
          force: forceDiscovery,
          retryIncomplete: true,
          scanOsm: false,
        ),
        // Contact enrichment is part of the retained adapter workflow above.
        enrichContacts: (_) async {},
      );
      if (!mounted) return;
      await _selectState(state);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('State build · $state'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  report.status == 'stopped_saved'
                      ? 'Stopped safely. Finished work was saved.'
                      : report.publicationSafe
                      ? 'Build finished and passed the safety check.'
                      : 'Build finished, but publication was blocked by the safety brake.',
                ),
                const SizedBox(height: 12),
                _summaryRow('Employers', report.after['employers'] ?? 0),
                _summaryRow('Worksites', report.after['worksites'] ?? 0),
                _summaryRow(
                  'Linked worksites',
                  report.after['linked_worksites'] ?? 0,
                ),
                _summaryRow('Ready sources', report.sourcesReady),
                _summaryRow(
                  'Sources needing review',
                  report.sourcesNeedingReview,
                ),
                if (report.errors.isNotEmpty) ...[
                  const Divider(),
                  const Text(
                    'Warnings',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  for (final error in report.errors.take(8)) Text('• $error'),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } finally {
      _builderControl = null;
      _builderStage = null;
      if (mounted) setState(() => _isBuilding = false);
    }
  }

  Widget _enrichmentControlButtons() => LayoutBuilder(
    builder: (context, constraints) {
      final isPostcodeStage =
          _currentPostcode != null && _currentPostcode != 'official';
      final canSkipCompany =
          !isPostcodeStage &&
          _enrichmentControl != null &&
          _currentCompanyName != null;
      final canSkipSource =
          _builderControl != null &&
          _enrichmentControl == null &&
          _currentPostcode == null &&
          (_builderStage == ConstructionBuildStage.inspectSources ||
              _builderStage == ConstructionBuildStage.importSources);
      final skip = ElevatedButton.icon(
        onPressed: canSkipSource
            ? () {
                _builderControl?.skipSource();
                setState(
                  () => _currentStatus =
                      'Skipping this source after the current safe request…',
                );
              }
            : isPostcodeStage
            ? _skipCurrentPostcode
            : canSkipCompany
            ? _skipCurrentCompany
            : null,
        icon: const Icon(Icons.skip_next_rounded),
        label: Text(
          canSkipSource
              ? 'Skip this source'
              : isPostcodeStage
              ? 'Skip this postcode'
              : 'Skip this company',
        ),
        style: ElevatedButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          backgroundColor: Colors.orange.shade700,
          foregroundColor: Colors.white,
        ),
      );
      final stop = ElevatedButton.icon(
        onPressed: _stopAndSaveEnrichment,
        icon: const Icon(Icons.stop_circle_outlined),
        label: const Text('Stop and save progress'),
        style: ElevatedButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          backgroundColor: Colors.red.shade700,
          foregroundColor: Colors.white,
        ),
      );
      if (constraints.maxWidth < 520) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [skip, const SizedBox(height: 8), stop],
        );
      }
      return Row(
        children: [
          Expanded(child: skip),
          const SizedBox(width: 10),
          Expanded(child: stop),
        ],
      );
    },
  );

  int _enrichmentStatusPriority(Map<String, dynamic> row) {
    switch ((row['contact_enrichment_status'] ?? 'pending').toString()) {
      case 'completed':
        return 6;
      case 'needs_review':
        return 5;
      case 'blocked_by_website':
        return 4;
      case 'retry_later':
        return 3;
      case 'no_verified_website':
      case 'identity_unresolved':
      case 'no_public_website':
        return 2;
      default:
        return 1;
    }
  }

  Future<void> _openNeedsReview(Map<String, dynamic> row) async {
    final result = await Navigator.of(context).push<ConstructionEditResult>(
      MaterialPageRoute(
        builder: (_) => ConstructionEditPage(
          companyId: (row['docId'] ?? row['id'] ?? '').toString(),
          initialCompany: Map<String, dynamic>.from(row),
        ),
      ),
    );
    if (!mounted) return;
    final state = _selectedState;
    if (state != null) await _selectState(state);
    if (!mounted) return;
    if (result?.changed == true &&
        result?.previousStatus == 'needs_review' &&
        result?.newStatus != 'needs_review') {
      setState(() => _didChange = true);
    }
  }

  Future<void> _showEnrichmentSummary({
    required String state,
    required int uniqueEmployers,
    required int readyRecords,
    required Map<String, int> counts,
    required ConstructionContactEnrichmentQueueResult queueResult,
  }) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Contact enrichment · $state'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _summaryRow('Unique employers analysed', uniqueEmployers),
              _summaryRow('Eligible worksite records', readyRecords),
              _summaryRow('Processed this run', queueResult.checked),
              _summaryRow('Skipped this run', queueResult.skipped),
              _summaryRow('Still resumable', queueResult.remaining),
              if (queueResult.cancelled)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'Stopped safely. Completed companies were saved and remaining companies can be resumed.',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              const Divider(height: 24),
              _summaryRow('Completed', counts['completed'] ?? 0),
              _summaryRow(
                'Identity unresolved',
                (counts['identity_unresolved'] ?? 0) +
                    (counts['no_verified_website'] ?? 0),
              ),
              _summaryRow(
                'No public website confirmed',
                counts['no_public_website'] ?? 0,
              ),
              _summaryRow(
                'Blocked by website',
                counts['blocked_by_website'] ?? 0,
              ),
              _summaryRow('Retry later', counts['retry_later'] ?? 0),
              _summaryRow('Timeout', counts['failure_timeout'] ?? 0),
              _summaryRow('HTTP 429', counts['failure_http_429'] ?? 0),
              _summaryRow('HTTP 5xx', counts['failure_http_5xx'] ?? 0),
              _summaryRow('Network / DNS', counts['failure_network_dns'] ?? 0),
              _summaryRow('Needs review', counts['needs_review'] ?? 0),
              _summaryRow('Pending', counts['pending'] ?? 0),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<List<String>> _loadRegionalPostcodes() async {
    final state = _selectedState;
    if (state == null) return const <String>[];
    await _visaStore.init();
    await _visaStore.importSeedAssetIfEmpty();
    final entries = await _visaStore.getAll();
    final postcodes = <String>{};
    for (final entry in entries) {
      final industry = (entry['industry'] ?? entry['id'] ?? '')
          .toString()
          .toLowerCase();
      if (!industry.contains('regional australia')) continue;
      final rawPostcodes = entry['postcodes'];
      if (rawPostcodes is! List) continue;
      for (final raw in rawPostcodes) {
        final postcode = raw.toString().padLeft(4, '0');
        if (!RegExp(r'^\d{4}$').hasMatch(postcode)) continue;
        if (getStateFromPostcode(postcode) == state) postcodes.add(postcode);
      }
    }
    return postcodes.toList()..sort();
  }

  Future<void> _selectState(String? value) async {
    setState(() {
      _selectedState = value;
      _nationalMinesResult = null;
      _nswMinesResult = null;
      _nswCoalProducersResult = null;
      _nswEpaPremisesResult = null;
      _selectedStatePostcodeCount = null;
      _savedFailedCount = 0;
      _latestTotals = null;
      _processed = 0;
      _total = 0;
      _clearCurrentProgress();
    });
    if (value == null) return;
    final postcodes = await _loadRegionalPostcodes();
    final failures = await _diagnostics.loadFailures(state: value);
    final store = ConstructionSqliteStore.instance;
    await store.init();
    final stateRows = (await store.getAll())
        .where((row) => (row['state'] ?? '').toString().toUpperCase() == value)
        .toList(growable: false);
    final storedCounts = <String, int>{};
    final storedEmployers = <String, Map<String, dynamic>>{};
    for (final row in stateRows) {
      if (!ConstructionPublicationPolicy.isVerifiedEnrichmentCandidate(row)) {
        continue;
      }
      final operatorCode = (row['operator_code'] ?? '').toString().trim();
      final key = operatorCode.isNotEmpty
          ? 'operator:$operatorCode'
          : (row['name'] ?? '').toString().trim().toLowerCase();
      if (key.isEmpty) continue;
      final current = storedEmployers[key];
      if (current == null ||
          _enrichmentStatusPriority(row) > _enrichmentStatusPriority(current)) {
        storedEmployers[key] = row;
      }
    }
    for (final row in storedEmployers.values) {
      final status = (row['contact_enrichment_status'] ?? 'pending').toString();
      storedCounts.update(status, (value) => value + 1, ifAbsent: () => 1);
      final failureKind = (row['contact_enrichment_failure_kind'] ?? '')
          .toString();
      if (failureKind.isNotEmpty) {
        storedCounts.update(
          'failure_$failureKind',
          (value) => value + 1,
          ifAbsent: () => 1,
        );
      }
    }
    if (!mounted || _selectedState != value) return;
    setState(() {
      _selectedStatePostcodeCount = postcodes.length;
      _savedFailedCount = failures.length;
      _enrichmentStatusCounts = storedCounts;
      _uniqueEmployersAnalysed = storedEmployers.length;
      _readyStateRecords = stateRows
          .where(ConstructionPublicationPolicy.canAppearOnMap)
          .length;
      final employerIds = <String>{};
      final worksiteIds = <String>{};
      final linkedWorksiteIds = <String>{};
      for (final row in stateRows) {
        if (ConstructionPublicationPolicy.isRelevantEmployer(row)) {
          final companyId = ConstructionDomainRecords.companyId(row);
          if (companyId.isNotEmpty) employerIds.add(companyId);
        }
        if (!ConstructionDomainRecords.isWorksite(row)) continue;
        final worksiteId = ConstructionDomainRecords.worksiteId(row);
        if (worksiteId.isEmpty) continue;
        worksiteIds.add(worksiteId);
        if (ConstructionDomainRecords.hasCorroboratedHiringLink(row)) {
          linkedWorksiteIds.add(worksiteId);
        }
      }
      _domainMetrics = {
        'employers': employerIds.length,
        'worksites': worksiteIds.length,
        'linked_worksites': linkedWorksiteIds.length,
      };
      _needsReviewRows = storedEmployers.values
          .where(
            (row) =>
                (row['contact_enrichment_status'] ?? '').toString() ==
                'needs_review',
          )
          .map((row) => Map<String, dynamic>.from(row))
          .toList(growable: false);
    });
  }

  Future<void> _startImport({
    bool failedOnly = false,
    bool showSummary = true,
  }) async {
    final state = _selectedState;
    if (state == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Select a state.')));
      return;
    }

    setState(() {
      _isImporting = true;
      _processed = 0;
      _total = 0;
      _clearCurrentProgress();
      _latestTotals = _ConstructionStateTotals(state: state);
    });

    try {
      var postcodes = await _loadRegionalPostcodes();
      if (failedOnly) {
        final failures = await _diagnostics.loadFailures(state: state);
        final eligible = postcodes.toSet();
        postcodes =
            failures
                .map((failure) => failure.postcode)
                .where(eligible.contains)
                .toSet()
                .toList()
              ..sort();
      }
      if (!mounted) return;
      if (postcodes.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No Regional Australia postcodes found for $state.'),
          ),
        );
        return;
      }

      final totals = _latestTotals ?? _ConstructionStateTotals(state: state);
      final retryPostcodes = <String>[];
      setState(() => _total = postcodes.length);
      for (final postcode in postcodes) {
        if (_stopRequested) break;
        try {
          final result = await _awaitOrSkip(
            _importService.importForPostcode(
              postcode,
              force: failedOnly || _forceRefresh,
              enrichWebContacts: true,
              uploadChangedToFirebase: false,
              onProgress: _handleProgress,
            ),
            postcode,
          );
          if (result == null) {
            totals.addSkippedByUser();
          } else {
            totals.add(result);
            await _diagnostics.markSuccessful(state, postcode);
            await _markResultPending(result);
            if (result.added > 0 || result.updated > 0 || result.enriched > 0) {
              _didChange = true;
            }
          }
        } catch (error) {
          if (_isRetryableImportError(error)) {
            retryPostcodes.add(postcode);
          } else {
            totals.addFailed(postcode, error);
            await _diagnostics.recordFailure(
              state: state,
              postcode: postcode,
              error: error,
            );
          }
        }
        if (!mounted) return;
        setState(() {
          _latestTotals = totals;
          _processed++;
        });
      }

      if (retryPostcodes.isNotEmpty && !_stopRequested) {
        if (!mounted) return;
        setState(() {
          _clearCurrentProgress();
          _currentStatus =
              'Waiting briefly before retrying ${retryPostcodes.length} temporary OSM failures...';
        });
        await Future<void>.delayed(
          const Duration(seconds: OsmImportConfig.stateImportRetryPauseSeconds),
        );
        for (var i = 0; i < retryPostcodes.length; i++) {
          if (_stopRequested) break;
          final postcode = retryPostcodes[i];
          if (!mounted) return;
          setState(() {
            _currentPostcode = postcode;
            _currentStatus =
                'Retrying temporary OSM failure ${i + 1}/${retryPostcodes.length}';
          });
          try {
            final result = await _importService.importForPostcode(
              postcode,
              force: true,
              enrichWebContacts: true,
              uploadChangedToFirebase: false,
              onProgress: _handleProgress,
            );
            totals.add(result);
            await _diagnostics.markSuccessful(state, postcode);
            await _markResultPending(result);
            if (result.added > 0 || result.updated > 0 || result.enriched > 0) {
              _didChange = true;
            }
          } catch (error) {
            totals.addFailed(postcode, error);
            await _diagnostics.recordFailure(
              state: state,
              postcode: postcode,
              error: error,
            );
          }
          if (mounted) setState(() => _latestTotals = totals);
        }
      }

      if (!mounted || _stopRequested) return;
      setState(() {
        _latestTotals = totals;
        _clearCurrentProgress();
        _currentStatus = 'Reclassifying and corroborating local employers...';
      });
      final catalogueReview = await _catalogueReviewService
          .reviewAndLinkOperators();
      if (catalogueReview.operatorCompanyIds.isNotEmpty) {
        await ConstructionPendingPublishService.instance.markPending(
          catalogueReview.operatorCompanyIds,
        );
      }
      final remainingFailures = await _diagnostics.loadFailures(state: state);
      if (mounted) {
        setState(() {
          _savedFailedCount = remainingFailures.length;
          _catalogueReview = catalogueReview;
          _currentStatus = null;
        });
      }
      if (showSummary) await _showSummary(totals);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Construction state import failed.'),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isImporting = false;
          _clearCurrentProgress();
        });
      }
      _skipCompleter = null;
    }
  }

  Future<void> _markResultPending(OsmConstructionImportResult result) async {
    if (result.changedConstructionIds.isEmpty) return;
    final count = await ConstructionPendingPublishService.instance.markPending(
      result.changedConstructionIds,
    );
    if (mounted) setState(() => _pendingPublishCount = count);
  }

  Future<void> _exportFailureReport() async {
    final state = _selectedState;
    if (state == null || _savedFailedCount == 0) return;
    final path = await _diagnostics.exportFailuresJson(state: state);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Failure report saved locally: $path')),
    );
  }

  bool _isRetryableImportError(Object error) {
    final message = error.toString();
    return error is TimeoutException ||
        message.contains('TimeoutException') ||
        message.contains('All Overpass endpoints failed') ||
        message.contains('HTTP 408') ||
        message.contains('HTTP 429') ||
        message.contains('HTTP 500') ||
        message.contains('HTTP 502') ||
        message.contains('HTTP 503') ||
        message.contains('HTTP 504');
  }

  void _handleProgress(OsmConstructionImportProgress progress) {
    if (!mounted) return;
    setState(() {
      _currentPostcode = progress.postcode;
      _currentCompanyName = progress.companyName;
      _currentCompanyIndex = progress.companyIndex;
      _currentCompanyTotal = progress.companyTotal;
      _currentStatus = progress.message ?? progress.stage;
      if (progress.postcode == 'official') {
        _processed = progress.companyIndex ?? _processed;
        _total = progress.companyTotal ?? _total;
      }
    });
  }

  void _clearCurrentProgress() {
    _currentPostcode = null;
    _currentCompanyName = null;
    _currentCompanyIndex = null;
    _currentCompanyTotal = null;
    _currentStatus = null;
  }

  Future<T?> _awaitOrSkip<T>(Future<T> future, String postcode) async {
    final completer = Completer<void>();
    setState(() {
      _skipCompleter = completer;
      _currentPostcode = postcode;
    });
    final winner = await Future.any<Object?>([
      future,
      completer.future.then((_) => const _ConstructionSkipSignal()),
    ]);
    if (identical(_skipCompleter, completer)) _skipCompleter = null;
    if (completer.isCompleted) {
      unawaited(future.then((_) {}, onError: (_) {}));
      return null;
    }
    return winner as T;
  }

  void _skipCurrentPostcode() {
    final completer = _skipCompleter;
    if (completer == null || completer.isCompleted) return;
    completer.complete();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Skipping postcode $_currentPostcode...')),
    );
  }

  Future<void> _showSummary(_ConstructionStateTotals totals) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('OSM construction state import · ${totals.state}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _summaryRow('Postcodes processed', totals.postcodesProcessed),
              _summaryRow('Successful OSM queries', totals.successfulQueries),
              _summaryRow('Skipped by cache', totals.skippedByCache),
              _summaryRow('Skipped by user', totals.skippedByUser),
              _summaryRow('Failed postcodes', totals.failedPostcodes),
              _summaryRow('Companies found in OSM', totals.discovered),
              _summaryRow('Unique companies changed', totals.uniqueCompanies),
              _summaryRow('Added', totals.added),
              _summaryRow('Updated', totals.updated),
              _summaryRow('Duplicates skipped', totals.skippedDuplicates),
              if (totals.entityCounts.isNotEmpty) ...[
                const Divider(height: 24),
                const Text(
                  'Employer relevance review',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                _summaryRow(
                  'Employers ready for review/map',
                  totals.entityCounts['employer'] ?? 0,
                ),
                _summaryRow(
                  'Project or work sites',
                  totals.entityCounts['project_site'] ?? 0,
                ),
                _summaryRow(
                  'Suppliers / retail excluded',
                  totals.entityCounts['supplier_retail'] ?? 0,
                ),
                _summaryRow(
                  'Needs review',
                  totals.entityCounts['needs_review'] ?? 0,
                ),
              ],
              if (totals.categoryCounts.isNotEmpty) ...[
                const Divider(height: 24),
                const Text(
                  'OSM matches by category',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                ...ConstructionCategory.values
                    .where(
                      (category) =>
                          (totals.categoryCounts[category.id] ?? 0) > 0,
                    )
                    .map(
                      (category) => _summaryRow(
                        category.label,
                        totals.categoryCounts[category.id] ?? 0,
                      ),
                    ),
              ],
              const Divider(height: 24),
              _summaryRow('With website', totals.withWebsite),
              _summaryRow('With phone', totals.withPhone),
              _summaryRow('With email', totals.withEmail),
              _summaryRow('With Facebook', totals.withFacebook),
              _summaryRow('With Instagram', totals.withInstagram),
              _summaryRow('With jobs/careers', totals.withCareers),
              _summaryRow('Website searches', totals.websiteSearches),
              const Divider(height: 24),
              _summaryRow(
                'Ready records for final publication',
                _pendingPublishCount,
              ),
              if (totals.failedDetails.isNotEmpty) ...[
                const Divider(height: 24),
                const Text(
                  'Failure reasons',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                ...totals.failureGroups.entries.map(
                  (entry) => Text('• ${entry.key}: ${entry.value}'),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Example failed postcodes',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                ...totals.failedDetails
                    .take(8)
                    .map(
                      (failure) => Text(
                        '• ${failure.postcode}: ${failure.shortMessage}',
                      ),
                    ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, int value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(child: Text(label)),
        const SizedBox(width: 16),
        Text(
          value.toString(),
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ],
    ),
  );

  Widget _statsCard(_ConstructionStateTotals totals) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xFFF4F6F7),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: const Color(0xFFD8E0E3)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Stats found · ${totals.state}',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _chip('Postcodes', totals.postcodesProcessed),
            _chip('Failed', totals.failedPostcodes),
            _chip('Found', totals.discovered),
            _chip('Unique', totals.uniqueCompanies),
            _chip('Added', totals.added),
            _chip('Updated', totals.updated),
            _chip('Web', totals.withWebsite),
            _chip('Email', totals.withEmail),
            _chip('Phone', totals.withPhone),
            _chip('Facebook', totals.withFacebook),
            _chip('Instagram', totals.withInstagram),
            _chip('Jobs', totals.withCareers),
            _chip('Ready records', _pendingPublishCount),
          ],
        ),
      ],
    ),
  );

  Widget _chip(String label, int value) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: const Color(0xFFD8E0E3)),
    ),
    child: Text('$label: $value'),
  );

  Widget _catalogueReviewCard(ConstructionCatalogueReviewResult review) =>
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFF6F2EA),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE0D5C3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Local catalogue quality',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _chip('Total', review.total),
                _chip('Employers', review.employers),
                _chip('Map ready', review.mapReady),
                _chip('Project sites', review.projectSites),
                _chip('Suppliers excluded', review.suppliersExcluded),
                _chip('Needs review', review.needsReview),
                _chip('No public contact', review.withoutPublicContact),
                _chip('Worksites corroborated', review.worksitesCorroborated),
                _chip('Operators linked', review.operatorsLinked),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _isImporting || _isReviewingCatalogue
                    ? null
                    : () => _reviewCatalogue(linkOperators: true),
                icon: _isReviewingCatalogue
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.fact_check_outlined),
                label: const Text('Review catalogue & link operators'),
              ),
            ),
          ],
        ),
      );

  Widget _enrichmentAnalysisCard() => Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Contact enrichment analysis',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          Text(
            '$_uniqueEmployersAnalysed unique employers · $_readyStateRecords eligible worksite records',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _chip('Completed', _enrichmentStatusCounts['completed'] ?? 0),
              _chip(
                'Identity unresolved',
                (_enrichmentStatusCounts['identity_unresolved'] ?? 0) +
                    (_enrichmentStatusCounts['no_verified_website'] ?? 0),
              ),
              _chip(
                'No public website',
                _enrichmentStatusCounts['no_public_website'] ?? 0,
              ),
              _chip(
                'Blocked',
                _enrichmentStatusCounts['blocked_by_website'] ?? 0,
              ),
              _chip('Retry later', _enrichmentStatusCounts['retry_later'] ?? 0),
              _chip('Timeout', _enrichmentStatusCounts['failure_timeout'] ?? 0),
              _chip(
                'HTTP 429',
                _enrichmentStatusCounts['failure_http_429'] ?? 0,
              ),
              _chip(
                'HTTP 5xx',
                _enrichmentStatusCounts['failure_http_5xx'] ?? 0,
              ),
              _chip(
                'Network / DNS',
                _enrichmentStatusCounts['failure_network_dns'] ?? 0,
              ),
              _chip(
                'Needs review',
                _enrichmentStatusCounts['needs_review'] ?? 0,
              ),
              _chip('Pending', _enrichmentStatusCounts['pending'] ?? 0),
            ],
          ),
          if (_needsReviewRows.isNotEmpty) ...[
            const Divider(height: 24),
            const Text(
              'Needs manual review',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            ..._needsReviewRows.map(
              (row) => ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text((row['name'] ?? 'Unnamed company').toString()),
                subtitle: Text((row['website'] ?? '').toString()),
                trailing: const Icon(Icons.edit_outlined),
                onTap: () => _openNeedsReview(row),
              ),
            ),
          ],
        ],
      ),
    ),
  );

  void _close() {
    if (_isImporting || _isImportingMinedex || _isBuilding) {
      _stopAndSaveEnrichment();
    }
    Navigator.pop(context, _didChange);
  }

  Widget _activeEnrichmentControls() => Material(
    elevation: 12,
    color: Colors.white,
    child: SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(20, 10, 20, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _currentCompanyName != null
                ? 'Working on $_currentCompanyName'
                : _currentPostcode != null && _currentPostcode != 'official'
                ? 'Working on postcode $_currentPostcode'
                : 'Preparing the state update…',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          _enrichmentControlButtons(),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final progress = _total == 0
        ? 0.0
        : (_processed / _total).clamp(0, 1).toDouble();
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _close();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'Add construction by state',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: _isImporting || _isImportingMinedex || _isBuilding
                ? 'Stop, save and go back'
                : 'Back',
            onPressed: _close,
          ),
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 0.5,
        ),
        backgroundColor: Colors.white,
        bottomNavigationBar: _isImporting || _isImportingMinedex || _isBuilding
            ? _activeEnrichmentControls()
            : null,
        body: Padding(
          padding: const EdgeInsets.all(20),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Build one state at a time from official sources, then enrich verified companies from their public corporate websites. OSM is only used by rescan actions. Results stay local until the final publication.',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 18),
                DropdownButtonFormField<String>(
                  initialValue: _selectedState,
                  decoration: InputDecoration(
                    labelText: 'Choose state',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  items: _states
                      .map(
                        (state) =>
                            DropdownMenuItem(value: state, child: Text(state)),
                      )
                      .toList(),
                  onChanged: _isImporting || _isBuilding
                      ? null
                      : (value) => unawaited(_selectState(value)),
                ),
                if (_selectedStatePostcodeCount != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'This will scan $_selectedStatePostcodeCount Regional Australia postcodes for $_selectedState.',
                    style: const TextStyle(color: Colors.black54),
                  ),
                ],
                if (_selectedState == 'WA') ...[
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEAF4F1),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Official WA mines & projects',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 5),
                        const Text(
                          'Adds current MINEDEX operators at their official worksite coordinates. Local only; nothing is sent to Firebase.',
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _chip('Map ready', _readyStateRecords),
                            if (_minedexResult != null) ...[
                              _chip(
                                'Verified links',
                                _minedexResult!.officialLinks,
                              ),
                              _chip(
                                'Likely eligible regional area',
                                _minedexResult!.regionalMapReady,
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Attribution: Based on Department of Mines, Petroleum and Exploration material · CC BY 4.0. Postcodes use ABS Postal Areas 2021 and are statistical approximations.',
                          style: TextStyle(fontSize: 11, color: Colors.black54),
                        ),
                      ],
                    ),
                  ),
                ],
                if (_selectedState != null && _selectedState != 'WA') ...[
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEAF4F1),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _selectedState == 'NSW'
                              ? 'Official national + NSW mines'
                              : 'Official national operating mines',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          _selectedState == 'NSW'
                              ? 'Imports national and NSW mine layers plus official EPA-licensed mining, extractive, concrete, road and rail premises. EPA corporate licence holders are corroborated as premises operators; personal and public-sector holders stay local-only.'
                              : 'Imports Geoscience Australia operating mines as local worksites. Employer links are added only when an official state source corroborates an operator or contractor.',
                        ),
                        if (_nationalMinesResult != null ||
                            _nswMinesResult != null ||
                            _nswCoalProducersResult != null ||
                            _nswEpaPremisesResult != null ||
                            _nswMembersResult != null ||
                            _nswCouncilMinesResult != null) ...[
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              if (_nationalMinesResult != null)
                                _chip(
                                  'National worksites',
                                  _nationalMinesResult!.worksites,
                                ),
                              if (_nswMinesResult != null)
                                _chip(
                                  'NSW worksites',
                                  _nswMinesResult!.worksites,
                                ),
                              if (_nswCoalProducersResult != null)
                                _chip(
                                  'Coal employer links',
                                  _nswCoalProducersResult!.linkedWorksites,
                                ),
                              if (_nswEpaPremisesResult != null) ...[
                                _chip(
                                  'EPA premises',
                                  _nswEpaPremisesResult!.premises,
                                ),
                                _chip(
                                  'EPA employer links',
                                  _nswEpaPremisesResult!.employerLinks,
                                ),
                              ],
                              if (_nswMembersResult != null)
                                _chip(
                                  'Additional employers',
                                  _nswMembersResult!.members,
                                ),
                              if (_nswCouncilMinesResult != null)
                                _chip(
                                  'Additional employer links',
                                  _nswCouncilMinesResult!.employerLinks,
                                ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 6),
                        Text(
                          _selectedState == 'NSW'
                              ? 'Attribution: Geoscience Australia, Geological Survey of NSW and NSW EPA public register · CC BY 4.0.'
                              : 'Attribution: © Commonwealth of Australia (Geoscience Australia) 2026 · CC BY 4.0.',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (_domainMetrics.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _chip('Employers', _domainMetrics['employers'] ?? 0),
                      _chip('Worksites', _domainMetrics['worksites'] ?? 0),
                      _chip(
                        'Linked worksites',
                        _domainMetrics['linked_worksites'] ?? 0,
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  onPressed: _isImporting || _isImportingMinedex || _isBuilding
                      ? null
                      : () => _buildOrUpdateState(),
                  icon: const Icon(Icons.manage_search_rounded),
                  label: const Text('Build or update this state'),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 52),
                    backgroundColor: Colors.blueGrey.shade700,
                    foregroundColor: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: const Text('Advanced recovery'),
                  subtitle: const Text(
                    'Only use if an official source changed or a previous run was interrupted.',
                  ),
                  children: [
                    OutlinedButton.icon(
                      onPressed:
                          _isImporting || _isImportingMinedex || _isBuilding
                          ? null
                          : () => _buildOrUpdateState(forceDiscovery: true),
                      icon: const Icon(Icons.restart_alt_rounded),
                      label: const Text('Repair sources and rebuild'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 52),
                      ),
                    ),
                  ],
                ),
                if (_isImporting) ...[
                  const SizedBox(height: 18),
                  LinearProgressIndicator(
                    value: progress == 0 ? null : progress,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _currentPostcode == 'official'
                        ? 'Enriching $_processed/$_total unique companies for ${_selectedState ?? ''}...'
                        : _total == 0
                        ? 'Preparing import for ${_selectedState ?? ''}...'
                        : 'Importing $_processed/$_total postcodes for ${_selectedState ?? ''}...',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  if (_currentPostcode != null) ...[
                    const SizedBox(height: 4),
                    if (_currentPostcode != 'official')
                      Text('Current postcode: $_currentPostcode'),
                    if (_currentCompanyName != null)
                      Text(
                        'Searching: $_currentCompanyName'
                        '${_currentCompanyIndex == null ? '' : ' · $_currentCompanyIndex/$_currentCompanyTotal'}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    if (_currentStatus != null) Text(_currentStatus!),
                    if (_currentPostcode != 'official') ...[
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerRight,
                        child: OutlinedButton.icon(
                          onPressed: _skipCurrentPostcode,
                          icon: const Icon(Icons.fast_forward_rounded),
                          label: const Text('Skip and continue'),
                        ),
                      ),
                    ],
                  ] else if (_currentStatus != null)
                    Text(_currentStatus!),
                ],
                if (_latestTotals != null) ...[
                  const SizedBox(height: 16),
                  _statsCard(_latestTotals!),
                ],
                if (_enrichmentStatusCounts.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _enrichmentAnalysisCard(),
                ],
                if (_catalogueReview != null) ...[
                  const SizedBox(height: 16),
                  _catalogueReviewCard(_catalogueReview!),
                ] else if (_isReviewingCatalogue) ...[
                  const SizedBox(height: 16),
                  const LinearProgressIndicator(),
                  const SizedBox(height: 8),
                  const Text('Reviewing the local construction catalogue...'),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ConstructionStateTotals {
  _ConstructionStateTotals({required this.state});

  final String state;
  int postcodesProcessed = 0;
  int skippedByCache = 0;
  int skippedByUser = 0;
  int failedPostcodes = 0;
  int discovered = 0;
  int added = 0;
  int updated = 0;
  int skippedDuplicates = 0;
  int withWebsite = 0;
  int withPhone = 0;
  int withEmail = 0;
  int withFacebook = 0;
  int withInstagram = 0;
  int withCareers = 0;
  int websiteSearches = 0;
  final Set<String> changedCompanyIds = <String>{};
  final List<_ConstructionPostcodeFailure> failedDetails = [];
  final Map<String, int> categoryCounts = <String, int>{};
  final Map<String, int> entityCounts = <String, int>{};

  int get uniqueCompanies => changedCompanyIds.length;
  int get successfulQueries =>
      postcodesProcessed - failedPostcodes - skippedByCache - skippedByUser;
  Map<String, int> get failureGroups {
    final groups = <String, int>{};
    for (final failure in failedDetails) {
      groups.update(
        failure.shortMessage,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
    }
    return groups;
  }

  void add(OsmConstructionImportResult result) {
    postcodesProcessed++;
    if (result.skippedByCooldown) {
      skippedByCache++;
      return;
    }
    discovered += result.discovered;
    added += result.added;
    updated += result.updated;
    skippedDuplicates += result.skippedDuplicates;
    changedCompanyIds.addAll(result.changedConstructionIds);
    final summary = result.summary;
    withWebsite += summary.withWebsite;
    withPhone += summary.withPhone;
    withEmail += summary.withEmail;
    withFacebook += summary.withFacebook;
    withInstagram += summary.withInstagram;
    withCareers += summary.withCareers;
    websiteSearches += summary.websiteDiscoveryAttempted;
    for (final entry in summary.categoryCounts.entries) {
      categoryCounts.update(
        entry.key,
        (count) => count + entry.value,
        ifAbsent: () => entry.value,
      );
    }
    for (final entry in summary.entityCounts.entries) {
      entityCounts.update(
        entry.key,
        (count) => count + entry.value,
        ifAbsent: () => entry.value,
      );
    }
  }

  void addSkippedByUser() {
    postcodesProcessed++;
    skippedByUser++;
  }

  void addFailed(String postcode, Object error) {
    postcodesProcessed++;
    failedPostcodes++;
    failedDetails.add(
      _ConstructionPostcodeFailure(postcode: postcode, error: error),
    );
  }
}

class _ConstructionPostcodeFailure {
  const _ConstructionPostcodeFailure({
    required this.postcode,
    required this.error,
  });

  final String postcode;
  final Object error;

  String get shortMessage {
    final raw = error.toString();
    if (raw.contains('All Overpass endpoints failed')) {
      return 'OSM/Overpass unavailable';
    }
    if (error is TimeoutException || raw.contains('TimeoutException')) {
      return 'postcode timed out';
    }
    return raw.length <= 90 ? raw : '${raw.substring(0, 90)}...';
  }
}

class _ConstructionSkipSignal {
  const _ConstructionSkipSignal();
}
