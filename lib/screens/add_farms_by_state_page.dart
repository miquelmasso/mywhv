import 'package:flutter/material.dart';
import '../services/farm_import_service.dart';

class AddFarmsByStatePage extends StatefulWidget {
  const AddFarmsByStatePage({super.key});

  @override
  State<AddFarmsByStatePage> createState() => _AddFarmsByStatePageState();
}

class _AddFarmsByStatePageState extends State<AddFarmsByStatePage> {
  final FarmImportService _importService = FarmImportService();

  final List<String> _states = const ['QLD', 'VIC', 'NSW', 'SA', 'WA', 'TAS', 'NT'];
  String? _selectedState;
  bool _isImporting = false;
  int _processed = 0;
  int _total = 0;

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
        final result = await _importService.importFarmsForPostcode(postcodeStr);
        if (!mounted) return;
        if (!result.allowed || !result.valid) {
          setState(() => _processed++);
          continue;
        }
        setState(() => _processed++);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Importació de farms completada: $_processed/$_total codis per ${_selectedState!}.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error important: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isImporting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final progress =
        _total == 0 ? 0.0 : (_processed / _total).clamp(0, 1).toDouble();

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Afegir farms per estat',
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
              'Importa totes les farms d’un estat (només codis regionals).',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 18),
            DropdownButtonFormField<String>(
              initialValue: _selectedState,
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
              label: const Text('Importar farms per estat'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 52),
                backgroundColor: Colors.green.shade700,
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
            ],
            const SizedBox(height: 16),
            const Text(
              'Els camps desats inclouen: name, address, state, postcode, '
              'latitude/longitude, phone, website, email, facebook_url, instagram_url, '
              'careers_page, source_place_id, timestamp, worked_here_count, '
              'is_remote_462, category.',
              style: TextStyle(color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }
}
