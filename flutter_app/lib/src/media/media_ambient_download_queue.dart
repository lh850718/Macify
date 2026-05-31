import 'dart:async';
import 'dart:io';

import '../content/content_models.dart';
import 'media_cache_index.dart';
import 'media_download_service.dart';
import 'media_resource_resolver.dart';
import 'remote_file_client.dart';

typedef MediaAmbientCacheIndexPersist =
    Future<void> Function(MediaCacheIndex index);
typedef MediaAmbientCacheIndexChanged = void Function(MediaCacheIndex index);
typedef MediaAmbientCacheIndexRead = MediaCacheIndex Function();

class MediaAmbientDownloadQueue {
  MediaAmbientDownloadQueue({
    required this.content,
    required this.cacheRoot,
    required this.client,
    required MediaCacheIndex initialIndex,
    this.bundledCatalog = const MediaResourceCatalog.empty(),
    MediaAmbientCacheIndexPersist? persistIndex,
    this.onIndexChanged,
    this.readIndex,
  }) : index = initialIndex,
       _persistIndex = persistIndex ?? ((index) => index.save());

  final ContentBundle content;
  final Directory cacheRoot;
  final RemoteFileClient client;
  final MediaResourceCatalog bundledCatalog;
  final MediaAmbientCacheIndexPersist _persistIndex;
  final MediaAmbientCacheIndexChanged? onIndexChanged;
  final MediaAmbientCacheIndexRead? readIndex;

  MediaCacheIndex index;
  Object? lastError;

  final _skippedTrackIds = <String>{};
  var _downloadInFlight = false;

  bool get isDownloading => _downloadInFlight;

  Future<List<MediaDownloadResult>> downloadMissingTracksForMix(
    AmbientMix mix,
  ) async {
    if (_downloadInFlight) return const [];

    _downloadInFlight = true;
    final downloaded = <MediaDownloadResult>[];
    try {
      final trackIds = mix.tracks
          .map((track) => track.id)
          .where((id) => id.trim().isNotEmpty)
          .toSet();
      for (final trackId in trackIds) {
        final result = await _downloadTrackIfNeeded(trackId);
        if (result != null) downloaded.add(result);
      }
    } finally {
      _downloadInFlight = false;
    }
    return downloaded;
  }

  Future<MediaDownloadResult?> _downloadTrackIfNeeded(String trackId) async {
    if (_skippedTrackIds.contains(trackId)) return null;

    final track = content.ambientCatalog.tracks[trackId];
    if (track == null) return null;

    index = readIndex?.call() ?? index;
    final resource = _resolver.ambientAudioResourceFor(track);
    if (resource.status != MediaResourceStatus.remote || !resource.isPlayable) {
      return null;
    }

    lastError = null;
    try {
      final mediaFile = content.manifest.media.ambientTracks[trackId];
      final result =
          await MediaDownloadService(
            content: content,
            cacheRoot: cacheRoot,
            client: client,
          ).downloadAmbientTrack(
            index,
            track,
            expectedBytes: mediaFile?.bytes,
            expectedSha256: mediaFile?.sha256,
          );
      final committedIndex = (readIndex?.call() ?? result.index)
          .withCachedAmbientTrack(track.id, result.resource.uri);
      final committedResult = MediaDownloadResult(
        index: committedIndex,
        resource: result.resource,
        bytesWritten: result.bytesWritten,
      );
      index = committedIndex;
      await _persistIndex(index);
      onIndexChanged?.call(index);
      return committedResult;
    } catch (error) {
      lastError = error;
      _skippedTrackIds.add(trackId);
      return null;
    }
  }

  MediaResourceResolver get _resolver {
    return MediaResourceResolver(
      content,
      catalog: index.toResourceCatalog(bundled: bundledCatalog),
    );
  }
}
