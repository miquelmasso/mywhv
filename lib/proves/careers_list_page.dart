import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import '../screens/restaurant_edit_page.dart';

class CareersListPage extends StatefulWidget {
  const CareersListPage({super.key});

  @override
  State<CareersListPage> createState() => _CareersListPageState();
}

class _CareersListPageState extends State<CareersListPage> {
  bool _loading = true;
  List<Map<String, dynamic>> _restaurants = [];

  @override
  void initState() {
    super.initState();
    _loadCareers();
  }

  Future<void> _loadCareers() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('restaurants')
          .orderBy('name')
          .get();

      final list = snapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'name': data['name'] ?? 'Sense nom',
          'careers_page': (data['careers_page'] ?? '').toString(),
        };
      }).where((r) => (r['careers_page'] as String).trim().isNotEmpty).toList();

      setState(() {
        _restaurants = list;
        _loading = false;
      });
    } catch (e) {
      debugPrint('❌ Error carregant pàgines de feina: $e');
      setState(() => _loading = false);
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
        title: const Text('Pàgines de feina dels restaurants'),
        backgroundColor: Colors.green,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _restaurants.isEmpty
              ? const Center(child: Text('⚠️ No hi ha dades.'))
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _restaurants.length,
                  itemBuilder: (context, i) {
                    final r = _restaurants[i];
                    final name = r['name'];
                    final link = r['careers_page'];
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
                        subtitle: link.isEmpty
                            ? const Text('— Sense enllaç —',
                                style: TextStyle(color: Colors.grey))
                            : InkWell(
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
                                builder: (_) => RestaurantEditPage(
                                  initialSearch: name,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
