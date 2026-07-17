import 'dart:convert';

import 'package:flutter/services.dart';

const backgroundAudioServiceChannelName = 'huxi_zen/background_audio';

class BackgroundAudioServiceBridge {
  const BackgroundAudioServiceBridge({
    MethodChannel channel = const MethodChannel(
      backgroundAudioServiceChannelName,
    ),
  }) : _channel = channel;

  final MethodChannel _channel;

  Future<bool> start({required List<BackgroundAudioTrack> tracks}) async {
    final started = await _sendTracks('start', tracks);
    return started ?? false;
  }

  Future<bool> sync({required List<BackgroundAudioTrack> tracks}) async {
    if (tracks.isEmpty) return stop();
    final synced = await _sendTracks('sync', tracks);
    return synced ?? false;
  }

  Future<bool> stop() async {
    final stopped = await _channel.invokeMethod<bool>('stop');
    return stopped ?? false;
  }

  Future<bool> startHapticPattern({
    required BackgroundHapticPattern pattern,
  }) async {
    final started = await _channel.invokeMethod<bool>('startHapticPattern', {
      'patternJson': jsonEncode(pattern.toJson()),
    });
    return started ?? false;
  }

  Future<bool> stopHaptics() async {
    final stopped = await _channel.invokeMethod<bool>('stopHaptics');
    return stopped ?? false;
  }

  Future<bool> playCompletionHaptic() async {
    final played = await _channel.invokeMethod<bool>('playCompletionHaptic');
    return played ?? false;
  }

  Future<BackgroundAudioServiceStatus> status() async {
    final raw = await _channel.invokeMapMethod<String, Object?>('status');
    return BackgroundAudioServiceStatus.fromJson(raw ?? const {});
  }

  Future<bool?> _sendTracks(String method, List<BackgroundAudioTrack> tracks) {
    if (tracks.isEmpty) return Future<bool?>.value(false);
    return _channel.invokeMethod<bool>(method, {
      'tracksJson': jsonEncode(
        tracks.map((track) => track.toJson()).toList(growable: false),
      ),
    });
  }
}

class BackgroundAudioTrack {
  const BackgroundAudioTrack({
    this.channelId = '',
    required this.mediaId,
    required this.title,
    required this.uri,
    this.durationMs = 0,
    this.volume = 1,
  });

  final String channelId;
  final String mediaId;
  final String title;
  final String uri;
  final int durationMs;
  final double volume;

  Map<String, Object?> toJson() => {
    'channelId': channelId,
    'mediaId': mediaId,
    'title': title,
    'uri': uri,
    'durationMs': durationMs,
    'volume': volume,
  };
}

class BackgroundHapticPattern {
  const BackgroundHapticPattern({
    required this.patternId,
    required this.phases,
    this.repeat = true,
    this.cycles = 0,
  });

  final String patternId;
  final List<BackgroundHapticPhase> phases;
  final bool repeat;
  final int cycles;

  Map<String, Object?> toJson() => {
    'patternId': patternId,
    'repeat': repeat,
    'cycles': cycles,
    'phases': phases.map((phase) => phase.toJson()).toList(growable: false),
  };
}

class BackgroundHapticPhase {
  const BackgroundHapticPhase({
    required this.label,
    required this.durationMs,
    this.vibrateMs = 45,
    this.amplitude = 96,
  });

  final String label;
  final int durationMs;
  final int vibrateMs;
  final int amplitude;

  Map<String, Object?> toJson() => {
    'label': label,
    'durationMs': durationMs,
    'vibrateMs': vibrateMs,
    'amplitude': amplitude,
  };
}

class BackgroundAudioServiceStatus {
  const BackgroundAudioServiceStatus({
    required this.platform,
    required this.mediaSessionServiceDeclared,
    required this.running,
    required this.trackCount,
    required this.lastCommand,
    required this.primaryUri,
    required this.playbackState,
    required this.lastError,
    required this.activeChannelIds,
    required this.hapticsRunning,
    required this.hapticPatternId,
    required this.hapticPhase,
    required this.hapticPhaseIndex,
  });

  final String platform;
  final bool mediaSessionServiceDeclared;
  final bool running;
  final int trackCount;
  final String lastCommand;
  final String primaryUri;
  final String playbackState;
  final String lastError;
  final List<String> activeChannelIds;
  final bool hapticsRunning;
  final String hapticPatternId;
  final String hapticPhase;
  final int hapticPhaseIndex;

  factory BackgroundAudioServiceStatus.fromJson(Map<String, Object?> json) {
    return BackgroundAudioServiceStatus(
      platform: _string(json['platform']),
      mediaSessionServiceDeclared: _bool(json['mediaSessionServiceDeclared']),
      running: _bool(json['running']),
      trackCount: _int(json['trackCount']),
      lastCommand: _string(json['lastCommand']),
      primaryUri: _string(json['primaryUri']),
      playbackState: _string(json['playbackState']),
      lastError: _string(json['lastError']),
      activeChannelIds: _stringList(json['activeChannelIds']),
      hapticsRunning: _bool(json['hapticsRunning']),
      hapticPatternId: _string(json['hapticPatternId']),
      hapticPhase: _string(json['hapticPhase']),
      hapticPhaseIndex: _int(json['hapticPhaseIndex']),
    );
  }

  Map<String, Object?> toJson() => {
    'platform': platform,
    'mediaSessionServiceDeclared': mediaSessionServiceDeclared,
    'running': running,
    'trackCount': trackCount,
    'lastCommand': lastCommand,
    'primaryUri': primaryUri,
    'playbackState': playbackState,
    'lastError': lastError,
    'activeChannelIds': activeChannelIds,
    'hapticsRunning': hapticsRunning,
    'hapticPatternId': hapticPatternId,
    'hapticPhase': hapticPhase,
    'hapticPhaseIndex': hapticPhaseIndex,
  };
}

String _string(Object? value) => value?.toString() ?? '';

bool _bool(Object? value) => value == true;

int _int(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

List<String> _stringList(Object? value) {
  if (value is! List) return const [];
  return value
      .map((item) => item.toString())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}
