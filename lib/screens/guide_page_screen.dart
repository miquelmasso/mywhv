import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';

import '../models/guide_manual/guide_manual.dart';
import '../services/main_tabs_controller.dart';
import '../services/overlay_helper.dart';
import 'mail_setup_page.dart';

class GuidePageScreen extends StatefulWidget {
  const GuidePageScreen({
    super.key,
    required this.sectionId,
    required this.page,
    this.onNavigateToTab,
  });

  final String sectionId;
  final GuidePage page;
  final void Function(int index)? onNavigateToTab;

  @override
  State<GuidePageScreen> createState() => _GuidePageScreenState();
}

class _GuidePageScreenState extends State<GuidePageScreen>
    with TickerProviderStateMixin {
  TabController? _controller;
  late List<ChecklistItem> _checklist;
  List<bool> _expandedStates = [];

  @override
  void initState() {
    super.initState();
    final isFindWorkPage = widget.page.id == 'find_work_online';
    final isFaceToFacePage = widget.page.id == 'work_face_to_face';
    final isContractsPage = widget.page.id == 'contracts_and_pay';
    final isVisaPage = widget.page.id == 'visa_overview';
    final isBeforeArrivalPage = widget.page.id == 'before_arrival_overview';
    final hasChecklist = widget.page.checklist.isNotEmpty;
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
      tabLength = 1 + (hasChecklist ? 1 : 0) + (hasActions ? 1 : 0);
    }

    _controller = TabController(length: tabLength, vsync: this);
    _checklist = widget.page.checklist
        .map((c) => ChecklistItem(id: c.id, text: c.text, done: c.done))
        .toList();
    if (isFindWorkPage) {
      _expandedStates = List<bool>.generate(widget.page.sections.length, (i) => false);
    }
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
    const bool hasActions = false; // disable actions tab globally
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.page.title),
        bottom: isFindWorkPage
            ? TabBar(
                controller: _controller,
                labelColor: Theme.of(context).colorScheme.primary,
                unselectedLabelColor: Colors.black54,
                tabs: const [
                  Tab(text: 'Facebook'),
                  Tab(text: 'Webs'),
                  Tab(text: 'Mapa'),
                ],
              )
            : TabBar(
                controller: _controller,
                labelColor: Theme.of(context).colorScheme.primary,
                unselectedLabelColor: Colors.black54,
                tabs: isVisaPage
                    ? const [
                        Tab(text: 'Requisits'),
                        Tab(text: 'Passos per aplicar'),
                      ]
                    : isBeforeArrivalPage
                        ? const [
                            Tab(text: 'Preparació'),
                            Tab(text: 'Diners'),
                            Tab(text: 'Hostal'),
                            Tab(text: 'CV'),
                      ]
                    : isFaceToFacePage
                        ? const [
                            Tab(text: 'Info'),
                            Tab(text: 'CV'),
                      ]
                    : isContractsPage
                        ? const [
                            Tab(text: 'Contractes'),
                            Tab(text: 'Salari'),
                          ]
                        : [
                            const Tab(text: 'Info'),
                            if (hasChecklist) const Tab(text: 'Checklist'),
                            if (hasActions) const Tab(text: 'Accions'),
                          ],
              ),
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
                          _InfoTab(blocks: widget.page.blocks),
                          const _CvTab(),
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
                          ),
                          _SectionBlocksView(
                            section: _findSectionById('apply_steps_tab'),
                            vsync: this,
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
                          ),
                          _SectionBlocksView(
                            section: _findSectionById('money_tab'),
                            vsync: this,
                          ),
                          _SectionBlocksView(
                            section: _findSectionById('hostel_tab'),
                            vsync: this,
                          ),
                          _SectionBlocksView(
                            section: _findSectionById('cv_tab'),
                            vsync: this,
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
                          const _ContractsTab(),
                          const _SalaryTab(),
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
                          _InfoTab(blocks: widget.page.blocks),
                          if (hasChecklist)
                            _ChecklistTab(
                              checklist: _checklist,
                              onToggle: _toggleChecklist,
                            ),
                          if (hasActions)
                            _ActionsTab(
                              mapCategory: cta?.mapCategory,
                              forumTag: cta?.forumTag,
                              externalLinks: cta?.externalLinks ?? const [],
                              goToMap: () => _goToTab(0),
                              goToForum: () => _goToTab(3),
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
  });

  final GuidePageSection? section;
  final bool isFacebook;
  final bool isMap;
  final TickerProvider vsync;
  final VoidCallback goToMap;
  final VoidCallback goToMailSetup;

  @override
  Widget build(BuildContext context) {
    if (section == null) {
      return const Center(child: Text('Sense contingut'));
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ...section!.blocks.map(
          (block) => _buildBlockWidget(
            context,
            block,
            vsync: vsync,
            copyLabel: section!.id == 'facebook'
                ? 'Missatge copiat'
                : section!.id == 'map'
                    ? 'Email copiat'
                    : 'Copiat',
          ),
        ),
        if (isFacebook) ...[
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: ElevatedButton.icon(
              onPressed: () => _launchExternal(Uri.parse('https://www.facebook.com/groups')),
              icon: const Icon(Icons.open_in_new),
              label: const Text('Obrir Facebook Groups'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
        ],
        if (isMap) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: goToMailSetup,
                  icon: const Icon(Icons.email_outlined),
                  label: const Text('Editar email'),
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
                  label: const Text('Anar al mapa'),
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
        ],
      ],
    );
  }
}

class _SectionBlocksView extends StatelessWidget {
  const _SectionBlocksView({
    required this.section,
    required this.vsync,
  });

  final GuidePageSection? section;
  final TickerProvider vsync;

  @override
  Widget build(BuildContext context) {
    if (section == null) {
      return const Center(child: Text('Sense contingut'));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: section!.blocks.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) => _buildBlockWidget(
        context,
        section!.blocks[index],
        vsync: vsync,
      ),
    );
  }
}

class _InfoTab extends StatelessWidget {
  const _InfoTab({required this.blocks, this.footer});

  final List<GuideBlock> blocks;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: blocks.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) => _buildBlockWidget(context, blocks[index]),
    );
  }
}

class _ChecklistTab extends StatelessWidget {
  const _ChecklistTab({
    required this.checklist,
    required this.onToggle,
  });

  final List<ChecklistItem> checklist;
  final void Function(String id, bool? value) onToggle;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: checklist.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
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
            title: Text(item.text),
            controlAffinity: ListTileControlAffinity.leading,
          ),
        );
      },
    );
  }
}

class _CvTab extends StatelessWidget {
  const _CvTab();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _InfoCard(
          title: 'Què posar al CV',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              _BulletText('Dades bàsiques (nom, telèfon, email)'),
              _BulletText('Disponibilitat immediata'),
              _BulletText('Experiència rellevant (hospitality / cleaning / farm)'),
              _BulletText('Visa type (WHV)'),
              _BulletText('Localització actual'),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _InfoCard(
          title: 'Tip',
          color: Colors.green.shade50,
          leading: const Icon(Icons.lightbulb_outline, color: Colors.green),
          child: const Text('CV simple, 1 pàgina, sense foto és acceptable a Austràlia.'),
        ),
      ],
    );
  }
}

class _ContractsTab extends StatelessWidget {
  const _ContractsTab();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: Text(
            'Salari comú',
            style: TextStyle(
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
                title: 'Casual',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text('30\$/h'),
                    SizedBox(height: 6),
                    _BulletText('Pots deixar-ho sense avisar'),
                    _BulletText('Et poden cancelar torns'),
                    _BulletText('Si estas malalt no et paguen'),
                  ],
                ),
              ),
              _InfoCard(
                title: 'Part-time',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text('24.5\$/h'),
                    SizedBox(height: 6),
                    _BulletText('Hores més estables'),
                    _BulletText('Paguen vacances i dies malat'),
                    _BulletText('Per marxar cal avisar'),
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
            text: const TextSpan(
              style: TextStyle(color: Colors.black87, fontSize: 14.5),
              children: [
                TextSpan(text: 'Condicions legals '),
                TextSpan(
                  text: 'Award a Fair Work',
                  style: TextStyle(
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
  const _SalaryTab();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _InfoCard(
          title: 'Impostos (tax)',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text('15–30% segons sou i situació.'),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _InfoCard(
          title: 'Superannuation',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text('~11% (aportació de l’empresa).'),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _InfoCard(
          title: 'Penalty rates',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              _BulletText('Dissabte: +25%*'),
              _BulletText('Diumenge: +50%*'),
              _BulletText('Public holiday: +100%*'),
            ],
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          '*Els % varien segons Award i sector.',
          style: TextStyle(color: Colors.black54, fontSize: 13),
        ),
      ],
    );
  }
}

class _BulletText extends StatelessWidget {
  const _BulletText(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('• '),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

Future<void> _launchExternal(Uri uri) async {
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

Widget _buildBlockWidget(
  BuildContext context,
  GuideBlock block, {
  TickerProvider? vsync,
  String? copyLabel,
}) {
  Widget _buttonIfAny() {
    if (block.buttonLabel == null || block.buttonUrl == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: ElevatedButton(
        onPressed: () => _launchExternal(Uri.parse(block.buttonUrl!)),
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        child: Text(block.buttonLabel!),
      ),
    );
  }

  Widget _textWithLinks(String? text) {
    if (text == null || text.isEmpty) return const SizedBox.shrink();
    final spans = _parseLinkTextSpans(text);
    if (spans.length == 1 && spans.first is TextSpan && (spans.first as TextSpan).recognizer == null) {
      return Text(text);
    }
    return RichText(
      text: TextSpan(
        style: const TextStyle(color: Colors.black87),
        children: spans,
      ),
    );
  }

  switch (block.type) {
    case 'bullets':
      return _InfoCard(
        title: block.title,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ...block.items.map((item) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('• '),
                      Expanded(child: _textWithLinks(item)),
                    ],
                  ),
                )),
            if (block.buttonLabel != null && block.buttonUrl != null) _buttonIfAny(),
          ],
        ),
      );
    case 'steps':
      return _InfoCard(
        title: block.title ?? 'Passos',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: block.items
              .asMap()
              .entries
              .map((e) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${e.key + 1}. ',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        Expanded(child: Text(e.value)),
                      ],
                    ),
                  ))
              .toList(),
        ),
      );
    case 'warning':
      return _InfoCard(
        title: block.title ?? 'Atenció',
        color: Colors.orange.shade50,
        leading: const Icon(Icons.warning_amber, color: Colors.orange),
        child: _textWithLinks(block.content),
      );
    case 'tip':
      final content = block.content ?? '';
      return InkWell(
        onTap: content.isNotEmpty
            ? () async {
                await Clipboard.setData(ClipboardData(text: content));
                if (vsync != null) {
                  await OverlayHelper.showCopiedOverlay(
                    context,
                    vsync!,
                    copyLabel ?? 'Copiat',
                  );
                }
              }
            : null,
        child: _InfoCard(
          title: block.title ?? 'Tip',
          color: Colors.green.shade50,
          leading: const Icon(Icons.lightbulb_outline, color: Colors.green),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _textWithLinks(content),
              if (block.buttonLabel != null && block.buttonUrl != null) _buttonIfAny(),
            ],
          ),
        ),
      );
    case 'text':
    default:
      return _InfoCard(
        title: block.title,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _textWithLinks(block.content),
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
  });

  final String? mapCategory;
  final String? forumTag;
  final List<String> externalLinks;
  final VoidCallback goToMap;
  final VoidCallback goToForum;

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
              'Veure al mapa${mapCategory != null ? ' ($mapCategory)' : ''}',
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
              'Preguntar al fòrum${forumTag != null ? ' (#$forumTag)' : ''}',
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
          if (externalLinks.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text(
              'Links externs',
              style: TextStyle(fontWeight: FontWeight.w700),
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
      label: Text('Preguntar al fòrum (#$tag)'),
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
