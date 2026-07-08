import 'package:flutter/material.dart';

import '../utils/app_i18n.dart';

class DonationPopup extends StatelessWidget {
  const DonationPopup({
    super.key,
    required this.onClose,
    required this.onSupport,
  });

  static const Color workyDayYellow = Color(0xFFEFC84A);
  static const Color textColor = Color(0xFF20242C);

  final VoidCallback onClose;
  final VoidCallback onSupport;

  @override
  Widget build(BuildContext context) {
    final maxWidth = MediaQuery.sizeOf(context).width - 48;

    return FutureBuilder<Map<String, String>>(
      future: AppI18n.load(),
      initialData: AppI18n.forCode('en'),
      builder: (context, snapshot) {
        final strings = snapshot.data ?? AppI18n.forCode('en');
        String t(String key) => AppI18n.t(strings, key);

        return Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: maxWidth.clamp(280.0, 360.0).toDouble(),
            ),
            child: Material(
              color: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.fromLTRB(24, 22, 24, 24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.16),
                      blurRadius: 28,
                      spreadRadius: -8,
                      offset: const Offset(0, 18),
                    ),
                  ],
                ),
                child: Stack(
                  children: [
                    Positioned(
                      top: -8,
                      right: -8,
                      child: IconButton(
                        onPressed: onClose,
                        icon: const Icon(Icons.close_rounded),
                        color: const Color(0xFF74777F),
                        tooltip: t('common.close'),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 82,
                            height: 82,
                            decoration: BoxDecoration(
                              color: workyDayYellow,
                              shape: BoxShape.circle,
                            ),
                            alignment: Alignment.center,
                            child: ClipOval(
                              child: Image.asset(
                                'assets/ios_icon.png',
                                width: 68,
                                height: 68,
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                          const SizedBox(height: 18),
                          Text(
                            '❤️ ${t('donation.title')}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: textColor,
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            t('donation.body'),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Color(0xFF5E626B),
                              fontSize: 14.5,
                              height: 1.38,
                              fontWeight: FontWeight.w500,
                              letterSpacing: 0,
                            ),
                          ),
                          const SizedBox(height: 22),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              onPressed: onSupport,
                              style: FilledButton.styleFrom(
                                backgroundColor: workyDayYellow,
                                foregroundColor: const Color(0xFF2D2508),
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 15,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(18),
                                ),
                              ),
                              child: Text(
                                t('donation.button'),
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0,
                                ),
                              ),
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
        );
      },
    );
  }
}
