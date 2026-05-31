import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:just_audio/just_audio.dart';

import '../../content/content_models.dart';
import '../../platform/background_audio_service.dart';

class AmbientAudioEngine extends StatefulWidget {
  const AmbientAudioEngine({
    super.key,
    required this.enabled,
    required this.mix,
    this.backgroundAudioBridge = const BackgroundAudioServiceBridge(),
    this.useAndroidBackgroundService = true,
  });

  final bool enabled;
  final AmbientMix? mix;
  final BackgroundAudioServiceBridge backgroundAudioBridge;
  final bool useAndroidBackgroundService;

  @override
  State<AmbientAudioEngine> createState() => _AmbientAudioEngineState();
}

class _AmbientAudioEngineState extends State<AmbientAudioEngine> {
  final _channels = <String, _AmbientChannel>{};

  bool get _usesBackgroundService =>
      widget.useAndroidBackgroundService &&
      defaultTargetPlatform == TargetPlatform.android;

  @override
  void initState() {
    super.initState();
    _syncPlayback();
  }

  @override
  void didUpdateWidget(AmbientAudioEngine oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled != widget.enabled ||
        oldWidget.mix?.id != widget.mix?.id) {
      _syncPlayback();
      return;
    }

    final oldTracks = oldWidget.mix?.tracks ?? const <ResolvedAmbientTrack>[];
    final nextTracks = widget.mix?.tracks ?? const <ResolvedAmbientTrack>[];
    if (!_sameTrackTargets(oldTracks, nextTracks)) {
      _syncPlayback();
    }
  }

  @override
  void dispose() {
    if (_usesBackgroundService) {
      unawaited(_stopBackgroundService());
    }
    for (final channel in _channels.values) {
      unawaited(channel.disposeNow());
    }
    _channels.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();

  void _syncPlayback() {
    if (_usesBackgroundService) {
      for (final channel in _channels.values) {
        unawaited(channel.disposeNow());
      }
      _channels.clear();
      unawaited(_syncBackgroundService());
      return;
    }
    unawaited(_syncChannels());
  }

  Future<void> _syncBackgroundService() async {
    final mix = widget.mix;
    try {
      if (!widget.enabled || mix == null) {
        await widget.backgroundAudioBridge.stop();
        return;
      }
      await widget.backgroundAudioBridge.sync(
        tracks: mix.tracks
            .map(
              (track) => BackgroundAudioTrack(
                channelId: track.channelId,
                mediaId: track.id,
                title: track.label,
                uri: track.url,
                durationMs: track.durationMs,
                volume: track.volume,
              ),
            )
            .toList(growable: false),
      );
    } on MissingPluginException {
      return;
    }
  }

  Future<void> _stopBackgroundService() async {
    try {
      await widget.backgroundAudioBridge.stop();
    } on MissingPluginException {
      return;
    }
  }

  Future<void> _syncChannels() async {
    final mix = widget.mix;
    if (!widget.enabled || mix == null) {
      final existing = _channels.values.toList(growable: false);
      _channels.clear();
      for (final channel in existing) {
        unawaited(channel.fadeOutAndDispose());
      }
      return;
    }

    final desired = {for (final track in mix.tracks) track.channelId: track};

    for (final entry in desired.entries) {
      final existing = _channels[entry.key];
      if (existing == null) {
        final channel = _AmbientChannel(entry.value);
        _channels[entry.key] = channel;
        unawaited(channel.start());
      } else {
        existing.updateTrack(entry.value);
      }
    }

    final removedKeys = _channels.keys
        .where((key) => !desired.containsKey(key))
        .toList(growable: false);
    for (final key in removedKeys) {
      final removed = _channels.remove(key);
      if (removed != null) unawaited(removed.fadeOutAndDispose());
    }
  }

  bool _sameTrackTargets(
    List<ResolvedAmbientTrack> previous,
    List<ResolvedAmbientTrack> next,
  ) {
    if (previous.length != next.length) return false;
    final previousByChannel = {
      for (final track in previous) track.channelId: track,
    };
    for (final track in next) {
      final old = previousByChannel[track.channelId];
      if (old == null ||
          old.url != track.url ||
          old.volume != track.volume ||
          old.durationMs != track.durationMs) {
        return false;
      }
    }
    return true;
  }
}

class _AmbientChannel {
  _AmbientChannel(this._track);

  static const _loopFadeDuration = Duration(milliseconds: 6000);
  static const _switchFadeDuration = Duration(milliseconds: 900);
  static const _fadeTick = Duration(milliseconds: 60);

  ResolvedAmbientTrack _track;
  AudioPlayer? _current;
  AudioPlayer? _next;
  Timer? _loopTimer;
  final _fadeTimers = <Timer>{};
  final _volumes = <AudioPlayer, double>{};
  final _stateSubscriptions = <AudioPlayer, StreamSubscription<PlayerState>>{};
  var _disposed = false;
  var _starting = false;

  Future<void> start() async {
    if (_disposed || _starting || _current != null) return;
    _starting = true;
    final player = await _createPlayer(_track, initialVolume: 0);
    _starting = false;
    if (_disposed) {
      if (player != null) {
        await _cancelPlayerSubscription(player);
        await player.dispose();
      }
      return;
    }
    if (player == null) return;
    _current = player;
    _fade(player, from: 0, to: _track.volume, duration: _switchFadeDuration);
    _scheduleLoop();
  }

  void updateTrack(ResolvedAmbientTrack track) {
    final urlChanged = track.url != _track.url;
    _track = track;

    if (urlChanged) {
      unawaited(_replaceWith(track));
      return;
    }

    for (final player in [_current, _next].whereType<AudioPlayer>()) {
      _fade(
        player,
        from: _volumes[player] ?? 0,
        to: track.volume,
        duration: _switchFadeDuration,
      );
    }
    _scheduleLoop();
  }

  Future<void> fadeOutAndDispose() async {
    if (_disposed) return;
    _disposed = true;
    _loopTimer?.cancel();
    final players = [
      _current,
      _next,
    ].whereType<AudioPlayer>().toList(growable: false);
    if (players.isEmpty) {
      _cancelFadeTimers();
      return;
    }

    await Future.wait(
      players.map(
        (player) => _fade(
          player,
          from: _volumes[player] ?? _track.volume,
          to: 0,
          duration: _switchFadeDuration,
          disposeOnComplete: true,
        ),
      ),
    );
    _cancelFadeTimers();
    _current = null;
    _next = null;
  }

  Future<void> disposeNow() async {
    _disposed = true;
    _loopTimer?.cancel();
    _cancelFadeTimers();
    final players = [
      _current,
      _next,
    ].whereType<AudioPlayer>().toList(growable: false);
    _current = null;
    _next = null;
    for (final player in players) {
      await _cancelPlayerSubscription(player);
      await player.dispose();
    }
  }

  Future<void> _replaceWith(ResolvedAmbientTrack track) async {
    final oldPlayers = [
      _current,
      _next,
    ].whereType<AudioPlayer>().toList(growable: false);
    _current = null;
    _next = null;
    _loopTimer?.cancel();
    for (final player in oldPlayers) {
      unawaited(
        _fade(
          player,
          from: _volumes[player] ?? _track.volume,
          to: 0,
          duration: _switchFadeDuration,
          disposeOnComplete: true,
        ),
      );
    }
    _track = track;
    await start();
  }

  void _scheduleLoop() {
    _loopTimer?.cancel();
    if (_disposed || _current == null) return;

    final duration = Duration(milliseconds: max(0, _track.durationMs));
    if (duration == Duration.zero) return;

    final position = _current?.position ?? Duration.zero;
    final remaining = duration - position;
    final delay = remaining - _loopFadeDuration;
    _loopTimer = Timer(
      delay > Duration.zero ? delay : Duration.zero,
      () => unawaited(_startLoopCrossfade()),
    );
  }

  Future<void> _startLoopCrossfade() async {
    if (_disposed || _current == null || _next != null) return;
    final next = await _createPlayer(_track, initialVolume: 0);
    if (_disposed) {
      if (next != null) {
        await _cancelPlayerSubscription(next);
        await next.dispose();
      }
      return;
    }
    if (next == null) {
      _scheduleLoop();
      return;
    }

    final previous = _current;
    _next = next;
    if (previous != null) {
      unawaited(
        _fade(
          previous,
          from: _volumes[previous] ?? _track.volume,
          to: 0,
          duration: _loopFadeDuration,
          disposeOnComplete: true,
        ),
      );
    }
    await _fade(next, from: 0, to: _track.volume, duration: _loopFadeDuration);
    if (_disposed) return;
    _current = next;
    _next = null;
    _scheduleLoop();
  }

  Future<AudioPlayer?> _createPlayer(
    ResolvedAmbientTrack track, {
    required double initialVolume,
  }) async {
    final player = AudioPlayer();
    try {
      await player.setLoopMode(LoopMode.off);
      await player.setVolume(initialVolume);
      _volumes[player] = initialVolume;
      await _setAudioSource(player, track.url);
      _stateSubscriptions[player] = player.playerStateStream.listen((state) {
        if (state.processingState == ProcessingState.completed &&
            !_disposed &&
            player == _current) {
          unawaited(_startLoopCrossfade());
        }
      });
      unawaited(player.play());
      return player;
    } catch (_) {
      _volumes.remove(player);
      await player.dispose();
      return null;
    }
  }

  Future<void> _setAudioSource(AudioPlayer player, String uri) {
    if (uri.startsWith('http://') || uri.startsWith('https://')) {
      return player.setUrl(uri);
    }
    if (uri.startsWith('assets/')) {
      return player.setAsset(uri);
    }
    return player.setFilePath(uri);
  }

  Future<void> _fade(
    AudioPlayer player, {
    required double from,
    required double to,
    required Duration duration,
    bool disposeOnComplete = false,
  }) {
    if (_disposed && !disposeOnComplete) return Future<void>.value();
    final completer = Completer<void>();
    final totalMs = max(1, duration.inMilliseconds);
    final startedAt = DateTime.now();
    late final Timer timer;

    timer = Timer.periodic(_fadeTick, (_) async {
      final elapsedMs = DateTime.now().difference(startedAt).inMilliseconds;
      final progress = (elapsedMs / totalMs).clamp(0, 1).toDouble();
      final volume = from + ((to - from) * progress);
      _volumes[player] = volume;
      await player.setVolume(volume);

      if (progress >= 1) {
        timer.cancel();
        _fadeTimers.remove(timer);
        _volumes[player] = to;
        await player.setVolume(to);
        if (disposeOnComplete) {
          _volumes.remove(player);
          await _cancelPlayerSubscription(player);
          await player.dispose();
        }
        if (!completer.isCompleted) completer.complete();
      }
    });

    _fadeTimers.add(timer);
    return completer.future;
  }

  void _cancelFadeTimers() {
    for (final timer in _fadeTimers.toList(growable: false)) {
      timer.cancel();
    }
    _fadeTimers.clear();
  }

  Future<void> _cancelPlayerSubscription(AudioPlayer player) async {
    final subscription = _stateSubscriptions.remove(player);
    await subscription?.cancel();
  }
}
