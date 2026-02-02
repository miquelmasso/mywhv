import 'dart:async';

import 'package:flutter/material.dart';
import '../services/restaurant_import_service.dart';

class AddRestaurantsByStatePage extends StatefulWidget {
  const AddRestaurantsByStatePage({super.key});

  @override
  State<AddRestaurantsByStatePage> createState() =>
      _AddRestaurantsByStatePageState();
}

class _AddRestaurantsByStatePageState extends State<AddRestaurantsByStatePage> {
  final RestaurantImportService _importService = RestaurantImportService();

  final List<String> _states = const ['QLD', 'VIC', 'NSW', 'SA', 'WA', 'TAS', 'NT'];
  String? _selectedState;
  bool _isImporting = false;
  int _processed = 0;
  int _total = 0;
  String? _currentPostcode;
  Completer<void>? _skipCompleter;

  Map<String, (int start, int end)> get _stateRanges => {
        'QLD': (4000, 4999),
        'VIC': (3000, 3999),
        'NSW': (2000, 2999),
        'SA': (5000, 5999),
        'WA': (6000, 6999),
        'TAS': (7000, 7999),
        'NT': (800, 999),
      };

  Future<void> _startImport() async {
    if (_selectedState == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona un estat.')),
      );
      return;
    }

    setState(() {
      _isImporting = true;
      _processed = 0;
      _total = 0;
      _currentPostcode = null;
    });

    try {
      final range = _stateRanges[_selectedState!] ??
          (_selectedState == 'NT' ? (800, 999) : (0, -1));
      final start = range.$1;
      final end = range.$2;
      if (end < start) {
        throw Exception('No hi ha rang definit per ${_selectedState!}');
      }

      setState(() => _total = end - start + 1);

      for (int pc = start; pc <= end; pc++) {
        final postcodeStr = pc.toString().padLeft(4, '0');
        final isRemote = await _awaitOrSkip(
          _importService.isRemoteTourismPostcode(postcodeStr),
          postcodeStr,
        );
        if (isRemote == true) {
          await _awaitOrSkip(
            _importService.importAllRestaurantsForPostcode(postcodeStr),
            postcodeStr,
          );
        }
        setState(() => _processed++);
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Import completed: $_processed/$_total postcodes for ${_selectedState!}.',
          ),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error important: $e')),
      );
    } finally {
      setState(() => _isImporting = false);
      _skipCompleter = null;
      _currentPostcode = null;
    }
  }

  Future<T?> _awaitOrSkip<T>(Future<T> future, String postcode) async {
    final completer = Completer<void>();
    setState(() {
      _skipCompleter = completer;
      _currentPostcode = postcode;
    });

    await Future.any([future, completer.future]);
    if (completer.isCompleted) {
      // Ignore result/possible errors from the original future after skipping.
      future.catchError((_) {});
      return null;
    }
    return await future;
  }

  void _skipCurrentPostcode() {
    if (_skipCompleter != null && !_skipCompleter!.isCompleted) {
      _skipCompleter!.complete();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saltant el codi $_currentPostcode...')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final progress =
        _total == 0 ? 0.0 : (_processed / _total).clamp(0, 1).toDouble();

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Afegir per estat',
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 10),
            const Text(
              'Importa tots els codis postals remots d’un estat (criteris Tourism & Hospitality).',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 18),
            DropdownButtonFormField<String>(
              value: _selectedState,
              decoration: InputDecoration(
                labelText: 'Escull estat',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              items: _states
                  .map(
                    (s) => DropdownMenuItem(
                      value: s,
                      child: Text(s),
                    ),
                  )
                  .toList(),
              onChanged: _isImporting ? null : (value) => setState(() => _selectedState = value),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _isImporting ? null : _startImport,
              icon: const Icon(Icons.download),
              label: const Text('Importar restaurants per estat'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 52),
                backgroundColor: Colors.green.shade600,
                foregroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 20),
            if (_isImporting) ...[
              LinearProgressIndicator(value: progress == 0 ? null : progress),
              const SizedBox(height: 12),
              Text(
                _total == 0
                    ? 'Preparing import for ${_selectedState ?? ''}...'
                    : 'Important $_processed/$_total codis postals per ${_selectedState ?? ''}...',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              if (_currentPostcode != null) ...[
                const SizedBox(height: 4),
                Text(
                  'Codi actual: $_currentPostcode',
                  style: const TextStyle(color: Colors.black54),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: OutlinedButton.icon(
                    onPressed: _skipCurrentPostcode,
                    icon: const Icon(Icons.fast_forward_rounded),
                    label: const Text('Saltar i seguir'),
                  ),
                ),
              ] else
                const SizedBox(height: 12),
            ],
            const SizedBox(height: 16),
            Text(
              'Les dades es guarden amb:'
              ' nom, telèfon, email, web, facebook_url, latitude/longitude, postcode, postcode_display, worked_here_count, state, timestamp.',
              style: const TextStyle(color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }
}
