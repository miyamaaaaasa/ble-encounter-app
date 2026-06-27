import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate {

  // Strong references prevent ARC from deallocating channels
  private var bleAdvertiserChannel: BleAdvertiserChannel?
  private var gattPlugin: GattPlugin?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self
    }

    // Must register plugins before super.application() starts the engine
    GeneratedPluginRegistrant.register(with: self)
    let result = super.application(application, didFinishLaunchingWithOptions: launchOptions)

    // Setup custom method channels after super.application() creates the window
    setupChannels()

    return result
  }

  private func setupChannels() {
    // FlutterAppDelegate exposes the window property; the root VC is set by Main.storyboard
    guard let controller = window?.rootViewController as? FlutterViewController else {
      // Fallback: try to find any FlutterViewController in the hierarchy
      if let vc = findFlutterViewController(in: window?.rootViewController) {
        bleAdvertiserChannel = BleAdvertiserChannel(messenger: vc.binaryMessenger)
        gattPlugin = GattPlugin(messenger: vc.binaryMessenger)
      }
      return
    }
    bleAdvertiserChannel = BleAdvertiserChannel(messenger: controller.binaryMessenger)
    gattPlugin = GattPlugin(messenger: controller.binaryMessenger)
  }

  private func findFlutterViewController(in vc: UIViewController?) -> FlutterViewController? {
    guard let vc = vc else { return nil }
    if let fvc = vc as? FlutterViewController { return fvc }
    for child in vc.children {
      if let found = findFlutterViewController(in: child) { return found }
    }
    return nil
  }

  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    if #available(iOS 14.0, *) {
      completionHandler([.banner, .sound, .badge])
    } else {
      completionHandler([.alert, .sound, .badge])
    }
  }
}
