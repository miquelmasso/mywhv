import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';

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

  /// Carrega un snapshot únic dels restaurants que estan a preferits.
  static Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> fetchFavoriteRestaurantsOnce() async {
    final ids = await loadFavoriteIds();
    if (ids.isEmpty) return [];
    final firestore = FirebaseFirestore.instance;
    final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs = [];
    final batches = <List<String>>[];
    final list = ids.toList();
    const int chunkSize = 10; // Firestore whereIn limit
    for (var i = 0; i < list.length; i += chunkSize) {
      batches.add(list.sublist(i, i + chunkSize > list.length ? list.length : i + chunkSize));
    }
    for (final batch in batches) {
      final snapshot = await firestore
          .collection('restaurants')
          .where(FieldPath.documentId, whereIn: batch)
          .get();
      docs.addAll(snapshot.docs);
    }
    return docs;
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
