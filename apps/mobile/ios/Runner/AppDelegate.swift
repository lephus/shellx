import Flutter
import UIKit
import UserNotifications
import firebase_messaging

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // V2-2b B5: a UIScene app registers its plugins after this method returns, but Apple wants the
    // notification centre's delegate set before it does; without this call a tap on a notification can
    // be missed in some launch states (firebase_messaging 16.7.0 README, "iOS apps using UIScene").
    // firebase_messaging's shared instance becomes the notification centre's delegate, so no later plugin may set UNUserNotificationCenter.current().delegate.
    FLTFirebaseMessagingPlugin.configureNotificationCenterDelegate()
    AppDelegate.registerNotificationCategories()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }

  /// V2-2b B8: the buttons of an AI permission push (`aps.category` = `ai_perm`). "Deny" is the first action
  /// that is not destructive, so the double tap of an Apple Watch (which runs that one) never allows; "Allow"
  /// also needs the phone unlocked. Both open the app: the answer goes from there, after the app's own lock
  /// (B10). The only place that registers categories: a second call would replace this set.
  static func registerNotificationCategories() {
    let reject = UNNotificationAction(
      identifier: "reject",
      title: NSLocalizedString("pushActionReject", comment: "Notification button: deny the AI agent's request"),
      options: [.foreground]
    )
    let allow = UNNotificationAction(
      identifier: "allow",
      title: NSLocalizedString("pushActionAllow", comment: "Notification button: allow the AI agent's request once"),
      options: [.foreground, .authenticationRequired]
    )
    let category = UNNotificationCategory(
      identifier: "ai_perm",
      actions: [reject, allow],
      intentIdentifiers: [],
      options: []
    )
    UNUserNotificationCenter.current().setNotificationCategories([category])
  }
}
