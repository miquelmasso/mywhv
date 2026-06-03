import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../screens/restaurant_edit_page.dart';
import '../services/map_markers_service.dart';

class WorkedHereListPage extends StatefulWidget {
  const WorkedHereListPage({super.key});

  @override
  State<WorkedHereListPage> createState() => _WorkedHereListPageState();
}

class _WorkedHereListPageState extends State<WorkedHereListPage> {
  bool _loading = false;
  bool _hasLoaded = false;
  List<Map<String, dynamic>> _restaurants = [];

  Future<void> _loadRestaurants() async {
    setState(() => _loading = true);
    try {
      var list = _sortRestaurants(
        (await MapMarkersService.loadRestaurants(
          fromServer: false,
          lightweight: true,
        )).map(_fromLocalRestaurant).toList(growable: true),
      );

      if (list.isEmpty) {
        final snapshot = await FirebaseFirestore.instance
            .collection('restaurants')
            .get();
        list = _sortRestaurants(
          snapshot.docs
              .map((doc) => _fromFirebaseRestaurant(doc.id, doc.data()))
              .toList(growable: true),
        );
      }

      if (!mounted) return;
      setState(() {
        _restaurants = list;
        _loading = false;
        _hasLoaded = true;
      });
    } catch (e) {
      debugPrint('Error carregant worked here dels restaurants: $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _hasLoaded = true;
      });
    }
  }

  static int _parseCount(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse((value ?? '').toString()) ?? 0;
  }

  static Map<String, dynamic> _fromLocalRestaurant(
    Map<String, dynamic> restaurant,
  ) {
    return {
      'docId': (restaurant['docId'] ?? restaurant['id'] ?? '').toString(),
      'name': (restaurant['name'] ?? 'Sense nom').toString(),
      'workedHereCount': _parseCount(restaurant['worked_here_count']),
    };
  }

  static Map<String, dynamic> _fromFirebaseRestaurant(
    String docId,
    Map<String, dynamic> data,
  ) {
    return {
      'docId': docId,
      'name': (data['name'] ?? 'Sense nom').toString(),
      'workedHereCount': _parseCount(data['worked_here_count']),
    };
  }

  static List<Map<String, dynamic>> _sortRestaurants(
    List<Map<String, dynamic>> restaurants,
  ) {
    return restaurants..sort((a, b) {
      final countA = a['workedHereCount'] as int;
      final countB = b['workedHereCount'] as int;
      final byCount = countB.compareTo(countA);
      if (byCount != 0) return byCount;

      final nameA = (a['name'] ?? '').toString().trim().toLowerCase();
      final nameB = (b['name'] ?? '').toString().trim().toLowerCase();
      return nameA.compareTo(nameB);
    });
  }

  int get _totalWorkedHere => _restaurants.fold<int>(
    0,
    (total, restaurant) => total + (restaurant['workedHereCount'] as int),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Worked here'),
        backgroundColor: Colors.deepPurple,
        actions: [
          IconButton(
            tooltip: 'Reload',
            onPressed: _loading ? null : _loadRestaurants,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : !_hasLoaded
          ? const Center(child: Text('Press reload to load the data.'))
          : _restaurants.isEmpty
          ? const Center(child: Text('No restaurants available.'))
          : Column(
              children: [
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.deepPurple.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.deepPurple.shade100),
                  ),
                  child: Text(
                    'Restaurants: ${_restaurants.length} · Worked here totals: $_totalWorkedHere',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _restaurants.length,
                    itemBuilder: (context, i) {
                      final restaurant = _restaurants[i];
                      final name = (restaurant['name'] ?? '').toString();
                      final count = restaurant['workedHereCount'] as int;

                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 6),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Colors.deepPurple.shade50,
                            foregroundColor: Colors.deepPurple,
                            child: Text('${i + 1}'),
                          ),
                          title: Text(
                            name,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '$count',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 18,
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                icon: const Icon(Icons.edit_outlined),
                                tooltip: 'Edit restaurant',
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => RestaurantEditPage(
                                        initialSearch: name,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}
