import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huxi_zen/src/content/content_models.dart';
import 'package:huxi_zen/src/features/home/ambient_audio_engine.dart';
import 'package:huxi_zen/src/platform/background_audio_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(backgroundAudioServiceChannelName);

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets('syncs Android ambient mix to the background audio service', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return true;
          });

      await tester.pumpWidget(AmbientAudioEngine(enabled: true, mix: _mix));
      await tester.pump();

      expect(calls.first.method, 'sync');
      final args = calls.first.arguments as Map<Object?, Object?>;
      final tracks = jsonDecode(args['tracksJson']! as String) as List;
      expect(tracks.single, containsPair('channelId', 'rain-layer'));
      expect(tracks.single, containsPair('mediaId', 'rain'));
      expect(tracks.single, containsPair('durationMs', 45000));

      await tester.pumpWidget(AmbientAudioEngine(enabled: false, mix: _mix));
      await tester.pump();

      expect(calls.map((call) => call.method), contains('stop'));
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

const _mix = AmbientMix(
  id: 'test-mix',
  label: 'Rain Layer',
  tracks: [
    ResolvedAmbientTrack(
      id: 'rain',
      channelId: 'rain-layer',
      label: 'Rain',
      file: 'light-rain.mp3',
      durationMs: 45000,
      volume: 0.3,
      url: 'assets/media/audio/light-rain.mp3',
    ),
  ],
);
