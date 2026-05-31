import '../../platform/background_audio_service.dart';

enum BreathingPhaseKind { inhale, holdAfterInhale, exhale, holdAfterExhale }

class BreathingRhythm {
  const BreathingRhythm({
    required this.inhaleSeconds,
    required this.holdAfterInhaleSeconds,
    required this.exhaleSeconds,
    required this.holdAfterExhaleSeconds,
    this.cycles = 0,
  });

  const BreathingRhythm.defaultBreath()
    : inhaleSeconds = 5,
      holdAfterInhaleSeconds = 0,
      exhaleSeconds = 5,
      holdAfterExhaleSeconds = 0,
      cycles = 0;

  const BreathingRhythm.defaultExercise()
    : inhaleSeconds = 4,
      holdAfterInhaleSeconds = 7,
      exhaleSeconds = 8,
      holdAfterExhaleSeconds = 0,
      cycles = 8;

  final int inhaleSeconds;
  final int holdAfterInhaleSeconds;
  final int exhaleSeconds;
  final int holdAfterExhaleSeconds;
  final int cycles;

  bool get hasFiniteCycles => cycles > 0;

  BreathingRhythm copyWith({
    int? inhaleSeconds,
    int? holdAfterInhaleSeconds,
    int? exhaleSeconds,
    int? holdAfterExhaleSeconds,
    int? cycles,
  }) {
    return BreathingRhythm(
      inhaleSeconds: inhaleSeconds ?? this.inhaleSeconds,
      holdAfterInhaleSeconds:
          holdAfterInhaleSeconds ?? this.holdAfterInhaleSeconds,
      exhaleSeconds: exhaleSeconds ?? this.exhaleSeconds,
      holdAfterExhaleSeconds:
          holdAfterExhaleSeconds ?? this.holdAfterExhaleSeconds,
      cycles: cycles ?? this.cycles,
    );
  }

  List<BreathingPhase> get phases {
    return [
      BreathingPhase(
        kind: BreathingPhaseKind.inhale,
        label: 'inhale',
        durationSeconds: inhaleSeconds,
      ),
      BreathingPhase(
        kind: BreathingPhaseKind.holdAfterInhale,
        label: 'hold-after-inhale',
        durationSeconds: holdAfterInhaleSeconds,
      ),
      BreathingPhase(
        kind: BreathingPhaseKind.exhale,
        label: 'exhale',
        durationSeconds: exhaleSeconds,
      ),
      BreathingPhase(
        kind: BreathingPhaseKind.holdAfterExhale,
        label: 'hold-after-exhale',
        durationSeconds: holdAfterExhaleSeconds,
      ),
    ].where((phase) => phase.durationSeconds > 0).toList(growable: false);
  }

  BackgroundHapticPattern toBackgroundHapticPattern({
    required String patternId,
    bool hapticsEnabled = true,
  }) {
    return BackgroundHapticPattern(
      patternId: patternId,
      repeat: true,
      cycles: cycles,
      phases: phases
          .map((phase) {
            final pulse = hapticsEnabled && phase.isBreathingMotion;
            return BackgroundHapticPhase(
              label: phase.label,
              durationMs: phase.durationSeconds * 1000,
              vibrateMs: pulse ? _pulseDurationMs(phase.durationSeconds) : 0,
              amplitude: pulse ? _pulseAmplitude(phase.kind) : 1,
            );
          })
          .toList(growable: false),
    );
  }

  int _pulseDurationMs(int phaseSeconds) {
    return (phaseSeconds * 14).clamp(36, 120);
  }

  int _pulseAmplitude(BreathingPhaseKind kind) {
    return switch (kind) {
      BreathingPhaseKind.inhale => 104,
      BreathingPhaseKind.exhale => 76,
      BreathingPhaseKind.holdAfterInhale ||
      BreathingPhaseKind.holdAfterExhale => 48,
    };
  }
}

class BreathingPhase {
  const BreathingPhase({
    required this.kind,
    required this.label,
    required this.durationSeconds,
  });

  final BreathingPhaseKind kind;
  final String label;
  final int durationSeconds;

  bool get isBreathingMotion =>
      kind == BreathingPhaseKind.inhale || kind == BreathingPhaseKind.exhale;
}
