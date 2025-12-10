import 'dart:io';
import 'package:http/io_client.dart';
import 'package:flutter/foundation.dart';

class EmailExtractor {
  String? lastFacebookUrl;
  static const bool _debugEmailFilterLogs = false;

  void _logEmail(String msg) {
    if (!_debugEmailFilterLogs) return;
    // ignore: avoid_print
    print(msg);
  }

  Future<String?> extract(String baseUrl, {String? businessName, String? locationName}) async {
    final tried = <String>{};
    final found = <Map<String, dynamic>>[];
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

// 🔹 Llista d’URLs a comprovar, amb combinació segura
final urlsToCheck = <String>{
  cleanedBase,
  safeCombine(cleanedBase, 'contact'),
  safeCombine(cleanedBase, 'contact-us'),
  safeCombine(cleanedBase, 'about'),
  safeCombine(cleanedBase, 'about-us'),
  safeCombine(cleanedBase, 'work-with-us'),
  safeCombine(cleanedBase, 'join-us'),
  safeCombine(cleanedBase, 'careers'),
};

    for (final url in urlsToCheck) {
      if (!tried.add(url)) continue;

      final html = await _fetchHtmlUnsafe(url);
      if (html == null || html.isEmpty) continue;

      final candidates = {
        ..._emailsFromMailto(html),
        ..._emailsDirect(html),
        ..._emailsFromJsonLd(html),
        ..._emailsDirect(_deobfuscate(html)),
      };

      for (final email in candidates) {
        if (!_isValidEmail(email, _domain(baseUrl), originUrl: url)) {
          _logEmail('❌ Filtrat: $email (invàlid)');
          continue;
        }

        final score = _scoreEmail(
          email,
          businessName ?? '',
          _domain(baseUrl),
          originUrl: url,
          locationName: locationName,
        );

        found.add({'email': email, 'score': score, 'origin': url});
      }
    }

    if (found.isEmpty) {
      _logEmail('⚠️ Cap correu vàlid trobat per $baseUrl');
      return null;
    }

    found.sort((a, b) => (b['score'] as int).compareTo(a['score'] as int));

    // print('📧 Candidats vàlids trobats per $baseUrl:');
    // for (final e in found) {
    //   print('   • ${e['email']} → ${e['score']}%  (origen: ${e['origin']})');
    // }

    final best = found.first;
    if ((best['score'] as int) < 40) {
      _logEmail('⚠️ Cap correu amb prou confiança.');
      return null;
    }

    _logEmail('✅ Millor correu: ${best['email']} (${best['score']}%)');
    return best['email'] as String;
  }

  // ---------------- HTTP amb SSL relaxat ----------------
  Future<String?> _fetchHtmlUnsafe(String url) async {
    try {
      final client = HttpClient()..badCertificateCallback = (_, __, ___) => true;
      final ioClient = IOClient(client);
      final response = await ioClient.get(Uri.parse(url)).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) return response.body;
      print('⚠️ HTTP ${response.statusCode} per $url');
    } catch (e) {
      print('⚠️ Error descarregant $url → $e');
    }
    return null;
  }

  // ---------------- Extractors ----------------
  final _emailRegex = RegExp(r'[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}');

  Set<String> _emailsFromMailto(String html) =>
      RegExp(r'mailto:([a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,})')
          .allMatches(html)
          .map((m) => m.group(1)!)
          .toSet();

  Set<String> _emailsDirect(String html) =>
      _emailRegex.allMatches(html).map((m) => m.group(0)!).toSet();

  Set<String> _emailsFromJsonLd(String html) =>
      RegExp(r'"email"\s*:\s*"([^"]+)"').allMatches(html).map((m) => m.group(1)!).toSet();

  String _deobfuscate(String html) => html
      .replaceAll('&commat;', '@')
      .replaceAll('&#64;', '@')
      .replaceAll('&#46;', '.')
      .replaceAll('&dot;', '.')
      .replaceAll(RegExp(r'\s*(?:at|AT)\s*'), '@')
      .replaceAll(RegExp(r'\s*(?:dot|DOT)\s*'), '.');

  // ---------------- Helpers ----------------
  String _combine(String base, String path) => base.endsWith('/') ? '$base$path' : '$base/$path';

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
      'reception', 'contact', 'info', 'admin', 'manager', 'sales',
      'reservations', 'booking', 'orders', 'team', 'hr', 'hello'
    ];
    if (roleKeywords.any((k) => e.contains(k))) score += 20;

    // 🔹 Nom de l'empresa
    final nameParts = businessName.toLowerCase().split(RegExp(r'[\s\-_]+')).where((n) => n.length > 3);
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
    } else if (origin.endsWith('/') || origin == domain) score += 10;

    // 🔹 Penalitzacions
    if (e.contains('noreply') || e.contains('do-not-reply')) score -= 30;
    if (e.length < 10) score -= 10;

    return score.clamp(0, 100);
  }

  // ---------------- Validació ----------------
 bool _isValidEmail(String email, String domain, {String? originUrl}) {
  final e = email.toLowerCase();

  // 1️⃣ Patró bàsic correcte
  final baseValid = RegExp(r'^[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.(com|com\.au)$').hasMatch(e);
  if (!baseValid) return false;

  // 2️⃣ Bloqueja si el website o origen és Facebook o similar
  if ((originUrl ?? '').contains('facebook.com') || (originUrl ?? '').contains('fbcdn.net')) {
    return false;
  }

  // 3️⃣ Bloqueja correus que semblin tècnics o falsos
  const blockedPatterns = [
    'loc@ion', 'valid@ion', 'transl@tion', 'jquery', 'cookie', 'anim@ed',
    'modulemetad@a', 'mut@ion', 'dataset', 'popover', 'popover', 'popover', 
    'test@', 'appspot', 'example', 'localhost', 'static', 'analytics', 'popover',
    'react', 'popover', 'badge', 'popover', 'dataset', 'aLayer.push', 'render',
    'imageinfo', 'popover', 'popover'
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
    'example.com'
  ];
  for (final bad in invalidDomains) {
    if (e.endsWith(bad)) return false;
  }


  return true;
}
}
