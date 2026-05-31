import 'package:flutter/services.dart';

const platformCapabilityChannelName = 'huxi_zen/platform_capabilities';

class PlatformCapabilityProbe {
  const PlatformCapabilityProbe({
    MethodChannel channel = const MethodChannel(platformCapabilityChannelName),
  }) : _channel = channel;

  final MethodChannel _channel;

  Future<PlatformCapabilityReport> loadReport() async {
    final raw = await _channel.invokeMapMethod<String, Object?>(
      'capabilityReport',
    );
    return PlatformCapabilityReport.fromJson(raw ?? const {});
  }

  Future<bool> pulseHaptic() async {
    return await _channel.invokeMethod<bool>('pulseHaptic') ?? false;
  }
}

class PlatformCapabilityReport {
  const PlatformCapabilityReport({
    required this.platform,
    required this.osVersion,
    required this.sdkInt,
    required this.backgroundAudioModeDeclared,
    required this.foregroundServicePermissionDeclared,
    required this.mediaPlaybackForegroundServicePermissionDeclared,
    required this.wakeLockPermissionDeclared,
    required this.mediaSessionServiceDeclared,
    required this.postNotificationsPermissionDeclared,
    required this.vibrationPermissionDeclared,
    required this.hapticsAvailable,
    required this.vibrationAvailable,
    required this.amplitudeControlAvailable,
    required this.backgroundVibrationRequiresForegroundService,
    required this.audioSessionPlaybackCategoryConfigured,
    required this.notes,
  });

  final String platform;
  final String osVersion;
  final int sdkInt;
  final bool backgroundAudioModeDeclared;
  final bool foregroundServicePermissionDeclared;
  final bool mediaPlaybackForegroundServicePermissionDeclared;
  final bool wakeLockPermissionDeclared;
  final bool mediaSessionServiceDeclared;
  final bool postNotificationsPermissionDeclared;
  final bool vibrationPermissionDeclared;
  final bool hapticsAvailable;
  final bool vibrationAvailable;
  final bool amplitudeControlAvailable;
  final bool backgroundVibrationRequiresForegroundService;
  final bool audioSessionPlaybackCategoryConfigured;
  final List<String> notes;

  bool get backgroundAudioReadyForSpike {
    if (platform == 'ios') {
      return backgroundAudioModeDeclared &&
          audioSessionPlaybackCategoryConfigured;
    }
    if (platform == 'android') {
      return foregroundServicePermissionDeclared &&
          mediaPlaybackForegroundServicePermissionDeclared &&
          wakeLockPermissionDeclared &&
          mediaSessionServiceDeclared;
    }
    return false;
  }

  bool get foregroundHapticReadyForSpike =>
      hapticsAvailable || vibrationAvailable;

  factory PlatformCapabilityReport.fromJson(Map<String, Object?> json) {
    return PlatformCapabilityReport(
      platform: _string(json['platform']),
      osVersion: _string(json['osVersion']),
      sdkInt: _int(json['sdkInt']),
      backgroundAudioModeDeclared: _bool(json['backgroundAudioModeDeclared']),
      foregroundServicePermissionDeclared: _bool(
        json['foregroundServicePermissionDeclared'],
      ),
      mediaPlaybackForegroundServicePermissionDeclared: _bool(
        json['mediaPlaybackForegroundServicePermissionDeclared'],
      ),
      wakeLockPermissionDeclared: _bool(json['wakeLockPermissionDeclared']),
      mediaSessionServiceDeclared: _bool(json['mediaSessionServiceDeclared']),
      postNotificationsPermissionDeclared: _bool(
        json['postNotificationsPermissionDeclared'],
      ),
      vibrationPermissionDeclared: _bool(json['vibrationPermissionDeclared']),
      hapticsAvailable: _bool(json['hapticsAvailable']),
      vibrationAvailable: _bool(json['vibrationAvailable']),
      amplitudeControlAvailable: _bool(json['amplitudeControlAvailable']),
      backgroundVibrationRequiresForegroundService: _bool(
        json['backgroundVibrationRequiresForegroundService'],
      ),
      audioSessionPlaybackCategoryConfigured: _bool(
        json['audioSessionPlaybackCategoryConfigured'],
      ),
      notes: _stringList(json['notes']),
    );
  }

  Map<String, Object?> toJson() {
    return {
      'platform': platform,
      'osVersion': osVersion,
      'sdkInt': sdkInt,
      'backgroundAudioModeDeclared': backgroundAudioModeDeclared,
      'foregroundServicePermissionDeclared':
          foregroundServicePermissionDeclared,
      'mediaPlaybackForegroundServicePermissionDeclared':
          mediaPlaybackForegroundServicePermissionDeclared,
      'wakeLockPermissionDeclared': wakeLockPermissionDeclared,
      'mediaSessionServiceDeclared': mediaSessionServiceDeclared,
      'postNotificationsPermissionDeclared':
          postNotificationsPermissionDeclared,
      'vibrationPermissionDeclared': vibrationPermissionDeclared,
      'hapticsAvailable': hapticsAvailable,
      'vibrationAvailable': vibrationAvailable,
      'amplitudeControlAvailable': amplitudeControlAvailable,
      'backgroundVibrationRequiresForegroundService':
          backgroundVibrationRequiresForegroundService,
      'audioSessionPlaybackCategoryConfigured':
          audioSessionPlaybackCategoryConfigured,
      'backgroundAudioReadyForSpike': backgroundAudioReadyForSpike,
      'foregroundHapticReadyForSpike': foregroundHapticReadyForSpike,
      'notes': notes,
    };
  }
}

String _string(Object? value) => value?.toString().trim() ?? '';

int _int(Object? value) {
  if (value is int) return value;
  if (value is num) return value.round();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

bool _bool(Object? value) {
  if (value is bool) return value;
  final text = value?.toString().toLowerCase().trim();
  return text == 'true' || text == '1';
}

List<String> _stringList(Object? value) {
  if (value is! List) return const [];
  return value
      .map((item) => item.toString().trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}
