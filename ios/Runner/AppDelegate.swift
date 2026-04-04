import UIKit
import Flutter
import FirebaseCore

@main
@objc class AppDelegate: FlutterAppDelegate {
  private let runtimeDeviceChannelName = "workyday/runtime_device"

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Inicialitza Firebase
    FirebaseApp.configure()

    // Registra tots els plugins (important!)
    GeneratedPluginRegistrant.register(with: self)
    if let runtimeRegistrar = registrar(forPlugin: runtimeDeviceChannelName) {
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

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
