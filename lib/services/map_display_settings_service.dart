import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MapDisplaySettingsService {
  MapDisplaySettingsService._();

  static final MapDisplaySettingsService instance =
      MapDisplaySettingsService._();

  static const String _showMaintenanceScreenKey = 'show_map_maintenance_screen';

  final ValueNotifier<bool> showMaintenanceScreen = ValueNotifier<bool>(false);

  bool get isMaintenanceScreenVisible => showMaintenanceScreen.value;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final storedValue = prefs.getBool(_showMaintenanceScreenKey);
    showMaintenanceScreen.value = storedValue ?? false;
    if (storedValue == null) {
      await prefs.setBool(_showMaintenanceScreenKey, false);
    }
  }

  Future<void> setMaintenanceScreenVisible(bool visible) async {
    if (showMaintenanceScreen.value == visible) {
      return;
    }
    showMaintenanceScreen.value = visible;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_showMaintenanceScreenKey, visible);
  }
}
