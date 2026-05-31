import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:huxi_zen/src/content/remote_content_sync.dart';
import 'package:huxi_zen/src/media/media_cache_index.dart';
import 'package:huxi_zen/src/media/media_resource_resolver.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('persists cached and removed resource state', () async {
    final index = const MediaCacheIndex()
        .withCachedVideo('video-a', '/cache/videos/video-a.mp4')
        .withCachedAmbientTrack('rain', '/cache/audio/rain.mp3')
        .withRemovedVideo('video-b')
        .withRemovedAmbientTrack('fire');

    await index.save();

    final loaded = await MediaCacheIndex.load();
    expect(loaded.cachedVideoFiles['video-a'], '/cache/videos/video-a.mp4');
    expect(loaded.cachedAmbientAudioFiles['rain'], '/cache/audio/rain.mp3');
    expect(loaded.removedVideoIds, contains('video-b'));
    expect(loaded.removedAmbientTrackIds, contains('fire'));
  });

  test('removed state clears stale cached entries', () {
    final index = const MediaCacheIndex()
        .withCachedVideo('video-a', '/cache/videos/video-a.mp4')
        .withCachedAmbientTrack('rain', '/cache/audio/rain.mp3')
        .withRemovedVideo('video-a')
        .withRemovedAmbientTrack('rain');

    expect(index.cachedVideoFiles, isNot(contains('video-a')));
    expect(index.cachedAmbientAudioFiles, isNot(contains('rain')));
    expect(index.removedVideoIds, contains('video-a'));
    expect(index.removedAmbientTrackIds, contains('rain'));
  });

  test('converts cache index to resource catalog with bundled assets', () {
    final index = const MediaCacheIndex()
        .withCachedVideo('video-a', '/cache/videos/video-a.mp4')
        .withRemovedAmbientTrack('rain');

    final catalog = index.toResourceCatalog(
      bundled: const MediaResourceCatalog(
        bundledVideoAssets: {'video-b': 'assets/videos/video-b.mp4'},
        bundledAmbientAudioAssets: {'fire': 'assets/audio/fire.mp3'},
      ),
    );

    expect(catalog.cachedVideoFiles['video-a'], '/cache/videos/video-a.mp4');
    expect(catalog.bundledVideoAssets['video-b'], 'assets/videos/video-b.mp4');
    expect(catalog.bundledAmbientAudioAssets['fire'], 'assets/audio/fire.mp3');
    expect(catalog.removedAmbientTrackIds, contains('rain'));
  });

  test('prunes cached entries whose files no longer exist', () async {
    final tempDir = await Directory.systemTemp.createTemp('huxi-cache-index-');
    addTearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    final existingVideo = File('${tempDir.path}/video.mp4');
    final existingAudio = File('${tempDir.path}/audio.mp3');
    await existingVideo.writeAsString('video');
    await existingAudio.writeAsString('audio');

    final index = MediaCacheIndex(
      cachedVideoFiles: {
        'video-a': existingVideo.path,
        'video-b': '${tempDir.path}/missing-video.mp4',
      },
      cachedAmbientAudioFiles: {
        'rain': existingAudio.path,
        'fire': '${tempDir.path}/missing-audio.mp3',
      },
    );

    final pruned = await index.pruneMissingFiles();

    expect(pruned.cachedVideoFiles, {'video-a': existingVideo.path});
    expect(pruned.cachedAmbientAudioFiles, {'rain': existingAudio.path});
  });

  test('deletes local files for removed resource ids', () async {
    final tempDir = await Directory.systemTemp.createTemp('huxi-cache-index-');
    addTearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    final removedVideo = File('${tempDir.path}/removed-video.mp4');
    final removedAudio = File('${tempDir.path}/removed-audio.mp3');
    final keptVideo = File('${tempDir.path}/kept-video.mp4');
    await removedVideo.writeAsString('old video');
    await removedAudio.writeAsString('old audio');
    await keptVideo.writeAsString('kept video');

    final index = MediaCacheIndex(
      cachedVideoFiles: {
        'video-old': removedVideo.path,
        'video-kept': keptVideo.path,
      },
      cachedAmbientAudioFiles: {'rain': removedAudio.path},
      removedVideoIds: {'video-old'},
      removedAmbientTrackIds: {'rain'},
    );

    final cleanup = await index.cleanupLocalFiles();

    expect(cleanup.deletedFilePaths, contains(removedVideo.path));
    expect(cleanup.deletedFilePaths, contains(removedAudio.path));
    expect(await removedVideo.exists(), isFalse);
    expect(await removedAudio.exists(), isFalse);
    expect(await keptVideo.exists(), isTrue);
    expect(cleanup.index.cachedVideoFiles, {'video-kept': keptVideo.path});
    expect(cleanup.index.cachedAmbientAudioFiles, isEmpty);
    expect(cleanup.index.removedVideoIds, contains('video-old'));
    expect(cleanup.index.removedAmbientTrackIds, contains('rain'));
  });

  test('reconciles remote media changes with cached files', () async {
    final tempDir = await Directory.systemTemp.createTemp('huxi-cache-index-');
    addTearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    final changedVideo = File('${tempDir.path}/changed-video.mp4');
    final removedVideo = File('${tempDir.path}/removed-video.mp4');
    final changedAudio = File('${tempDir.path}/changed-audio.mp3');
    final keptVideo = File('${tempDir.path}/kept-video.mp4');
    await changedVideo.writeAsString('old video');
    await removedVideo.writeAsString('removed video');
    await changedAudio.writeAsString('old audio');
    await keptVideo.writeAsString('kept video');

    final index = MediaCacheIndex(
      cachedVideoFiles: {
        'video-changed': changedVideo.path,
        'video-removed': removedVideo.path,
        'video-kept': keptVideo.path,
      },
      cachedAmbientAudioFiles: {'rain': changedAudio.path},
      removedVideoIds: {'video-restored'},
      removedAmbientTrackIds: {'wind-restored'},
    );

    final result = await index.reconcileRemoteMediaChanges(
      const RemoteMediaChanges(
        changedVideoIds: ['video-changed', 'video-restored'],
        removedVideoIds: ['video-removed'],
        changedAmbientTrackIds: ['rain', 'wind-restored'],
        removedAmbientTrackIds: ['fire'],
      ),
    );

    expect(result.deletedFilePaths, contains(changedVideo.path));
    expect(result.deletedFilePaths, contains(removedVideo.path));
    expect(result.deletedFilePaths, contains(changedAudio.path));
    expect(await changedVideo.exists(), isFalse);
    expect(await removedVideo.exists(), isFalse);
    expect(await changedAudio.exists(), isFalse);
    expect(await keptVideo.exists(), isTrue);
    expect(result.invalidatedVideoIds, {'video-changed', 'video-removed'});
    expect(result.removedVideoIds, {'video-removed'});
    expect(result.restoredVideoIds, {'video-restored'});
    expect(result.invalidatedAmbientTrackIds, {'rain'});
    expect(result.removedAmbientTrackIds, {'fire'});
    expect(result.restoredAmbientTrackIds, {'wind-restored'});
    expect(result.index.cachedVideoFiles, {'video-kept': keptVideo.path});
    expect(result.index.cachedAmbientAudioFiles, isEmpty);
    expect(result.index.removedVideoIds, {'video-removed'});
    expect(result.index.removedAmbientTrackIds, {'fire'});
  });
}
