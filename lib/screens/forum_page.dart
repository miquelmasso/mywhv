import 'package:flutter/material.dart';

import '../config/admin_config.dart';
import '../services/map_display_settings_service.dart';

class ForumPage extends StatelessWidget {
  const ForumPage({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = MapDisplaySettingsService.instance;
    return Scaffold(
      body: Center(
        child: ValueListenableBuilder<bool>(
          valueListenable: settings.showMaintenanceScreen,
          builder: (context, isMaintenanceVisible, _) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Forum (soon)',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                const Text(
                  'a community to help each other',
                  style: TextStyle(fontSize: 14, color: Colors.black54),
                  textAlign: TextAlign.center,
                ),
                if (isAdminSession) ...[
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
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
                      isMaintenanceVisible
                          ? Icons.map_outlined
                          : Icons.build_circle_outlined,
                    ),
                    label: Text(
                      isMaintenanceVisible
                          ? 'Desactivar manteniment'
                          : 'Activar manteniment',
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}
