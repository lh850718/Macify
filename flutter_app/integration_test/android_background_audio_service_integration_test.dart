import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huxi_zen/src/platform/background_audio_service.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('starts and stops Android MediaSession foreground service', (
    tester,
  ) async {
    const bridge = BackgroundAudioServiceBridge();
    final initial = await bridge.status();
    debugPrint(
      'ANDROID_BACKGROUND_AUDIO_STATUS_INITIAL ${jsonEncode(initial.toJson())}',
    );

    if (initial.platform != 'android') {
      return;
    }

    expect(initial.mediaSessionServiceDeclared, isTrue);
    addTearDown(() async {
      await bridge.stop();
    });

    final started = await bridge.start(
      tracks: const [
        BackgroundAudioTrack(
          channelId: 'waterfall-main',
          mediaId: 'waterfall',
          title: 'Waterfall',
          uri: 'assets/media/audio/waterfall.mp3',
          durationMs: 62000,
          volume: 0.12,
        ),
        BackgroundAudioTrack(
          channelId: 'birds-layer',
          mediaId: 'birds',
          title: 'Birds',
          uri: 'assets/media/audio/birds.mp3',
          durationMs: 64000,
          volume: 0.08,
        ),
      ],
    );
    expect(started, isTrue);

    await tester.pump(const Duration(seconds: 2));

    final running = await bridge.status();
    debugPrint(
      'ANDROID_BACKGROUND_AUDIO_STATUS_RUNNING ${jsonEncode(running.toJson())}',
    );
    expect(running.running, isTrue);
    expect(running.trackCount, 2);
    expect(running.primaryUri, 'assets/media/audio/waterfall.mp3');
    expect(
      running.activeChannelIds,
      containsAll(['waterfall-main', 'birds-layer']),
    );
    expect(running.lastError, isEmpty);

    final hapticsStarted = await bridge.startHapticPattern(
      pattern: const BackgroundHapticPattern(
        patternId: 'integration-breath',
        phases: [
          BackgroundHapticPhase(label: 'inhale', durationMs: 500),
          BackgroundHapticPhase(
            label: 'hold-after-inhale',
            durationMs: 1,
            vibrateMs: 0,
          ),
          BackgroundHapticPhase(label: 'exhale', durationMs: 500),
          BackgroundHapticPhase(
            label: 'hold-after-exhale',
            durationMs: 1,
            vibrateMs: 0,
          ),
        ],
      ),
    );
    expect(hapticsStarted, isTrue);
    await tester.pump(const Duration(milliseconds: 200));

    final hapticStatus = await bridge.status();
    debugPrint(
      'ANDROID_BACKGROUND_AUDIO_STATUS_HAPTICS ${jsonEncode(hapticStatus.toJson())}',
    );
    expect(hapticStatus.hapticsRunning, isTrue);
    expect(hapticStatus.hapticPatternId, 'integration-breath');
    expect(hapticStatus.hapticPhase, isNotEmpty);

    final synced = await bridge.sync(
      tracks: const [
        BackgroundAudioTrack(
          channelId: 'waterfall-main',
          mediaId: 'waterfall',
          title: 'Waterfall',
          uri: 'assets/media/audio/waterfall.mp3',
          durationMs: 62000,
          volume: 0.05,
        ),
      ],
    );
    expect(synced, isTrue);
    await tester.pump(const Duration(seconds: 1));

    final syncedStatus = await bridge.status();
    debugPrint(
      'ANDROID_BACKGROUND_AUDIO_STATUS_SYNCED ${jsonEncode(syncedStatus.toJson())}',
    );
    expect(syncedStatus.running, isTrue);
    expect(syncedStatus.trackCount, 1);
    expect(syncedStatus.activeChannelIds, ['waterfall-main']);
    expect(syncedStatus.hapticsRunning, isTrue);

    final hapticsStopped = await bridge.stopHaptics();
    expect(hapticsStopped, isTrue);
    await tester.pump(const Duration(milliseconds: 100));

    final hapticsStoppedStatus = await bridge.status();
    expect(hapticsStoppedStatus.hapticsRunning, isFalse);

    final stopped = await bridge.stop();
    expect(stopped, isTrue);
    await tester.pump(const Duration(milliseconds: 300));

    final finalStatus = await bridge.status();
    debugPrint(
      'ANDROID_BACKGROUND_AUDIO_STATUS_STOPPED ${jsonEncode(finalStatus.toJson())}',
    );
    expect(finalStatus.running, isFalse);
  });
}
