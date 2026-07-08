import 'package:flutter/material.dart';

import '../services/map_display_settings_service.dart';
import '../services/map_restaurants_refresh_service.dart';

class MapManagementPage extends StatefulWidget {
  const MapManagementPage({super.key});

  @override
  State<MapManagementPage> createState() => _MapManagementPageState();
}

class _MapManagementPageState extends State<MapManagementPage> {
  bool _isRefreshingRestaurants = false;

  Future<void> _refreshRestaurantsFromFirebase() async {
    if (_isRefreshingRestaurants) return;
    setState(() => _isRefreshingRestaurants = true);
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
    } catch (error) {
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
        setState(() => _isRefreshingRestaurants = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = MapDisplaySettingsService.instance;
    return Scaffold(
      appBar: AppBar(title: const Text('Map management')),
      body: ValueListenableBuilder<bool>(
        valueListenable: settings.showMaintenanceScreen,
        builder: (context, isMaintenanceVisible, _) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: SwitchListTile.adaptive(
                  value: isMaintenanceVisible,
                  title: const Text('Show maintenance screen'),
                  subtitle: Text(
                    isMaintenanceVisible
                        ? 'La primera pestanya del mapa mostra el missatge de manteniment.'
                        : 'La primera pestanya del mapa mostra el mapa OSM.',
                  ),
                  onChanged: (value) async {
                    await settings.setMaintenanceScreenVisible(value);
                    if (!context.mounted) {
                      return;
                    }
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          value
                              ? 'Pantalla de manteniment activada'
                              : 'Mapa OSM activat',
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              Text(
                isMaintenanceVisible
                    ? 'Quan esta activat, la pestanya principal deixa de mostrar el mapa i ensenya la pantalla de manteniment.'
                    : 'Quan esta desactivat, la pestanya principal mostra el mapa OSM de sempre.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    final nextValue = !isMaintenanceVisible;
                    await settings.setMaintenanceScreenVisible(nextValue);
                    if (!context.mounted) {
                      return;
                    }
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          nextValue
                              ? 'Pantalla de manteniment activada'
                              : 'Mapa OSM activat',
                        ),
                      ),
                    );
                  },
                  icon: Icon(
                    isMaintenanceVisible ? Icons.map_outlined : Icons.build,
                  ),
                  label: Text(
                    isMaintenanceVisible
                        ? 'Desactivar manteniment'
                        : 'Activar manteniment',
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isRefreshingRestaurants
                      ? null
                      : _refreshRestaurantsFromFirebase,
                  icon: _isRefreshingRestaurants
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2.2),
                        )
                      : const Icon(Icons.download_for_offline_outlined),
                  label: Text(
                    _isRefreshingRestaurants
                        ? 'Generant restaurants.json...'
                        : 'Generar restaurants.json',
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
