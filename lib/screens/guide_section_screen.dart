import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/guide_manual/guide_manual.dart';
import '../services/main_tabs_controller.dart';
import 'guide_page_screen.dart';

class GuideSectionScreen extends StatelessWidget {
  const GuideSectionScreen({
    super.key,
    required this.section,
    this.onNavigateToTab,
    this.initialPageId,
  });

  final GuideSection section;
  final void Function(int index)? onNavigateToTab;
  final String? initialPageId;

  bool get _isTabbedSection =>
      section.id == 'arrival_steps' ||
      section.id == 'housing' ||
      section.id == 'regional_and_extension' ||
      section.id == 'transport' ||
      section.id == 'money_taxes';

  int get _initialTabIndex {
    if (initialPageId == null) return 0;
    final idx = section.pages.indexWhere((p) => p.id == initialPageId);
    return idx == -1 ? 0 : idx;
  }

  String _tabLabelForPage(GuidePage page) {
    if (section.id == 'arrival_steps') {
      switch (page.id) {
        case 'sim_and_internet':
          return 'SIM';
        case 'tfn':
          return 'TFN';
        case 'certificates':
          return 'Certificats';
      }
    }
    if (section.id == 'housing') {
      switch (page.id) {
        case 'shared_housing_facebook':
          return 'Compartit';
        case 'lease':
          return 'Agència';
      }
    }
    if (section.id == 'regional_and_extension') {
      switch (page.id) {
        case 'extension_rules':
          return 'Extensió';
        case 'farm_types_pay':
          return 'Feines i sous';
      }
    }
    if (section.id == 'transport') {
      switch (page.id) {
        case 'buying_car':
          return 'Comprar';
        case 'car_rego':
          return 'Rego';
        case 'car_roadworthy':
          return 'Roadworthy';
        case 'car_tips':
          return 'Consells';
      }
    }
    if (section.id == 'money_taxes') {
      switch (page.id) {
        case 'wages':
          return 'Salaris';
        case 'taxes_and_super':
          return 'Impostos';
        case 'super_basics':
          return 'Super';
      }
    }
    return page.title;
  }

  @override
  Widget build(BuildContext context) {
    if (_isTabbedSection) {
      final tabs = section.pages.map((p) => Tab(text: _tabLabelForPage(p))).toList();
      return DefaultTabController(
        length: section.pages.length,
        initialIndex: _initialTabIndex.clamp(0, section.pages.length - 1).toInt(),
        child: Builder(builder: (context) {
          final controller = DefaultTabController.of(context);
          return Scaffold(
            appBar: AppBar(
              title: Text(section.title),
              bottom: TabBar(
                isScrollable: false,
                labelPadding: EdgeInsets.zero,
                indicatorSize: TabBarIndicatorSize.tab,
                labelColor: Theme.of(context).colorScheme.primary,
                unselectedLabelColor: Colors.black54,
                labelStyle: const TextStyle(fontWeight: FontWeight.w600),
                unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w400),
                tabs: tabs,
              ),
            ),
            body: Column(
              children: [
                Expanded(
                  child: TabBarView(
                    children: section.pages
                        .map(
                          (page) => _PageBlocksView(
                            page: page,
                            sectionId: section.id,
                            onNavigateToTab: onNavigateToTab,
                          ),
                        )
                        .toList(),
                  ),
                ),
                AnimatedBuilder(
                  animation: controller!,
                  builder: (context, _) {
                    final idx = controller.index.clamp(0, section.pages.length - 1);
                    final tag = section.pages[idx].cta?.forumTag;
                    final forumButton = _forumButton(tag, () {
                      MainTabsController.goToTab(context, 3,
                          forumTag: tag, onNavigateToTab: onNavigateToTab);
                    });
                    if (forumButton == null) return const SizedBox.shrink();
                    return SafeArea(
                      top: false,
                      minimum: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: forumButton,
                    );
                  },
                ),
              ],
            ),
          );
        }),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(section.title),
        // No search icon for section pages (ex: work/feina).
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              section.description,
              style: const TextStyle(fontSize: 15, color: Colors.black87),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.separated(
                itemCount: section.pages.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final page = section.pages[index];
                  return InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => GuidePageScreen(
                            sectionId: section.id,
                            page: page,
                            onNavigateToTab: onNavigateToTab,
                          ),
                        ),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
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
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.blue.withOpacity(0.08),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.menu_book_rounded,
                                color: Colors.blue),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  page.title,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  page.summary,
                                  style: const TextStyle(
                                    color: Colors.black87,
                                    fontSize: 13.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right, color: Colors.black45),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PageBlocksView extends StatelessWidget {
  const _PageBlocksView({
    required this.page,
    required this.sectionId,
    this.onNavigateToTab,
  });

  final GuidePage page;
  final String sectionId;
  final void Function(int index)? onNavigateToTab;

  @override
  Widget build(BuildContext context) {
    if (sectionId == 'money_taxes' && page.id == 'wages') {
      return _WagesPageView(page: page, onNavigateToTab: onNavigateToTab);
    }
    if (sectionId == 'money_taxes' && page.id == 'taxes_and_super') {
      return _TaxesPageView(page: page, onNavigateToTab: onNavigateToTab);
    }
    if (sectionId == 'money_taxes' && page.id == 'super_basics') {
      return _SuperPageView(page: page, onNavigateToTab: onNavigateToTab);
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      itemCount: page.blocks.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) =>
          _BlockCard(block: page.blocks[index], onNavigateToTab: onNavigateToTab),
    );
  }
}

class _BlockCard extends StatelessWidget {
  const _BlockCard({required this.block, this.onNavigateToTab});

  final GuideBlock block;
  final void Function(int index)? onNavigateToTab;

  Widget _bullet(String text) {
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

  @override
  Widget build(BuildContext context) {
    switch (block.type) {
      case 'warning':
        return _InfoCard(
          color: Colors.orange.shade50,
          leading: const Icon(Icons.warning_amber, color: Colors.orange),
          title: block.title ?? 'Important',
          child: Text(block.content ?? ''),
        );
      case 'tip':
        return _InfoCard(
          color: Colors.green.shade50,
          leading: const Icon(Icons.lightbulb_outline, color: Colors.green),
          title: block.title ?? 'Tip',
          child: Text(block.content ?? ''),
        );
      case 'steps':
        return _InfoCard(
          title: block.title,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: block.items
                .asMap()
                .entries
                .map(
                  (e) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${e.key + 1}. ',
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                        Expanded(child: Text(e.value)),
                      ],
                    ),
                  ),
                )
                .toList(),
          ),
        );
      case 'bullets':
        return _InfoCard(
          title: block.title,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: block.items.map(_bullet).toList(),
          ),
        );
      default:
        return _InfoCard(
          title: block.title,
          child: Text(block.content ?? ''),
        );
    }
  }
}

Widget? _forumButton(String? tag, VoidCallback onPressed) {
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

class _WagesPageView extends StatelessWidget {
  const _WagesPageView({required this.page, this.onNavigateToTab});

  final GuidePage page;
  final void Function(int index)? onNavigateToTab;

  Future<void> _openFairWork(BuildContext context) async {
    final uri = Uri.parse('https://www.fairwork.gov.au/employment-conditions/awards');
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No s’ha pogut obrir l’enllaç.')),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No s’ha pogut obrir l’enllaç.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      children: [
        
        const SizedBox(height: 12),
        const ContractComparisonCard(),
        const SizedBox(height: 6),
        
        const SizedBox(height: 12),
        _InfoCard(
          color: Colors.green.shade50,
          leading: const Icon(Icons.lightbulb_outline, color: Colors.green),
          title: 'Consells pràctics',
          child: const Text('Si no reps payslip o falta info, pregunta de seguida.'),
        ),
        const SizedBox(height: 12),
        OfficialLinkTile(onTap: (ctx) => _openFairWork(ctx)),
      ],
    );
  }
}

class ContractComparisonCard extends StatelessWidget {
  const ContractComparisonCard({super.key});

  Widget _pill(String text, {required bool positive}) {
    final icon = positive ? Icons.check_circle_outline : Icons.remove_circle_outline;
    final iconColor = positive ? Colors.green : Colors.red.shade400;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: iconColor, size: 18),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: Colors.black87,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ),
      ],
    );
  }

  Widget _column(String title, Color color, List<Widget> points, {required String highlight}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5),
          ),
          const SizedBox(height: 4),
          Text(
            highlight,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
          const SizedBox(height: 8),
          ...points.map(
            (p) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: p,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 520;
        final content = Row(
          children: [
            Expanded(
              child: _column(
                'Casual',
                Colors.orange.shade50,
                [
                  _pill('Sou/h lleugerament més alt', positive: true),
                  _pill('Menys hores garantides', positive: false),
                  _pill('Menys estabilitat', positive: false),
                ],
                highlight: '~30 AUD/h',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _column(
                'Part-time / Full-time',
                Colors.blue.shade50,
                [
                  _pill('Sou/h similar', positive: true),
                  _pill('Més estabilitat', positive: true),
                  _pill('Hores més previsibles', positive: true),
                ],
                highlight: '~24 AUD/h',
              ),
            ),
          ],
        );

        if (isNarrow) {
          return Column(
            children: [
              _column(
                'Casual',
                Colors.orange.shade50,
                [
                  _pill('Sou/h lleugerament més alt', positive: true),
                  _pill('Menys hores garantides', positive: false),
                  _pill('Menys estabilitat', positive: false),
                ],
                highlight: '~30 AUD/h',
              ),
              const SizedBox(height: 10),
              _column(
                'Part-time / Full-time',
                Colors.blue.shade50,
                [
                  _pill('Sou/h similar', positive: true),
                  _pill('Més estabilitat', positive: true),
                  _pill('Hores més previsibles', positive: true),
                ],
                highlight: '~24 AUD/h',
              ),
            ],
          );
        }

        return content;
      },
    );
  }
}

class OfficialLinkTile extends StatelessWidget {
  const OfficialLinkTile({super.key, required this.onTap});

  final Future<void> Function(BuildContext) onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => onTap(context),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
          border: Border.all(color: Colors.blue.withOpacity(0.15)),
        ),
        child: Row(
          children: [
            const Icon(Icons.open_in_new, color: Colors.blue),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Consulta salaris oficials (Fair Work)',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Colors.black87,
                ),
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.blue[700]),
          ],
        ),
      ),
    );
  }
}

class _TaxesPageView extends StatelessWidget {
  const _TaxesPageView({required this.page, this.onNavigateToTab});

  final GuidePage page;
  final void Function(int index)? onNavigateToTab;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      children: const [
        _InfoCard(
          title: 'WHV tax',
          child: Text('~15% al primer tram (pot canviar, mira ATO).'),
        ),
        SizedBox(height: 12),
        _InfoCard(
          title: 'Ràpid',
          child: Text('Dona el TFN des del primer dia. Cada paga ha de venir amb payslip.'),
        ),
        SizedBox(height: 12),
        _InfoCard(
          title: 'Claus',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ChecklistRow('Any fiscal: 1 juliol – 30 juny'),
              _ChecklistRow('Sense TFN retenen molt més'),
              _ChecklistRow('Revisa al payslip: hores, tarifa/h, tax i super'),
            ],
          ),
        ),
        SizedBox(height: 12),
        _InfoCard(
          color: Colors.greenAccent,
          title: 'Consells pràctics',
          child: Text('Si t’han retingut massa, recupera-ho a la tax return.'),
        ),
      ],
    );
  }
}

class _ChecklistRow extends StatelessWidget {
  const _ChecklistRow(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          const Icon(Icons.check_circle_outline, color: Colors.green, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _SuperPageView extends StatelessWidget {
  const _SuperPageView({required this.page, this.onNavigateToTab});

  final GuidePage page;
  final void Function(int index)? onNavigateToTab;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      children: const [
        _InfoCard(
          title: 'Essencial',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Super = pensió obligatòria (~11% extra).',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              SizedBox(height: 6),
              Text('Dona el teu fons o te’n crearan un.'),
            ],
          ),
        ),
        SizedBox(height: 12),
        _InfoCard(
          title: 'Detalls importants',
          child: Column(
            children: [
              _ChecklistRow('Anota nom del fons i número de membre.'),
              _ChecklistRow('Comprova al payslip que hi ha aportació a super.'),
              _ChecklistRow('Nova feina: dona el mateix fons per no dispersar saldos.'),
            ],
          ),
        ),
        SizedBox(height: 12),
        _InfoCard(
          color: Color(0xFFE8F5E9),
          leading: Icon(Icons.flight_takeoff, color: Colors.green),
          title: 'Consells pràctics',
          child: Text('Quan marxis, demana el DASP (super) des de fora d’Austràlia.'),
        ),
        SizedBox(height: 10),
        _InfoCard(
          color: Color(0xFFE8F5E9),
          leading: Icon(Icons.search, color: Colors.green),
          title: 'Super perdut',
          child: Text('Busca fons a l’ATO amb el TFN i consolida’ls.'),
        ),
      ],
    );
  }
}
