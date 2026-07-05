import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AdminButtonVisibilityService {
  AdminButtonVisibilityService._();

  static final AdminButtonVisibilityService instance =
      AdminButtonVisibilityService._();

  static const _preferenceKey = 'show_admin_button_on_map';

  final ValueNotifier<bool> enabled = ValueNotifier<bool>(false);

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    enabled.value = prefs.getBool(_preferenceKey) ?? false;
  }

  Future<void> setEnabled(bool value) async {
    if (enabled.value != value) {
      enabled.value = value;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_preferenceKey, value);
  }
}
