import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AffiliateLinksService {
  AffiliateLinksService._();

  static final AffiliateLinksService instance = AffiliateLinksService._();

  static const String _configUrl =
      'https://workyday.com/config/affiliate_links.json';
  static const String _cacheKey = 'affiliate_links_cache_json';
  static const String _lastFetchKey = 'affiliate_links_last_successful_fetch';
  static const Duration _fetchInterval = Duration(days: 30);

  Future<void>? _initFuture;
  Map<String, String> _links = const {};

  Future<void> init() {
    return _initFuture ??= _initInternal();
  }

  Future<String> getLink(String key) async {
    await init();
    return _links[key]?.trim() ?? '';
  }

  Future<void> _initInternal() async {
    final prefs = await SharedPreferences.getInstance();
    _links = _decodeLinks(prefs.getString(_cacheKey));

    final lastFetchMillis = prefs.getInt(_lastFetchKey) ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    final shouldFetch =
        lastFetchMillis == 0 ||
        now - lastFetchMillis >= _fetchInterval.inMilliseconds;

    if (!shouldFetch) return;

    try {
      final response = await http
          .get(Uri.parse(_configUrl))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return;
      }

      final freshLinks = _decodeLinks(response.body);
      if (freshLinks.isEmpty) return;

      _links = freshLinks;
      await prefs.setString(_cacheKey, response.body);
      await prefs.setInt(_lastFetchKey, now);
    } catch (error) {
      debugPrint('Affiliate links fetch failed: $error');
    }
  }

  Map<String, String> _decodeLinks(String? rawJson) {
    if (rawJson == null || rawJson.trim().isEmpty) {
      return const {};
    }

    try {
      final decoded = jsonDecode(rawJson);
      if (decoded is! Map<String, dynamic>) {
        return const {};
      }

      return decoded.map((key, value) {
        return MapEntry(key, value is String ? value.trim() : '');
      })..removeWhere((key, value) => value.isEmpty);
    } catch (error) {
      debugPrint('Affiliate links decode failed: $error');
      return const {};
    }
  }
}
