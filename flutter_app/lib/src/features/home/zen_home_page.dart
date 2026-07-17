import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../content/ambient_resolver.dart';
import '../../content/content_models.dart';
import '../../content/content_repository.dart';
import '../../content/quote_repository.dart';
import '../../content/remote_content_sync.dart';
import '../../media/bundled_media_catalog.dart';
import '../../media/media_ambient_download_queue.dart';
import '../../media/media_cache_index.dart';
import '../../media/media_download_service.dart';
import '../../media/media_resource_resolver.dart';
import '../../media/media_video_prefetch_queue.dart';
import '../../media/remote_file_client.dart';
import '../../preferences/user_preferences.dart';
import '../../weather/weather_repository.dart';
import '../breathing/breathing_models.dart';
import '../breathing/breathing_page.dart';
import '../licenses/license_page.dart' as app_license;
import 'ambient_audio_engine.dart';
import 'crossfade_video_background.dart';

const _favoriteScope = 'favorites';

const _categoryOptions = [
  CategoryOption(value: 'all', label: '全部'),
  CategoryOption(value: _favoriteScope, label: '收藏'),
  CategoryOption(value: 'Landscapes', label: '自然景观'),
  CategoryOption(value: 'AnimalsAndPlants', label: '动植物'),
  CategoryOption(value: 'Motion', label: '运转'),
  CategoryOption(value: 'Underwater', label: '水下景观'),
];

class ZenHomePage extends StatefulWidget {
  const ZenHomePage({
    super.key,
    required this.repository,
    required this.loadRemoteImages,
    this.contentSyncService,
    this.remoteManifestUri,
    this.onRemoteContentCheck,
    this.enableMediaDownloads = true,
    this.mediaCacheRoot,
    this.mediaDownloadClient,
    this.onMediaDownloaded,
    this.bundledMediaCatalog,
    this.weatherRepository,
    this.quoteRepository = const AssetQuoteRepository(),
  });

  final ContentRepository repository;
  final bool loadRemoteImages;
  final ContentSyncService? contentSyncService;
  final Uri? remoteManifestUri;
  final ValueChanged<RemoteContentCheck>? onRemoteContentCheck;
  final bool enableMediaDownloads;
  final Directory? mediaCacheRoot;
  final RemoteFileClient? mediaDownloadClient;
  final ValueChanged<MediaDownloadResult>? onMediaDownloaded;
  final MediaResourceCatalog? bundledMediaCatalog;
  final WeatherForecastRepository? weatherRepository;
  final QuoteRepository quoteRepository;

  @override
  State<ZenHomePage> createState() => _ZenHomePageState();
}

class _ZenHomePageState extends State<ZenHomePage> with WidgetsBindingObserver {
  late final Future<ContentBundle> _contentFuture;
  final _random = Random();
  final _favoriteKeys = <String>{};
  var _scope = 'all';
  var _queue = <VideoItem>[];
  var _queueIndex = 0;
  var _chromeVisible = true;
  var _infoVisible = false;
  var _breathingActive = false;
  var _resumeBreathingAfterLifecycle = false;
  var _ambientOn = false;
  var _settings = const AppSettings.defaults();
  var _mediaCacheIndex = const MediaCacheIndex();
  var _bundledMediaCatalog = const MediaResourceCatalog.empty();
  var _mediaCatalog = const MediaResourceCatalog.empty();
  String? _toastMessage;
  Timer? _toastTimer;
  String? _remoteCheckStartedForVersion;
  MediaVideoPrefetchQueue? _videoPrefetchQueue;
  MediaAmbientDownloadQueue? _ambientDownloadQueue;
  String? _ambientDownloadRequestedForMixId;
  Future<Directory>? _mediaCacheRootFuture;
  HttpRemoteFileClient? _ownedMediaDownloadClient;
  OpenMeteoWeatherRepository? _ownedWeatherRepository;
  WeatherForecast? _forecast;
  var _weatherLoading = false;
  String? _weatherError;
  var _weatherVisible = false;
  var _weatherRequestSerial = 0;
  String? _weatherRequestKey;
  var _quotes = <QuoteItem>[];
  QuoteItem? _currentQuote;
  var _homeHorizontalDragDelta = 0.0;

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _toastTimer?.cancel();
    _ownedMediaDownloadClient?.close(force: true);
    _ownedWeatherRepository?.close(force: true);
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _contentFuture = widget.repository.load().then((content) async {
      final preferences = await UserPreferences.load();
      final loadedCacheIndex = await MediaCacheIndex.load();
      final cleanup = await loadedCacheIndex.cleanupLocalFiles();
      final cacheIndex = cleanup.index;
      if (cleanup.changed) {
        unawaited(cacheIndex.save());
      }
      _favoriteKeys
        ..clear()
        ..addAll(preferences.favoriteKeys);
      _scope = preferences.shuffleScope;
      _settings = preferences.settings;
      _quotes = await widget.quoteRepository.load().catchError(
        (_) => const <QuoteItem>[],
      );
      _currentQuote ??= _pickQuote();
      _bundledMediaCatalog =
          widget.bundledMediaCatalog ?? await loadBundledMediaCatalog(content);
      _mediaCacheIndex = cacheIndex;
      _mediaCatalog = cacheIndex.toResourceCatalog(
        bundled: _bundledMediaCatalog,
      );
      _resetQueue(content);
      _refreshWeatherFromSettings(_settings);
      _startRemoteContentCheck(content);
      return content;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _resumeAfterLifecyclePause();
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        _hideTransientOverlaysForLifecyclePause();
      case AppLifecycleState.detached:
        _suspendForLifecycleDetach();
    }
  }

  void _startRemoteContentCheck(ContentBundle content) {
    final syncService = widget.contentSyncService;
    final manifestUri = widget.remoteManifestUri;
    if (syncService == null || manifestUri == null) return;
    if (_remoteCheckStartedForVersion == content.manifest.contentVersion) {
      return;
    }
    _remoteCheckStartedForVersion = content.manifest.contentVersion;

    unawaited(
      syncService
          .checkManifest(
            localManifest: content.manifest,
            remoteManifestUri: manifestUri,
          )
          .then((check) {
            unawaited(_reconcileRemoteMediaChanges(check));
            widget.onRemoteContentCheck?.call(check);
          })
          .catchError((_) {
            // Startup must stay offline-first. A failed manifest check should
            // never block the bundled content path.
          }),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ContentBundle>(
      future: _contentFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _LoadError(error: snapshot.error);
        }
        if (!snapshot.hasData) {
          return const _LoadingView();
        }

        final content = snapshot.requireData;
        final video = _currentVideo;
        final mediaResolver = MediaResourceResolver(
          content,
          catalog: _mediaCatalog,
        );
        final videoResource = video == null
            ? null
            : mediaResolver.videoResourceFor(video);
        final resolver = AmbientResolver(content, mediaResolver: mediaResolver);
        final ambientMix = _settings.ambientAudioMode == 'custom'
            ? resolver.ambientMixFromCustomSettings(_settings.customAmbientMix)
            : resolver.ambientTrackForVideo(video);
        _queueAmbientDownload(content, ambientMix);
        final isFavorite =
            video != null &&
            _favoriteKeys.contains(_favoriteKey(content, video));

        return Scaffold(
          body: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onHorizontalDragEnd: _breathingActive
                ? null
                : (details) => _handleHomeHorizontalDragEnd(content, details),
            onHorizontalDragStart: _breathingActive
                ? null
                : (_) => _homeHorizontalDragDelta = 0,
            onHorizontalDragUpdate: _breathingActive
                ? null
                : (details) {
                    _homeHorizontalDragDelta += details.primaryDelta ?? 0;
                  },
            child: Stack(
              fit: StackFit.expand,
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => _chromeVisible = !_chromeVisible),
                  onDoubleTap: video == null
                      ? null
                      : () => _toggleFavorite(content, video),
                  onVerticalDragEnd: (details) {
                    final velocity = details.primaryVelocity ?? 0;
                    if (velocity < -220) _nextVideo(content);
                    if (velocity > 220) _previousVideo();
                  },
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      CrossfadeVideoBackground(
                        video: video,
                        videoBase: content.config.defaultVideoBase,
                        enabled: widget.loadRemoteImages,
                        resource: videoResource,
                        onVideoCycleCompleted: (video) =>
                            _handleVideoCycleCompleted(content, video),
                      ),
                      const _BackgroundScrim(),
                    ],
                  ),
                ),
                AnimatedOpacity(
                  opacity: _chromeVisible && !_breathingActive ? 1 : 0,
                  duration: const Duration(milliseconds: 220),
                  child: IgnorePointer(
                    ignoring: !_chromeVisible || _breathingActive,
                    child: _HomeChrome(
                      video: video,
                      quote: _currentQuote,
                      ambientMix: ambientMix,
                      ambientOn: _ambientOn,
                      emptyFavorites:
                          _scope == _favoriteScope && _queue.isEmpty,
                      isFavorite: isFavorite,
                      settings: _settings,
                      forecast: _forecast,
                      weatherLoading: _weatherLoading,
                      weatherError: _weatherError,
                      onOpenBreathing: _enterBreathing,
                      onOpenSettings: () => _openSettings(content),
                      onToggleAmbient: () =>
                          setState(() => _ambientOn = !_ambientOn),
                      onNextQuote: _nextQuote,
                      onToggleInfo: () => setState(() {
                        _infoVisible = !_infoVisible;
                        _weatherVisible = false;
                      }),
                      onToggleWeather: _toggleWeather,
                    ),
                  ),
                ),
                if (_weatherVisible && _forecast != null && _chromeVisible)
                  _WeatherInfoPanel(
                    forecast: _forecast!,
                    onClose: () => setState(() => _weatherVisible = false),
                  ),
                if (_infoVisible && video != null && _chromeVisible)
                  _VideoInfoOverlay(
                    video: video,
                    isFavorite: isFavorite,
                    onToggleFavorite: () => _toggleFavorite(content, video),
                    onClose: () => setState(() => _infoVisible = false),
                  ),
                AmbientAudioEngine(enabled: _ambientOn, mix: ambientMix),
                if (_breathingActive)
                  BreathingOverlay(
                    settings: _settings,
                    ambientOn: _ambientOn,
                    ambientAvailable: ambientMix != null,
                    ambientLabel: ambientMix?.label ?? '无音轨',
                    onSettingsChanged: _handleBreathingSettingsChanged,
                    onToggleAmbient: () =>
                        setState(() => _ambientOn = !_ambientOn),
                    onExit: _exitBreathing,
                  ),
                if (_toastMessage != null)
                  _ToastMessage(message: _toastMessage!),
              ],
            ),
          ),
        );
      },
    );
  }

  void _enterBreathing() {
    var nextSettings = _settings;
    final shouldResetCues =
        !_settings.rememberZenCues &&
        (_settings.zenHaptics || _settings.zenSound || _settings.zenVoiceCue);
    if (shouldResetCues) {
      nextSettings = _settings.copyWith(
        zenHaptics: false,
        zenSound: false,
        zenVoiceCue: false,
      );
      unawaited(UserPreferences.saveSettings(nextSettings));
    }
    setState(() {
      _settings = nextSettings;
      _breathingActive = true;
      _infoVisible = false;
      _chromeVisible = true;
    });
  }

  void _exitBreathing() {
    setState(() => _breathingActive = false);
  }

  void _handleBreathingSettingsChanged(AppSettings settings) {
    setState(() => _settings = settings);
    unawaited(UserPreferences.saveSettings(settings));
  }

  void _hideTransientOverlaysForLifecyclePause() {
    if (!_infoVisible && !_weatherVisible) return;
    setState(() {
      _infoVisible = false;
      _weatherVisible = false;
    });
  }

  void _suspendForLifecycleDetach() {
    final shouldResumeBreathing =
        _resumeBreathingAfterLifecycle || _breathingActive;
    final nextSettings = _settings.copyWith(
      zenHaptics: _settings.rememberZenCues ? _settings.zenHaptics : false,
      zenSound: false,
      zenVoiceCue: false,
    );
    final settingsChanged =
        nextSettings.zenHaptics != _settings.zenHaptics ||
        nextSettings.zenSound != _settings.zenSound ||
        nextSettings.zenVoiceCue != _settings.zenVoiceCue;

    if (!_breathingActive &&
        _resumeBreathingAfterLifecycle == shouldResumeBreathing &&
        !_ambientOn &&
        !_infoVisible &&
        !settingsChanged) {
      return;
    }

    setState(() {
      _resumeBreathingAfterLifecycle = shouldResumeBreathing;
      _breathingActive = false;
      _ambientOn = false;
      _infoVisible = false;
      _settings = nextSettings;
    });
    if (settingsChanged) {
      unawaited(UserPreferences.saveSettings(nextSettings));
    }
  }

  void _resumeAfterLifecyclePause() {
    if (!_resumeBreathingAfterLifecycle) return;
    setState(() {
      _resumeBreathingAfterLifecycle = false;
      _breathingActive = true;
      _chromeVisible = true;
      _infoVisible = false;
    });
  }

  VideoItem? get _currentVideo {
    if (_queue.isEmpty || _queueIndex < 0 || _queueIndex >= _queue.length) {
      return null;
    }
    return _queue[_queueIndex];
  }

  QuoteItem? _pickQuote([String? currentContent]) {
    if (_quotes.isEmpty) return null;
    if (_quotes.length == 1) return _quotes.first;

    var picked = _quotes[_random.nextInt(_quotes.length)];
    while (picked.content == currentContent) {
      picked = _quotes[_random.nextInt(_quotes.length)];
    }
    return picked;
  }

  void _nextQuote() {
    final next = _pickQuote(_currentQuote?.content);
    if (next == null) return;
    setState(() => _currentQuote = next);
  }

  Future<void> _openSettings(ContentBundle content) async {
    final result = await Navigator.of(context).push<_SettingsResult>(
      MaterialPageRoute(
        builder: (context) => _SettingsPage(
          content: content,
          mediaCatalog: _mediaCatalog,
          selectedScope: _scope,
          settings: _settings,
          favoriteCount: _favoriteKeys.length,
          videoCount: content.publishedVideos.length,
          maxCustomAmbientTracks: content.ambientCatalog.maxCustomAmbientTracks,
          customTrackOptions: AmbientResolver(
            content,
          ).customAmbientTrackOptions(),
        ),
      ),
    );
    if (result != null && mounted) {
      final previousSettings = _settings;
      setState(() {
        _settings = result.settings;
      });
      unawaited(UserPreferences.saveSettings(result.settings));
      if (result.scope != _scope) {
        _changeScope(content, result.scope);
      }
      if (_weatherSettingsChanged(previousSettings, result.settings)) {
        _refreshWeatherFromSettings(result.settings);
      }
    }
  }

  void _handleHomeHorizontalDragEnd(
    ContentBundle content,
    DragEndDetails details,
  ) {
    final velocity = details.primaryVelocity ?? 0;
    final delta = _homeHorizontalDragDelta;
    _homeHorizontalDragDelta = 0;
    if (velocity < -220 || delta < -96) _openSettings(content);
    if (velocity > 220 || delta > 96) _enterBreathing();
  }

  void _changeScope(ContentBundle content, String scope) {
    setState(() {
      _scope = scope;
      _infoVisible = false;
      _resetQueue(content, avoidVideoId: _currentVideo?.id);
    });
    unawaited(UserPreferences.saveShuffleScope(scope));
  }

  void _nextVideo(ContentBundle content) {
    if (_queue.isEmpty) return;
    setState(() {
      _infoVisible = false;
      if (_queueIndex < _queue.length - 1) {
        _queueIndex += 1;
      } else {
        _resetQueue(content, avoidVideoId: _currentVideo?.id);
      }
    });
  }

  void _previousVideo() {
    if (_queueIndex <= 0) return;
    setState(() {
      _infoVisible = false;
      _queueIndex -= 1;
    });
  }

  void _toggleFavorite(ContentBundle content, VideoItem video) {
    final key = _favoriteKey(content, video);
    late final String message;
    setState(() {
      if (_favoriteKeys.contains(key)) {
        _favoriteKeys.remove(key);
        message = '已取消收藏';
      } else {
        _favoriteKeys.add(key);
        message = '收藏成功';
      }
      if (_scope == _favoriteScope) {
        _resetQueue(content, avoidVideoId: video.id);
      }
      _toastMessage = message;
    });
    unawaited(UserPreferences.saveFavoriteKeys(_favoriteKeys));
    _toastTimer?.cancel();
    _toastTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _toastMessage = null);
    });
  }

  void _resetQueue(ContentBundle content, {String? avoidVideoId}) {
    final videos = _videosForScope(content);
    _queue = videos.toList(growable: true)..shuffle(_random);
    if (avoidVideoId != null &&
        _queue.length > 1 &&
        _queue.first.id == avoidVideoId) {
      final swapIndex = _queue.indexWhere((video) => video.id != avoidVideoId);
      if (swapIndex > 0) {
        final current = _queue.first;
        _queue[0] = _queue[swapIndex];
        _queue[swapIndex] = current;
      }
    }
    _queueIndex = 0;
  }

  List<VideoItem> _videosForScope(ContentBundle content) {
    final videos = content.publishedVideos;
    if (_scope == _favoriteScope) {
      return videos
          .where(
            (video) => _favoriteKeys.contains(_favoriteKey(content, video)),
          )
          .toList(growable: false);
    }
    if (_scope == 'all') return videos;
    final scoped = videos
        .where((video) => video.category == _scope)
        .toList(growable: false);
    return scoped.isEmpty ? videos : scoped;
  }

  String _favoriteKey(ContentBundle content, VideoItem video) {
    return video.favoriteKey(content.config.defaultVideoLibrary);
  }

  void _handleVideoCycleCompleted(ContentBundle content, VideoItem video) {
    if (!widget.enableMediaDownloads) return;
    unawaited(_handleVideoCycleCompletedAsync(content, video));
  }

  Future<void> _handleVideoCycleCompletedAsync(
    ContentBundle content,
    VideoItem video,
  ) async {
    final queue = await _ensureVideoPrefetchQueue(content);
    final result = await queue.markVideoCycleCompleted(
      video: video,
      playbackScope: _videosForScope(content),
      currentVideoId: _currentVideo?.id,
    );
    if (result != null) widget.onMediaDownloaded?.call(result);
  }

  Future<void> _reconcileRemoteMediaChanges(RemoteContentCheck check) async {
    if (!check.media.hasChanges) return;
    final result = await _mediaCacheIndex.reconcileRemoteMediaChanges(
      check.media,
    );
    if (!mounted || !result.changed) return;
    await result.index.save();
    if (!mounted) return;
    setState(() {
      _applyMediaCacheIndex(result.index);
    });
  }

  Future<MediaVideoPrefetchQueue> _ensureVideoPrefetchQueue(
    ContentBundle content,
  ) async {
    final existing = _videoPrefetchQueue;
    if (existing != null) return existing;

    final queue = MediaVideoPrefetchQueue(
      content: content,
      cacheRoot: await _mediaCacheRoot(),
      client: widget.mediaDownloadClient ?? _downloadClient(),
      initialIndex: _mediaCacheIndex,
      bundledCatalog: _bundledMediaCatalog,
      readIndex: () => _mediaCacheIndex,
      onIndexChanged: (index) {
        if (!mounted) return;
        setState(() {
          _applyMediaCacheIndex(index);
        });
      },
    );
    _videoPrefetchQueue = queue;
    return queue;
  }

  void _queueAmbientDownload(ContentBundle content, AmbientMix? mix) {
    if (!widget.enableMediaDownloads || !_ambientOn || mix == null) {
      _ambientDownloadRequestedForMixId = null;
      return;
    }
    if (_ambientDownloadRequestedForMixId == mix.id) return;
    _ambientDownloadRequestedForMixId = mix.id;
    unawaited(_downloadAmbientMix(content, mix));
  }

  Future<void> _downloadAmbientMix(
    ContentBundle content,
    AmbientMix mix,
  ) async {
    final queue = await _ensureAmbientDownloadQueue(content);
    final results = await queue.downloadMissingTracksForMix(mix);
    for (final result in results) {
      widget.onMediaDownloaded?.call(result);
    }
  }

  Future<MediaAmbientDownloadQueue> _ensureAmbientDownloadQueue(
    ContentBundle content,
  ) async {
    final existing = _ambientDownloadQueue;
    if (existing != null) return existing;

    final queue = MediaAmbientDownloadQueue(
      content: content,
      cacheRoot: await _mediaCacheRoot(),
      client: widget.mediaDownloadClient ?? _downloadClient(),
      initialIndex: _mediaCacheIndex,
      bundledCatalog: _bundledMediaCatalog,
      readIndex: () => _mediaCacheIndex,
      onIndexChanged: (index) {
        if (!mounted) return;
        setState(() {
          _applyMediaCacheIndex(index);
        });
      },
    );
    _ambientDownloadQueue = queue;
    return queue;
  }

  void _applyMediaCacheIndex(MediaCacheIndex index) {
    _mediaCacheIndex = index;
    _mediaCatalog = index.toResourceCatalog(bundled: _bundledMediaCatalog);
    _videoPrefetchQueue?.index = index;
    _ambientDownloadQueue?.index = index;
    _ambientDownloadRequestedForMixId = null;
  }

  Future<Directory> _mediaCacheRoot() {
    final injected = widget.mediaCacheRoot;
    if (injected != null) return Future.value(injected);
    return _mediaCacheRootFuture ??= _defaultMediaCacheRoot();
  }

  Future<Directory> _defaultMediaCacheRoot() async {
    final supportRoot = await getApplicationSupportDirectory();
    final root = Directory(
      '${supportRoot.path}${Platform.pathSeparator}media-cache',
    );
    await root.create(recursive: true);
    return root;
  }

  RemoteFileClient _downloadClient() {
    return _ownedMediaDownloadClient ??= HttpRemoteFileClient();
  }

  WeatherForecastRepository get _weatherRepository {
    return widget.weatherRepository ??
        (_ownedWeatherRepository ??= OpenMeteoWeatherRepository());
  }

  void _refreshWeatherFromSettings(AppSettings settings) {
    if (!mounted) return;
    final city = settings.city.trim();
    if (!settings.showWeather || city.isEmpty) {
      setState(() {
        _forecast = null;
        _weatherLoading = false;
        _weatherError = null;
        _weatherVisible = false;
        _weatherRequestKey = null;
      });
      return;
    }

    final requestKey = '${city.toLowerCase()}|${settings.temperatureUnit}';
    if (_weatherLoading && _weatherRequestKey == requestKey) return;
    _weatherRequestKey = requestKey;
    final requestSerial = ++_weatherRequestSerial;
    setState(() {
      _weatherLoading = _forecast == null;
      _weatherError = null;
    });

    unawaited(
      _weatherRepository
          .getForecast(city: city, temperatureUnit: settings.temperatureUnit)
          .then((forecast) {
            if (!mounted || requestSerial != _weatherRequestSerial) return;
            setState(() {
              _forecast = forecast;
              _weatherLoading = false;
              _weatherError = null;
            });
          })
          .catchError((_) {
            if (!mounted || requestSerial != _weatherRequestSerial) return;
            setState(() {
              _weatherLoading = false;
              _weatherError = '天气暂不可用';
              _weatherVisible = false;
            });
          }),
    );
  }

  bool _weatherSettingsChanged(AppSettings before, AppSettings after) {
    return before.showWeather != after.showWeather ||
        before.city.trim() != after.city.trim() ||
        before.temperatureUnit != after.temperatureUnit;
  }

  void _toggleWeather() {
    if (_forecast == null) {
      _refreshWeatherFromSettings(_settings);
      return;
    }
    setState(() {
      _weatherVisible = !_weatherVisible;
      _infoVisible = false;
    });
  }
}

class CategoryOption {
  const CategoryOption({required this.value, required this.label});

  final String value;
  final String label;
}

class _HomeChrome extends StatelessWidget {
  const _HomeChrome({
    required this.video,
    required this.quote,
    required this.ambientMix,
    required this.ambientOn,
    required this.emptyFavorites,
    required this.isFavorite,
    required this.settings,
    required this.forecast,
    required this.weatherLoading,
    required this.weatherError,
    required this.onOpenBreathing,
    required this.onOpenSettings,
    required this.onToggleAmbient,
    required this.onNextQuote,
    required this.onToggleInfo,
    required this.onToggleWeather,
  });

  final VideoItem? video;
  final QuoteItem? quote;
  final AmbientMix? ambientMix;
  final bool ambientOn;
  final bool emptyFavorites;
  final bool isFavorite;
  final AppSettings settings;
  final WeatherForecast? forecast;
  final bool weatherLoading;
  final String? weatherError;
  final VoidCallback onOpenBreathing;
  final VoidCallback onOpenSettings;
  final VoidCallback onToggleAmbient;
  final VoidCallback onNextQuote;
  final VoidCallback onToggleInfo;
  final VoidCallback onToggleWeather;

  @override
  Widget build(BuildContext context) {
    final title = video?.titleForDisplay() ?? '呼吸Zen';
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (settings.showVideoMeta)
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: InkWell(
                        onTap: video == null ? null : onToggleInfo,
                        borderRadius: BorderRadius.circular(6),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 2,
                            vertical: 5,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 17,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Container(
                                width: 44,
                                height: 1,
                                color: Colors.white.withValues(alpha: 0.58),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  )
                else
                  const Spacer(),
                if (settings.showWeather) ...[
                  const SizedBox(width: 10),
                  _WeatherPill(
                    forecast: forecast,
                    loading: weatherLoading,
                    error: weatherError,
                    onTap: onToggleWeather,
                  ),
                ],
              ],
            ),
            const Spacer(),
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (settings.showClock) ...[
                    const _ClockText(),
                    if (settings.showQuote || emptyFavorites)
                      const SizedBox(height: 12),
                  ],
                  if (settings.showQuote && quote != null)
                    _QuoteBlock(quote: quote!, onTap: onNextQuote),
                  if (emptyFavorites) ...[
                    const SizedBox(height: 18),
                    Text(
                      '先收藏视频',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.72),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const Spacer(),
            Row(
              children: [
                _ZenEntryButton(onPressed: onOpenBreathing),
                const Spacer(),
                _BottomActions(
                  ambientOn: ambientOn,
                  ambientAvailable: ambientMix != null,
                  ambientLabel: ambientMix?.label ?? '无音轨',
                  onOpenSettings: onOpenSettings,
                  onToggleAmbient: onToggleAmbient,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _QuoteBlock extends StatelessWidget {
  const _QuoteBlock({required this.quote, required this.onTap});

  final QuoteItem quote;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 330),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                quote.content,
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.88),
                  fontSize: 16,
                  height: 1.48,
                  shadows: const [
                    Shadow(
                      color: Color(0x70000000),
                      offset: Offset(0, 3),
                      blurRadius: 14,
                    ),
                  ],
                ),
              ),
              if (quote.author.isNotEmpty) ...[
                const SizedBox(height: 7),
                Text(
                  '- ${quote.author}',
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.66),
                    fontSize: 12,
                    shadows: const [
                      Shadow(
                        color: Color(0x66000000),
                        offset: Offset(0, 2),
                        blurRadius: 10,
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ZenEntryButton extends StatelessWidget {
  const _ZenEntryButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '呼吸页',
      child: IconButton(
        key: const ValueKey('open-breathing-button'),
        onPressed: onPressed,
        icon: const Icon(Icons.self_improvement_rounded),
        color: Colors.white.withValues(alpha: 0.82),
        iconSize: 25,
        style: IconButton.styleFrom(
          backgroundColor: Colors.white.withValues(alpha: 0.15),
          minimumSize: const Size.square(44),
          shape: const CircleBorder(),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.10)),
        ),
      ),
    );
  }
}

class _BottomActions extends StatelessWidget {
  const _BottomActions({
    required this.ambientOn,
    required this.ambientAvailable,
    required this.ambientLabel,
    required this.onOpenSettings,
    required this.onToggleAmbient,
  });

  final bool ambientOn;
  final bool ambientAvailable;
  final String ambientLabel;
  final VoidCallback onOpenSettings;
  final VoidCallback onToggleAmbient;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _PlainTextButton(
          key: const ValueKey('open-settings-button'),
          label: '···',
          semanticLabel: '设置',
          onPressed: onOpenSettings,
        ),
        const SizedBox(width: 18),
        _PlainTextButton(
          label: '♪',
          semanticLabel: ambientLabel,
          active: ambientOn,
          disabled: !ambientAvailable && !ambientOn,
          onPressed: ambientAvailable || ambientOn ? onToggleAmbient : null,
        ),
      ],
    );
  }
}

class _PlainTextButton extends StatelessWidget {
  const _PlainTextButton({
    super.key,
    required this.label,
    required this.semanticLabel,
    required this.onPressed,
    this.active = false,
    this.disabled = false,
  });

  final String label;
  final String semanticLabel;
  final VoidCallback? onPressed;
  final bool active;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    final opacity = disabled
        ? 0.24
        : active
        ? 0.96
        : 0.72;
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
          textStyle: TextStyle(
            fontSize: label == '···' ? 24 : 26,
            fontWeight: FontWeight.w500,
            letterSpacing: label == '···' ? 2 : 0,
          ),
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

class _ToastMessage extends StatelessWidget {
  const _ToastMessage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: MediaQuery.paddingOf(context).bottom + 74,
      child: Center(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.46),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            child: Text(
              message,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.86),
                fontSize: 13,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingsPage extends StatefulWidget {
  const _SettingsPage({
    required this.content,
    required this.mediaCatalog,
    required this.selectedScope,
    required this.settings,
    required this.favoriteCount,
    required this.videoCount,
    required this.maxCustomAmbientTracks,
    required this.customTrackOptions,
  });

  final ContentBundle content;
  final MediaResourceCatalog mediaCatalog;
  final String selectedScope;
  final AppSettings settings;
  final int favoriteCount;
  final int videoCount;
  final int maxCustomAmbientTracks;
  final List<CustomAmbientTrackOption> customTrackOptions;

  @override
  State<_SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<_SettingsPage> {
  late String _selectedScope;
  late AppSettings _settings;
  var _ambientAuditionOn = false;

  @override
  void initState() {
    super.initState();
    _selectedScope = widget.selectedScope;
    _settings = widget.settings;
  }

  @override
  Widget build(BuildContext context) {
    final ambientResolver = AmbientResolver(
      widget.content,
      mediaResolver: MediaResourceResolver(
        widget.content,
        catalog: widget.mediaCatalog,
      ),
    );
    final auditionMix = ambientResolver.ambientMixFromCustomSettings(
      _settings.customAmbientMix,
    );

    return Theme(
      data: ThemeData(
        brightness: Brightness.light,
        fontFamily: 'PingFang SC',
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF47C7A2),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      child: Scaffold(
        backgroundColor: const Color(0xFFF3F6F7),
        body: SafeArea(
          child: Stack(
            children: [
              ListView(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 86),
                children: [
                  _SettingsHeader(onOpenLicenses: _openLicenses),
                  _SettingsSection(
                    title: '显示',
                    children: [
                      _DisplayToggleRow(
                        showClock: _settings.showClock,
                        showWeather: _settings.showWeather,
                        showQuote: _settings.showQuote,
                        showVideoMeta: _settings.showVideoMeta,
                        onClockTap: () => setState(
                          () => _settings = _settings.copyWith(
                            showClock: !_settings.showClock,
                          ),
                        ),
                        onWeatherTap: () => setState(
                          () => _settings = _settings.copyWith(
                            showWeather: !_settings.showWeather,
                          ),
                        ),
                        onQuoteTap: () => setState(
                          () => _settings = _settings.copyWith(
                            showQuote: !_settings.showQuote,
                          ),
                        ),
                        onVideoMetaTap: () => setState(
                          () => _settings = _settings.copyWith(
                            showVideoMeta: !_settings.showVideoMeta,
                          ),
                        ),
                      ),
                      if (_settings.showWeather)
                        _WeatherSettingsRow(
                          city: _settings.city,
                          temperatureUnit: _settings.temperatureUnit,
                          onCityChanged: (value) => setState(
                            () => _settings = _settings.copyWith(city: value),
                          ),
                          onUnitChanged: (value) => setState(
                            () => _settings = _settings.copyWith(
                              temperatureUnit: value,
                            ),
                          ),
                        ),
                      _SwitchRow(
                        label: '保留呼吸页设置',
                        hint: '仅保留呼吸提示音和触感；退出后重新进入仍先静音',
                        value: _settings.rememberZenCues,
                        onChanged: (value) => setState(
                          () => _settings = _settings.copyWith(
                            rememberZenCues: value,
                          ),
                        ),
                      ),
                    ],
                  ),
                  _SettingsPlainCard(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const _SettingsLabel('播放范围'),
                            const SizedBox(height: 8),
                            _ScopeGrid(
                              selectedScope: _selectedScope,
                              favoriteCount: widget.favoriteCount,
                              onChanged: (scope) =>
                                  setState(() => _selectedScope = scope),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  _SettingsPlainCard(
                    children: [
                      _BreathingRhythmSettings(
                        settings: _settings,
                        onChanged: (settings) =>
                            setState(() => _settings = settings),
                      ),
                    ],
                  ),
                  _SettingsPlainCard(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: _InlineSettingsRow(
                          label: '背景音频',
                          child: _SegmentedAudioMode(
                            value: _settings.ambientAudioMode,
                            onChanged: _changeAmbientAudioMode,
                          ),
                        ),
                      ),
                      if (_settings.ambientAudioMode == 'custom') ...[
                        const SizedBox(height: 6),
                        _CustomAmbientControls(
                          options: widget.customTrackOptions,
                          mix: _settings.customAmbientMix,
                          maxSelected: widget.maxCustomAmbientTracks,
                          auditionOn: _ambientAuditionOn,
                          onToggleTrack: _toggleCustomAmbientTrack,
                          onVolumeChanged: _changeCustomAmbientTrackVolume,
                          onToggleAudition: () =>
                              _toggleAmbientAudition(auditionMix),
                        ),
                      ],
                      const SizedBox(height: 8),
                    ],
                  ),
                ],
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _SettingsBottomBar(
                  onSave: () => Navigator.of(context).pop(
                    _SettingsResult(scope: _selectedScope, settings: _settings),
                  ),
                ),
              ),
              AmbientAudioEngine(
                enabled: _ambientAuditionOn,
                mix: auditionMix,
                useAndroidBackgroundService: false,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _changeAmbientAudioMode(String value) {
    setState(() {
      _settings = _settings.copyWith(ambientAudioMode: value);
      if (value != 'custom') _ambientAuditionOn = false;
    });
  }

  void _toggleCustomAmbientTrack(String trackId) {
    final mix = _settings.customAmbientMix.toList(growable: true);
    final index = mix.indexWhere((item) => item.trackId == trackId);

    if (index >= 0) {
      mix.removeAt(index);
    } else if (mix.length >= widget.maxCustomAmbientTracks) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('最多选择 ${widget.maxCustomAmbientTracks} 个声音')),
      );
      return;
    } else {
      mix.add(CustomAmbientSetting(trackId: trackId, volume: 0));
    }

    setState(() {
      _settings = _settings.copyWith(customAmbientMix: List.unmodifiable(mix));
    });
  }

  void _changeCustomAmbientTrackVolume(String trackId, double percent) {
    final volume = (percent / 100).clamp(0, 1).toDouble();
    final mix = _settings.customAmbientMix.toList(growable: true);
    final index = mix.indexWhere((item) => item.trackId == trackId);
    if (index < 0) return;

    mix[index] = CustomAmbientSetting(trackId: trackId, volume: volume);
    setState(() {
      _settings = _settings.copyWith(customAmbientMix: List.unmodifiable(mix));
    });
  }

  void _toggleAmbientAudition(AmbientMix? auditionMix) {
    if (_ambientAuditionOn) {
      setState(() => _ambientAuditionOn = false);
      return;
    }
    if (_settings.customAmbientMix.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('先选择一个声音')));
      return;
    }
    setState(() => _ambientAuditionOn = true);
    if (auditionMix == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('拖动音量开始试听')));
    }
  }

  Future<void> _openLicenses() {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => app_license.LicensePage(content: widget.content),
      ),
    );
  }
}

class _SettingsResult {
  const _SettingsResult({required this.scope, required this.settings});

  final String scope;
  final AppSettings settings;
}

class _SettingsHeader extends StatelessWidget {
  const _SettingsHeader({required this.onOpenLicenses});

  final VoidCallback onOpenLicenses;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: InkWell(
              onTap: onOpenLicenses,
              borderRadius: BorderRadius.circular(6),
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  '© 呼吸Zen',
                  style: TextStyle(
                    color: Color(0xFF15222B),
                    fontSize: 23,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
          const Text(
            '安静的呼吸与风景',
            textAlign: TextAlign.right,
            style: TextStyle(
              color: Color(0xFF6E7C86),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0x1A15222B)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F223A48),
            blurRadius: 18,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 38,
            child: Align(
              alignment: Alignment.centerLeft,
              child: _SettingsLabel(title),
            ),
          ),
          ...children,
        ],
      ),
    );
  }
}

class _SettingsPlainCard extends StatelessWidget {
  const _SettingsPlainCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0x1A15222B)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F223A48),
            blurRadius: 18,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

class _InlineSettingsRow extends StatelessWidget {
  const _InlineSettingsRow({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(width: 72, child: _SettingsLabel(label)),
        const SizedBox(width: 8),
        Expanded(child: child),
      ],
    );
  }
}

class _DisplayToggleRow extends StatelessWidget {
  const _DisplayToggleRow({
    required this.showClock,
    required this.showWeather,
    required this.showQuote,
    required this.showVideoMeta,
    required this.onClockTap,
    required this.onWeatherTap,
    required this.onQuoteTap,
    required this.onVideoMetaTap,
  });

  final bool showClock;
  final bool showWeather;
  final bool showQuote;
  final bool showVideoMeta;
  final VoidCallback onClockTap;
  final VoidCallback onWeatherTap;
  final VoidCallback onQuoteTap;
  final VoidCallback onVideoMetaTap;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0x1215222B))),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: _DisplayTogglePill(
                label: '时间',
                active: showClock,
                onTap: onClockTap,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _DisplayTogglePill(
                label: '天气',
                active: showWeather,
                onTap: onWeatherTap,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _DisplayTogglePill(
                label: '语录',
                active: showQuote,
                onTap: onQuoteTap,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _DisplayTogglePill(
                label: '视频信息',
                active: showVideoMeta,
                onTap: onVideoMetaTap,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DisplayTogglePill extends StatelessWidget {
  const _DisplayTogglePill({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      toggled: active,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? const Color(0xFF47C7A2) : const Color(0xFFE3EAEC),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: active ? const Color(0x0047C7A2) : const Color(0x1215222B),
            ),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              maxLines: 1,
              softWrap: false,
              style: TextStyle(
                color: active ? Colors.white : const Color(0xFF6F7D86),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.label,
    required this.value,
    required this.onChanged,
    this.hint,
  });

  final String label;
  final String? hint;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0x1215222B))),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: Color(0xFF1D2C36),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (hint != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      hint!,
                      style: const TextStyle(
                        color: Color(0xFF7A8792),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            SizedBox(
              width: 52,
              child: Transform.scale(
                scale: 0.84,
                alignment: Alignment.centerRight,
                child: Switch(
                  value: value,
                  activeThumbColor: const Color(0xFF47C7A2),
                  onChanged: onChanged,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WeatherSettingsRow extends StatefulWidget {
  const _WeatherSettingsRow({
    required this.city,
    required this.temperatureUnit,
    required this.onCityChanged,
    required this.onUnitChanged,
  });

  final String city;
  final String temperatureUnit;
  final ValueChanged<String> onCityChanged;
  final ValueChanged<String> onUnitChanged;

  @override
  State<_WeatherSettingsRow> createState() => _WeatherSettingsRowState();
}

class _WeatherSettingsRowState extends State<_WeatherSettingsRow> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.city);
  }

  @override
  void didUpdateWidget(covariant _WeatherSettingsRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.city != _controller.text) {
      _controller.value = TextEditingValue(
        text: widget.city,
        selection: TextSelection.collapsed(offset: widget.city.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0x1215222B))),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F6),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 1,
                  ),
                  child: TextField(
                    key: const ValueKey('weather-city-input'),
                    controller: _controller,
                    onChanged: widget.onCityChanged,
                    textInputAction: TextInputAction.done,
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      hintText: '城市',
                      isDense: true,
                    ),
                    style: const TextStyle(
                      color: Color(0xFF1D2C36),
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            _UnitPill(
              label: '摄氏度',
              active: widget.temperatureUnit == 'celsius',
              onTap: () => widget.onUnitChanged('celsius'),
            ),
            const SizedBox(width: 6),
            _UnitPill(
              label: '华氏度',
              active: widget.temperatureUnit == 'fahrenheit',
              onTap: () => widget.onUnitChanged('fahrenheit'),
            ),
          ],
        ),
      ),
    );
  }
}

class _UnitPill extends StatelessWidget {
  const _UnitPill({
    required this.label,
    required this.onTap,
    this.active = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: active ? const Color(0xFF47C7A2) : const Color(0xFFE7ECEE),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          child: Text(
            label,
            style: TextStyle(
              color: active ? Colors.white : const Color(0xFF40505B),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingsLabel extends StatelessWidget {
  const _SettingsLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: Color(0xFF1D2C36),
        fontSize: 15,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _ScopeGrid extends StatelessWidget {
  const _ScopeGrid({
    required this.selectedScope,
    required this.favoriteCount,
    required this.onChanged,
  });

  final String selectedScope;
  final int favoriteCount;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 38,
      child: Row(
        children: [
          for (var index = 0; index < _categoryOptions.length; index++) ...[
            if (index > 0) const SizedBox(width: 8),
            Expanded(
              child: _ScopePill(
                option: _categoryOptions[index],
                selected: selectedScope == _categoryOptions[index].value,
                disabled:
                    _categoryOptions[index].value == _favoriteScope &&
                    favoriteCount == 0,
                onChanged: onChanged,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ScopePill extends StatelessWidget {
  const _ScopePill({
    required this.option,
    required this.selected,
    required this.disabled,
    required this.onChanged,
  });

  final CategoryOption option;
  final bool selected;
  final bool disabled;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final enabled = !disabled;
    final backgroundColor = selected
        ? const Color(0xFF47C7A2)
        : enabled
        ? const Color(0xFFE3EAEC)
        : const Color(0x55E3EAEC);
    final foregroundColor = selected
        ? Colors.white
        : enabled
        ? const Color(0xFF40505B)
        : const Color(0x667A8792);

    return Semantics(
      button: true,
      enabled: enabled,
      selected: selected,
      label: option.label,
      child: SizedBox.expand(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: enabled ? () => onChanged(option.value) : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOut,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: selected
                    ? const Color(0x0047C7A2)
                    : const Color(0x1215222B),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                option.label,
                maxLines: 2,
                softWrap: true,
                textAlign: TextAlign.center,
                overflow: TextOverflow.visible,
                style: TextStyle(
                  color: foregroundColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  height: 1.05,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BreathingRhythmSettings extends StatelessWidget {
  const _BreathingRhythmSettings({
    required this.settings,
    required this.onChanged,
  });

  final AppSettings settings;
  final ValueChanged<AppSettings> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _BreathingRhythmFormula(
          title: '呼吸节奏- 默认',
          rhythm: settings.defaultBreathRhythm,
          topBorder: false,
          onChanged: (rhythm) =>
              onChanged(settings.copyWith(defaultBreathRhythm: rhythm)),
        ),
        _BreathingRhythmFormula(
          title: '自定义呼吸练习',
          rhythm: settings.customBreathRhythm,
          includeCycles: true,
          onChanged: (rhythm) =>
              onChanged(settings.copyWith(customBreathRhythm: rhythm)),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _BreathingRhythmFormula extends StatelessWidget {
  const _BreathingRhythmFormula({
    required this.title,
    required this.rhythm,
    required this.onChanged,
    this.includeCycles = false,
    this.topBorder = true,
  });

  final String title;
  final BreathingRhythm rhythm;
  final bool includeCycles;
  final bool topBorder;
  final ValueChanged<BreathingRhythm> onChanged;

  @override
  Widget build(BuildContext context) {
    final fieldWidth = includeCycles ? 34.0 : 36.0;
    final arrowWidth = includeCycles ? 13.0 : 15.0;
    final unitWidth = includeCycles ? 30.0 : 18.0;
    final tailUnitWidth = includeCycles ? 18.0 : 18.0;
    final labelCells = [
      _RhythmFormulaLabel('吸气', width: fieldWidth),
      SizedBox(width: arrowWidth),
      _RhythmFormulaLabel('屏息', width: fieldWidth),
      SizedBox(width: arrowWidth),
      _RhythmFormulaLabel('呼气', width: fieldWidth),
      SizedBox(width: arrowWidth),
      _RhythmFormulaLabel('屏息', width: fieldWidth),
      if (includeCycles) ...[
        SizedBox(width: unitWidth),
        _RhythmFormulaLabel('组数', width: fieldWidth),
        SizedBox(width: tailUnitWidth),
      ] else
        SizedBox(width: tailUnitWidth),
    ];
    final inputCells = [
      _RhythmNumberInput(
        value: rhythm.inhaleSeconds,
        min: 1,
        max: 60,
        width: fieldWidth,
        onChanged: (value) => onChanged(rhythm.copyWith(inhaleSeconds: value)),
      ),
      _RhythmArrow(width: arrowWidth),
      _RhythmNumberInput(
        value: rhythm.holdAfterInhaleSeconds,
        min: 0,
        max: 60,
        width: fieldWidth,
        onChanged: (value) =>
            onChanged(rhythm.copyWith(holdAfterInhaleSeconds: value)),
      ),
      _RhythmArrow(width: arrowWidth),
      _RhythmNumberInput(
        value: rhythm.exhaleSeconds,
        min: 1,
        max: 60,
        width: fieldWidth,
        onChanged: (value) => onChanged(rhythm.copyWith(exhaleSeconds: value)),
      ),
      _RhythmArrow(width: arrowWidth),
      _RhythmNumberInput(
        value: rhythm.holdAfterExhaleSeconds,
        min: 0,
        max: 60,
        width: fieldWidth,
        onChanged: (value) =>
            onChanged(rhythm.copyWith(holdAfterExhaleSeconds: value)),
      ),
      if (includeCycles) ...[
        _RhythmUnit('秒 ×', width: unitWidth),
        _RhythmNumberInput(
          value: rhythm.cycles,
          min: 1,
          max: 99,
          width: fieldWidth,
          onChanged: (value) => onChanged(rhythm.copyWith(cycles: value)),
        ),
        _RhythmUnit('组', width: tailUnitWidth),
      ] else
        _RhythmUnit('秒', width: tailUnitWidth),
    ];

    return DecoratedBox(
      decoration: BoxDecoration(
        border: topBorder
            ? const Border(top: BorderSide(color: Color(0x1215222B)))
            : null,
      ),
      child: SizedBox(
        width: double.infinity,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SettingsLabel(title),
              const SizedBox(height: 8),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(mainAxisSize: MainAxisSize.min, children: labelCells),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: inputCells,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RhythmNumberInput extends StatefulWidget {
  const _RhythmNumberInput({
    required this.value,
    required this.min,
    required this.max,
    this.width = 32,
    required this.onChanged,
  });

  final int value;
  final int min;
  final int max;
  final double width;
  final ValueChanged<int> onChanged;

  @override
  State<_RhythmNumberInput> createState() => _RhythmNumberInputState();
}

class _RhythmNumberInputState extends State<_RhythmNumberInput> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: '${widget.value}');
    _focusNode = FocusNode()..addListener(_handleFocusChanged);
  }

  @override
  void didUpdateWidget(covariant _RhythmNumberInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_focusNode.hasFocus && _controller.text != '${widget.value}') {
      _controller.text = '${widget.value}';
    }
  }

  @override
  void dispose() {
    _focusNode
      ..removeListener(_handleFocusChanged)
      ..dispose();
    _controller.dispose();
    super.dispose();
  }

  void _handleFocusChanged() {
    if (!_focusNode.hasFocus) _commit();
    if (mounted) setState(() {});
  }

  void _commit() {
    final parsed = int.tryParse(_controller.text.trim());
    final next = (parsed ?? widget.value).clamp(widget.min, widget.max).toInt();
    if (_controller.text != '$next') {
      _controller.text = '$next';
      _controller.selection = TextSelection.collapsed(
        offset: _controller.text.length,
      );
    }
    if (next != widget.value) widget.onChanged(next);
  }

  void _handleChanged(String value) {
    final parsed = int.tryParse(value.trim());
    if (parsed == null) return;
    final next = parsed.clamp(widget.min, widget.max).toInt();
    if (next != widget.value) widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.width,
      height: 32,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F6),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: _focusNode.hasFocus
                ? const Color(0xFF47C7A2)
                : const Color(0x1A1F434E),
          ),
        ),
        child: Center(
          child: SizedBox(
            height: 20,
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              textAlignVertical: TextAlignVertical.center,
              textInputAction: TextInputAction.done,
              onChanged: _handleChanged,
              onSubmitted: (_) => _commit(),
              style: const TextStyle(
                color: Color(0xFF1D2C36),
                fontSize: 16,
                fontWeight: FontWeight.w600,
                height: 1,
              ),
              decoration: const InputDecoration(
                border: InputBorder.none,
                isCollapsed: true,
                counterText: '',
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RhythmFormulaLabel extends StatelessWidget {
  const _RhythmFormulaLabel(this.text, {required this.width});

  final String text;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Text(
        text,
        textAlign: TextAlign.center,
        softWrap: false,
        style: const TextStyle(
          color: Color(0xFF7A8792),
          fontSize: 11,
          fontWeight: FontWeight.w600,
          height: 1.15,
        ),
      ),
    );
  }
}

class _RhythmArrow extends StatelessWidget {
  const _RhythmArrow({required this.width});

  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: 32,
      child: const Align(
        alignment: Alignment.center,
        child: Text(
          '→',
          style: TextStyle(
            color: Color(0xFF9CA9B1),
            fontSize: 13,
            fontWeight: FontWeight.w600,
            height: 1,
          ),
        ),
      ),
    );
  }
}

class _RhythmUnit extends StatelessWidget {
  const _RhythmUnit(this.text, {required this.width});

  final String text;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: 32,
      child: Align(
        alignment: Alignment.center,
        child: Text(
          text,
          textAlign: TextAlign.center,
          softWrap: false,
          overflow: TextOverflow.visible,
          style: const TextStyle(
            color: Color(0xFF87939C),
            fontSize: 12,
            fontWeight: FontWeight.w600,
            height: 1,
          ),
        ),
      ),
    );
  }
}

class _SegmentedAudioMode extends StatelessWidget {
  const _SegmentedAudioMode({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _AudioModeButton(
            label: '视频自带音频',
            active: value == 'video',
            onPressed: () => onChanged('video'),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: _AudioModeButton(
            label: '自定义混音',
            active: value == 'custom',
            onPressed: () => onChanged('custom'),
          ),
        ),
      ],
    );
  }
}

class _AudioModeButton extends StatelessWidget {
  const _AudioModeButton({
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
        foregroundColor: active ? Colors.white : const Color(0xFF40505B),
        backgroundColor: active
            ? const Color(0xFF47C7A2)
            : const Color(0xFFE9EFF1),
        padding: const EdgeInsets.symmetric(vertical: 8),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: Text(label),
    );
  }
}

class _CustomAmbientControls extends StatelessWidget {
  const _CustomAmbientControls({
    required this.options,
    required this.mix,
    required this.maxSelected,
    required this.auditionOn,
    required this.onToggleTrack,
    required this.onVolumeChanged,
    required this.onToggleAudition,
  });

  final List<CustomAmbientTrackOption> options;
  final List<CustomAmbientSetting> mix;
  final int maxSelected;
  final bool auditionOn;
  final ValueChanged<String> onToggleTrack;
  final void Function(String trackId, double percent) onVolumeChanged;
  final VoidCallback onToggleAudition;

  @override
  Widget build(BuildContext context) {
    final selectedById = {for (final item in mix) item.trackId: item};
    final selectedCount = selectedById.length;

    return Column(
      children: [
        Row(
          children: [
            Text(
              '$selectedCount/$maxSelected',
              style: const TextStyle(
                color: Color(0xFF7A8792),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            TextButton(
              onPressed: onToggleAudition,
              style: TextButton.styleFrom(
                foregroundColor: auditionOn
                    ? Colors.white
                    : const Color(0xFF16745F),
                backgroundColor: auditionOn
                    ? const Color(0xFF47C7A2)
                    : const Color(0xFFE7F7F1),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text(auditionOn ? '停止试听' : '开始试听'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        for (final option in options)
          _CustomAmbientTrackRow(
            option: option,
            selected: selectedById[option.id],
            disabled:
                selectedById[option.id] == null && selectedCount >= maxSelected,
            onToggleTrack: onToggleTrack,
            onVolumeChanged: onVolumeChanged,
          ),
      ],
    );
  }
}

class _CustomAmbientTrackRow extends StatelessWidget {
  const _CustomAmbientTrackRow({
    required this.option,
    required this.selected,
    required this.disabled,
    required this.onToggleTrack,
    required this.onVolumeChanged,
  });

  final CustomAmbientTrackOption option;
  final CustomAmbientSetting? selected;
  final bool disabled;
  final ValueChanged<String> onToggleTrack;
  final void Function(String trackId, double percent) onVolumeChanged;

  @override
  Widget build(BuildContext context) {
    final selected = this.selected;
    final active = selected != null;
    final percent = active ? (selected.volume * 100).round() : 0;

    return Opacity(
      opacity: disabled ? 0.48 : 1,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          children: [
            SizedBox(
              width: 88,
              child: TextButton(
                key: ValueKey('custom-ambient-track-${option.id}'),
                onPressed: disabled ? null : () => onToggleTrack(option.id),
                style: TextButton.styleFrom(
                  foregroundColor: active
                      ? const Color(0xFF16745F)
                      : const Color(0xFF53636E),
                  backgroundColor: active
                      ? const Color(0xFFE7F7F1)
                      : const Color(0xFFF6F8FA),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(
                      color: active
                          ? const Color(0x3347C7A2)
                          : const Color(0x141F434E),
                    ),
                  ),
                ),
                child: Text(
                  option.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            if (active) ...[
              const SizedBox(width: 12),
              Expanded(
                child: Slider(
                  key: ValueKey('custom-ambient-volume-${option.id}'),
                  min: 0,
                  max: 100,
                  divisions: 100,
                  value: percent.toDouble(),
                  onChanged: (value) => onVolumeChanged(option.id, value),
                ),
              ),
              SizedBox(
                width: 42,
                child: Text(
                  '$percent%',
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    color: Color(0xFF16745F),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SettingsBottomBar extends StatelessWidget {
  const _SettingsBottomBar({required this.onSave});

  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.96),
        border: const Border(top: BorderSide(color: Color(0x1215222B))),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          14,
          8,
          14,
          MediaQuery.paddingOf(context).bottom + 8,
        ),
        child: FilledButton(
          onPressed: onSave,
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF47C7A2),
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(44),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: const Text('保存返回'),
        ),
      ),
    );
  }
}

class _GradientBackground extends StatelessWidget {
  const _GradientBackground();

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

class _BackgroundScrim extends StatelessWidget {
  const _BackgroundScrim();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.42),
            Colors.black.withValues(alpha: 0.08),
            Colors.black.withValues(alpha: 0.52),
          ],
        ),
      ),
    );
  }
}

class _ClockText extends StatefulWidget {
  const _ClockText();

  @override
  State<_ClockText> createState() => _ClockTextState();
}

class _ClockTextState extends State<_ClockText> {
  late DateTime _now;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hour = _now.hour.toString().padLeft(2, '0');
    final minute = _now.minute.toString().padLeft(2, '0');
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$hour:$minute',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 72,
            fontWeight: FontWeight.w300,
            letterSpacing: 0,
          ),
        ),
        Text(
          '${_now.month}月${_now.day}日',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.68),
            fontSize: 14,
          ),
        ),
      ],
    );
  }
}

class _WeatherPill extends StatelessWidget {
  const _WeatherPill({
    required this.forecast,
    required this.loading,
    required this.error,
    required this.onTap,
  });

  final WeatherForecast? forecast;
  final bool loading;
  final String? error;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final current = forecast?.current;
    final label = forecast == null
        ? error ?? (loading ? '天气加载中' : '天气加载中')
        : '${_temperatureText(current?.temperature)} ${describeWeather(current?.weatherCode)} · ${forecast!.location}';
    final canTap = forecast != null || (error != null && !loading);
    return Semantics(
      button: canTap,
      label: '天气',
      child: GestureDetector(
        onTap: canTap ? onTap : null,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.25),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 174),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Text(
                forecast == null ? '--° $label' : label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withValues(
                    alpha: forecast == null ? 0.66 : 0.84,
                  ),
                  fontSize: 13,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WeatherInfoPanel extends StatelessWidget {
  const _WeatherInfoPanel({required this.forecast, required this.onClose});

  final WeatherForecast forecast;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final current = forecast.current;
    final firstDay = forecast.daily.isNotEmpty ? forecast.daily.first : null;
    return SafeArea(
      child: Align(
        alignment: Alignment.topRight,
        child: Container(
          width: min(MediaQuery.sizeOf(context).width - 32, 390),
          margin: const EdgeInsets.fromLTRB(18, 58, 18, 0),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xDD101820),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x66000000),
                blurRadius: 26,
                offset: Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          forecast.location,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${describeWeather(current.weatherCode)} · 体感 ${_plainNumber(current.feelsLike)}°',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.68),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: onClose,
                    icon: const Icon(Icons.close_rounded),
                    color: Colors.white.withValues(alpha: 0.82),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _temperatureText(current.temperature),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 52,
                      fontWeight: FontWeight.w300,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 9),
                    child: Text(
                      forecast.unit,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.72),
                        fontSize: 16,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _WeatherMetric(
                    value: '${_plainNumber(current.humidity)}%',
                    label: '湿度',
                  ),
                  const SizedBox(width: 10),
                  _WeatherMetric(
                    value: _plainNumber(current.windSpeed),
                    label: 'km/h 风',
                  ),
                  const SizedBox(width: 10),
                  _WeatherMetric(
                    value: _plainNumber(firstDay?.uvIndex),
                    label: '紫外线',
                  ),
                ],
              ),
              if (forecast.daily.isNotEmpty) ...[
                const SizedBox(height: 16),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 260),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: forecast.daily.length,
                    separatorBuilder: (context, index) => Divider(
                      height: 18,
                      color: Colors.white.withValues(alpha: 0.10),
                    ),
                    itemBuilder: (context, index) {
                      final day = forecast.daily[index];
                      return _DailyWeatherRow(day: day, index: index);
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _WeatherMetric extends StatelessWidget {
  const _WeatherMetric({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: Column(
            children: [
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.58),
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DailyWeatherRow extends StatelessWidget {
  const _DailyWeatherRow({required this.day, required this.index});

  final WeatherDaily day;
  final int index;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            SizedBox(
              width: 78,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _dailyLabel(day.date, index),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _dateShort(day.date),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.54),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Text(
                describeWeather(day.weatherCode),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.82),
                  fontSize: 13,
                ),
              ),
            ),
            Text(
              '${_plainNumber(day.min)}° / ${_plainNumber(day.max)}°',
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          '降水 ${_plainNumber(day.precipitation)}% · ${_plainNumber(day.precipitationSum)}mm · 风 ${_plainNumber(day.windSpeed)} km/h',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.54),
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          '紫外线 ${_plainNumber(day.uvIndex)} · 日出 ${_timeOnly(day.sunrise)} · 日落 ${_timeOnly(day.sunset)}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.54),
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}

class _VideoInfoOverlay extends StatelessWidget {
  const _VideoInfoOverlay({
    required this.video,
    required this.isFavorite,
    required this.onToggleFavorite,
    required this.onClose,
  });

  final VideoItem video;
  final bool isFavorite;
  final VoidCallback onToggleFavorite;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onClose,
      child: SafeArea(
        child: Align(
          alignment: Alignment.topLeft,
          child: Container(
            width: min(MediaQuery.sizeOf(context).width - 32, 420),
            margin: const EdgeInsets.fromLTRB(18, 58, 18, 0),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        video.titleForDisplay(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: onClose,
                      icon: const Icon(Icons.close_rounded),
                      color: Colors.white,
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
                if (video.locationName.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    [
                      video.locationName,
                      if (video.locationCountry.isNotEmpty)
                        video.locationCountry,
                    ].join(' · '),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 13,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Text(
                  video.description.isEmpty ? '暂无介绍' : video.description,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.84),
                    fontSize: 14,
                    height: 1.6,
                  ),
                ),
                const SizedBox(height: 16),
                InkWell(
                  onTap: onToggleFavorite,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          isFavorite ? '♥' : '♡',
                          style: TextStyle(
                            color: isFavorite
                                ? const Color(0xFFFF405F)
                                : Colors.white.withValues(alpha: 0.8),
                            fontSize: 26,
                            height: 1,
                            shadows: isFavorite
                                ? const [
                                    Shadow(
                                      color: Color(0x5CFF405F),
                                      blurRadius: 10,
                                    ),
                                  ]
                                : const [],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          isFavorite ? '取消收藏' : '收藏视频',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.82),
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: _GradientBackground());
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.error});

  final Object? error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            '内容加载失败\n$error',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white),
          ),
        ),
      ),
    );
  }
}

String _temperatureText(int? value) => '${_plainNumber(value)}°';

String _plainNumber(int? value) => value == null ? '--' : '$value';

String _dailyLabel(String date, int index) {
  if (index == 0) return '今天';
  if (index == 1) return '明天';
  final parsed = DateTime.tryParse(date);
  if (parsed == null) return '第 ${index + 1} 天';
  const weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
  return weekdays[parsed.weekday - 1];
}

String _dateShort(String date) {
  final parsed = DateTime.tryParse(date);
  if (parsed == null) {
    return date.length >= 5 ? date.substring(date.length - 5) : date;
  }
  return '${parsed.month}/${parsed.day}';
}

String _timeOnly(String? value) {
  if (value == null || value.isEmpty) return '--';
  final parsed = DateTime.tryParse(value);
  if (parsed != null) {
    return '${parsed.hour.toString().padLeft(2, '0')}:${parsed.minute.toString().padLeft(2, '0')}';
  }
  final marker = value.indexOf('T');
  if (marker >= 0 && marker + 6 <= value.length) {
    return value.substring(marker + 1, marker + 6);
  }
  return value;
}
