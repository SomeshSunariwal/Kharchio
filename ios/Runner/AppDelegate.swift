import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var settingsChannel: FlutterMethodChannel?
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let channel = FlutterMethodChannel(
      name: "com.expense.kharchio/settings",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    channel.setMethodCallHandler { call, result in
      let key = "appearance.themeMode"
      switch call.method {
      case "getSettings":
        result([
          "themeMode": UserDefaults.standard.string(forKey: key) ?? "system",
          "currency": UserDefaults.standard.string(forKey: "preferences.currency") ?? "INR",
          "speechLanguage": UserDefaults.standard.string(forKey: "preferences.speechLanguage") ?? "auto",
          "categories": UserDefaults.standard.string(forKey: "preferences.categories") ?? "[]"
        ])
      case "setPreference":
        guard let args = call.arguments as? [String: Any],
              let preference = args["key"] as? String,
              let value = args["value"] as? String,
              (preference == "currency" && ["INR", "USD"].contains(value)) ||
              (preference == "speechLanguage" && ["auto", "hi", "en", "hinglish"].contains(value)) ||
              (preference == "categories" && value.utf8.count <= 65536 &&
               ((try? JSONSerialization.jsonObject(with: Data(value.utf8))) as? [String: Any])?["items"] is [Any]) else {
          result(FlutterError(code: "INVALID_PREFERENCE", message: "Unsupported preference value.", details: nil))
          return
        }
        UserDefaults.standard.set(value, forKey: "preferences." + preference)
        result(nil)
      case "getThemeMode":
        result(UserDefaults.standard.string(forKey: key) ?? "system")
      case "setThemeMode":
        guard let args = call.arguments as? [String: Any],
              let mode = args["value"] as? String,
              ["system", "dark", "light"].contains(mode) else {
          result(FlutterError(code: "INVALID_THEME", message: "Choose system, dark, or light.", details: nil))
          return
        }
        UserDefaults.standard.set(mode, forKey: key)
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    settingsChannel = channel
  }
}
