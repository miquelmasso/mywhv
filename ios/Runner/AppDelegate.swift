import UIKit
import Flutter
import GoogleMaps
import FirebaseCore

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Inicialitza Firebase
    FirebaseApp.configure()

    // Inicialitza Google Maps
    GMSServices.provideAPIKey("AIzaSyCq0y5wPxOt9oZR6Z0-b0fR5fmQq3BiivI") // Substitueix amb la teva clau d'API

    // Registra tots els plugins (important!)
    GeneratedPluginRegistrant.register(with: self)

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
