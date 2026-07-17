import AVFoundation
import AudioToolbox
import CoreHaptics
import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  private var platformCapabilityChannel: FlutterMethodChannel?
  private var backgroundAudioChannel: FlutterMethodChannel?
  private var hapticTimer: Timer?
  private var hapticCueTimers: [Timer] = []
  private var hapticPattern: IOSHapticPattern?
  private var hapticPhaseIndex = 0
  private var hapticCompletedCycles = 0
  private static let miniProgramInhaleHapticCues: [(atMs: Int, style: IOSSystemHapticStyle)] = [
    (0, .light),
    (320, .light),
    (620, .light),
    (900, .light),
    (1160, .light),
    (1400, .light),
    (1620, .medium),
    (1830, .medium),
    (2050, .medium),
    (2300, .medium),
    (2580, .medium),
    (2890, .heavy),
    (3230, .heavy),
    (3590, .heavy),
    (3970, .heavy),
  ]

  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)
    _ = Self.configurePlaybackAudioSession()
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

    backgroundAudioChannel = FlutterMethodChannel(
      name: "huxi_zen/background_audio",
      binaryMessenger: controller.binaryMessenger
    )
    backgroundAudioChannel?.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "start", "sync":
        result(false)
      case "stop":
        self?.stopHapticPattern()
        result(true)
      case "startHapticPattern":
        result(self?.startHapticPattern(call.arguments) ?? false)
      case "stopHaptics":
        self?.stopHapticPattern()
        result(true)
      case "playCompletionHaptic":
        result(self?.playCompletionHaptic() ?? false)
      case "status":
        result(self?.backgroundAudioStatus() ?? Self.emptyBackgroundAudioStatus())
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
      try AVAudioSession.sharedInstance().setActive(true)
      return true
    } catch {
      return false
    }
  }

  private static func pulseHaptic() -> Bool {
    pulseSystemHaptic(.light)
    return true
  }

  private func startHapticPattern(_ arguments: Any?) -> Bool {
    guard
      let arguments = arguments as? [String: Any],
      let patternJson = arguments["patternJson"] as? String,
      let data = patternJson.data(using: .utf8),
      let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let pattern = IOSHapticPattern(json: raw),
      !pattern.phases.isEmpty
    else {
      return false
    }

    hapticPattern = pattern
    hapticPhaseIndex = 0
    hapticCompletedCycles = 0
    scheduleHapticPhase()
    return true
  }

  private func scheduleHapticPhase() {
    guard let pattern = hapticPattern, !pattern.phases.isEmpty else {
      stopHapticPattern()
      return
    }

    hapticTimer?.invalidate()
    cancelHapticCueTimers()
    hapticPhaseIndex = min(max(0, hapticPhaseIndex), pattern.phases.count - 1)
    let phase = pattern.phases[hapticPhaseIndex]
    if shouldPulseHoldToExhaleTransition(pattern: pattern, phase: phase) {
      pulseBubblePopHaptic()
    }
    if phase.vibrateMs > 0 && phase.label == "inhale" {
      scheduleMiniProgramInhaleHaptics(durationMs: phase.durationMs)
    }

    let interval = max(0.05, Double(max(1, phase.durationMs)) / 1000.0)
    let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
      self?.advanceHapticPhase()
    }
    hapticTimer = timer
    RunLoop.main.add(timer, forMode: .common)
  }

  private func advanceHapticPhase() {
    guard let pattern = hapticPattern else { return }
    let nextIndex = hapticPhaseIndex + 1
    if nextIndex < pattern.phases.count {
      hapticPhaseIndex = nextIndex
      scheduleHapticPhase()
      return
    }

    hapticCompletedCycles += 1
    let shouldRepeat = pattern.repeatPattern
      && (pattern.cycles <= 0 || hapticCompletedCycles < pattern.cycles)
    if shouldRepeat {
      hapticPhaseIndex = 0
      scheduleHapticPhase()
    } else {
      stopHapticPattern()
    }
  }

  private func stopHapticPattern() {
    hapticTimer?.invalidate()
    hapticTimer = nil
    cancelHapticCueTimers()
    hapticPattern = nil
    hapticPhaseIndex = 0
    hapticCompletedCycles = 0
  }

  private func cancelHapticCueTimers() {
    hapticCueTimers.forEach { $0.invalidate() }
    hapticCueTimers.removeAll()
  }

  private func backgroundAudioStatus() -> [String: Any] {
    [
      "platform": "ios",
      "mediaSessionServiceDeclared": false,
      "running": false,
      "trackCount": 0,
      "lastCommand": hapticPattern == nil ? "" : "haptic-phase",
      "primaryUri": "",
      "playbackState": "",
      "lastError": "",
      "activeChannelIds": [],
      "hapticsRunning": hapticPattern != nil,
      "hapticPatternId": hapticPattern?.patternId ?? "",
      "hapticPhase": currentHapticPhase()?.label ?? "",
      "hapticPhaseIndex": hapticPattern == nil ? -1 : hapticPhaseIndex,
    ]
  }

  private static func emptyBackgroundAudioStatus() -> [String: Any] {
    [
      "platform": "ios",
      "mediaSessionServiceDeclared": false,
      "running": false,
      "trackCount": 0,
      "lastCommand": "",
      "primaryUri": "",
      "playbackState": "",
      "lastError": "",
      "activeChannelIds": [],
      "hapticsRunning": false,
      "hapticPatternId": "",
      "hapticPhase": "",
      "hapticPhaseIndex": -1,
    ]
  }

  private func currentHapticPhase() -> IOSHapticPhase? {
    guard let pattern = hapticPattern, pattern.phases.indices.contains(hapticPhaseIndex) else {
      return nil
    }
    return pattern.phases[hapticPhaseIndex]
  }

  private func scheduleMiniProgramInhaleHaptics(durationMs: Int) {
    let scale = max(0.2, Double(durationMs) / 5000.0)
    hapticCueTimers = Self.miniProgramInhaleHapticCues.compactMap { cue in
      let interval = max(0.0, Double(cue.atMs) * scale / 1000.0)
      if interval <= 0 {
        Self.pulseSystemHaptic(cue.style)
        return nil
      }
      let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
        guard self?.currentHapticPhase()?.label == "inhale" else { return }
        Self.pulseSystemHaptic(cue.style)
      }
      RunLoop.main.add(timer, forMode: .common)
      return timer
    }
  }

  private func shouldPulseHoldToExhaleTransition(
    pattern: IOSHapticPattern,
    phase: IOSHapticPhase
  ) -> Bool {
    guard phase.vibrateMs > 0, phase.label == "exhale" else { return false }
    let previousIndex = hapticPhaseIndex == 0 ? pattern.phases.count - 1 : hapticPhaseIndex - 1
    guard pattern.phases.indices.contains(previousIndex) else { return false }
    return pattern.phases[previousIndex].label == "hold-after-inhale"
  }

  private func pulseBubblePopHaptic() {
    Self.pulseSystemHaptic(.light)
    let timer = Timer(timeInterval: 0.08, repeats: false) { [weak self] _ in
      guard self?.currentHapticPhase()?.label == "exhale" else { return }
      Self.pulseSystemHaptic(.light)
    }
    hapticCueTimers.append(timer)
    RunLoop.main.add(timer, forMode: .common)
  }

  private func playCompletionHaptic() -> Bool {
    cancelHapticCueTimers()
    Self.pulseLongCompletionHaptic()
    let timer = Timer(timeInterval: 0.62, repeats: false) { _ in
      Self.pulseLongCompletionHaptic()
    }
    hapticCueTimers.append(timer)
    RunLoop.main.add(timer, forMode: .common)
    return true
  }

  private static func pulseLongCompletionHaptic() {
    AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
    pulseSystemHaptic(.heavy)
  }

  private static func pulseSystemHaptic(_ style: IOSSystemHapticStyle) {
    switch style {
    case .light:
      let generator = UISelectionFeedbackGenerator()
      generator.prepare()
      generator.selectionChanged()
    case .medium:
      let generator = UIImpactFeedbackGenerator(style: .medium)
      generator.prepare()
      generator.impactOccurred()
    case .heavy:
      let generator = UIImpactFeedbackGenerator(style: .heavy)
      generator.prepare()
      generator.impactOccurred()
    }
  }
}

private enum IOSSystemHapticStyle {
  case light
  case medium
  case heavy
}

private struct IOSHapticPattern {
  let patternId: String
  let repeatPattern: Bool
  let cycles: Int
  let phases: [IOSHapticPhase]

  init?(json: [String: Any]) {
    patternId = json["patternId"] as? String ?? ""
    repeatPattern = json["repeat"] as? Bool ?? true
    cycles = json["cycles"] as? Int ?? 0
    let rawPhases = json["phases"] as? [[String: Any]] ?? []
    phases = rawPhases.compactMap(IOSHapticPhase.init(json:))
    if phases.isEmpty { return nil }
  }
}

private struct IOSHapticPhase {
  let label: String
  let durationMs: Int
  let vibrateMs: Int

  init?(json: [String: Any]) {
    label = json["label"] as? String ?? ""
    durationMs = json["durationMs"] as? Int ?? 0
    vibrateMs = json["vibrateMs"] as? Int ?? 0
    if durationMs <= 0 { return nil }
  }
}
