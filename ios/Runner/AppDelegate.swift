import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var sharedTextChannel: FlutterMethodChannel?
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    guard let registrar = engineBridge.pluginRegistry.registrar(
      forPlugin: "NimbleClipSharedIntent"
    ) else {
      assertionFailure("Unable to create the shared-intent plugin registrar")
      return
    }
    sharedTextChannel = FlutterMethodChannel(
      name: "com.vannt.nimbleclip/shared_intent",
      binaryMessenger: registrar.messenger()
    )
    sharedTextChannel?.setMethodCallHandler { call, result in
      guard call.method == "consumeSharedText" else {
        result(FlutterMethodNotImplemented)
        return
      }
      let defaults = UserDefaults(suiteName: "group.com.vannt.nimbleclip")
      let text = defaults?.string(forKey: "sharedText")
      defaults?.removeObject(forKey: "sharedText")
      result(text)
    }
  }
}
