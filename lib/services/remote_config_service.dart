import 'dart:async';
import 'dart:io';

import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_store_links.dart';
import '../widgets/update_notice_widgets.dart';

enum AppUpdateType { forced, soft }

class AppUpdateNotice {
  const AppUpdateNotice({
    required this.type,
    required this.message,
    required this.currentVersion,
    required this.latestVersion,
    required this.minSupportedVersion,
  });

  final AppUpdateType type;
  final String message;
  final String currentVersion;
  final String latestVersion;
  final String minSupportedVersion;

  bool get isForced => type == AppUpdateType.forced;
  bool get isSoft => type == AppUpdateType.soft;
}

class UpdateService {
  UpdateService._();

  static final UpdateService instance = UpdateService._();

  static const String _softUpdateSeenVersionKey = 'soft_update_seen_version';

  final FirebaseRemoteConfig _remoteConfig = FirebaseRemoteConfig.instance;
  final ValueNotifier<AppUpdateNotice?> _softUpdateNotice =
      ValueNotifier<AppUpdateNotice?>(null);
  final ValueNotifier<bool> _forceUpdateLaunching = ValueNotifier<bool>(false);
  final ValueNotifier<String?> _forceUpdateLaunchError = ValueNotifier<String?>(
    null,
  );

  OverlayEntry? _softBannerEntry;
  Timer? _softBannerTimer;
  bool _isInitialized = false;
  bool _forceDialogVisible = false;
  Future<void>? _initFuture;

  ValueListenable<AppUpdateNotice?> get softUpdateNoticeListenable =>
      _softUpdateNotice;

  Future<void> init() async {
    if (_isInitialized) return;
    await (_initFuture ??= _initInternal());
  }

  Future<void> _initInternal() async {
    if (_isInitialized) return;

    await _remoteConfig.setConfigSettings(
      RemoteConfigSettings(
        fetchTimeout: const Duration(seconds: 15),
        minimumFetchInterval: const Duration(hours: 12),
      ),
    );

    await _remoteConfig.setDefaults(const <String, Object>{
      'latest_version': '',
      'min_supported_version': '',
      'update_message': '',
    });

    try {
      await _remoteConfig.fetchAndActivate();
    } catch (error) {
      debugPrint('UpdateService init failed: $error');
    }

    await _refreshComputedState();
    _isInitialized = true;
  }

  Future<void> refresh() async {
    if (!_isInitialized) {
      await init();
    }

    try {
      await _remoteConfig.fetchAndActivate();
    } catch (error) {
      debugPrint('UpdateService refresh failed: $error');
    }

    await _refreshComputedState();
  }

  Future<AppUpdateNotice?> getUpdateNotice() async {
    if (!_isInitialized) {
      await init();
    }
    return _refreshComputedState();
  }

  Future<void> maybeShowUpdateDialog(BuildContext context) async {
    if (!_isInitialized) {
      await init();
    }

    if (!context.mounted) {
      return;
    }

    final notice = await getUpdateNotice();
    if (notice == null || !context.mounted) {
      return;
    }

    if (notice.isForced) {
      await _showForcedUpdateDialog(context, notice);
      return;
    }

    final hasSeenSoftUpdate = await _hasSeenSoftUpdate(notice.latestVersion);
    if (hasSeenSoftUpdate) {
      return;
    }

    await _markSoftUpdateSeen(notice.latestVersion);
    _softUpdateNotice.value = notice;
    if (!context.mounted) {
      return;
    }
    _showSoftUpdateBanner(context, notice);
  }

  String get _storeUrl => Platform.isIOS
      ? AppStoreLinks.iosStoreUrl
      : AppStoreLinks.androidStoreUrl;

  Future<bool> openStoreListing() async {
    final uri = Uri.parse(_storeUrl);
    if (await _tryLaunchStore(uri, LaunchMode.externalApplication)) {
      return true;
    }
    if (await _tryLaunchStore(uri, LaunchMode.platformDefault)) {
      return true;
    }
    debugPrint(
      'UpdateService openStoreListing failed: no handler could open $_storeUrl',
    );
    return false;
  }

  Future<AppUpdateNotice?> _refreshComputedState() async {
    final packageInfo = await PackageInfo.fromPlatform();
    final currentVersion = packageInfo.version.trim();
    final latestVersion = _remoteConfig.getString('latest_version').trim();
    final minSupportedVersion = _remoteConfig
        .getString('min_supported_version')
        .trim();
    final updateMessage = _remoteConfig.getString('update_message').trim();

    if (currentVersion.isEmpty) {
      _softUpdateNotice.value = null;
      return null;
    }

    final requiresForcedUpdate =
        minSupportedVersion.isNotEmpty &&
        _compareVersions(currentVersion, minSupportedVersion) < 0;

    if (requiresForcedUpdate) {
      _softUpdateNotice.value = null;
      return AppUpdateNotice(
        type: AppUpdateType.forced,
        message: _resolveMessage(updateMessage, forced: true),
        currentVersion: currentVersion,
        latestVersion: latestVersion,
        minSupportedVersion: minSupportedVersion,
      );
    }

    final needsSoftUpdate =
        latestVersion.isNotEmpty &&
        _compareVersions(currentVersion, latestVersion) < 0;

    if (!needsSoftUpdate) {
      _softUpdateNotice.value = null;
      return null;
    }

    final notice = AppUpdateNotice(
      type: AppUpdateType.soft,
      message: _resolveMessage(updateMessage, forced: false),
      currentVersion: currentVersion,
      latestVersion: latestVersion,
      minSupportedVersion: minSupportedVersion,
    );
    final hasSeenSoftUpdate = await _hasSeenSoftUpdate(latestVersion);
    _softUpdateNotice.value = hasSeenSoftUpdate ? notice : null;
    return notice;
  }

  Future<void> _showForcedUpdateDialog(
    BuildContext context,
    AppUpdateNotice notice,
  ) async {
    if (_forceDialogVisible || !context.mounted) {
      return;
    }

    _removeSoftUpdateBanner();
    _forceDialogVisible = true;
    _forceUpdateLaunching.value = false;
    _forceUpdateLaunchError.value = null;

    try {
      await showGeneralDialog<void>(
        context: context,
        barrierDismissible: false,
        barrierLabel: 'Update required',
        barrierColor: Colors.transparent,
        transitionDuration: const Duration(milliseconds: 180),
        pageBuilder: (dialogContext, _, _) {
          return PopScope(
            canPop: false,
            child: ForceUpdateOverlay(
              message: notice.message,
              storeUrl: _storeUrl,
              isLaunchingListenable: _forceUpdateLaunching,
              errorMessageListenable: _forceUpdateLaunchError,
              onUpdateNow: () {
                unawaited(_handleForcedUpdateTap());
              },
              onCopyStoreLink: () {
                unawaited(_copyStoreLink());
              },
            ),
          );
        },
        transitionBuilder: (dialogContext, animation, secondary, child) {
          final curved = Curves.easeOutCubic.transform(animation.value);
          return Opacity(
            opacity: animation.value,
            child: Transform.scale(scale: 0.96 + (0.04 * curved), child: child),
          );
        },
      );
    } finally {
      _forceDialogVisible = false;
    }
  }

  void _showSoftUpdateBanner(BuildContext context, AppUpdateNotice notice) {
    _removeSoftUpdateBanner();

    final overlay = Overlay.of(context, rootOverlay: true);

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) {
        return Material(
          color: Colors.transparent,
          child: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _removeSoftUpdateBanner,
                  child: const SizedBox.expand(),
                ),
              ),
              Positioned.fill(
                child: SafeArea(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 360),
                        child: GestureDetector(
                          onTap: () {},
                          child: SoftUpdateBanner(
                            message: notice.message,
                            onUpdateNow: () {
                              _removeSoftUpdateBanner();
                              unawaited(openStoreListing());
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );

    _softBannerEntry = entry;
    overlay.insert(entry);
    _softBannerTimer = Timer(
      const Duration(seconds: 5),
      _removeSoftUpdateBanner,
    );
  }

  void _removeSoftUpdateBanner() {
    _softBannerTimer?.cancel();
    _softBannerTimer = null;
    _softBannerEntry?.remove();
    _softBannerEntry = null;
  }

  Future<void> _handleForcedUpdateTap() async {
    if (_forceUpdateLaunching.value) {
      return;
    }

    _forceUpdateLaunchError.value = null;
    _forceUpdateLaunching.value = true;
    final opened = await openStoreListing();
    _forceUpdateLaunching.value = false;

    if (!opened) {
      _forceUpdateLaunchError.value =
          'We could not open the store automatically. Use the link below to update manually.';
    }
  }

  Future<void> _copyStoreLink() async {
    await Clipboard.setData(ClipboardData(text: _storeUrl));
    _forceUpdateLaunchError.value =
        'Update link copied. Paste it into your browser if the store app does not open.';
  }

  Future<bool> _tryLaunchStore(Uri uri, LaunchMode mode) async {
    try {
      return await launchUrl(uri, mode: mode);
    } catch (error) {
      debugPrint('UpdateService openStoreListing failed ($mode): $error');
      return false;
    }
  }

  String _resolveMessage(String remoteMessage, {required bool forced}) {
    if (remoteMessage.isNotEmpty) {
      return remoteMessage;
    }

    return forced
        ? 'A new version is required to keep using the app.'
        : 'A newer version of the app is available.';
  }

  int _compareVersions(String left, String right) {
    final leftParts = _parseVersion(left);
    final rightParts = _parseVersion(right);
    final maxLength = leftParts.length > rightParts.length
        ? leftParts.length
        : rightParts.length;

    for (var index = 0; index < maxLength; index++) {
      final leftValue = index < leftParts.length ? leftParts[index] : 0;
      final rightValue = index < rightParts.length ? rightParts[index] : 0;

      if (leftValue > rightValue) {
        return 1;
      }
      if (leftValue < rightValue) {
        return -1;
      }
    }

    return 0;
  }

  List<int> _parseVersion(String version) {
    return version
        .split(RegExp(r'[^0-9]+'))
        .where((part) => part.isNotEmpty)
        .map(int.parse)
        .toList();
  }

  Future<bool> _hasSeenSoftUpdate(String latestVersion) async {
    if (latestVersion.isEmpty) {
      return false;
    }

    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_softUpdateSeenVersionKey) == latestVersion;
  }

  Future<void> _markSoftUpdateSeen(String latestVersion) async {
    if (latestVersion.isEmpty) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_softUpdateSeenVersionKey, latestVersion);
  }

}

class RemoteConfigService {
  RemoteConfigService._();

  static UpdateService get instance => UpdateService.instance;
}
