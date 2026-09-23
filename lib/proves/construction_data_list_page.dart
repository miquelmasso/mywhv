import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../screens/construction_edit_page.dart';
import '../services/construction_sqlite_store.dart';
import 'csv_export_helper.dart';

class ConstructionDataListPage extends StatefulWidget {
  const ConstructionDataListPage({super.key});

  @override
  State<ConstructionDataListPage> createState() =>
      _ConstructionDataListPageState();
}

class _ConstructionDataListPageState extends State<ConstructionDataListPage> {
  final _searchController = TextEditingController();
  List<Map<String, dynamic>> _rows = const [];
  bool _loading = false;
  bool _exporting = false;
  bool _hasLoaded = false;
  String _state = 'All';
  String _status = 'All';

  static const _csvHeaders = <String>[
    'id',
    'name',
    'state',
    'postcode',
    'address',
    'latitude',
    'longitude',
    'source',
    'company_id',
    'worksite_id',
    'worksite_name',
    'company_worksite_role',
    'link_corroborated',
    'company_worksite_evidence',
    'website',
    'email',
    'phone',
    'careers_page',
    'application_contact_type',
    'email_contact_type',
    'email_contact_confidence',
    'email_contact_evidence',
    'email_format_valid',
    'email_semantic_valid',
    'email_domain_status',
    'email_identity_status',
    'email_officially_published',
    'email_public_eligible',
    'email_source_url',
    'careers_contact_type',
    'careers_verification_status',
    'careers_public_eligible',
    'classification_source',
    'classification_confidence',
    'contact_enrichment_status',
    'contact_enrichment_stage',
    'contact_enrichment_failure_kind',
    'contact_enrichment_timeout_stage',
    'publication_status',
    'blocked',
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final rows = await ConstructionSqliteStore.instance.getAll();
      rows.sort(
        (a, b) => _text(
          a,
          'name',
        ).toLowerCase().compareTo(_text(b, 'name').toLowerCase()),
      );
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _hasLoaded = true;
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not load Construction data: $error')),
      );
      setState(() => _hasLoaded = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _text(Map<String, dynamic> row, String key) =>
      (row[key] ?? '').toString().trim();

  String _rowState(Map<String, dynamic> row) =>
      _text(row, 'state').toUpperCase();

  String _rowStatus(Map<String, dynamic> row) {
    final value = _text(row, 'contact_enrichment_status');
    return value.isEmpty ? 'not_started' : value;
  }

  List<String> get _states {
    final values =
        _rows.map(_rowState).where((value) => value.isNotEmpty).toSet()
          ..remove('ALL');
    final sorted = values.toList()..sort();
    return ['All', ...sorted];
  }

  List<String> get _statuses {
    final values = _rows.map(_rowStatus).toSet()..remove('All');
    final sorted = values.toList()..sort();
    return ['All', ...sorted];
  }

  List<Map<String, dynamic>> get _visibleRows {
    final query = _searchController.text.trim().toLowerCase();
    return _rows
        .where((row) {
          if (_state != 'All' && _rowState(row) != _state) return false;
          if (_status != 'All' && _rowStatus(row) != _status) return false;
          if (query.isEmpty) return true;
          return [
            'name',
            'worksite_name',
            'address',
            'postcode',
            'website',
            'email',
            'company_id',
            'worksite_id',
            'source',
          ].any((key) => _text(row, key).toLowerCase().contains(query));
        })
        .toList(growable: false);
  }

  Future<void> _exportCsv() async {
    final rows = _visibleRows;
    if (_loading || _exporting || rows.isEmpty) return;
    setState(() => _exporting = true);
    try {
      final path = await exportRowsAsCsv(
        filePrefix: 'construction_algorithm_audit',
        headers: _csvHeaders,
        rows: rows
            .map((row) => _csvHeaders.map((key) => _text(row, key)).toList())
            .toList(growable: false),
      );
      await Clipboard.setData(ClipboardData(text: path));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'CSV created (${rows.length} rows). Path copied: $path',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not create the CSV: $error')),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _edit(Map<String, dynamic> row) async {
    final id = _text(row, 'id').isNotEmpty
        ? _text(row, 'id')
        : _text(row, 'docId');
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            ConstructionEditPage(companyId: id, initialCompany: row),
      ),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visibleRows;
    final linked = visible
        .where((row) => _text(row, 'worksite_id').isNotEmpty)
        .length;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Construction data'),
        backgroundColor: Colors.blueGrey,
        actions: [
          IconButton(
            tooltip: 'Reload',
            onPressed: _loading || _exporting ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Export filtered CSV',
            onPressed: _loading || _exporting ? null : _exportCsv,
            icon: _exporting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download_outlined),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : !_hasLoaded
          ? const Center(child: Text('Press reload to load the data.'))
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Search company, worksite, contact or ID',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: _states.contains(_state)
                              ? _state
                              : 'All',
                          decoration: const InputDecoration(labelText: 'State'),
                          items: _states
                              .map(
                                (value) => DropdownMenuItem(
                                  value: value,
                                  child: Text(value),
                                ),
                              )
                              .toList(),
                          onChanged: (value) =>
                              setState(() => _state = value ?? 'All'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: _statuses.contains(_status)
                              ? _status
                              : 'All',
                          decoration: const InputDecoration(
                            labelText: 'Enrichment',
                          ),
                          items: _statuses
                              .map(
                                (value) => DropdownMenuItem(
                                  value: value,
                                  child: Text(
                                    value,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (value) =>
                              setState(() => _status = value ?? 'All'),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.all(12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blueGrey.shade50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Visible: ${visible.length} / ${_rows.length}  ·  Linked: $linked',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      ElevatedButton.icon(
                        onPressed: visible.isEmpty || _exporting
                            ? null
                            : _exportCsv,
                        icon: const Icon(Icons.description_outlined),
                        label: const Text('Generate CSV'),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: visible.isEmpty
                      ? const Center(
                          child: Text(
                            'No Construction records match these filters.',
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                          itemCount: visible.length,
                          itemBuilder: (context, index) {
                            final row = visible[index];
                            final details = <String>[
                              if (_rowState(row).isNotEmpty) _rowState(row),
                              if (_text(row, 'postcode').isNotEmpty)
                                _text(row, 'postcode'),
                              _rowStatus(row),
                              if (_text(
                                row,
                                'company_worksite_role',
                              ).isNotEmpty)
                                _text(row, 'company_worksite_role'),
                            ];
                            final contact =
                                [
                                  _text(row, 'email'),
                                  _text(row, 'careers_page'),
                                  _text(row, 'website'),
                                ].firstWhere(
                                  (value) => value.isNotEmpty,
                                  orElse: () => 'No contact found',
                                );
                            return Card(
                              child: ListTile(
                                title: Text(
                                  _text(row, 'name').isEmpty
                                      ? 'Unnamed record'
                                      : _text(row, 'name'),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                subtitle: Text(
                                  '${details.join(' · ')}\n$contact',
                                ),
                                isThreeLine: true,
                                trailing: IconButton(
                                  tooltip: 'Edit construction record',
                                  icon: const Icon(Icons.edit_outlined),
                                  onPressed: () => _edit(row),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}
