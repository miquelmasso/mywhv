import 'package:flutter/material.dart';

import '../services/admin_button_visibility_service.dart';

class ForumPage extends StatefulWidget {
  const ForumPage({super.key});

  @override
  State<ForumPage> createState() => _ForumPageState();
}

class _ForumPageState extends State<ForumPage> {
  Future<void> _enableAdminButton() async {
    await AdminButtonVisibilityService.instance.setEnabled(true);
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Admin button enabled on the map menu')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final adminEnabled = AdminButtonVisibilityService.instance.enabled.value;

    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
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
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: adminEnabled ? null : _enableAdminButton,
                icon: const Icon(Icons.admin_panel_settings),
                label: Text(
                  adminEnabled ? 'Admin mode enabled' : 'Activate admin mode',
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: adminEnabled
                      ? Colors.green
                      : Colors.blueGrey,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
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
