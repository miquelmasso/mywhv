import 'package:flutter/material.dart';

class MapMaintenancePage extends StatelessWidget {
  const MapMaintenancePage({super.key});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: const Color(0xFFFFF7F1),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(28),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 28,
                          offset: const Offset(0, 14),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(22),
                          child: Image.asset(
                            'assets/kangaroo_manteniment.png',
                            fit: BoxFit.cover,
                          ),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          'Hey legends 🫡\nThanks so much for downloading the app !\nThe map has crashed because of an overload of requests and users, but I’m already working on fixing it.\n\nIt should be back very soon with an update.\nAppreciate your patience ❤️',
                          textAlign: TextAlign.center,
                          style: textTheme.titleMedium?.copyWith(
                            height: 1.5,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF1F2937),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
