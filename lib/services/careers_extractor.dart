import 'contact_html_fetcher.dart';

class CareersExtractor {
  /// 🔍 Troba una pàgina de "careers" o "jobs" dins d'un lloc web
  Future<String?> find(String baseUrl) async {
    // Si la web base és una xarxa social, no busquem cap careers page
    final parsedBase = Uri.tryParse(baseUrl);
    if (parsedBase != null) {
      final host = parsedBase.host.toLowerCase();
      if (host.contains('facebook.com') ||
          host.contains('m.facebook.com') ||
          host.contains('fb.com') ||
          host.contains('instagram.com') ||
          host.contains('linkedin.com') ||
          host.contains('twitter.com')) {
        return null;
      }
    }

    // PHASE 0: Prova rutes canòniques directes abans de parsejar HTML
    final baseUri = Uri.tryParse(baseUrl);
    if (baseUri != null) {
      const canonicalPaths = [
        '/careers',
        '/jobs',
        '/work-with-us',
        '/work-for-us',
        '/join-our-team',
        '/join-us',
        '/employment',
        '/vacancies',
        '/hiring',
        '/opportunities',
        '/recruitment',
        '/positions',
      ];

      for (final path in canonicalPaths) {
        final canonical = Uri(
          scheme: baseUri.scheme,
          host: baseUri.host,
          port: baseUri.hasPort ? baseUri.port : null,
          path: path,
        ).toString();

        final htmlCanonical = await _fetchHtml(canonical);
        if (htmlCanonical == null || htmlCanonical.isEmpty) continue;

        final lower = htmlCanonical.toLowerCase();
        const keywords = [
          'career',
          'careers',
          'jobs',
          'vacancies',
          'join our team',
          'join us',
          'employment',
          'hiring',
          'opportunities',
          'recruitment',
          'positions',
          'apply now',
        ];
        if (keywords.any((k) => lower.contains(k))) {
          final uri = Uri.tryParse(canonical);
          if (uri != null && _isGenericFacebookCareers(uri)) {
            continue;
          }
          return canonical;
        }
      }
    }

    // PHASE 1: Lògica existent
    final html = await _fetchHtml(baseUrl);
    if (html == null || html.isEmpty) return null;

    // 1️⃣ Cerca href amb cometes dobles o simples
    final reHrefDouble = RegExp(
      r'href\s*=\s*"([^"]*(?:careers?|jobs?|employment|vacancies|hiring|opportunities|recruitment|positions|join-us|join-our-team|work-with-us|work-for-us|apply)[^"]*)"',
      caseSensitive: false,
    );
    final reHrefSingle = RegExp(
      r"href\s*=\s*'([^']*(?:careers?|jobs?|employment|vacancies|hiring|opportunities|recruitment|positions|join-us|join-our-team|work-with-us|work-for-us|apply)[^']*)'",
      caseSensitive: false,
    );

    final Set<String> candidates = {};

    for (final m in reHrefDouble.allMatches(html)) {
      final link = m.group(1);
      if (link != null && link.isNotEmpty) candidates.add(link);
    }

    for (final m in reHrefSingle.allMatches(html)) {
      final link = m.group(1);
      if (link != null && link.isNotEmpty) candidates.add(link);
    }

    // 2️⃣ Busca text visible rellevant (com “Jobs”, “Careers”)
    final reVisible = RegExp(
      r'>([^<]*(?:careers?|jobs?|employment|vacancies|hiring|opportunities|recruitment|positions|join our team|join us|work with us|work for us|apply now)[^<]*)<',
      caseSensitive: false,
    );
    if (reVisible.hasMatch(html)) {
      candidates.add(baseUrl);
    }

    // 3️⃣ Explora subpàgines típiques per trobar-hi enllaços
    final related = <String>{
      _combineUrl(baseUrl, 'about'),
      _combineUrl(baseUrl, 'contact'),
      _combineUrl(baseUrl, 'team'),
      _combineUrl(baseUrl, 'join'),
    };

    for (final sub in related) {
      final subHtml = await _fetchHtml(sub);
      if (subHtml == null) continue;

      for (final m in reHrefDouble.allMatches(subHtml)) {
        final link = m.group(1);
        if (link != null && link.isNotEmpty) candidates.add(link);
      }
      for (final m in reHrefSingle.allMatches(subHtml)) {
        final link = m.group(1);
        if (link != null && link.isNotEmpty) candidates.add(link);
      }

      if (reVisible.hasMatch(subHtml)) {
        candidates.add(sub);
      }
    }

    if (candidates.isEmpty) {
      candidates.addAll(await _discoverSitemapCareerUrls(baseUrl));
    }

    // 4️⃣ Filtra i valida els enllaços
    var filtered = candidates
        .where((link) => _isValidCareerLink(baseUrl, link))
        .toList();

    if (filtered.isEmpty) {
      candidates.addAll(await _discoverSitemapCareerUrls(baseUrl));
      filtered = candidates
          .where((link) => _isValidCareerLink(baseUrl, link))
          .toList();
    }

    // 5️⃣ Puntuem, ordenem i retornem el millor candidat
    if (filtered.isNotEmpty) {
      final baseHost = Uri.parse(baseUrl).host;

      final scored = filtered.map((raw) {
        final full = raw.startsWith('http') ? raw : _combineUrl(baseUrl, raw);
        Uri? uri;
        try {
          uri = Uri.parse(full);
        } catch (_) {}
        if (uri == null) {
          return {'url': full, 'score': -9999, 'pathLength': full.length};
        }

        final host = uri.host;
        final path = uri.path;
        int score = 0;

        if (host == baseHost) score += 50;
        if (path == '/careers' || path == '/jobs') {
          score += 100;
        } else if (path.endsWith('/careers') || path.endsWith('/jobs')) {
          score += 40;
        }

        final depth = path.split('/').where((p) => p.isNotEmpty).length;
        score -= depth * 5;

        final lowerPath = path.toLowerCase();
        if (lowerPath.contains('/blog/') ||
            lowerPath.contains('/news/') ||
            lowerPath.contains('/dining/') ||
            lowerPath.contains('/menu/')) {
          score -= 10;
        }

        return {'url': full, 'score': score, 'pathLength': path.length};
      }).toList();

      scored.sort((a, b) {
        final scoreB = (b['score'] as int);
        final scoreA = (a['score'] as int);
        if (scoreB != scoreA) return scoreB.compareTo(scoreA);
        final lenA = (a['pathLength'] as int);
        final lenB = (b['pathLength'] as int);
        return lenA.compareTo(lenB);
      });

      final best = scored.first;
      final bestUrl = best['url'] as String;
      final bestHtml = await _fetchHtml(bestUrl);
      if (bestHtml == null || _looksLike404(bestHtml)) return null;
      return bestUrl;
    }

    return null;
  }

  // ───────────────────────── helpers ─────────────────────────

  Future<String?> _fetchHtml(String url) async {
    return ContactHtmlFetcher.fetch(url);
  }

  bool _isValidCareerLink(String baseUrl, String link) {
    try {
      final normalized = link.startsWith('http')
          ? link
          : _combineUrl(baseUrl, link);

      final uri = Uri.parse(normalized);
      final ll = normalized.toLowerCase();
      final host = uri.host;
      final path = uri.path;

      final isGenericFacebookCareers = _isGenericFacebookCareers(uri);
      final isSocial =
          host.contains('facebook.com') ||
          host.contains('m.facebook.com') ||
          host.contains('fb.com') ||
          host.contains('instagram.com') ||
          host.contains('instagr.am') ||
          host.contains('linkedin.com') ||
          host.contains('twitter.com') ||
          host.contains('tiktok.com');
      final invalidExt =
          ll.endsWith('.pdf') ||
          ll.endsWith('.doc') ||
          ll.endsWith('.docx') ||
          ll.endsWith('.zip') ||
          ll.endsWith('.jpg') ||
          ll.endsWith('.png') ||
          ll.endsWith('.jpeg');
      final tooLong = ll.length > 140 || ll.split(RegExp(r'[?&]')).length > 6;
      final badPath =
          path.contains('/accommodation/') ||
          path.contains('/destination/') ||
          path.contains('/contact/') ||
          path.contains('/team/') ||
          path.contains('/menu/');
      final validKeyword =
          path.contains('/careers') ||
          path.contains('/jobs') ||
          path.contains('/work-with-us') ||
          path.contains('/work-for-us') ||
          path.contains('/join-our-team') ||
          path.contains('/join-us') ||
          path.contains('/employment') ||
          path.contains('/vacancies') ||
          path.contains('/hiring') ||
          path.contains('/opportunities') ||
          path.contains('/recruitment') ||
          path.contains('/positions') ||
          path.contains('/apply') ||
          path.contains('/team-member') ||
          path.contains('/work-at') ||
          path.contains('/people-and-culture');

      return validKeyword &&
          !isSocial &&
          !isGenericFacebookCareers &&
          !invalidExt &&
          !tooLong &&
          !badPath &&
          host.isNotEmpty &&
          path.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  bool _looksLike404(String html) {
    final lower = html.toLowerCase();
    return lower.contains('404 not found') ||
        lower.contains('page not found') ||
        (lower.contains('not found') && lower.contains('error'));
  }

  bool _isGenericFacebookCareers(Uri uri) {
    final host = uri.host.toLowerCase();
    if (!(host.contains('facebook.com') || host.contains('fb.com'))) {
      return false;
    }
    final path = uri.path.toLowerCase();
    return path == '/careers' ||
        path == '/careers/' ||
        path == '/jobs' ||
        path == '/jobs/';
  }

  Future<List<String>> _discoverSitemapCareerUrls(String baseUrl) async {
    final base = Uri.tryParse(baseUrl);
    if (base == null || base.host.isEmpty) return const <String>[];
    final sitemapUrls = <String>{
      _combineBasePath(base, '/sitemap.xml'),
      _combineBasePath(base, '/sitemap_index.xml'),
    };
    final found = <String, int>{};

    for (final sitemapUrl in sitemapUrls) {
      final xml = await _fetchHtml(sitemapUrl);
      if (xml == null || xml.isEmpty) continue;
      for (final match in RegExp(
        r'<loc>\s*([^<]+)\s*</loc>',
        caseSensitive: false,
      ).allMatches(xml)) {
        final raw = match.group(1)?.trim();
        if (raw == null || raw.isEmpty) continue;
        if (raw.toLowerCase().endsWith('.xml')) {
          final nested = await _fetchHtml(raw);
          if (nested == null || nested.isEmpty) continue;
          for (final nestedMatch in RegExp(
            r'<loc>\s*([^<]+)\s*</loc>',
            caseSensitive: false,
          ).allMatches(nested)) {
            _addSitemapCareerCandidate(base, nestedMatch.group(1), found);
          }
          continue;
        }
        _addSitemapCareerCandidate(base, raw, found);
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

  void _addSitemapCareerCandidate(
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
    final score = _scoreCareerUrl(url);
    if (score <= 0) return;
    final previous = found[url];
    if (previous == null || score > previous) found[url] = score;
  }

  int _scoreCareerUrl(String url) {
    final lower = url.toLowerCase();
    var score = 0;
    const strong = [
      'careers',
      'jobs',
      'work-with-us',
      'work-for-us',
      'join-our-team',
      'join-us',
      'employment',
      'vacancies',
      'hiring',
      'opportunities',
      'recruitment',
      'positions',
      'apply',
      'team-member',
      'work-at',
      'people-and-culture',
    ];
    for (final keyword in strong) {
      if (lower.contains(keyword)) score += 30;
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

  String _combineUrl(String base, String path) {
    if (path.startsWith('http')) return path;
    if (base.endsWith('/') && path.startsWith('/')) {
      return base + path.substring(1);
    } else if (!base.endsWith('/') && !path.startsWith('/')) {
      return '$base/$path';
    } else {
      return base + path;
    }
  }
}
