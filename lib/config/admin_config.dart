import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String adminUid = 'EuCfztB40CNpQ9OqosqF0H8TBUc2';
const String _adminOverridePrefsKey = 'admin_mode_override_enabled';

bool _adminOverrideEnabled = false;

bool get isAdminSession =>
    _adminOverrideEnabled || FirebaseAuth.instance.currentUser?.uid == adminUid;

bool get isAdminOverrideEnabled => _adminOverrideEnabled;

Future<void> loadAdminOverride() async {
  final prefs = await SharedPreferences.getInstance();
  _adminOverrideEnabled = prefs.getBool(_adminOverridePrefsKey) ?? false;
}

Future<void> setAdminOverride(bool enabled) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_adminOverridePrefsKey, enabled);
  _adminOverrideEnabled = enabled;
}
