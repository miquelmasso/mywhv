import 'dart:async';
import 'dart:ui';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'firebase_options.dart';
import 'features/onboarding/onboarding_controller.dart';
import 'features/onboarding/onboarding_overlay.dart';
import 'features/onboarding/onboarding_steps.dart';
import 'navigation/route_observer.dart';
import 'screens/forum_page.dart';
import 'screens/guide_screen.dart';
import 'screens/map_maintenance_page.dart';
import 'screens/map_screen.dart';
import 'screens/admin_gate_page.dart';
import 'screens/tips_random_page.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'services/offline_bootstrap_service.dart';
import 'services/map_display_settings_service.dart';
import 'services/map_markers_service.dart';
import 'services/remote_config_service.dart';
import 'services/runtime_device_service.dart';
import 'services/review_service.dart';

Future<void> main() async {
  final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  await dotenv.load(fileName: ".env");

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  // Mantén la xarxa de Firestore desactivada per defecte
  //await FirebaseFirestore.instance.disableNetwork();
  debugPrint('✅ Firebase initialized correctly');

  await MapDisplaySettingsService.instance.init();
  await RuntimeDeviceService.instance.init();
  final shouldShowOnboarding =
      await OnboardingController.peekShouldShowOnLaunch();
  final initialHomeIndex =
      shouldShowOnboarding &&
          !MapDisplaySettingsService.instance.isMaintenanceScreenVisible
      ? 1
      : 0;

  runApp(MyApp(initialHomeIndex: initialHomeIndex));
  FlutterNativeSplash.remove();
  unawaited(_bootstrapDeferredAppServices());
}

Future<void> _bootstrapDeferredAppServices() async {
  try {
    await Future.wait<void>([
      OfflineBootstrapService.instance.init(),
      RemoteConfigService.instance.init(),
      ReviewService.instance.registerAppOpen(),
    ]);
  } catch (error) {
    debugPrint('⚠️ Deferred app bootstrap failed: $error');
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, required this.initialHomeIndex});

  final int initialHomeIndex;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WorkyDay',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color.fromARGB(255, 215, 10, 10),
        ),
      ),
      navigatorObservers: [routeObserver],
      home: MyHomePage(initialIndex: initialHomeIndex),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, this.initialIndex = 1});

  final int initialIndex;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  static const bool _enableOnboarding = true;
  static const int _mapTabIndex = 0;
  static const int _guideTabIndex = 1;

  late int _selectedIndex;
  int _adminTapCount = 0;
  DateTime? _adminFirstTap;
  int _onboardingSyncToken = 0;
  late final Set<int> _loadedTabIndices;

  final GlobalKey<MapScreenState> _primaryOsmMapPageKey =
      GlobalKey<MapScreenState>();
  final GlobalKey _mapTabIconKey = GlobalKey();
  final GlobalKey _guideTabIconKey = GlobalKey();
  OnboardingController? _onboardingController;
  late bool _isMaintenanceScreenVisible;

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialIndex;
    _loadedTabIndices = <int>{widget.initialIndex};
    _isMaintenanceScreenVisible =
        MapDisplaySettingsService.instance.isMaintenanceScreenVisible;
    MapDisplaySettingsService.instance.showMaintenanceScreen.addListener(
      _handleMapDisplaySettingsChanged,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(RemoteConfigService.instance.maybeShowUpdateDialog(context));
    });
    unawaited(_warmUpMapInBackground());
    unawaited(_initOnboarding());
  }

  Future<void> _warmUpMapInBackground() async {
    if (_isMaintenanceScreenVisible) {
      return;
    }

    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (!mounted || _isMaintenanceScreenVisible) {
      return;
    }

    try {
      await OfflineBootstrapService.instance.init();
      if (!mounted || _isMaintenanceScreenVisible) {
        return;
      }
      unawaited(
        MapMarkersService.loadRestaurants(fromServer: false, lightweight: true),
      );
    } catch (_) {
      // Ignore warm-up failures; the map data will load on demand.
    }
  }

  Widget _buildPage(int index) {
    return switch (index) {
      0 =>
        _isMaintenanceScreenVisible
            ? const MapMaintenancePage()
            : MapScreen(key: _primaryOsmMapPageKey),
      1 => GuideScreen(onNavigateToTab: _onItemTapped),
      2 => const TipsRandomPage(),
      3 => const ForumPage(),
      _ => const SizedBox.shrink(),
    };
  }

  List<Widget> get _pages => List<Widget>.generate(4, (index) {
    if (!_loadedTabIndices.contains(index)) {
      return const SizedBox.shrink();
    }
    return _buildPage(index);
  });

  Future<void> _initOnboarding() async {
    if (!_enableOnboarding) {
      return;
    }
    final controller = await OnboardingController.create();
    if (!mounted) {
      return;
    }
    controller.addListener(_handleOnboardingChanged);
    setState(() {
      _onboardingController = controller;
    });
    if (_isMaintenanceScreenVisible && controller.shouldShowOnLaunch) {
      await controller.complete();
      return;
    }
    if (controller.shouldShowOnLaunch) {
      _selectTab(_guideTabIndex, trackAdmin: false, showMapTooltip: false);
      await _waitForNextFrame();
      if (!mounted || _onboardingController != controller) {
        return;
      }
      controller.showWelcome();
    }
  }

  void _resetAdminTapState() {
    _adminTapCount = 0;
    _adminFirstTap = null;
  }

  void _onItemTapped(int index) {
    _selectTab(index);
  }

  bool _isMapTab(int index) => index == 0;

  int? _onboardingTargetTabIndex(OnboardingStepData step) {
    if (step.isWelcome) {
      return _guideTabIndex;
    }

    return switch (step.target) {
      OnboardingTarget.mapArea ||
      OnboardingTarget.mapTab ||
      OnboardingTarget.automaticEmail => _mapTabIndex,
      OnboardingTarget.guideTab => _guideTabIndex,
      OnboardingTarget.none => null,
    };
  }

  void _handleMapDisplaySettingsChanged() {
    final nextValue =
        MapDisplaySettingsService.instance.isMaintenanceScreenVisible;
    if (!mounted || _isMaintenanceScreenVisible == nextValue) {
      return;
    }
    setState(() {
      _isMaintenanceScreenVisible = nextValue;
    });
  }

  void _showProfileTooltipForTab(int index) {
    if (index == 0 && !_isMaintenanceScreenVisible) {
      _primaryOsmMapPageKey.currentState?.activateMapView();
      _primaryOsmMapPageKey.currentState?.showProfileTooltipIfNeeded();
    }
  }

  bool _consumeActiveMapBackPress() {
    if (_selectedIndex == 0 && !_isMaintenanceScreenVisible) {
      return _primaryOsmMapPageKey.currentState?.consumeBackPress() ?? false;
    }
    return false;
  }

  void _selectTab(
    int index, {
    bool trackAdmin = true,
    bool showMapTooltip = true,
  }) {
    const forumIndex = 3;
    final now = DateTime.now();

    if (trackAdmin && index == forumIndex) {
      if (_adminFirstTap == null ||
          now.difference(_adminFirstTap!) > const Duration(seconds: 3)) {
        _adminFirstTap = now;
        _adminTapCount = 1;
      } else {
        _adminTapCount += 1;
      }

      if (_adminTapCount >= 10) {
        _adminTapCount = 0;
        _adminFirstTap = null;
        HapticFeedback.mediumImpact();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Admin gate unlocked')));
        _openAdminGate();
      }
    } else {
      _resetAdminTapState();
    }

    if (_selectedIndex != index || !_loadedTabIndices.contains(index)) {
      setState(() {
        _selectedIndex = index;
        _loadedTabIndices.add(index);
      });
    }
    if (_isMapTab(index) && !_isMaintenanceScreenVisible) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _primaryOsmMapPageKey.currentState?.activateMapView();
      });
    }
    if (showMapTooltip && _isMapTab(index)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showProfileTooltipForTab(index);
      });
    }
  }

  void _handleOnboardingChanged() {
    unawaited(_syncOnboardingUi());
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _syncOnboardingUi() async {
    final controller = _onboardingController;
    if (!mounted || controller == null) {
      return;
    }

    final syncToken = ++_onboardingSyncToken;
    final target = controller.isVisible
        ? controller.currentStep.target
        : OnboardingTarget.none;
    final targetTabIndex = controller.isVisible
        ? _onboardingTargetTabIndex(controller.currentStep)
        : null;

    if (targetTabIndex != null) {
      _selectTab(targetTabIndex, trackAdmin: false, showMapTooltip: false);
      await _waitForNextFrame();
      if (!mounted || _onboardingSyncToken != syncToken) {
        return;
      }
    }

    final primaryOsmMapState = _primaryOsmMapPageKey.currentState;
    final shouldShowEmailPreview =
        target == OnboardingTarget.automaticEmail &&
        controller.isVisible &&
        !_isMaintenanceScreenVisible;
    if (!_isMaintenanceScreenVisible) {
      primaryOsmMapState?.setOnboardingEmailPreviewVisible(
        shouldShowEmailPreview,
      );
    }

    if (shouldShowEmailPreview) {
      await _waitForNextFrame();
      if (!mounted || _onboardingSyncToken != syncToken) {
        return;
      }
    }

    if (controller.isVisible) {
      await _waitForOnboardingTarget(syncToken);
      if (!mounted || _onboardingSyncToken != syncToken) {
        return;
      }
    }

    if (mounted && _onboardingSyncToken == syncToken) {
      setState(() {});
    }
  }

  Future<void> _handleOnboardingPrimaryAction() async {
    final controller = _onboardingController;
    if (controller == null) {
      return;
    }
    if (controller.currentStep.isWelcome) {
      controller.startTour();
      return;
    }
    final isLastStep = controller.currentStepIndex == controller.totalSteps - 1;
    if (isLastStep) {
      await _finishOnboarding();
      return;
    }
    controller.nextStep();
  }

  Future<void> _finishOnboarding() async {
    final controller = _onboardingController;
    if (controller == null) {
      return;
    }
    _primaryOsmMapPageKey.currentState?.setOnboardingEmailPreviewVisible(false);
    _selectTab(1, trackAdmin: false, showMapTooltip: false);
    await _waitForNextFrame();
    if (!mounted) {
      return;
    }
    await controller.complete();
  }

  Future<void> _waitForOnboardingTarget(int syncToken) async {
    final controller = _onboardingController;
    if (!mounted || controller == null || !controller.isVisible) {
      return;
    }

    if (controller.currentStep.isWelcome ||
        controller.currentStep.target == OnboardingTarget.none) {
      await _waitForNextFrame();
      return;
    }

    for (var attempt = 0; attempt < 12; attempt++) {
      if (!mounted || _onboardingSyncToken != syncToken) {
        return;
      }

      final rect = _currentOnboardingHighlightRect();
      if (rect != null && rect.width > 0 && rect.height > 0) {
        return;
      }

      await _waitForNextFrame();
      await Future<void>.delayed(const Duration(milliseconds: 16));
    }
  }

  Rect? _rectForKey(GlobalKey key) {
    final renderObject = key.currentContext?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) {
      return null;
    }
    final offset = renderObject.localToGlobal(Offset.zero);
    return offset & renderObject.size;
  }

  Rect? _currentOnboardingHighlightRect() {
    final controller = _onboardingController;
    if (controller == null || !controller.isVisible) {
      return null;
    }

    final primaryOsmMapState = _primaryOsmMapPageKey.currentState;
    switch (controller.currentStep.target) {
      case OnboardingTarget.none:
        return null;
      case OnboardingTarget.mapArea:
        if (_isMaintenanceScreenVisible) {
          return null;
        }
        return primaryOsmMapState?.onboardingMapAreaRect;
      case OnboardingTarget.mapTab:
        return _rectForKey(_mapTabIconKey);
      case OnboardingTarget.automaticEmail:
        if (_isMaintenanceScreenVisible) {
          return null;
        }
        return primaryOsmMapState?.onboardingMailTileRect;
      case OnboardingTarget.guideTab:
        return _rectForKey(_guideTabIconKey);
    }
  }

  Future<void> _waitForNextFrame() {
    final completer = Completer<void>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      completer.complete();
    });
    return completer.future;
  }

  Future<void> _openAdminGate() async {
    final result = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => const AdminGatePage()));
    if (result == true && mounted) {
      setState(() {}); // refresh UI to reflect admin session
    }
  }

  static const List<Color> _dockItemColors = <Color>[
    Color(0xFFBFDDF5),
    Color(0xFFD8C9F2),
    Color(0xFFF2C6DA),
    Color(0xFFF4E7C7),
  ];

  static const List<Color> _dockIconColors = <Color>[
    Color(0xFF21465F),
    Color(0xFF5D4B77),
    Color(0xFF7A4B61),
    Color(0xFF75623C),
  ];

  Widget _buildDockNavItem(
    IconData iconData,
    int index, {
    GlobalKey? iconKey,
  }) {
    final isSelected = _selectedIndex == index;
    final itemColor = _dockItemColors[index];
    final iconColor = _dockIconColors[index];

    return Expanded(
      child: Semantics(
        button: true,
        selected: isSelected,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _onItemTapped(index),
          child: Center(
            child: AnimatedScale(
              scale: isSelected ? 1.06 : 1,
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              child: AnimatedContainer(
                key: isSelected ? iconKey : null,
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                width: isSelected ? 54 : 48,
                height: isSelected ? 54 : 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: itemColor.withValues(alpha: isSelected ? 0.96 : 0.68),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.68),
                    width: 1.1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: isSelected ? 0.14 : 0.08,
                      ),
                      blurRadius: isSelected ? 14 : 9,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Icon(
                  iconData,
                  color: iconColor,
                  size: isSelected ? 25 : 23,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAppleDockNavigationBar() {
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(18, 0, 18, 10),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(34),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
          child: Container(
            height: 76,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.62),
              borderRadius: BorderRadius.circular(34),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.72),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.10),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              children: <Widget>[
                _buildDockNavItem(
                  Icons.map_outlined,
                  0,
                  iconKey: _mapTabIconKey,
                ),
                _buildDockNavItem(
                  Icons.lightbulb_outline,
                  1,
                  iconKey: _guideTabIconKey,
                ),
                _buildDockNavItem(Icons.auto_awesome, 2),
                _buildDockNavItem(Icons.forum_outlined, 3),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _onboardingController?.removeListener(_handleOnboardingChanged);
    MapDisplaySettingsService.instance.showMaintenanceScreen.removeListener(
      _handleMapDisplaySettingsChanged,
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final onboardingController = _onboardingController;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        final handledByMap =
            _isMapTab(_selectedIndex) && _consumeActiveMapBackPress();
        if (handledByMap) return;
        SystemNavigator.pop();
      },
      child: Stack(
        children: [
          Scaffold(
            extendBody: true,
            body: IndexedStack(index: _selectedIndex, children: _pages),
            bottomNavigationBar: _buildAppleDockNavigationBar(),
          ),
          if (onboardingController?.isVisible ?? false)
            OnboardingOverlay(
              step: onboardingController!.currentStep,
              stepIndex: onboardingController.currentStepIndex,
              totalSteps: onboardingController.totalSteps,
              highlightRect: _currentOnboardingHighlightRect(),
              onPrimaryPressed: () {
                unawaited(_handleOnboardingPrimaryAction());
              },
              onSkipPressed: () {
                unawaited(_finishOnboarding());
              },
            ),
        ],
      ),
    );
  }
}
