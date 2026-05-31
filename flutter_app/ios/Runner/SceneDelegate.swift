import AVFoundation
import CoreHaptics
import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  private var platformCapabilityChannel: FlutterMethodChannel?

  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)
    guard let controller = window?.rootViewController as? FlutterViewController else {
      return
    }
    platformCapabilityChannel = FlutterMethodChannel(
      name: "huxi_zen/platform_capabilities",
      binaryMessenger: controller.binaryMessenger
    )
    platformCapabilityChannel?.setMethodCallHandler { call, result in
      switch call.method {
      case "capabilityReport":
        result(Self.capabilityReport())
      case "pulseHaptic":
        result(Self.pulseHaptic())
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private static func capabilityReport() -> [String: Any] {
    let backgroundModes =
      Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String] ?? []
    let audioSessionConfigured = configurePlaybackAudioSession()
    let supportsHaptics: Bool
    if #available(iOS 13.0, *) {
      supportsHaptics = CHHapticEngine.capabilitiesForHardware().supportsHaptics
    } else {
      supportsHaptics = false
    }

    return [
      "platform": "ios",
      "osVersion": UIDevice.current.systemVersion,
      "sdkInt": 0,
      "backgroundAudioModeDeclared": backgroundModes.contains("audio"),
      "foregroundServicePermissionDeclared": false,
      "mediaPlaybackForegroundServicePermissionDeclared": false,
      "postNotificationsPermissionDeclared": false,
      "vibrationPermissionDeclared": false,
      "hapticsAvailable": supportsHaptics,
      "vibrationAvailable": supportsHaptics,
      "amplitudeControlAvailable": supportsHaptics,
      "backgroundVibrationRequiresForegroundService": false,
      "audioSessionPlaybackCategoryConfigured": audioSessionConfigured,
      "notes": [
        "iOS background audio requires UIBackgroundModes audio and an active playback audio session.",
        "iOS background haptics should be treated as unsupported unless a device test proves otherwise.",
      ],
    ]
  }

  private static func configurePlaybackAudioSession() -> Bool {
    do {
      try AVAudioSession.sharedInstance().setCategory(
        .playback,
        mode: .default,
        options: [.mixWithOthers]
      )
      return true
    } catch {
      return false
    }
  }

  private static func pulseHaptic() -> Bool {
    let generator = UIImpactFeedbackGenerator(style: .soft)
    generator.prepare()
    generator.impactOccurred()
    return true
  }
}
