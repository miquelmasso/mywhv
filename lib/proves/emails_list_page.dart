import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../screens/restaurant_edit_page.dart';

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
          .orderBy('name')
          .get();

      final list = snapshot.docs
          .map((doc) {
            final data = doc.data();
            return {
              'docId': doc.id,
              'name': (data['name'] ?? 'Sense nom').toString(),
              'email': (data['email'] ?? '').toString().trim(),
            };
          })
          .where((r) => (r['email'] as String).isNotEmpty)
          .toList(growable: false);

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

  String _csvEscape(String value) {
    final escaped = value.replaceAll('"', '""');
    final mustQuote =
        escaped.contains(',') ||
        escaped.contains('"') ||
        escaped.contains('\n');
    return mustQuote ? '"$escaped"' : escaped;
  }

  String _timestampForFileName(DateTime now) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${now.year}${two(now.month)}${two(now.day)}_${two(now.hour)}${two(now.minute)}${two(now.second)}';
  }

  Future<Directory> _resolveExportDirectory() async {
    final appDocuments = await getApplicationDocumentsDirectory();

    // iOS Simulator: try to save directly in host Mac Downloads.
    if (Platform.isIOS) {
      const simulatorMarker = '/Library/Developer/CoreSimulator/Devices/';
      final idx = appDocuments.path.indexOf(simulatorMarker);
      if (idx > 0) {
        final macHome = appDocuments.path.substring(0, idx);
        final downloads = Directory('$macHome/Downloads');
        if (await downloads.exists()) {
          return downloads;
        }
      }
    }

    if (Platform.isAndroid) {
      final external = await getExternalStorageDirectory();
      if (external != null) return external;
    }

    final home = Platform.environment['HOME'];
    if (home != null && home.isNotEmpty) {
      final downloads = Directory('$home/Downloads');
      if (await downloads.exists()) {
        return downloads;
      }
    }

    return appDocuments;
  }

  Future<void> _exportCsv() async {
    if (_loading || _exporting || _restaurants.isEmpty) return;

    setState(() => _exporting = true);
    try {
      final rows = <String>['doc_id,name,email'];
      for (final row in _restaurants) {
        final docId = (row['docId'] ?? '').toString();
        final name = (row['name'] ?? '').toString();
        final email = (row['email'] ?? '').toString();
        rows.add(
          '${_csvEscape(docId)},${_csvEscape(name)},${_csvEscape(email)}',
        );
      }

      final directory = await _resolveExportDirectory();
      final fileName =
          'restaurants_emails_${_timestampForFileName(DateTime.now())}.csv';
      final file = File('${directory.path}/$fileName');
      await file.writeAsString(rows.join('\n'), flush: true);

      await Clipboard.setData(ClipboardData(text: file.path));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'CSV creat (${_restaurants.length} correus). Path copiat: ${file.path}',
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
