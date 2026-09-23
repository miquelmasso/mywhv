import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/construction_category.dart';
import '../services/construction_pending_publish_service.dart';
import '../services/construction_sqlite_store.dart';
import '../services/map_markers_service.dart';
import '../services/osm_construction_import_service.dart';

class AddConstructionByPostcodePage extends StatefulWidget {
  const AddConstructionByPostcodePage({super.key});

  @override
  State<AddConstructionByPostcodePage> createState() =>
      _AddConstructionByPostcodePageState();
}

class _AddConstructionByPostcodePageState
    extends State<AddConstructionByPostcodePage> {
  static const _lastImportPostcodeKey = 'last_osm_construction_postcode';

  final TextEditingController _postcodeController = TextEditingController(
    text: '4802',
  );
  final OsmConstructionImportService _importService =
      OsmConstructionImportService();

  String _result = '';
  String _progress = '';
  String? _lastImportPostcode;
  bool _loading = false;
  bool _forceRefresh = false;
  bool _didImportChanges = false;
  int _pendingPublishCount = 0;

  @override
  void initState() {
    super.initState();
    _loadLastImportPostcode();
    _loadPendingPublishCount();
  }

  @override
  void dispose() {
    _postcodeController.dispose();
    super.dispose();
  }

  Future<void> _loadLastImportPostcode() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _lastImportPostcode = prefs.getString(_lastImportPostcodeKey);
    });
  }

  Future<void> _loadPendingPublishCount() async {
    final pending = await ConstructionPendingPublishService.instance
        .getPendingIds();
    if (mounted) setState(() => _pendingPublishCount = pending.length);
  }

  String? _normalizedPostcode() {
    final input = _postcodeController.text.trim();
    if (input.isEmpty) return null;
    final postcode = input.padLeft(4, '0');
    return RegExp(r'^\d{4}$').hasMatch(postcode) ? postcode : null;
  }

  void _showSnack(String text, {Color? color}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: color ?? Colors.blueGrey.shade800,
      ),
    );
  }

  void _handleProgress(OsmConstructionImportProgress progress) {
    if (!mounted) return;
    final company = progress.companyName?.trim() ?? '';
    final position =
        progress.companyIndex != null && progress.companyTotal != null
        ? ' ${progress.companyIndex}/${progress.companyTotal}'
        : '';
    setState(() {
      _progress = [
        progress.message ?? progress.stage,
        if (company.isNotEmpty) '$company$position',
      ].join(' · ');
    });
  }

  Future<void> _importFromOsm() async {
    final postcode = _normalizedPostcode();
    if (postcode == null) {
      _showSnack('Enter a valid 4-digit postcode.', color: Colors.orange);
      return;
    }

    setState(() {
      _loading = true;
      _result = '';
      _progress = 'Preparing construction import';
    });

    try {
      final result = await _importService.importForPostcode(
        postcode,
        force: _forceRefresh,
        enrichWebContacts: true,
        uploadChangedToFirebase: false,
        onProgress: _handleProgress,
      );
      if (!mounted) return;

      if (result.skippedByCooldown) {
        _showSnack(
          result.message ?? 'This postcode was scanned recently.',
          color: Colors.orange,
        );
        return;
      }
      if (result.message != null && result.discovered == 0) {
        _showSnack(result.message!, color: Colors.orange);
        return;
      }

      if (result.changedConstructionIds.isNotEmpty) {
        _pendingPublishCount = await ConstructionPendingPublishService.instance
            .markPending(result.changedConstructionIds);
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_lastImportPostcodeKey, result.postcode);
      _lastImportPostcode = result.postcode;
      _didImportChanges =
          _didImportChanges || result.added > 0 || result.updated > 0;

      if (mounted) setState(() => _loading = false);
      await _showImportSummary(result);
      if (!mounted) return;
      setState(() {
        _result =
            'OSM ${result.postcode}: ${result.discovered} found, '
            '${result.added} added, ${result.updated} updated, '
            '${result.skippedDuplicates} duplicates, '
            '${result.enriched} enriched, '
            '$_pendingPublishCount pending publication.';
      });
    } catch (error) {
      if (!mounted) return;
      _showSnack(
        'OpenStreetMap import failed: ${_shortError(error)}',
        color: Colors.red,
      );
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _progress = '';
        });
      }
    }
  }

  Future<void> _deleteLatestPostcode() async {
    final fallback = _normalizedPostcode();
    final postcode = (_lastImportPostcode?.trim().isNotEmpty ?? false)
        ? _lastImportPostcode!.trim().padLeft(4, '0')
        : fallback;
    if (postcode == null) {
      _showSnack('Import a postcode before deleting.', color: Colors.orange);
      return;
    }

    setState(() => _loading = true);
    try {
      final store = ConstructionSqliteStore.instance;
      await store.init();
      final before = await store.getAll();
      final deletedIds = before
          .where((company) {
            final companyPostcode =
                (company['postcode_display'] ?? company['postcode'] ?? '')
                    .toString()
                    .padLeft(4, '0');
            final source = (company['source'] ?? '').toString();
            final sourceId = (company['source_place_id'] ?? '').toString();
            return companyPostcode == postcode &&
                (source == 'osm' || sourceId.startsWith('osm:'));
          })
          .map(
            (company) => (company['docId'] ?? company['id'] ?? '').toString(),
          )
          .where((id) => id.isNotEmpty)
          .toList(growable: false);

      final deleted = await store.deleteOsmCompaniesForPostcode(postcode);
      if (deleted == 0) {
        _showSnack(
          'No OSM construction companies found for $postcode.',
          color: Colors.orange,
        );
        return;
      }
      await MapMarkersService.deleteConstructionCompaniesFromFirebase(
        deletedIds,
      );
      await ConstructionPendingPublishService.instance.removePending(
        deletedIds,
      );
      await _loadPendingPublishCount();
      await MapMarkersService.replaceLocalConstructionCompanies(
        await store.getAll(),
      );
      _didImportChanges = true;
      _showSnack(
        'Deleted $deleted construction companies from $postcode.',
        color: Colors.redAccent,
      );
    } catch (error) {
      if (!mounted) return;
      _showSnack('Construction deletion failed.', color: Colors.red);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _showImportSummary(OsmConstructionImportResult result) async {
    final summary = result.summary;
    final contacts = summary.emailContacts.take(10).toList();
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('OSM construction summary · ${result.postcode}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _summaryRow('Found in OSM', result.discovered),
              _summaryRow('Added', result.added),
              _summaryRow('Updated', result.updated),
              _summaryRow('Duplicates skipped', result.skippedDuplicates),
              if (summary.categoryCounts.isNotEmpty) ...[
                const Divider(height: 24),
                const Text(
                  'OSM matches by category',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                ...ConstructionCategory.values
                    .where(
                      (category) =>
                          (summary.categoryCounts[category.id] ?? 0) > 0,
                    )
                    .map(
                      (category) => _summaryRow(
                        category.label,
                        summary.categoryCounts[category.id] ?? 0,
                      ),
                    ),
              ],
              const Divider(height: 24),
              _summaryRow('Processed for contacts', summary.processed),
              _summaryRow('With website', summary.withWebsite),
              _summaryRow('With phone', summary.withPhone),
              _summaryRow('With email', summary.withEmail),
              _summaryRow('With Facebook', summary.withFacebook),
              _summaryRow('With Instagram', summary.withInstagram),
              _summaryRow('With jobs/careers', summary.withCareers),
              const Divider(height: 24),
              _summaryRow(
                'Website searches',
                summary.websiteDiscoveryAttempted,
              ),
              _summaryRow('Websites from OSM', summary.websiteFromOsm),
              _summaryRow('Websites discovered', summary.websiteDiscovered),
              const SizedBox(height: 14),
              const Text(
                'Companies with email',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              if (contacts.isEmpty)
                const Text('No valid email was found.')
              else
                ...contacts.map(
                  (contact) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text('• ${contact.name}\n  ${contact.email}'),
                  ),
                ),
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

  String _shortError(Object error) {
    final raw = error.toString();
    if (raw.contains('All Overpass endpoints failed')) {
      return 'OSM/Overpass is unavailable. Try Force rescan later.';
    }
    if (raw.length <= 120) return raw;
    return '${raw.substring(0, 120)}...';
  }

  void _close() => Navigator.pop(context, _didImportChanges);

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _close();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'Construction management',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _close,
          ),
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 0.5,
        ),
        backgroundColor: Colors.white,
        body: Padding(
          padding: const EdgeInsets.all(20),
          child: SingleChildScrollView(
            child: Column(
              children: [
                const SizedBox(height: 10),
                const Text(
                  'Search construction by postcode',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 25),
                TextField(
                  controller: _postcodeController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Enter postcode',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.public),
                      onPressed: _loading ? null : _importFromOsm,
                    ),
                  ),
                  onSubmitted: (_) {
                    if (!_loading) _importFromOsm();
                  },
                ),
                const SizedBox(height: 20),
                if (_loading) ...[
                  const CircularProgressIndicator(),
                  if (_progress.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(_progress, textAlign: TextAlign.center),
                  ],
                ] else if (_result.isNotEmpty)
                  Text(
                    _result,
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.green.shade700,
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                const SizedBox(height: 30),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF4F6F7),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFD8E0E3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'OpenStreetMap construction import',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Uses the postcode area to find builders, trades, construction offices and related businesses. No API key or billing is required.',
                        style: TextStyle(color: Colors.black54, height: 1.35),
                      ),
                      const SizedBox(height: 10),
                      Material(
                        type: MaterialType.transparency,
                        child: SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Force rescan'),
                          subtitle: const Text(
                            'Ignore the 30-day postcode scan cache.',
                          ),
                          value: _forceRefresh,
                          onChanged: _loading
                              ? null
                              : (value) =>
                                    setState(() => _forceRefresh = value),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _loading ? null : _importFromOsm,
                          icon: const Icon(Icons.construction),
                          label: const Text('Import from OpenStreetMap'),
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size(double.infinity, 50),
                            backgroundColor: Colors.blueGrey.shade700,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  onPressed: _loading ? null : _deleteLatestPostcode,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Delete latest postcode'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
