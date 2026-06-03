import 'package:flutter/material.dart';

import '../screens/report_message_page.dart';

class AppErrorDialogs {
  const AppErrorDialogs._();

  static const Color _accent = Color(0xFF7470C8);
  static const Color _ink = Color(0xFF151922);
  static const Color _muted = Color(0xFF5D6470);

  static Future<void> showMapAssetError(
    BuildContext context, {
    VoidCallback? onRetry,
  }) {
    return show(
      context,
      title: 'Didn\'t load',
      message: 'Something went wrong. Please try again.',
      helperTitle: 'Next step',
      helperText: 'Try again later or report it.',
      imageAsset: 'assets/kangaroo_sad.png',
    );
  }

  static Future<void> showMailError(BuildContext context) {
    return show(
      context,
      title: 'Email failed',
      message: 'We could not open your email app.',
      helperTitle: 'Next step',
      helperText: 'Check Mail setup or report it.',
      imageAsset: 'assets/kangaroo_sad.png',
    );
  }

  static Future<void> show(
    BuildContext context, {
    required String title,
    required String message,
    required String helperTitle,
    required String helperText,
    String? imageAsset,
  }) async {
    if (!context.mounted) return;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 24),
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          child: Stack(
            children: [
              SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 18, 22, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 48),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 50,
                            height: 64,
                            child: imageAsset == null
                                ? const Icon(
                                    Icons.error_outline_rounded,
                                    size: 46,
                                    color: _accent,
                                  )
                                : Image.asset(
                                    imageAsset,
                                    fit: BoxFit.contain,
                                    errorBuilder: (_, _, _) => const Icon(
                                      Icons.error_outline_rounded,
                                      size: 46,
                                      color: _accent,
                                    ),
                                  ),
                          ),
                          const SizedBox(width: 2),
                          Flexible(
                            child: Text(
                              title,
                              textAlign: TextAlign.left,
                              style: const TextStyle(
                                color: _ink,
                                fontSize: 21,
                                height: 1.08,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      message,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: _muted,
                        fontSize: 15.5,
                        height: 1.35,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1EFFF),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Row(
                        children: [
                          const CircleAvatar(
                            radius: 21,
                            backgroundColor: _accent,
                            child: Icon(
                              Icons.lightbulb_outline_rounded,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  helperTitle,
                                  style: const TextStyle(
                                    color: _accent,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  helperText,
                                  style: const TextStyle(
                                    color: _ink,
                                    fontSize: 14,
                                    height: 1.28,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _accent,
                          side: const BorderSide(color: _accent),
                          padding: const EdgeInsets.symmetric(vertical: 11),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        onPressed: () {
                          Navigator.of(dialogContext).pop();
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const ReportMessagePage(),
                            ),
                          );
                        },
                        icon: const Icon(Icons.mail_outline_rounded),
                        label: const Text(
                          'Report a problem',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                right: 10,
                top: 10,
                child: Material(
                  color: const Color(0xFFF5F5F7),
                  shape: const CircleBorder(),
                  child: IconButton(
                    constraints: const BoxConstraints.tightFor(
                      width: 42,
                      height: 42,
                    ),
                    padding: EdgeInsets.zero,
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    icon: const Icon(Icons.close_rounded, color: _ink),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
