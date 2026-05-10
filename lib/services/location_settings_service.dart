import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

class LocationSettingsService {
  LocationSettingsService._();

  static const MethodChannel _channel = MethodChannel(
    'workyday/location_settings',
  );

  static Future<bool> openLocationPermissionSettings() async {
    try {
      final opened = await _channel.invokeMethod<bool>(
        'openLocationPermissionSettings',
      );
      if (opened ?? false) {
        return true;
      }
    } catch (_) {}

    return openAppSettings();
  }
}
