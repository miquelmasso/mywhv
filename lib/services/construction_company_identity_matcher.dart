class ConstructionCompanyIdentityMatcher {
  const ConstructionCompanyIdentityMatcher._();

  /// Requires a complete company identity, not a shared word. This prevents
  /// names such as "Aeris Resources" from matching an unrelated "Aeris", or
  /// "Mineral Hill" from matching a company whose domain merely contains
  /// "hill".
  static bool matchesWebsite({
    required String html,
    required String url,
    required String businessName,
    Iterable<String> aliases = const <String>[],
  }) {
    final host =
        Uri.tryParse(
          url,
        )?.host.toLowerCase().replaceFirst(RegExp(r'^www\.'), '') ??
        '';
    if (host.isEmpty) return false;
    final hostSlug = _slug(host.split('.').first);
    final declaredNames = _declaredWebsiteNames(html);
    final primaryTokenCount = _identityTokens(businessName).length;

    bool completeMatch(String name, {required bool isPrimary}) {
      final tokens = _identityTokens(name);
      if (tokens.isEmpty) return false;
      final phrase = tokens.join(' ');
      final compact = tokens.join();
      if (tokens.length == 1) {
        if (!isPrimary && primaryTokenCount > 1) return false;
        final token = tokens.single;
        return token.length >= 5 &&
            (hostSlug == token || declaredNames.contains(token));
      }
      return hostSlug.contains(compact) || declaredNames.contains(phrase);
    }

    if (completeMatch(businessName, isPrimary: true)) return true;
    return aliases.any((alias) => completeMatch(alias, isPrimary: false));
  }

  static List<String> _identityTokens(String value) => _words(
    value,
  ).where((token) => !_legalSuffixes.contains(token)).toList(growable: false);

  static List<String> _words(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim()
      .split(RegExp(r'\s+'))
      .where((token) => token.isNotEmpty)
      .toList(growable: false);

  static String _slug(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');

  static String _stripHtml(String value) => value
      .replaceAll(
        RegExp(r'<script[\s\S]*?</script>', caseSensitive: false),
        ' ',
      )
      .replaceAll(RegExp(r'<style[\s\S]*?</style>', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'<[^>]+>'), ' ')
      .replaceAll(RegExp(r'&[a-z0-9#]+;', caseSensitive: false), ' ');

  static Set<String> _declaredWebsiteNames(String html) {
    final values = <String>[];
    for (final match in RegExp(
      r'<title[^>]*>([\s\S]*?)</title>',
      caseSensitive: false,
    ).allMatches(html)) {
      values.add(match.group(1) ?? '');
    }
    for (final match in RegExp(
      r'"(?:name|legalName)"\s*:\s*"([^"]+)"',
      caseSensitive: false,
    ).allMatches(html)) {
      values.add(match.group(1) ?? '');
    }
    return values
        .map(_stripHtml)
        .map(_identityTokens)
        .where((tokens) => tokens.isNotEmpty)
        .map((tokens) => tokens.join(' '))
        .toSet();
  }

  static const _legalSuffixes = {
    'pty',
    'ltd',
    'limited',
    'inc',
    'incorporated',
    'llc',
    'plc',
    'co',
    'company',
    'group',
    'the',
    'australia',
    'australian',
  };
}
