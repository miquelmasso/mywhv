import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'package:latlong2/latlong.dart';
import 'firebase_options.dart';
import 'features/onboarding/onboarding_controller.dart';
import 'features/onboarding/onboarding_overlay.dart';
import 'features/onboarding/onboarding_steps.dart';
import 'navigation/route_observer.dart';
import 'screens/map_maintenance_page.dart';
import 'screens/map_screen.dart';
import 'screens/screens.dart';
import 'screens/admin_gate_page.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'services/offline_bootstrap_service.dart';
import 'services/map_display_settings_service.dart';
import 'services/map_markers_service.dart';
import 'services/offline_state.dart';
import 'services/runtime_device_service.dart';
import 'services/review_service.dart';
import 'services/tile_cache_service.dart';

// 👇 Fitxers per actualitzar codis postals
// ignore: unused_import
import 'models/visa_postcodes_uploader.dart';

Future<void> main() async {
  final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

  await dotenv.load(fileName: ".env");

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  // Mantén la xarxa de Firestore desactivada per defecte
  //await FirebaseFirestore.instance.disableNetwork();
  debugPrint('✅ Firebase initialized correctly');

  await FMTCObjectBoxBackend().initialise();
  await FMTCStore('basemap').manage.create();

  await OfflineBootstrapService.instance.init();
  await MapDisplaySettingsService.instance.init();
  await RuntimeDeviceService.instance.init();
  debugPrint('🔌 Offline mode: ${OfflineState.instance.isOfflineMode}');
  await ReviewService.instance.registerAppOpen();

  FlutterNativeSplash.remove();

  // 🔽 Descomenta aquestes línies si vols actualitzar els codis postals al Firestore:
  //
  //await VisaPostcodesUploader.uploadVisaPostcodes();
  //
  // Quan s’executin, pujaran tots els codis nous al Firebase i eliminaran els anteriors.

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

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
      home: const MyHomePage(initialIndex: 0),
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
  static const LatLng _backgroundWarmupCenter = LatLng(-25.0, 133.0);
  static const int _backgroundWarmupZoom = 5;

  late int _selectedIndex;
  int _adminTapCount = 0;
  DateTime? _adminFirstTap;
  int _onboardingSyncToken = 0;
  late final Set<int> _loadedTabIndices;

  final GlobalKey<MapScreenState> _primaryOsmMapPageKey =
      GlobalKey<MapScreenState>();
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
      unawaited(
        MapMarkersService.loadRestaurants(fromServer: false, lightweight: true),
      );

      final cache = await TileCacheService.instance.init();
      if (!mounted || _isMaintenanceScreenVisible) {
        return;
      }
      if (cache == TileCacheService.instance.cache) {
        unawaited(
          TileCacheService.instance.prefetchArea(
            _backgroundWarmupCenter,
            _backgroundWarmupZoom,
            spanDeg: 6.0,
            maxTiles: 320,
          ),
        );
      }
    } catch (_) {
      // Ignore warm-up failures; the map will load on demand.
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
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _onboardingController != controller) {
          return;
        }
        controller.showWelcome();
      });
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

    final targetTabIndex = switch (target) {
      OnboardingTarget.mapArea || OnboardingTarget.automaticEmail => 0,
      OnboardingTarget.guideTab => 1,
      OnboardingTarget.none => null,
    };

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

  BottomNavigationBarItem _buildNavItem(
    IconData iconData,
    int index, {
    GlobalKey? iconKey,
  }) {
    final isSelected = _selectedIndex == index;
    return BottomNavigationBarItem(
      icon: _buildNavIcon(iconData, false, key: isSelected ? null : iconKey),
      activeIcon: _buildNavIcon(
        iconData,
        true,
        key: isSelected ? iconKey : null,
      ),
      label: '',
    );
  }

  Widget _buildNavIcon(IconData iconData, bool selected, {Key? key}) {
    return AnimatedContainer(
      key: key,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
      child: Icon(
        iconData,
        color: selected ? Colors.black87 : Colors.grey.shade600,
        size: 24,
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
            body: IndexedStack(index: _selectedIndex, children: _pages),
            bottomNavigationBar: Theme(
              data: Theme.of(context).copyWith(
                splashColor: Colors.transparent,
                highlightColor: Colors.transparent,
                hoverColor: Colors.transparent,
              ),
              child: BottomNavigationBar(
                type: BottomNavigationBarType.fixed,
                showSelectedLabels: false,
                showUnselectedLabels: false,
                currentIndex: _selectedIndex,
                selectedItemColor: Theme.of(context).colorScheme.primary,
                onTap: _onItemTapped,
                items: <BottomNavigationBarItem>[
                  _buildNavItem(Icons.map_outlined, 0),
                  _buildNavItem(
                    Icons.lightbulb_outline,
                    1,
                    iconKey: _guideTabIconKey,
                  ),
                  _buildNavItem(Icons.auto_awesome, 2),
                  _buildNavItem(Icons.forum_outlined, 3),
                ],
              ),
            ),
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
