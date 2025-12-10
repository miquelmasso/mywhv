import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'mail_setup_page.dart';
import 'restaurant_edit_page.dart';
import 'gestio_restaurants.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  Future<void> resetWorkedHereCount(BuildContext context) async {
    try {
      final firestore = FirebaseFirestore.instance;

      final query = await firestore.collection('restaurants').get();

      WriteBatch batch = firestore.batch();

      for (var doc in query.docs) {
        batch.update(doc.reference, {'worked_here_count': 0});
      }

      await batch.commit();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tots els worked_here_count s’han posat a 0!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error fent reset: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Perfil')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Configuració de perfil',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            const Text(
              'Des d’aquí pots configurar el teu correu automàtic, editar la informació dels restaurants o accedir a les eines de gestió i comprovació.',
              style: TextStyle(fontSize: 15),
            ),
            const SizedBox(height: 24),

            Center(
              child: Column(
                children: [
                  // 📨 Configurar correu automàtic
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const MailSetupPage()),
                      );
                    },
                    icon: const Icon(Icons.email_outlined),
                    label: const Text('Configurar correu automàtic'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // ✏️ Editar restaurants
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const RestaurantEditPage()),
                      );
                    },
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Editar restaurants'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueAccent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // 🧭 Gestió i comprovació
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const TipsPage()),
                      );
                    },
                    icon: const Icon(Icons.build_circle_outlined),
                    label: const Text('Gestió i comprovació'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // 🔄 RESET worked_here_count
                  ElevatedButton.icon(
                    onPressed: () async {
                      await resetWorkedHereCount(context);
                    },
                    icon: const Icon(Icons.restore),
                    label: const Text('Reset worked_here_count'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepPurple,
                      foregroundColor: Colors.white,
                      padding:
                          const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
