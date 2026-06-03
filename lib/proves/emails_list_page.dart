import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../screens/restaurant_edit_page.dart';
import '../services/map_markers_service.dart';
import 'csv_export_helper.dart';

class EmailsListPage extends StatefulWidget {
  const EmailsListPage({super.key});

  @override
  State<EmailsListPage> createState() => _EmailsListPageState();
}

class _EmailsListPageState extends State<EmailsListPage> {
  bool _loading = false;
  bool _exporting = false;
  bool _hasLoaded = false;
  List<Map<String, dynamic>> _restaurants = [];

  Future<void> _loadEmails() async {
    setState(() => _loading = true);
    try {
      var list = _sortByName(
        (await MapMarkersService.loadRestaurants(
              fromServer: false,
              lightweight: true,
            ))
            .map(_fromRestaurant)
            .where((r) => (r['email'] as String).isNotEmpty)
            .toList(growable: true),
      );

      if (list.isEmpty) {
        final snapshot = await FirebaseFirestore.instance
            .collection('restaurants')
            .get();
        list = _sortByName(
          snapshot.docs
              .map((doc) => _fromRestaurant(doc.data(), docId: doc.id))
              .where((r) => (r['email'] as String).isNotEmpty)
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
      debugPrint('Error carregant correus: $e');
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
      'email': _extractEmail(data),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Restaurant emails'),
        backgroundColor: Colors.blueAccent,
        actions: [
          IconButton(
            tooltip: 'Reload',
            onPressed: _loading || _exporting ? null : _loadEmails,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Export CSV',
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
          : _restaurants.isEmpty
          ? const Center(child: Text('No emails available.'))
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
                          'Total emails: ${_restaurants.length}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      ElevatedButton.icon(
                        onPressed: _exporting ? null : _exportCsv,
                        icon: const Icon(Icons.description_outlined),
                        label: const Text('Generate CSV'),
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
                            tooltip: 'Edit restaurant',
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
