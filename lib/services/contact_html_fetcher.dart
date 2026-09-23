import 'dart:async';
import 'dart:io';

import 'package:http/io_client.dart';

class ContactHtmlFetcher {
  ContactHtmlFetcher._();

  static final IOClient _client = IOClient(
    HttpClient()..badCertificateCallback = (_, _, _) => true,
  );
  static final Map<String, Future<String?>> _cache =
      <String, Future<String?>>{};
  static final Map<String, String> _lastFailureByHost = <String, String>{};

  static String? lastFailureReason(String url) {
    final host = Uri.tryParse(_normalizeUrl(url))?.host.toLowerCase();
    return host == null ? null : _lastFailureByHost[host];
  }

  static Future<String?> fetch(String url, {Duration? timeout}) {
    final normalized = _normalizeUrl(url);
    if (normalized.isEmpty) return Future.value(null);
    return _cache.putIfAbsent(normalized, () {
      final future = _fetchUncached(
        normalized,
        timeout: timeout ?? _defaultTimeoutForUrl(normalized),
      );
      future.then((html) {
        if (html == null) _cache.remove(normalized);
      });
      return future;
    });
  }

  static Future<void> prefetchAll(
    Iterable<String> urls, {
    Duration? timeout,
  }) async {
    await Future.wait(
      urls.map((url) => fetch(url, timeout: timeout).then((_) {})),
      eagerError: false,
    );
  }

  static Future<String?> _fetchUncached(String url, {Duration? timeout}) async {
    try {
      final response = await _client
          .get(
            Uri.parse(url),
            headers: const {
              'User-Agent':
                  'Mozilla/5.0 (compatible; WorkyDayContactImporter/1.0)',
              'Accept':
                  'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
            },
          )
          .timeout(timeout ?? const Duration(seconds: 10));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        final host = Uri.tryParse(url)?.host.toLowerCase() ?? '';
        if (host.isNotEmpty) {
          if (response.statusCode == 403) {
            _lastFailureByHost[host] = 'http_403_blocked';
          } else if (response.statusCode == 429 || response.statusCode >= 500) {
            _lastFailureByHost[host] =
                'http_${response.statusCode}_retry_later';
          } else {
            // A missing optional page such as /careers is not a transient
            // failure of the company's website.
            _lastFailureByHost.remove(host);
          }
        }
        return null;
      }

      final host = Uri.tryParse(url)?.host.toLowerCase() ?? '';
      if (host.isNotEmpty) _lastFailureByHost.remove(host);

      final contentType = response.headers['content-type']?.toLowerCase() ?? '';
      if (contentType.isNotEmpty &&
          !contentType.contains('text/html') &&
          !contentType.contains('application/xhtml') &&
          !contentType.contains('application/xml') &&
          !contentType.contains('text/xml') &&
          !contentType.contains('text/plain')) {
        return null;
      }

      return response.body;
    } on TimeoutException {
      final host = Uri.tryParse(url)?.host.toLowerCase() ?? '';
      if (host.isNotEmpty) _lastFailureByHost[host] = 'timeout_retry_later';
      return null;
    } on SocketException {
      final host = Uri.tryParse(url)?.host.toLowerCase() ?? '';
      if (host.isNotEmpty) _lastFailureByHost[host] = 'network_retry_later';
      return null;
    } catch (_) {
      return null;
    }
  }

  static String _normalizeUrl(String value) {
    var url = value.trim();
    if (url.isEmpty) return '';
    if (!RegExp(r'^https?://', caseSensitive: false).hasMatch(url)) {
      url = 'https://$url';
    }
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.trim().isEmpty) return '';
    if (uri.scheme != 'http' && uri.scheme != 'https') return '';
    return uri.replace(fragment: '').toString();
  }

  static Duration _defaultTimeoutForUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return const Duration(seconds: 6);
    final path = uri.path.toLowerCase();
    if (path == '/' || path.isEmpty) return const Duration(seconds: 8);
    if (path.endsWith('.xml') || path.contains('sitemap')) {
      return const Duration(seconds: 6);
    }
    if (path.contains('contact') ||
        path.contains('about') ||
        path.contains('career') ||
        path.contains('job')) {
      return const Duration(seconds: 8);
    }
    return const Duration(seconds: 6);
  }
}
