import 'package:flutter/services.dart';

class RuntimeDeviceService {
  RuntimeDeviceService._();

  static final RuntimeDeviceService instance = RuntimeDeviceService._();
  static const MethodChannel _channel = MethodChannel(
    'workyday/runtime_device',
  );

  bool _isIosSimulator = false;

  bool get isIosSimulator => _isIosSimulator;

  Future<void> init() async {
    try {
      _isIosSimulator =
          await _channel.invokeMethod<bool>('isIosSimulator') ?? false;
    } on MissingPluginException {
      _isIosSimulator = false;
    } on PlatformException {
      _isIosSimulator = false;
    }
  }
}
