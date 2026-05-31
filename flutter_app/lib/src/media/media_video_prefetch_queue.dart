import 'dart:async';
import 'dart:io';

import '../content/content_models.dart';
import 'media_cache_index.dart';
import 'media_download_service.dart';
import 'media_prefetch_policy.dart';
import 'media_resource_resolver.dart';
import 'remote_file_client.dart';

typedef MediaCacheIndexPersist = Future<void> Function(MediaCacheIndex index);
typedef MediaCacheIndexChanged = void Function(MediaCacheIndex index);
typedef MediaCacheIndexRead = MediaCacheIndex Function();

class MediaVideoPrefetchQueue {
  MediaVideoPrefetchQueue({
    required this.content,
    required this.cacheRoot,
    required this.client,
    required MediaCacheIndex initialIndex,
    this.bundledCatalog = const MediaResourceCatalog.empty(),
    MediaCacheIndexPersist? persistIndex,
    this.onIndexChanged,
    this.readIndex,
  }) : index = initialIndex,
       _persistIndex = persistIndex ?? ((index) => index.save());

  final ContentBundle content;
  final Directory cacheRoot;
  final RemoteFileClient client;
  final MediaResourceCatalog bundledCatalog;
  final MediaCacheIndexPersist _persistIndex;
  final MediaCacheIndexChanged? onIndexChanged;
  final MediaCacheIndexRead? readIndex;

  MediaCacheIndex index;
  MediaPrefetchDecision? lastDecision;
  Object? lastError;

  final _playedVideoIds = <String>{};
  final _skippedVideoIds = <String>{};
  var _downloadInFlight = false;

  bool get isDownloading => _downloadInFlight;

  Future<MediaDownloadResult?> markVideoCycleCompleted({
    required VideoItem video,
    required Iterable<VideoItem> playbackScope,
    String? currentVideoId,
  }) {
    _playedVideoIds.add(video.id);
    return maybeDownloadNext(
      playbackScope: playbackScope,
      currentVideoId: currentVideoId,
    );
  }

  Future<MediaDownloadResult?> maybeDownloadNext({
    required Iterable<VideoItem> playbackScope,
    String? currentVideoId,
  }) async {
    if (_downloadInFlight) return null;

    index = readIndex?.call() ?? index;
    final policy = MediaPrefetchPolicy(_resolver);
    final decision = policy.nextVideoToDownload(
      playbackScope: playbackScope,
      playedVideoIds: _playedVideoIds,
      skippedVideoIds: _skippedVideoIds,
      currentVideoId: currentVideoId,
    );
    lastDecision = decision;
    lastError = null;
    final video = decision.video;
    if (video == null) return null;

    _downloadInFlight = true;
    try {
      final mediaFile = content.manifest.media.videos[video.id];
      final result =
          await MediaDownloadService(
            content: content,
            cacheRoot: cacheRoot,
            client: client,
          ).downloadVideo(
            index,
            video,
            expectedBytes: mediaFile?.bytes,
            expectedSha256: mediaFile?.sha256,
          );
      final committedIndex = (readIndex?.call() ?? result.index)
          .withCachedVideo(video.id, result.resource.uri);
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
      _skippedVideoIds.add(video.id);
      return null;
    } finally {
      _downloadInFlight = false;
    }
  }

  MediaResourceResolver get _resolver {
    return MediaResourceResolver(
      content,
      catalog: index.toResourceCatalog(bundled: bundledCatalog),
    );
  }
}
