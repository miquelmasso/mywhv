import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import 'restaurant_sqlite_store.dart';

class FavoritesService {
  FavoritesService._();

  static const _prefsKey = 'favorite_places';
  static final StreamController<Set<String>> _controller =
      StreamController<Set<String>>.broadcast();

  static Stream<Set<String>> get changes => _controller.stream;

  /// Llegeix la llista d'IDs de preferits des de SharedPreferences (mateixa lògica del mapa).
  static Future<Set<String>> loadFavoriteIds() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_prefsKey) ?? [];
    return list.toSet();
  }

  /// Carrega els restaurants preferits resolent els IDs contra SQLite local.
  static Future<List<Map<String, dynamic>>> fetchFavoriteRestaurantsOnce({
    bool forceServer = false,
  }) async {
    if (forceServer) {
      // La signatura es manté per compatibilitat, però els preferits ja són local-only.
    }
    final ids = await loadFavoriteIds();
    if (ids.isEmpty) return [];
    final store = RestaurantSqliteStore.instance;
    await store.init();
    final restaurants = await store.getAll();
    final favorites = <Map<String, dynamic>>[];

    for (final id in ids) {
      for (final restaurant in restaurants) {
        final candidateId = (restaurant['docId'] ?? restaurant['id'] ?? '')
            .toString();
        if (candidateId != id) continue;
        favorites.add(Map<String, dynamic>.from(restaurant));
        break;
      }
    }

    return favorites;
  }

  /// Treu de preferits sense refrescar UI (mateixa clau que al mapa).
  static Future<void> removeFavorite(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getStringList(_prefsKey)?.toSet() ?? <String>{};
    current.remove(id);
    await prefs.setStringList(_prefsKey, current.toList());
    _emit(current);
  }

  /// Torna a afegir un ID a preferits (mateixa lògica del mapa).
  static Future<void> addFavorite(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getStringList(_prefsKey)?.toSet() ?? <String>{};
    current.add(id);
    await prefs.setStringList(_prefsKey, current.toList());
    _emit(current);
  }

  /// Emiteix canvis perquè altres pantalles (mapa) els escoltin.
  static void broadcast(Set<String> ids) {
    _emit(ids);
  }

  static void _emit(Set<String> ids) {
    if (!_controller.isClosed) {
      _controller.add(Set<String>.from(ids));
    }
  }
}
