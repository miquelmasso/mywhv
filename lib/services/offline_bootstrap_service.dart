import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';

import 'offline_state.dart';
import 'farm_sqlite_store.dart';
import 'harvest_places_sqlite_store.dart';
import 'restaurant_sqlite_store.dart';
import 'visa_postcodes_sqlite_store.dart';

class OfflineBootstrapService {
  OfflineBootstrapService._();
  static final OfflineBootstrapService instance = OfflineBootstrapService._();

  static const _prefsFirstLaunchKey = 'first_launch_completed_v2';
  Future<void>? _initFuture;

  Future<void> init() {
    return _initFuture ??= _initInternal();
  }

  Future<void> _initInternal() async {
    final prefs = await SharedPreferences.getInstance();
    final farmStore = FarmSqliteStore.instance;
    final harvestStore = HarvestPlacesSqliteStore.instance;
    final store = RestaurantSqliteStore.instance;
    final visaStore = VisaPostcodesSqliteStore.instance;

    final connectivity = await Connectivity().checkConnectivity();
    final hasInternet = connectivity.any((r) => r != ConnectivityResult.none);

    final wasCompleted = prefs.getBool(_prefsFirstLaunchKey) ?? false;
    OfflineState.instance.isFirstLaunchDone = wasCompleted;
    OfflineState.instance.isOfflineMode = !hasInternet;

    await Future.wait<void>([
      _prepareStore(
        init: farmStore.init,
        importSeedIfEmpty: farmStore.importSeedAssetIfEmpty,
      ),
      _prepareStore(
        init: harvestStore.init,
        importSeedIfEmpty: harvestStore.importSeedAssetIfEmpty,
      ),
      _prepareStore(
        init: store.init,
        importSeedIfEmpty: store.importSeedAssetIfEmpty,
      ),
      _prepareStore(
        init: visaStore.init,
        importSeedIfEmpty: visaStore.importSeedAssetIfEmpty,
      ),
      _ensureTileCacheDirectory(),
    ]);

    if (!wasCompleted && await store.hasData) {
      await prefs.setBool(_prefsFirstLaunchKey, true);
      OfflineState.instance.isFirstLaunchDone = true;
    }
  }

  Future<void> _prepareStore({
    required Future<void> Function() init,
    required Future<void> Function() importSeedIfEmpty,
  }) async {
    await init();
    await importSeedIfEmpty();
  }

  Future<void> _ensureTileCacheDirectory() async {
    final dir = await getApplicationSupportDirectory();
    final tilesDir = Directory(p.join(dir.path, 'osm_tiles'));
    if (!tilesDir.existsSync()) {
      await tilesDir.create(recursive: true);
    }
    OfflineState.instance.tileCachePath = tilesDir.path;
  }
}
