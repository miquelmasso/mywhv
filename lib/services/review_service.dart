import 'package:flutter/material.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ReviewService {
  ReviewService._();

  static final ReviewService instance = ReviewService._();

  static const String _appStoreId = '6759898869';
  static const int _minimumAppOpens = 4;
  static const Duration _promptCooldown = Duration(days: 30);
  static const Duration _dismissalCooldown = Duration(days: 14);

  static const String actionWorkplaceDetailOpened = 'workplace_detail_opened';
  static const String actionContactOrExternalLinkTapped =
      'contact_or_external_link_tapped';
  static const String actionFavoriteSaved = 'favorite_saved';

  static const String _appOpenCountKey = 'review_app_open_count';
  static const String _positiveActionCountKey = 'review_positive_action_count';
  static const String _lastPositiveActionTypeKey =
      'review_last_positive_action_type';
  static const String _lastPromptAtKey = 'review_last_prompt_at_ms';
  static const String _lastDismissedAtKey = 'review_last_dismissed_at_ms';

  final InAppReview _inAppReview = InAppReview.instance;
  bool _promptInFlight = false;

  /// Counts app starts so the review prompt never appears on first launch.
  Future<void> registerAppOpen() async {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getInt(_appOpenCountKey) ?? 0;
    await prefs.setInt(_appOpenCountKey, current + 1);
  }

  /// Records a positive signal from the user.
  ///
  /// Add new triggers later by passing a new string action type from the
  /// relevant success path in the UI.
  Future<void> registerPositiveAction({required String actionType}) async {
    final trimmedActionType = actionType.trim();
    if (trimmedActionType.isEmpty) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getInt(_positiveActionCountKey) ?? 0;
    await prefs.setInt(_positiveActionCountKey, current + 1);
    await prefs.setString(_lastPositiveActionTypeKey, trimmedActionType);
  }

  /// Safe UI entry point: checks eligibility, shows a lightweight pre-prompt
  /// and then requests the native review flow when appropriate.
  Future<void> maybeAskForReview(BuildContext context) async {
    if (_promptInFlight || !context.mounted) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    if (!_isEligible(prefs)) {
      return;
    }
    if (!context.mounted) {
      return;
    }

    _promptInFlight = true;
    try {
      final shouldRequestReview = await _showPrePrompt(context);
      if (!context.mounted) {
        return;
      }

      if (shouldRequestReview == true) {
        await _markPromptShown(prefs);
        await requestInAppReview();
        return;
      }

      await _markDismissal(prefs);
    } finally {
      _promptInFlight = false;
    }
  }

  /// Requests the official in-app review sheet when the platform supports it.
  /// If the native prompt is unavailable, it falls back to the store listing.
  Future<void> requestInAppReview() async {
    try {
      if (await _inAppReview.isAvailable()) {
        await _inAppReview.requestReview();
      } else {
        await openStoreListing();
      }
    } catch (error) {
      debugPrint('ReviewService requestInAppReview failed: $error');
      await openStoreListing();
    }
  }

  /// Opens the public store listing as a manual fallback.
  Future<void> openStoreListing() async {
    try {
      await _inAppReview.openStoreListing(appStoreId: _appStoreId);
    } catch (error) {
      debugPrint('ReviewService openStoreListing failed: $error');
    }
  }

  bool _isEligible(SharedPreferences prefs) {
    final appOpens = prefs.getInt(_appOpenCountKey) ?? 0;
    if (appOpens < _minimumAppOpens) {
      return false;
    }

    final positiveActionCount = prefs.getInt(_positiveActionCountKey) ?? 0;
    if (positiveActionCount < 1) {
      return false;
    }

    final lastPromptAt = _readTimestamp(prefs, _lastPromptAtKey);
    if (lastPromptAt != null) {
      final elapsedSincePrompt = DateTime.now().difference(lastPromptAt);
      if (elapsedSincePrompt < _promptCooldown) {
        return false;
      }
    }

    final lastDismissedAt = _readTimestamp(prefs, _lastDismissedAtKey);
    if (lastDismissedAt != null) {
      final elapsedSinceDismissal = DateTime.now().difference(lastDismissedAt);
      if (elapsedSinceDismissal < _dismissalCooldown) {
        return false;
      }
    }

    return true;
  }

  Future<void> _markPromptShown(SharedPreferences prefs) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await prefs.setInt(_lastPromptAtKey, now);
  }

  Future<void> _markDismissal(SharedPreferences prefs) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await prefs.setInt(_lastDismissedAtKey, now);
  }

  DateTime? _readTimestamp(SharedPreferences prefs, String key) {
    final raw = prefs.getInt(key);
    if (raw == null || raw <= 0) {
      return null;
    }
    return DateTime.fromMillisecondsSinceEpoch(raw);
  }

  Future<bool?> _showPrePrompt(BuildContext context) {
    final borderRadius = BorderRadius.circular(24);
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: borderRadius),
          elevation: 8,
          backgroundColor: const Color(0xFFFFF7F5),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Icon(
                  Icons.star_outline_rounded,
                  size: 30,
                  color: Colors.black54,
                ),
                const SizedBox(height: 10),
                const Text(
                  'Are you enjoying WorkyDay?',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'WorkyDay is just getting started. Rate the app and tell us your favourite feature.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.black.withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.black87,
                          side: BorderSide(color: Colors.grey.shade400),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        onPressed: () => Navigator.of(dialogContext).pop(false),
                        child: const Text('Not now'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        onPressed: () => Navigator.of(dialogContext).pop(true),
                        child: const Text('Rate app'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
