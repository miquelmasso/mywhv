import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../services/farm_import_service.dart';
import '../services/harvest_import_service.dart';

class ManageFarmsPage extends StatefulWidget {
  const ManageFarmsPage({super.key});

  @override
  State<ManageFarmsPage> createState() => _ManageFarmsPageState();
}

class _ManageFarmsPageState extends State<ManageFarmsPage> {
  final List<String> _states = const ['QLD', 'VIC', 'NSW', 'SA', 'WA', 'TAS', 'NT'];
  final FarmImportService _importService = FarmImportService();
  final HarvestImportService _harvestImportService = HarvestImportService();
  String? _selectedState;
  bool _isDeleting = false;
  bool _isImporting = false;
  bool _isImportingHarvest = false;
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
      _showSnack('Selecciona un estat per eliminar.', Colors.orange);
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar farms per estat'),
        content: Text(
          'Segur que vols eliminar totes les farms de ${_selectedState!}? Aquesta acció no es pot desfer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel·lar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
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
      final firestore = FirebaseFirestore.instance;
      QuerySnapshot<Map<String, dynamic>> snapshot;
      do {
        snapshot = await firestore
            .collection('farms')
            .where('state', isEqualTo: _selectedState)
            .limit(300)
            .get();

        if (snapshot.docs.isEmpty) break;

        final batch = firestore.batch();
        for (final doc in snapshot.docs) {
          batch.delete(doc.reference);
        }
        await batch.commit();
        setState(() => _deleted += snapshot.docs.length);
      } while (snapshot.docs.isNotEmpty);

      _showSnack('Eliminades $_deleted farms de ${_selectedState!}', Colors.green);
    } catch (e) {
      _showSnack('Error eliminant: $e', Colors.red);
    } finally {
      setState(() => _isDeleting = false);
    }
  }

  Future<void> _importByState() async {
    if (_selectedState == null) {
      _showSnack('Selecciona un estat per afegir.', Colors.orange);
      return;
    }

    setState(() {
      _isImporting = true;
      _processed = 0;
      _total = 0;
    });

    try {
      final range = _stateRanges[_selectedState!] ??
          (_selectedState == 'NT' ? (800, 999) : (0, -1));
      final start = range.$1;
      final end = range.$2;
      if (end < start) {
        throw Exception('No hi ha rang definit per ${_selectedState!}');
      }

      final added = await _importService.importFarmsForState(_selectedState!);
      setState(() {
        _processed = 1;
        _total = 1;
      });

      _showSnack(
        'Importació de farms completada per ${_selectedState!}. Nous: $added',
        Colors.green,
      );
    } catch (e) {
      _showSnack('Error important: $e', Colors.red);
    } finally {
      setState(() => _isImporting = false);
    }
  }

  Future<void> _importHarvest() async {
    if (_isImportingHarvest) return;
    setState(() {
      _isImportingHarvest = true;
      _harvestStatus = 'Descarregant...';
      _harvestParsed = 0;
      _harvestWritten = 0;
      _harvestErrors = 0;
    });

    try {
      final result = await _harvestImportService.importHarvest(onProgress: (p) {
        setState(() {
          _harvestStatus = p.message;
          _harvestParsed = p.regionsParsed;
          _harvestWritten = p.docsWritten;
          _harvestErrors = p.errors;
        });
      });
      _showSnack(
        'Harvest import. Regions: ${result.regions} docs: ${result.docs} errors: ${result.errors}'
        ' | HTTP: ${result.httpStatus ?? '-'} | len: ${result.bodyLength ?? '-'}',
        Colors.green,
      );
      if (result.errors > 0) {
        _showErrorDialog(result);
      }
    } catch (e) {
      _showSnack('Error import Harvest: $e', Colors.red);
    } finally {
      setState(() => _isImportingHarvest = false);
    }
  }

  void _showSnack(String text, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), backgroundColor: color),
    );
  }

  void _showErrorDialog(dynamic result) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Harvest import error'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('HTTP: ${result.httpStatus ?? '-'}'),
                Text('Body length: ${result.bodyLength ?? '-'}'),
                if (result.finalUrl != null) Text('URL: ${result.finalUrl}'),
                if (result.exception != null) Text('Exception: ${result.exception}'),
                const SizedBox(height: 8),
                const Text('Snippet:'),
                const SizedBox(height: 4),
                Container(
                  constraints: const BoxConstraints(maxHeight: 200),
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  color: Colors.grey.shade200,
                  child: SingleChildScrollView(
                    child: Text(
                      result.snippet ?? '',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Tancar'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestionar farms'),
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
              'Afegir o eliminar farms per estat.',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _selectedState,
              decoration: const InputDecoration(
                labelText: 'Escull estat',
                border: OutlineInputBorder(),
              ),
              items: _states
                  .map(
                    (s) => DropdownMenuItem(
                      value: s,
                      child: Text(s),
                    ),
                  )
                  .toList(),
              onChanged: (_isDeleting || _isImporting)
                  ? null
                  : (v) => setState(() => _selectedState = v),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: (_isDeleting || _isImporting) ? null : _importByState,
              icon: const Icon(Icons.add),
              label: Text(_isImporting ? 'Important...' : 'Afegir farms per estat'),
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
              label: Text(_isImportingHarvest ? 'Important...' : '🌾 Import Harvest (Admin)'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 52),
                backgroundColor: Colors.orange.shade700,
                foregroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _isDeleting ? null : _deleteByState,
              icon: const Icon(Icons.delete_forever),
              label: Text(
                _isDeleting ? 'Eliminant...' : 'Eliminar farms per estat',
              ),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 52),
                backgroundColor: Colors.red.shade700,
                foregroundColor: Colors.white,
              ),
            ),
            if (_isDeleting || _isImporting || _isImportingHarvest) ...[
              const SizedBox(height: 16),
              const LinearProgressIndicator(),
              const SizedBox(height: 8),
              if (_total > 0 && _isImporting)
                Text(
                  'Important $_processed/$_total codis per ${_selectedState ?? ''}...',
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
