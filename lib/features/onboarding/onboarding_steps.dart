enum OnboardingTarget { none, mapArea, automaticEmail, guideTab }

class OnboardingStepData {
  const OnboardingStepData({
    required this.id,
    required this.title,
    required this.description,
    required this.primaryLabel,
    required this.target,
    this.bullets = const <String>[],
    this.isWelcome = false,
  });

  final String id;
  final String title;
  final String description;
  final String primaryLabel;
  final OnboardingTarget target;
  final List<String> bullets;
  final bool isWelcome;
}

const List<OnboardingStepData> onboardingSteps = <OnboardingStepData>[
  OnboardingStepData(
    id: 'welcome',
    title: 'Welcome to WorkyDay 👋',
    description:
        'Find jobs and useful info for your Working Holiday in Australia.\nLet’s do a quick tour.',
    primaryLabel: 'Start tour',
    target: OnboardingTarget.none,
    isWelcome: true,
  ),
  OnboardingStepData(
    id: 'map',
    title: 'Find workplaces around you',
    description: 'Tap a place to view details and contact employers.',
    primaryLabel: 'Next',
    target: OnboardingTarget.mapArea,
  ),
  OnboardingStepData(
    id: 'automatic_email',
    title: 'Contact employers faster',
    description:
        'Save your message and CV once, then send applications faster.',
    primaryLabel: 'Next',
    target: OnboardingTarget.automaticEmail,
  ),
  OnboardingStepData(
    id: 'guide',
    title: 'Australia Guide',
    description: 'Everything you need for your Working Holiday:',
    bullets: <String>[
      'visa requirements',
      'jobs',
      'housing',
      'taxes and super',
    ],
    primaryLabel: 'Finish',
    target: OnboardingTarget.guideTab,
  ),
];
