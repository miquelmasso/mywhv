import 'package:flutter/material.dart';

import '../models/guide_manual/guide_manual.dart';
import '../services/main_tabs_controller.dart';

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
    with SingleTickerProviderStateMixin {
  late TabController _controller;
  late List<ChecklistItem> _checklist;

  @override
  void initState() {
    super.initState();
    _controller = TabController(length: 3, vsync: this);
    _checklist = widget.page.checklist
        .map((c) => ChecklistItem(id: c.id, text: c.text, done: c.done))
        .toList();
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

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cta = widget.page.cta;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.page.title),
        bottom: TabBar(
          controller: _controller,
          labelColor: Theme.of(context).colorScheme.primary,
          unselectedLabelColor: Colors.black54,
          tabs: const [
            Tab(text: 'Info'),
            Tab(text: 'Checklist'),
            Tab(text: 'Accions'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _controller,
        children: [
          _InfoTab(blocks: widget.page.blocks),
          _ChecklistTab(
            checklist: _checklist,
            onToggle: _toggleChecklist,
          ),
          _ActionsTab(
            mapCategory: cta?.mapCategory,
            forumTag: cta?.forumTag,
            externalLinks: cta?.externalLinks ?? const [],
            goToMap: () => _goToTab(0),
            goToForum: () => _goToTab(3),
          ),
        ],
      ),
    );
  }
}

class _InfoTab extends StatelessWidget {
  const _InfoTab({required this.blocks});

  final List<GuideBlock> blocks;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: blocks.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final block = blocks[index];
        switch (block.type) {
          case 'bullets':
            return _InfoCard(
              title: block.title,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: block.items
                    .map((item) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('• '),
                              Expanded(child: Text(item)),
                            ],
                          ),
                        ))
                    .toList(),
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
                              Text('${e.key + 1}. ',
                                  style:
                                      const TextStyle(fontWeight: FontWeight.w600)),
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
              child: Text(block.content ?? ''),
            );
          case 'tip':
            return _InfoCard(
              title: block.title ?? 'Tip',
              color: Colors.green.shade50,
              leading: const Icon(Icons.lightbulb_outline, color: Colors.green),
              child: Text(block.content ?? ''),
            );
          case 'text':
          default:
            return _InfoCard(
              title: block.title,
              child: Text(block.content ?? ''),
            );
        }
      },
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
