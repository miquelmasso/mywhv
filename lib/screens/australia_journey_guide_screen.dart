import 'package:flutter/material.dart';

import '../models/guide_manual/guide_manual.dart';
import '../services/affiliate_links_service.dart';
import '../services/donation_service.dart';
import '../services/external_link_service.dart';
import '../services/journey_guide_progress_service.dart';
import '../utils/guide_section_theme.dart';
import '../widgets/guide_back_button.dart';
import 'guide_page_screen.dart';
import 'guide_section_screen.dart';
import 'international_banks_screen.dart';
import 'travel_insurance_screen.dart';
import 'visa_type_selection_screen.dart';

enum JourneyStepStatus { available, completed, locked }

class AustraliaJourneyGuideScreen extends StatefulWidget {
  const AustraliaJourneyGuideScreen({
    super.key,
    required this.manual,
    this.onNavigateToTab,
  });

  final GuideManual manual;
  final void Function(int index)? onNavigateToTab;

  @override
  State<AustraliaJourneyGuideScreen> createState() =>
      _AustraliaJourneyGuideScreenState();
}

class _AustraliaJourneyGuideScreenState
    extends State<AustraliaJourneyGuideScreen> {
  static const List<_JourneyStepData> _steps = [
    _JourneyStepData(
      id: 'visa_requirements',
      title: 'Visa & requirements',
      description: 'Learn which visa fits you before travelling.',
      bulletPoints: [
        'Compare WHV and Student Visa paths',
        'Check age, passport and country rules',
        'Review funds, insurance and documents',
        'Use official sources before applying',
      ],
      checklistItems: [
        'Choose WHV or Student Visa path',
        'Check passport validity',
        'Review visa requirements for your country',
        'Check English/IELTS requirement if applicable',
        'Prepare health insurance if required',
        'Prepare proof of funds',
        'Prepare education documents if applicable',
        'Create or access your ImmiAccount',
        'Save official immigration links',
      ],
      tip: 'Start here. Everything else depends on your visa path.',
      icon: Icons.badge_outlined,
      mascotAsset: _MascotAssets.thinking,
      resources: [_JourneyResource.insurance, _JourneyResource.youtooProject],
    ),
    _JourneyStepData(
      id: 'before_arrival',
      title: 'Before arrival',
      description: 'Prepare insurance, flights, money and your first plan.',
      bulletPoints: [
        'Plan your first city and season',
        'Book flights and first nights early',
        'Prepare money, cards and travel cover',
        'Set up internet for when you land',
      ],
      checklistItems: [
        'Compare travel insurance options',
        'Book your flight to Australia',
        'Book your first nights',
        'Download offline maps for arrival',
        'Prepare travel card or bank backup',
        'Choose an e-sim or arrival SIM plan',
        'Save important documents offline',
        'Plan airport to hostel transport',
      ],
      tip: 'A tiny bit of prep now saves a lot of stress later.',
      icon: Icons.flight_takeoff_rounded,
      mascotAsset: _MascotAssets.excited,
      resources: [
        _JourneyResource.insurance,
        _JourneyResource.flights,
        _JourneyResource.esims,
        _JourneyResource.youtooProject,
      ],
    ),
    _JourneyStepData(
      id: 'arrival_steps',
      title: 'Arrival & paperwork',
      description: 'Set up TFN, SIM card and key documents.',
      bulletPoints: [
        'Get connected with SIM or e-sim',
        'Apply for your TFN correctly',
        'Open a bank account and keep details safe',
        'Save certificates and important paperwork',
      ],
      checklistItems: [
        'Activate SIM or e-sim',
        'Apply for TFN',
        'Open or prepare a bank account',
        'Set up Super account details',
        'Get Australian phone number ready for forms',
        'Save passport and visa copies',
        'Organise certificates and IDs',
        'Store emergency contacts',
      ],
      tip: 'Do the boring setup once, then Australia gets easier.',
      icon: Icons.how_to_reg_rounded,
      mascotAsset: _MascotAssets.happy,
      resources: [_JourneyResource.banks],
    ),
    _JourneyStepData(
      id: 'housing',
      title: 'Housing',
      description: 'Discover where backpackers usually stay.',
      bulletPoints: [
        'Start with hostels or short stays',
        'Compare location, transport and weekly price',
        'Avoid sending deposits too quickly',
        'Use housing groups carefully',
      ],
      checklistItems: [
        'Book first hostel or short stay',
        'Join local housing groups',
        'Check transport before choosing an area',
        'Prepare deposit budget',
        'Avoid paying before verifying the place',
        'Inspect the room before committing',
        'Confirm bills and bond conditions',
        'Keep written proof of payments',
      ],
      tip: 'First nights are about location, flexibility and safety.',
      icon: Icons.home_rounded,
      mascotAsset: _MascotAssets.thinking,
      resources: [_JourneyResource.hostels],
    ),
    _JourneyStepData(
      id: 'work',
      title: 'Jobs',
      description: 'Learn how to find work and apply.',
      bulletPoints: [
        'Prepare a simple Australian-style CV',
        'Apply online and in person',
        'Follow up with managers quickly',
        'Keep track of applications and contacts',
      ],
      checklistItems: [
        'Prepare Australian-style CV',
        'Create a simple job tracker',
        'Prepare a short cover message',
        'Apply online',
        'Hand out CVs in person',
        'Follow up with managers',
        'Save references and certificates',
        'Check pay rate before accepting',
      ],
      tip: 'Apply wide, follow up fast, and keep your CV simple.',
      icon: Icons.work_rounded,
      mascotAsset: _MascotAssets.excited,
    ),
    _JourneyStepData(
      id: 'regional_and_extension',
      title: 'Regional farm work',
      description: 'Understand regional jobs and second-year visa basics.',
      bulletPoints: [
        'Check if the postcode counts',
        'Understand eligible industries and tasks',
        'Track payslips and work dates',
        'Avoid unclear cash-in-hand offers',
      ],
      checklistItems: [
        'Check eligible postcode',
        'Confirm eligible industry and task',
        'Save payslips',
        'Track days and employer details',
        'Keep signed timesheets if possible',
        'Confirm ABN or employer details',
        'Avoid unclear cash-only offers',
        'Back up evidence for second-year visa',
      ],
      tip: 'Check postcode eligibility before committing to a job.',
      icon: Icons.agriculture_rounded,
      mascotAsset: _MascotAssets.thinking,
    ),
    _JourneyStepData(
      id: 'transport',
      title: 'Vehicle',
      description: 'Buying, renting or travelling around Australia.',
      bulletPoints: [
        'Compare car, van, bus and flights',
        'Check rego, insurance and roadworthy rules',
        'Budget for fuel, repairs and tolls',
        'Plan long drives with safety stops',
      ],
      checklistItems: [
        'Compare transport options',
        'Check rego and insurance',
        'Inspect vehicle before buying',
        'Check PPSR/VIN before buying',
        'Confirm roadworthy rules by state',
        'Budget fuel and repairs',
        'Prepare emergency kit and spare tyre',
        'Plan long drives safely',
      ],
      tip: 'A car can be freedom, but paperwork matters.',
      icon: Icons.directions_car_rounded,
      mascotAsset: _MascotAssets.happy,
    ),
    _JourneyStepData(
      id: 'money_taxes',
      title: 'Wages, taxes & super',
      description: 'Understand payslips, taxes and superannuation.',
      bulletPoints: [
        'Know your minimum pay rate',
        'Read payslips before accepting problems',
        'Understand tax and super basics',
        'Keep records for refunds and claims',
      ],
      checklistItems: [
        'Learn your minimum pay rate',
        'Check each payslip',
        'Keep tax records',
        'Confirm your TFN is given to employers',
        'Check super is being paid',
        'Save superannuation details',
        'Keep bank and employer records',
        'Prepare for tax return season',
      ],
      tip: 'Know your pay rate and keep every payslip.',
      icon: Icons.attach_money_rounded,
      mascotAsset: _MascotAssets.proud,
    ),
  ];

  Set<String> _completed = {};
  Map<String, Set<String>> _checkedChecklistItems = {};
  bool _loading = true;
  bool _celebrationShown = false;

  @override
  void initState() {
    super.initState();
    _loadProgress();
  }

  Future<void> _loadProgress() async {
    final completed = await JourneyGuideProgressService.instance
        .loadCompletedSteps();
    final checkedChecklistItems = await JourneyGuideProgressService.instance
        .loadChecklistItems(_steps.map((step) => step.id));
    if (!mounted) return;
    setState(() {
      _completed = completed;
      _checkedChecklistItems = checkedChecklistItems;
      _loading = false;
    });
  }

  bool get _journeyCompleted => _completed.length >= _steps.length;

  int get _checkedTaskCount {
    return _steps.fold<int>(
      0,
      (total, step) => total + (_checkedChecklistItems[step.id]?.length ?? 0),
    );
  }

  int get _totalTaskCount {
    return _steps.fold<int>(
      0,
      (total, step) => total + step.checklistItems.length,
    );
  }

  JourneyStepStatus _statusFor(int index) {
    final step = _steps[index];
    if (_completed.contains(step.id)) return JourneyStepStatus.completed;
    if (index == 0 || _completed.contains(_steps[index - 1].id)) {
      return JourneyStepStatus.available;
    }
    return JourneyStepStatus.locked;
  }

  GuideSection? _sectionById(String id) {
    try {
      return widget.manual.sections.firstWhere((section) => section.id == id);
    } catch (_) {
      return null;
    }
  }

  Future<void> _markCompleted(_JourneyStepData step) async {
    final updated = await JourneyGuideProgressService.instance
        .markStepCompleted(step.id, totalSteps: _steps.length);
    if (!mounted) return;
    setState(() => _completed = updated);

    final finished = updated.length >= _steps.length;
    if (finished && !_celebrationShown) {
      _celebrationShown = true;
      await _showCompletionMessage();
      if (mounted) {
        await DonationService.instance.showSupportPopup(context);
      }
    }
  }

  Future<void> _showCompletionMessage() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(_MascotAssets.proud, height: 126),
            const SizedBox(height: 10),
            const Text(
              'Nice! Journey completed',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF151922),
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'You now know where the important WorkyDay guide sections live.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black54, height: 1.3),
            ),
          ],
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFF2D14B),
              foregroundColor: const Color(0xFF151922),
              shape: const StadiumBorder(),
              padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 12),
            ),
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  void _openFullGuide(_JourneyStepData step) {
    final section = _sectionById(step.id);
    if (section == null) return;

    if (section.id == 'visa_requirements' && section.pages.isNotEmpty) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => VisaTypeSelectionScreen(
            sectionId: section.id,
            whvPage: section.pages.first,
            onNavigateToTab: widget.onNavigateToTab,
            initialStrings: widget.manual.strings,
          ),
        ),
      );
      return;
    }

    if (section.id == 'before_arrival' && section.pages.isNotEmpty) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => GuidePageScreen(
            sectionId: section.id,
            page: section.pages.first,
            onNavigateToTab: widget.onNavigateToTab,
            initialStrings: widget.manual.strings,
          ),
        ),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GuideSectionScreen(
          section: section,
          onNavigateToTab: widget.onNavigateToTab,
          strings: widget.manual.strings,
        ),
      ),
    );
  }

  Future<void> _openStepModal(_JourneyStepData step) async {
    final index = _steps.indexWhere((item) => item.id == step.id);
    final status = _statusFor(index);
    if (!_journeyCompleted && status == JourneyStepStatus.locked) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (modalContext) {
        if (_journeyCompleted) {
          return _JourneyChecklistModal(
            step: step,
            checkedItems: _checkedChecklistItems[step.id] ?? const <String>{},
            onChanged: (item, checked) async {
              final updated = await JourneyGuideProgressService.instance
                  .setChecklistItem(
                    stepId: step.id,
                    item: item,
                    checked: checked,
                  );
              if (!mounted) return;
              setState(() {
                _checkedChecklistItems = {
                  ..._checkedChecklistItems,
                  step.id: updated,
                };
              });
            },
            onOpenFullGuide: () {
              Navigator.of(modalContext).pop();
              _openFullGuide(step);
            },
          );
        }
        return _JourneyStepDetailModal(
          step: step,
          status: status,
          onOpenFullGuide: () {
            Navigator.of(modalContext).pop();
            _openFullGuide(step);
          },
          onComplete: () async {
            Navigator.of(modalContext).pop();
            await _markCompleted(step);
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final completedCount = _completed.length.clamp(0, _steps.length).toInt();
    final checklistMode = _journeyCompleted;
    return Scaffold(
      backgroundColor: const Color(0xFFFFF8F6),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
                      child: Row(
                        children: [
                          GuideBackButton(
                            onTap: () => Navigator.of(context).pop(),
                          ),
                          const Expanded(
                            child: Text(
                              'Your Australia Journey',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Color(0xFF151922),
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const SizedBox(width: 48),
                        ],
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: JourneyProgressHeader(
                      completed: checklistMode
                          ? _checkedTaskCount
                          : completedCount,
                      total: checklistMode ? _totalTaskCount : _steps.length,
                      label: checklistMode
                          ? 'Australia checklist'
                          : 'Journey progress',
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: _MascotHeader(
                      completedCount: completedCount,
                      checklistMode: checklistMode,
                    ),
                  ),
                  SliverList.builder(
                    itemCount: _steps.length,
                    itemBuilder: (context, index) {
                      final step = _steps[index];
                      return _JourneyStepCard(
                        step: step,
                        index: index,
                        status: _statusFor(index),
                        checklistMode: checklistMode,
                        checkedItems:
                            _checkedChecklistItems[step.id]?.length ?? 0,
                        totalItems: step.checklistItems.length,
                        isLast: index == _steps.length - 1,
                        onTap: () => _openStepModal(step),
                      );
                    },
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 28)),
                ],
              ),
      ),
    );
  }
}

class JourneyProgressHeader extends StatelessWidget {
  const JourneyProgressHeader({
    super.key,
    required this.completed,
    required this.total,
    required this.label,
  });

  final int completed;
  final int total;
  final String label;

  @override
  Widget build(BuildContext context) {
    final progress = total == 0 ? 0.0 : completed / total;
    final percent = (progress * 100).round();
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 14),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 22,
              spreadRadius: -8,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  '$percent%',
                  style: const TextStyle(
                    color: Color(0xFF151922),
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const Spacer(),
                Text(
                  total == 0 ? label : '$completed of $total',
                  style: const TextStyle(
                    color: Colors.black54,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 10,
                backgroundColor: const Color(0xFFF2E7E3),
                valueColor: const AlwaysStoppedAnimation(Color(0xFFF2D14B)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _JourneyStepCard extends StatelessWidget {
  const _JourneyStepCard({
    required this.step,
    required this.index,
    required this.status,
    required this.checklistMode,
    required this.checkedItems,
    required this.totalItems,
    required this.isLast,
    required this.onTap,
  });

  final _JourneyStepData step;
  final int index;
  final JourneyStepStatus status;
  final bool checklistMode;
  final int checkedItems;
  final int totalItems;
  final bool isLast;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = GuideSectionTheme.forSection(step.id);
    final isLocked = !checklistMode && status == JourneyStepStatus.locked;
    final isCompleted = checklistMode
        ? totalItems > 0 && checkedItems >= totalItems
        : status == JourneyStepStatus.completed;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: isLocked
                      ? Colors.grey.shade200
                      : isCompleted
                      ? const Color(0xFF8EB7A5)
                      : theme.accent,
                  shape: BoxShape.circle,
                  boxShadow: isLocked
                      ? null
                      : [
                          BoxShadow(
                            color: theme.accent.withValues(alpha: 0.25),
                            blurRadius: 16,
                            spreadRadius: -5,
                            offset: const Offset(0, 9),
                          ),
                        ],
                ),
                child: Icon(
                  isCompleted ? Icons.check_rounded : step.icon,
                  color: isLocked ? Colors.black26 : Colors.white,
                  size: 28,
                ),
              ),
              if (!isLast)
                Container(
                  width: 4,
                  height: 54,
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  decoration: BoxDecoration(
                    color: checklistMode
                        ? theme.accent
                        : isCompleted
                        ? const Color(0xFF8EB7A5).withValues(alpha: 0.45)
                        : Colors.black.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: Opacity(
                opacity: isLocked ? 0.55 : 1,
                child: Material(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(24),
                    onTap: isLocked ? null : onTap,
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: isCompleted
                              ? const Color(0xFF8EB7A5).withValues(alpha: 0.28)
                              : Colors.white,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 20,
                            spreadRadius: -8,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  step.title,
                                  style: const TextStyle(
                                    color: Color(0xFF151922),
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  checklistMode
                                      ? '$checkedItems of $totalItems tasks checked'
                                      : step.description,
                                  style: const TextStyle(
                                    color: Colors.black54,
                                    height: 1.25,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                if (checklistMode) ...[
                                  const SizedBox(height: 10),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(99),
                                    child: LinearProgressIndicator(
                                      value: totalItems == 0
                                          ? 0
                                          : checkedItems / totalItems,
                                      minHeight: 7,
                                      backgroundColor: theme.softAccent
                                          .withValues(alpha: 0.45),
                                      valueColor: AlwaysStoppedAnimation(
                                        theme.accent,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          Icon(
                            isCompleted
                                ? Icons.check_circle_rounded
                                : isLocked
                                ? Icons.lock_outline_rounded
                                : Icons.chevron_right_rounded,
                            color: isLocked ? Colors.black26 : theme.accent,
                          ),
                        ],
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
  }
}

class _JourneyStepDetailModal extends StatelessWidget {
  const _JourneyStepDetailModal({
    required this.step,
    required this.status,
    required this.onOpenFullGuide,
    required this.onComplete,
  });

  final _JourneyStepData step;
  final JourneyStepStatus status;
  final VoidCallback onOpenFullGuide;
  final Future<void> Function() onComplete;

  @override
  Widget build(BuildContext context) {
    final theme = GuideSectionTheme.forSection(step.id);
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      padding: EdgeInsets.fromLTRB(
        22,
        12,
        22,
        22 + MediaQuery.of(context).padding.bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Image.asset(
                  step.mascotAsset,
                  width: 84,
                  height: 84,
                  fit: BoxFit.contain,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: _SpeechBubble(
                    text: _messageForStatus(status),
                    color: theme.softAccent,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Text(
              step.title,
              style: const TextStyle(
                color: Color(0xFF151922),
                fontSize: 26,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              step.description,
              style: const TextStyle(
                color: Colors.black54,
                fontSize: 16,
                height: 1.32,
              ),
            ),
            const SizedBox(height: 14),
            _JourneyBulletList(points: step.bulletPoints, theme: theme),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: theme.calloutBackground,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.lightbulb_outline_rounded, color: theme.accent),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      step.tip,
                      style: const TextStyle(
                        color: Color(0xFF2E2E2E),
                        height: 1.28,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (step.resources.isNotEmpty) ...[
              const SizedBox(height: 14),
              const Text(
                'Useful resources',
                style: TextStyle(
                  color: Colors.black54,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  letterSpacing: 0.2,
                ),
              ),
              const SizedBox(height: 8),
              for (final resource in step.resources) ...[
                _RecommendedResourceCard(resource: resource, theme: theme),
                const SizedBox(height: 8),
              ],
            ],
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: theme.buttonBackground,
                  foregroundColor: theme.buttonText,
                  elevation: 0,
                  shape: const StadiumBorder(),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: onOpenFullGuide,
                child: const Text(
                  'Go to full guide',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: status == JourneyStepStatus.completed
                      ? const Color(0xFF6F9F82)
                      : const Color(0xFF151922),
                  side: BorderSide(
                    color: status == JourneyStepStatus.completed
                        ? const Color(0xFF6F9F82).withValues(alpha: 0.35)
                        : Colors.black.withValues(alpha: 0.10),
                  ),
                  shape: const StadiumBorder(),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                ),
                onPressed: status == JourneyStepStatus.completed
                    ? null
                    : () {
                        onComplete();
                      },
                icon: Icon(
                  status == JourneyStepStatus.completed
                      ? Icons.check_circle_rounded
                      : Icons.check_rounded,
                ),
                label: Text(
                  status == JourneyStepStatus.completed
                      ? 'Completed'
                      : 'Mark as completed',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _messageForStatus(JourneyStepStatus status) {
    if (status == JourneyStepStatus.completed) {
      return 'Nice! One step closer to your Working Holiday adventure.';
    }
    return 'Hey mate! Let’s get you ready for Australia 🇦🇺';
  }
}

class _JourneyChecklistModal extends StatefulWidget {
  const _JourneyChecklistModal({
    required this.step,
    required this.checkedItems,
    required this.onChanged,
    required this.onOpenFullGuide,
  });

  final _JourneyStepData step;
  final Set<String> checkedItems;
  final Future<void> Function(String item, bool checked) onChanged;
  final VoidCallback onOpenFullGuide;

  @override
  State<_JourneyChecklistModal> createState() => _JourneyChecklistModalState();
}

class _JourneyChecklistModalState extends State<_JourneyChecklistModal> {
  late Set<String> _checkedItems;

  @override
  void initState() {
    super.initState();
    _checkedItems = {...widget.checkedItems};
  }

  Future<void> _toggleItem(String item, bool checked) async {
    setState(() {
      if (checked) {
        _checkedItems.add(item);
      } else {
        _checkedItems.remove(item);
      }
    });
    await widget.onChanged(item, checked);
  }

  @override
  Widget build(BuildContext context) {
    final step = widget.step;
    final theme = GuideSectionTheme.forSection(step.id);
    final checkedCount = _checkedItems.length;
    final total = step.checklistItems.length;
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      padding: EdgeInsets.fromLTRB(
        22,
        12,
        22,
        22 + MediaQuery.of(context).padding.bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    color: theme.softAccent,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(step.icon, color: theme.accent, size: 30),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        step.title,
                        style: const TextStyle(
                          color: Color(0xFF151922),
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$checkedCount of $total tasks done',
                        style: const TextStyle(
                          color: Colors.black54,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: total == 0 ? 0 : checkedCount / total,
                minHeight: 9,
                backgroundColor: theme.softAccent.withValues(alpha: 0.45),
                valueColor: AlwaysStoppedAnimation(theme.accent),
              ),
            ),
            const SizedBox(height: 16),
            for (final item in step.checklistItems) ...[
              _ChecklistTile(
                item: item,
                checked: _checkedItems.contains(item),
                theme: theme,
                onChanged: (checked) => _toggleItem(item, checked),
              ),
              if (item != step.checklistItems.last) const SizedBox(height: 8),
            ],
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: theme.buttonBackground,
                  foregroundColor: theme.buttonText,
                  elevation: 0,
                  shape: const StadiumBorder(),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: widget.onOpenFullGuide,
                child: const Text(
                  'Open full guide',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChecklistTile extends StatelessWidget {
  const _ChecklistTile({
    required this.item,
    required this.checked,
    required this.theme,
    required this.onChanged,
  });

  final String item;
  final bool checked;
  final GuideSectionTheme theme;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: checked ? theme.softAccent.withValues(alpha: 0.58) : Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => onChanged(!checked),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: checked
                  ? theme.accent.withValues(alpha: 0.30)
                  : Colors.black.withValues(alpha: 0.07),
            ),
          ),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: checked ? theme.accent : Colors.transparent,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: checked
                        ? theme.accent
                        : Colors.black.withValues(alpha: 0.16),
                    width: 1.4,
                  ),
                ),
                child: checked
                    ? const Icon(
                        Icons.check_rounded,
                        color: Colors.white,
                        size: 19,
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  item,
                  style: TextStyle(
                    color: checked
                        ? const Color(0xFF151922)
                        : const Color(0xFF3F3A38),
                    fontSize: 15,
                    height: 1.22,
                    fontWeight: checked ? FontWeight.w800 : FontWeight.w600,
                    decoration: checked ? TextDecoration.lineThrough : null,
                    decorationColor: theme.accent.withValues(alpha: 0.65),
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

class _JourneyBulletList extends StatelessWidget {
  const _JourneyBulletList({required this.points, required this.theme});

  final List<String> points;
  final GuideSectionTheme theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAFA),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.accent.withValues(alpha: 0.10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final point in points) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      color: theme.accent.withValues(alpha: 0.72),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    point,
                    style: const TextStyle(
                      color: Color(0xFF3F3A38),
                      fontSize: 14.5,
                      height: 1.28,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            if (point != points.last) const SizedBox(height: 7),
          ],
        ],
      ),
    );
  }
}

class _RecommendedResourceCard extends StatelessWidget {
  const _RecommendedResourceCard({required this.resource, required this.theme});

  final _JourneyResource resource;
  final GuideSectionTheme theme;

  @override
  Widget build(BuildContext context) {
    final data = resource.data;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => _handleTap(context),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: theme.accent.withValues(alpha: 0.14)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 12,
                spreadRadius: -8,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: theme.softAccent.withValues(alpha: 0.75),
                  shape: BoxShape.circle,
                ),
                child: Icon(data.icon, color: theme.accent, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      data.title,
                      style: TextStyle(
                        color: theme.buttonText,
                        fontWeight: FontWeight.w800,
                        fontSize: 14.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      data.subtitle,
                      style: const TextStyle(
                        color: Colors.black45,
                        fontSize: 12,
                        height: 1.18,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                decoration: BoxDecoration(
                  color: theme.softAccent.withValues(alpha: 0.52),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Open',
                      style: TextStyle(
                        color: theme.buttonText,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(width: 2),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: theme.buttonText,
                      size: 17,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleTap(BuildContext context) async {
    switch (resource) {
      case _JourneyResource.insurance:
        await showTravelInsuranceDialog(context);
      case _JourneyResource.youtooProject:
        await _openUrl(
          context,
          'https://youtooproject.com/contacto/?ref=miquelmasso',
        );
      case _JourneyResource.flights:
        await _showSimpleProviderDialog(
          context,
          title: 'Buy your flights',
          providers: [
            _ResourceProvider(
              label: 'Kiwi',
              asset: 'assets/Kiwi.com logo.png',
              fallbackIcon: Icons.flight_takeoff_outlined,
              onTap: () async {
                var link = await AffiliateLinksService.instance.getLink(
                  'Kiwi_link',
                );
                if (link.isEmpty) {
                  link = await AffiliateLinksService.instance.getLink(
                    'kiwi_link',
                  );
                }
                if (context.mounted) await _openUrl(context, link);
              },
            ),
            _ResourceProvider(
              label: 'Trip',
              asset: 'assets/trip logo.png',
              fallbackIcon: Icons.travel_explore_outlined,
              directLink:
                  'https://www.trip.com/?Allianceid=8388962&SID=315592467&trip_sub1=&trip_sub3=D17431528',
            ),
          ],
        );
      case _JourneyResource.hostels:
        await _showSimpleProviderDialog(
          context,
          title: 'Where to book hostels',
          providers: [
            _ResourceProvider(
              label: 'Trip',
              asset: 'assets/trip logo.png',
              fallbackIcon: Icons.hotel_outlined,
              directLink:
                  'https://www.trip.com/hotels/w/home?Allianceid=8388962&SID=315592467&trip_sub1=&trip_sub3=D17431528',
            ),
          ],
        );
      case _JourneyResource.banks:
        await showInternationalBanksDialog(context);
      case _JourneyResource.esims:
        await _showSimpleProviderDialog(
          context,
          title: 'Popular e-sims',
          providers: [
            _ResourceProvider(
              label: 'Airalo',
              asset: 'assets/Airalo logo.png',
              fallbackIcon: Icons.sim_card_outlined,
              linkKeys: const ['airalo_link', 'Airalo_link', 'airaloLink'],
            ),
            _ResourceProvider(
              label: 'Holafly',
              asset: 'assets/Holafly logo .png',
              fallbackIcon: Icons.sim_card_outlined,
              directLink: 'https://holafly.sjv.io/B5P7B9',
            ),
            _ResourceProvider(
              label: 'Sally e-sim',
              asset: 'assets/sally e-sim logo.png',
              fallbackIcon: Icons.sim_card_outlined,
              linkKeys: const [
                'sally_esim_link',
                'sally_e_sim_link',
                'sally_link',
                'Sally_link',
                'sallyesim_link',
              ],
            ),
            _ResourceProvider(
              label: 'Yesim',
              asset: 'assets/Yesim logo.png',
              fallbackIcon: Icons.sim_card_outlined,
              directLink: 'https://yesim.tpo.lv/x3ZNhigi',
            ),
          ],
        );
    }
  }

  Future<void> _showSimpleProviderDialog(
    BuildContext context, {
    required String title,
    required List<_ResourceProvider> providers,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xFF151922),
            fontSize: 21,
            fontWeight: FontWeight.w800,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final provider in providers) ...[
              _ResourceProviderButton(
                provider: provider,
                onTap: () async {
                  if (provider.onTap != null) {
                    await provider.onTap!();
                    return;
                  }
                  var link = provider.directLink ?? '';
                  for (final key in provider.linkKeys) {
                    if (link.isNotEmpty) break;
                    link = await AffiliateLinksService.instance.getLink(key);
                  }
                  if (context.mounted) await _openUrl(context, link);
                },
              ),
              if (provider != providers.last) const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _openUrl(BuildContext context, String link) async {
    final uri = Uri.tryParse(link);
    if (uri == null || !uri.hasScheme) {
      if (context.mounted) {
        await ExternalLinkService.showBrokenLinkDialog(context);
      }
      return;
    }
    await ExternalLinkService.open(context, uri.toString());
  }
}

class _ResourceProviderButton extends StatelessWidget {
  const _ResourceProviderButton({required this.provider, required this.onTap});

  final _ResourceProvider provider;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFFFF7F5),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () {
          onTap();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: Image.asset(
                  provider.asset,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => Icon(
                    provider.fallbackIcon,
                    color: const Color(0xFF9B6A5D),
                  ),
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Text(
                  provider.label,
                  style: const TextStyle(
                    color: Color(0xFF8A4A3A),
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const Icon(Icons.chevron_right, color: Color(0xFF9B6A5D)),
            ],
          ),
        ),
      ),
    );
  }
}

class _MascotHeader extends StatelessWidget {
  const _MascotHeader({
    required this.completedCount,
    required this.checklistMode,
  });

  final int completedCount;
  final bool checklistMode;

  @override
  Widget build(BuildContext context) {
    final message = checklistMode
        ? 'Now use this as your Australia checklist. Tick things off as you go.'
        : completedCount == 0
        ? 'First things first: visa, arrival and basic setup.'
        : 'Nice! One step closer to your Working Holiday adventure.';
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
      child: Row(
        children: [
          Image.asset(_MascotAssets.happy, width: 96, height: 96),
          const SizedBox(width: 10),
          Expanded(
            child: _SpeechBubble(text: message, color: const Color(0xFFFFF2C8)),
          ),
        ],
      ),
    );
  }
}

class _SpeechBubble extends StatelessWidget {
  const _SpeechBubble({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Color(0xFF2E2E2E),
          fontWeight: FontWeight.w700,
          height: 1.22,
        ),
      ),
    );
  }
}

class _ResourceProvider {
  const _ResourceProvider({
    required this.label,
    required this.asset,
    required this.fallbackIcon,
    this.directLink,
    this.linkKeys = const [],
    this.onTap,
  });

  final String label;
  final String asset;
  final IconData fallbackIcon;
  final String? directLink;
  final List<String> linkKeys;
  final Future<void> Function()? onTap;
}

class _JourneyStepData {
  const _JourneyStepData({
    required this.id,
    required this.title,
    required this.description,
    required this.bulletPoints,
    required this.checklistItems,
    required this.tip,
    required this.icon,
    required this.mascotAsset,
    this.resources = const [],
  });

  final String id;
  final String title;
  final String description;
  final List<String> bulletPoints;
  final List<String> checklistItems;
  final String tip;
  final IconData icon;
  final String mascotAsset;
  final List<_JourneyResource> resources;
}

enum _JourneyResource {
  insurance,
  youtooProject,
  flights,
  hostels,
  banks,
  esims,
}

extension on _JourneyResource {
  _JourneyResourceData get data {
    switch (this) {
      case _JourneyResource.insurance:
        return const _JourneyResourceData(
          title: 'Recommended insurances',
          subtitle: 'Compare useful travel insurance options.',
          icon: Icons.health_and_safety_outlined,
        );
      case _JourneyResource.youtooProject:
        return const _JourneyResourceData(
          title: 'YouTooProject',
          subtitle: 'Student visa and study support.',
          icon: Icons.school_outlined,
        );
      case _JourneyResource.flights:
        return const _JourneyResourceData(
          title: 'Buy your flights',
          subtitle: 'Useful flight booking partners.',
          icon: Icons.flight_takeoff_outlined,
        );
      case _JourneyResource.hostels:
        return const _JourneyResourceData(
          title: 'Where to book hostels',
          subtitle: 'Find your first nights in Australia.',
          icon: Icons.hotel_outlined,
        );
      case _JourneyResource.banks:
        return const _JourneyResourceData(
          title: 'International banks',
          subtitle: 'Cards and accounts for arrival.',
          icon: Icons.account_balance_outlined,
        );
      case _JourneyResource.esims:
        return const _JourneyResourceData(
          title: 'Popular e-sim',
          subtitle: 'Internet ready when you land.',
          icon: Icons.sim_card_outlined,
        );
    }
  }
}

class _JourneyResourceData {
  const _JourneyResourceData({
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final IconData icon;
}

class _MascotAssets {
  const _MascotAssets._();

  static const String happy = 'assets/kangaroo_happy.png';
  static const String thinking = 'assets/kangaroo_thinking.png';
  static const String excited = 'assets/kangaroo_excited.png';
  static const String proud = 'assets/kangaroo_proud.png';
}
