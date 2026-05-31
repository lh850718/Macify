import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:huxi_zen/src/content/content_models.dart';
import 'package:huxi_zen/src/content/content_repository.dart';
import 'package:huxi_zen/src/media/media_cache_index.dart';
import 'package:huxi_zen/src/media/media_prefetch_policy.dart';
import 'package:huxi_zen/src/media/media_video_prefetch_queue.dart';
import 'package:huxi_zen/src/media/remote_file_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('huxi-prefetch-test-');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('downloads one remote video after the local cycle completes', () async {
    final loadedContent = await const AssetContentRepository().load();
    final local = loadedContent.videos.firstWhere(
      (item) => item.id == 'pixabay-28707',
    );
    final remoteA = loadedContent.videos.firstWhere(
      (item) => item.id == 'pixabay-159703',
    );
    final remoteB = loadedContent.videos.firstWhere(
      (item) => item.id == 'pixabay-228847',
    );
    final content = _withVideoMediaManifest(loadedContent, {
      remoteA.id: utf8.encode('video-a').length,
      remoteB.id: utf8.encode('video-b').length,
    });
    final client = _FakeRemoteFileClient({
      remoteA.remoteVideoUrl(content.config.defaultVideoBase): utf8.encode(
        'video-a',
      ),
      remoteB.remoteVideoUrl(content.config.defaultVideoBase): utf8.encode(
        'video-b',
      ),
    });
    final savedIndexes = <MediaCacheIndex>[];
    final queue = MediaVideoPrefetchQueue(
      content: content,
      cacheRoot: tempDir,
      client: client,
      initialIndex: const MediaCacheIndex().withCachedVideo(
        local.id,
        '/cache/videos/${local.id}.mp4',
      ),
      persistIndex: (index) async => savedIndexes.add(index),
    );

    final first = await queue.markVideoCycleCompleted(
      video: local,
      playbackScope: [local, remoteA, remoteB],
      currentVideoId: local.id,
    );

    expect(first?.resource.id, remoteA.id);
    expect(queue.index.cachedVideoFiles, contains(remoteA.id));
    expect(savedIndexes, hasLength(1));

    final second = await queue.maybeDownloadNext(
      playbackScope: [local, remoteA, remoteB],
      currentVideoId: local.id,
    );

    expect(second, isNull);
    expect(
      queue.lastDecision?.reason,
      MediaPrefetchBlockReason.localCycleIncomplete,
    );
    expect(queue.lastDecision?.remainingLocalVideoIds, {remoteA.id});

    final third = await queue.markVideoCycleCompleted(
      video: remoteA,
      playbackScope: [local, remoteA, remoteB],
      currentVideoId: remoteA.id,
    );

    expect(third?.resource.id, remoteB.id);
    expect(queue.index.cachedVideoFiles, contains(remoteB.id));
    expect(savedIndexes, hasLength(2));
  });

  test('skips a failed prefetch for the current session', () async {
    final loadedContent = await const AssetContentRepository().load();
    final local = loadedContent.videos.firstWhere(
      (item) => item.id == 'pixabay-28707',
    );
    final missingRemote = loadedContent.videos.firstWhere(
      (item) => item.id == 'pixabay-159703',
    );
    final fallbackRemote = loadedContent.videos.firstWhere(
      (item) => item.id == 'pixabay-228847',
    );
    final content = _withVideoMediaManifest(loadedContent, {
      missingRemote.id: utf8.encode('missing').length,
      fallbackRemote.id: utf8.encode('fallback').length,
    });
    final client = _FakeRemoteFileClient({
      fallbackRemote.remoteVideoUrl(content.config.defaultVideoBase): utf8
          .encode('fallback'),
    });
    final queue = MediaVideoPrefetchQueue(
      content: content,
      cacheRoot: tempDir,
      client: client,
      initialIndex: const MediaCacheIndex().withCachedVideo(
        local.id,
        '/cache/videos/${local.id}.mp4',
      ),
      persistIndex: (_) async {},
    );

    final failed = await queue.markVideoCycleCompleted(
      video: local,
      playbackScope: [local, missingRemote, fallbackRemote],
      currentVideoId: local.id,
    );

    expect(failed, isNull);
    expect(queue.lastError, isA<RemoteFileException>());

    final fallback = await queue.maybeDownloadNext(
      playbackScope: [local, missingRemote, fallbackRemote],
      currentVideoId: local.id,
    );

    expect(fallback?.resource.id, fallbackRemote.id);
    expect(queue.index.cachedVideoFiles, contains(fallbackRemote.id));
  });

  test('commits downloaded video on top of the latest cache index', () async {
    final loadedContent = await const AssetContentRepository().load();
    final local = loadedContent.videos.firstWhere(
      (item) => item.id == 'pixabay-28707',
    );
    final remote = loadedContent.videos.firstWhere(
      (item) => item.id == 'pixabay-159703',
    );
    final content = _withVideoMediaManifest(loadedContent, {
      remote.id: utf8.encode('video-a').length,
    });
    final latestIndex = MediaCacheIndex(
      cachedVideoFiles: {local.id: '/cache/videos/${local.id}.mp4'},
      cachedAmbientAudioFiles: {'waterfall': '/cache/audio/waterfall.mp3'},
    );
    final queue = MediaVideoPrefetchQueue(
      content: content,
      cacheRoot: tempDir,
      client: _FakeRemoteFileClient({
        remote.remoteVideoUrl(content.config.defaultVideoBase): utf8.encode(
          'video-a',
        ),
      }),
      initialIndex: const MediaCacheIndex().withCachedVideo(
        local.id,
        '/cache/videos/${local.id}.mp4',
      ),
      readIndex: () => latestIndex,
      persistIndex: (_) async {},
    );

    final result = await queue.markVideoCycleCompleted(
      video: local,
      playbackScope: [local, remote],
      currentVideoId: local.id,
    );

    expect(result?.resource.id, remote.id);
    expect(
      queue.index.cachedAmbientAudioFiles,
      latestIndex.cachedAmbientAudioFiles,
    );
    expect(queue.index.cachedVideoFiles, contains(remote.id));
  });
}

ContentBundle _withVideoMediaManifest(
  ContentBundle content,
  Map<String, int> videoBytes,
) {
  return ContentBundle(
    manifest: ContentManifest(
      schemaVersion: content.manifest.schemaVersion,
      contentVersion: content.manifest.contentVersion,
      defaultVideoLibrary: content.manifest.defaultVideoLibrary,
      files: content.manifest.files,
      media: ContentMediaManifest(
        videos: videoBytes.map(
          (videoId, bytes) => MapEntry(
            videoId,
            ManifestMediaFile(
              path: 'videos/$videoId.mp4',
              bytes: bytes,
              sha256: '',
            ),
          ),
        ),
        ambientTracks: content.manifest.media.ambientTracks,
      ),
    ),
    config: content.config,
    videos: content.videos,
    ambientCatalog: content.ambientCatalog,
    ambientRules: content.ambientRules,
    videoAudioMixes: content.videoAudioMixes,
  );
}

class _FakeRemoteFileClient implements RemoteFileClient {
  const _FakeRemoteFileClient(this.bytesByUrl);

  final Map<String, List<int>> bytesByUrl;

  @override
  Future<int> download(Uri uri, File destination) async {
    final bytes = bytesByUrl[uri.toString()];
    if (bytes == null) {
      throw RemoteFileException('Missing fake bytes', uri: uri);
    }
    await destination.parent.create(recursive: true);
    await destination.writeAsBytes(bytes);
    return bytes.length;
  }

  @override
  Future<String> readString(Uri uri) async {
    final bytes = bytesByUrl[uri.toString()];
    if (bytes == null) throw RemoteFileException('Missing fake text', uri: uri);
    return utf8.decode(bytes);
  }
}
