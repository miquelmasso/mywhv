import 'package:flutter/material.dart';

import 'mail_setup_page.dart';
import 'restaurant_edit_page.dart';
import 'gestio_restaurants.dart';
import 'manage_farms_page.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

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

                  const SizedBox(height: 16),

                  // 🌾 Gestionar farms (afegir/eliminar per estat)
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const ManageFarmsPage(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.agriculture),
                    label: const Text('Gestionar farms'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.brown.shade600,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
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
