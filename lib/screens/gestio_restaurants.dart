import 'package:flutter/material.dart';
import '../services/map_restaurants_refresh_service.dart';
import 'add_restaurants_by_postcode_page.dart';
import 'add_restaurants_by_state_page.dart';

class TipsPage extends StatefulWidget {
  const TipsPage({super.key});

  @override
  State<TipsPage> createState() => _TipsPageState();
}

class _TipsPageState extends State<TipsPage> {
  bool _isGeneratingRestaurantsJson = false;

  Future<void> _generateRestaurantsJson() async {
    if (_isGeneratingRestaurantsJson) return;
    setState(() => _isGeneratingRestaurantsJson = true);
    try {
      final result = await MapRestaurantsRefreshService.instance
          .refreshFromFirebase();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'restaurants.json generat. ${result.count} restaurants sincronitzats.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'We could not generate restaurants.json right now. Please try again.',
          ),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isGeneratingRestaurantsJson = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Restaurant management',
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
              label: const Text('Add by postcode'),
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
              label: const Text('Add by state'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 52),
                backgroundColor: Colors.green.shade600,
                foregroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 14),
            ElevatedButton.icon(
              onPressed: _isGeneratingRestaurantsJson
                  ? null
                  : _generateRestaurantsJson,
              icon: _isGeneratingRestaurantsJson
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2.2),
                    )
                  : const Icon(Icons.download_for_offline_outlined),
              label: Text(
                _isGeneratingRestaurantsJson
                    ? 'Generant restaurants.json...'
                    : 'Generar restaurants.json',
              ),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 52),
                backgroundColor: Colors.orange.shade700,
                foregroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Genera el fitxer intern que anira dins la propera versio de l’app.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}
