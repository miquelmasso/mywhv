import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class EmailsListPage extends StatefulWidget {
  const EmailsListPage({super.key});

  @override
  State<EmailsListPage> createState() => _EmailsListPageState();
}

class _EmailsListPageState extends State<EmailsListPage> {
  bool _loading = true;
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

      final list = snapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'name': data['name'] ?? 'Sense nom',
          'email': data['email'] ?? '',
        };
      }).toList();

      setState(() {
        _restaurants = list;
        _loading = false;
      });
    } catch (e) {
      print('❌ Error carregant correus: $e');
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Correus dels restaurants'),
        backgroundColor: Colors.blueAccent,
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
                    final email = r['email'];
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
                        subtitle: SelectableText(
                          email.isEmpty ? '— Sense correu —' : email,
                          style: TextStyle(
                            color: email.isEmpty ? Colors.grey : Colors.black87,
                          ),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
