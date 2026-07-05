import 'package:flutter/foundation.dart';

import 'contact_html_fetcher.dart';

class FacebookExtractor {
  static const bool _verboseLogs = false;

  void _log(String msg) {
    if (_verboseLogs) {
      // ignore: avoid_print
      debugPrint(msg);
    }
  }

  Future<Map<String, dynamic>?> find({
    required String baseUrl,
    required String businessName,
    required String address,
    String? phone,
  }) async {
    final tried = <String>{};
    final found = <String>{};
    final cleanedBase = _cleanBaseUrl(baseUrl);

    final baseUri = Uri.tryParse(baseUrl);
    if (baseUri != null &&
        (baseUri.host.contains('facebook.com') ||
            baseUri.host.contains('fb.com') ||
            baseUri.host.contains('m.facebook.com'))) {
      _log('⚠️ Base website is Facebook; skipping page detection.');
      return null;
    }

    // 🔹 Funció per combinar camins de forma segura
    String safeCombine(String base, String path) {
      if (path.startsWith('http') || path.startsWith(base)) return path;
      if (path.isEmpty || path == '/') return base;
      return base.endsWith('/') ? '$base$path' : '$base/$path';
    }

    // 🔹 Primer prova la pàgina principal, després subpàgines
    Future<void> checkUrl(String url) async {
      if (!tried.add(url)) return;
      final html = await _fetchHtmlUnsafe(url);
      if (html == null || html.isEmpty) return;
      final matches = _extractFacebookLinks(html);
      if (matches.isNotEmpty) found.addAll(matches);
    }

    await checkUrl(cleanedBase);

    if (found.isEmpty) {
      final subpages = <String>{
        safeCombine(cleanedBase, 'about'),
        safeCombine(cleanedBase, 'about-us'),
        safeCombine(cleanedBase, 'contact'),
        safeCombine(cleanedBase, 'contact-us'),
        safeCombine(cleanedBase, 'connect'),
        safeCombine(cleanedBase, 'social'),
        safeCombine(cleanedBase, 'footer'),
      };

      for (final url in subpages) {
        await checkUrl(url);
        if (found.isNotEmpty) break;
      }
    }

    if (found.isEmpty) {
      for (final url in await _discoverRelevantSitemapUrls(cleanedBase)) {
        await checkUrl(url);
        if (found.isNotEmpty) break;
      }
    }

    if (found.isEmpty) {
      _log('⚠️ Cap Facebook trobat per $baseUrl');
      return null;
    }

    // 🔹 Selecciona el millor link
    final best = _selectBest(found, businessName);
    if (best == null) {
      _log('⚠️ No valid Facebook link for $baseUrl');
      return null;
    }
    _log('✅ Facebook trobat: $best');
    return {'link': best, 'score': 100};
  }

  // ---------------- Helpers ----------------

  Future<String?> _fetchHtmlUnsafe(String url) async {
    final html = await ContactHtmlFetcher.fetch(url);
    if (html == null) _log('⚠️ Error descarregant $url');
    return html;
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
      final xml = await _fetchHtmlUnsafe(sitemapUrl);
      if (xml == null || xml.isEmpty) continue;
      for (final match in RegExp(
        r'<loc>\s*([^<]+)\s*</loc>',
        caseSensitive: false,
      ).allMatches(xml)) {
        final raw = match.group(1)?.trim();
        if (raw == null || raw.isEmpty) continue;
        if (raw.toLowerCase().endsWith('.xml')) {
          final nested = await _fetchHtmlUnsafe(raw);
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

  Set<String> _extractFacebookLinks(String html) {
    final links = <String>{};
    final normalizedHtml = _normalizeHtmlForSocialExtraction(html);

    final patterns = [
      // href="https://facebook.com/..."
      RegExp(
        r'href\s*=\s*"(https?:\/\/(?:www\.|m\.|mbasic\.|business\.)?(?:facebook|fb)\.com\/[^<>\s"]+)"',
        caseSensitive: false,
      ),
      // href='https://facebook.com/...'
      RegExp(
        r"href\s*=\s*'(https?:\/\/(?:www\.|m\.|mbasic\.|business\.)?(?:facebook|fb)\.com\/[^<>\s']+)'",
        caseSensitive: false,
      ),

      // data-href="https://facebook.com/..."
      RegExp(
        r'data-href\s*=\s*"(https?:\/\/(?:www\.|m\.|mbasic\.|business\.)?(?:facebook|fb)\.com\/[^<>\s"]+)"',
        caseSensitive: false,
      ),
      // data-href='https://facebook.com/...'
      RegExp(
        r"data-href\s*=\s*'(https?:\/\/(?:www\.|m\.|mbasic\.|business\.)?(?:facebook|fb)\.com\/[^<>\s']+)'",
        caseSensitive: false,
      ),

      // content="https://facebook.com/..."
      RegExp(
        r'content\s*=\s*"(https?:\/\/(?:www\.|m\.|mbasic\.|business\.)?(?:facebook|fb)\.com\/[^<>\s"]+)"',
        caseSensitive: false,
      ),
      // content='https://facebook.com/...'
      RegExp(
        r"content\s*=\s*'(https?:\/\/(?:www\.|m\.|mbasic\.|business\.)?(?:facebook|fb)\.com\/[^<>\s']+)'",
        caseSensitive: false,
      ),

      // Fallback — qualsevol URL de Facebook
      RegExp(
        r'''(https?:\/\/(?:www\.|m\.|mbasic\.|business\.)?(?:facebook|fb)\.com\/[^\s<>"']+)''',
        caseSensitive: false,
      ),
    ];

    for (final reg in patterns) {
      for (final match in reg.allMatches(normalizedHtml)) {
        final url = match.group(1)?.trim();
        if (url != null && !_isBad(url) && _isValidFacebookPage(url)) {
          links.add(_clean(url));
        }
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

  bool _isBad(String url) {
    final l = url.toLowerCase();
    return l.contains('plugin') ||
        l.contains('share.php') ||
        l.contains('dialog') ||
        l.contains('pixel') ||
        l.contains('login') ||
        l.contains('/2008/fbml') ||
        l.contains('/search/') ||
        l.contains('/photo') ||
        l.contains('/watch') ||
        l.contains('/tr');
  }

  String _clean(String url) {
    var u = url.split('?').first;
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    return u;
  }

  bool _isValidFacebookPage(String url) {
    final uri = _parse(url);
    if (uri == null) return false;

    final host = uri.host.toLowerCase();
    if (!host.contains('facebook.com') && !host.contains('fb.com')) {
      return false;
    }

    if (uri.path.isEmpty || uri.path == '/') {
      return false;
    }

    final segments = uri.pathSegments
        .where((s) => s.trim().isNotEmpty)
        .toList();
    if (segments.isEmpty) return false;

    const badSegments = {
      '2008',
      'fbml',
      'tr',
      'photo',
      'photos',
      'watch',
      'search',
      'top',
      'sharer.php',
      'sharer',
      'plugins',
      'dialog',
      'events',
      'help',
      'login',
      'logout',
      'l.php',
      'policy',
      'privacy',
      'terms',
      'marketplace',
      'groups',
      'hashtag',
      'permalink.php',
      'story.php',
      'reel',
      'reels',
    };
    final lowerSegments = segments
        .map((segment) => segment.toLowerCase())
        .toList();
    if (lowerSegments.any(badSegments.contains)) return false;

    const blockedPageSlugs = {
      'wix',
      'bitly',
      'exploreuluru',
      'localsearchau',
      'wordpresscom',
      'wordpress',
      'meta',
      'facebook',
      'facebookapp',
      'developers',
      'business',
      'pages',
    };
    final cleanedSegments = lowerSegments
        .map((segment) => segment.replaceAll(RegExp(r'[^a-z0-9]'), ''))
        .where((segment) => segment.isNotEmpty)
        .toList(growable: false);
    if (cleanedSegments.any(blockedPageSlugs.contains)) return false;

    if (segments.length >= 2 &&
        segments[0].toLowerCase() == 'pages' &&
        segments[1].toLowerCase() == 'category') {
      return false;
    }

    if (uri.path == '/profile.php') {
      final id = uri.queryParameters['id'];
      return id != null &&
          id.trim().isNotEmpty &&
          RegExp(r'^\d+$').hasMatch(id);
    }

    // slug-based paths
    for (final seg in segments) {
      final trimmed = seg.trim();
      if (trimmed.length >= 3 && !trimmed.endsWith('.php')) {
        return true;
      }
    }

    return false;
  }

  Uri? _parse(String url) {
    try {
      return Uri.parse(url);
    } catch (_) {
      return null;
    }
  }

  String _cleanBaseUrl(String url) {
    try {
      final uri = Uri.parse(url);
      return '${uri.scheme}://${uri.host}';
    } catch (_) {
      return url.split('?').first;
    }
  }

  String? _selectBest(Set<String> found, String businessName) {
    final scored = <Map<String, dynamic>>[];
    for (final link in found) {
      final uri = _parse(link);
      if (uri == null) continue;
      if (!_isValidFacebookPage(link)) continue;
      final score = _scoreFacebookLink(uri, businessName);
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

  int _scoreFacebookLink(Uri uri, String businessName) {
    int score = 0;
    final host = uri.host.toLowerCase();
    if (host.startsWith('www.')) score += 10;

    final pathSegments = uri.pathSegments
        .where((s) => s.trim().isNotEmpty)
        .toList();

    // profile.php with id
    if (uri.path == '/profile.php' &&
        uri.queryParameters['id'] != null &&
        uri.queryParameters['id']!.trim().isNotEmpty) {
      score += 40;
    }

    // business name match
    final normalizedBiz = businessName.toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9]'),
      '',
    );
    final candidateSlug = _extractSlugFromPath(pathSegments);
    if (normalizedBiz.isNotEmpty && candidateSlug.isNotEmpty) {
      if (candidateSlug == normalizedBiz) {
        score += 90;
      } else if (candidateSlug.contains(normalizedBiz) ||
          normalizedBiz.contains(candidateSlug)) {
        score += 65;
      } else {
        final tokenScore = _businessTokenMatchScore(
          businessName,
          candidateSlug,
        );
        score += tokenScore;
      }
    }

    // depth penalty
    score -= pathSegments.length * 5;

    // query penalty if many params
    final queryCount = uri.queryParameters.length;
    if (queryCount > 3) score -= (queryCount - 3) * 5;

    return score;
  }

  int _businessTokenMatchScore(String businessName, String candidateSlug) {
    final tokens = businessName
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9]+'))
        .where((token) => token.length >= 3)
        .toList(growable: false);
    if (tokens.isEmpty || candidateSlug.isEmpty) return 0;
    var score = 0;
    for (final token in tokens) {
      if (candidateSlug.contains(token)) score += 25;
    }
    if (score == 0) return 0;
    return score + (tokens.length > 1 ? 10 : 0);
  }

  String _extractSlugFromPath(List<String> segments) {
    if (segments.isEmpty) return '';
    if (segments.first.toLowerCase() == 'pages' && segments.length >= 2) {
      return segments[1].toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    }
    final last = segments.last.toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9]'),
      '',
    );
    return last;
  }
}
