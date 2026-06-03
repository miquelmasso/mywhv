import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../screens/restaurant_edit_page.dart';
import '../services/external_link_service.dart';
import '../services/map_markers_service.dart';
import 'csv_export_helper.dart';

class FacebookListPage extends StatefulWidget {
  const FacebookListPage({super.key});

  @override
  State<FacebookListPage> createState() => _FacebookListPageState();
}

class _FacebookListPageState extends State<FacebookListPage> {
  bool _loading = false;
  bool _exporting = false;
  bool _hasLoaded = false;
  List<Map<String, dynamic>> _restaurants = [];

  Future<void> _loadFacebookLinks() async {
    setState(() => _loading = true);
    try {
      var list = _sortByName(
        (await MapMarkersService.loadRestaurants(
              fromServer: false,
              lightweight: true,
            ))
            .map(_fromRestaurant)
            .where((r) => (r['facebook_url'] as String).isNotEmpty)
            .toList(growable: true),
      );

      if (list.isEmpty) {
        final snapshot = await FirebaseFirestore.instance
            .collection('restaurants')
            .get();
        list = _sortByName(
          snapshot.docs
              .map((doc) => _fromRestaurant(doc.data(), docId: doc.id))
              .where((r) => (r['facebook_url'] as String).isNotEmpty)
              .toList(growable: true),
        );
      }

      if (!mounted) return;
      setState(() {
        _restaurants = list;
        _loading = false;
        _hasLoaded = true;
      });
    } catch (e) {
      debugPrint('❌ Error carregant enllaços de Facebook: $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _hasLoaded = true;
      });
    }
  }

  Map<String, dynamic> _fromRestaurant(
    Map<String, dynamic> data, {
    String? docId,
  }) {
    return {
      'docId': (docId ?? data['docId'] ?? data['id'] ?? '').toString(),
      'name': (data['name'] ?? 'Sense nom').toString(),
      'facebook_url': (data['facebook_url'] ?? '').toString().trim(),
    };
  }

  List<Map<String, dynamic>> _sortByName(List<Map<String, dynamic>> rows) {
    return rows..sort((a, b) {
      final nameA = (a['name'] ?? '').toString().trim().toLowerCase();
      final nameB = (b['name'] ?? '').toString().trim().toLowerCase();
      final byName = nameA.compareTo(nameB);
      if (byName != 0) return byName;
      final idA = (a['docId'] ?? '').toString();
      final idB = (b['docId'] ?? '').toString();
      return idA.compareTo(idB);
    });
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'We could not create the CSV right now. Please try again.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _openUrl(String url) async {
    if (!mounted) return;
    await ExternalLinkService.open(context, url);
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
          : !_hasLoaded
          ? const Center(
              child: Text('Prem actualitzar per carregar les dades.'),
            )
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
