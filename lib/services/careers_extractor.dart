import 'package:http/http.dart' as http;

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
      r'href\s*=\s*"([^"]*(?:careers?|jobs?)[^"]*)"',
      caseSensitive: false,
    );
    final reHrefSingle = RegExp(
      r"href\s*=\s*'([^']*(?:careers?|jobs?)[^']*)'",
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
      r'>([^<]*(?:careers?|jobs?)[^<]*)<',
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

    // 4️⃣ Filtra i valida els enllaços
    final filtered = candidates.where((link) {
      try {
        // Normalitza l'enllaç
        final normalized = link.startsWith('http')
            ? link
            : _combineUrl(baseUrl, link);

        final uri = Uri.parse(normalized);
        final ll = normalized.toLowerCase();
        final host = uri.host;
        final path = uri.path;

        final isGenericFacebookCareers = _isGenericFacebookCareers(uri);

        // ❌ Filtra dominis socials (Facebook mai s'accepta com a careers)
        final isSocial =
            host.contains('facebook.com') ||
            host.contains('m.facebook.com') ||
            host.contains('fb.com') ||
            host.contains('instagram.com') ||
            host.contains('instagr.am') ||
            host.contains('linkedin.com') ||
            host.contains('twitter.com') ||
            host.contains('tiktok.com');

        // ❌ Extensions no vàlides
        final invalidExt =
            ll.endsWith('.pdf') ||
            ll.endsWith('.doc') ||
            ll.endsWith('.docx') ||
            ll.endsWith('.zip') ||
            ll.endsWith('.jpg') ||
            ll.endsWith('.png') ||
            ll.endsWith('.jpeg');

        // ❌ Evita rutes llargues o amb massa paràmetres
        final tooLong = ll.length > 120 || ll.split(RegExp(r'[?&]')).length > 5;

        // ❌ Pàgines internes o seccions no rellevants
        final badPath =
            path.contains('/accommodation/') ||
            path.contains('/destination/') ||
            path.contains('/contact/') ||
            path.contains('/team/') ||
            path.contains('/menu/');

        // ✅ Només accepta si el path conté “/careers” o “/jobs”
        final validKeyword =
            path.contains('/careers') || path.contains('/jobs');

        // ✅ Ha de complir totes les condicions
        return validKeyword &&
            !isSocial &&
            !isGenericFacebookCareers &&
            !invalidExt &&
            !tooLong &&
            !badPath &&
            host.isNotEmpty &&
            path.isNotEmpty;
      } catch (e) {
        return false;
      }
    }).toList();

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
    try {
      final resp = await http.get(Uri.parse(url));
      if (resp.statusCode == 200) return resp.body;
    } catch (_) {
      return null;
    }
    return null;
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
