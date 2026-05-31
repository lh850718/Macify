import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:huxi_zen/src/content/content_models.dart';
import 'package:huxi_zen/src/content/content_repository.dart';
import 'package:huxi_zen/src/media/media_ambient_download_queue.dart';
import 'package:huxi_zen/src/media/media_cache_index.dart';
import 'package:huxi_zen/src/media/media_resource_resolver.dart';
import 'package:huxi_zen/src/media/remote_file_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('huxi-ambient-test-');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('downloads remote ambient tracks used by the current mix', () async {
    final loadedContent = await const AssetContentRepository().load();
    final waterfall = loadedContent.ambientCatalog.tracks['waterfall']!;
    final river = loadedContent.ambientCatalog.tracks['river']!;
    final content = _withAmbientMediaManifest(loadedContent, {
      waterfall.id: utf8.encode('waterfall-audio').length,
      river.id: utf8.encode('river-audio').length,
    });
    final client = _FakeRemoteFileClient({
      _ambientUrl(content, waterfall): utf8.encode('waterfall-audio'),
      _ambientUrl(content, river): utf8.encode('river-audio'),
    });
    final savedIndexes = <MediaCacheIndex>[];
    final queue = MediaAmbientDownloadQueue(
      content: content,
      cacheRoot: tempDir,
      client: client,
      initialIndex: const MediaCacheIndex(),
      persistIndex: (index) async => savedIndexes.add(index),
    );

    final results = await queue.downloadMissingTracksForMix(
      AmbientMix(
        id: 'mix',
        label: 'Water + River',
        tracks: [_resolved(waterfall, content), _resolved(river, content)],
      ),
    );

    expect(results.map((result) => result.resource.id), [
      waterfall.id,
      river.id,
    ]);
    expect(queue.index.cachedAmbientAudioFiles, contains(waterfall.id));
    expect(queue.index.cachedAmbientAudioFiles, contains(river.id));
    expect(savedIndexes, hasLength(2));
    expect(
      await File(
        queue.index.cachedAmbientAudioFiles[waterfall.id]!,
      ).readAsString(),
      'waterfall-audio',
    );
  });

  test('skips cached bundled and removed ambient tracks', () async {
    final loadedContent = await const AssetContentRepository().load();
    final waterfall = loadedContent.ambientCatalog.tracks['waterfall']!;
    final fire = loadedContent.ambientCatalog.tracks['fire']!;
    final wind = loadedContent.ambientCatalog.tracks['wind']!;
    final river = loadedContent.ambientCatalog.tracks['river']!;
    final content = _withAmbientMediaManifest(loadedContent, {
      river.id: utf8.encode('river-audio').length,
    });
    final client = _FakeRemoteFileClient({
      _ambientUrl(content, river): utf8.encode('river-audio'),
    });
    final queue = MediaAmbientDownloadQueue(
      content: content,
      cacheRoot: tempDir,
      client: client,
      initialIndex: const MediaCacheIndex(
        cachedAmbientAudioFiles: {'waterfall': '/cache/audio/waterfall.mp3'},
        removedAmbientTrackIds: {'wind'},
      ),
      bundledCatalog: const MediaResourceCatalog(
        bundledAmbientAudioAssets: {'fire': 'assets/media/audio/fire.mp3'},
      ),
      persistIndex: (_) async {},
    );

    final results = await queue.downloadMissingTracksForMix(
      AmbientMix(
        id: 'mix',
        label: 'Mixed',
        tracks: [
          _resolved(waterfall, content),
          _resolved(fire, content),
          _resolved(wind, content),
          _resolved(river, content),
        ],
      ),
    );

    expect(results.map((result) => result.resource.id), [river.id]);
    expect(queue.index.cachedAmbientAudioFiles, contains(waterfall.id));
    expect(queue.index.cachedAmbientAudioFiles, contains(river.id));
    expect(queue.index.cachedAmbientAudioFiles, isNot(contains(fire.id)));
    expect(queue.index.cachedAmbientAudioFiles, isNot(contains(wind.id)));
  });

  test('commits downloaded audio on top of the latest cache index', () async {
    final loadedContent = await const AssetContentRepository().load();
    final waterfall = loadedContent.ambientCatalog.tracks['waterfall']!;
    final content = _withAmbientMediaManifest(loadedContent, {
      waterfall.id: utf8.encode('waterfall-audio').length,
    });
    final latestIndex = const MediaCacheIndex(
      cachedVideoFiles: {'pixabay-28707': '/cache/videos/pixabay-28707.mp4'},
    );
    final queue = MediaAmbientDownloadQueue(
      content: content,
      cacheRoot: tempDir,
      client: _FakeRemoteFileClient({
        _ambientUrl(content, waterfall): utf8.encode('waterfall-audio'),
      }),
      initialIndex: const MediaCacheIndex(),
      readIndex: () => latestIndex,
      persistIndex: (_) async {},
    );

    final results = await queue.downloadMissingTracksForMix(
      AmbientMix(
        id: 'waterfall',
        label: 'Waterfall',
        tracks: [_resolved(waterfall, content)],
      ),
    );

    expect(results, hasLength(1));
    expect(queue.index.cachedVideoFiles, latestIndex.cachedVideoFiles);
    expect(queue.index.cachedAmbientAudioFiles, contains(waterfall.id));
  });
}

ContentBundle _withAmbientMediaManifest(
  ContentBundle content,
  Map<String, int> ambientBytes,
) {
  return ContentBundle(
    manifest: ContentManifest(
      schemaVersion: content.manifest.schemaVersion,
      contentVersion: content.manifest.contentVersion,
      defaultVideoLibrary: content.manifest.defaultVideoLibrary,
      files: content.manifest.files,
      media: ContentMediaManifest(
        videos: content.manifest.media.videos,
        ambientTracks: ambientBytes.map(
          (trackId, bytes) => MapEntry(
            trackId,
            ManifestMediaFile(
              path: content.ambientCatalog.tracks[trackId]?.file ?? '',
              bytes: bytes,
              sha256: '',
            ),
          ),
        ),
      ),
    ),
    config: content.config,
    videos: content.videos,
    ambientCatalog: content.ambientCatalog,
    ambientRules: content.ambientRules,
    videoAudioMixes: content.videoAudioMixes,
  );
}

ResolvedAmbientTrack _resolved(AmbientTrack track, ContentBundle content) {
  return ResolvedAmbientTrack(
    id: track.id,
    channelId: track.id,
    label: track.label,
    file: track.file,
    durationMs: track.durationMs,
    volume: track.volume,
    url: _ambientUrl(content, track),
  );
}

String _ambientUrl(ContentBundle content, AmbientTrack track) =>
    '${content.config.defaultAmbientAudioBase}/${track.file}';

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
