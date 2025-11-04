import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class RestaurantEditPage extends StatefulWidget {
  const RestaurantEditPage({super.key});

  @override
  State<RestaurantEditPage> createState() => _RestaurantEditPageState();
}

class _RestaurantEditPageState extends State<RestaurantEditPage> {
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _results = [];
  Map<String, dynamic>? _selectedRestaurant;

  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _facebookController = TextEditingController();
  final TextEditingController _careersController = TextEditingController();

  bool _loading = false;
  bool _isBlocked = false;

  Future<void> _searchRestaurants(String query) async {
    if (query.isEmpty) {
      setState(() => _results = []);
      return;
    }

    final snapshot = await FirebaseFirestore.instance
        .collection('restaurants')
        .where('name', isGreaterThanOrEqualTo: query)
        .where('name', isLessThanOrEqualTo: '$query\uf8ff')
        .limit(10)
        .get();

    final results = snapshot.docs.map((doc) {
      return {'id': doc.id, ...doc.data()};
    }).toList();

    if (results.isEmpty) {
      final allDocs = await FirebaseFirestore.instance
          .collection('restaurants')
          .limit(100)
          .get();
      final filtered = allDocs.docs
          .where((d) {
            final name = (d['name'] ?? '').toString().toLowerCase();
            return name.contains(query.toLowerCase());
          })
          .map((d) => {'id': d.id, ...d.data()})
          .toList();
      setState(() => _results = filtered);
    } else {
      setState(() => _results = results);
    }
  }

  void _selectRestaurant(Map<String, dynamic> restaurant) {
    setState(() {
      _selectedRestaurant = restaurant;
      _emailController.text = restaurant['email'] ?? '';
      _facebookController.text = restaurant['facebook_url'] ?? '';
      _careersController.text = restaurant['careers_page'] ?? '';
      _isBlocked = restaurant['blocked'] ?? false;
      _results = [];
      _searchController.text = restaurant['name'] ?? '';
    });
  }

  Future<void> _saveChanges() async {
    if (_selectedRestaurant == null) return;
    setState(() => _loading = true);

    try {
      await FirebaseFirestore.instance
          .collection('restaurants')
          .doc(_selectedRestaurant!['id'])
          .update({
            'email': _emailController.text.trim(),
            'facebook_url': _facebookController.text.trim(),
            'careers_page': _careersController.text.trim(),
            'blocked': _isBlocked,
          });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ Canvis desats correctament!')),
      );
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('❌ Error al desar: $e')));
    } finally {
      setState(() => _loading = false);
    }
  }

  Widget _buildClearableField({
    required TextEditingController controller,
    required String label,
  }) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        suffixIcon: controller.text.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear, color: Colors.grey),
                onPressed: () {
                  setState(() => controller.clear());
                },
              )
            : null,
      ),
      onChanged: (_) => setState(() {}),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Editar restaurants')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _searchController,
              onChanged: _searchRestaurants,
              decoration: InputDecoration(
                labelText: 'Cerca un restaurant',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, color: Colors.grey),
                        onPressed: () {
                          setState(() {
                            _searchController.clear();
                            _results.clear();
                            _selectedRestaurant = null;
                          });
                        },
                      )
                    : null,
              ),
            ),
            if (_results.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(top: 4),
                padding: const EdgeInsets.symmetric(vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black12,
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                constraints: const BoxConstraints(maxHeight: 200),
                child: ListView.builder(
                  itemCount: _results.length,
                  itemBuilder: (context, index) {
                    final r = _results[index];
                    return ListTile(
                      title: Text(r['name'] ?? 'Sense nom'),
                      onTap: () => _selectRestaurant(r),
                    );
                  },
                ),
              ),
            const SizedBox(height: 16),
            if (_selectedRestaurant != null) ...[
              _buildClearableField(
                controller: _emailController,
                label: 'Correu electrònic',
              ),
              const SizedBox(height: 12),
              _buildClearableField(
                controller: _facebookController,
                label: 'Enllaç de Facebook',
              ),
              const SizedBox(height: 12),
              _buildClearableField(
                controller: _careersController,
                label: 'Pàgina de feina (careers)',
              ),
              const SizedBox(height: 20),
              SwitchListTile(
                title: const Text(
                  '🚫 Bloquejar restaurant',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                value: _isBlocked,
                onChanged: (value) async {
                  setState(() => _isBlocked = value);

                  if (value == true && _selectedRestaurant != null) {
                    // 🔹 Buida els camps i marca com bloquejat
                    _emailController.clear();
                    _facebookController.clear();
                    _careersController.clear();

                    await FirebaseFirestore.instance
                        .collection('restaurants')
                        .doc(_selectedRestaurant!['id'])
                        .update({
                          'email': '',
                          'facebook_url': '',
                          'careers_page': '',
                          'blocked': true,
                        });

                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          '🚫 Restaurant bloquejat i dades esborrades.',
                        ),
                        backgroundColor: Colors.redAccent,
                      ),
                    );
                  }
                },
                activeColor: Colors.redAccent,
              ),

              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _loading ? null : _saveChanges,
                icon: const Icon(Icons.save),
                label: _loading
                    ? const Text('Guardant...')
                    : const Text('Guardar canvis'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 48),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
