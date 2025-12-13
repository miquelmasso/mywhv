import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/google_places_service.dart';
import '../services/postcode_state_helper.dart';
import '../services/restaurant_import_service.dart';

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
        _result = '❌ Introdueix un codi postal.';
        _restaurantName = '';
      });
      return;
    }

    final String postcodeStr = input.padLeft(4, '0');
    final int? postcodeNum = int.tryParse(postcodeStr);

    if (postcodeNum == null) {
      setState(() {
        _result = '❌ Escriu un número vàlid.';
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
      final snapshot = await _firestore.collection('visa_postcodes').get();

      bool found = false;
      String category = '';

      for (var doc in snapshot.docs) {
        final data = doc.data();
        final List<dynamic> postcodes = data['postcodes'] ?? [];
        final postcodesStr =
            postcodes.map((e) => e.toString().padLeft(4, '0')).toList();

        if (postcodesStr.contains(postcodeStr)) {
          found = true;
          category = data['industry'] ?? doc.id;
          break;
        }
      }

      if (!found) {
        setState(() {
          _result = '⚠️ $postcodeStr no és regional ni remot.';
        });
      } else {
        if (category.contains('Regional')) {
          _result = '✅ $postcodeStr és REGIONAL (Regional Australia)';
        } else if (category.contains('Hospitality')) {
          _result = '✅ $postcodeStr és REMOTE (Tourism & Hospitality)';
        } else {
          _result = '✅ $postcodeStr és vàlid per al visat 417/462.';
        }

        final list = await _placesService.SaveTwoRestaurantsForPostcode(
          postcodeNum,
        );
        final restaurant = list.isNotEmpty ? list.first : null;

        if (restaurant != null) {
          final name = restaurant['name'] ?? 'Nom desconegut';

          setState(() {
            _restaurantName = name;
          });
        } else {
          setState(() {
            _restaurantName = 'No s’ha trobat cap restaurant per aquest codi.';
          });
        }
      }
    } catch (e) {
      setState(() => _result = '❌ Error al cercar: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _addRestaurantAutomatically() async {
    final input = _postcodeController.text.trim();
    if (input.isEmpty) {
      _showSnack('❌ Introdueix un codi postal.');
      return;
    }

    setState(() => _loading = true);

    try {
      final result = await _importService.importRestaurantsForPostcode(input);

      if (!result.valid) {
        _showSnack('❌ Codi postal invàlid.');
        return;
      }

      if (!result.allowed) {
        _showSnack(
          '❌ El codi postal ${result.postcode} no és REMOT ni del Northern Territory.',
          color: Colors.deepOrange,
        );
        return;
      }

      if (result.addedCount == 0) {
        _showSnack(
          '⚠️ No s’han trobat restaurants nous.',
          color: Colors.orange,
        );
      } else {
        _showSnack(
          '✅ ${result.addedCount} restaurants afegits correctament per ${result.postcode}!',
          color: Colors.green,
        );
      }
    } catch (e) {
      _showSnack('❌ Error afegint restaurants: $e', color: Colors.red);
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
        _showSnack(
          '⚠️ No hi ha cap restaurant per eliminar.',
          color: Colors.orange,
        );
      } else {
        final doc = snapshot.docs.first;
        final name = doc['name'] ?? 'Desconegut';
        await doc.reference.delete();
        _showSnack('🗑️ Eliminat: $name', color: Colors.redAccent);
      }
    } catch (e) {
      _showSnack('❌ Error eliminant: $e', color: Colors.red);
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
          '⚠️ Només hi ha un restaurant, res per eliminar.',
          color: Colors.orange,
        );
        return;
      }

      for (var i = 1; i < snapshot.docs.length; i++) {
        await snapshot.docs[i].reference.delete();
      }

      final lastName = snapshot.docs.first['name'] ?? 'Desconegut';
      _showSnack('🧹 Tots eliminats excepte: $lastName', color: Colors.purple);
    } catch (e) {
      _showSnack('❌ Error eliminant: $e', color: Colors.red);
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _findAllRestaurantsByPostcode() async {
    final input = _postcodeController.text.trim();
    if (input.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('❌ Introdueix un codi postal.')),
      );
      return;
    }

    final String postcodeStr = input.padLeft(4, '0');
    final int? postcodeNum = int.tryParse(postcodeStr);
    if (postcodeNum == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Codi postal invàlid.')));
      return;
    }

    setState(() => _loading = true);

    try {
      final totalAdded =
          await _importService.importAllRestaurantsForPostcode(postcodeStr);

      if (totalAdded == 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '⚠️ No s’han trobat nous restaurants per $postcodeStr.',
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '✅ S’han afegit $totalAdded restaurants per $postcodeStr!',
            ),
            backgroundColor: Colors.green.shade700,
          ),
        );
      }
    } catch (e) {
      print('❌ Error en la cerca massiva: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ Error cercant tots els restaurants: $e')),
      );
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestió de restaurants',
            style: TextStyle(fontWeight: FontWeight.bold)),
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
                'Comprova si un codi postal és\nREGIONAL o REMOT',
                style: TextStyle(
                    fontSize: 22, fontWeight: FontWeight.w800, height: 1.4),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 25),
              TextField(
                controller: _postcodeController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Introdueix codi postal',
                  border:
                      OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
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
                    label: const Text('Afegir restaurant'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green.shade600,
                      foregroundColor: Colors.white,
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: _deleteLastRestaurant,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Eliminar últim'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                      foregroundColor: Colors.white,
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: _deleteAllExceptLast,
                    icon: const Icon(Icons.cleaning_services),
                    label: const Text('Eliminar tots menys l’últim'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepPurple,
                      foregroundColor: Colors.white,
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: _findAllRestaurantsByPostcode,
                    icon: const Icon(Icons.search_rounded),
                    label: const Text('Afegir tots els del codi postal'),
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
