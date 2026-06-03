import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'external_link_service.dart';
import '../widgets/donation_popup.dart';

class DonationService {
  DonationService._();

  static final DonationService instance = DonationService._();

  static const String _openCountKey = 'donation_app_open_count';
  static const String _nextEligibleOpenKey = 'donation_next_eligible_open';
  static const String _supportedKey = 'donation_supported';
  static const String _stripeUrl =
      'https://buy.stripe.com/9B6bJ05c6eJSgjU7Sxbo401';

  static const int _firstPromptAfterOpens = 10;
  static const int _dismissedPromptDelayOpens = 20;

  bool _shownThisSession = false;

  Future<void> registerAppOpen() async {
    final prefs = await SharedPreferences.getInstance();
    final currentCount = prefs.getInt(_openCountKey) ?? 0;
    await prefs.setInt(_openCountKey, currentCount + 1);
  }

  Future<void> maybeShowAutomaticPopup(BuildContext context) async {
    if (_shownThisSession) return;

    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_supportedKey) ?? false) return;

    final openCount = prefs.getInt(_openCountKey) ?? 0;
    final nextEligibleOpen =
        prefs.getInt(_nextEligibleOpenKey) ?? (_firstPromptAfterOpens + 1);
    if (openCount <= _firstPromptAfterOpens || openCount < nextEligibleOpen) {
      return;
    }

    if (!context.mounted) return;
    _shownThisSession = true;
    await showSupportPopup(context);
  }

  Future<bool> showSupportPopup(BuildContext context) async {
    final result = await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Support WorkyDay',
      barrierColor: Colors.black.withValues(alpha: 0.42),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (dialogContext, _, _) {
        return DonationPopup(
          onClose: () => Navigator.of(dialogContext).pop(false),
          onSupport: () async {
            final navigator = Navigator.of(dialogContext);
            final opened = await _openStripeLink(dialogContext);
            if (opened) {
              await _markSupported();
              navigator.pop(true);
            }
          },
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.94, end: 1).animate(curved),
            child: child,
          ),
        );
      },
    );

    final supported = result ?? false;
    if (!supported) {
      await _markDismissed();
    }
    return supported;
  }

  Future<bool> _openStripeLink(BuildContext context) {
    return ExternalLinkService.open(context, _stripeUrl);
  }

  Future<void> _markSupported() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_supportedKey, true);
  }

  Future<void> _markDismissed() async {
    final prefs = await SharedPreferences.getInstance();
    final openCount = prefs.getInt(_openCountKey) ?? 0;
    await prefs.setInt(
      _nextEligibleOpenKey,
      openCount + _dismissedPromptDelayOpens,
    );
  }
}
