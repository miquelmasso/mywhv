import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';

import '../models/guide_manual/guide_manual.dart';
import '../services/main_tabs_controller.dart';
import 'guide_page_screen.dart';
import '../repositories/guide_manual_repository.dart';
import '../services/overlay_helper.dart';
import '../services/postcode_eligibility_service.dart';

Future<void> _launchExternal(Uri uri) async {
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

Future<void> _openGuidePage(
  BuildContext context,
  String pageId, {
  void Function(int index)? onNavigateToTab,
}) async {
  final manual = await GuideManualRepository().loadFromAssets();
  GuideSection? targetSection;
  for (final section in manual.sections) {
    for (final page in section.pages) {
      if (page.id == pageId) {
        if (!context.mounted) return;
        final shouldShowTabbed =
            section.id == 'housing' ||
            section.id == 'arrival_steps' ||
            section.id == 'regional_and_extension' ||
            section.id == 'transport' ||
            section.id == 'money_taxes';
        if (shouldShowTabbed) {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => GuideSectionScreen(
                section: section,
                initialPageId: page.id,
                onNavigateToTab: onNavigateToTab,
                strings: manual.strings,
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
                onNavigateToTab: onNavigateToTab,
                initialStrings: manual.strings,
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

  // Fallback: if a section id was provided instead of page id, open that section.
  if (targetSection != null && context.mounted) {
    final shouldShowTabbed =
        targetSection.id == 'housing' ||
        targetSection.id == 'arrival_steps' ||
        targetSection.id == 'regional_and_extension' ||
        targetSection.id == 'transport' ||
        targetSection.id == 'money_taxes';
    if (shouldShowTabbed) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => GuideSectionScreen(
            section: targetSection!,
            onNavigateToTab: onNavigateToTab,
            strings: manual.strings,
          ),
        ),
      );
    } else {
      // Open first page if no tabs.
      final firstPage =
          targetSection!.pages.isNotEmpty ? targetSection!.pages.first : null;
      if (firstPage != null) {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => GuidePageScreen(
              sectionId: targetSection!.id,
              page: firstPage,
              onNavigateToTab: onNavigateToTab,
              initialStrings: manual.strings,
            ),
          ),
        );
      }
    }
  }
}

class GuideSectionScreen extends StatelessWidget {
  const GuideSectionScreen({
    super.key,
    required this.section,
    this.onNavigateToTab,
    this.initialPageId,
    this.strings = const {},
  });

  final GuideSection section;
  final void Function(int index)? onNavigateToTab;
  final String? initialPageId;
  final Map<String, String> strings;

  String _resolve(dynamic value) {
    if (value == null) return '';
    if (value is Map && value['key'] is String) {
      final key = value['key'] as String;
      final v = strings[key];
      if (v == null || v.trim().isEmpty) {
        debugPrint('Empty or missing key: $key');
        return key;
      }
      return v;
    }
    if (value is String) {
      if (value.startsWith('@')) {
        final key = value.substring(1);
        final v = strings[key];
        if (v == null || v.trim().isEmpty) {
          debugPrint('Empty or missing key: $key');
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
    if (value is Iterable) {
      return value.map(_resolve).join('\n');
    }
    return value.toString();
  }

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
          return _resolve('@arrival.sim.title');
        case 'tfn':
          return _resolve('@arrival.tfn.title');
        case 'certificates':
          return _resolve('@tab.certificates.title');
      }
    }
    if (section.id == 'housing') {
      switch (page.id) {
        case 'shared_housing_facebook':
          return _resolve('@housing.shared.title');
        case 'lease':
          return _resolve('@housing.lease.title');
      }
    }
    if (section.id == 'regional_and_extension') {
      switch (page.id) {
        case 'extension_rules':
          return _resolve('@regional.extension.title');
        case 'farm_types_pay':
          return _resolve('@regional.farm.title');
      }
    }
    if (section.id == 'transport') {
      switch (page.id) {
        case 'buying_car':
          return _resolve('@transport.buy.title');
        case 'car_rego':
          return _resolve('@transport.rego.title');
        case 'car_roadworthy':
          return _resolve('@transport.roadworthy.title');
        case 'car_tips':
          return _resolve('@transport.tips.title');
      }
    }
    if (section.id == 'money_taxes') {
      switch (page.id) {
        case 'wages':
          return _resolve('@money.wages.title');
        case 'taxes_and_super':
          return _resolve('@money.taxes.title');
        case 'super_basics':
          return _resolve('@money.super.title');
      }
    }
    return _resolve(page.title);
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
                  title: Text(_resolve(section.title)),
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
                            strings: strings,
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
        title: Text(_resolve(section.title)),
        // No search icon for section pages (ex: work/feina).
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _resolve(section.description),
              style: const TextStyle(fontSize: 15, color: Colors.black87),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.separated(
                itemCount: section.pages.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final page = section.pages[index];
                  IconData _pageIcon() {
                    switch (page.id) {
                      case 'find_work_online':
                        return Icons.wifi;
                      case 'work_face_to_face':
                        return Icons.groups_outlined;
                      default:
                        return Icons.menu_book_rounded;
                    }
                  }
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
                            initialStrings: strings,
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
                          child: Icon(_pageIcon(), color: Colors.blue),
                        ),
                        const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _resolve(page.title),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  _resolve(page.summary),
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

class _PageBlocksView extends StatefulWidget {
  const _PageBlocksView({
    required this.page,
    required this.sectionId,
    this.onNavigateToTab,
    required this.strings,
  });

  final GuidePage page;
  final String sectionId;
  final void Function(int index)? onNavigateToTab;
  final Map<String, String> strings;

  @override
  State<_PageBlocksView> createState() => _PageBlocksViewState();
}

class _PageBlocksViewState extends State<_PageBlocksView>
    with SingleTickerProviderStateMixin {
  String _resolve(dynamic value) {
    if (value == null) return '';
    if (value is Map && value['key'] is String) {
      final key = value['key'] as String;
      return widget.strings[key] ?? key;
    }
    if (value is String) {
      if (value.startsWith('@')) {
        final key = value.substring(1);
        return widget.strings[key] ?? key;
      }
      return value;
    }
    if (value is Iterable) {
      return value.map(_resolve).join('\n');
    }
    return value.toString();
  }

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      itemCount: widget.page.blocks.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) => _BlockCard(
        block: widget.page.blocks[index],
        onNavigateToTab: widget.onNavigateToTab,
        resolve: _resolve,
        sectionId: widget.sectionId,
        pageId: widget.page.id,
        vsync: this,
      ),
    );
  }
}

class _BlockCard extends StatelessWidget {
  const _BlockCard({
    required this.block,
    this.onNavigateToTab,
    required this.resolve,
    required this.sectionId,
    required this.pageId,
    this.vsync,
  });

  final GuideBlock block;
  final void Function(int index)? onNavigateToTab;
  final String Function(dynamic value) resolve;
  final String sectionId;
  final String pageId;
  final TickerProvider? vsync;

  Widget _callout({
    required String variant,
    required BuildContext context,
  }) {
    Color bg = Colors.blue.shade50;
    Color iconColor = Colors.blue.shade700;
    IconData icon = Icons.info_outline;
    if (variant == 'warning') {
      bg = Colors.orange.shade50;
      iconColor = Colors.orange.shade700;
      icon = Icons.warning_amber_rounded;
    } else if (variant == 'success') {
      bg = Colors.green.shade50;
      iconColor = Colors.green.shade700;
      icon = Icons.lightbulb_outline;
    }
    debugPrint(
        'Guide callout render -> type=${block.type} variant=$variant section=$sectionId page=$pageId widget=GuideCallout');
    Widget body;
    Widget bulletIcon() {
      if (variant == 'warning') {
        return Icon(Icons.cancel_outlined, size: 18, color: Colors.red.shade700);
      }
      if (variant == 'success') {
        return Icon(Icons.check_circle_outline, size: 18, color: Colors.green.shade700);
      }
      return Icon(Icons.circle, size: 10, color: Colors.grey.shade700);
    }
    if (block.items.isNotEmpty) {
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
                    Expanded(child: Text(resolve(item))),
                  ],
                ),
              ),
            )
            .toList(),
      );
    } else {
      body = Text(resolve(block.content));
    }

    Future<void> handleCopy() async {
      final copyTarget = block.copyText ?? block.content ?? block.items.join('\n');
      final resolvedCopy = resolve(copyTarget);
      if (resolvedCopy.trim().isEmpty) return;
      await Clipboard.setData(ClipboardData(text: resolvedCopy));
      final msgKey = block.copyMessageKey ?? '@ui.message_copied';
      final resolvedMsg = resolve(msgKey);
      if (vsync != null) {
        await OverlayHelper.showCopiedOverlay(context, vsync!, resolvedMsg);
      } else {
        final messenger = ScaffoldMessenger.maybeOf(context);
        if (messenger != null) {
          messenger
            ..hideCurrentSnackBar()
            ..showSnackBar(
              SnackBar(
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                content: Text(resolvedMsg),
                duration: const Duration(seconds: 2),
              ),
            );
        }
      }
    }

    final callout = _InfoCard(
      color: bg,
      leading: Icon(icon, color: iconColor),
      title: resolve(block.title ?? '@ui.tip'),
      child: body,
    );

    if (block.copyOnTap) {
      return InkWell(
        onTap: handleCopy,
        borderRadius: BorderRadius.circular(12),
        child: callout,
      );
    }
    return callout;
  }

  Widget _bullet(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('• '),
          Expanded(child: Text(resolve(text))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasButton = block.buttonUrl != null && block.buttonLabel != null;
    final hasTitle = block.title != null && block.title!.isNotEmpty;
    final hasContent = block.content != null && block.content!.isNotEmpty;
    final hasItems = block.items.isNotEmpty;
    IconData? _iconFromString(String? name) {
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
    Color? cardColor;
    if (block.variant == 'warning') {
      cardColor = Colors.orange.shade50;
    } else if (block.variant == 'success') {
      cardColor = Colors.green.shade50;
    } else if (block.variant == 'info') {
      cardColor = Colors.blue.shade50;
    } else if (block.variant == 'milestone') {
      cardColor = Colors.orange.shade50;
    }
    if (hasButton && !hasTitle && !hasContent && !hasItems) {
      final isCopyAction = block.buttonUrl!.startsWith('copy:');
      final isGuideNavigation = block.buttonUrl!.startsWith('guide:');
      final isAction = block.buttonUrl!.startsWith('action:');
      if (isAction && block.buttonUrl!.contains('check_postcode')) {
        return Padding(
          padding: const EdgeInsets.only(top: 10),
          child: _InlinePostcodeChecker(t: resolve),
        );
      }
      Future<void> _handleTap() async {
        if (isCopyAction) {
          final textToCopy =
              block.content?.isNotEmpty == true ? resolve(block.content) : block.items.join('\\n');
          if (textToCopy.isNotEmpty) {
            await Clipboard.setData(ClipboardData(text: textToCopy));
          }
          return;
        }
        if (isGuideNavigation) {
          final targetPageId = block.buttonUrl!.substring('guide:'.length);
          if (targetPageId.isNotEmpty) {
            await _openGuidePage(context, targetPageId, onNavigateToTab: onNavigateToTab);
          }
          return;
        }
        await _launchExternal(Uri.parse(block.buttonUrl!));
      }

      return Align(
        alignment: Alignment.centerLeft,
        child: ElevatedButton(
          onPressed: _handleTap,
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: Text(resolve(block.buttonLabel)),
        ),
      );
    }

    switch (block.type) {
      case 'callout':
        return _callout(
          variant: block.variant ?? 'info',
          context: context,
        );
      case 'warning':
        return _callout(
          variant: 'warning',
          context: context,
        );
      case 'tip':
        return _callout(
          variant: 'success',
          context: context,
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
                  resolve(block.title),
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
      case 'steps':
        return _InfoCard(
          title: resolve(block.title),
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
                        Expanded(child: Text(resolve(e.value))),
                      ],
                    ),
                  ),
                )
                .toList(),
          ),
        );
      default:
        if (block.variant == 'milestone') {
          final lines = resolve(block.content ?? '').split('\n');
          final value = lines.isNotEmpty ? lines.first : '';
          final small = lines.length > 1 ? lines.sublist(1).join('\n') : '';
          final leadingIcon = Icons.flag;
          return _InfoCard(
            color: cardColor,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Icon(leadingIcon, color: Colors.deepOrange, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        resolve(block.title),
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
                          color: Colors.deepOrange.shade700,
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
        final leadingIcon = _iconFromString(block.icon);
        return _InfoCard(
          title: resolve(block.title),
          color: cardColor,
          leading: leadingIcon != null ? Icon(leadingIcon, color: Colors.brown.shade400) : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (block.content != null && block.content!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    resolve(block.content),
                    style: const TextStyle(color: Colors.black54, fontSize: 13),
                  ),
                ),
              if (block.chips.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
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
                (block.ordered
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: block.items.asMap().entries.map((entry) {
                          final text = resolve(entry.value);
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('${entry.key + 1}. ',
                                    style: const TextStyle(fontWeight: FontWeight.w600)),
                                Expanded(child: Text(text)),
                              ],
                            ),
                          );
                        }).toList(),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: block.items
                            .map(
                              (item) => Padding(
                                padding: const EdgeInsets.symmetric(vertical: 3),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('• '),
                                    Expanded(
                                      child: Text(
                                        resolve(item),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                            .toList(),
                      )),
              if (hasButton) const SizedBox(height: 10),
              if (hasButton)
                Center(
                  child: Material(
                    color: const Color(0xFFF8EDEA),
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () async {
                        if (block.buttonUrl == null) return;
                        if (block.buttonUrl!.startsWith('guide:')) {
                          final targetPageId = block.buttonUrl!.substring('guide:'.length);
                          if (targetPageId.isNotEmpty) {
                            await _openGuidePage(context, targetPageId,
                                onNavigateToTab: onNavigateToTab);
                          }
                          return;
                        }
                        await _launchExternal(Uri.parse(block.buttonUrl!));
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
                ),
            ],
          ),
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
    return Container(
      padding: padding,
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
  const _WagesPageView({
    required this.page,
    this.onNavigateToTab,
    required this.strings,
  });

  final GuidePage page;
  final void Function(int index)? onNavigateToTab;
  final Map<String, String> strings;

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
          color: Color(0xFFE8F5E9),
          leading: const Icon(Icons.lightbulb_outline, color: Colors.green),
          title: 'Remember',
          child: const Text('If you do not receive a payslip or missing information, ask immediately.'),
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
                  _pill('Slightly higher salary/h', positive: true),
                  _pill('Fewer guaranteed hours', positive: false),
                  _pill('Less stability', positive: false),
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
                  _pill('Similar salary/h', positive: true),
                  _pill('More stability', positive: true),
                  _pill('More predictable hours', positive: true),
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
                  _pill('Slightly higher salary/h', positive: true),
                  _pill('Fewer guaranteed hours', positive: false),
                  _pill('Less stability', positive: false),
                ],
                highlight: '~30 AUD/h',
              ),
              const SizedBox(height: 10),
              _column(
                'Part-time / Full-time',
                Colors.blue.shade50,
                [
                  _pill('Similar salary/h', positive: true),
                  _pill('More stability', positive: true),
                  _pill('More predictable hours', positive: true),
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
                'Check official wages (Fair Work)',
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
  const _TaxesPageView({
    required this.page,
    this.onNavigateToTab,
    required this.strings,
  });

  final GuidePage page;
  final void Function(int index)? onNavigateToTab;
  final Map<String, String> strings;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      children: const [
        _InfoCard(
          title: 'WHV tax',
          child: Text('~15% first bracket (can change, check ATO).'),
        ),
        SizedBox(height: 12),
        _InfoCard(
          title: 'Quick',
          child: Text('Give TFN from day one. Every pay must come with a payslip.'),
        ),
        SizedBox(height: 12),
        _InfoCard(
          title: 'Key points',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ChecklistRow('Fiscal year: 1 July – 30 June'),
              _ChecklistRow('Without TFN they withhold a lot more'),
              _ChecklistRow('Check payslip: hours, rate/h, tax and super'),
            ],
          ),
        ),
        SizedBox(height: 12),
        _InfoCard(
          color: Color(0xFFE8F5E9),
          title: 'Practical tip',
          child: Text('If they withheld too much, recover it in the tax return.'),
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

class _InlinePostcodeChecker extends StatefulWidget {
  const _InlinePostcodeChecker({required this.t});

  final String Function(String key) t;

  @override
  State<_InlinePostcodeChecker> createState() => _InlinePostcodeCheckerState();
}

class _InlinePostcodeCheckerState extends State<_InlinePostcodeChecker> {
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
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w600,
                    ),
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

class _SuperPageView extends StatelessWidget {
  const _SuperPageView({
    required this.page,
    this.onNavigateToTab,
    required this.strings,
  });

  final GuidePage page;
  final void Function(int index)? onNavigateToTab;
  final Map<String, String> strings;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      children: const [
        _InfoCard(
          title: 'Essential',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Super = mandatory pension (~11% extra).',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              SizedBox(height: 6),
              Text('Provide your fund or they will create one.'),
            ],
          ),
        ),
        SizedBox(height: 12),
        _InfoCard(
          title: 'Key details',
          child: Column(
            children: [
              _ChecklistRow('Write down fund name and member number.'),
              _ChecklistRow('Check payslip shows super contribution.'),
              _ChecklistRow('New job: give same fund to avoid scattered balances.'),
            ],
          ),
        ),
        SizedBox(height: 12),
        _InfoCard(
          color: Color(0xFFE8F5E9),
          leading: Icon(Icons.flight_takeoff, color: Colors.green),
          title: 'Practical tip',
          child: Text('When leaving, apply for DASP (super) from outside Australia.'),
        ),
        SizedBox(height: 10),
        _InfoCard(
          color: Color(0xFFE8F5E9),
          leading: Icon(Icons.search, color: Colors.green),
          title: 'Lost super',
          child: Text('Find funds via ATO with TFN and consolidate them.'),
        ),
      ],
    );
  }
}
