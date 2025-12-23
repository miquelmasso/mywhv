import 'package:flutter/material.dart';

import '../models/guide_manual/guide_manual.dart';
import '../services/main_tabs_controller.dart';
import 'guide_page_screen.dart';

class GuideSectionScreen extends StatelessWidget {
  const GuideSectionScreen({
    super.key,
    required this.section,
    this.onNavigateToTab,
  });

  final GuideSection section;
  final void Function(int index)? onNavigateToTab;

  bool get _isTabbedSection =>
      section.id == 'arrival_steps' ||
      section.id == 'housing' ||
      section.id == 'regional_and_extension' ||
      section.id == 'transport' ||
      section.id == 'money_taxes';

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
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () {
              // Placeholder search within section
            },
            tooltip: 'Search dins secció',
          ),
        ],
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
