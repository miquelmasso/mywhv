import 'package:flutter/material.dart';

import '../config/admin_config.dart';
import '../services/admin_button_visibility_service.dart';

class ForumPage extends StatefulWidget {
  const ForumPage({super.key});

  @override
  State<ForumPage> createState() => _ForumPageState();
}

class _ForumPageState extends State<ForumPage> {
  bool _adminEnabled = isAdminSession;

  @override
  void initState() {
    super.initState();
    _syncAdminState();
  }

  Future<void> _syncAdminState() async {
    await loadAdminOverride();
    if (!mounted) return;
    setState(() => _adminEnabled = isAdminSession);
  }

  Future<void> _enableAdminMode() async {
    await setAdminOverride(true);
    await AdminButtonVisibilityService.instance.setEnabled(true);
    if (!mounted) return;
    setState(() => _adminEnabled = true);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Admin mode enabled')));
  }

  @override
  Widget build(BuildContext context) {
    final adminEnabled =
        _adminEnabled || AdminButtonVisibilityService.instance.enabled.value;

    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
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
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: adminEnabled ? null : _enableAdminMode,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF8FB3A1),
                    disabledBackgroundColor: const Color(0xFFDDE8E2),
                    foregroundColor: Colors.white,
                    disabledForegroundColor: const Color(0xFF527466),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                  child: Text(
                    adminEnabled ? 'Admin mode enabled' : 'Enable admin mode',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
