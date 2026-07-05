import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/google_places_service.dart';
import '../services/map_markers_service.dart';
import '../services/osm_restaurant_import_service.dart';
import '../services/restaurant_import_service.dart';
import '../services/restaurant_sqlite_store.dart';
import '../services/visa_postcodes_sqlite_store.dart';

class AddRestaurantsByPostcodePage extends StatefulWidget {
  const AddRestaurantsByPostcodePage({super.key});

  @override
  State<AddRestaurantsByPostcodePage> createState() =>
      _AddRestaurantsByPostcodePageState();
}

class _AddRestaurantsByPostcodePageState
    extends State<AddRestaurantsByPostcodePage> {
  static const _lastOsmImportPostcodeKey = 'last_osm_import_postcode';

  final TextEditingController _postcodeController = TextEditingController(
    text: '4802',
  );
  String _result = '';
  String _restaurantName = '';
  String? _lastOsmImportPostcode;
  bool _loading = false;
  bool _forceOsmRefresh = false;
  bool _enrichOsmContacts = true;

  final _firestore = FirebaseFirestore.instance;
  final _placesService = GooglePlacesService();
  final OsmRestaurantImportService _osmImportService =
      OsmRestaurantImportService();
  final RestaurantImportService _importService = RestaurantImportService();
  final VisaPostcodesSqliteStore _visaStore = VisaPostcodesSqliteStore.instance;

  @override
  void initState() {
    super.initState();
    _loadLastOsmImportPostcode();
  }

  @override
  void dispose() {
    _postcodeController.dispose();
    super.dispose();
  }

  Future<void> _loadLastOsmImportPostcode() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _lastOsmImportPostcode = prefs.getString(_lastOsmImportPostcodeKey);
    });
  }

  void _showSnack(String text, {Color? color}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: color ?? Colors.blueGrey.shade800,
      ),
    );
  }

  Future<void> _showOsmImportSummaryDialog(
    OsmRestaurantImportResult result,
  ) async {
    final summary = result.summary;
    final emailContacts = summary.emailContacts;
    final visibleEmailContacts = emailContacts.take(10).toList();
    final moreEmailContacts =
        emailContacts.length - visibleEmailContacts.length;

    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('OSM import summary · ${result.postcode}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _summaryRow('Found in OSM', result.discovered),
                _summaryRow('Added', result.added),
                _summaryRow('Updated', result.updated),
                _summaryRow('Duplicates skipped', result.skippedDuplicates),
                const Divider(height: 24),
                _summaryRow('Processed for contacts', summary.processed),
                _summaryRow('With website', summary.withWebsite),
                _summaryRow('With phone', summary.withPhone),
                _summaryRow('With email', summary.withEmail),
                _summaryRow('With Facebook', summary.withFacebook),
                _summaryRow('With Instagram', summary.withInstagram),
                _summaryRow('With jobs/careers', summary.withCareers),
                const Divider(height: 24),
                _summaryRow(
                  'Website searches attempted',
                  summary.websiteDiscoveryAttempted,
                ),
                _summaryRow('Websites from OSM', summary.websiteFromOsm),
                _summaryRow('Websites discovered', summary.websiteDiscovered),
                if (summary.websiteDiscovered > 0) ...[
                  Padding(
                    padding: const EdgeInsets.only(left: 12, top: 4),
                    child: Text(
                      'Wikidata: ${summary.websiteFromWikidata} · '
                      'brands: ${summary.websiteFromKnownBrand} · '
                      'domains: ${summary.websiteFromProbableDomain}',
                      style: TextStyle(
                        color: Colors.grey.shade700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Text(
                  'Restaurants with email',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                if (visibleEmailContacts.isEmpty)
                  Text(
                    'No valid email was found.',
                    style: TextStyle(color: Colors.grey.shade700),
                  )
                else
                  ...visibleEmailContacts.map(
                    (contact) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        '• ${contact.name}\n  ${contact.email}',
                        style: const TextStyle(height: 1.25),
                      ),
                    ),
                  ),
                if (moreEmailContacts > 0)
                  Text(
                    '+ $moreEmailContacts more',
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Widget _summaryRow(String label, int value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(child: Text(label)),
          const SizedBox(width: 16),
          Text(
            value.toString(),
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ],
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

  Future<void> _deleteLastPostcodeRestaurants() async {
    final fallbackPostcode = _postcodeController.text.trim().padLeft(4, '0');
    final postcode = (_lastOsmImportPostcode?.trim().isNotEmpty ?? false)
        ? _lastOsmImportPostcode!.trim().padLeft(4, '0')
        : fallbackPostcode;
    if (!RegExp(r'^\d{4}$').hasMatch(postcode)) {
      _showSnack(
        'Import a postcode from OpenStreetMap before deleting.',
        color: Colors.orange,
      );
      return;
    }

    setState(() => _loading = true);

    try {
      final store = RestaurantSqliteStore.instance;
      await store.init();
      final restaurants = await store.getAll();
      var deleted = 0;
      final remaining = <Map<String, dynamic>>[];

      for (final restaurant in restaurants) {
        final restaurantPostcode =
            (restaurant['postcode_display'] ?? restaurant['postcode'] ?? '')
                .toString()
                .padLeft(4, '0');
        final docId = (restaurant['docId'] ?? restaurant['id'] ?? '')
            .toString();
        final source = (restaurant['source'] ?? '').toString();
        final sourcePlaceId = (restaurant['source_place_id'] ?? '').toString();
        final isOsmRestaurant =
            source == 'osm' ||
            sourcePlaceId.startsWith('osm:') ||
            docId.startsWith('osm_');

        if (restaurantPostcode == postcode && isOsmRestaurant) {
          deleted++;
          continue;
        }
        remaining.add(restaurant);
      }

      if (deleted == 0) {
        _showSnack(
          'No OSM restaurants found to delete for $postcode.',
          color: Colors.orange,
        );
        return;
      }

      await MapMarkersService.replaceLocalRestaurants(remaining);
      _showSnack(
        '🗑️ Deleted $deleted OSM restaurants from postcode $postcode.',
        color: Colors.redAccent,
      );
    } catch (e) {
      _showSnack(
        'We could not delete the latest postcode restaurants right now.',
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

  Future<void> _importRestaurantsFromOsm() async {
    final input = _postcodeController.text.trim();
    if (input.isEmpty) {
      _showSnack('Enter a postcode.', color: Colors.orange);
      return;
    }

    setState(() => _loading = true);
    try {
      final result = await _osmImportService.importForPostcode(
        input,
        force: _forceOsmRefresh,
        enrichWebContacts: _enrichOsmContacts,
      );
      if (!mounted) return;

      if (result.skippedByCooldown) {
        _showSnack(
          result.message ?? 'This postcode was scanned recently.',
          color: Colors.orange,
        );
        return;
      }
      if (result.message != null && result.discovered == 0) {
        _showSnack(result.message!, color: Colors.orange);
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_lastOsmImportPostcodeKey, result.postcode);
      _lastOsmImportPostcode = result.postcode;

      if (mounted) setState(() => _loading = false);
      await _showOsmImportSummaryDialog(result);
      if (!mounted) return;

      _showSnack(
        'OSM ${result.postcode}: ${result.discovered} found, '
        '${result.added} added, ${result.updated} updated, '
        '${result.skippedDuplicates} duplicates'
        '${result.enriched > 0 ? ', ${result.enriched} enriched' : ''}.',
        color: result.added > 0 || result.updated > 0
            ? Colors.green.shade700
            : Colors.blueGrey.shade700,
      );
    } catch (error) {
      debugPrint('OSM restaurant import failed: $error');
      if (!mounted) return;
      _showSnack(
        'OpenStreetMap import failed: ${_shortOsmError(error)}',
        color: Colors.red,
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _shortOsmError(Object error) {
    final raw = error.toString();
    if (raw.contains('All Overpass endpoints failed')) {
      return 'OSM/Overpass is unavailable. Try Force rescan later.';
    }
    if (raw.contains('Nominatim returned')) {
      return 'postcode location service unavailable.';
    }
    if (raw.length <= 120) return raw;
    return '${raw.substring(0, 120)}...';
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
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF4F8F5),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFD5E5D9)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'OpenStreetMap import',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Uses Nominatim to locate the postcode and Overpass to find hospitality venues. No API key or billing is required.',
                      style: TextStyle(color: Colors.black54, height: 1.35),
                    ),
                    const SizedBox(height: 10),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Force rescan'),
                      subtitle: const Text(
                        'Ignore the 30-day postcode scan cache.',
                      ),
                      value: _forceOsmRefresh,
                      onChanged: _loading
                          ? null
                          : (value) => setState(() => _forceOsmRefresh = value),
                    ),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Enrich web contacts'),
                      subtitle: const Text(
                        'Uses OSM tags, Wikidata, known brands and validated probable domains, then visits official websites for email, jobs and Facebook.',
                      ),
                      value: _enrichOsmContacts,
                      onChanged: _loading
                          ? null
                          : (value) =>
                                setState(() => _enrichOsmContacts = value),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _loading ? null : _importRestaurantsFromOsm,
                        icon: const Icon(Icons.public),
                        label: const Text('Import from OpenStreetMap'),
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 50),
                          backgroundColor: const Color(0xFF4E7D5B),
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
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
                    onPressed: _deleteLastPostcodeRestaurants,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Delete latest postcode'),
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
