import 'package:flutter/material.dart';

import '../services/construction_catalog_pipeline_service.dart';
import '../services/construction_pending_publish_service.dart';
import '../services/construction_sqlite_store.dart';
import '../services/osm_construction_import_service.dart';
import 'construction_edit_page.dart';

class ConstructionCatalogPipelinePage extends StatefulWidget {
  const ConstructionCatalogPipelinePage({super.key});

  @override
  State<ConstructionCatalogPipelinePage> createState() =>
      _ConstructionCatalogPipelinePageState();
}

class _ConstructionCatalogPipelinePageState
    extends State<ConstructionCatalogPipelinePage> {
  final _pipeline = ConstructionCatalogPipelineService();
  bool _running = false;
  bool _publishing = false;
  ConstructionPipelineProgress? _progress;
  ConstructionPipelineResult? _result;
  List<Map<String, dynamic>> _needsReview = const [];
  int _pendingPublish = 0;
  ConstructionContactEnrichmentControl? _enrichmentControl;

  @override
  void initState() {
    super.initState();
    _refreshPending();
    _loadNeedsReview();
  }

  Future<void> _loadNeedsReview() async {
    final store = ConstructionSqliteStore.instance;
    await store.init();
    final rows = (await store.getAll())
        .where(
          (row) =>
              (row['contact_enrichment_status'] ?? '').toString() ==
              'needs_review',
        )
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
    if (mounted) {
      setState(() {
        _needsReview = rows;
        _result?.enrichmentStatusCounts['needs_review'] = rows.length;
      });
    }
  }

  Future<void> _refreshPending() async {
    final ids = await ConstructionPendingPublishService.instance
        .getPublishablePendingIds();
    if (mounted) setState(() => _pendingPublish = ids.length);
  }

  Future<void> _run({
    required bool includeOsm,
    required bool force,
    required bool retryIncomplete,
  }) async {
    if (_running || _publishing) return;
    setState(() {
      _running = true;
      _result = null;
      _progress = null;
    });
    final enrichmentControl = ConstructionContactEnrichmentControl();
    _enrichmentControl = enrichmentControl;
    try {
      final result = await _pipeline.runNational(
        forceOsm: force,
        includeOsmGapScan: includeOsm,
        retryIncompleteEnrichment: retryIncomplete,
        forceEnrichment: force,
        enrichmentControl: enrichmentControl,
        onProgress: (progress) {
          if (mounted) setState(() => _progress = progress);
        },
      );
      if (!mounted) return;
      setState(() {
        _result = result;
        _needsReview = result.needsReview;
      });
      await _refreshPending();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Pipeline failed: $error'),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      _enrichmentControl = null;
      if (mounted) setState(() => _running = false);
    }
  }

  void _skipCurrentCompany() {
    final skipped = _enrichmentControl?.skipCurrentCompany() ?? false;
    if (!mounted || !skipped) return;
    setState(() {});
  }

  void _stopAndSave() {
    _enrichmentControl?.stopAndSave();
    if (mounted) setState(() {});
  }

  Widget _enrichmentControlButtons(ConstructionPipelineProgress progress) =>
      LayoutBuilder(
        builder: (context, constraints) {
          final skip = ElevatedButton.icon(
            onPressed: progress.companyName == null
                ? null
                : _skipCurrentCompany,
            icon: const Icon(Icons.skip_next_rounded),
            label: const Text('Skip this company'),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              backgroundColor: Colors.orange.shade700,
              foregroundColor: Colors.white,
            ),
          );
          final stop = ElevatedButton.icon(
            onPressed: _stopAndSave,
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

  Future<void> _publish() async {
    if (_running || _publishing || _pendingPublish == 0) return;
    setState(() => _publishing = true);
    try {
      final result = await ConstructionPendingPublishService.instance
          .publishPendingAndExportJson();
      if (!mounted) return;
      setState(() => _pendingPublish = result.remaining);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${result.uploaded} records uploaded to Firebase; JSON contains ${result.jsonCount}.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Upload failed. The local publication queue was kept.'),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  Future<void> _reviewCompany(Map<String, dynamic> row) async {
    final result = await Navigator.of(context).push<ConstructionEditResult>(
      MaterialPageRoute(
        builder: (_) => ConstructionEditPage(
          companyId: (row['docId'] ?? row['id'] ?? '').toString(),
          initialCompany: Map<String, dynamic>.from(row),
        ),
      ),
    );
    if (!mounted) return;
    await _loadNeedsReview();
    await _refreshPending();
    if (!mounted) return;
    if (result?.changed == true &&
        result?.previousStatus == 'needs_review' &&
        result?.newStatus != 'needs_review') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Construction review saved locally.')),
      );
    }
  }

  void _close() => Navigator.pop(context, _result != null);

  @override
  Widget build(BuildContext context) {
    final progress = _progress;
    final ratio = progress == null || progress.total == 0
        ? null
        : (progress.processed / progress.total).clamp(0.0, 1.0);
    return PopScope(
      canPop: !_running && !_publishing,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && !_running && !_publishing) _close();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('National construction pipeline'),
          leading: IconButton(
            onPressed: _running || _publishing ? null : _close,
            icon: const Icon(Icons.arrow_back),
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              'Official sources come first. Corporate websites enrich missing public contacts; OSM is used only as a gap finder.',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            const Card(
              child: ListTile(
                leading: Icon(Icons.cloud_off_outlined),
                title: Text('Map first, Firebase only on button 4'),
                subtitle: Text(
                  'Eligible results appear on the local map and enter the publication queue automatically.',
                ),
              ),
            ),
            const SizedBox(height: 10),
            _actionButton(
              icon: Icons.manage_search_rounded,
              label: '1 · Find and enrich all',
              description:
                  'Import official sources and enrich every pending verified company.',
              onPressed: () =>
                  _run(includeOsm: false, force: false, retryIncomplete: false),
            ),
            _actionButton(
              icon: Icons.restart_alt_rounded,
              label: '2 · Force a full rescan',
              description:
                  'Ignore caches, rescan OSM gaps and recheck all verified companies.',
              onPressed: () =>
                  _run(includeOsm: true, force: true, retryIncomplete: true),
            ),
            _actionButton(
              icon: Icons.sync_rounded,
              label: '3 · Resume contact enrichment',
              description:
                  'Keep completed companies unchanged and retry only pending or temporarily failed contact lookups. OSM is not scanned.',
              onPressed: () =>
                  _run(includeOsm: false, force: false, retryIncomplete: true),
            ),
            _actionButton(
              icon: Icons.cloud_upload_outlined,
              label: _publishing
                  ? 'Uploading...'
                  : '4 · Upload $_pendingPublish ready records to Firebase',
              description:
                  'The only action that publishes externally and generates the JSON.',
              onPressed: _pendingPublish == 0 ? null : _publish,
              filled: false,
            ),
            if (progress != null) ...[
              const SizedBox(height: 16),
              LinearProgressIndicator(value: ratio),
              const SizedBox(height: 8),
              Text(progress.message),
              if (progress.companyName != null)
                Text(
                  'Searching: ${progress.companyName}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              if (progress.stage ==
                      ConstructionPipelineStage.enrichingOfficialContacts &&
                  _enrichmentControl != null) ...[
                const SizedBox(height: 12),
                _enrichmentControlButtons(progress),
              ],
              if (progress.postcode != null)
                Text(
                  'Postcode ${progress.postcode} · ${progress.processed}/${progress.total}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
            ],
            if (_result != null) ...[
              const SizedBox(height: 16),
              _ResultCard(result: _result!),
            ],
            if (_needsReview.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                'Needs manual review (${_needsReview.length})',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              ..._needsReview.map(
                (row) => Card(
                  child: ListTile(
                    title: Text((row['name'] ?? 'Unnamed company').toString()),
                    subtitle: Text(
                      (row['website'] ?? 'Several possible websites')
                          .toString(),
                    ),
                    trailing: const Icon(Icons.edit_outlined),
                    onTap: () => _reviewCompany(row),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    required String description,
    required VoidCallback? onPressed,
    bool filled = true,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: double.infinity,
          child: filled
              ? ElevatedButton.icon(
                  onPressed: _running || _publishing ? null : onPressed,
                  icon: Icon(icon),
                  label: Text(label),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 52),
                  ),
                )
              : OutlinedButton.icon(
                  onPressed: _running || _publishing ? null : onPressed,
                  icon: Icon(icon),
                  label: Text(label),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 52),
                  ),
                ),
        ),
        const SizedBox(height: 3),
        Text(
          description,
          style: const TextStyle(fontSize: 12, color: Colors.black54),
        ),
      ],
    ),
  );
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.result});

  final ConstructionPipelineResult result;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Analysis',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          _row('Completed', _status('completed')),
          _row(
            'Identity unresolved',
            _status('identity_unresolved') + _status('no_verified_website'),
          ),
          _row('No public website', _status('no_public_website')),
          _row('Blocked by website', _status('blocked_by_website')),
          _row('Retry later', _status('retry_later')),
          _row('Timeout', _status('failure_timeout')),
          _row('HTTP 429', _status('failure_http_429')),
          _row('HTTP 5xx', _status('failure_http_5xx')),
          _row('Network / DNS', _status('failure_network_dns')),
          _row('Needs review', _status('needs_review')),
          _row('Pending', _status('pending')),
          if (result.enrichmentCancelled)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Text(
                'Stopped safely. Completed companies were saved; remaining companies can be resumed.',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          _row('Processed this run', result.officialContactsChecked),
          _row('Skipped this run', result.enrichmentSkipped),
          _row('Still resumable', result.enrichmentRemaining),
          const Divider(height: 24),
          _row('Official worksites', result.officialWorksitesImported),
          _row('OSM places discovered', result.osmDiscovered),
          _row('Eligible on local map', result.mapEligible),
          _row('Hidden: no contact', result.hiddenWithoutContact),
          _row('Hidden: no coordinates', result.hiddenWithoutCoordinates),
        ],
      ),
    ),
  );

  int _status(String key) => result.enrichmentStatusCounts[key] ?? 0;

  Widget _row(String label, int value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        Expanded(child: Text(label)),
        Text('$value', style: const TextStyle(fontWeight: FontWeight.w700)),
      ],
    ),
  );
}
