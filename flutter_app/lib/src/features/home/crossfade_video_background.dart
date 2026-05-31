import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../content/content_models.dart';
import '../../media/media_resource_resolver.dart';

class CrossfadeVideoBackground extends StatefulWidget {
  const CrossfadeVideoBackground({
    super.key,
    required this.video,
    required this.videoBase,
    required this.enabled,
    this.resource,
    this.onVideoCycleCompleted,
  });

  final VideoItem? video;
  final String videoBase;
  final bool enabled;
  final MediaResource? resource;
  final ValueChanged<VideoItem>? onVideoCycleCompleted;

  @override
  State<CrossfadeVideoBackground> createState() =>
      _CrossfadeVideoBackgroundState();
}

class _CrossfadeVideoBackgroundState extends State<CrossfadeVideoBackground>
    with SingleTickerProviderStateMixin {
  static const _loopPreloadThreshold = Duration(milliseconds: 3500);
  static const _loopFadeDuration = Duration(milliseconds: 3000);
  static const _switchFadeDuration = Duration(milliseconds: 650);
  static const _disposeGraceDuration = Duration(milliseconds: 1200);

  late final AnimationController _fadeController;
  VideoPlayerController? _current;
  VideoPlayerController? _incoming;
  Timer? _monitorTimer;
  final _disposeTasks = <VideoPlayerController, Future<void>>{};
  String? _currentVideoId;
  var _generation = 0;
  var _activationInFlight = false;
  var _reportedCycleGeneration = -1;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(vsync: this);
    if (widget.enabled && widget.video != null) {
      unawaited(_activateVideo(widget.video!, immediate: true));
    }
  }

  @override
  void didUpdateWidget(CrossfadeVideoBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextVideo = widget.video;
    if (!widget.enabled || nextVideo == null) {
      _stopPlayback();
      return;
    }

    if (!oldWidget.enabled ||
        oldWidget.video?.id != nextVideo.id ||
        oldWidget.videoBase != widget.videoBase ||
        oldWidget.resource?.status != widget.resource?.status ||
        oldWidget.resource?.uri != widget.resource?.uri) {
      unawaited(
        _activateVideo(
          nextVideo,
          immediate: _current == null,
          fadeDuration: _switchFadeDuration,
        ),
      );
    }
  }

  @override
  void dispose() {
    _generation += 1;
    _activationInFlight = false;
    _monitorTimer?.cancel();
    _fadeController.dispose();
    final oldCurrent = _current;
    final oldIncoming = _incoming;
    _current = null;
    _incoming = null;
    _currentVideoId = null;
    unawaited(_disposeController(oldCurrent));
    unawaited(_disposeController(oldIncoming));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        _PosterFallback(video: widget.video, enabled: widget.enabled),
        if (_current case final current?)
          _VideoLayer(controller: current, opacity: 1),
        if (_incoming case final incoming?)
          AnimatedBuilder(
            animation: _fadeController,
            builder: (context, child) {
              return _VideoLayer(
                controller: incoming,
                opacity: _fadeController.value,
              );
            },
          ),
      ],
    );
  }

  Future<void> _activateVideo(
    VideoItem video, {
    required bool immediate,
    Duration fadeDuration = _switchFadeDuration,
  }) async {
    final generation = ++_generation;
    _activationInFlight = true;
    final resource = _resourceForVideo(video);
    if (!resource.isPlayable) {
      _stopPlayback();
      return;
    }
    final VideoPlayerController controller;
    try {
      controller = await _createController(resource);
    } catch (_) {
      if (mounted && generation == _generation) {
        _activationInFlight = false;
      }
      return;
    }
    if (!mounted || generation != _generation) {
      await _disposeController(controller);
      return;
    }

    if (immediate || _current == null) {
      final oldCurrent = _current;
      final oldIncoming = _incoming;
      setState(() {
        _current = controller;
        _incoming = null;
        _currentVideoId = video.id;
      });
      await _disposeController(oldCurrent);
      await _disposeController(oldIncoming);
      if (!mounted || generation != _generation) return;
      _activationInFlight = false;
      _startMonitorTimer();
      return;
    }

    final oldIncoming = _incoming;
    setState(() {
      _incoming = controller;
      _fadeController
        ..duration = fadeDuration
        ..value = 0;
    });
    await _disposeController(oldIncoming);

    try {
      await _fadeController.forward(from: 0);
    } on TickerCanceled {
      return;
    }

    if (!mounted || generation != _generation) {
      await _disposeController(controller);
      return;
    }

    final oldCurrent = _current;
    setState(() {
      _current = controller;
      _incoming = null;
      _currentVideoId = video.id;
    });
    await _disposeController(oldCurrent);
    if (!mounted || generation != _generation) return;
    _activationInFlight = false;
    _startMonitorTimer();
  }

  MediaResource _resourceForVideo(VideoItem video) {
    final resource = widget.resource;
    if (resource != null) return resource;
    return MediaResource(
      kind: MediaResourceKind.video,
      id: video.id,
      status: MediaResourceStatus.remote,
      uri: video.remoteVideoUrl(widget.videoBase),
    );
  }

  Future<VideoPlayerController> _createController(
    MediaResource resource,
  ) async {
    final options = VideoPlayerOptions(mixWithOthers: true);
    final controller = switch (resource.status) {
      MediaResourceStatus.bundled => VideoPlayerController.asset(
        resource.uri,
        videoPlayerOptions: options,
      ),
      MediaResourceStatus.cached => VideoPlayerController.file(
        File(resource.uri),
        videoPlayerOptions: options,
      ),
      MediaResourceStatus.remote => VideoPlayerController.networkUrl(
        Uri.parse(resource.uri),
        videoPlayerOptions: options,
      ),
      MediaResourceStatus.removed => throw StateError(
        'Cannot play removed video resource ${resource.id}',
      ),
    };
    await controller.initialize();
    await controller.setLooping(false);
    await controller.setVolume(0);
    await controller.play();
    return controller;
  }

  void _startMonitorTimer() {
    _monitorTimer?.cancel();
    _monitorTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      _maybePreloadLoop();
    });
  }

  void _maybePreloadLoop() {
    final current = _current;
    final video = widget.video;
    if (current == null ||
        video == null ||
        _incoming != null ||
        _activationInFlight ||
        _currentVideoId != video.id ||
        !current.value.isInitialized) {
      return;
    }

    final duration = current.value.duration;
    if (duration == Duration.zero) return;

    final remaining = duration - current.value.position;
    if (remaining <= _loopPreloadThreshold &&
        current.value.position > const Duration(seconds: 1)) {
      if (_reportedCycleGeneration != _generation) {
        _reportedCycleGeneration = _generation;
        widget.onVideoCycleCompleted?.call(video);
      }
      unawaited(
        _activateVideo(
          video,
          immediate: false,
          fadeDuration: _loopFadeDuration,
        ),
      );
    }
  }

  void _stopPlayback() {
    _generation += 1;
    _activationInFlight = false;
    _monitorTimer?.cancel();
    _monitorTimer = null;
    final oldCurrent = _current;
    final oldIncoming = _incoming;
    if (mounted) {
      setState(() {
        _current = null;
        _incoming = null;
        _currentVideoId = null;
      });
    } else {
      _current = null;
      _incoming = null;
      _currentVideoId = null;
    }
    unawaited(_disposeController(oldCurrent));
    unawaited(_disposeController(oldIncoming));
  }

  Future<void> _disposeController(VideoPlayerController? controller) async {
    if (controller == null) return;
    final existingTask = _disposeTasks[controller];
    if (existingTask != null) return existingTask;

    late final Future<void> task;
    task = Future<void>.delayed(_disposeGraceDuration)
        .then((_) => controller.dispose())
        .catchError((_) {
          // Disposal is best-effort; stale platform callbacks should not crash UI.
        })
        .whenComplete(() {
          _disposeTasks.remove(controller);
        });
    _disposeTasks[controller] = task;
    return task;
  }
}

class _VideoLayer extends StatelessWidget {
  const _VideoLayer({required this.controller, required this.opacity});

  final VideoPlayerController controller;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    if (!controller.value.isInitialized) return const SizedBox.shrink();

    final size = controller.value.size;
    if (size.width <= 0 || size.height <= 0) return const SizedBox.shrink();

    return Opacity(
      opacity: opacity,
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: VideoPlayer(controller),
        ),
      ),
    );
  }
}

class _PosterFallback extends StatelessWidget {
  const _PosterFallback({required this.video, required this.enabled});

  final VideoItem? video;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final url = video?.previewImage ?? '';
    if (!enabled || url.isEmpty) return const _FallbackGradient();
    return Image.network(
      url,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => const _FallbackGradient(),
    );
  }
}

class _FallbackGradient extends StatelessWidget {
  const _FallbackGradient();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF111A1F), Color(0xFF1D342F), Color(0xFF0A0D11)],
        ),
      ),
    );
  }
}
