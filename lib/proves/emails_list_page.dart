import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../screens/restaurant_edit_page.dart';
import 'csv_export_helper.dart';

class EmailsListPage extends StatefulWidget {
  const EmailsListPage({super.key});

  @override
  State<EmailsListPage> createState() => _EmailsListPageState();
}

class _EmailsListPageState extends State<EmailsListPage> {
  bool _loading = true;
  bool _exporting = false;
  List<Map<String, dynamic>> _restaurants = [];

  @override
  void initState() {
    super.initState();
    _loadEmails();
  }

  Future<void> _loadEmails() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('restaurants')
          .get();

      final list =
          snapshot.docs
              .map((doc) {
                final data = doc.data();
                return {
                  'docId': doc.id,
                  'name': (data['name'] ?? 'Sense nom').toString(),
                  'email': _extractEmail(data),
                };
              })
              .where((r) => (r['email'] as String).isNotEmpty)
              .toList(growable: true)
            ..sort((a, b) {
              final nameA = (a['name'] ?? '').toString().trim().toLowerCase();
              final nameB = (b['name'] ?? '').toString().trim().toLowerCase();
              final byName = nameA.compareTo(nameB);
              if (byName != 0) return byName;
              final idA = (a['docId'] ?? '').toString();
              final idB = (b['docId'] ?? '').toString();
              return idA.compareTo(idB);
            });

      if (!mounted) return;
      setState(() {
        _restaurants = list;
        _loading = false;
      });
    } catch (e) {
      debugPrint('Error carregant correus: $e');
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  String _extractEmail(Map<String, dynamic> data) {
    final primary = (data['email'] ?? '').toString().trim();
    final legacyEmails =
        (data['emails'] as List?)
            ?.whereType<String>()
            .map((email) => email.trim())
            .where((email) => email.isNotEmpty)
            .toList(growable: false) ??
        const <String>[];

    if (primary.isEmpty) {
      return legacyEmails.join(', ');
    }

    if (legacyEmails.isEmpty) {
      return primary;
    }

    final uniqueEmails = <String>{primary, ...legacyEmails};
    return uniqueEmails.join(', ');
  }

  Future<void> _exportCsv() async {
    if (_loading || _exporting || _restaurants.isEmpty) return;

    setState(() => _exporting = true);
    try {
      final filePath = await exportRowsAsCsv(
        filePrefix: 'restaurants_emails',
        headers: const ['doc_id', 'name', 'email'],
        rows: _restaurants
            .map(
              (row) => [
                (row['docId'] ?? '').toString(),
                (row['name'] ?? '').toString(),
                (row['email'] ?? '').toString(),
              ],
            )
            .toList(growable: false),
      );

      await Clipboard.setData(ClipboardData(text: filePath));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'CSV creat (${_restaurants.length} correus). Path copiat: $filePath',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error creant CSV: $e')));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Correus dels restaurants'),
        backgroundColor: Colors.blueAccent,
        actions: [
          IconButton(
            tooltip: 'Recarregar',
            onPressed: _loading || _exporting ? null : _loadEmails,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Exportar CSV',
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
          : _restaurants.isEmpty
          ? const Center(child: Text('No hi ha correus disponibles.'))
          : Column(
              children: [
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blueGrey.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.blueGrey.shade100),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Correus totals: ${_restaurants.length}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      ElevatedButton.icon(
                        onPressed: _exporting ? null : _exportCsv,
                        icon: const Icon(Icons.description_outlined),
                        label: const Text('Generar CSV'),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _restaurants.length,
                    itemBuilder: (context, i) {
                      final r = _restaurants[i];
                      final name = (r['name'] ?? '').toString();
                      final email = (r['email'] ?? '').toString();
                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 6),
                        child: ListTile(
                          title: Text(
                            name,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          subtitle: SelectableText(email),
                          trailing: IconButton(
                            icon: const Icon(Icons.edit_outlined),
                            tooltip: 'Editar restaurant',
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      RestaurantEditPage(initialSearch: name),
                                ),
                              );
                            },
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
