import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/map_markers_service.dart';
import 'add_restaurants_by_postcode_page.dart';
import 'add_restaurants_by_state_page.dart';

class TipsPage extends StatefulWidget {
  const TipsPage({super.key});

  @override
  State<TipsPage> createState() => _TipsPageState();
}

class _TipsPageState extends State<TipsPage> {
  bool _isRefreshing = false;

  Future<void> _refreshRestaurants() async {
    setState(() => _isRefreshing = true);
    try {
      await FirebaseFirestore.instance.enableNetwork();
      final restaurants = await MapMarkersService.loadRestaurants(fromServer: true);
      if (!mounted) return;

      final total = restaurants.length;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            total == 0
                ? '⚠️ No s’han trobat restaurants al servidor.'
                : '✅ $total restaurants actualitzats des del servidor.',
          ),
          backgroundColor: total == 0 ? Colors.orange : Colors.green.shade700,
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error actualitzant restaurants: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      await FirebaseFirestore.instance.disableNetwork();
      if (mounted) setState(() => _isRefreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Gestió de restaurants',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0.5,
      ),
      backgroundColor: Colors.white,
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'Com vols afegir restaurants?',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                height: 1.3,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const AddRestaurantsByPostcodePage(),
                  ),
                );
              },
              icon: const Icon(Icons.location_on),
              label: const Text('Afegir per codi postal'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 52),
                backgroundColor: Colors.blueAccent,
                foregroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 14),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const AddRestaurantsByStatePage(),
                  ),
                );
              },
              icon: const Icon(Icons.map),
              label: const Text('Afegir per estat'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 52),
                backgroundColor: Colors.green.shade600,
                foregroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 14),
            ElevatedButton.icon(
              onPressed: _isRefreshing ? null : _refreshRestaurants,
              icon: _isRefreshing
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Icon(Icons.sync),
              label: Text(_isRefreshing ? 'Actualitzant...' : 'Actualitzar restaurants'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 52),
                backgroundColor: Colors.orange.shade700,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
