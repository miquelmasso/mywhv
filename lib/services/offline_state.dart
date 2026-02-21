class OfflineState {
  OfflineState._();
  static final OfflineState instance = OfflineState._();

  bool isOfflineMode = false;
  bool isFirstLaunchDone = false;
  String? tileCachePath;
}
