import 'dart:async';

import 'package:flutter/material.dart';
import '../services/map_markers_service.dart';
import '../services/osm_restaurant_import_service.dart';
import '../services/postcode_state_helper.dart';
import '../services/restaurant_sqlite_store.dart';
import '../services/visa_postcodes_sqlite_store.dart';

class AddRestaurantsByStatePage extends StatefulWidget {
  const AddRestaurantsByStatePage({super.key});

  @override
  State<AddRestaurantsByStatePage> createState() =>
      _AddRestaurantsByStatePageState();
}

class _AddRestaurantsByStatePageState extends State<AddRestaurantsByStatePage> {
  final OsmRestaurantImportService _osmImportService =
      OsmRestaurantImportService();
  final VisaPostcodesSqliteStore _visaStore = VisaPostcodesSqliteStore.instance;

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
  bool _forceOsmRefresh = false;
  int _processed = 0;
  int _total = 0;
  int? _selectedStatePostcodeCount;
  String? _currentPostcode;
  String? _currentRestaurantName;
  int? _currentRestaurantIndex;
  int? _currentRestaurantTotal;
  String? _currentRestaurantStatus;
  _StateOsmImportTotals? _latestTotals;
  Completer<void>? _skipCompleter;

  Future<void> _startImport() async {
    if (_selectedState == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Select a state.')));
      return;
    }

    setState(() {
      _isImporting = true;
      _processed = 0;
      _total = 0;
      _currentPostcode = null;
      _currentRestaurantName = null;
      _currentRestaurantIndex = null;
      _currentRestaurantTotal = null;
      _currentRestaurantStatus = null;
      _latestTotals = _StateOsmImportTotals(state: _selectedState!);
    });

    try {
      final postcodes = await _loadHospitalityPostcodesForSelectedState();
      if (postcodes.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'No Tourism & Hospitality postcodes found for ${_selectedState!}.',
            ),
          ),
        );
        return;
      }
      final totals =
          _latestTotals ?? _StateOsmImportTotals(state: _selectedState!);

      if (!mounted) return;
      setState(() => _total = postcodes.length);

      for (final postcodeStr in postcodes) {
        try {
          final result = await _awaitOrSkip(
            _osmImportService.importForPostcode(
              postcodeStr,
              force: _forceOsmRefresh,
              enrichWebContacts: true,
              uploadChangedToFirebase: false,
              onProgress: _handleOsmProgress,
            ),
            postcodeStr,
          );
          if (result != null) {
            totals.add(result);
          } else {
            totals.addSkippedByUser(postcodeStr);
          }
        } catch (error) {
          totals.addFailed(postcodeStr, error);
        }
        if (!mounted) return;
        setState(() {
          _latestTotals = totals;
          _processed++;
        });
      }

      if (!mounted) return;
      setState(() {
        _currentPostcode = null;
        _currentRestaurantName = null;
        _currentRestaurantIndex = null;
        _currentRestaurantTotal = null;
        _currentRestaurantStatus = 'Uploading OSM restaurants to Firebase...';
      });
      try {
        totals.firebaseUploaded = await _uploadStateImportToFirebase(totals);
      } catch (error) {
        totals.firebaseUploadFailed = true;
        totals.firebaseUploadError = error.toString();
      }

      if (!mounted) return;
      setState(() {
        _latestTotals = totals;
        _currentRestaurantStatus = null;
      });
      await _showStateImportSummaryDialog(totals);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'We could not import restaurants for this state right now.',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isImporting = false);
      }
      _skipCompleter = null;
      _currentPostcode = null;
      _currentRestaurantName = null;
      _currentRestaurantIndex = null;
      _currentRestaurantTotal = null;
      _currentRestaurantStatus = null;
    }
  }

  Future<void> _selectState(String? value) async {
    setState(() {
      _selectedState = value;
      _selectedStatePostcodeCount = null;
      _latestTotals = null;
      _processed = 0;
      _total = 0;
      _currentPostcode = null;
      _currentRestaurantName = null;
      _currentRestaurantIndex = null;
      _currentRestaurantTotal = null;
      _currentRestaurantStatus = null;
    });
    if (value == null) return;

    final postcodes = await _loadHospitalityPostcodesForSelectedState();
    if (!mounted || _selectedState != value) return;
    setState(() {
      _selectedStatePostcodeCount = postcodes.length;
    });
  }

  void _handleOsmProgress(OsmRestaurantImportProgress progress) {
    if (!mounted) return;
    setState(() {
      _currentPostcode = progress.postcode;
      _currentRestaurantName = progress.restaurantName;
      _currentRestaurantIndex = progress.restaurantIndex;
      _currentRestaurantTotal = progress.restaurantTotal;
      _currentRestaurantStatus =
          progress.message ?? _labelForProgressStage(progress.stage);
    });
  }

  String _labelForProgressStage(String stage) {
    return switch (stage) {
      'locating_postcode' => 'Locating postcode',
      'querying_osm' => 'Finding restaurants in OSM',
      'enriching_restaurant' => 'Searching contact data',
      'restaurant_timeout' => 'Skipped after 3 minutes without new data',
      'restaurant_enriched' => 'New data found',
      'restaurant_checked' => 'No new data found',
      _ => stage,
    };
  }

  Future<int> _uploadStateImportToFirebase(_StateOsmImportTotals totals) async {
    if (totals.changedRestaurantIds.isEmpty) return 0;

    final store = RestaurantSqliteStore.instance;
    await store.init();
    final changedIds = totals.changedRestaurantIds;
    final changedRestaurants = (await store.getAll())
        .where((row) {
          final id = (row['docId'] ?? row['id'] ?? '').toString();
          return changedIds.contains(id);
        })
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
    if (changedRestaurants.isEmpty) return 0;

    await MapMarkersService.upsertRestaurantsToFirebase(changedRestaurants);
    return changedRestaurants.length;
  }

  Future<List<String>> _loadHospitalityPostcodesForSelectedState() async {
    final state = _selectedState;
    if (state == null) return const <String>[];

    await _visaStore.init();
    final entries = await _visaStore.getAll();
    final postcodes = <String>{};

    for (final entry in entries) {
      final industry = (entry['industry'] ?? entry['id'] ?? '')
          .toString()
          .toLowerCase();
      if (!industry.contains('hospitality')) continue;

      final rawPostcodes = entry['postcodes'];
      if (rawPostcodes is! List) continue;
      for (final raw in rawPostcodes) {
        final postcode = raw.toString().padLeft(4, '0');
        if (!RegExp(r'^\d{4}$').hasMatch(postcode)) continue;
        if (getStateFromPostcode(postcode) == state) {
          postcodes.add(postcode);
        }
      }
    }

    final sorted = postcodes.toList();
    sorted.sort();
    return sorted;
  }

  Future<void> _showStateImportSummaryDialog(
    _StateOsmImportTotals totals,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('OSM state import · ${totals.state}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _summaryRow('Postcodes processed', totals.postcodesProcessed),
                _summaryRow(
                  'Postcodes skipped by cache',
                  totals.skippedByCache,
                ),
                _summaryRow('Postcodes skipped by user', totals.skippedByUser),
                _summaryRow('Postcodes failed', totals.failedPostcodes),
                _summaryRow('Restaurants found in OSM', totals.discovered),
                _summaryRow('Added', totals.added),
                _summaryRow('Updated', totals.updated),
                _summaryRow('Duplicates skipped', totals.skippedDuplicates),
                const Divider(height: 24),
                _summaryRow('With website', totals.withWebsite),
                _summaryRow('With phone', totals.withPhone),
                _summaryRow('With email', totals.withEmail),
                _summaryRow('With Facebook', totals.withFacebook),
                _summaryRow('With Instagram', totals.withInstagram),
                _summaryRow('With jobs/careers', totals.withCareers),
                const Divider(height: 24),
                _summaryRow('Uploaded to Firebase', totals.firebaseUploaded),
                if (totals.firebaseUploadFailed)
                  Text(
                    'Firebase upload failed: ${totals.firebaseUploadError ?? 'unknown error'}',
                    style: TextStyle(color: Colors.red.shade700, height: 1.25),
                  ),
                const Divider(height: 24),
                _summaryRow('Websites from OSM', totals.websiteFromOsm),
                _summaryRow('Websites discovered', totals.websiteDiscovered),
                if (totals.websiteDiscovered > 0)
                  Padding(
                    padding: const EdgeInsets.only(left: 12, top: 4),
                    child: Text(
                      'Wikidata: ${totals.websiteFromWikidata} · '
                      'brands: ${totals.websiteFromKnownBrand} · '
                      'domains: ${totals.websiteFromProbableDomain}',
                      style: TextStyle(
                        color: Colors.grey.shade700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                if (totals.failedDetails.isNotEmpty) ...[
                  const Divider(height: 24),
                  Text(
                    'Failed postcodes',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...totals.failedDetails
                      .take(8)
                      .map(
                        (failure) => Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text(
                            '• ${failure.postcode}: ${failure.shortMessage}',
                            style: TextStyle(
                              color: Colors.red.shade700,
                              height: 1.25,
                            ),
                          ),
                        ),
                      ),
                  if (totals.failedDetails.length > 8)
                    Text(
                      '+ ${totals.failedDetails.length - 8} more',
                      style: TextStyle(color: Colors.grey.shade700),
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
        );
      },
    );
  }

  Widget _summaryRow(String label, int value) {
    return Padding(
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
  }

  Widget _buildStatsCard(_StateOsmImportTotals totals) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F8F5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFD5E5D9)),
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
              _statChip('Postcodes', totals.postcodesProcessed),
              _statChip('Failed', totals.failedPostcodes),
              _statChip('Found', totals.discovered),
              _statChip('Added', totals.added),
              _statChip('Updated', totals.updated),
              _statChip('Web', totals.withWebsite),
              _statChip('Email', totals.withEmail),
              _statChip('Phone', totals.withPhone),
              _statChip('Facebook', totals.withFacebook),
              _statChip('Instagram', totals.withInstagram),
              _statChip('Jobs', totals.withCareers),
              _statChip('Firebase', totals.firebaseUploaded),
            ],
          ),
          if (totals.firebaseUploadFailed) ...[
            const SizedBox(height: 10),
            Text(
              'Firebase upload failed: ${totals.firebaseUploadError ?? 'unknown error'}',
              style: TextStyle(color: Colors.red.shade700, height: 1.3),
            ),
          ],
          const SizedBox(height: 10),
          Text(
            'Web sources: OSM ${totals.websiteFromOsm}, discovered ${totals.websiteDiscovered} '
            '(Wikidata ${totals.websiteFromWikidata}, brands ${totals.websiteFromKnownBrand}, domains ${totals.websiteFromProbableDomain})',
            style: TextStyle(color: Colors.grey.shade700, height: 1.3),
          ),
          if (totals.skippedByCache > 0) ...[
            const SizedBox(height: 6),
            Text(
              'Skipped by cache: ${totals.skippedByCache}',
              style: TextStyle(color: Colors.orange.shade800),
            ),
          ],
          if (totals.skippedByUser > 0) ...[
            const SizedBox(height: 6),
            Text(
              'Skipped by user: ${totals.skippedByUser}',
              style: TextStyle(color: Colors.orange.shade800),
            ),
          ],
          if (totals.failedDetails.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Last failed: ${totals.failedDetails.last.postcode} · '
              '${totals.failedDetails.last.shortMessage}',
              style: TextStyle(color: Colors.red.shade700, height: 1.3),
            ),
          ],
        ],
      ),
    );
  }

  Widget _statChip(String label, int value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFD5E5D9)),
      ),
      child: Text(
        '$label: $value',
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
    );
  }

  Future<T?> _awaitOrSkip<T>(Future<T> future, String postcode) async {
    final completer = Completer<void>();
    setState(() {
      _skipCompleter = completer;
      _currentPostcode = postcode;
    });

    final winner = await Future.any<Object?>([
      future,
      completer.future.then((_) => _PostcodeSkipSignal()),
    ]);
    if (completer.isCompleted) {
      // Ignore result/possible errors from the original future after skipping.
      unawaited(future.then((_) {}, onError: (_) {}));
      return null;
    }
    return winner as T;
  }

  void _skipCurrentPostcode() {
    if (_skipCompleter != null && !_skipCompleter!.isCompleted) {
      _skipCompleter!.complete();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Skipping postcode $_currentPostcode...')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final progress = _total == 0
        ? 0.0
        : (_processed / _total).clamp(0, 1).toDouble();

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Add by state',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 10),
              const Text(
                'Import all remote postcodes from one state using the OpenStreetMap import logic (Tourism & Hospitality criteria).',
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
                    .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                    .toList(),
                onChanged: _isImporting
                    ? null
                    : (value) => unawaited(_selectState(value)),
              ),
              if (_selectedStatePostcodeCount != null) ...[
                const SizedBox(height: 8),
                Text(
                  'This will scan all $_selectedStatePostcodeCount Tourism & Hospitality postcodes for $_selectedState.',
                  style: const TextStyle(color: Colors.black54),
                ),
              ],
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _isImporting ? null : _startImport,
                icon: const Icon(Icons.download),
                label: const Text('Import restaurants by state from OSM'),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 52),
                  backgroundColor: Colors.green.shade600,
                  foregroundColor: Colors.white,
                ),
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Force OSM rescan'),
                subtitle: const Text('Ignore the 30-day postcode scan cache.'),
                value: _forceOsmRefresh,
                onChanged: _isImporting
                    ? null
                    : (value) => setState(() => _forceOsmRefresh = value),
              ),
              const SizedBox(height: 20),
              if (_isImporting) ...[
                LinearProgressIndicator(value: progress == 0 ? null : progress),
                const SizedBox(height: 12),
                Text(
                  _total == 0
                      ? 'Preparing import for ${_selectedState ?? ''}...'
                      : 'Importing $_processed/$_total postcodes for ${_selectedState ?? ''}...',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                if (_currentPostcode != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Current postcode: $_currentPostcode',
                    style: const TextStyle(color: Colors.black54),
                  ),
                  if (_currentRestaurantName != null ||
                      _currentRestaurantStatus != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      _currentRestaurantName == null
                          ? (_currentRestaurantStatus ?? '')
                          : 'Searching: $_currentRestaurantName',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Colors.black87,
                      ),
                    ),
                    if (_currentRestaurantIndex != null &&
                        _currentRestaurantTotal != null)
                      Text(
                        'Restaurant $_currentRestaurantIndex/$_currentRestaurantTotal',
                        style: const TextStyle(color: Colors.black54),
                      ),
                    if (_currentRestaurantStatus != null &&
                        _currentRestaurantName != null)
                      Text(
                        _currentRestaurantStatus!,
                        style: TextStyle(
                          color:
                              _currentRestaurantStatus!.contains('Skipped') ||
                                  _currentRestaurantStatus!.contains('failed')
                              ? Colors.orange.shade800
                              : Colors.black54,
                        ),
                      ),
                  ],
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: OutlinedButton.icon(
                      onPressed: _skipCurrentPostcode,
                      icon: const Icon(Icons.fast_forward_rounded),
                      label: const Text('Skip and continue'),
                    ),
                  ),
                ] else if (_currentRestaurantStatus != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    _currentRestaurantStatus!,
                    style: const TextStyle(
                      color: Colors.black54,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                ] else
                  const SizedBox(height: 12),
              ],
              if (_latestTotals != null) ...[
                const SizedBox(height: 16),
                _buildStatsCard(_latestTotals!),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _StateOsmImportTotals {
  _StateOsmImportTotals({required this.state});

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
  int websiteFromOsm = 0;
  int websiteDiscovered = 0;
  int websiteFromWikidata = 0;
  int websiteFromKnownBrand = 0;
  int websiteFromProbableDomain = 0;
  int firebaseUploaded = 0;
  bool firebaseUploadFailed = false;
  String? firebaseUploadError;
  final Set<String> changedRestaurantIds = <String>{};
  final List<_PostcodeFailure> failedDetails = <_PostcodeFailure>[];

  void add(OsmRestaurantImportResult result) {
    postcodesProcessed++;
    if (result.skippedByCooldown) {
      skippedByCache++;
      return;
    }
    discovered += result.discovered;
    added += result.added;
    updated += result.updated;
    skippedDuplicates += result.skippedDuplicates;
    changedRestaurantIds.addAll(result.changedRestaurantIds);

    final summary = result.summary;
    withWebsite += summary.withWebsite;
    withPhone += summary.withPhone;
    withEmail += summary.withEmail;
    withFacebook += summary.withFacebook;
    withInstagram += summary.withInstagram;
    withCareers += summary.withCareers;
    websiteFromOsm += summary.websiteFromOsm;
    websiteDiscovered += summary.websiteDiscovered;
    websiteFromWikidata += summary.websiteFromWikidata;
    websiteFromKnownBrand += summary.websiteFromKnownBrand;
    websiteFromProbableDomain += summary.websiteFromProbableDomain;
  }

  void addSkippedByUser(String postcode) {
    postcodesProcessed++;
    skippedByUser++;
  }

  void addFailed(String postcode, Object error) {
    postcodesProcessed++;
    failedPostcodes++;
    failedDetails.add(_PostcodeFailure(postcode: postcode, error: error));
  }
}

class _PostcodeFailure {
  const _PostcodeFailure({required this.postcode, required this.error});

  final String postcode;
  final Object error;

  String get shortMessage {
    final raw = error.toString();
    if (raw.contains('All Overpass endpoints failed')) {
      return 'OSM/Overpass unavailable';
    }
    if (raw.contains('Nominatim returned')) {
      return 'postcode location unavailable';
    }
    if (error is TimeoutException || raw.contains('TimeoutException')) {
      return 'postcode timed out';
    }
    if (raw.length <= 90) return raw;
    return '${raw.substring(0, 90)}...';
  }
}

class _PostcodeSkipSignal {}
