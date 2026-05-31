import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';

import '../../preferences/user_preferences.dart';
import 'breathing_haptics.dart';
import 'breathing_models.dart';

const _breathSoundAsset = 'assets/media/audio/breath.mp3';
const _breathScaleMin = 0.45;
const _breathScaleMax = 1.2;
const _breathHoldOpacity = 0.76;
const _breathEntryDuration = Duration(milliseconds: 760);
const _breathCompletionDuration = Duration(milliseconds: 3000);
const _breathCurve = Cubic(0.45, 0, 0.55, 1);

enum _BreathingMode { defaultBreath, customExercise }

class BreathingOverlay extends StatefulWidget {
  const BreathingOverlay({
    super.key,
    required this.settings,
    required this.ambientOn,
    required this.ambientAvailable,
    required this.ambientLabel,
    required this.onSettingsChanged,
    required this.onToggleAmbient,
    required this.onExit,
    this.hapticController = const BreathingHapticController(),
  });

  final AppSettings settings;
  final bool ambientOn;
  final bool ambientAvailable;
  final String ambientLabel;
  final ValueChanged<AppSettings> onSettingsChanged;
  final VoidCallback onToggleAmbient;
  final VoidCallback onExit;
  final BreathingHapticController hapticController;

  @override
  State<BreathingOverlay> createState() => _BreathingOverlayState();
}

class _BreathingOverlayState extends State<BreathingOverlay>
    with SingleTickerProviderStateMixin {
  late AppSettings _settings;
  late final AnimationController _rotationController;
  Timer? _phaseTimer;
  Timer? _holdOpacityTimer;
  Timer? _countdownTimer;
  Timer? _hintTimer;
  AudioPlayer? _soundPlayer;

  var _mode = _BreathingMode.defaultBreath;
  var _phaseText = '';
  var _practiceText = '';
  var _countdownText = '';
  var _hintText = '';
  var _flowerVisible = true;
  var _flowerEntering = false;
  var _flowerBursting = false;
  var _flowerScale = _breathScaleMin;
  var _flowerOpacity = 1.0;
  var _flowerRotationTurns = 0.0;
  var _phaseAnimationDuration = Duration.zero;
  Curve _phaseAnimationCurve = _breathCurve;
  var _phaseEntering = false;
  var _customCycleIndex = 0;
  var _phaseSerial = 0;

  @override
  void initState() {
    super.initState();
    _settings = widget.settings;
    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 36),
    )..repeat();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _startDefaultSession();
      unawaited(_syncSound());
    });
  }

  @override
  void didUpdateWidget(BreathingOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.settings, _settings)) {
      _settings = widget.settings;
    }
  }

  @override
  void dispose() {
    _phaseTimer?.cancel();
    _holdOpacityTimer?.cancel();
    _countdownTimer?.cancel();
    _hintTimer?.cancel();
    _rotationController.dispose();
    unawaited(widget.hapticController.stop());
    unawaited(_soundPlayer?.dispose() ?? Future<void>.value());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragEnd: (details) {
          final velocity = details.primaryVelocity ?? 0;
          if (velocity < -220) widget.onExit();
          if (velocity > 220) _startCustomExercise();
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(
              child: _BreathingStage(
                countdownText: _countdownText,
                phaseText: _phaseText,
                practiceText: _practiceText,
                flowerVisible: _flowerVisible,
                flowerEntering: _flowerEntering,
                flowerBursting: _flowerBursting,
                flowerScale: _flowerScale,
                flowerOpacity: _flowerOpacity,
                flowerRotationTurns: _flowerRotationTurns,
                phaseAnimationDuration: _phaseAnimationDuration,
                phaseAnimationCurve: _phaseAnimationCurve,
                phaseEntering: _phaseEntering,
                rotationController: _rotationController,
              ),
            ),
            Positioned(
              left: 18,
              right: 18,
              bottom: safeBottom + 88,
              child: _ZenHint(text: _hintText),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: safeBottom + 44,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _ZenCueButton(
                    label: '触感',
                    active: _settings.zenHaptics,
                    onPressed: _toggleHaptics,
                  ),
                  const SizedBox(width: 24),
                  _ZenCueButton(
                    label: '颂钵音',
                    active: _settings.zenSound,
                    onPressed: _toggleSound,
                  ),
                  const SizedBox(width: 24),
                  _ZenCueButton(
                    key: const ValueKey('start-custom-breath-button'),
                    label: '自定义练习',
                    active: _mode == _BreathingMode.customExercise,
                    onPressed: _startCustomExercise,
                  ),
                ],
              ),
            ),
            Positioned(
              right: 78,
              bottom: safeBottom + 2,
              child: _ZenRoundButton(
                label: '♪',
                semanticLabel: widget.ambientLabel,
                active: widget.ambientOn,
                disabled: !widget.ambientAvailable && !widget.ambientOn,
                onPressed: widget.ambientAvailable || widget.ambientOn
                    ? widget.onToggleAmbient
                    : null,
              ),
            ),
            Positioned(
              right: 22,
              bottom: safeBottom + 7,
              child: _ZenExitButton(onPressed: widget.onExit),
            ),
          ],
        ),
      ),
    );
  }

  BreathingRhythm get _currentRhythm {
    return _mode == _BreathingMode.customExercise
        ? _settings.customBreathRhythm
        : _settings.defaultBreathRhythm;
  }

  void _startDefaultSession() {
    _phaseTimer?.cancel();
    _holdOpacityTimer?.cancel();
    _countdownTimer?.cancel();
    _mode = _BreathingMode.defaultBreath;
    _customCycleIndex = 0;
    _phaseSerial += 1;
    setState(() {
      _phaseText = '';
      _practiceText = '';
      _countdownText = '';
      _flowerVisible = true;
      _flowerEntering = false;
      _flowerBursting = false;
      _flowerScale = _breathScaleMin;
      _flowerOpacity = 1;
      _flowerRotationTurns = 0;
      _phaseAnimationDuration = Duration.zero;
      _phaseAnimationCurve = _breathCurve;
      _phaseEntering = false;
    });
    _startFirstPhase(syncHaptics: true);
  }

  void _startCustomExercise() {
    _phaseTimer?.cancel();
    _holdOpacityTimer?.cancel();
    _countdownTimer?.cancel();
    _customCycleIndex = 0;
    _mode = _BreathingMode.customExercise;
    _phaseSerial += 1;
    unawaited(widget.hapticController.stop());
    setState(() {
      _phaseText = '';
      _practiceText = _customBreathIntroText(_settings.customBreathRhythm);
      _countdownText = '3';
      _flowerVisible = false;
      _flowerEntering = false;
      _flowerBursting = false;
      _flowerScale = _breathScaleMin;
      _flowerOpacity = 1;
      _flowerRotationTurns = 0;
      _phaseAnimationDuration = Duration.zero;
      _phaseAnimationCurve = _breathCurve;
      _phaseEntering = false;
    });
    _runCountdown(3);
  }

  void _runCountdown(int value) {
    _countdownTimer?.cancel();
    _countdownTimer = Timer(const Duration(seconds: 1), () {
      if (!mounted || _mode != _BreathingMode.customExercise) return;
      if (value > 1) {
        setState(() => _countdownText = '${value - 1}');
        _runCountdown(value - 1);
        return;
      }
      setState(() {
        _countdownText = '';
      });
      _startFirstPhase(withEntry: true, syncHaptics: true);
    });
  }

  void _startFirstPhase({bool withEntry = false, bool syncHaptics = false}) {
    final phases = _currentRhythm.phases;
    if (phases.isEmpty) return;
    final firstPhase = phases.first;
    if (!withEntry) {
      _startPhase(firstPhase);
      if (syncHaptics) unawaited(_syncHapticsForSession());
      return;
    }

    _phaseTimer?.cancel();
    _holdOpacityTimer?.cancel();
    final serial = ++_phaseSerial;
    setState(() {
      _phaseText = _phaseLabel(firstPhase.kind);
      _flowerVisible = true;
      _flowerEntering = true;
      _flowerBursting = false;
      _flowerScale = _breathScaleMin;
      _flowerOpacity = 1;
      _flowerRotationTurns = 0;
      _phaseAnimationDuration = Duration.zero;
      _phaseAnimationCurve = _breathCurve;
      _phaseEntering = true;
    });
    _phaseTimer = Timer(_breathEntryDuration, () {
      if (!mounted || _phaseSerial != serial) return;
      setState(() {
        _flowerEntering = false;
        _phaseEntering = false;
      });
      _startPhase(firstPhase);
      if (syncHaptics) unawaited(_syncHapticsForSession());
    });
  }

  void _startPhase(BreathingPhase phase) {
    _phaseTimer?.cancel();
    _holdOpacityTimer?.cancel();
    final serial = ++_phaseSerial;
    final rhythm = _currentRhythm;
    if (_mode == _BreathingMode.customExercise &&
        phase.kind == BreathingPhaseKind.inhale) {
      final targetCycles = max(1, rhythm.cycles);
      if (_customCycleIndex >= targetCycles) {
        _completeCustomExercise();
        return;
      }
      _customCycleIndex += 1;
    }

    final duration = Duration(seconds: phase.durationSeconds);
    final holdPhase = _isHoldPhase(phase.kind);
    final animationDuration = holdPhase
        ? Duration(milliseconds: max(1, duration.inMilliseconds ~/ 2))
        : duration;
    setState(() {
      _phaseText = _phaseLabel(phase.kind);
      if (_mode == _BreathingMode.customExercise) {
        _practiceText = _customProgressText(rhythm);
      }
      _phaseAnimationDuration = animationDuration;
      _phaseAnimationCurve = _breathCurve;
      _phaseEntering = false;
      _flowerEntering = false;
      _flowerBursting = false;
      _flowerScale = _targetScaleForPhase(phase.kind);
      _flowerOpacity = holdPhase ? _breathHoldOpacity : 1;
      _flowerRotationTurns = 0;
      _flowerVisible = true;
    });

    if (holdPhase) {
      final remainingMs = max(
        1,
        duration.inMilliseconds - animationDuration.inMilliseconds,
      );
      _holdOpacityTimer = Timer(animationDuration, () {
        if (!mounted || _phaseSerial != serial) return;
        setState(() {
          _phaseAnimationDuration = Duration(milliseconds: remainingMs);
          _phaseAnimationCurve = _breathCurve;
          _flowerOpacity = 1;
        });
      });
    }

    _phaseTimer = Timer(duration, () {
      if (!mounted) return;
      _startPhase(_nextPhase(phase, _currentRhythm));
    });
  }

  void _completeCustomExercise() {
    _phaseTimer?.cancel();
    _holdOpacityTimer?.cancel();
    _countdownTimer?.cancel();
    final serial = ++_phaseSerial;
    unawaited(widget.hapticController.stop());
    setState(() {
      _mode = _BreathingMode.defaultBreath;
      _phaseText = '';
      _practiceText = '本次练习完成，恢复默认呼吸';
      _countdownText = '';
      _flowerVisible = true;
      _flowerEntering = false;
      _flowerBursting = true;
      _flowerScale = 2.15;
      _flowerOpacity = 0;
      _flowerRotationTurns = 18 / 360;
      _phaseAnimationDuration = _breathCompletionDuration;
      _phaseAnimationCurve = Curves.easeOut;
      _phaseEntering = false;
    });
    _phaseTimer = Timer(
      _breathCompletionDuration + const Duration(milliseconds: 80),
      () {
        if (!mounted || _phaseSerial != serial) return;
        setState(() {
          _customCycleIndex = 0;
          _flowerVisible = false;
          _flowerBursting = false;
          _flowerScale = _breathScaleMin;
          _flowerOpacity = 1;
          _flowerRotationTurns = 0;
          _phaseAnimationDuration = Duration.zero;
          _phaseAnimationCurve = _breathCurve;
          _phaseEntering = false;
        });
        _phaseTimer = Timer(const Duration(milliseconds: 40), () {
          if (!mounted || _phaseSerial != serial) return;
          setState(() => _practiceText = '');
          _startFirstPhase(withEntry: true, syncHaptics: true);
        });
      },
    );
  }

  BreathingPhase _nextPhase(BreathingPhase phase, BreathingRhythm rhythm) {
    final phases = rhythm.phases;
    if (phases.isEmpty) return phase;
    final index = phases.indexWhere(
      (candidate) => candidate.kind == phase.kind,
    );
    if (index < 0 || index == phases.length - 1) return phases.first;
    return phases[index + 1];
  }

  Future<void> _toggleHaptics() async {
    final enabled = !_settings.zenHaptics;
    final next = _settings.copyWith(zenHaptics: enabled);
    _updateSettings(next);
    if (enabled) {
      _showHint('需要打开手机振动功能');
      await _syncHapticsForSession();
    } else {
      await widget.hapticController.stop();
    }
  }

  Future<void> _toggleSound() async {
    final enabled = !_settings.zenSound;
    final next = _settings.copyWith(zenSound: enabled);
    _updateSettings(next);
    await _syncSound();
  }

  void _updateSettings(AppSettings settings) {
    setState(() => _settings = settings);
    widget.onSettingsChanged(settings);
  }

  Future<void> _syncHapticsForSession() async {
    if (!_settings.zenHaptics || _countdownText.isNotEmpty || _flowerEntering) {
      await widget.hapticController.stop();
      return;
    }
    if (_mode == _BreathingMode.customExercise) {
      await widget.hapticController.startExercise(
        rhythm: _settings.customBreathRhythm,
      );
    } else {
      await widget.hapticController.startRhythm(
        _settings.defaultBreathRhythm,
        patternId: 'default-breath',
      );
    }
  }

  Future<void> _syncSound() async {
    if (!_settings.zenSound) {
      await _soundPlayer?.stop();
      return;
    }
    try {
      final player = _soundPlayer ??= AudioPlayer();
      if (!player.playing) {
        await player.setAsset(_breathSoundAsset);
        await player.setLoopMode(LoopMode.one);
        await player.setVolume(0.55);
        unawaited(player.play());
      }
    } on MissingPluginException {
      _showHint('颂钵音暂不可用');
    } on PlayerException {
      _showHint('颂钵音暂不可用');
    }
  }

  void _showHint(String text) {
    _hintTimer?.cancel();
    if (!mounted) return;
    setState(() => _hintText = text);
    _hintTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _hintText = '');
    });
  }

  String _customProgressText(BreathingRhythm rhythm) {
    final targetCycles = max(1, rhythm.cycles);
    final completedCycles = max(0, _customCycleIndex - 1);
    final remainingCycles = max(1, targetCycles - completedCycles);
    return '还剩$remainingCycles组';
  }
}

class _BreathingStage extends StatelessWidget {
  const _BreathingStage({
    required this.countdownText,
    required this.phaseText,
    required this.practiceText,
    required this.flowerVisible,
    required this.flowerEntering,
    required this.flowerBursting,
    required this.flowerScale,
    required this.flowerOpacity,
    required this.flowerRotationTurns,
    required this.phaseAnimationDuration,
    required this.phaseAnimationCurve,
    required this.phaseEntering,
    required this.rotationController,
  });

  final String countdownText;
  final String phaseText;
  final String practiceText;
  final bool flowerVisible;
  final bool flowerEntering;
  final bool flowerBursting;
  final double flowerScale;
  final double flowerOpacity;
  final double flowerRotationTurns;
  final Duration phaseAnimationDuration;
  final Curve phaseAnimationCurve;
  final bool phaseEntering;
  final AnimationController rotationController;

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final stageSide = min(screen.width * 0.48, 320.0);
    final labelTop = screen.height / 2 + screen.width * 208 / 750;
    final labelHeight = screen.width * 56 / 750;
    final practiceTop = screen.height / 2 + screen.width * 274 / 750;
    final practiceWidth = min(screen.width * 610 / 750, screen.width - 40);

    return Stack(
      fit: StackFit.expand,
      children: [
        Center(
          child: SizedBox.square(
            dimension: stageSide,
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (countdownText.isNotEmpty)
                  _CountdownText(text: countdownText),
                if (flowerVisible)
                  RotationTransition(
                    turns: rotationController,
                    child: AnimatedRotation(
                      turns: flowerRotationTurns,
                      duration: phaseAnimationDuration,
                      curve: phaseAnimationCurve,
                      child: AnimatedScale(
                        scale: flowerScale,
                        duration: phaseAnimationDuration,
                        curve: phaseAnimationCurve,
                        child: AnimatedOpacity(
                          opacity: flowerOpacity,
                          duration: phaseAnimationDuration,
                          curve: phaseAnimationCurve,
                          child: _EnteringFade(
                            active: flowerEntering,
                            child: _BreathingFlower(
                              bursting: flowerBursting,
                              burstDuration: _breathCompletionDuration,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          top: labelTop,
          height: labelHeight,
          child: Center(child: _PhaseText(phaseText, entering: phaseEntering)),
        ),
        Positioned(
          left: (screen.width - practiceWidth) / 2,
          width: practiceWidth,
          top: practiceTop,
          height: screen.width * 118 / 750,
          child: Center(
            child: Text(
              practiceText,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.58),
                fontSize: 13,
                height: 1.5,
                shadows: const [
                  Shadow(
                    color: Color(0x99000000),
                    offset: Offset(0, 2),
                    blurRadius: 10,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _EnteringFade extends StatelessWidget {
  const _EnteringFade({required this.active, required this.child});

  final bool active;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!active) return child;
    return TweenAnimationBuilder<double>(
      key: ValueKey(active),
      tween: Tween(begin: 0.0, end: 1.0),
      duration: _breathEntryDuration,
      curve: Curves.easeOut,
      builder: (context, opacity, child) {
        return Opacity(opacity: opacity, child: child);
      },
      child: child,
    );
  }
}

class _PhaseText extends StatelessWidget {
  const _PhaseText(this.text, {required this.entering});

  final String text;
  final bool entering;

  @override
  Widget build(BuildContext context) {
    final child = Text(
      text,
      style: TextStyle(
        color: Colors.white.withValues(alpha: 0.85),
        fontSize: 16,
        fontWeight: FontWeight.w300,
        letterSpacing: 3,
        shadows: const [
          Shadow(
            color: Color(0x99000000),
            offset: Offset(0, 2),
            blurRadius: 12,
          ),
        ],
      ),
    );
    if (!entering) return child;
    return TweenAnimationBuilder<double>(
      key: ValueKey('$text-$entering'),
      tween: Tween(begin: 0.0, end: 1.0),
      duration: _breathEntryDuration,
      curve: Curves.easeOut,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, (1 - value) * 5),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

class _CountdownText extends StatelessWidget {
  const _CountdownText({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      key: ValueKey(text),
      tween: Tween(begin: 0.72, end: 1.18),
      duration: const Duration(milliseconds: 980),
      curve: Curves.easeInOut,
      builder: (context, scale, child) {
        final opacity = scale < 1 ? (scale - 0.72) / 0.28 : 1 - (scale - 1);
        return Opacity(
          opacity: opacity.clamp(0, 1),
          child: Transform.scale(scale: scale, child: child),
        );
      },
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 74,
          fontWeight: FontWeight.w200,
          letterSpacing: 0,
          shadows: [
            Shadow(
              color: Color(0x99000000),
              offset: Offset(0, 4),
              blurRadius: 24,
            ),
          ],
        ),
      ),
    );
  }
}

class _BreathingFlower extends StatelessWidget {
  const _BreathingFlower({required this.bursting, required this.burstDuration});

  final bool bursting;
  final Duration burstDuration;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = min(constraints.maxWidth, constraints.maxHeight);
        return TweenAnimationBuilder<double>(
          key: ValueKey(bursting),
          tween: Tween(begin: 0.0, end: bursting ? 1.0 : 0.0),
          duration: bursting ? burstDuration : Duration.zero,
          curve: Curves.easeOut,
          builder: (context, burstProgress, child) {
            return RepaintBoundary(
              child: CustomPaint(
                size: Size.square(size),
                isComplex: true,
                painter: _BreathingFlowerPainter(burstProgress: burstProgress),
              ),
            );
          },
        );
      },
    );
  }
}

class _BreathingFlowerPainter extends CustomPainter {
  const _BreathingFlowerPainter({required this.burstProgress});

  final double burstProgress;

  static const _petalStops = [0.0, 0.45, 0.8, 1.0];

  @override
  void paint(Canvas canvas, Size size) {
    final side = min(size.width, size.height);
    final petalSide = side * 0.56;
    final progress = burstProgress.clamp(0.0, 1.0);
    final petalOffset = petalSide * _lerp(0.26, 1.12, progress);
    final petalScale = _lerp(1, 0.42, progress);
    final petalOpacity = 1 - progress;
    final scaledPetalSide = petalSide * petalScale;
    final petalRect = Rect.fromCenter(
      center: Offset(0, -petalOffset),
      width: scaledPetalSide,
      height: scaledPetalSide,
    );
    final shader = RadialGradient(
      center: Alignment(-0.3, -0.3),
      radius: 0.82,
      colors: [
        Color.fromRGBO(255, 255, 255, 0.20 * petalOpacity),
        Color.fromRGBO(220, 240, 255, 0.45 * petalOpacity),
        Color.fromRGBO(180, 220, 255, 0.18 * petalOpacity),
        const Color.fromRGBO(180, 220, 255, 0),
      ],
      stops: _petalStops,
    ).createShader(petalRect);
    final paint = Paint()
      ..shader = shader
      ..blendMode = BlendMode.screen
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.5);

    canvas.translate(size.width / 2, size.height / 2);
    for (var index = 0; index < 6; index += 1) {
      canvas
        ..save()
        ..rotate(index * pi / 3)
        ..drawOval(petalRect, paint)
        ..restore();
    }
  }

  @override
  bool shouldRepaint(covariant _BreathingFlowerPainter oldDelegate) {
    return oldDelegate.burstProgress != burstProgress;
  }
}

class _ZenCueButton extends StatelessWidget {
  const _ZenCueButton({
    super.key,
    required this.label,
    required this.active,
    required this.onPressed,
  });

  final String label;
  final bool active;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: Colors.white.withValues(alpha: active ? 0.74 : 0.24),
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 10),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          letterSpacing: 0,
        ),
      ),
      child: Text(
        label,
        style: const TextStyle(
          shadows: [
            Shadow(
              color: Color(0x99000000),
              offset: Offset(0, 2),
              blurRadius: 10,
            ),
          ],
        ),
      ),
    );
  }
}

class _ZenRoundButton extends StatelessWidget {
  const _ZenRoundButton({
    required this.label,
    required this.semanticLabel,
    required this.active,
    required this.disabled,
    required this.onPressed,
  });

  final String label;
  final String semanticLabel;
  final bool active;
  final bool disabled;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final opacity = disabled
        ? 0.24
        : active
        ? 0.96
        : 0.54;
    return Semantics(
      button: true,
      label: semanticLabel,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: Colors.white.withValues(alpha: opacity),
          padding: EdgeInsets.zero,
          minimumSize: const Size.square(44),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          textStyle: const TextStyle(fontSize: 26, fontWeight: FontWeight.w500),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: Text(
          label,
          style: const TextStyle(
            shadows: [
              Shadow(
                color: Color(0x99000000),
                offset: Offset(0, 2),
                blurRadius: 12,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ZenExitButton extends StatelessWidget {
  const _ZenExitButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: Colors.white.withValues(alpha: 0.62),
        backgroundColor: Colors.black.withValues(alpha: 0.16),
        padding: EdgeInsets.zero,
        minimumSize: const Size.square(40),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: const TextStyle(fontSize: 34, fontWeight: FontWeight.w300),
        shape: const CircleBorder(),
      ),
      child: const Text('‹'),
    );
  }
}

class _ZenHint extends StatelessWidget {
  const _ZenHint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: text.isEmpty ? 0 : 1,
      duration: const Duration(milliseconds: 180),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.46),
          fontSize: 12,
          shadows: const [
            Shadow(
              color: Color(0x99000000),
              offset: Offset(0, 2),
              blurRadius: 12,
            ),
          ],
        ),
      ),
    );
  }
}

String _phaseLabel(BreathingPhaseKind kind) {
  return switch (kind) {
    BreathingPhaseKind.inhale => '吸气',
    BreathingPhaseKind.exhale => '呼气',
    BreathingPhaseKind.holdAfterInhale ||
    BreathingPhaseKind.holdAfterExhale => '屏息',
  };
}

double _lerp(double begin, double end, double progress) {
  return begin + (end - begin) * progress;
}

double _targetScaleForPhase(BreathingPhaseKind kind) {
  return switch (kind) {
    BreathingPhaseKind.inhale ||
    BreathingPhaseKind.holdAfterInhale => _breathScaleMax,
    BreathingPhaseKind.exhale ||
    BreathingPhaseKind.holdAfterExhale => _breathScaleMin,
  };
}

bool _isHoldPhase(BreathingPhaseKind kind) {
  return switch (kind) {
    BreathingPhaseKind.holdAfterInhale ||
    BreathingPhaseKind.holdAfterExhale => true,
    BreathingPhaseKind.inhale || BreathingPhaseKind.exhale => false,
  };
}

String _customBreathIntroText(BreathingRhythm rhythm) {
  final parts = [
    if (rhythm.inhaleSeconds > 0) '吸${rhythm.inhaleSeconds}秒',
    if (rhythm.holdAfterInhaleSeconds > 0)
      '屏息${rhythm.holdAfterInhaleSeconds}秒',
    if (rhythm.exhaleSeconds > 0) '呼${rhythm.exhaleSeconds}秒',
    if (rhythm.holdAfterExhaleSeconds > 0)
      '屏息${rhythm.holdAfterExhaleSeconds}秒',
  ];
  return [
    '本次练习${max(1, rhythm.cycles)}组',
    parts.join('->'),
    '可在设置中修改',
  ].join('\n');
}
