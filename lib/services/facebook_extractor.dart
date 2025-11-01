import 'package:http/http.dart' as http;

class FacebookExtractor {
  final Map<String, String> _headers = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120 Safari/537.36',
    'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8'
  };

  /// Cerca dins la web del negoci un link de Facebook i avalua si sembla real.
  Future<Map<String, dynamic>?> find({
    required String baseUrl,
    required String businessName,
    required String address,
    String? phone,
  }) async {
    //print('📘 Buscant Facebook dins $baseUrl...');

    final html = await _fetchHtml(baseUrl);
    if (html == null || html.isEmpty) {
      //print('⚠️ No s’ha pogut descarregar la web.');
      return null;
    }

    final links = _extractFacebookLinks(html);
    if (links.isEmpty) {
      //print('⚠️ No s’han trobat links de Facebook.');
      return null;
    }

    final city = _extractCity(address);
    final domain = _extractDomain(baseUrl);
    final cleanName = _normalize(businessName);

    final scored = links.map((l) {
      final s = _score(l, cleanName, city, domain);
      return {'link': l, 'score': s};
    }).toList()
      ..sort((a, b) => (b['score'] as int).compareTo(a['score'] as int));

    for (final s in scored) {
      //print('   • ${s['link']} → ${s['score']}%');
    }

    final best = scored.first;
    if ((best['score'] as int) < 40) {
      //print('⚠️ Cap link amb prou confiança (${best['score']}%).');
      return null;
    }

    final clean = _clean(best['link'] as String);
    //print('🏆 Millor: $clean (${best['score']}%)');
    return {'link': clean, 'score': best['score']};
  }

  // ---------------- HELPER FUNCTIONS ----------------

  Future<String?> _fetchHtml(String url) async {
    try {
      final r = await http.get(Uri.parse(url), headers: _headers).timeout(const Duration(seconds: 10));
      if (r.statusCode == 200) return r.body;
      //print('⚠️ HTTP ${r.statusCode} per $url');
    } catch (e) {
      //print('⚠️ Error descarregant $url → $e');
    }
    return null;
  }

  Set<String> _extractFacebookLinks(String html) {
    final links = <String>{};
    final reg = RegExp(r'https?:\/\/(?:www\.)?facebook\.com\/[^\s"<>\)]+', caseSensitive: false);
    for (final m in reg.allMatches(html)) {
      final u = _clean(m.group(0)!);
      if (!_isBad(u)) links.add(u);
    }
    //print('🌐 Links trobats: ${links.length}');
    return links;
  }

  bool _isBad(String url) {
    final l = url.toLowerCase();
    return l.contains('pixel') ||
        l.contains('share.php') ||
        l.contains('dialog') ||
        l.contains('plugin') ||
        l.contains('tr?id=');
  }

  String _clean(String url) {
    var u = url.trim();
    try {
      u = Uri.decodeFull(u);
    } catch (_) {}
    for (final c in ['"', "'", '#', '?', '&', '%']) {
      final i = u.indexOf(c);
      if (i > 0) u = u.substring(0, i);
    }
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    if (!u.startsWith('http')) u = 'https://$u';
    return u;
  }

  String _normalize(String t) =>
      t.toLowerCase().replaceAll(RegExp(r'[^a-z0-9\s]'), '').trim();

  String _extractDomain(String url) {
    try {
      return Uri.parse(url).host.replaceAll('www.', '');
    } catch (_) {
      return '';
    }
  }

  String _extractCity(String address) {
    final parts = address.split(',').map((s) => s.trim()).toList();
    for (final p in parts) {
      if (RegExp(r'\b(QLD|NSW|VIC|WA|SA|TAS|NT)\b', caseSensitive: false)
          .hasMatch(p)) {
        return p.split(RegExp(r'\b(QLD|NSW|VIC|WA|SA|TAS|NT)\b')).first.trim();
      }
    }
    return parts.length >= 2 ? parts[1].replaceAll(RegExp(r'\d'), '').trim() : '';
  }

  int _score(String url, String name, String city, String domain) {
    int s = 0;
    final l = url.toLowerCase();

    // 🔹 1) Nom parcial al link
    for (final p in name.split(' ')) {
      if (p.length > 2 && l.contains(p)) s += 20;
    }

    // 🔹 2) Ciutat
    if (city.isNotEmpty && l.contains(city.toLowerCase())) s += 25;

    // 🔹 3) Domini
    if (domain.isNotEmpty && l.contains(domain.split('.').first)) s += 10;

    // 🔹 4) Bonus per "restaurant", "bar", "cafe"
    if (RegExp(r'(bar|cafe|restaurant)', caseSensitive: false).hasMatch(l)) s += 15;

    // 🔹 5) Penalitza generics
    if (_isBad(l)) s -= 20;

    return s.clamp(0, 100);
  }
}
