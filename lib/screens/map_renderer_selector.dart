import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../services/runtime_device_service.dart';

enum MapRendererKind { mapLibre, vectorPmtilesFallback }

MapRendererKind resolveMapRendererKind() {
  final isIosSimulator = RuntimeDeviceService.instance.isIosSimulator;
  final useFallback =
      isIosSimulator || defaultTargetPlatform == TargetPlatform.android;

  return useFallback
      ? MapRendererKind.vectorPmtilesFallback
      : MapRendererKind.mapLibre;
}

String mapRendererLabel(MapRendererKind kind) {
  return switch (kind) {
    MapRendererKind.mapLibre => 'MapLibre',
    MapRendererKind.vectorPmtilesFallback => 'vector_map_tiles_pmtiles',
  };
}

class MapRendererSelector extends StatelessWidget {
  const MapRendererSelector({
    super.key,
    required this.rendererKind,
    required this.mapLibreBuilder,
    required this.vectorPmtilesBuilder,
  });

  final MapRendererKind rendererKind;
  final WidgetBuilder mapLibreBuilder;
  final WidgetBuilder vectorPmtilesBuilder;

  @override
  Widget build(BuildContext context) {
    return switch (rendererKind) {
      MapRendererKind.mapLibre => mapLibreBuilder(context),
      MapRendererKind.vectorPmtilesFallback => vectorPmtilesBuilder(context),
    };
  }
}
