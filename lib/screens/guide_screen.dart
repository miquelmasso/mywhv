import 'dart:async';

import 'package:flutter/material.dart';

import '../models/guide_manual/guide_manual.dart';
import '../repositories/guide_manual_repository.dart';
import '../services/search_service.dart';
import 'guide_page_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'guide_section_screen.dart';

class GuideScreen extends StatefulWidget {
  const GuideScreen({super.key, this.onNavigateToTab});

  final void Function(int index)? onNavigateToTab;

  @override
  State<GuideScreen> createState() => _GuideScreenState();
}

class _GuideScreenState extends State<GuideScreen> {
  static const Map<String, IconData> _iconMap = {
    // Use broadly available Material icons to avoid SDK version issues.
    'passport': Icons.badge_outlined,
    'flight_takeoff': Icons.flight_takeoff,
    'how_to_reg': Icons.how_to_reg,
    'home': Icons.home,
    'work': Icons.work,
    'agriculture': Icons.agriculture,
    'directions_car': Icons.directions_car,
    'attach_money': Icons.attach_money,
  };

  late Future<GuideManual> _future;
  String _langCode = 'en';
  String _query = '';
  Timer? _debounce;
  bool _isSearching = false;
  List<SearchResult> _results = [];
  final SearchService _searchService = SearchService.instance;

  @override
  void initState() {
    super.initState();
    _future = _loadManualWithSavedLocale();
  }

  Future<GuideManual> _loadManualWithSavedLocale() async {
    final prefs = await SharedPreferences.getInstance();
    final systemLang = WidgetsBinding.instance.platformDispatcher.locale.languageCode;
    final saved = prefs.getString('guide_lang');
    final chosen = saved ?? (systemLang.isNotEmpty ? systemLang : 'en');
    _langCode = chosen;
    return GuideManualRepository().loadByLocaleCode(chosen);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _openSection(
    BuildContext context,
    GuideSection section,
    Map<String, String> strings,
  ) {
    // Per a seccions que només tenen una pàgina (ex: visa, abans d'arribar), salta directament al contingut.
    final shouldOpenDirectly =
        (section.id == 'visa_requirements' || section.id == 'before_arrival') &&
            section.pages.isNotEmpty;
    if (shouldOpenDirectly) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => GuidePageScreen(
            sectionId: section.id,
            page: section.pages.first,
            onNavigateToTab: widget.onNavigateToTab,
            initialStrings: strings,
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
          strings: strings,
        ),
      ),
    );
  }

  List<GuideSection> _filterSections(List<GuideSection> sections) {
    if (_query.trim().isEmpty) return sections;
    final q = _query.toLowerCase();
    return sections
        .where(
          (s) =>
              s.title.toLowerCase().contains(q) ||
              s.description.toLowerCase().contains(q),
        )
        .toList();
  }

  IconData _iconForSection(String iconName) {
    return _iconMap[iconName] ?? Icons.menu_book_outlined;
  }

  void _onQueryChanged(String val) {
    setState(() => _query = val);
    _debounce?.cancel();
    if (val.trim().isEmpty) {
      setState(() {
        _results = [];
        _isSearching = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 250), () async {
      setState(() => _isSearching = true);
      await _searchService.init();
      final res = _searchService.search(val);
      setState(() {
        _results = res;
        _isSearching = false;
      });
    });
  }

  void _chooseLanguage() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Select language', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 20),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _flagOption(context, 'en', '🇬🇧'),
                  const SizedBox(width: 16),
                  _flagOption(context, 'es', '🇪🇸'),
                  const SizedBox(width: 16),
                  _flagOption(context, 'fr', '🇫🇷'),
                  const SizedBox(width: 16),
                  _flagOption(context, 'de', '🇩🇪'),
                  const SizedBox(width: 16),
                  _flagOption(context, 'hi', '🇮🇳'),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _flagOption(BuildContext context, String code, String flag) {
    final isSelected = _langCode == code;
    return GestureDetector(
      onTap: () async {
        Navigator.of(context).pop();
        if (code == _langCode) return;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('guide_lang', code);
        setState(() {
          _langCode = code;
          _future = GuideManualRepository().loadByLocaleCode(_langCode);
        });
        await _searchService.init(localeOverride: code);
      },
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isSelected
              ? Theme.of(context).colorScheme.primary.withOpacity(0.15)
              : Colors.transparent,
          border: Border.all(
            color: isSelected
                ? Theme.of(context).colorScheme.primary
                : Colors.grey.withOpacity(0.3),
          ),
        ),
        child: Text(
          flag,
          style: const TextStyle(fontSize: 30),
        ),
      ),
    );
  }

  Widget _buildHighlighted(String text) {
    final q = _query.trim();
    if (q.isEmpty) {
      return Text(text, maxLines: 2, overflow: TextOverflow.ellipsis);
    }
    final lower = text.toLowerCase();
    final queryLower = q.toLowerCase();
    final idx = lower.indexOf(queryLower);
    if (idx == -1) {
      return Text(text, maxLines: 2, overflow: TextOverflow.ellipsis);
    }
    final before = text.substring(0, idx);
    final match = text.substring(idx, idx + q.length);
    final after = text.substring(idx + q.length);
    return RichText(
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        style: const TextStyle(color: Colors.black87),
        children: [
          TextSpan(text: before),
          TextSpan(
            text: match,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          TextSpan(text: after),
        ],
      ),
    );
  }

  Widget _buildResultsList(void Function(int index)? onNavigateToTab) {
    if (_isSearching) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_results.isEmpty) {
      return const Center(child: Text('No s’han trobat resultats'));
    }
    return ListView.separated(
      itemCount: _results.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final result = _results[index];
        return InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () async {
            FocusScope.of(context).unfocus();
            await _searchService.navigateToResult(result, context,
                onNavigateToTab: onNavigateToTab);
            setState(() {
              _query = '';
              _results = [];
            });
          },
          child: Container(
            padding: const EdgeInsets.all(12),
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  result.title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  result.subtitle,
                  style: const TextStyle(color: Colors.black54, fontSize: 13),
                ),
                const SizedBox(height: 6),
                _buildHighlighted(result.snippet),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Australia Guide'),
        centerTitle: true,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: IconButton(
              tooltip: 'Change language',
              onPressed: _chooseLanguage,
              icon: const Icon(Icons.translate),
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              onChanged: _onQueryChanged,
              decoration: InputDecoration(
                hintText: 'Search anything',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.white,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: Colors.grey.withOpacity(0.2),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: FutureBuilder<GuideManual>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError || snapshot.data == null) {
                    return Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text('Error carregant la guia.'),
                        const SizedBox(height: 12),
                        ElevatedButton(
                          onPressed: () {
                            setState(() {
                              _future = GuideManualRepository().loadFromAssets();
                            });
                          },
                          child: const Text('Retry'),
                        ),
                      ],
                    );
                  }
                  if (_query.trim().isNotEmpty) {
                    return _buildResultsList(widget.onNavigateToTab);
                  }

                  final strings = snapshot.data!.strings;
                  String resolve(dynamic value) {
                    if (value == null) return '';
                    if (value is Map && value['key'] is String) {
                      final key = value['key'] as String;
                      return strings[key] ?? key;
                    }
                    if (value is String) {
                      if (value.startsWith('@')) {
                        final key = value.substring(1);
                        return strings[key] ?? key;
                      }
                      return value;
                    }
                    if (value is Iterable) {
                      return value.map(resolve).join('\n');
                    }
                    return value.toString();
                  }

                  final sections = _filterSections(snapshot.data!.sections);
                  if (sections.isEmpty) {
                    return const Center(child: Text('No s’han trobat seccions.'));
                  }
                  return GridView.builder(
                    itemCount: sections.length,
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 12,
                      childAspectRatio: 1.35,
                    ),
                    itemBuilder: (context, index) {
                      final section = sections[index];
                      return InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => _openSection(context, section, snapshot.data!.strings),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
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
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(7),
                                decoration: BoxDecoration(
                                  color: Colors.blue.withOpacity(0.08),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  _iconForSection(section.icon),
                                  size: 22,
                              color: Colors.blue[700],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                                resolve(section.title),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13.5,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
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
