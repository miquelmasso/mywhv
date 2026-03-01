import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';

import '../screens/restaurant_edit_page.dart';
import 'csv_export_helper.dart';

class FacebookListPage extends StatefulWidget {
  const FacebookListPage({super.key});

  @override
  State<FacebookListPage> createState() => _FacebookListPageState();
}

class _FacebookListPageState extends State<FacebookListPage> {
  bool _loading = true;
  bool _exporting = false;
  List<Map<String, dynamic>> _restaurants = [];

  @override
  void initState() {
    super.initState();
    _loadFacebookLinks();
  }

  Future<void> _loadFacebookLinks() async {
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
              'facebook_url': (data['facebook_url'] ?? '').toString().trim(),
            };
          })
          .where((r) => (r['facebook_url'] as String).isNotEmpty)
          .toList(growable: false);

      if (!mounted) return;
      setState(() {
        _restaurants = list;
        _loading = false;
      });
    } catch (e) {
      debugPrint('❌ Error carregant enllaços de Facebook: $e');
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _exportCsv() async {
    if (_loading || _exporting || _restaurants.isEmpty) return;

    setState(() => _exporting = true);
    try {
      final filePath = await exportRowsAsCsv(
        filePrefix: 'restaurants_facebook',
        headers: const ['doc_id', 'name', 'facebook_url'],
        rows: _restaurants
            .map(
              (row) => [
                (row['docId'] ?? '').toString(),
                (row['name'] ?? '').toString(),
                (row['facebook_url'] ?? '').toString(),
              ],
            )
            .toList(growable: false),
      );

      await Clipboard.setData(ClipboardData(text: filePath));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'CSV creat (${_restaurants.length} Facebook). Path copiat: $filePath',
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

  Future<void> _openUrl(String url) async {
    if (url.isEmpty) return;
    final uri = Uri.parse(url);
    final canOpen = await canLaunchUrl(uri);
    if (!mounted) return;
    if (canOpen) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No s’ha pogut obrir l’enllaç')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Enllaços de Facebook'),
        backgroundColor: Colors.indigo,
        actions: [
          IconButton(
            tooltip: 'Recarregar',
            onPressed: _loading || _exporting ? null : _loadFacebookLinks,
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
          ? const Center(child: Text('⚠️ No hi ha dades.'))
          : Column(
              children: [
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.indigo.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.indigo.shade100),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Enllaços totals: ${_restaurants.length}',
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
                      final link = (r['facebook_url'] ?? '').toString();
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
                          subtitle: InkWell(
                            onTap: () => _openUrl(link),
                            child: Text(
                              link,
                              style: const TextStyle(
                                color: Colors.blue,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ),
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
