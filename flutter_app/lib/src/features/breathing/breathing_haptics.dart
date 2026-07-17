import 'package:flutter/services.dart';

import '../../platform/background_audio_service.dart';
import 'breathing_models.dart';

class BreathingHapticController {
  const BreathingHapticController({
    this.bridge = const BackgroundAudioServiceBridge(),
  });

  final BackgroundAudioServiceBridge bridge;

  Future<bool> startDefault({bool enabled = true}) {
    return startRhythm(
      const BreathingRhythm.defaultBreath(),
      patternId: 'default-breath',
      enabled: enabled,
    );
  }

  Future<bool> startExercise({
    BreathingRhythm rhythm = const BreathingRhythm.defaultExercise(),
    bool enabled = true,
  }) {
    return startRhythm(rhythm, patternId: 'custom-exercise', enabled: enabled);
  }

  Future<bool> startRhythm(
    BreathingRhythm rhythm, {
    required String patternId,
    bool enabled = true,
  }) async {
    if (!enabled) return stop();
    try {
      return await bridge.startHapticPattern(
        pattern: rhythm.toBackgroundHapticPattern(patternId: patternId),
      );
    } on MissingPluginException {
      return false;
    }
  }

  Future<bool> stop() async {
    try {
      return await bridge.stopHaptics();
    } on MissingPluginException {
      return false;
    }
  }

  Future<bool> playCompletion() async {
    try {
      return await bridge.playCompletionHaptic();
    } on MissingPluginException {
      return false;
    }
  }
}
