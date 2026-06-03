import 'package:flutter/material.dart';

import '../services/farm_import_service.dart';
import '../services/farm_sqlite_store.dart';
import '../services/harvest_admin_import_service.dart';
import '../services/harvest_geocode_service.dart';

class ManageFarmsPage extends StatefulWidget {
  const ManageFarmsPage({super.key});

  @override
  State<ManageFarmsPage> createState() => _ManageFarmsPageState();
}

class _ManageFarmsPageState extends State<ManageFarmsPage> {
  final List<String> _states = const [
    'QLD',
    'VIC',
    'NSW',
    'SA',
    'WA',
    'TAS',
    'NT',
  ];
  final FarmImportService _importService = FarmImportService();
  final FarmSqliteStore _farmStore = FarmSqliteStore.instance;
  final HarvestAdminImportService _harvestAssetService =
      HarvestAdminImportService();
  final HarvestGeocodeService _harvestGeocodeService = HarvestGeocodeService();
  String? _selectedState;
  bool _isDeleting = false;
  bool _isImporting = false;
  bool _isImportingHarvest = false;
  bool _isGeocodingHarvest = false;
  int _deleted = 0;
  int _processed = 0;
  int _total = 0;
  String _harvestStatus = '';
  int _harvestParsed = 0;
  int _harvestWritten = 0;
  int _harvestErrors = 0;

  Map<String, (int start, int end)> get _stateRanges => {
    'QLD': (4000, 4999),
    'VIC': (3000, 3999),
    'NSW': (2000, 2999),
    'SA': (5000, 5999),
    'WA': (6000, 6999),
    'TAS': (7000, 7999),
    'NT': (800, 999),
  };

  Future<void> _deleteByState() async {
    if (_selectedState == null) {
      _showSnack('Select a state to delete.', Colors.orange);
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete farms by state'),
        content: Text(
          'Are you sure you want to delete all farms from ${_selectedState!}? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() {
      _isDeleting = true;
      _deleted = 0;
    });

    try {
      await _farmStore.init();
      final deleted = await _farmStore.deleteByState(_selectedState!);
      setState(() => _deleted = deleted);

      _showSnack(
        'Deleted $_deleted farms from ${_selectedState!}',
        Colors.green,
      );
    } catch (e) {
      _showSnack(
        'We could not delete farms for this state right now.',
        Colors.red,
      );
    } finally {
      setState(() => _isDeleting = false);
    }
  }

  Future<void> _importByState() async {
    if (_selectedState == null) {
      _showSnack('Select a state to add.', Colors.orange);
      return;
    }

    setState(() {
      _isImporting = true;
      _processed = 0;
      _total = 0;
    });

    try {
      final range =
          _stateRanges[_selectedState!] ??
          (_selectedState == 'NT' ? (800, 999) : (0, -1));
      final start = range.$1;
      final end = range.$2;
      if (end < start) {
        throw Exception('No range defined for ${_selectedState!}');
      }

      final added = await _importService.importFarmsForState(_selectedState!);
      setState(() {
        _processed = 1;
        _total = 1;
      });

      _showSnack(
        'Farm import completed for ${_selectedState!}. New: $added',
        Colors.green,
      );
    } catch (e) {
      _showSnack(
        'We could not import farms for this state right now.',
        Colors.red,
      );
    } finally {
      setState(() => _isImporting = false);
    }
  }

  Future<void> _importHarvest() async {
    if (_isImportingHarvest) return;
    setState(() {
      _isImportingHarvest = true;
      _harvestStatus = 'Downloading...';
      _harvestParsed = 0;
      _harvestWritten = 0;
      _harvestErrors = 0;
    });

    try {
      setState(() {
        _harvestStatus = 'Reading asset...';
      });
      final written = await _harvestAssetService.importHarvestPlacesFromAsset();
      _harvestParsed = written;
      _harvestWritten = written;
      _harvestErrors = 0;
      _harvestStatus = 'Completed';
      _showSnack('Harvest import. Docs: $written', Colors.green);
    } catch (e) {
      _showSnack('We could not import harvest data right now.', Colors.red);
    } finally {
      setState(() => _isImportingHarvest = false);
    }
  }

  Future<void> _geocodeHarvestPlaces() async {
    if (_isGeocodingHarvest) return;
    setState(() {
      _isGeocodingHarvest = true;
    });
    try {
      final combined = await _harvestGeocodeService.importAndGeocodeFromAsset();
      _showSnack(
        'Harvest import done. docs: ${combined.importOutcome.docs}, months: ${combined.importOutcome.monthsUpdated}, errors: ${combined.importOutcome.errors}',
        Colors.green,
      );
      final res = combined.geocodeResult;
      _showSnack(
        'Geocode done. updated: ${res.updated}, skipped: ${res.skipped}, errors: ${res.errors}',
        Colors.green,
      );
    } catch (e) {
      _showSnack(
        'We could not update harvest locations right now.',
        Colors.red,
      );
    } finally {
      setState(() {
        _isGeocodingHarvest = false;
      });
    }
  }

  void _showSnack(String text, Color color) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(text), backgroundColor: color));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage farms'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Add or delete farms by state.',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _selectedState,
              decoration: const InputDecoration(
                labelText: 'Choose state',
                border: OutlineInputBorder(),
              ),
              items: _states
                  .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                  .toList(),
              onChanged: (_isDeleting || _isImporting)
                  ? null
                  : (v) => setState(() => _selectedState = v),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: (_isDeleting || _isImporting) ? null : _importByState,
              icon: const Icon(Icons.add),
              label: Text(_isImporting ? 'Importing...' : 'Add farms by state'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 52),
                backgroundColor: Colors.green.shade700,
                foregroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _isImportingHarvest ? null : _importHarvest,
              icon: const Icon(Icons.cloud_download),
              label: Text(
                _isImportingHarvest
                    ? 'Importing...'
                    : '🌾 Import Harvest (Admin)',
              ),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 52),
                backgroundColor: Colors.orange.shade700,
                foregroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: (_isGeocodingHarvest || _isImportingHarvest)
                  ? null
                  : _geocodeHarvestPlaces,
              icon: const Icon(Icons.explore),
              label: Text(
                _isGeocodingHarvest
                    ? 'Geocoding...'
                    : '🧭 Geocode Harvest Places (Admin)',
              ),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 52),
                backgroundColor: Colors.blueGrey.shade700,
                foregroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _isDeleting ? null : _deleteByState,
              icon: const Icon(Icons.delete_forever),
              label: Text(
                _isDeleting ? 'Deleting...' : 'Delete farms by state',
              ),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 52),
                backgroundColor: Colors.red.shade700,
                foregroundColor: Colors.white,
              ),
            ),
            if (_isDeleting ||
                _isImporting ||
                _isImportingHarvest ||
                _isGeocodingHarvest) ...[
              const SizedBox(height: 16),
              const LinearProgressIndicator(),
              const SizedBox(height: 8),
              if (_total > 0 && _isImporting)
                Text(
                  'Importing $_processed/$_total postcodes for ${_selectedState ?? ''}...',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              if (_isImportingHarvest)
                Text(
                  'Harvest: $_harvestStatus\nRegions: $_harvestParsed • Docs: $_harvestWritten • Errors: $_harvestErrors',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
