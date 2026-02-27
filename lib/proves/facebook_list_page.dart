import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';

import '../screens/restaurant_edit_page.dart';

class FacebookListPage extends StatefulWidget {
  const FacebookListPage({super.key});

  @override
  State<FacebookListPage> createState() => _FacebookListPageState();
}

class _FacebookListPageState extends State<FacebookListPage> {
  bool _loading = true;
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

      final list = snapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'name': data['name'] ?? 'Sense nom',
          'facebook_url': (data['facebook_url'] ?? '').toString(),
        };
      }).where((r) => (r['facebook_url'] as String).trim().isNotEmpty).toList();

      setState(() {
        _restaurants = list;
        _loading = false;
      });
    } catch (e) {
      debugPrint('❌ Error carregant enllaços de Facebook: $e');
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
        title: const Text('Enllaços de Facebook'),
        backgroundColor: Colors.indigo,
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
                    final link = r['facebook_url'];
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
