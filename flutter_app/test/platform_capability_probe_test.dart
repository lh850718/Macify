import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huxi_zen/src/platform/platform_capability_probe.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(platformCapabilityChannelName);

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('parses iOS background audio and haptic capability report', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'capabilityReport');
          return {
            'platform': 'ios',
            'osVersion': '26.5',
            'backgroundAudioModeDeclared': true,
            'audioSessionPlaybackCategoryConfigured': true,
            'hapticsAvailable': true,
            'vibrationAvailable': true,
            'notes': ['ios note'],
          };
        });

    final report = await const PlatformCapabilityProbe().loadReport();

    expect(report.platform, 'ios');
    expect(report.backgroundAudioReadyForSpike, isTrue);
    expect(report.foregroundHapticReadyForSpike, isTrue);
    expect(report.notes, ['ios note']);
  });

  test(
    'parses Android foreground service and vibration capability report',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            expect(call.method, 'capabilityReport');
            return {
              'platform': 'android',
              'osVersion': '16',
              'sdkInt': 36,
              'foregroundServicePermissionDeclared': true,
              'mediaPlaybackForegroundServicePermissionDeclared': true,
              'wakeLockPermissionDeclared': true,
              'mediaSessionServiceDeclared': true,
              'postNotificationsPermissionDeclared': true,
              'vibrationPermissionDeclared': true,
              'vibrationAvailable': true,
              'amplitudeControlAvailable': false,
              'backgroundVibrationRequiresForegroundService': true,
            };
          });

      final report = await const PlatformCapabilityProbe().loadReport();

      expect(report.platform, 'android');
      expect(report.sdkInt, 36);
      expect(report.backgroundAudioReadyForSpike, isTrue);
      expect(report.foregroundHapticReadyForSpike, isTrue);
      expect(report.backgroundVibrationRequiresForegroundService, isTrue);
    },
  );

  test(
    'can trigger a foreground haptic pulse through the platform channel',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            expect(call.method, 'pulseHaptic');
            return true;
          });

      await expectLater(
        const PlatformCapabilityProbe().pulseHaptic(),
        completion(isTrue),
      );
    },
  );
}
