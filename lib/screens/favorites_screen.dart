import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/favorites_service.dart';

class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  late Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _future;
  final Set<String> _removedIds = {};

  @override
  void initState() {
    super.initState();
    _future = FavoritesService.fetchFavoriteRestaurantsOnce();
  }

  Future<void> _removeFavorite(String id) async {
    await FavoritesService.removeFavorite(id); // mateixa lògica que al mapa
    setState(() {
      _removedIds.add(id);
    });
    // No snackbar: la UI reflecteix el cor desmarcat i es propaga al mapa.
  }

  Future<void> _addFavorite(String id) async {
    await FavoritesService.addFavorite(id);
    setState(() {
      _removedIds.remove(id);
    });
  }

  Future<void> _openUrl(String url) async {
    if (url.trim().isEmpty) return;
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No s’ha pogut obrir l’enllaç.')),
      );
    }
  }

  Future<void> _call(String phone) async => _openUrl('tel:$phone');
  Future<void> _email(String mail) async => _openUrl('mailto:$mail');
  Future<void> _openDirections(String address) async {
    if (address.trim().isEmpty) return;
    final uri = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=${Uri.encodeComponent(address)}');
    await _openUrl(uri.toString());
  }

  Widget _actionIcon(IconData icon, Color color, VoidCallback onTap, {String? tooltip}) {
    return IconButton(
      icon: Icon(icon, color: color),
      tooltip: tooltip,
      onPressed: onTap,
    );
  }

  Widget _buildCard(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final name = (data['name'] ?? '').toString();
    final address = (data['address'] ?? '').toString();
    final state = (data['state'] ?? '').toString();
    final postcode = (data['postcode'] ?? '').toString();
    final category = (data['category'] ?? '').toString();
    final phone = (data['phone'] ?? '').toString();
    final email = (data['email'] ?? '').toString();
    final facebook = (data['facebook_url'] ?? '').toString();
    final careers = (data['careers_page'] ?? '').toString();
    final instagram = (data['instagram_url'] ?? '').toString();

    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name.isEmpty ? 'Sense nom' : name,
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        address.isNotEmpty
                            ? address
                            : 'Postcode: $postcode${state.isNotEmpty ? ' • $state' : ''}',
                        style: const TextStyle(color: Colors.black54),
                      ),
                      if (category.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.blue.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            category,
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () {
                    final removed = _removedIds.contains(doc.id);
                    if (removed) {
                      _addFavorite(doc.id);
                    } else {
                      _removeFavorite(doc.id);
                    }
                  },
                  icon: Icon(
                    _removedIds.contains(doc.id) ? Icons.favorite_border : Icons.favorite,
                    color: _removedIds.contains(doc.id) ? Colors.grey : Colors.red,
                  ),
                  tooltip: _removedIds.contains(doc.id) ? 'Add to favourites' : 'Remove from favourites',
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                if (phone.isNotEmpty) _actionIcon(Icons.call, Colors.green, () => _call(phone), tooltip: 'Trucar'),
                if (email.isNotEmpty)
                  _actionIcon(Icons.email_outlined, Colors.redAccent, () => _email(email), tooltip: 'Email'),
                if (facebook.isNotEmpty)
                  _actionIcon(Icons.facebook, Colors.blue, () => _openUrl(facebook), tooltip: 'Facebook'),
                if (careers.isNotEmpty)
                  _actionIcon(Icons.work_outline, Colors.green, () => _openUrl(careers),
                      tooltip: 'Ofertes/feina'),
                if (instagram.isNotEmpty)
                  IconButton(
                    icon: const FaIcon(FontAwesomeIcons.instagram, color: Colors.purple),
                    tooltip: 'Instagram',
                    onPressed: () => _openUrl(instagram),
                  ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.directions, color: Colors.blueAccent),
                  tooltip: 'Com arribar',
                  onPressed: () => _openDirections(address.isNotEmpty ? address : name),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Favourites')),
      body: FutureBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Text('error loading favourites: ${snapshot.error}'),
            );
          }
          final docs = snapshot.data ?? [];
          if (docs.isEmpty) {
            return const Center(child: Text('No favourites yet'));
          }
          final ordered = List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(docs.reversed);
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            itemCount: ordered.length,
            itemBuilder: (context, index) => _buildCard(ordered[index]),
          );
        },
      ),
    );
  }
}
