import 'dart:async';

import '../models/guide_manual/guide_manual.dart';
import '../repositories/guide_manual_repository.dart';
import '../screens/guide_page_screen.dart';
import '../screens/guide_section_screen.dart';
import 'package:flutter/material.dart';

class SearchResult {
  final String title;
  final String subtitle;
  final String snippet;
  final String sectionId;
  final String pageId;
  final int? tabIndex;
  final double score;

  const SearchResult({
    required this.title,
    required this.subtitle,
    required this.snippet,
    required this.sectionId,
    required this.pageId,
    required this.score,
    this.tabIndex,
  });
}

class SearchService {
  SearchService._();

  static final SearchService instance = SearchService._();

  GuideManual? _manual;
  final List<_SearchEntry> _entries = [];
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    _manual = await GuideManualRepository().loadFromAssets();
    _buildIndex();
    _initialized = true;
  }

  List<SearchResult> search(String query) {
    if (!_initialized || query.trim().isEmpty) return [];
    final q = query.trim().toLowerCase();
    final results = <SearchResult>[];

    for (final entry in _entries) {
      double score = 0;
      final inTitle = entry.titleLower.contains(q);
      final inSubtitle = entry.subtitleLower.contains(q);
      final inBody = entry.bodyLower.contains(q);

      if (!inTitle && !inSubtitle && !inBody) continue;

      if (inTitle) score += 3;
      if (inSubtitle) score += 2;
      if (inBody) score += 1;

      final snippet = _buildSnippet(entry, q);

      results.add(
        SearchResult(
          title: entry.title,
          subtitle: entry.subtitle,
          snippet: snippet,
          sectionId: entry.sectionId,
          pageId: entry.pageId,
          tabIndex: entry.tabIndex,
          score: score,
        ),
      );
    }

    results.sort((a, b) {
      final scoreDiff = b.score.compareTo(a.score);
      if (scoreDiff != 0) return scoreDiff;
      return a.snippet.length.compareTo(b.snippet.length);
    });

    return results.take(20).toList();
  }

  Future<void> navigateToResult(
    SearchResult result,
    BuildContext context, {
    void Function(int index)? onNavigateToTab,
  }) async {
    if (_manual == null) return;
    GuideSection? section;
    for (final s in _manual!.sections) {
      if (s.id == result.sectionId) {
        section = s;
        break;
      }
    }
    section ??= _manual!.sections.isNotEmpty ? _manual!.sections.first : null;
    if (section == null) return;

    GuidePage? page;
    for (final p in section.pages) {
      if (p.id == result.pageId) {
        page = p;
        break;
      }
    }
    page ??= section.pages.isNotEmpty ? section.pages.first : null;
    if (page == null) return;

    final resolvedSection = section;
    final resolvedPage = page;

    if (_isTabbedSection(resolvedSection.id)) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => GuideSectionScreen(
            section: resolvedSection,
            onNavigateToTab: onNavigateToTab,
            initialPageId: resolvedPage.id,
          ),
        ),
      );
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => GuidePageScreen(
            sectionId: resolvedSection.id,
            page: resolvedPage,
            onNavigateToTab: onNavigateToTab,
          ),
        ),
      );
    }
  }

  void _buildIndex() {
    if (_manual == null) return;
    for (final section in _manual!.sections) {
      for (var i = 0; i < section.pages.length; i++) {
        final page = section.pages[i];
        final tabIndex = _isTabbedSection(section.id) ? i : null;
        final lines = <String>[];

        void addLine(String? text) {
          if (text == null || text.trim().isEmpty) return;
          lines.add(text.trim());
        }

        addLine(page.title);
        addLine(page.summary);
        for (final block in page.blocks) {
          addLine(block.title);
          addLine(block.content);
          for (final item in block.items) {
            addLine(item);
          }
        }
        for (final sec in page.sections) {
          addLine(sec.title);
          addLine(sec.subtitle);
          for (final block in sec.blocks) {
            addLine(block.title);
            addLine(block.content);
            for (final item in block.items) {
              addLine(item);
            }
          }
        }

        final body = lines.join(' • ');
        _entries.add(
          _SearchEntry(
            sectionId: section.id,
            pageId: page.id,
            title: page.title,
            subtitle: section.title,
            body: body,
            tabIndex: tabIndex,
            lines: lines,
          ),
        );
      }
    }
  }

  String _buildSnippet(_SearchEntry entry, String query) {
    final matchLine = entry.lines.firstWhere(
      (l) => l.toLowerCase().contains(query),
      orElse: () => entry.lines.isNotEmpty ? entry.lines.first : entry.title,
    );
    final lower = matchLine.toLowerCase();
    final idx = lower.indexOf(query);
    if (idx == -1 || matchLine.length <= 140) {
      return matchLine;
    }
    final start = (idx - 30).clamp(0, matchLine.length).toInt();
    final end = (idx + query.length + 30).clamp(0, matchLine.length).toInt();
    final prefix = start > 0 ? '…' : '';
    final suffix = end < matchLine.length ? '…' : '';
    return '$prefix${matchLine.substring(start, end)}$suffix';
  }

  bool _isTabbedSection(String id) =>
      id == 'arrival_steps' ||
      id == 'housing' ||
      id == 'regional_and_extension' ||
      id == 'transport' ||
      id == 'money_taxes';
}

class _SearchEntry {
  final String sectionId;
  final String pageId;
  final String title;
  final String subtitle;
  final String body;
  final int? tabIndex;
  final List<String> lines;

  _SearchEntry({
    required this.sectionId,
    required this.pageId,
    required this.title,
    required this.subtitle,
    required this.body,
    required this.lines,
    this.tabIndex,
  });

  String get titleLower => title.toLowerCase();
  String get subtitleLower => subtitle.toLowerCase();
  String get bodyLower => body.toLowerCase();
}
