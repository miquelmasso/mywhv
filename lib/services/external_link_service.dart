import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../screens/report_message_page.dart';

class ExternalLinkService {
  const ExternalLinkService._();

  static const String _brokenLinkAsset = 'assets/icons/Enllaç trencat cangur .png';

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
                padding: const EdgeInsets.fromLTRB(22, 18, 22, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(22),
                      child: SizedBox(
                        height: 142,
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
                    const SizedBox(height: 10),
                    const Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: 'Oops! ',
                            style: TextStyle(color: Color(0xFF7470C8)),
                          ),
                          TextSpan(text: 'Link failed'),
                        ],
                      ),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Color(0xFF151922),
                        fontSize: 24,
                        height: 1.12,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'This link is not available right now.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Color(0xFF5D6470),
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
                      child: const Row(
                        children: [
                          CircleAvatar(
                            radius: 21,
                            backgroundColor: Color(0xFF7470C8),
                            child: Icon(
                              Icons.lightbulb_outline_rounded,
                              color: Colors.white,
                            ),
                          ),
                          SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'What can you do?',
                                  style: TextStyle(
                                    color: Color(0xFF7470C8),
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  'Try again later or report it.',
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
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF7470C8),
                          side: const BorderSide(color: Color(0xFF7470C8)),
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
