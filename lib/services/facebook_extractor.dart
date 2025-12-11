import 'dart:io';
import 'package:http/io_client.dart';

class FacebookExtractor {
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
      print('⚠️ La web base és Facebook; s’omet la detecció de pàgina.');
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
      print('⚠️ Cap Facebook trobat per $baseUrl');
      return null;
    }

    // 🔹 Selecciona el millor link
    final best = _selectBest(found, businessName);
    if (best == null) {
      print('⚠️ Cap Facebook vàlid per $baseUrl');
      return null;
    }
    print('✅ Facebook trobat: $best');
    return {'link': best, 'score': 100};
  }

  // ---------------- Helpers ----------------

  Future<String?> _fetchHtmlUnsafe(String url) async {
    try {
      final client = HttpClient()
        ..badCertificateCallback = (_, __, ___) => true;
      final ioClient = IOClient(client);
      final response = await ioClient
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) return response.body;
      print('⚠️ HTTP ${response.statusCode} per $url');
    } catch (e) {
      print('⚠️ Error descarregant $url → $e');
    }
    return null;
  }

  Set<String> _extractFacebookLinks(String html) {
    final links = <String>{};

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
      for (final match in reg.allMatches(html)) {
        final url = match.group(1)?.trim();
        if (url != null && !_isBad(url) && _isValidFacebookPage(url)) {
          links.add(_clean(url));
        }
      }
    }
    return links;
  }

  bool _isBad(String url) {
    final l = url.toLowerCase();
    return l.contains('plugin') ||
        l.contains('share.php') ||
        l.contains('dialog') ||
        l.contains('pixel') ||
        l.contains('login');
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
    if (!host.contains('facebook.com') && !host.contains('fb.com')) return false;

    if (uri.path.isEmpty || uri.path == '/') return false;

    final segments = uri.pathSegments.where((s) => s.trim().isNotEmpty).toList();
    if (segments.isEmpty) return false;

    const badLastSegments = {
      'tr',
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
    };
    final lastSegment = segments.last.toLowerCase();
    if (badLastSegments.contains(lastSegment)) return false;
    if (segments.length >= 2 &&
        segments[0].toLowerCase() == 'pages' &&
        segments[1].toLowerCase() == 'category') {
      return false;
    }

    if (uri.path == '/profile.php') {
      final id = uri.queryParameters['id'];
      return id != null && id.trim().isNotEmpty && RegExp(r'^\d+$').hasMatch(id);
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

    final pathSegments =
        uri.pathSegments.where((s) => s.trim().isNotEmpty).toList();
    final lastSegment = pathSegments.isNotEmpty ? pathSegments.last : '';

    // profile.php with id
    if (uri.path == '/profile.php' &&
        uri.queryParameters['id'] != null &&
        uri.queryParameters['id']!.trim().isNotEmpty) {
      score += 40;
    }

    // business name match
    final normalizedBiz =
        businessName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    final candidateSlug = _extractSlugFromPath(pathSegments);
    if (normalizedBiz.isNotEmpty &&
        candidateSlug.isNotEmpty &&
        candidateSlug.contains(normalizedBiz)) {
      score += 60;
    }

    // depth penalty
    score -= pathSegments.length * 5;

    // query penalty if many params
    final queryCount = uri.queryParameters.length;
    if (queryCount > 3) score -= (queryCount - 3) * 5;

    return score;
  }

  String _extractSlugFromPath(List<String> segments) {
    if (segments.isEmpty) return '';
    if (segments.first.toLowerCase() == 'pages' && segments.length >= 2) {
      return segments[1].toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    }
    final last = segments.last.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    return last;
  }
}
