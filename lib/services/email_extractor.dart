import 'package:flutter/foundation.dart';

import 'contact_html_fetcher.dart';

class EmailVerificationResult {
  const EmailVerificationResult({
    required this.email,
    required this.score,
    required this.origin,
  });

  final String email;
  final int score;
  final String origin;
}

class EmailExtractor {
  String? lastFacebookUrl;
  static const bool _debugEmailFilterLogs = false;
  static const int _maxPagesToCheck = 18;
  static const int _maxPriorityPagesToCheck = 12;

  void _logEmail(String msg) {
    if (!_debugEmailFilterLogs) return;
    // ignore: avoid_print
    debugPrint(msg);
  }

  Future<String?> extract(
    String baseUrl, {
    String? businessName,
    String? locationName,
  }) async {
    final result = await extractVerified(
      baseUrl,
      businessName: businessName,
      locationName: locationName,
    );
    return result?.email;
  }

  Future<EmailVerificationResult?> extractVerified(
    String baseUrl, {
    String? businessName,
    String? locationName,
  }) async {
    final tried = <String>{};
    final found = <EmailVerificationResult>[];
    final cleanedBase = _cleanBaseUrl(baseUrl);

    // 🔹 Funció segura per combinar camins sense duplicar el domini
    String safeCombine(String base, String path) {
      // Si el path ja comença amb http o amb el domini complet, el retorna tal qual
      if (path.startsWith('http') || path.startsWith(base)) return path;

      // Si és un path buit o "/", retorna simplement el domini base
      if (path.isEmpty || path == '/') return base;

      // Afegeix "/" només si cal
      return base.endsWith('/') ? '$base$path' : '$base/$path';
    }

    // 🔹 Llista d’URLs a comprovar, en ordre de prioritat.
    final priorityUrls = <String>[
      cleanedBase,
      safeCombine(cleanedBase, 'contact'),
      safeCombine(cleanedBase, 'contact-us'),
      safeCombine(cleanedBase, 'about'),
      safeCombine(cleanedBase, 'about-us'),
      safeCombine(cleanedBase, 'work-with-us'),
      safeCombine(cleanedBase, 'join-us'),
      safeCombine(cleanedBase, 'careers'),
    ];

    final homepageHtml = await _fetchHtmlUnsafe(cleanedBase);
    if (homepageHtml != null && homepageHtml.isNotEmpty) {
      priorityUrls.addAll(
        _extractRelevantInternalUrls(cleanedBase, homepageHtml),
      );
    }

    var checkedPages = 0;
    Future<void> checkUrls(
      Iterable<String> urls, {
      required int maxPages,
    }) async {
      for (final url in urls) {
        if (!tried.add(url)) continue;
        if (checkedPages >= maxPages) break;
        checkedPages++;

        final html = await _fetchHtmlUnsafe(url);
        if (html == null || html.isEmpty) continue;

        final candidates = _extractEmailCandidates(html);

        for (final email in candidates) {
          final verified = verifyCandidate(
            email,
            website: baseUrl,
            businessName: businessName,
            locationName: locationName,
            originUrl: url,
          );
          if (verified == null) {
            _logEmail('❌ Filtered: $email (invalid)');
            continue;
          }
          found.add(verified);
        }
      }
    }

    await checkUrls(priorityUrls, maxPages: _maxPriorityPagesToCheck);
    if (checkedPages < _maxPagesToCheck) {
      await checkUrls(
        await _discoverRelevantSitemapUrls(cleanedBase),
        maxPages: _maxPagesToCheck,
      );
    }

    if (found.isEmpty) {
      _logEmail('⚠️ No valid email found for $baseUrl');
      return null;
    }

    found.sort((a, b) => b.score.compareTo(a.score));

    // debugPrint('📧 Candidats vàlids trobats per $baseUrl:');
    // for (final e in found) {
    //   debugPrint('   • ${e['email']} → ${e['score']}%  (origen: ${e['origin']})');
    // }

    final best = found.first;
    if (best.score < 40) {
      _logEmail('⚠️ No email with enough confidence.');
      return null;
    }

    _logEmail('✅ Millor correu: ${best.email} (${best.score}%)');
    return best;
  }

  EmailVerificationResult? verifyCandidate(
    String email, {
    required String website,
    String? businessName,
    String? locationName,
    String? originUrl,
  }) {
    final normalizedEmail = email.trim();
    if (normalizedEmail.isEmpty) return null;
    final domain = _domain(website);
    if (!_isValidEmail(normalizedEmail, domain, originUrl: originUrl)) {
      return null;
    }

    final score = _scoreEmail(
      normalizedEmail,
      businessName ?? '',
      domain,
      originUrl: originUrl,
      locationName: locationName,
    );
    if (score < 40) return null;
    return EmailVerificationResult(
      email: normalizedEmail,
      score: score,
      origin: originUrl ?? 'existing',
    );
  }

  // ---------------- HTTP amb SSL relaxat ----------------
  Future<String?> _fetchHtmlUnsafe(String url) async {
    final html = await ContactHtmlFetcher.fetch(url);
    if (html == null) _logEmail('⚠️ Error descarregant $url');
    return html;
  }

  // ---------------- Extractors ----------------
  final _emailRegex = RegExp(
    r'[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}',
  );

  Set<String> _emailsFromMailto(String html) => RegExp(
    r'mailto:([a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,})',
  ).allMatches(html).map((m) => m.group(1)!).toSet();

  Set<String> _emailsDirect(String html) =>
      _emailRegex.allMatches(html).map((m) => m.group(0)!).toSet();

  Set<String> _emailsFromJsonLd(String html) => RegExp(
    r'"email"\s*:\s*"([^"]+)"',
  ).allMatches(html).map((m) => m.group(1)!).toSet();

  Set<String> _extractEmailCandidates(String html) {
    final normalized = _normalizeHtmlForContactExtraction(html);
    return {
      ..._emailsFromMailto(normalized),
      ..._emailsDirect(normalized),
      ..._emailsFromJsonLd(normalized),
      ..._emailsDirect(_deobfuscate(normalized)),
    };
  }

  String _normalizeHtmlForContactExtraction(String html) => html
      .replaceAll(r'\/', '/')
      .replaceAll(r'\u0040', '@')
      .replaceAll(r'\u004f', 'O')
      .replaceAll(r'\u002e', '.')
      .replaceAll(r'\u002E', '.')
      .replaceAll('&commat;', '@')
      .replaceAll('&#64;', '@')
      .replaceAll('&#x40;', '@')
      .replaceAll('&#X40;', '@')
      .replaceAll('&#46;', '.')
      .replaceAll('&#x2e;', '.')
      .replaceAll('&#x2E;', '.')
      .replaceAll('&period;', '.')
      .replaceAll('&dot;', '.');

  String _deobfuscate(String html) {
    var text = _stripHtml(html);
    text = text
        .replaceAll(
          RegExp(
            r'\s*(?:\[|\(|\{)\s*at\s*(?:\]|\)|\})\s*',
            caseSensitive: false,
          ),
          '@',
        )
        .replaceAll(RegExp(r'\s+(?:at)\s+', caseSensitive: false), '@')
        .replaceAll(
          RegExp(
            r'\s*(?:\[|\(|\{)\s*dot\s*(?:\]|\)|\})\s*',
            caseSensitive: false,
          ),
          '.',
        )
        .replaceAll(RegExp(r'\s+(?:dot)\s+', caseSensitive: false), '.')
        .replaceAll(RegExp(r'\s+@\s+'), '@')
        .replaceAll(RegExp(r'\s+\.\s+'), '.');
    return text;
  }

  String _stripHtml(String html) {
    return html
        .replaceAll(
          RegExp(
            r'<script\b[^>]*>.*?</script>',
            caseSensitive: false,
            dotAll: true,
          ),
          ' ',
        )
        .replaceAll(
          RegExp(
            r'<style\b[^>]*>.*?</style>',
            caseSensitive: false,
            dotAll: true,
          ),
          ' ',
        )
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .replaceAll('&nbsp;', ' ');
  }

  List<String> _extractRelevantInternalUrls(String baseUrl, String html) {
    final base = Uri.tryParse(baseUrl);
    if (base == null || base.host.isEmpty) return const <String>[];
    final candidates = <String, int>{};
    final normalized = _normalizeHtmlForContactExtraction(html);
    final hrefRegex = RegExp(
      r'''href\s*=\s*["']?([^"'\s>]+)''',
      caseSensitive: false,
    );
    for (final match in hrefRegex.allMatches(normalized)) {
      final raw = match.group(1);
      if (raw == null || raw.trim().isEmpty) continue;
      final resolved = _resolveInternalUrl(base, raw);
      if (resolved == null) continue;
      final score = _scoreRelevantUrl(resolved);
      if (score <= 0) continue;
      final previous = candidates[resolved];
      if (previous == null || score > previous) {
        candidates[resolved] = score;
      }
    }

    final sorted = candidates.entries.toList()
      ..sort((a, b) {
        final byScore = b.value.compareTo(a.value);
        if (byScore != 0) return byScore;
        return a.key.length.compareTo(b.key.length);
      });
    return sorted.map((entry) => entry.key).take(8).toList(growable: false);
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
    final resolved = _resolveInternalUrl(base, raw.trim());
    if (resolved == null) return;
    final score = _scoreRelevantUrl(resolved);
    if (score <= 0) return;
    final previous = found[resolved];
    if (previous == null || score > previous) found[resolved] = score;
  }

  String? _resolveInternalUrl(Uri base, String raw) {
    if (raw.startsWith('mailto:') ||
        raw.startsWith('tel:') ||
        raw.startsWith('#') ||
        raw.startsWith('javascript:')) {
      return null;
    }
    final uri = Uri.tryParse(raw);
    final resolved = uri == null
        ? null
        : (uri.hasScheme ? uri : base.resolveUri(uri));
    if (resolved == null) return null;
    if (resolved.host.toLowerCase().replaceFirst('www.', '') !=
        base.host.toLowerCase().replaceFirst('www.', '')) {
      return null;
    }
    final lower = resolved.toString().toLowerCase();
    if (RegExp(
      r'\.(jpg|jpeg|png|gif|webp|svg|pdf|zip|css|js)(\?|$)',
    ).hasMatch(lower)) {
      return null;
    }
    return resolved.replace(fragment: '', query: '').toString();
  }

  int _scoreRelevantUrl(String url) {
    final lower = url.toLowerCase();
    var score = 0;
    const strong = [
      'contact',
      'contact-us',
      'enquiries',
      'reservation',
      'booking',
      'bookings',
      'functions',
      'events',
      'careers',
      'jobs',
      'work-with-us',
      'join-us',
      'join-our-team',
    ];
    const medium = ['about', 'team', 'visit', 'location', 'venue'];
    for (final keyword in strong) {
      if (lower.contains(keyword)) score += 30;
    }
    for (final keyword in medium) {
      if (lower.contains(keyword)) score += 10;
    }
    if (lower.contains('/blog') ||
        lower.contains('/news') ||
        lower.contains('/privacy') ||
        lower.contains('/terms')) {
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

  // ---------------- Helpers ----------------
  String _domain(String url) {
    try {
      return Uri.parse(url).host.replaceAll('www.', '');
    } catch (_) {
      return '';
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

  // ---------------- Scoring ----------------
  int _scoreEmail(
    String email,
    String businessName,
    String domain, {
    String? originUrl,
    String? locationName,
  }) {
    int score = 0;
    final e = email.toLowerCase();
    final origin = (originUrl ?? '').toLowerCase();
    final coreDomain = domain.split('.').first.toLowerCase();

    // 🔹 Domini propi
    if (e.contains(coreDomain)) score += 25;

    // 🔹 Paraules clau útils
    const roleKeywords = [
      'reception',
      'contact',
      'info',
      'admin',
      'manager',
      'sales',
      'reservations',
      'booking',
      'orders',
      'team',
      'hr',
      'hello',
    ];
    if (roleKeywords.any((k) => e.contains(k))) score += 20;

    // 🔹 Nom de l'empresa
    final nameParts = businessName
        .toLowerCase()
        .split(RegExp(r'[\s\-_]+'))
        .where((n) => n.length > 3);
    if (nameParts.any((p) => e.contains(p))) score += 20;

    // 🔹 Localització
    if (locationName != null) {
      final locParts = locationName.toLowerCase().split(RegExp(r'[\s,]+'));
      if (locParts.any((p) => e.contains(p) && p.length > 3)) score += 15;
    }

    // 🔹 Correus personals
    if (RegExp(r'@(gmail|hotmail|outlook|yahoo)\.').hasMatch(e)) score += 10;

    // 🔹 Pàgina d’origen rellevant
    if (origin.contains('/contact') || origin.contains('/about')) {
      score += 20;
    } else if (origin.endsWith('/') || origin == domain) {
      score += 10;
    }

    // 🔹 Penalitzacions
    if (e.contains('noreply') || e.contains('do-not-reply')) score -= 30;
    if (e.length < 10) score -= 10;

    return score.clamp(0, 100);
  }

  // ---------------- Validació ----------------
  bool _isValidEmail(String email, String domain, {String? originUrl}) {
    final e = email.toLowerCase();

    // 1️⃣ Patró bàsic correcte
    final baseValid = RegExp(
      r'^[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9\-]+(?:\.[a-zA-Z0-9\-]+)+$',
    ).hasMatch(e);
    if (!baseValid) return false;

    // 2️⃣ Bloqueja si el website o origen és Facebook o similar
    if ((originUrl ?? '').contains('facebook.com') ||
        (originUrl ?? '').contains('fbcdn.net')) {
      return false;
    }

    // 3️⃣ Bloqueja correus que semblin tècnics o falsos
    const blockedPatterns = [
      'loc@ion',
      'valid@ion',
      'transl@tion',
      'jquery',
      'cookie',
      'anim@ed',
      'modulemetad@a',
      'mut@ion',
      'dataset',
      'popover',
      'popover',
      'popover',
      'test@',
      'appspot',
      'example',
      'localhost',
      'static',
      'analytics',
      'popover',
      'react',
      'popover',
      'badge',
      'popover',
      'dataset',
      'aLayer.push',
      'render',
      'imageinfo',
      'popover',
      'popover',
    ];
    for (final pattern in blockedPatterns) {
      if (e.contains(pattern)) return false;
    }

    // 4️⃣ Bloqueja dominis sospitosos o no humans
    const invalidDomains = [
      'sky.com', // correu personal no relacionat amb negocis
      'sentry.io',
      'wixpress.com',
      'parastorage.com',
      'cloudflare.com',
      'google.com',
      'example.com',
    ];
    for (final bad in invalidDomains) {
      if (e.endsWith(bad)) return false;
    }

    return true;
  }
}
