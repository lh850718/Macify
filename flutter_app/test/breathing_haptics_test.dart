import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huxi_zen/src/features/breathing/breathing_haptics.dart';
import 'package:huxi_zen/src/features/breathing/breathing_models.dart';
import 'package:huxi_zen/src/platform/background_audio_service.dart';

void main() {
  test('starts the default haptic rhythm', () async {
    final bridge = _FakeBackgroundAudioBridge();
    final controller = BreathingHapticController(bridge: bridge);

    final started = await controller.startDefault();

    expect(started, isTrue);
    expect(bridge.startedPatterns.single.patternId, 'default-breath');
    expect(bridge.startedPatterns.single.cycles, 0);
    expect(bridge.startedPatterns.single.phases.map((phase) => phase.label), [
      'inhale',
      'exhale',
    ]);
  });

  test('starts a finite custom exercise rhythm', () async {
    final bridge = _FakeBackgroundAudioBridge();
    final controller = BreathingHapticController(bridge: bridge);

    final started = await controller.startExercise(
      rhythm: const BreathingRhythm(
        inhaleSeconds: 4,
        holdAfterInhaleSeconds: 7,
        exhaleSeconds: 8,
        holdAfterExhaleSeconds: 0,
        cycles: 6,
      ),
    );

    expect(started, isTrue);
    final pattern = bridge.startedPatterns.single;
    expect(pattern.patternId, 'custom-exercise');
    expect(pattern.cycles, 6);
    expect(pattern.phases.map((phase) => phase.durationMs), [4000, 7000, 8000]);
  });

  test('disabled haptics stop any running pattern', () async {
    final bridge = _FakeBackgroundAudioBridge();
    final controller = BreathingHapticController(bridge: bridge);

    final stopped = await controller.startDefault(enabled: false);

    expect(stopped, isTrue);
    expect(bridge.startedPatterns, isEmpty);
    expect(bridge.stopHapticsCount, 1);
  });

  test('plays custom exercise completion haptic through the bridge', () async {
    final bridge = _FakeBackgroundAudioBridge();
    final controller = BreathingHapticController(bridge: bridge);

    final played = await controller.playCompletion();

    expect(played, isTrue);
    expect(bridge.completionHapticCount, 1);
  });

  test('missing platform plugin is reported as unavailable', () async {
    final controller = BreathingHapticController(
      bridge: _MissingPluginBackgroundAudioBridge(),
    );

    await expectLater(controller.startDefault(), completion(isFalse));
    await expectLater(controller.stop(), completion(isFalse));
    await expectLater(controller.playCompletion(), completion(isFalse));
  });
}

class _FakeBackgroundAudioBridge extends BackgroundAudioServiceBridge {
  final startedPatterns = <BackgroundHapticPattern>[];
  var stopHapticsCount = 0;
  var completionHapticCount = 0;

  @override
  Future<bool> startHapticPattern({
    required BackgroundHapticPattern pattern,
  }) async {
    startedPatterns.add(pattern);
    return true;
  }

  @override
  Future<bool> stopHaptics() async {
    stopHapticsCount += 1;
    return true;
  }

  @override
  Future<bool> playCompletionHaptic() async {
    completionHapticCount += 1;
    return true;
  }
}

class _MissingPluginBackgroundAudioBridge extends BackgroundAudioServiceBridge {
  @override
  Future<bool> startHapticPattern({required BackgroundHapticPattern pattern}) {
    throw MissingPluginException();
  }

  @override
  Future<bool> stopHaptics() {
    throw MissingPluginException();
  }

  @override
  Future<bool> playCompletionHaptic() {
    throw MissingPluginException();
  }
}
