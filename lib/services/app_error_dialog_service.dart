import 'package:flutter/material.dart';

import '../screens/report_message_page.dart';
import '../utils/app_i18n.dart';

class AppErrorDialogService {
  const AppErrorDialogService._();

  static const Color _accent = Color(0xFF7470C8);
  static const Color _ink = Color(0xFF151922);
  static const String _sadKangarooAsset = 'assets/icons/kangaroo_sad.png';

  static Future<void> showMapAssetErrorDialog(BuildContext context) async {
    final strings = await AppI18n.load();
    if (!context.mounted) return;
    return showCriticalErrorDialog(
      context,
      imageAsset: _sadKangarooAsset,
      titlePrefix: AppI18n.t(strings, 'error.oops'),
      title: AppI18n.t(strings, 'error.load_title'),
      message: AppI18n.t(strings, 'error.load_message'),
      helperTitle: AppI18n.t(strings, 'common.next_step'),
      helperText: AppI18n.t(strings, 'error.try_report'),
      reportLabel: AppI18n.t(strings, 'common.report_problem'),
      closeTooltip: AppI18n.t(strings, 'common.close'),
    );
  }

  static Future<void> showMailErrorDialog(BuildContext context) async {
    final strings = await AppI18n.load();
    if (!context.mounted) return;
    return showCriticalErrorDialog(
      context,
      imageAsset: _sadKangarooAsset,
      titlePrefix: AppI18n.t(strings, 'error.oops'),
      title: AppI18n.t(strings, 'error.email_title'),
      message: AppI18n.t(strings, 'error.email_message'),
      helperTitle: AppI18n.t(strings, 'common.next_step'),
      helperText: AppI18n.t(strings, 'error.email_helper'),
      reportLabel: AppI18n.t(strings, 'common.report_problem'),
      closeTooltip: AppI18n.t(strings, 'common.close'),
    );
  }

  static Future<void> showCriticalErrorDialog(
    BuildContext context, {
    required String title,
    required String message,
    required String helperTitle,
    required String helperText,
    String? titlePrefix,
    String imageAsset = _sadKangarooAsset,
    String reportLabel = 'Report a problem',
    String closeTooltip = 'Close',
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
                            child: Image.asset(
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
                            child: Text.rich(
                              TextSpan(
                                children: [
                                  if (titlePrefix != null)
                                    TextSpan(
                                      text: titlePrefix,
                                      style: const TextStyle(color: _accent),
                                    ),
                                  TextSpan(text: title),
                                ],
                              ),
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
                        label: Text(
                          reportLabel,
                          style: const TextStyle(fontWeight: FontWeight.w800),
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
                    tooltip: closeTooltip,
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

class AppCriticalErrorState extends StatelessWidget {
  const AppCriticalErrorState({
    super.key,
    required this.title,
    required this.message,
    required this.onRetry,
    this.imageAsset = AppErrorDialogService._sadKangarooAsset,
  });

  final String title;
  final String message;
  final VoidCallback onRetry;
  final String imageAsset;

  @override
  Widget build(BuildContext context) {
    final strings = AppI18n.forCode(
      WidgetsBinding.instance.platformDispatcher.locale.languageCode,
    );
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(24, 26, 24, 24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 26,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 150,
                child: Image.asset(
                  imageAsset,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => const Icon(
                    Icons.error_outline_rounded,
                    size: 84,
                    color: Color(0xFF7470C8),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF151922),
                  fontSize: 26,
                  height: 1.12,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF5D6470),
                  fontSize: 15.5,
                  height: 1.35,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF7470C8),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded),
                  label: Text(
                    AppI18n.t(strings, 'common.try_again'),
                    style: const TextStyle(fontWeight: FontWeight.w800),
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
