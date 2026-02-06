import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/guide_manual/guide_manual.dart';
import '../repositories/guide_manual_repository.dart';
import '../services/main_tabs_controller.dart';
import '../services/overlay_helper.dart';
import 'mail_setup_page.dart';
import 'guide_section_screen.dart';

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
  List<bool> _expandedStates = [];
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
      return value.map((v) => _resolveTextValue(strings, v, onMissing: onMissing)).join('\n');
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
    final bool hasChecklistTab = hasChecklist &&
        widget.sectionId != 'arrival_steps' &&
        widget.sectionId != 'housing' &&
        widget.sectionId != 'regional_and_extension' &&
        widget.sectionId != 'transport' &&
        widget.sectionId != 'money_taxes';
    const bool hasActions = false; // disable actions tab globally

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
      tabLength = 1 + (hasChecklistTab ? 1 : 0) + (hasActions ? 1 : 0);
    }

    final initialIdx =
        (widget.initialTabIndex ?? 0).clamp(0, tabLength - 1);
    _controller = TabController(length: tabLength, vsync: this, initialIndex: initialIdx);
    _checklist = widget.page.checklist
        .map((c) => ChecklistItem(id: c.id, text: c.text, done: c.done))
        .toList();
    if (isFindWorkPage) {
      _expandedStates = List<bool>.generate(widget.page.sections.length, (i) => false);
    }
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
        _checklist[idx] =
            ChecklistItem(id: _checklist[idx].id, text: _checklist[idx].text, done: value ?? false);
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
        hasChecklist && widget.sectionId != 'arrival_steps' && widget.sectionId != 'housing';
    const bool hasActions = false; // disable actions tab globally

    String _tabTitle(String sectionId, String fallbackKey) {
      final s = _findSectionById(sectionId);
      return _resolver(s?.title ?? fallbackKey);
    }

    final tabs = isFindWorkPage
        ? widget.page.sections
            .map((s) => Tab(text: _resolver(s.title)))
            .toList(growable: false)
        : isVisaPage
            ? [
                Tab(text: _tabTitle('requirements_tab', '@visa.requirements.tab_title')),
                Tab(text: _tabTitle('apply_steps_tab', '@visa.apply.tab_title')),
              ]
            : isBeforeArrivalPage
                ? [
                    Tab(text: _tabTitle('preparation_tab', '@before.prep.tab_title')),
                    Tab(text: _tabTitle('lodging_tab', '@before.lodging.tab_title')),
                    Tab(text: _tabTitle('money_tab', '@before.money.tab_title')),
                    Tab(text: _tabTitle('cv_tab', '@before.cv.tab_title')),
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
                            if (hasActions) Tab(text: _resolver('@ui.tab.actions')),
                          ];
    final resolvedTitle = _resolver(widget.page.title);
    final tabBar = TabBar(
      controller: _controller,
      labelColor: Theme.of(context).colorScheme.primary,
      unselectedLabelColor: Colors.black54,
      isScrollable: false,
      labelPadding: EdgeInsets.zero,
      indicatorSize: TabBarIndicatorSize.tab,
      labelStyle: const TextStyle(fontWeight: FontWeight.w600),
      unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w400),
      tabs: tabs,
    );
    return Scaffold(
      appBar: AppBar(
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
                            MaterialPageRoute(builder: (_) => const MailSetupPage()),
                          );
                        },
                        resolve: _resolver,
                      ),
                      _FindWorkTabContent(
                        section: _findSectionById('webs'),
                        vsync: this,
                        goToMap: () => _goToTab(0),
                        goToMailSetup: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const MailSetupPage()),
                          );
                        },
                        resolve: _resolver,
                      ),
                      _FindWorkTabContent(
                        section: _findSectionById('map'),
                        isMap: true,
                        vsync: this,
                        goToMap: () => _goToTab(0),
                        goToMailSetup: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const MailSetupPage()),
                          );
                        },
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
            )
          : isFaceToFacePage
              ? Column(
                  children: [
                    Expanded(
                      child: TabBarView(
                        controller: _controller,
                        children: [
        _InfoTab(blocks: widget.page.blocks, t: _t, resolve: _resolver),
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
                          ),
                          _SectionBlocksView(
                            section: _findSectionById('apply_steps_tab'),
                            vsync: this,
                            onNavigateToTab: widget.onNavigateToTab,
                            t: _t,
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
                          ),
                          _SectionBlocksView(
                            section: _findSectionById('lodging_tab'),
                            vsync: this,
                            onNavigateToTab: widget.onNavigateToTab,
                            t: _t,
                            resolve: _resolver,
                          ),
                          _SectionBlocksView(
                            section: _findSectionById('money_tab'),
                            vsync: this,
                            onNavigateToTab: widget.onNavigateToTab,
                            t: _t,
                            resolve: _resolver,
                          ),
                          _SectionBlocksView(
                            section: _findSectionById('cv_tab'),
                            vsync: this,
                            onNavigateToTab: widget.onNavigateToTab,
                            t: _t,
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
                          _InfoTab(blocks: widget.page.blocks, t: _t, resolve: _resolver),
                          if (hasChecklistTab)
                          _ChecklistTab(
                            checklist: _checklist,
                            onToggle: _toggleChecklist,
                            resolve: _resolver,
                          ),
                          if (hasActions)
                            _ActionsTab(
                              mapCategory: cta?.mapCategory,
                              forumTag: cta?.forumTag,
                              externalLinks: cta?.externalLinks ?? const [],
                              goToMap: () => _goToTab(0),
                              goToForum: () => _goToTab(3),
                              t: _t,
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
  });

  final GuidePageSection? section;
  final bool isFacebook;
  final bool isMap;
  final TickerProvider vsync;
  final VoidCallback goToMap;
  final VoidCallback goToMailSetup;
  final String Function(dynamic value) resolve;

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
        ),
      ),
    ];

    if (isFacebook) {
      widgets.add(
        ElevatedButton.icon(
          onPressed: () => _launchExternal(Uri.parse('https://www.facebook.com/groups')),
          icon: const Icon(Icons.open_in_new),
          label: Text(resolve('ui.open_facebook_groups')),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
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
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
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
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
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
      separatorBuilder: (_, __) =>
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
  });

  final GuidePageSection? section;
  final TickerProvider vsync;
  final void Function(int index)? onNavigateToTab;
  final String Function(String key) t;
  final String Function(dynamic value) resolve;

  @override
  Widget build(BuildContext context) {
    if (section == null) {
      return Center(child: Text(resolve('ui.no_content')));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: section!.blocks.length,
      separatorBuilder: (_, __) => const SizedBox(height: _GuidePageScreenState.kGuideBlockSpacing),
      itemBuilder: (context, index) => _buildBlockWidget(
        context,
        section!.blocks[index],
        vsync: vsync,
        onNavigateToTab: onNavigateToTab,
        t: t,
        resolve: resolve,
      ),
    );
  }
}

class _InfoTab extends StatelessWidget {
  const _InfoTab({
    required this.blocks,
    this.footer,
    required this.t,
    required this.resolve,
  });

  final List<GuideBlock> blocks;
  final Widget? footer;
  final String Function(String key) t;
  final String Function(dynamic value) resolve;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: blocks.length + (footer != null ? 1 : 0),
      separatorBuilder: (_, __) =>
          const SizedBox(height: _GuidePageScreenState.kGuideBlockSpacing),
      itemBuilder: (context, index) {
        if (footer != null && index == blocks.length) {
          return footer!;
        }
        return _buildBlockWidget(
          context,
          blocks[index],
          t: t,
          resolve: resolve,
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
      separatorBuilder: (_, __) =>
          const SizedBox(height: _GuidePageScreenState.kGuideBlockSpacing),
      itemBuilder: (context, index) {
        final item = checklist[index];
        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
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
          color: Colors.green.shade50,
          leading: const Icon(Icons.lightbulb_outline, color: Colors.green),
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
              children: [
                cards[0],
                const SizedBox(height: 12),
                cards[1],
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        GestureDetector(
          onTap: () => _launchExternal(
            Uri.parse('https://www.fairwork.gov.au/employment-conditions/awards'),
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
            children: [
              Text(t('ui.salary.tax_text')),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _InfoCard(
          title: t('ui.salary.super_title'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(t('ui.salary.super_text')),
            ],
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
  const _BulletText({
    required this.text,
    this.label,
    this.orderedIndex,
  });

  final String text;
  final String? label;
  final int? orderedIndex;

  @override
  Widget build(BuildContext context) {
    final baseStyle = DefaultTextStyle.of(context).style;
    final spans = <TextSpan>[
      if (label != null && label!.trim().isNotEmpty)
        TextSpan(text: label, style: baseStyle.copyWith(fontWeight: FontWeight.bold)),
      if (label != null && label!.trim().isNotEmpty)
        TextSpan(text: text.isNotEmpty ? ': ' : ' ', style: baseStyle),
      TextSpan(text: text, style: baseStyle),
    ];

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
            child: RichText(
              text: TextSpan(children: spans),
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> _launchExternal(Uri uri) async {
  await launchUrl(uri, mode: LaunchMode.externalApplication);
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
}) {
  Widget _actionButton({required Widget label, required VoidCallback onPressed, IconData? icon}) {
    final btn = icon != null
        ? ElevatedButton.icon(
            onPressed: onPressed,
            icon: Icon(icon),
            label: label,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          )
        : ElevatedButton(
            onPressed: onPressed,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: label,
          );
    return SizedBox(width: double.infinity, child: btn);
  }

  Widget _buttonIfAny() {
    if (block.buttonLabel == null || block.buttonUrl == null) return const SizedBox.shrink();
    final isCopyAction = block.buttonUrl!.startsWith('copy:');
    final isGuideNavigation = block.buttonUrl!.startsWith('guide:');
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: ElevatedButton(
        onPressed: () async {
          if (isCopyAction) {
            final textToCopy = block.content?.isNotEmpty == true
                ? block.content!
                : block.items.join('\n');
            if (textToCopy.isNotEmpty) {
              await Clipboard.setData(ClipboardData(text: textToCopy));
              if (vsync != null) {
                await OverlayHelper.showCopiedOverlay(
                  context,
                  vsync!,
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
          await _launchExternal(Uri.parse(block.buttonUrl!));
        },
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          backgroundColor: const Color(0xFFF8EDEA),
          foregroundColor: const Color(0xFF8A4A3A),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
          child: Text(resolve(block.buttonLabel)),
      ),
    );
  }

  Widget _cvSheet(GuideBlock block) {
    final lines = (block.content ?? '').split('\n');
    final headings = ['PROFILE', 'WORK EXPERIENCE', 'SKILLS', 'AVAILABILITY'];

    String _line(int index) => index >= 0 && index < lines.length ? lines[index] : '';
    int _headingIndex(String heading) => lines.indexOf(heading);

    List<String> _sectionContent(String heading) {
      final start = _headingIndex(heading);
      if (start == -1) return [];
      final nextIndices =
          headings.map(_headingIndex).where((i) => i > start).toList()..sort();
      final end = nextIndices.isNotEmpty ? nextIndices.first : lines.length;
      return lines.sublist(start + 1, end).where((l) => l.trim().isNotEmpty).toList();
    }

    Widget _section(String title, List<String> content) {
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
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _line(0),
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 20,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    [
                      _line(1),
                      _line(2),
                    ].where((l) => l.isNotEmpty).join('\n'),
                    style: const TextStyle(color: Colors.black87),
                  ),
                  const SizedBox(height: 16),
                  _section('PROFILE', _sectionContent('PROFILE')),
                  const SizedBox(height: 14),
                  _section('WORK EXPERIENCE', _sectionContent('WORK EXPERIENCE')),
                  const SizedBox(height: 14),
                  _section('SKILLS', _sectionContent('SKILLS')),
                  const SizedBox(height: 14),
                  _section('AVAILABILITY', _sectionContent('AVAILABILITY')),
                ],
              ),
            ),
          ),
        ),
        if (block.buttonLabel != null && block.buttonUrl != null) ...[
          const SizedBox(height: 12),
          _buttonIfAny(),
        ],
      ],
    );
  }

  Widget _textWithLinks(dynamic textValue, String Function(dynamic) resolve) {
    final resolved = resolve(textValue);
    if (resolved.isEmpty) return const SizedBox.shrink();
    final spans = _parseLinkTextSpans(resolved);
    if (spans.length == 1 && spans.first is TextSpan && (spans.first as TextSpan).recognizer == null) {
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
        Future<void> _handleTap() async {
          if (isCopyAction) {
            final textToCopy =
                block.content?.isNotEmpty == true ? block.content! : block.items.join('\n');
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
          await _launchExternal(Uri.parse(block.buttonUrl!));
        }

        final label = Text(resolve(block.buttonLabel));
        // No card wrapper; match Facebook button styling
        return _actionButton(
          label: label,
          onPressed: _handleTap,
          icon: block.icon != null ? Icons.open_in_new : null,
        );
      }

      final resolvedTitle = resolve(block.title ?? '');
      final isProcessingCard = block.title == '@visa.requirements.processing_title';
      return _InfoCard(
        title: resolvedTitle,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isProcessingCard)
              Text(resolve('@visa.processing.simple'))
            else if (block.content != null &&
                block.content!.isNotEmpty &&
                block.items.isEmpty)
              _textWithLinks(block.content, resolve),
            ...block.items.asMap().entries.map((entry) {
              final raw = entry.value;
              String? label;
              String text = raw;
              final idx = raw.indexOf(':');
              if (idx != -1) {
                label = raw.substring(0, idx).trim();
                text = raw.substring(idx + 1).trim();
              }
              label = label != null ? resolve(label) : null;
              text = resolve(text);
              return _BulletText(
                text: text,
                label: label,
                orderedIndex: block.ordered ? entry.key : null,
              );
            }),
            if (block.buttonLabel != null && block.buttonUrl != null) _buttonIfAny(),
          ],
        ),
      );
    case 'callout':
      final resolvedTitle = resolve(block.title ?? '');
      Color bg = Colors.blue.shade50;
      Color iconColor = Colors.blue.shade700;
      IconData icon = Icons.info_outline;
      if (block.variant == 'warning') {
        bg = Colors.orange.shade50;
        iconColor = Colors.orange.shade700;
        icon = Icons.warning_amber_rounded;
      } else if (block.variant == 'success') {
        bg = Colors.green.shade50;
        iconColor = Colors.green.shade700;
        icon = Icons.lightbulb_outline;
      }
      return _InfoCard(
        title: resolvedTitle,
        color: bg,
        leading: Icon(icon, color: iconColor),
        child: _textWithLinks(block.content, resolve),
      );
    case 'paragraph':
      return _InfoCard(
        title: resolve(block.title ?? ''),
        child: _textWithLinks(block.content, resolve),
      );
    case 'cv_sheet':
      return _cvSheet(block);
    default:
      if (block.type == 'button') {
        final isCopyAction = block.buttonUrl?.startsWith('copy:') ?? false;
        final isGuideNavigation = block.buttonUrl?.startsWith('guide:') ?? false;
        Future<void> _handleTap() async {
          if (block.buttonLabel == null || block.buttonUrl == null) return;
          if (isCopyAction) {
            final textToCopy =
                block.content?.isNotEmpty == true ? block.content! : block.items.join('\\n');
            if (textToCopy.isNotEmpty) {
              await Clipboard.setData(ClipboardData(text: textToCopy));
              if (vsync != null) {
                await OverlayHelper.showCopiedOverlay(
                  context,
                  vsync!,
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
          await _openGuidePage(context, targetPageId,
              onNavigateToTab: onNavigateToTab, initialTabIndex: tabIndex);
        }
        return;
      }
          await _launchExternal(Uri.parse(block.buttonUrl!));
        }

        return Center(
          child: Material(
            color: const Color(0xFFF8EDEA),
            shape: const StadiumBorder(),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: block.buttonLabel != null && block.buttonUrl != null ? _handleTap : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                child: Text(
                  resolve(block.buttonLabel),
                  style: const TextStyle(
                    color: Color(0xFF8A4A3A),
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
                  if (vsync != null) {
                    await OverlayHelper.showCopiedOverlay(
                      context,
                      vsync!,
                    resolve(copyLabel ?? 'ui.copy'),
                    );
                  }
                }
              : null,
          child: _InfoCard(
            title: block.title ?? (isWarning ? 'Atenció' : 'Tip'),
            color: isWarning ? Colors.orange.shade50 : Colors.green.shade50,
            leading: Icon(
              isWarning ? Icons.warning_amber : Icons.lightbulb_outline,
              color: isWarning ? Colors.orange : Colors.green,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _textWithLinks(content, resolve),
                if (block.buttonLabel != null && block.buttonUrl != null) _buttonIfAny(),
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
            ...block.items.asMap().entries.map((entry) => _BulletText(
                  text: entry.value,
                  orderedIndex: ordered ? entry.key : null,
                )),
            if (block.content != null && block.content!.isNotEmpty && block.items.isEmpty)
              _textWithLinks(block.content, resolve),
            if (block.buttonLabel != null && block.buttonUrl != null) _buttonIfAny(),
          ],
        ),
      );
  }
}

class _ActionsTab extends StatelessWidget {
  const _ActionsTab({
    this.mapCategory,
    this.forumTag,
    required this.externalLinks,
    required this.goToMap,
    required this.goToForum,
    required this.t,
  });

  final String? mapCategory;
  final String? forumTag;
  final List<String> externalLinks;
  final VoidCallback goToMap;
  final VoidCallback goToForum;
  final String Function(String key) t;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ElevatedButton.icon(
            onPressed: goToMap,
            icon: const Icon(Icons.map_outlined),
            label: Text(
              '${t('ui.actions.map')}${mapCategory != null ? ' ($mapCategory)' : ''}',
            ),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: goToForum,
            icon: const Icon(Icons.forum_outlined),
            label: Text(
              '${t('ui.actions.forum')}${forumTag != null ? ' (#$forumTag)' : ''}',
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
          if (externalLinks.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              t('ui.actions.links_title'),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            ...externalLinks.map(
              (link) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(link, style: const TextStyle(color: Colors.blue)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

Widget? _buildForumButton({required String? tag, required VoidCallback onPressed}) {
  if (tag == null || tag.isEmpty) return null;
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

bool _hasActions(GuideCtaLink? cta) {
  if (cta == null) return false;
  final hasMap = (cta.mapCategory ?? '').isNotEmpty;
  final hasForum = (cta.forumTag ?? '').isNotEmpty;
  final hasLinks = cta.externalLinks.isNotEmpty;
  return hasMap || hasForum || hasLinks;
}

List<InlineSpan> _parseLinkTextSpans(String text) {
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
            _launchExternal(Uri.parse(url));
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
  });

  final String? title;
  final Widget child;
  final Color? color;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color ?? Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (leading != null) ...[
            leading!,
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null && title!.isNotEmpty) ...[
                  Text(
                    title!,
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
