import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/google_places_service.dart';
import '../services/restaurant_import_service.dart';
import '../services/visa_postcodes_sqlite_store.dart';

class AddRestaurantsByPostcodePage extends StatefulWidget {
  const AddRestaurantsByPostcodePage({super.key});

  @override
  State<AddRestaurantsByPostcodePage> createState() =>
      _AddRestaurantsByPostcodePageState();
}

class _AddRestaurantsByPostcodePageState
    extends State<AddRestaurantsByPostcodePage> {
  final TextEditingController _postcodeController = TextEditingController(
    text: '4802',
  );
  String _result = '';
  String _restaurantName = '';
  bool _loading = false;

  final _firestore = FirebaseFirestore.instance;
  final _placesService = GooglePlacesService();
  final RestaurantImportService _importService = RestaurantImportService();
  final VisaPostcodesSqliteStore _visaStore = VisaPostcodesSqliteStore.instance;

  void _showSnack(String text, {Color? color}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: color ?? Colors.blueGrey.shade800,
      ),
    );
  }

  Future<void> _checkPostcode() async {
    final input = _postcodeController.text.trim();
    if (input.isEmpty) {
      setState(() {
        _result = '❌ Enter a postcode.';
        _restaurantName = '';
      });
      return;
    }

    final String postcodeStr = input.padLeft(4, '0');
    final int? postcodeNum = int.tryParse(postcodeStr);

    if (postcodeNum == null) {
      setState(() {
        _result = '❌ Enter a valid number.';
        _restaurantName = '';
      });
      return;
    }

    setState(() {
      _loading = true;
      _result = '';
      _restaurantName = '';
    });

    try {
      await _visaStore.init();
      final entries = await _visaStore.getAll();

      bool found = false;
      String category = '';

      for (final data in entries) {
        final List<dynamic> postcodes = data['postcodes'] ?? [];
        final postcodesStr = postcodes
            .map((e) => e.toString().padLeft(4, '0'))
            .toList();

        if (postcodesStr.contains(postcodeStr)) {
          found = true;
          category = (data['industry'] ?? data['id'] ?? '').toString();
          break;
        }
      }

      if (!found) {
        setState(() {
          _result = '⚠️ $postcodeStr is not regional or remote.';
        });
      } else {
        if (category.contains('Regional')) {
          _result = '✅ $postcodeStr is REGIONAL (Regional Australia)';
        } else if (category.contains('Hospitality')) {
          _result = '✅ $postcodeStr is REMOTE (Tourism & Hospitality)';
        } else {
          _result = '✅ $postcodeStr is valid for visa 417/462.';
        }

        final list = await _placesService.saveTwoRestaurantsForPostcode(
          postcodeNum,
        );
        final restaurant = list.isNotEmpty ? list.first : null;

        if (restaurant != null) {
          final name = restaurant['name'] ?? 'Unknown name';

          setState(() {
            _restaurantName = name;
          });
        } else {
          setState(() {
            _restaurantName = 'No restaurants found for this postcode.';
          });
        }
      }
    } catch (e) {
      setState(
        () => _result =
            'We could not check this postcode right now. Please try again.',
      );
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _addRestaurantAutomatically() async {
    final input = _postcodeController.text.trim();
    if (input.isEmpty) {
      _showSnack('❌ Enter a postcode.');
      return;
    }

    setState(() => _loading = true);

    try {
      final result = await _importService.importRestaurantsForPostcode(input);

      if (!result.valid) {
        _showSnack('❌ Invalid postcode.');
        return;
      }

      if (!result.allowed) {
        _showSnack(
          '❌ Postcode ${result.postcode} is not REMOTE or in the Northern Territory.',
          color: Colors.deepOrange,
        );
        return;
      }

      if (result.addedCount == 0) {
        _showSnack('⚠️ No new restaurants found.', color: Colors.orange);
      } else {
        _showSnack(
          '✅ ${result.addedCount} restaurants added for ${result.postcode}!',
          color: Colors.green,
        );
      }
    } catch (e) {
      _showSnack(
        'We could not add restaurants right now. Please try again.',
        color: Colors.red,
      );
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _deleteLastRestaurant() async {
    setState(() => _loading = true);

    try {
      final snapshot = await _firestore
          .collection('restaurants')
          .orderBy('timestamp', descending: true)
          .limit(1)
          .get();

      if (snapshot.docs.isEmpty) {
        _showSnack('⚠️ No restaurants to delete.', color: Colors.orange);
      } else {
        final doc = snapshot.docs.first;
        final name = doc['name'] ?? 'Unknown';
        await doc.reference.delete();
        _showSnack('🗑️ Deleted: $name', color: Colors.redAccent);
      }
    } catch (e) {
      _showSnack(
        'We could not delete the restaurant right now. Please try again.',
        color: Colors.red,
      );
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _deleteAllExceptLast() async {
    setState(() => _loading = true);

    try {
      final snapshot = await _firestore
          .collection('restaurants')
          .orderBy('timestamp', descending: true)
          .get();

      if (snapshot.docs.length <= 1) {
        _showSnack(
          '⚠️ Only one restaurant, nothing to remove.',
          color: Colors.orange,
        );
        return;
      }

      for (var i = 1; i < snapshot.docs.length; i++) {
        await snapshot.docs[i].reference.delete();
      }

      final lastName = snapshot.docs.first['name'] ?? 'Unknown';
      _showSnack('🧹 Deleted all except: $lastName', color: Colors.purple);
    } catch (e) {
      _showSnack(
        'We could not delete the restaurants right now. Please try again.',
        color: Colors.red,
      );
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _findAllRestaurantsByPostcode() async {
    final input = _postcodeController.text.trim();
    if (input.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('❌ Enter a postcode.')));
      return;
    }

    final String postcodeStr = input.padLeft(4, '0');
    final int? postcodeNum = int.tryParse(postcodeStr);
    if (postcodeNum == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Invalid postcode.')));
      return;
    }

    setState(() => _loading = true);

    try {
      final totalAdded = await _importService.importAllRestaurantsForPostcode(
        postcodeStr,
      );
      if (!mounted) return;

      if (totalAdded == 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('⚠️ No new restaurants found for $postcodeStr.'),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Added $totalAdded restaurants for $postcodeStr!'),
            backgroundColor: Colors.green.shade700,
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ Error en la cerca massiva: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'We could not search all restaurants for this postcode right now.',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Restaurant management',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0.5,
      ),
      backgroundColor: Colors.white,
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 10),
              const Text(
                'Check if a postcode is\nREGIONAL or REMOTE',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 25),
              TextField(
                controller: _postcodeController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Enter postcode',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.search),
                    onPressed: _checkPostcode,
                  ),
                ),
                onSubmitted: (_) => _checkPostcode(),
              ),
              const SizedBox(height: 20),
              if (_loading)
                const CircularProgressIndicator()
              else ...[
                Text(
                  _result,
                  style: TextStyle(
                    fontSize: 18,
                    color: _result.contains('✅')
                        ? Colors.green
                        : _result.contains('⚠️')
                        ? Colors.orange
                        : Colors.red,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 15),
                if (_restaurantName.isNotEmpty)
                  Text(
                    '🍴 $_restaurantName',
                    style: const TextStyle(
                      fontSize: 16,
                      color: Colors.black87,
                      fontStyle: FontStyle.italic,
                    ),
                    textAlign: TextAlign.center,
                  ),
              ],
              const SizedBox(height: 40),
              Wrap(
                spacing: 15,
                runSpacing: 15,
                alignment: WrapAlignment.center,
                children: [
                  ElevatedButton.icon(
                    onPressed: _addRestaurantAutomatically,
                    icon: const Icon(Icons.restaurant),
                    label: const Text('Add restaurant'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green.shade600,
                      foregroundColor: Colors.white,
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: _deleteLastRestaurant,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Delete latest'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                      foregroundColor: Colors.white,
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: _deleteAllExceptLast,
                    icon: const Icon(Icons.cleaning_services),
                    label: const Text('Delete all except latest'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepPurple,
                      foregroundColor: Colors.white,
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: _findAllRestaurantsByPostcode,
                    icon: const Icon(Icons.search_rounded),
                    label: const Text('Add all from postcode'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueAccent,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
