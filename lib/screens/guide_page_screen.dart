import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';

import '../models/guide_manual/guide_manual.dart';
import '../repositories/guide_manual_repository.dart';
import '../services/affiliate_links_service.dart';
import '../services/external_link_service.dart';
import '../services/main_tabs_controller.dart';
import '../services/overlay_helper.dart';
import '../services/postcode_eligibility_service.dart';
import '../utils/guide_section_theme.dart';
import '../widgets/guide_back_button.dart';
import 'mail_setup_page.dart';
import 'guide_section_screen.dart';
import 'international_banks_screen.dart';
import 'travel_insurance_screen.dart';

const Color _guideInlineIconColor = Color(0xFFA35D4F);

IconData? _guideIconForDecoratedTitle(String title) {
  final trimmed = title.trimLeft();
  if (trimmed.startsWith('📌')) return Icons.push_pin_outlined;
  if (trimmed.startsWith('✔️') || trimmed.startsWith('✔')) {
    return Icons.check_circle_outline_rounded;
  }
  if (trimmed.startsWith('🔁')) return Icons.sync_alt_rounded;
  if (trimmed.startsWith('⚠️') || trimmed.startsWith('⚠')) {
    return Icons.warning_amber_rounded;
  }
  if (trimmed.startsWith('💡')) return Icons.lightbulb_outline_rounded;
  if (trimmed.startsWith('🧾')) return Icons.receipt_long_outlined;
  if (trimmed.startsWith('🔧')) return Icons.build_outlined;
  if (trimmed.startsWith('🆘')) return Icons.health_and_safety_outlined;
  if (trimmed.startsWith('ℹ️') || trimmed.startsWith('ℹ')) {
    return Icons.info_outline_rounded;
  }
  return null;
}

String _cleanGuideTitle(String title) {
  var clean = title.trimLeft();
  const prefixes = <String>[
    '📌',
    '✔️',
    '✔',
    '🔁',
    '⚠️',
    '⚠',
    '💡',
    '🧾',
    '🔧',
    '🆘',
    'ℹ️',
    'ℹ',
  ];
  for (final prefix in prefixes) {
    if (clean.startsWith(prefix)) {
      clean = clean.substring(prefix.length).trimLeft();
      break;
    }
  }
  return clean;
}

class GuidePageScreen extends StatefulWidget {
  const GuidePageScreen({
    super.key,
    required this.sectionId,
    required this.page,
    this.onNavigateToTab,
    this.initialStrings,
    this.initialTabIndex,
  });

  final String sectionId;
  final GuidePage page;
  final void Function(int index)? onNavigateToTab;
  final Map<String, String>? initialStrings;
  final int? initialTabIndex;

  @override
  State<GuidePageScreen> createState() => _GuidePageScreenState();
}

class _GuidePageScreenState extends State<GuidePageScreen>
    with TickerProviderStateMixin {
  static const double kGuideBlockSpacing = 16;
  TabController? _controller;
  late List<ChecklistItem> _checklist;
  Map<String, String> _strings = {};

  String Function(dynamic) get _resolver =>
      (value) => _resolveTextValue(_strings, value, onMissing: debugPrint);

  String _resolveTextValue(
    Map<String, String> strings,
    dynamic value, {
    void Function(String key)? onMissing,
  }) {
    if (value == null) return '';
    if (value is Iterable) {
      return value
          .map((v) => _resolveTextValue(strings, v, onMissing: onMissing))
          .join('\n');
    }
    if (value is Map && value['key'] is String) {
      final key = value['key'] as String;
      final v = strings[key];
      if (v == null || v.trim().isEmpty) {
        onMissing?.call(key);
        return key;
      }
      return v;
    }
    if (value is String) {
      if (value.startsWith('@')) {
        final key = value.substring(1);
        final v = strings[key];
        if (v == null || v.trim().isEmpty) {
          onMissing?.call(key);
          return key;
        }
        return v;
      }
      final direct = strings[value];
      if (direct != null && direct.trim().isNotEmpty) {
        return direct;
      }
      return value;
    }
    return value.toString();
  }

  @override
  void initState() {
    super.initState();
    _strings = widget.initialStrings ?? {};
    final isFindWorkPage = widget.page.id == 'find_work_online';
    final isFaceToFacePage = widget.page.id == 'work_face_to_face';
    final isContractsPage = widget.page.id == 'contracts_and_pay';
    final isVisaPage = widget.page.id == 'visa_overview';
    final isBeforeArrivalPage = widget.page.id == 'before_arrival_overview';
    final hasChecklist = widget.page.checklist.isNotEmpty;
    final bool hasChecklistTab =
        hasChecklist &&
        widget.sectionId != 'arrival_steps' &&
        widget.sectionId != 'housing' &&
        widget.sectionId != 'regional_and_extension' &&
        widget.sectionId != 'transport' &&
        widget.sectionId != 'money_taxes';
    int tabLength;
    if (isFindWorkPage) {
      tabLength = 3;
    } else if (isFaceToFacePage) {
      tabLength = 2;
    } else if (isContractsPage) {
      tabLength = 2;
    } else if (isVisaPage) {
      tabLength = widget.page.sections.length.clamp(2, 2);
    } else if (isBeforeArrivalPage) {
      tabLength = widget.page.sections.length.clamp(4, 4);
    } else {
      tabLength = 1 + (hasChecklistTab ? 1 : 0);
    }

    final initialIdx = (widget.initialTabIndex ?? 0).clamp(0, tabLength - 1);
    _controller = TabController(
      length: tabLength,
      vsync: this,
      initialIndex: initialIdx,
    );
    _checklist = widget.page.checklist
        .map((c) => ChecklistItem(id: c.id, text: c.text, done: c.done))
        .toList();
    _loadStrings();
  }

  Future<void> _loadStrings() async {
    try {
      final manual = await GuideManualRepository().loadFromAssets();
      if (!mounted) return;
      setState(() => _strings = manual.strings);
    } catch (_) {
      // ignore load errors; fallback to empty map
    }
  }

  String _t(String key) {
    final value = _strings[key];
    if (value == null) {
      debugPrint('Missing string key: $key');
      return key;
    }
    return value;
  }

  String tKeyOrText(dynamic value) {
    if (value == null) return '';
    if (value is Map && value['key'] is String) {
      return _t(value['key'] as String);
    }
    if (value is String) {
      if (value.startsWith('@')) {
        return _t(value.substring(1));
      }
      return value;
    }
    return value.toString();
  }

  void _toggleChecklist(String id, bool? value) {
    setState(() {
      final idx = _checklist.indexWhere((c) => c.id == id);
      if (idx != -1) {
        _checklist[idx] = ChecklistItem(
          id: _checklist[idx].id,
          text: _checklist[idx].text,
          done: value ?? false,
        );
      }
    });
  }

  void _goToTab(int index) {
    MainTabsController.goToTab(
      context,
      index,
      mapCategory: widget.page.cta?.mapCategory,
      forumTag: widget.page.cta?.forumTag,
      onNavigateToTab: widget.onNavigateToTab,
    );
  }

  GuidePageSection? _findSectionById(String id) {
    try {
      return widget.page.sections.firstWhere((s) => s.id == id);
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cta = widget.page.cta;
    final sectionTheme = GuideSectionTheme.forSection(widget.sectionId);
    final isFindWorkPage = widget.page.id == 'find_work_online';
    final isFaceToFacePage = widget.page.id == 'work_face_to_face';
    final isContractsPage = widget.page.id == 'contracts_and_pay';
    final isVisaPage = widget.page.id == 'visa_overview';
    final isBeforeArrivalPage = widget.page.id == 'before_arrival_overview';
    final forumButton = _buildForumButton(
      tag: cta?.forumTag,
      onPressed: () => _goToTab(3),
    );
    final hasChecklist = widget.page.checklist.isNotEmpty;
    final bool hasChecklistTab =
        hasChecklist &&
        widget.sectionId != 'arrival_steps' &&
        widget.sectionId != 'housing';
    String tabTitle(String sectionId, String fallbackKey) {
      final s = _findSectionById(sectionId);
      return _resolver(s?.title ?? fallbackKey);
    }

    final tabs = isFindWorkPage
        ? widget.page.sections
              .map((s) => Tab(text: _resolver(s.title)))
              .toList(growable: false)
        : isVisaPage
        ? [
            Tab(
              text: tabTitle(
                'requirements_tab',
                '@visa.requirements.tab_title',
              ),
            ),
            Tab(text: tabTitle('apply_steps_tab', '@visa.apply.tab_title')),
          ]
        : isBeforeArrivalPage
        ? [
            Tab(text: tabTitle('preparation_tab', '@before.prep.tab_title')),
            Tab(text: tabTitle('lodging_tab', '@before.lodging.tab_title')),
            Tab(text: tabTitle('money_tab', '@before.money.tab_title')),
            Tab(text: tabTitle('cv_tab', '@before.cv.tab_title')),
          ]
        : isFaceToFacePage
        ? [
            Tab(text: _resolver('@ui.tab.info')),
            Tab(text: _resolver('@ui.tab.cv')),
          ]
        : isContractsPage
        ? [
            Tab(text: _resolver('@ui.tab.contracts')),
            Tab(text: _resolver('@ui.tab.salary')),
          ]
        : [
            Tab(text: _resolver('@ui.tab.info')),
            if (hasChecklistTab) Tab(text: _resolver('@ui.tab.checklist')),
          ];
    final resolvedTitle = _resolver(widget.page.title);
    final tabBar = TabBar(
      controller: _controller,
      labelColor: sectionTheme.buttonText,
      unselectedLabelColor: Colors.black54,
      isScrollable: false,
      labelPadding: EdgeInsets.zero,
      indicatorSize: TabBarIndicatorSize.tab,
      indicatorColor: sectionTheme.accent,
      dividerColor: sectionTheme.softAccent,
      labelStyle: const TextStyle(fontWeight: FontWeight.w600),
      unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w400),
      tabs: tabs,
    );
    return Scaffold(
      backgroundColor: sectionTheme.pageBackground,
      appBar: AppBar(
        backgroundColor: sectionTheme.pageBackground,
        surfaceTintColor: sectionTheme.pageBackground,
        centerTitle: true,
        leadingWidth: 72,
        leading: Padding(
          padding: const EdgeInsets.only(left: 16),
          child: GuideBackButton(onTap: () => Navigator.of(context).pop()),
        ),
        title: Text(resolvedTitle),
        bottom: tabBar,
      ),
      body: isFindWorkPage
          ? Column(
              children: [
                Expanded(
                  child: TabBarView(
                    controller: _controller,
                    children: [
                      _FindWorkTabContent(
                        section: _findSectionById('facebook'),
                        isFacebook: true,
                        vsync: this,
                        goToMap: () => _goToTab(0),
                        goToMailSetup: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const MailSetupPage(),
                            ),
                          );
                        },
                        resolve: _resolver,
                        sectionTheme: sectionTheme,
                      ),
                      _FindWorkTabContent(
                        section: _findSectionById('webs'),
                        vsync: this,
                        goToMap: () => _goToTab(0),
                        goToMailSetup: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const MailSetupPage(),
                            ),
                          );
                        },
                        resolve: _resolver,
                        sectionTheme: sectionTheme,
                      ),
                      _FindWorkTabContent(
                        section: _findSectionById('map'),
                        isMap: true,
                        vsync: this,
                        goToMap: () => _goToTab(0),
                        goToMailSetup: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const MailSetupPage(),
                            ),
                          );
                        },
                        resolve: _resolver,
                        sectionTheme: sectionTheme,
                      ),
                    ],
                  ),
                ),
                if (forumButton != null)
                  SafeArea(
                    top: false,
                    minimum: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: forumButton,
                  ),
              ],
            )
          : isFaceToFacePage
          ? Column(
              children: [
                Expanded(
                  child: TabBarView(
                    controller: _controller,
                    children: [
                      _InfoTab(
                        blocks: widget.page.blocks,
                        t: _t,
                        resolve: _resolver,
                        sectionTheme: sectionTheme,
                      ),
                      _CvTab(t: _t),
                    ],
                  ),
                ),
                if (forumButton != null)
                  SafeArea(
                    top: false,
                    minimum: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: forumButton,
                  ),
              ],
            )
          : widget.page.id == 'visa_overview'
          ? Column(
              children: [
                Expanded(
                  child: TabBarView(
                    controller: _controller,
                    children: [
                      _SectionBlocksView(
                        section: _findSectionById('requirements_tab'),
                        vsync: this,
                        onNavigateToTab: widget.onNavigateToTab,
                        t: _t,
                        resolve: _resolver,
                        sectionTheme: sectionTheme,
                      ),
                      _SectionBlocksView(
                        section: _findSectionById('apply_steps_tab'),
                        vsync: this,
                        onNavigateToTab: widget.onNavigateToTab,
                        t: _t,
                        resolve: _resolver,
                        sectionTheme: sectionTheme,
                      ),
                    ],
                  ),
                ),
                if (forumButton != null)
                  SafeArea(
                    top: false,
                    minimum: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: forumButton,
                  ),
              ],
            )
          : widget.page.id == 'before_arrival_overview'
          ? Column(
              children: [
                Expanded(
                  child: TabBarView(
                    controller: _controller,
                    children: [
                      _SectionBlocksView(
                        section: _findSectionById('preparation_tab'),
                        vsync: this,
                        onNavigateToTab: widget.onNavigateToTab,
                        t: _t,
                        resolve: _resolver,
                        sectionTheme: sectionTheme,
                      ),
                      _SectionBlocksView(
                        section: _findSectionById('lodging_tab'),
                        vsync: this,
                        onNavigateToTab: widget.onNavigateToTab,
                        t: _t,
                        resolve: _resolver,
                        sectionTheme: sectionTheme,
                      ),
                      _SectionBlocksView(
                        section: _findSectionById('money_tab'),
                        vsync: this,
                        onNavigateToTab: widget.onNavigateToTab,
                        t: _t,
                        resolve: _resolver,
                        sectionTheme: sectionTheme,
                      ),
                      _SectionBlocksView(
                        section: _findSectionById('cv_tab'),
                        vsync: this,
                        onNavigateToTab: widget.onNavigateToTab,
                        t: _t,
                        resolve: _resolver,
                        sectionTheme: sectionTheme,
                      ),
                    ],
                  ),
                ),
                if (forumButton != null)
                  SafeArea(
                    top: false,
                    minimum: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: forumButton,
                  ),
              ],
            )
          : isContractsPage
          ? Column(
              children: [
                Expanded(
                  child: TabBarView(
                    controller: _controller,
                    children: [
                      _ContractsTab(t: _t),
                      _SalaryTab(t: _t),
                    ],
                  ),
                ),
                if (forumButton != null)
                  SafeArea(
                    top: false,
                    minimum: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: forumButton,
                  ),
              ],
            )
          : Column(
              children: [
                Expanded(
                  child: TabBarView(
                    controller: _controller,
                    children: [
                      _InfoTab(
                        blocks: widget.page.blocks,
                        t: _t,
                        resolve: _resolver,
                        sectionTheme: sectionTheme,
                      ),
                      if (hasChecklistTab)
                        _ChecklistTab(
                          checklist: _checklist,
                          onToggle: _toggleChecklist,
                          resolve: _resolver,
                        ),
                    ],
                  ),
                ),
                if (forumButton != null)
                  SafeArea(
                    top: false,
                    minimum: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: forumButton,
                  ),
              ],
            ),
    );
  }
}

class _FindWorkTabContent extends StatelessWidget {
  const _FindWorkTabContent({
    required this.section,
    this.isFacebook = false,
    this.isMap = false,
    required this.vsync,
    required this.goToMap,
    required this.goToMailSetup,
    required this.resolve,
    required this.sectionTheme,
  });

  final GuidePageSection? section;
  final bool isFacebook;
  final bool isMap;
  final TickerProvider vsync;
  final VoidCallback goToMap;
  final VoidCallback goToMailSetup;
  final String Function(dynamic value) resolve;
  final GuideSectionTheme sectionTheme;

  @override
  Widget build(BuildContext context) {
    if (section == null) {
      return Center(child: Text(resolve('ui.no_content')));
    }
    final widgets = <Widget>[
      ...section!.blocks.map(
        (block) => _buildBlockWidget(
          context,
          block,
          vsync: vsync,
          copyLabel: section!.id == 'facebook'
              ? resolve('ui.copied')
              : section!.id == 'map'
              ? resolve('ui.email_copied')
              : resolve('ui.copy'),
          t: (k) => k,
          resolve: (v) => resolve(v),
          sectionTheme: sectionTheme,
        ),
      ),
    ];

    if (isFacebook) {
      widgets.add(
        ElevatedButton.icon(
          onPressed: () => _launchExternal(
            context,
            Uri.parse('https://www.facebook.com/groups'),
          ),
          icon: const Icon(Icons.open_in_new),
          label: Text(resolve('ui.open_facebook_groups')),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 12),
            backgroundColor: sectionTheme.buttonBackground,
            foregroundColor: sectionTheme.buttonText,
            elevation: 0,
            shape: const StadiumBorder(),
          ),
        ),
      );
    }

    if (isMap) {
      widgets.add(
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: goToMailSetup,
                icon: const Icon(Icons.email_outlined),
                label: Text(resolve('ui.edit_email')),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  backgroundColor: sectionTheme.buttonBackground,
                  foregroundColor: sectionTheme.buttonText,
                  elevation: 0,
                  shape: const StadiumBorder(),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: goToMap,
                icon: const Icon(Icons.map_outlined),
                label: Text(resolve('ui.go_to_map')),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  backgroundColor: sectionTheme.buttonBackground,
                  foregroundColor: sectionTheme.buttonText,
                  elevation: 0,
                  shape: const StadiumBorder(),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: widgets.length,
      separatorBuilder: (_, _) =>
          const SizedBox(height: _GuidePageScreenState.kGuideBlockSpacing),
      itemBuilder: (context, index) => widgets[index],
    );
  }
}

class _SectionBlocksView extends StatelessWidget {
  const _SectionBlocksView({
    required this.section,
    required this.vsync,
    this.onNavigateToTab,
    required this.t,
    required this.resolve,
    required this.sectionTheme,
  });

  final GuidePageSection? section;
  final TickerProvider vsync;
  final void Function(int index)? onNavigateToTab;
  final String Function(String key) t;
  final String Function(dynamic value) resolve;
  final GuideSectionTheme sectionTheme;

  @override
  Widget build(BuildContext context) {
    if (section == null) {
      return Center(child: Text(resolve('ui.no_content')));
    }
    final widgets = <Widget>[];
    var insertedPreparationInsurance = false;
    var insertedHostelsAffiliate = false;
    for (final block in section!.blocks) {
      widgets.add(
        _buildBlockWidget(
          context,
          block,
          vsync: vsync,
          onNavigateToTab: onNavigateToTab,
          t: t,
          resolve: resolve,
          sectionTheme: sectionTheme,
        ),
      );
      if (section!.id == 'preparation_tab' &&
          block.title == '@before.prep.season_title') {
        widgets.add(
          _BeforeArrivalInsuranceAffiliateCard(
            resolve: resolve,
            sectionTheme: sectionTheme,
          ),
        );
        widgets.add(
          _BeforeArrivalFlightsAffiliateCard(sectionTheme: sectionTheme),
        );
        insertedPreparationInsurance = true;
      }
      if (section!.id == 'lodging_tab' &&
          block.title == '@before.lodging.hostel_title') {
        widgets.add(
          _BeforeArrivalHostelsAffiliateCard(sectionTheme: sectionTheme),
        );
        insertedHostelsAffiliate = true;
      }
    }
    if (section!.id == 'preparation_tab' && !insertedPreparationInsurance) {
      widgets.add(
        _BeforeArrivalInsuranceAffiliateCard(
          resolve: resolve,
          sectionTheme: sectionTheme,
        ),
      );
      widgets.add(
        _BeforeArrivalFlightsAffiliateCard(sectionTheme: sectionTheme),
      );
    }
    if (section!.id == 'money_tab') {
      widgets.add(_SuggestedInternationalBanksCard(sectionTheme: sectionTheme));
    }
    if (section!.id == 'lodging_tab' && !insertedHostelsAffiliate) {
      widgets.add(
        _BeforeArrivalHostelsAffiliateCard(sectionTheme: sectionTheme),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: widgets.length,
      separatorBuilder: (_, _) =>
          const SizedBox(height: _GuidePageScreenState.kGuideBlockSpacing),
      itemBuilder: (context, index) => widgets[index],
    );
  }
}

class _InfoTab extends StatelessWidget {
  const _InfoTab({
    required this.blocks,
    required this.t,
    required this.resolve,
    required this.sectionTheme,
  });

  final List<GuideBlock> blocks;
  final String Function(String key) t;
  final String Function(dynamic value) resolve;
  final GuideSectionTheme sectionTheme;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: blocks.length,
      separatorBuilder: (_, _) =>
          const SizedBox(height: _GuidePageScreenState.kGuideBlockSpacing),
      itemBuilder: (context, index) {
        return _buildBlockWidget(
          context,
          blocks[index],
          t: t,
          resolve: resolve,
          sectionTheme: sectionTheme,
        );
      },
    );
  }
}

class _ChecklistTab extends StatelessWidget {
  const _ChecklistTab({
    required this.checklist,
    required this.onToggle,
    required this.resolve,
  });

  final List<ChecklistItem> checklist;
  final void Function(String id, bool? value) onToggle;
  final String Function(dynamic value) resolve;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: checklist.length,
      separatorBuilder: (_, _) =>
          const SizedBox(height: _GuidePageScreenState.kGuideBlockSpacing),
      itemBuilder: (context, index) {
        final item = checklist[index];
        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: CheckboxListTile(
            value: item.done,
            onChanged: (v) => onToggle(item.id, v),
            title: Text(resolve(item.text)),
            controlAffinity: ListTileControlAffinity.leading,
          ),
        );
      },
    );
  }
}

class _CvTab extends StatelessWidget {
  const _CvTab({required this.t});

  final String Function(String key) t;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _InfoCard(
          title: t('ui.cv.title'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _BulletText(text: t('ui.cv.basic_details')),
              _BulletText(text: t('ui.cv.immediate')),
              _BulletText(text: t('ui.cv.experience')),
              _BulletText(text: t('ui.cv.visa')),
              _BulletText(text: t('ui.cv.location')),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _InfoCard(
          title: t('ui.tip'),
          color: Colors.orange.shade50,
          leading: Icon(Icons.lightbulb_outline, color: Colors.orange.shade700),
          child: Text(t('ui.cv.tip')),
        ),
      ],
    );
  }
}

class _ContractsTab extends StatelessWidget {
  const _ContractsTab({required this.t});

  final String Function(String key) t;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            t('ui.contracts.salary_title'),
            style: const TextStyle(
              color: Colors.black54,
              fontSize: 13.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth > 540;
            final cards = [
              _InfoCard(
                title: t('ui.contracts.casual_title'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t('ui.contracts.casual_rate')),
                    const SizedBox(height: 6),
                    _BulletText(text: t('ui.contracts.casual_b1')),
                    _BulletText(text: t('ui.contracts.casual_b2')),
                    _BulletText(text: t('ui.contracts.casual_b3')),
                  ],
                ),
              ),
              _InfoCard(
                title: t('ui.contracts.pt_title'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t('ui.contracts.pt_rate')),
                    const SizedBox(height: 6),
                    _BulletText(text: t('ui.contracts.pt_b1')),
                    _BulletText(text: t('ui.contracts.pt_b2')),
                    _BulletText(text: t('ui.contracts.pt_b3')),
                  ],
                ),
              ),
            ];

            if (isWide) {
              return Row(
                children: [
                  Expanded(child: cards[0]),
                  const SizedBox(width: 12),
                  Expanded(child: cards[1]),
                ],
              );
            }
            return Column(
              children: [cards[0], const SizedBox(height: 12), cards[1]],
            );
          },
        ),
        const SizedBox(height: 16),
        GestureDetector(
          onTap: () => _launchExternal(
            context,
            Uri.parse(
              'https://www.fairwork.gov.au/employment-conditions/awards',
            ),
          ),
          child: RichText(
            text: TextSpan(
              style: const TextStyle(color: Colors.black87, fontSize: 14.5),
              children: [
                TextSpan(text: t('ui.contracts.link_prefix')),
                TextSpan(
                  text: t('ui.contracts.link_label'),
                  style: const TextStyle(
                    color: Colors.blue,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SalaryTab extends StatelessWidget {
  const _SalaryTab({required this.t});

  final String Function(String key) t;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _InfoCard(
          title: t('ui.salary.tax_title'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [Text(t('ui.salary.tax_text'))],
          ),
        ),
        const SizedBox(height: 12),
        _InfoCard(
          title: t('ui.salary.super_title'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [Text(t('ui.salary.super_text'))],
          ),
        ),
        const SizedBox(height: 12),
        _InfoCard(
          title: t('ui.salary.penalty_title'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _BulletText(text: t('ui.salary.penalty_sat')),
              _BulletText(text: t('ui.salary.penalty_sun')),
              _BulletText(text: t('ui.salary.penalty_hol')),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Text(
          t('ui.salary.penalty_note'),
          style: const TextStyle(color: Colors.black54, fontSize: 13),
        ),
      ],
    );
  }
}

class _BulletText extends StatelessWidget {
  const _BulletText({required this.text, this.orderedIndex});

  final String text;
  final int? orderedIndex;

  @override
  Widget build(BuildContext context) {
    final baseStyle = DefaultTextStyle.of(context).style;
    final spans = <TextSpan>[TextSpan(text: text, style: baseStyle)];

    final bullet = orderedIndex != null ? '${orderedIndex! + 1}. ' : '• ';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            bullet,
            style: orderedIndex != null
                ? const TextStyle(fontWeight: FontWeight.w600)
                : baseStyle,
          ),
          Expanded(
            child: RichText(text: TextSpan(children: spans)),
          ),
        ],
      ),
    );
  }
}

Future<void> _launchExternal(BuildContext context, Uri uri) async {
  await ExternalLinkService.open(context, uri.toString());
}

Future<void> _openGuidePage(
  BuildContext context,
  String pageId, {
  void Function(int index)? onNavigateToTab,
  int? initialTabIndex,
}) async {
  final manual = await GuideManualRepository().loadFromAssets();
  GuideSection? targetSection;
  for (final section in manual.sections) {
    for (final page in section.pages) {
      if (page.id == pageId) {
        if (!context.mounted) return;
        if (section.id == 'housing') {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => GuideSectionScreen(
                section: section,
                strings: manual.strings,
                initialPageId: page.id,
                onNavigateToTab: onNavigateToTab,
              ),
            ),
          );
        } else {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => GuidePageScreen(
                sectionId: section.id,
                page: page,
                initialStrings: manual.strings,
                onNavigateToTab: onNavigateToTab,
                initialTabIndex: initialTabIndex,
              ),
            ),
          );
        }
        return;
      }
    }
    if (section.id == pageId) {
      targetSection = section;
    }
  }

  if (targetSection != null && context.mounted) {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GuideSectionScreen(
          section: targetSection!,
          strings: manual.strings,
          onNavigateToTab: onNavigateToTab,
        ),
      ),
    );
  }
}

Widget _buildBlockWidget(
  BuildContext context,
  GuideBlock block, {
  TickerProvider? vsync,
  String? copyLabel,
  void Function(int index)? onNavigateToTab,
  required String Function(String key) t,
  required String Function(dynamic value) resolve,
  GuideSectionTheme sectionTheme = GuideSectionTheme.fallback,
}) {
  Widget actionButton({
    required Widget label,
    required VoidCallback onPressed,
    IconData? icon,
  }) {
    final btn = icon != null
        ? ElevatedButton.icon(
            onPressed: onPressed,
            icon: Icon(icon),
            label: label,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 10),
              backgroundColor: sectionTheme.buttonBackground,
              foregroundColor: sectionTheme.buttonText,
              elevation: 0,
              shape: const StadiumBorder(),
            ),
          )
        : ElevatedButton(
            onPressed: onPressed,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 10),
              backgroundColor: sectionTheme.buttonBackground,
              foregroundColor: sectionTheme.buttonText,
              elevation: 0,
              shape: const StadiumBorder(),
            ),
            child: label,
          );
    return SizedBox(width: double.infinity, child: btn);
  }

  Widget buttonIfAny() {
    if (block.buttonLabel == null || block.buttonUrl == null) {
      return const SizedBox.shrink();
    }
    final isCopyAction = block.buttonUrl!.startsWith('copy:');
    final isGuideNavigation = block.buttonUrl!.startsWith('guide:');
    final isAction = block.buttonUrl!.startsWith('action:');
    final isCompactMapButton =
        block.icon != null &&
        block.buttonUrl!.contains('regional_and_extension#tab=0');
    if (isAction && block.buttonUrl!.contains('check_postcode')) {
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: InlinePostcodeChecker(t: t),
      );
    }
    if (isAction && block.buttonUrl!.contains('travel_insurance')) {
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: SizedBox(
          width: double.infinity,
          child: Material(
            color: sectionTheme.buttonBackground,
            shape: const StadiumBorder(),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => showTravelInsuranceDialog(context),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 10,
                ),
                child: Text(
                  resolve(block.buttonLabel),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: sectionTheme.buttonText,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }
    if (isCompactMapButton) {
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: SizedBox(
          width: double.infinity,
          child: Material(
            color: sectionTheme.buttonBackground,
            shape: const StadiumBorder(),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () async =>
                  _launchExternal(context, Uri.parse(block.buttonUrl!)),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 10,
                ),
                child: Text(
                  resolve(block.buttonLabel),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: sectionTheme.buttonText,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: () async {
            if (isCopyAction) {
              final textToCopy = block.content?.isNotEmpty == true
                  ? block.content!
                  : block.items.join('\n');
              if (textToCopy.isNotEmpty) {
                await Clipboard.setData(ClipboardData(text: textToCopy));
                if (!context.mounted) return;
                if (vsync != null) {
                  await OverlayHelper.showCopiedOverlay(
                    context,
                    vsync,
                    resolve(block.buttonLabel ?? 'ui.copy'),
                  );
                }
              }
              return;
            }
            if (isGuideNavigation) {
              final raw = block.buttonUrl!.substring('guide:'.length);
              final parts = raw.split('#');
              final targetPageId = parts.first;
              int? tabIndex;
              if (parts.length > 1 && parts[1].startsWith('tab=')) {
                tabIndex = int.tryParse(parts[1].substring(4));
              }
              if (targetPageId.isNotEmpty) {
                await _openGuidePage(
                  context,
                  targetPageId,
                  onNavigateToTab: onNavigateToTab,
                  initialTabIndex: tabIndex,
                );
              }
              return;
            }
            await _launchExternal(context, Uri.parse(block.buttonUrl!));
          },
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            backgroundColor: sectionTheme.buttonBackground,
            foregroundColor: sectionTheme.buttonText,
            elevation: 0,
            shape: const StadiumBorder(),
          ),
          child: Text(
            resolve(block.buttonLabel),
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }

  Widget cvSheet(GuideBlock block) {
    final lines = (block.content ?? '').split('\n');
    final headings = ['PROFILE', 'WORK EXPERIENCE', 'SKILLS', 'AVAILABILITY'];

    String line(int index) =>
        index >= 0 && index < lines.length ? lines[index] : '';
    int headingIndex(String heading) => lines.indexOf(heading);

    List<String> sectionContent(String heading) {
      final start = headingIndex(heading);
      if (start == -1) return [];
      final nextIndices =
          headings.map(headingIndex).where((i) => i > start).toList()..sort();
      final end = nextIndices.isNotEmpty ? nextIndices.first : lines.length;
      return lines
          .sublist(start + 1, end)
          .where((l) => l.trim().isNotEmpty)
          .toList();
    }

    Widget section(String title, List<String> content) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 6),
          ...content.map(
            (line) => line.trim().startsWith('•')
                ? _BulletText(
                    text: line.trim().replaceFirst(RegExp(r'^•\\s*'), ''),
                  )
                : Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(line),
                  ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    line(0),
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 20,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    [line(1), line(2)].where((l) => l.isNotEmpty).join('\n'),
                    style: const TextStyle(color: Colors.black87),
                  ),
                  const SizedBox(height: 16),
                  section('PROFILE', sectionContent('PROFILE')),
                  const SizedBox(height: 14),
                  section('WORK EXPERIENCE', sectionContent('WORK EXPERIENCE')),
                  const SizedBox(height: 14),
                  section('SKILLS', sectionContent('SKILLS')),
                  const SizedBox(height: 14),
                  section('AVAILABILITY', sectionContent('AVAILABILITY')),
                ],
              ),
            ),
          ),
        ),
        if (block.buttonLabel != null && block.buttonUrl != null) ...[
          const SizedBox(height: 12),
          buttonIfAny(),
        ],
      ],
    );
  }

  Widget textWithLinks(dynamic textValue, String Function(dynamic) resolve) {
    final resolved = resolve(textValue);
    if (resolved.isEmpty) return const SizedBox.shrink();
    final spans = _parseLinkTextSpans(context, resolved);
    if (spans.length == 1 &&
        spans.first is TextSpan &&
        (spans.first as TextSpan).recognizer == null) {
      return Text(resolved);
    }
    return RichText(
      text: TextSpan(
        style: const TextStyle(color: Colors.black87),
        children: spans,
      ),
    );
  }

  switch (block.type) {
    case 'card':
      final hasButton = block.buttonLabel != null && block.buttonUrl != null;
      final hasTitle = block.title != null && block.title!.isNotEmpty;
      final hasContent = block.content != null && block.content!.isNotEmpty;
      final hasItems = block.items.isNotEmpty;
      if (hasButton && !hasTitle && !hasContent && !hasItems) {
        final isCopyAction = block.buttonUrl!.startsWith('copy:');
        final isGuideNavigation = block.buttonUrl!.startsWith('guide:');
        final isAction = block.buttonUrl!.startsWith('action:');
        Future<void> handleTap() async {
          if (isCopyAction) {
            final textToCopy = block.content?.isNotEmpty == true
                ? block.content!
                : block.items.join('\n');
            if (textToCopy.isNotEmpty) {
              await Clipboard.setData(ClipboardData(text: textToCopy));
            }
            return;
          }
          if (isGuideNavigation) {
            final raw = block.buttonUrl!.substring('guide:'.length);
            final parts = raw.split('#');
            final targetPageId = parts.first;
            int? tabIndex;
            if (parts.length > 1 && parts[1].startsWith('tab=')) {
              tabIndex = int.tryParse(parts[1].substring(4));
            }
            if (targetPageId.isNotEmpty) {
              await _openGuidePage(
                context,
                targetPageId,
                onNavigateToTab: onNavigateToTab,
                initialTabIndex: tabIndex,
              );
            }
            return;
          }
          await _launchExternal(context, Uri.parse(block.buttonUrl!));
        }

        if (isAction && block.buttonUrl!.contains('check_postcode')) {
          return InlinePostcodeChecker(t: t);
        }
        final label = Text(resolve(block.buttonLabel));
        // No card wrapper; match Facebook button styling
        return actionButton(
          label: label,
          onPressed: handleTap,
          icon: block.icon != null ? Icons.open_in_new : null,
        );
      }

      Color? cardColor;
      if (block.variant == 'warning') {
        cardColor = sectionTheme.calloutBackground;
      } else if (block.variant == 'success') {
        cardColor = sectionTheme.calloutBackground;
      } else if (block.variant == 'info') {
        cardColor = sectionTheme.softAccent;
      } else if (block.variant == 'milestone') {
        cardColor = sectionTheme.softAccent;
      }
      IconData? iconFromString(String? name) {
        switch (name) {
          case 'local_florist':
            return Icons.local_florist;
          case 'agriculture':
            return Icons.agriculture;
          case 'restaurant_menu':
            return Icons.restaurant_menu;
          default:
            return null;
        }
      }
      final leadingIcon = iconFromString(block.icon);
      final variantIcon = block.variant == 'warning'
          ? Icons.warning_amber_rounded
          : block.variant == 'success'
          ? Icons.lightbulb_outline_rounded
          : block.variant == 'info'
          ? Icons.info_outline_rounded
          : null;
      final effectiveLeadingIcon = leadingIcon ?? variantIcon;
      final effectiveLeadingColor =
          block.variant == 'warning' || block.variant == 'success'
          ? sectionTheme.warningIcon
          : sectionTheme.accent;

      final resolvedTitle = resolve(block.title ?? '');
      final isProcessingCard =
          block.title == '@visa.requirements.processing_title';
      final isBeforeLandingCard = block.title == '@arrival.sim.before_title';
      if (block.variant == 'milestone') {
        final lines = resolve(block.content ?? '').split('\n');
        final value = lines.isNotEmpty ? lines.first : '';
        final small = lines.length > 1 ? lines.sublist(1).join('\n') : '';
        return _InfoCard(
          color: cardColor,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(Icons.flag, color: sectionTheme.accent, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      resolvedTitle,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: sectionTheme.buttonText,
                      ),
                    ),
                  ),
                ],
              ),
              if (small.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  small,
                  style: const TextStyle(fontSize: 13, color: Colors.black87),
                ),
              ],
            ],
          ),
        );
      }
      return _InfoCard(
        title: resolvedTitle,
        color: cardColor,
        leading: effectiveLeadingIcon != null
            ? Icon(effectiveLeadingIcon, color: effectiveLeadingColor)
            : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isProcessingCard &&
                block.content != null &&
                block.content!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  resolve(block.content),
                  style: const TextStyle(color: Colors.black54, fontSize: 13),
                ),
              ),
            if (isBeforeLandingCard) ...[
              const SizedBox(height: 6),
              const Text(
                'Otherwise get an e-sim that will work as soon as you land.',
                style: TextStyle(color: Colors.black54, fontSize: 13),
              ),
              const SizedBox(height: 12),
              _PopularESimsButton(sectionTheme: sectionTheme),
            ],
            if (isProcessingCard) Text(resolve('@visa.processing.simple')),
            if (block.chips.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 6),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: block.chips
                      .map(
                        (item) => Text(
                          resolve(item),
                          style: const TextStyle(fontSize: 20),
                        ),
                      )
                      .toList(),
                ),
              ),
            if (block.items.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: block.ordered
                    ? _OrderedBlockItems(
                        items: block.items,
                        resolve: resolve,
                        appendAffiliateAfterVisaInsuranceItem:
                            block.title == '@visa.requirements.title',
                        sectionTheme: sectionTheme,
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: block.items.map((item) {
                          final text = resolve(item);
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('• '),
                                Expanded(child: Text(text)),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
              ),
            if (block.buttonLabel != null && block.buttonUrl != null)
              buttonIfAny(),
          ],
        ),
      );
    case 'callout':
      final resolvedTitle = resolve(block.title ?? '');
      Color bg = sectionTheme.softAccent;
      Color iconColor = sectionTheme.accent;
      IconData icon = Icons.info_outline;
      if (block.variant == 'warning') {
        bg = sectionTheme.calloutBackground;
        iconColor = sectionTheme.warningIcon;
        icon = Icons.warning_amber_rounded;
      } else if (block.variant == 'success') {
        bg = sectionTheme.calloutBackground;
        iconColor = sectionTheme.warningIcon;
        icon = Icons.lightbulb_outline;
      }
      final hasItems = block.items.isNotEmpty;
      Widget body;
      Widget bulletIcon() {
        if (block.variant == 'warning') {
          return Icon(
            Icons.cancel_outlined,
            size: 18,
            color: sectionTheme.warningIcon,
          );
        }
        if (block.variant == 'success') {
          return Icon(
            Icons.check_circle_outline,
            size: 18,
            color: sectionTheme.warningIcon,
          );
        }
        return Icon(Icons.circle, size: 10, color: Colors.grey.shade700);
      }
      if (hasItems) {
        body = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: block.items
              .map(
                (item) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(right: 6, top: 2),
                        child: bulletIcon(),
                      ),
                      Expanded(child: textWithLinks(item, resolve)),
                    ],
                  ),
                ),
              )
              .toList(),
        );
      } else {
        body = textWithLinks(block.content, resolve);
      }

      Future<void> handleCopy() async {
        final copyTarget =
            block.copyText ?? block.content ?? block.items.join('\n');
        final resolvedCopy = resolve(copyTarget);
        if (resolvedCopy.trim().isEmpty) return;
        await Clipboard.setData(ClipboardData(text: resolvedCopy));
        if (!context.mounted) return;
        final msgKey = block.copyMessageKey ?? '@ui.message_copied';
        if (vsync != null) {
          await OverlayHelper.showCopiedOverlay(
            context,
            vsync,
            resolve(msgKey),
          );
        } else {
          final snack = SnackBar(
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            content: Text(resolve(msgKey)),
            duration: const Duration(seconds: 2),
          );
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(snack);
        }
      }

      final card = _InfoCard(
        title: resolvedTitle,
        color: bg,
        leading: Icon(icon, color: iconColor),
        child: body,
      );

      if (block.copyOnTap) {
        return InkWell(
          onTap: handleCopy,
          borderRadius: BorderRadius.circular(12),
          child: card,
        );
      }
      return card;
    case 'paragraph':
      return _InfoCard(
        title: resolve(block.title ?? ''),
        child: textWithLinks(block.content, resolve),
      );
    case 'header':
      return Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(
              Icons.check_circle_outline,
              color: Colors.grey.shade500,
              size: 19,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                resolve(block.title ?? ''),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
            ),
          ],
        ),
      );
    case 'cv_sheet':
      return cvSheet(block);
    default:
      if (block.type == 'button') {
        final isCopyAction = block.buttonUrl?.startsWith('copy:') ?? false;
        final isGuideNavigation =
            block.buttonUrl?.startsWith('guide:') ?? false;
        final isAction = block.buttonUrl?.startsWith('action:') ?? false;
        if (isAction &&
            (block.buttonUrl?.contains('check_postcode') ?? false)) {
          return InlinePostcodeChecker(t: t);
        }
        Future<void> handleTap() async {
          if (block.buttonLabel == null || block.buttonUrl == null) return;
          if (isCopyAction) {
            final textToCopy = block.content?.isNotEmpty == true
                ? block.content!
                : block.items.join('\\n');
            if (textToCopy.isNotEmpty) {
              await Clipboard.setData(ClipboardData(text: textToCopy));
              if (!context.mounted) return;
              if (vsync != null) {
                await OverlayHelper.showCopiedOverlay(
                  context,
                  vsync,
                  block.buttonLabel ?? 'Copied',
                );
              }
            }
            return;
          }
          if (isGuideNavigation) {
            final raw = block.buttonUrl!.substring('guide:'.length);
            final parts = raw.split('#');
            final targetPageId = parts.first;
            int? tabIndex;
            if (parts.length > 1 && parts[1].startsWith('tab=')) {
              tabIndex = int.tryParse(parts[1].substring(4));
            }
            if (targetPageId.isNotEmpty) {
              await _openGuidePage(
                context,
                targetPageId,
                onNavigateToTab: onNavigateToTab,
                initialTabIndex: tabIndex,
              );
            }
            return;
          }
          await _launchExternal(context, Uri.parse(block.buttonUrl!));
        }

        return SizedBox(
          width: double.infinity,
          child: Material(
            color: sectionTheme.buttonBackground,
            shape: const StadiumBorder(),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: block.buttonLabel != null && block.buttonUrl != null
                  ? handleTap
                  : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 10,
                ),
                child: Text(
                  resolve(block.buttonLabel),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: sectionTheme.buttonText,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        );
      }
      if (block.type == 'tip' || block.type == 'warning') {
        final content = block.content ?? '';
        final isWarning = block.type == 'warning';
        return InkWell(
          onTap: content.isNotEmpty
              ? () async {
                  await Clipboard.setData(ClipboardData(text: content));
                  if (!context.mounted) return;
                  if (vsync != null) {
                    await OverlayHelper.showCopiedOverlay(
                      context,
                      vsync,
                      resolve(copyLabel ?? 'ui.copy'),
                    );
                  }
                }
              : null,
          child: _InfoCard(
            title: block.title ?? (isWarning ? 'Atenció' : 'Tip'),
            color: Colors.orange.shade50,
            leading: Icon(
              isWarning ? Icons.warning_amber : Icons.lightbulb_outline,
              color: Colors.orange.shade700,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                textWithLinks(content, resolve),
                if (block.buttonLabel != null && block.buttonUrl != null)
                  buttonIfAny(),
              ],
            ),
          ),
        );
      }
      final ordered = block.type == 'steps';
      return _InfoCard(
        title: block.title,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ...block.items.asMap().entries.map(
              (entry) => _BulletText(
                text: entry.value,
                orderedIndex: ordered ? entry.key : null,
              ),
            ),
            if (block.content != null &&
                block.content!.isNotEmpty &&
                block.items.isEmpty)
              textWithLinks(block.content, resolve),
            if (block.buttonLabel != null && block.buttonUrl != null)
              buttonIfAny(),
          ],
        ),
      );
  }
}

class InlinePostcodeChecker extends StatefulWidget {
  const InlinePostcodeChecker({super.key, required this.t});

  final String Function(String key) t;

  @override
  State<InlinePostcodeChecker> createState() => _InlinePostcodeCheckerState();
}

class _InlinePostcodeCheckerState extends State<InlinePostcodeChecker> {
  final _controller = TextEditingController();
  final _service = PostcodeEligibilityService.instance;
  bool? _isRegional;

  Future<void> _onChanged(String value) async {
    if (value.length != 4 || int.tryParse(value) == null) {
      setState(() => _isRegional = null);
      return;
    }
    final res = await _service.check(value);
    final regional = res.type != PostcodeVisaType.notEligible;
    setState(() => _isRegional = regional);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final success = _isRegional == true;
    final failure = _isRegional == false;
    final color = success
        ? Colors.green.shade700
        : failure
        ? Colors.red.shade700
        : Colors.black54;
    final icon = success
        ? Icons.check_circle_outline
        : failure
        ? Icons.cancel_outlined
        : null;

    return _InfoCard(
      title: widget.t('@regional.extension.check_title'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _controller,
            keyboardType: TextInputType.number,
            maxLength: 4,
            decoration: InputDecoration(
              hintText: widget.t('@regional.extension.check_hint'),
              counterText: '',
            ),
            onChanged: _onChanged,
          ),
          if (_isRegional != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                if (icon != null) Icon(icon, color: color, size: 20),
                if (icon != null) const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.t(
                      _isRegional == true
                          ? '@regional.extension.check_result_regional'
                          : '@regional.extension.check_result_not',
                    ),
                    style: TextStyle(color: color, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

const bool _showGuideForumButtons = false;

Widget? _buildForumButton({
  required String? tag,
  required VoidCallback onPressed,
}) {
  if (!_showGuideForumButtons || tag == null || tag.isEmpty) return null;
  return SizedBox(
    width: double.infinity,
    child: ElevatedButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.forum_outlined),
      label: Text('Ask forum (#$tag)'),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: const StadiumBorder(),
      ),
    ),
  );
}

List<InlineSpan> _parseLinkTextSpans(BuildContext context, String text) {
  final spans = <InlineSpan>[];
  final regex = RegExp(r'\[\[(.+?)\|(.+?)\]\]');
  int start = 0;

  for (final match in regex.allMatches(text)) {
    if (match.start > start) {
      spans.add(TextSpan(text: text.substring(start, match.start)));
    }
    final label = match.group(1) ?? '';
    final url = match.group(2) ?? '';
    spans.add(
      TextSpan(
        text: label,
        style: const TextStyle(
          color: Colors.blue,
          decoration: TextDecoration.underline,
        ),
        recognizer: TapGestureRecognizer()
          ..onTap = () {
            _launchExternal(context, Uri.parse(url));
          },
      ),
    );
    start = match.end;
  }

  if (start < text.length) {
    spans.add(TextSpan(text: text.substring(start)));
  }

  return spans.isEmpty ? [TextSpan(text: text)] : spans;
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    this.title,
    required this.child,
    this.color,
    this.leading,
    this.padding = const EdgeInsets.all(14),
  });

  final String? title;
  final Widget child;
  final Color? color;
  final Widget? leading;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final decoratedTitle = title;
    final displayTitle = decoratedTitle == null
        ? null
        : _cleanGuideTitle(decoratedTitle);
    final resolvedLeading =
        leading ??
        (decoratedTitle == null
            ? null
            : _guideIconForDecoratedTitle(decoratedTitle) == null
            ? null
            : Icon(
                _guideIconForDecoratedTitle(decoratedTitle),
                color: _guideInlineIconColor,
              ));
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (resolvedLeading != null) ...[
            resolvedLeading,
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (displayTitle != null && displayTitle.isNotEmpty) ...[
                  Text(
                    displayTitle,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 6),
                ],
                child,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OrderedBlockItems extends StatelessWidget {
  const _OrderedBlockItems({
    required this.items,
    required this.resolve,
    this.appendAffiliateAfterVisaInsuranceItem = false,
    this.sectionTheme = GuideSectionTheme.fallback,
  });

  final List<dynamic> items;
  final String Function(dynamic value) resolve;
  final bool appendAffiliateAfterVisaInsuranceItem;
  final GuideSectionTheme sectionTheme;

  bool _isVisaInsuranceItem(dynamic item) {
    return item == '@visa.requirements.item_4' ||
        item == 'visa.requirements.item_4';
  }

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (final entry in items.asMap().entries) {
      final text = resolve(entry.value);
      children.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${entry.key + 1}. ',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              Expanded(child: Text(text)),
            ],
          ),
        ),
      );
      if (appendAffiliateAfterVisaInsuranceItem &&
          _isVisaInsuranceItem(entry.value)) {
        children.add(
          _VisaRequirementsInsuranceAffiliatePanel(
            resolve: resolve,
            sectionTheme: sectionTheme,
          ),
        );
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }
}

class _VisaRequirementsInsuranceAffiliatePanel extends StatelessWidget {
  const _VisaRequirementsInsuranceAffiliatePanel({
    required this.resolve,
    required this.sectionTheme,
  });

  final String Function(dynamic value) resolve;
  final GuideSectionTheme sectionTheme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _GuideAffiliateCtaButton(
            label: resolve('@insurance.affiliate.recommended_button'),
            sectionTheme: sectionTheme,
          ),
        ],
      ),
    );
  }
}

class _BeforeArrivalInsuranceAffiliateCard extends StatelessWidget {
  const _BeforeArrivalInsuranceAffiliateCard({
    required this.resolve,
    required this.sectionTheme,
  });

  final String Function(dynamic value) resolve;
  final GuideSectionTheme sectionTheme;

  @override
  Widget build(BuildContext context) {
    return _InfoCard(
      title: resolve('@before.insurance.title'),
      color: sectionTheme.softAccent,
      leading: Icon(
        Icons.health_and_safety_outlined,
        color: sectionTheme.accent,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            resolve('@before.insurance.body'),
            style: const TextStyle(fontSize: 13.5, color: Colors.black87),
          ),
          const SizedBox(height: 12),
          _GuideAffiliateCtaButton(
            label: resolve('@insurance.affiliate.compare_button'),
            sectionTheme: sectionTheme,
          ),
        ],
      ),
    );
  }
}

class _SuggestedInternationalBanksCard extends StatelessWidget {
  const _SuggestedInternationalBanksCard({required this.sectionTheme});

  final GuideSectionTheme sectionTheme;

  @override
  Widget build(BuildContext context) {
    return _InfoCard(
      title: 'Suggested international banks',
      child: SizedBox(
        width: double.infinity,
        child: Material(
          color: sectionTheme.buttonBackground,
          shape: const StadiumBorder(),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => showInternationalBanksDialog(context),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.account_balance_outlined,
                    size: 20,
                    color: sectionTheme.buttonText,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'International banks',
                    style: TextStyle(
                      color: sectionTheme.buttonText,
                      fontWeight: FontWeight.w800,
                      fontSize: 15.5,
                      letterSpacing: 0,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BeforeArrivalFlightsAffiliateCard extends StatelessWidget {
  const _BeforeArrivalFlightsAffiliateCard({required this.sectionTheme});

  final GuideSectionTheme sectionTheme;

  @override
  Widget build(BuildContext context) {
    return _InfoCard(
      title: 'Flights',
      color: sectionTheme.softAccent,
      leading: Icon(Icons.flight_takeoff_outlined, color: sectionTheme.accent),
      child: SizedBox(
        width: double.infinity,
        child: Material(
          color: sectionTheme.buttonBackground,
          shape: const StadiumBorder(),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => _showFlightsDialog(context),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              child: Text(
                'Buy your flights',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: sectionTheme.buttonText,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showFlightsDialog(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: const Text(
            'Buy your flights',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFF151922),
              fontSize: 21,
              fontWeight: FontWeight.w800,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _FlightProviderButton(
                label: 'Kiwi',
                asset: 'assets/Kiwi.com logo.png',
                fallbackIcon: Icons.flight_takeoff_outlined,
                onTap: () {
                  _openKiwiLink(context);
                },
              ),
              const SizedBox(height: 12),
              _FlightProviderButton(
                label: 'Trip',
                asset: 'assets/trip logo.png',
                fallbackIcon: Icons.travel_explore_outlined,
                onTap: () {
                  _openUrl(
                    context,
                    'https://www.trip.com/?Allianceid=8388962&SID=315592467&trip_sub1=&trip_sub3=D17431528',
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openKiwiLink(BuildContext context) async {
    var link = await AffiliateLinksService.instance.getLink('Kiwi_link');
    if (link.isEmpty) {
      link = await AffiliateLinksService.instance.getLink('kiwi_link');
    }
    if (!context.mounted) return;

    if (link.isEmpty) {
      await ExternalLinkService.showBrokenLinkDialog(context);
      return;
    }

    await _openUrl(context, link);
  }

  Future<void> _openUrl(BuildContext context, String link) async {
    await ExternalLinkService.open(context, link);
  }
}

class _BeforeArrivalHostelsAffiliateCard extends StatelessWidget {
  const _BeforeArrivalHostelsAffiliateCard({required this.sectionTheme});

  final GuideSectionTheme sectionTheme;

  static const String _tripHostelsUrl =
      'https://www.trip.com/hotels/w/home?Allianceid=8388962&SID=315592467&trip_sub1=&trip_sub3=D17431528';

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Material(
        color: sectionTheme.buttonBackground,
        shape: const StadiumBorder(),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _showHostelsDialog(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            child: Text(
              'Where to book hostels',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: sectionTheme.buttonText,
                fontWeight: FontWeight.w700,
                fontSize: 15.5,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showHostelsDialog(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: const Text(
            'Where to book hostels',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFF151922),
              fontSize: 21,
              fontWeight: FontWeight.w800,
            ),
          ),
          content: _FlightProviderButton(
            label: 'Trip',
            asset: 'assets/trip logo.png',
            fallbackIcon: Icons.hotel_outlined,
            onTap: () {
              _openUrl(context, _tripHostelsUrl);
            },
          ),
        );
      },
    );
  }

  Future<void> _openUrl(BuildContext context, String link) async {
    await ExternalLinkService.open(context, link);
  }
}

class _FlightProviderButton extends StatelessWidget {
  const _FlightProviderButton({
    required this.label,
    required this.asset,
    required this.fallbackIcon,
    required this.onTap,
  });

  final String label;
  final String asset;
  final IconData fallbackIcon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFFFF7F5),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
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
                  asset,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => Icon(
                    fallbackIcon,
                    color: const Color(0xFF9B6A5D),
                    size: 23,
                  ),
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Text(
                  label,
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

class _PopularESimsButton extends StatelessWidget {
  const _PopularESimsButton({required this.sectionTheme});

  final GuideSectionTheme sectionTheme;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Material(
        color: sectionTheme.buttonBackground,
        shape: const StadiumBorder(),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _showESimsDialog(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            child: Text(
              'Popular e-sims',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: sectionTheme.buttonText,
                fontWeight: FontWeight.w700,
                fontSize: 15.5,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showESimsDialog(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: const Text(
            'Popular e-sims',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFF151922),
              fontSize: 21,
              fontWeight: FontWeight.w800,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ESimProviderButton(
                label: 'Airalo',
                asset: 'assets/Airalo logo.png',
                onTap: () => _openCachedESimLink(context, const [
                  'airalo_link',
                  'Airalo_link',
                  'airaloLink',
                ]),
              ),
              const SizedBox(height: 12),
              _ESimProviderButton(
                label: 'Holafly',
                asset: 'assets/Holafly logo .png',
                onTap: () => _openDirectESimLink(
                  context,
                  'https://holafly.sjv.io/B5P7B9',
                ),
              ),
              const SizedBox(height: 12),
              _ESimProviderButton(
                label: 'Sally e-sim',
                asset: 'assets/sally e-sim logo.png',
                onTap: () => _openCachedESimLink(context, const [
                  'sally_esim_link',
                  'sally_e_sim_link',
                  'sally_link',
                  'Sally_link',
                  'sallyesim_link',
                ]),
              ),
              const SizedBox(height: 12),
              _ESimProviderButton(
                label: 'Yesim',
                asset: 'assets/Yesim logo.png',
                onTap: () => _openDirectESimLink(
                  context,
                  'https://yesim.tpo.lv/x3ZNhigi',
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openCachedESimLink(
    BuildContext context,
    List<String> keys,
  ) async {
    var link = '';
    for (final key in keys) {
      link = await AffiliateLinksService.instance.getLink(key);
      if (link.isNotEmpty) break;
    }
    if (!context.mounted) return;
    if (link.isEmpty) {
      await ExternalLinkService.showBrokenLinkDialog(context);
      return;
    }
    await _openESimUrl(context, link);
  }

  Future<void> _openDirectESimLink(BuildContext context, String link) async {
    await _openESimUrl(context, link);
  }

  Future<void> _openESimUrl(BuildContext context, String link) async {
    await ExternalLinkService.open(context, link);
  }
}

class _ESimProviderButton extends StatelessWidget {
  const _ESimProviderButton({
    required this.label,
    required this.asset,
    required this.onTap,
  });

  final String label;
  final String asset;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _FlightProviderButton(
      label: label,
      asset: asset,
      fallbackIcon: Icons.sim_card_outlined,
      onTap: onTap,
    );
  }
}

class _GuideAffiliateCtaButton extends StatelessWidget {
  const _GuideAffiliateCtaButton({
    this.label = 'Compare WHV insurance',
    this.sectionTheme = GuideSectionTheme.fallback,
  });

  final String label;
  final GuideSectionTheme sectionTheme;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Material(
        color: sectionTheme.buttonBackground,
        shape: const StadiumBorder(),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => showTravelInsuranceDialog(context),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: sectionTheme.buttonText,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
