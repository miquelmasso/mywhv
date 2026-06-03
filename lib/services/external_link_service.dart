import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../screens/report_message_page.dart';

class ExternalLinkService {
  const ExternalLinkService._();

  static const String _brokenLinkAsset = 'assets/Enllaç trencat cangur .png';

  static Future<bool> open(
    BuildContext context,
    String? link, {
    LaunchMode mode = LaunchMode.externalApplication,
  }) async {
    final rawLink = link?.trim() ?? '';
    final uri = Uri.tryParse(rawLink);
    if (rawLink.isEmpty || uri == null || !uri.hasScheme) {
      if (context.mounted) await showBrokenLinkDialog(context);
      return false;
    }

    bool opened;
    try {
      opened = await launchUrl(uri, mode: mode);
    } catch (error) {
      debugPrint('External link open failed: $error');
      opened = false;
    }

    if (!opened && context.mounted) {
      await showBrokenLinkDialog(context);
    }
    return opened;
  }

  static Future<void> showBrokenLinkDialog(BuildContext context) async {
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
                padding: const EdgeInsets.fromLTRB(24, 26, 24, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(22),
                      child: SizedBox(
                        height: 190,
                        width: double.infinity,
                        child: Image.asset(
                          _brokenLinkAsset,
                          fit: BoxFit.cover,
                          alignment: const Alignment(0, 0.12),
                          errorBuilder: (_, _, _) => const Icon(
                            Icons.link_off_rounded,
                            size: 92,
                            color: Color(0xFF7470C8),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: 'Upsi! ',
                            style: TextStyle(color: Color(0xFF7470C8)),
                          ),
                          TextSpan(text: 'This link\nis not working'),
                        ],
                      ),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Color(0xFF151922),
                        fontSize: 25,
                        height: 1.12,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'It looks like this link is no longer available or has stopped working.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Color(0xFF5D6470),
                        fontSize: 15.5,
                        height: 1.35,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1EFFF),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: const Row(
                        children: [
                          CircleAvatar(
                            radius: 24,
                            backgroundColor: Color(0xFF7470C8),
                            child: Icon(
                              Icons.lightbulb_outline_rounded,
                              color: Colors.white,
                            ),
                          ),
                          SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'What can you do?',
                                  style: TextStyle(
                                    color: Color(0xFF7470C8),
                                    fontSize: 15.5,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  'Try again later or let us know so we can review it.',
                                  style: TextStyle(
                                    color: Color(0xFF151922),
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
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF7470C8),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        onPressed: () {
                          Navigator.of(dialogContext).pop();
                          Navigator.of(
                            context,
                            rootNavigator: true,
                          ).popUntil((route) => route.isFirst);
                        },
                        icon: const Icon(Icons.home_rounded),
                        label: const Text(
                          'Go to main menu',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF7470C8),
                          side: const BorderSide(color: Color(0xFF7470C8)),
                          padding: const EdgeInsets.symmetric(vertical: 13),
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
                right: 12,
                top: 12,
                child: Material(
                  color: const Color(0xFFF5F5F7),
                  shape: const CircleBorder(),
                  child: IconButton(
                    tooltip: 'Tancar',
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    icon: const Icon(
                      Icons.close_rounded,
                      color: Color(0xFF151922),
                    ),
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
