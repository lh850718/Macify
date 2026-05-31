import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huxi_zen/src/platform/platform_capability_probe.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('collects native platform capability report', (tester) async {
    const probe = PlatformCapabilityProbe();

    final report = await probe.loadReport();
    final pulseResult = await probe.pulseHaptic();

    debugPrint('PLATFORM_CAPABILITY_REPORT ${jsonEncode(report.toJson())}');
    debugPrint('PLATFORM_CAPABILITY_HAPTIC_PULSE $pulseResult');

    expect(report.platform, isIn(['android', 'ios']));
    expect(report.osVersion, isNotEmpty);
    expect(report.backgroundAudioReadyForSpike, isTrue);

    if (report.platform == 'android') {
      expect(report.foregroundServicePermissionDeclared, isTrue);
      expect(report.mediaPlaybackForegroundServicePermissionDeclared, isTrue);
      expect(report.vibrationPermissionDeclared, isTrue);
      expect(report.backgroundVibrationRequiresForegroundService, isTrue);
    }

    if (report.platform == 'ios') {
      expect(report.backgroundAudioModeDeclared, isTrue);
      expect(report.audioSessionPlaybackCategoryConfigured, isTrue);
    }
  });
}
