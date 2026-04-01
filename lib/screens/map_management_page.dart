import 'package:flutter/material.dart';

import '../services/map_display_settings_service.dart';

class MapManagementPage extends StatelessWidget {
  const MapManagementPage({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = MapDisplaySettingsService.instance;
    return Scaffold(
      appBar: AppBar(title: const Text('Gestio de mapa')),
      body: ValueListenableBuilder<bool>(
        valueListenable: settings.showMaintenanceScreen,
        builder: (context, isMaintenanceVisible, _) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: SwitchListTile.adaptive(
                  value: isMaintenanceVisible,
                  title: const Text('Mostrar pantalla de manteniment'),
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
            ],
          );
        },
      ),
    );
  }
}
