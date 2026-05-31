import 'package:flutter_test/flutter_test.dart';
import 'package:huxi_zen/src/features/breathing/breathing_models.dart';

void main() {
  test('default breathing rhythm maps to a repeating haptic pattern', () {
    const rhythm = BreathingRhythm.defaultBreath();

    final pattern = rhythm.toBackgroundHapticPattern(
      patternId: 'default-breath',
    );

    expect(pattern.patternId, 'default-breath');
    expect(pattern.repeat, isTrue);
    expect(pattern.cycles, 0);
    expect(pattern.phases.map((phase) => phase.label), ['inhale', 'exhale']);
    expect(pattern.phases.map((phase) => phase.durationMs), [5000, 5000]);
    expect(pattern.phases.every((phase) => phase.vibrateMs > 0), isTrue);
  });

  test('custom exercise rhythm skips zero phases and preserves cycles', () {
    const rhythm = BreathingRhythm.defaultExercise();

    final pattern = rhythm.toBackgroundHapticPattern(patternId: 'custom-478');

    expect(pattern.cycles, 8);
    expect(pattern.phases.map((phase) => phase.label), [
      'inhale',
      'hold-after-inhale',
      'exhale',
    ]);
    expect(pattern.phases.map((phase) => phase.durationMs), [4000, 7000, 8000]);
    expect(pattern.phases[0].vibrateMs, greaterThan(0));
    expect(pattern.phases[1].vibrateMs, 0);
    expect(
      pattern.phases[2].vibrateMs,
      greaterThan(pattern.phases[0].vibrateMs),
    );
  });

  test('haptics can be disabled while keeping phase timing', () {
    const rhythm = BreathingRhythm(
      inhaleSeconds: 3,
      holdAfterInhaleSeconds: 1,
      exhaleSeconds: 6,
      holdAfterExhaleSeconds: 2,
      cycles: 3,
    );

    final pattern = rhythm.toBackgroundHapticPattern(
      patternId: 'silent-breath',
      hapticsEnabled: false,
    );

    expect(pattern.cycles, 3);
    expect(pattern.phases, hasLength(4));
    expect(pattern.phases.every((phase) => phase.vibrateMs == 0), isTrue);
  });
}
