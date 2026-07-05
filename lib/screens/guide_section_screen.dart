import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/guide_manual/guide_manual.dart';
import '../services/affiliate_links_service.dart';
import '../services/external_link_service.dart';
import '../services/main_tabs_controller.dart';
import 'guide_page_screen.dart';
import '../repositories/guide_manual_repository.dart';
import '../services/overlay_helper.dart';
import '../services/postcode_eligibility_service.dart';
import '../utils/guide_section_theme.dart';
import '../widgets/guide_back_button.dart';

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

Future<void> _launchExternal(BuildContext context, Uri uri) async {
  await ExternalLinkService.open(context, uri.toString());
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
    final section = targetSection;
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
            onNavigateToTab: onNavigateToTab,
            strings: manual.strings,
          ),
        ),
      );
    } else {
      // Open first page if no tabs.
      final firstPage = section.pages.isNotEmpty ? section.pages.first : null;
      if (firstPage != null) {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => GuidePageScreen(
              sectionId: section.id,
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
    final sectionTheme = GuideSectionTheme.forSection(section.id);
    if (_isTabbedSection) {
      final tabs = section.pages
          .map((p) => Tab(text: _tabLabelForPage(p)))
          .toList();
      return DefaultTabController(
        length: section.pages.length,
        initialIndex: _initialTabIndex
            .clamp(0, section.pages.length - 1)
            .toInt(),
        child: Builder(
          builder: (context) {
            final controller = DefaultTabController.of(context);
            return Scaffold(
              backgroundColor: sectionTheme.pageBackground,
              appBar: AppBar(
                backgroundColor: sectionTheme.pageBackground,
                surfaceTintColor: sectionTheme.pageBackground,
                centerTitle: true,
                leadingWidth: 72,
                leading: Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: GuideBackButton(
                    onTap: () => Navigator.of(context).pop(),
                  ),
                ),
                title: Text(_resolve(section.title)),
                bottom: TabBar(
                  isScrollable: false,
                  labelPadding: EdgeInsets.zero,
                  indicatorSize: TabBarIndicatorSize.tab,
                  labelColor: sectionTheme.buttonText,
                  unselectedLabelColor: Colors.black54,
                  indicatorColor: sectionTheme.accent,
                  dividerColor: sectionTheme.softAccent,
                  labelStyle: const TextStyle(fontWeight: FontWeight.w600),
                  unselectedLabelStyle: const TextStyle(
                    fontWeight: FontWeight.w400,
                  ),
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
                              sectionTheme: sectionTheme,
                            ),
                          )
                          .toList(),
                    ),
                  ),
                  AnimatedBuilder(
                    animation: controller,
                    builder: (context, _) {
                      final idx = controller.index.clamp(
                        0,
                        section.pages.length - 1,
                      );
                      final tag = section.pages[idx].cta?.forumTag;
                      final forumButton = _forumButton(tag, () {
                        MainTabsController.goToTab(
                          context,
                          3,
                          forumTag: tag,
                          onNavigateToTab: onNavigateToTab,
                        );
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
          },
        ),
      );
    }

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
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final page = section.pages[index];
                  IconData pageIcon() {
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
                            color: Colors.black.withValues(alpha: 0.05),
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
                              color: sectionTheme.softAccent,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(pageIcon(), color: sectionTheme.accent),
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
                          const Icon(
                            Icons.chevron_right,
                            color: Colors.black45,
                          ),
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
    required this.sectionTheme,
  });

  final GuidePage page;
  final String sectionId;
  final void Function(int index)? onNavigateToTab;
  final Map<String, String> strings;
  final GuideSectionTheme sectionTheme;

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
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) => _BlockCard(
        block: widget.page.blocks[index],
        onNavigateToTab: widget.onNavigateToTab,
        resolve: _resolve,
        sectionId: widget.sectionId,
        pageId: widget.page.id,
        vsync: this,
        sectionTheme: widget.sectionTheme,
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
    required this.sectionTheme,
    this.vsync,
  });

  final GuideBlock block;
  final void Function(int index)? onNavigateToTab;
  final String Function(dynamic value) resolve;
  final String sectionId;
  final String pageId;
  final GuideSectionTheme sectionTheme;
  final TickerProvider? vsync;

  Widget _callout({required String variant, required BuildContext context}) {
    Color bg = sectionTheme.softAccent;
    Color iconColor = sectionTheme.accent;
    IconData icon = Icons.info_outline;
    if (variant == 'warning') {
      bg = sectionTheme.calloutBackground;
      iconColor = sectionTheme.warningIcon;
      icon = Icons.warning_amber_rounded;
    } else if (variant == 'success') {
      bg = sectionTheme.calloutBackground;
      iconColor = sectionTheme.warningIcon;
      icon = Icons.lightbulb_outline;
    }
    debugPrint(
      'Guide callout render -> type=${block.type} variant=$variant section=$sectionId page=$pageId widget=GuideCallout',
    );
    Widget body;
    Widget bulletIcon() {
      if (variant == 'warning') {
        return Icon(
          Icons.cancel_outlined,
          size: 18,
          color: sectionTheme.warningIcon,
        );
      }
      if (variant == 'success') {
        return Icon(
          Icons.check_circle_outline,
          size: 18,
          color: sectionTheme.warningIcon,
        );
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
      final copyTarget =
          block.copyText ?? block.content ?? block.items.join('\n');
      final resolvedCopy = resolve(copyTarget);
      if (resolvedCopy.trim().isEmpty) return;
      await Clipboard.setData(ClipboardData(text: resolvedCopy));
      if (!context.mounted) return;
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
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
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

  @override
  Widget build(BuildContext context) {
    final hasButton = block.buttonUrl != null && block.buttonLabel != null;
    final hasTitle = block.title != null && block.title!.isNotEmpty;
    final hasContent = block.content != null && block.content!.isNotEmpty;
    final hasItems = block.items.isNotEmpty;
    final isBeforeLandingCard =
        block.title == '@arrival.sim.before_title' ||
        resolve(block.title) == 'Before landing';
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
      Future<void> handleTap() async {
        if (isCopyAction) {
          final textToCopy = block.content?.isNotEmpty == true
              ? resolve(block.content)
              : block.items.join('\\n');
          if (textToCopy.isNotEmpty) {
            await Clipboard.setData(ClipboardData(text: textToCopy));
          }
          return;
        }
        if (isGuideNavigation) {
          final targetPageId = block.buttonUrl!.substring('guide:'.length);
          if (targetPageId.isNotEmpty) {
            await _openGuidePage(
              context,
              targetPageId,
              onNavigateToTab: onNavigateToTab,
            );
          }
          return;
        }
        await _launchExternal(context, Uri.parse(block.buttonUrl!));
      }

      return SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: handleTap,
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
      );
    }

    switch (block.type) {
      case 'callout':
        return _callout(variant: block.variant ?? 'info', context: context);
      case 'warning':
        return _callout(variant: 'warning', context: context);
      case 'tip':
        return _callout(variant: 'success', context: context);
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
                        Text(
                          '${e.key + 1}. ',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
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
                    Icon(leadingIcon, color: sectionTheme.accent, size: 20),
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
        return _InfoCard(
          title: resolve(block.title),
          color: cardColor,
          leading: effectiveLeadingIcon != null
              ? Icon(effectiveLeadingIcon, color: effectiveLeadingColor)
              : null,
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
              if (isBeforeLandingCard) ...[
                const SizedBox(height: 6),
                const Text(
                  'Otherwise get an e-sim that will work as soon as you land.',
                  style: TextStyle(color: Colors.black54, fontSize: 13),
                ),
                const SizedBox(height: 12),
                _PopularESimsButton(sectionTheme: sectionTheme),
              ],
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
                                Text(
                                  '${entry.key + 1}. ',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
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
                                padding: const EdgeInsets.symmetric(
                                  vertical: 3,
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('• '),
                                    Expanded(child: Text(resolve(item))),
                                  ],
                                ),
                              ),
                            )
                            .toList(),
                      )),
              if (hasButton) const SizedBox(height: 10),
              if (hasButton)
                SizedBox(
                  width: double.infinity,
                  child: Material(
                    color: sectionTheme.buttonBackground,
                    shape: const StadiumBorder(),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () async {
                        if (block.buttonUrl == null) return;
                        if (block.buttonUrl!.startsWith('guide:')) {
                          final targetPageId = block.buttonUrl!.substring(
                            'guide:'.length,
                          );
                          if (targetPageId.isNotEmpty) {
                            await _openGuidePage(
                              context,
                              targetPageId,
                              onNavigateToTab: onNavigateToTab,
                            );
                          }
                          return;
                        }
                        await _launchExternal(
                          context,
                          Uri.parse(block.buttonUrl!),
                        );
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
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
            ],
          ),
        );
    }
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
                asset: 'assets/icons/Airalo logo.png',
                onTap: () => _openCachedESimLink(context, const [
                  'airalo_link',
                  'Airalo_link',
                  'airaloLink',
                ]),
              ),
              const SizedBox(height: 12),
              _ESimProviderButton(
                label: 'Holafly',
                asset: 'assets/icons/Holafly logo .png',
                onTap: () => _openDirectESimLink(
                  context,
                  'https://holafly.sjv.io/B5P7B9',
                ),
              ),
              const SizedBox(height: 12),
              _ESimProviderButton(
                label: 'Sally e-sim',
                asset: 'assets/icons/sally e-sim logo.png',
                onTap: () => _openCachedESimLink(context, const [
                  'sally_esim_link',
                  'sally_e_sim_link',
                  'sally_link',
                  'Sally_link',
                  'sallyesim_link',
                  'sally e-sim_link',
                ]),
              ),
              const SizedBox(height: 12),
              _ESimProviderButton(
                label: 'Yesim',
                asset: 'assets/icons/Yesim logo.png',
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
                  errorBuilder: (_, _, _) => const Icon(
                    Icons.sim_card_outlined,
                    color: Color(0xFF9B6A5D),
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

const bool _showSectionForumButtons = false;

Widget? _forumButton(String? tag, VoidCallback onPressed) {
  if (!_showSectionForumButtons || tag == null || tag.isEmpty) return null;
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
