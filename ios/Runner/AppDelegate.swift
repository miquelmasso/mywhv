import UIKit
import Flutter
import FirebaseCore

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let runtimeDeviceChannelName = "workyday/runtime_device"
  private let locationSettingsChannelName = "workyday/location_settings"

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Inicialitza Firebase
    FirebaseApp.configure()

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    let registry = engineBridge.pluginRegistry
    GeneratedPluginRegistrant.register(with: registry)
    registerMethodChannels(with: registry)
  }

  private func registerMethodChannels(with registry: FlutterPluginRegistry) {
    if let runtimeRegistrar = registry.registrar(forPlugin: runtimeDeviceChannelName) {
      let runtimeChannel = FlutterMethodChannel(
        name: runtimeDeviceChannelName,
        binaryMessenger: runtimeRegistrar.messenger()
      )
      runtimeChannel.setMethodCallHandler { call, result in
        switch call.method {
        case "isIosSimulator":
          #if targetEnvironment(simulator)
          result(true)
          #else
          result(false)
          #endif
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }
    if let locationSettingsRegistrar = registry.registrar(forPlugin: locationSettingsChannelName) {
      let locationSettingsChannel = FlutterMethodChannel(
        name: locationSettingsChannelName,
        binaryMessenger: locationSettingsRegistrar.messenger()
      )
      locationSettingsChannel.setMethodCallHandler { call, result in
        switch call.method {
        case "openLocationPermissionSettings":
          guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else {
            result(false)
            return
          }
          guard UIApplication.shared.canOpenURL(settingsURL) else {
            result(false)
            return
          }
          UIApplication.shared.open(settingsURL, options: [:]) { success in
            result(success)
          }
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }
  }
}
