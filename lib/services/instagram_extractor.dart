import 'package:flutter/foundation.dart';

import 'contact_html_fetcher.dart';

class InstagramExtractor {
  static const bool _verboseLogs = false;

  void _log(String msg) {
    if (_verboseLogs) debugPrint(msg);
  }

  Future<Map<String, dynamic>?> find({
    required String baseUrl,
    required String businessName,
  }) async {
    final baseUri = Uri.tryParse(baseUrl);
    if (baseUri != null && baseUri.host.toLowerCase().contains('instagram.')) {
      return _isValidInstagramProfile(baseUrl)
          ? {'link': _clean(baseUrl), 'score': 100}
          : null;
    }

    final tried = <String>{};
    final found = <String>{};
    final cleanedBase = _cleanBaseUrl(baseUrl);

    Future<void> checkUrl(String url) async {
      if (!tried.add(url)) return;
      final html = await ContactHtmlFetcher.fetch(url);
      if (html == null || html.isEmpty) return;
      found.addAll(_extractInstagramLinks(html));
    }

    await checkUrl(cleanedBase);

    if (found.isEmpty) {
      for (final path in const [
        'about',
        'about-us',
        'contact',
        'contact-us',
        'connect',
        'social',
      ]) {
        await checkUrl(_combineUrl(cleanedBase, path));
        if (found.isNotEmpty) break;
      }
    }

    if (found.isEmpty) {
      for (final url in await _discoverRelevantSitemapUrls(cleanedBase)) {
        await checkUrl(url);
        if (found.isNotEmpty) break;
      }
    }

    final best = _selectBest(found, businessName);
    if (best == null) {
      _log('⚠️ No valid Instagram link for $baseUrl');
      return null;
    }
    return {'link': best, 'score': 100};
  }

  Future<List<String>> _discoverRelevantSitemapUrls(String baseUrl) async {
    final base = Uri.tryParse(baseUrl);
    if (base == null || base.host.isEmpty) return const <String>[];
    final sitemapUrls = <String>{
      _combineBasePath(base, '/sitemap.xml'),
      _combineBasePath(base, '/sitemap_index.xml'),
    };
    final found = <String, int>{};
    for (final sitemapUrl in sitemapUrls) {
      final xml = await ContactHtmlFetcher.fetch(sitemapUrl);
      if (xml == null || xml.isEmpty) continue;
      for (final match in RegExp(
        r'<loc>\s*([^<]+)\s*</loc>',
        caseSensitive: false,
      ).allMatches(xml)) {
        final raw = match.group(1)?.trim();
        if (raw == null || raw.isEmpty) continue;
        if (raw.toLowerCase().endsWith('.xml')) {
          final nested = await ContactHtmlFetcher.fetch(raw);
          if (nested == null || nested.isEmpty) continue;
          for (final nestedMatch in RegExp(
            r'<loc>\s*([^<]+)\s*</loc>',
            caseSensitive: false,
          ).allMatches(nested)) {
            _addRelevantSitemapCandidate(base, nestedMatch.group(1), found);
          }
          continue;
        }
        _addRelevantSitemapCandidate(base, raw, found);
      }
    }
    final sorted = found.entries.toList()
      ..sort((a, b) {
        final byScore = b.value.compareTo(a.value);
        if (byScore != 0) return byScore;
        return a.key.length.compareTo(b.key.length);
      });
    return sorted.map((entry) => entry.key).take(6).toList(growable: false);
  }

  void _addRelevantSitemapCandidate(
    Uri base,
    String? raw,
    Map<String, int> found,
  ) {
    if (raw == null || raw.trim().isEmpty) return;
    final uri = Uri.tryParse(raw.trim());
    if (uri == null) return;
    final resolved = uri.hasScheme ? uri : base.resolveUri(uri);
    if (resolved.host.toLowerCase().replaceFirst('www.', '') !=
        base.host.toLowerCase().replaceFirst('www.', '')) {
      return;
    }
    final url = resolved.replace(fragment: '', query: '').toString();
    final score = _scoreRelevantSitemapUrl(url);
    if (score <= 0) return;
    final previous = found[url];
    if (previous == null || score > previous) found[url] = score;
  }

  int _scoreRelevantSitemapUrl(String url) {
    final lower = url.toLowerCase();
    var score = 0;
    const strong = ['contact', 'about', 'connect', 'social', 'visit'];
    const medium = ['team', 'location', 'venue', 'events', 'functions'];
    for (final keyword in strong) {
      if (lower.contains(keyword)) score += 30;
    }
    for (final keyword in medium) {
      if (lower.contains(keyword)) score += 10;
    }
    if (lower.contains('/blog') ||
        lower.contains('/news') ||
        lower.contains('/privacy') ||
        lower.contains('/menu')) {
      score -= 30;
    }
    return score;
  }

  String _combineBasePath(Uri base, String path) {
    return Uri(
      scheme: base.scheme,
      host: base.host,
      port: base.hasPort ? base.port : null,
      path: path,
    ).toString();
  }

  Set<String> _extractInstagramLinks(String html) {
    final links = <String>{};
    final normalizedHtml = _normalizeHtmlForSocialExtraction(html);
    final patterns = [
      RegExp(
        r'href\s*=\s*"(https?:\/\/(?:www\.)?instagram\.com\/[^<>\s"]+)"',
        caseSensitive: false,
      ),
      RegExp(
        r"href\s*=\s*'(https?:\/\/(?:www\.)?instagram\.com\/[^<>\s']+)'",
        caseSensitive: false,
      ),
      RegExp(
        r'content\s*=\s*"(https?:\/\/(?:www\.)?instagram\.com\/[^<>\s"]+)"',
        caseSensitive: false,
      ),
      RegExp(
        r'''(https?:\/\/(?:www\.)?instagram\.com\/[^\s<>"']+)''',
        caseSensitive: false,
      ),
    ];

    for (final pattern in patterns) {
      for (final match in pattern.allMatches(normalizedHtml)) {
        final raw = match.group(1)?.trim();
        if (raw == null) continue;
        final clean = _clean(raw);
        if (_isValidInstagramProfile(clean)) links.add(clean);
      }
    }
    return links;
  }

  String _normalizeHtmlForSocialExtraction(String html) => html
      .replaceAll(r'\/', '/')
      .replaceAll(r'\u002f', '/')
      .replaceAll(r'\u002F', '/')
      .replaceAll('&amp;', '&')
      .replaceAll('&#x2F;', '/')
      .replaceAll('&#47;', '/');

  String? _selectBest(Set<String> found, String businessName) {
    final scored = <Map<String, dynamic>>[];
    for (final link in found) {
      final uri = Uri.tryParse(link);
      if (uri == null || !_isValidInstagramProfile(link)) continue;
      final score = _scoreInstagramLink(uri, businessName);
      if (score < 35) continue;
      scored.add({'url': link, 'score': score, 'pathLen': uri.path.length});
    }
    if (scored.isEmpty) return null;
    scored.sort((a, b) {
      final sb = b['score'] as int;
      final sa = a['score'] as int;
      if (sb != sa) return sb.compareTo(sa);
      return (a['pathLen'] as int).compareTo(b['pathLen'] as int);
    });
    return scored.first['url'] as String;
  }

  int _scoreInstagramLink(Uri uri, String businessName) {
    var score = 0;
    final segments = uri.pathSegments
        .where((segment) => segment.trim().isNotEmpty)
        .toList(growable: false);
    if (segments.length == 1) score += 30;

    final normalizedBiz = businessName.toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9]'),
      '',
    );
    final handle = segments.isEmpty
        ? ''
        : segments.first.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    if (normalizedBiz.isNotEmpty && handle.isNotEmpty) {
      if (handle == normalizedBiz) {
        score += 80;
      } else if (handle.contains(normalizedBiz) ||
          normalizedBiz.contains(handle)) {
        score += 50;
      } else {
        score += _businessTokenMatchScore(businessName, handle);
      }
    }
    score -= segments.length * 5;
    return score;
  }

  int _businessTokenMatchScore(String businessName, String handle) {
    final tokens = businessName
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9]+'))
        .where((token) => token.length >= 3)
        .toList(growable: false);
    if (tokens.isEmpty || handle.isEmpty) return 0;
    var score = 0;
    for (final token in tokens) {
      if (handle.contains(token)) score += 25;
    }
    if (score == 0) return 0;
    return score + (tokens.length > 1 ? 10 : 0);
  }

  bool _isValidInstagramProfile(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    final host = uri.host.toLowerCase();
    if (!host.contains('instagram.com')) return false;
    final segments = uri.pathSegments
        .where((segment) => segment.trim().isNotEmpty)
        .toList(growable: false);
    if (segments.length != 1) return false;
    final handle = segments.first.toLowerCase();
    const blocked = {
      'p',
      'reel',
      'reels',
      'stories',
      'explore',
      'accounts',
      'about',
      'developer',
      'legal',
      'privacy',
    };
    if (blocked.contains(handle)) return false;
    if (handle.length < 2 || handle.length > 30) return false;
    return RegExp(r'^[a-z0-9._]+$').hasMatch(handle);
  }

  String _clean(String url) {
    var clean = url.split('?').first.split('#').first;
    while (clean.endsWith('/')) {
      clean = clean.substring(0, clean.length - 1);
    }
    return clean;
  }

  String _cleanBaseUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) return url.split('?').first;
    return '${uri.scheme}://${uri.host}';
  }

  String _combineUrl(String base, String path) {
    if (path.startsWith('http')) return path;
    if (base.endsWith('/')) return '$base$path';
    return '$base/$path';
  }
}
