import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'onboarding_steps.dart';

class OnboardingController extends ChangeNotifier {
  OnboardingController._(this._prefs, this._hasSeenOnboarding);

  static const String hasSeenOnboardingKey = 'hasSeenOnboarding';

  final SharedPreferences _prefs;
  bool _hasSeenOnboarding;
  bool _isVisible = false;
  int _currentStepIndex = 0;

  static Future<OnboardingController> create() async {
    final prefs = await SharedPreferences.getInstance();
    final hasSeen = prefs.getBool(hasSeenOnboardingKey) ?? false;
    return OnboardingController._(prefs, hasSeen);
  }

  bool get shouldShowOnLaunch => !_hasSeenOnboarding;
  bool get isVisible => _isVisible;
  int get currentStepIndex => _currentStepIndex;
  int get totalSteps => onboardingSteps.length;
  OnboardingStepData get currentStep => onboardingSteps[_currentStepIndex];

  void showWelcome() {
    if (_hasSeenOnboarding) {
      return;
    }
    _isVisible = true;
    _currentStepIndex = 0;
    notifyListeners();
  }

  void startTour() {
    if (_hasSeenOnboarding) {
      return;
    }
    _isVisible = true;
    _currentStepIndex = 1;
    notifyListeners();
  }

  void nextStep() {
    if (!_isVisible) {
      return;
    }
    if (_currentStepIndex >= onboardingSteps.length - 1) {
      return;
    }
    _currentStepIndex += 1;
    notifyListeners();
  }

  Future<void> complete() async {
    _hasSeenOnboarding = true;
    _isVisible = false;
    _currentStepIndex = onboardingSteps.length - 1;
    await _prefs.setBool(hasSeenOnboardingKey, true);
    notifyListeners();
  }
}
