import '../content/content_models.dart';

enum MediaResourceKind { video, ambientAudio }

enum MediaResourceStatus { bundled, cached, remote, removed }

class MediaResource {
  const MediaResource({
    required this.kind,
    required this.id,
    required this.status,
    required this.uri,
  });

  final MediaResourceKind kind;
  final String id;
  final MediaResourceStatus status;
  final String uri;

  bool get isPlayable =>
      status != MediaResourceStatus.removed && uri.isNotEmpty;

  bool get isLocal =>
      status == MediaResourceStatus.bundled ||
      status == MediaResourceStatus.cached;
}

class MediaResourceCatalog {
  const MediaResourceCatalog({
    this.bundledVideoAssets = const {},
    this.cachedVideoFiles = const {},
    this.removedVideoIds = const {},
    this.bundledAmbientAudioAssets = const {},
    this.cachedAmbientAudioFiles = const {},
    this.removedAmbientTrackIds = const {},
  });

  const MediaResourceCatalog.empty()
    : bundledVideoAssets = const {},
      cachedVideoFiles = const {},
      removedVideoIds = const {},
      bundledAmbientAudioAssets = const {},
      cachedAmbientAudioFiles = const {},
      removedAmbientTrackIds = const {};

  final Map<String, String> bundledVideoAssets;
  final Map<String, String> cachedVideoFiles;
  final Set<String> removedVideoIds;
  final Map<String, String> bundledAmbientAudioAssets;
  final Map<String, String> cachedAmbientAudioFiles;
  final Set<String> removedAmbientTrackIds;
}

class MediaResourceResolver {
  const MediaResourceResolver(
    this.content, {
    this.catalog = const MediaResourceCatalog.empty(),
  });

  final ContentBundle content;
  final MediaResourceCatalog catalog;

  MediaResource videoResourceFor(VideoItem video) {
    if (catalog.removedVideoIds.contains(video.id)) {
      return MediaResource(
        kind: MediaResourceKind.video,
        id: video.id,
        status: MediaResourceStatus.removed,
        uri: '',
      );
    }

    final cached = catalog.cachedVideoFiles[video.id];
    if (cached != null && cached.isNotEmpty) {
      return MediaResource(
        kind: MediaResourceKind.video,
        id: video.id,
        status: MediaResourceStatus.cached,
        uri: cached,
      );
    }

    final bundled = catalog.bundledVideoAssets[video.id];
    if (bundled != null && bundled.isNotEmpty) {
      return MediaResource(
        kind: MediaResourceKind.video,
        id: video.id,
        status: MediaResourceStatus.bundled,
        uri: bundled,
      );
    }

    return MediaResource(
      kind: MediaResourceKind.video,
      id: video.id,
      status: MediaResourceStatus.remote,
      uri: video.remoteVideoUrl(content.config.defaultVideoBase),
    );
  }

  MediaResource ambientAudioResourceFor(AmbientTrack track) {
    if (catalog.removedAmbientTrackIds.contains(track.id)) {
      return MediaResource(
        kind: MediaResourceKind.ambientAudio,
        id: track.id,
        status: MediaResourceStatus.removed,
        uri: '',
      );
    }

    final cached = catalog.cachedAmbientAudioFiles[track.id];
    if (cached != null && cached.isNotEmpty) {
      return MediaResource(
        kind: MediaResourceKind.ambientAudio,
        id: track.id,
        status: MediaResourceStatus.cached,
        uri: cached,
      );
    }

    final bundled = catalog.bundledAmbientAudioAssets[track.id];
    if (bundled != null && bundled.isNotEmpty) {
      return MediaResource(
        kind: MediaResourceKind.ambientAudio,
        id: track.id,
        status: MediaResourceStatus.bundled,
        uri: bundled,
      );
    }

    return MediaResource(
      kind: MediaResourceKind.ambientAudio,
      id: track.id,
      status: MediaResourceStatus.remote,
      uri: _remoteAmbientUrl(track),
    );
  }

  String _remoteAmbientUrl(AmbientTrack track) {
    final base = _normalizeBase(content.config.defaultAmbientAudioBase);
    return base.isEmpty ? '' : '$base/${track.file}';
  }
}

String _normalizeBase(String value) =>
    value.trim().replaceFirst(RegExp(r'/$'), '');
