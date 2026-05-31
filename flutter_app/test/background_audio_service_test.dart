import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huxi_zen/src/platform/background_audio_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(backgroundAudioServiceChannelName);

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'sends background audio tracks as json to the platform channel',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            expect(call.method, 'start');
            final args = call.arguments as Map<Object?, Object?>;
            final tracks = jsonDecode(args['tracksJson']! as String) as List;
            expect(tracks, hasLength(2));
            expect(tracks.first, {
              'channelId': 'waterfall-main',
              'mediaId': 'waterfall',
              'title': 'Waterfall',
              'uri': 'assets/media/audio/waterfall.mp3',
              'durationMs': 62000,
              'volume': 0.6,
            });
            return true;
          });

      final started = await const BackgroundAudioServiceBridge().start(
        tracks: const [
          BackgroundAudioTrack(
            channelId: 'waterfall-main',
            mediaId: 'waterfall',
            title: 'Waterfall',
            uri: 'assets/media/audio/waterfall.mp3',
            durationMs: 62000,
            volume: 0.6,
          ),
          BackgroundAudioTrack(
            mediaId: 'birds',
            title: 'Birds',
            uri: 'assets/media/audio/birds.mp3',
          ),
        ],
      );

      expect(started, isTrue);
    },
  );

  test('syncs updated track state through the platform channel', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'sync');
          final args = call.arguments as Map<Object?, Object?>;
          final tracks = jsonDecode(args['tracksJson']! as String) as List;
          expect(tracks.single, containsPair('channelId', 'rain-bed'));
          expect(tracks.single, containsPair('durationMs', 45000));
          expect(tracks.single, containsPair('volume', 0.25));
          return true;
        });

    await expectLater(
      const BackgroundAudioServiceBridge().sync(
        tracks: const [
          BackgroundAudioTrack(
            channelId: 'rain-bed',
            mediaId: 'rain',
            title: 'Rain',
            uri: 'assets/media/audio/light-rain.mp3',
            durationMs: 45000,
            volume: 0.25,
          ),
        ],
      ),
      completion(isTrue),
    );
  });

  test('empty sync stops the platform service', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'stop');
          return true;
        });

    await expectLater(
      const BackgroundAudioServiceBridge().sync(tracks: const []),
      completion(isTrue),
    );
  });

  test('does not start the platform service without tracks', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          fail('empty starts should not reach the platform channel');
        });

    await expectLater(
      const BackgroundAudioServiceBridge().start(tracks: const []),
      completion(isFalse),
    );
  });

  test('parses background audio service status', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'status');
          return {
            'platform': 'android',
            'mediaSessionServiceDeclared': true,
            'running': true,
            'trackCount': 2,
            'lastCommand': 'start',
            'primaryUri': 'assets/media/audio/waterfall.mp3',
            'playbackState': 'ready',
            'lastError': '',
            'activeChannelIds': ['waterfall-main', 'birds'],
            'hapticsRunning': true,
            'hapticPatternId': 'default-breath',
            'hapticPhase': 'inhale',
            'hapticPhaseIndex': 0,
          };
        });

    final status = await const BackgroundAudioServiceBridge().status();

    expect(status.platform, 'android');
    expect(status.mediaSessionServiceDeclared, isTrue);
    expect(status.running, isTrue);
    expect(status.trackCount, 2);
    expect(status.playbackState, 'ready');
    expect(status.lastError, isEmpty);
    expect(status.activeChannelIds, ['waterfall-main', 'birds']);
    expect(status.hapticsRunning, isTrue);
    expect(status.hapticPatternId, 'default-breath');
    expect(status.hapticPhase, 'inhale');
    expect(status.hapticPhaseIndex, 0);
  });

  test('stops the platform background audio service', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'stop');
          return true;
        });

    await expectLater(
      const BackgroundAudioServiceBridge().stop(),
      completion(isTrue),
    );
  });

  test('starts and stops a background haptic pattern', () async {
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          if (call.method == 'startHapticPattern') {
            final args = call.arguments as Map<Object?, Object?>;
            final pattern =
                jsonDecode(args['patternJson']! as String)
                    as Map<String, Object?>;
            expect(pattern['patternId'], 'default-breath');
            expect(pattern['cycles'], 0);
            final phases = pattern['phases']! as List;
            expect(phases, hasLength(4));
            expect(phases.first, {
              'label': 'inhale',
              'durationMs': 5000,
              'vibrateMs': 45,
              'amplitude': 96,
            });
          }
          return true;
        });

    final bridge = const BackgroundAudioServiceBridge();
    final started = await bridge.startHapticPattern(
      pattern: const BackgroundHapticPattern(
        patternId: 'default-breath',
        phases: [
          BackgroundHapticPhase(label: 'inhale', durationMs: 5000),
          BackgroundHapticPhase(
            label: 'hold-after-inhale',
            durationMs: 1,
            vibrateMs: 0,
          ),
          BackgroundHapticPhase(label: 'exhale', durationMs: 5000),
          BackgroundHapticPhase(
            label: 'hold-after-exhale',
            durationMs: 1,
            vibrateMs: 0,
          ),
        ],
      ),
    );
    final stopped = await bridge.stopHaptics();

    expect(started, isTrue);
    expect(stopped, isTrue);
    expect(calls, ['startHapticPattern', 'stopHaptics']);
  });
}
