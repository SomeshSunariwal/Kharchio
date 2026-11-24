import Flutter
import Network
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var settingsChannel: FlutterMethodChannel?
  private var subscriptionChannel: FlutterMethodChannel?
  private var subscriptionTap: [String: Any]?
  private let subscriptionNotifications = SubscriptionNotifications()
  private let networkConnectivity = NetworkConnectivityStream()
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let center = UNUserNotificationCenter.current()
    subscriptionNotifications.fallback = center.delegate
    subscriptionNotifications.open = { [weak self] id, day in
      guard let self = self else { return }
      self.subscriptionTap = ["planId": id, "dueDay": day]
      self.subscriptionChannel?.invokeMethod("reminderTapped", arguments: nil)
    }
    center.delegate = subscriptionNotifications
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let messenger = engineBridge.applicationRegistrar.messenger()
    FlutterEventChannel(name: "com.somesh.kharchio/network", binaryMessenger: messenger)
      .setStreamHandler(networkConnectivity)
    let reminders = FlutterMethodChannel(
      name: "com.somesh.kharchio/subscription_reminders", binaryMessenger: messenger
    )
    reminders.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { result(nil); return }
      let center = UNUserNotificationCenter.current()
      switch call.method {
      case "consumeTap":
        let tap = self.subscriptionTap
        self.subscriptionTap = nil
        result(tap)
      case "hasPermission":
        center.getNotificationSettings { settings in
          result(settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional)
        }
      case "requestPermission":
        center.getNotificationSettings { settings in
          if settings.authorizationStatus == .denied {
            DispatchQueue.main.async {
              if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
              }
              result(nil)
            }
          } else {
            center.requestAuthorization(options: [.alert, .sound]) { _, error in
              if let error = error {
                result(FlutterError(code: "REMINDER_PERMISSION", message: error.localizedDescription, details: nil))
              } else {
                result(nil)
              }
            }
          }
        }
      case "replaceReminders":
        guard let json = call.arguments as? String,
              let entries = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [[String: Any]] else {
          result(FlutterError(code: "INVALID_REMINDERS", message: "Could not read reminders.", details: nil))
          return
        }
        self.replaceSubscriptionReminders(entries, result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    subscriptionChannel = reminders
    let channel = FlutterMethodChannel(
      name: "com.somesh.kharchio/settings",
      binaryMessenger: messenger
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

  private func replaceSubscriptionReminders(_ entries: [[String: Any]], result: @escaping FlutterResult) {
    let center = UNUserNotificationCenter.current()
    center.getNotificationSettings { settings in
      guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
        result(nil)
        return
      }
      center.getPendingNotificationRequests { pending in
        DispatchQueue.main.async {
          let trackingKey = "subscriptionReminderTimes"
          let now = Date().timeIntervalSince1970
          let calendar = Calendar(identifier: .gregorian)
          let existing = UserDefaults.standard.dictionary(forKey: trackingKey) as? [String: Double] ?? [:]
          var tracking = existing.filter { $0.value <= now && $0.value > now - 365 * 86400 }
          var requests: [UNNotificationRequest] = []
          for entry in entries {
            guard let id = entry["id"] as? String, let message = entry["message"] as? String,
                  let plan = entry["planId"] as? String, let dueDay = entry["dueDay"] as? Int else { continue }
            let identifier = SubscriptionNotifications.prefix + id
            if tracking[identifier] != nil { continue }
            let date = DateComponents(calendar: calendar, year: entry["year"] as? Int,
                                      month: entry["month"] as? Int, day: entry["day"] as? Int,
                                      hour: entry["hour"] as? Int, minute: entry["minute"] as? Int)
            let trigger = UNCalendarNotificationTrigger(dateMatching: date, repeats: false)
            guard let scheduled = trigger.nextTriggerDate(), scheduled.timeIntervalSince1970 > now else { continue }
            let content = UNMutableNotificationContent()
            content.title = "Subscription reminder"
            content.body = message
            content.sound = .default
            content.userInfo = ["planId": plan, "dueDay": dueDay]
            tracking[identifier] = scheduled.timeIntervalSince1970
            requests.append(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
          }
          let desired = Set(requests.map(\.identifier))
          center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter {
            $0.hasPrefix(SubscriptionNotifications.prefix) && !desired.contains($0)
          })
          let group = DispatchGroup()
          var failure: Error?
          for request in requests {
            group.enter()
            center.add(request) { error in
              DispatchQueue.main.async {
                if let error = error {
                  failure = error
                  tracking.removeValue(forKey: request.identifier)
                }
                group.leave()
              }
            }
          }
          group.notify(queue: .main) {
            UserDefaults.standard.set(tracking, forKey: trackingKey)
            if let failure = failure {
              result(FlutterError(code: "REMINDER_SCHEDULE", message: failure.localizedDescription, details: nil))
            } else {
              result(nil)
            }
          }
        }
      }
    }
  }
}

private final class SubscriptionNotifications: NSObject, UNUserNotificationCenterDelegate {
  static let prefix = "subscription:"
  weak var fallback: UNUserNotificationCenterDelegate?
  var open: ((String, Int) -> Void)?

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    if notification.request.identifier.hasPrefix(Self.prefix) {
      completionHandler([.banner, .list, .sound])
    } else if fallback?.responds(to: #selector(userNotificationCenter(_:willPresent:withCompletionHandler:))) == true {
      fallback?.userNotificationCenter?(center, willPresent: notification, withCompletionHandler: completionHandler)
    } else {
      completionHandler([])
    }
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    let request = response.notification.request
    if request.identifier.hasPrefix(Self.prefix) {
      if response.actionIdentifier == UNNotificationDefaultActionIdentifier,
         let id = request.content.userInfo["planId"] as? String,
         let day = request.content.userInfo["dueDay"] as? Int {
        DispatchQueue.main.async { self.open?(id, day) }
      }
      completionHandler()
    } else if fallback?.responds(to: #selector(userNotificationCenter(_:didReceive:withCompletionHandler:))) == true {
      fallback?.userNotificationCenter?(center, didReceive: response, withCompletionHandler: completionHandler)
    } else {
      completionHandler()
    }
  }
}

private final class NetworkConnectivityStream: NSObject, FlutterStreamHandler {
  private var monitor: NWPathMonitor?
  private let queue = DispatchQueue(label: "com.somesh.kharchio.network")

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    monitor?.cancel()
    let current = NWPathMonitor()
    monitor = current
    current.pathUpdateHandler = { [weak self, weak current] path in
      let connected = path.status == .satisfied
      DispatchQueue.main.async {
        guard let current = current, self?.monitor === current else { return }
        events(connected)
      }
    }
    current.start(queue: queue)
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    monitor?.cancel()
    monitor = nil
    return nil
  }
}
