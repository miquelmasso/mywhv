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

    // 🔹 Funció per combinar camins de forma segura
    String safeCombine(String base, String path) {
      if (path.startsWith('http') || path.startsWith(base)) return path;
      if (path.isEmpty || path == '/') return base;
      return base.endsWith('/') ? '$base$path' : '$base/$path';
    }

    // 🔹 Llista de possibles subpàgines on poden aparèixer links socials
    final urlsToCheck = <String>{
      cleanedBase,
      safeCombine(cleanedBase, 'about'),
      safeCombine(cleanedBase, 'about-us'),
      safeCombine(cleanedBase, 'contact'),
      safeCombine(cleanedBase, 'contact-us'),
      safeCombine(cleanedBase, 'connect'),
      safeCombine(cleanedBase, 'social'),
      safeCombine(cleanedBase, 'footer'),
    };

    for (final url in urlsToCheck) {
      if (!tried.add(url)) continue;
      final html = await _fetchHtmlUnsafe(url);
      if (html == null || html.isEmpty) continue;

      final matches = _extractFacebookLinks(html);
      if (matches.isNotEmpty) found.addAll(matches);
    }
    if (baseUrl.toLowerCase().contains('facebook.com')) {
      print('✅ Website ja és de Facebook: $baseUrl');
      return {'link': baseUrl, 'score': 100};
    }
    if (found.isEmpty) {
      // Si no troba res, prova amb la pàgina arrel (sense path)
      final rootHtml = await _fetchHtmlUnsafe(cleanedBase);
      if (rootHtml != null) found.addAll(_extractFacebookLinks(rootHtml));
    }

    if (found.isEmpty) {
      print('⚠️ Cap Facebook trobat per $baseUrl');
      return null;
    }

    // 🔹 Selecciona el millor link
    final best = _selectBest(found, businessName, address);
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
        if (url != null && !_isBad(url)) links.add(_clean(url));
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

  String _cleanBaseUrl(String url) {
    try {
      final uri = Uri.parse(url);
      return '${uri.scheme}://${uri.host}';
    } catch (_) {
      return url.split('?').first;
    }
  }

  String _selectBest(Set<String> found, String name, String address) {
    // De moment simplement agafa el primer vàlid
    for (final link in found) {
      if (!link.contains('share') && !link.contains('plugin')) return link;
    }
    return found.first;
  }
}
