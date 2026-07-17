import 'package:flutter_test/flutter_test.dart';
import 'package:huxi_zen/src/content/content_repository.dart';
import 'package:huxi_zen/src/media/media_prefetch_policy.dart';
import 'package:huxi_zen/src/media/media_resource_resolver.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'downloads a remote video without waiting for the local cycle',
    () async {
      final content = await const AssetContentRepository().load();
      final localA = content.videos.firstWhere(
        (item) => item.id == 'pixabay-28707',
      );
      final localB = content.videos.firstWhere(
        (item) => item.id == 'pixabay-47213',
      );
      final remote = content.videos.firstWhere(
        (item) => item.id == 'pixabay-228847',
      );
      final resolver = MediaResourceResolver(
        content,
        catalog: MediaResourceCatalog(
          bundledVideoAssets: {localA.id: 'assets/videos/${localA.id}.mp4'},
          cachedVideoFiles: {localB.id: '/cache/videos/${localB.id}.mp4'},
        ),
      );
      final policy = MediaPrefetchPolicy(resolver);

      final ready = policy.nextVideoToDownload(
        playbackScope: [localA, localB, remote],
        playedVideoIds: {localA.id},
      );

      expect(ready.shouldDownload, isTrue);
      expect(ready.reason, MediaPrefetchBlockReason.ready);
      expect(ready.video?.id, remote.id);
      expect(ready.remainingLocalVideoIds, {localB.id});
    },
  );

  test('can prefetch when no bundled or cached video exists', () async {
    final content = await const AssetContentRepository().load();
    final videos = content.publishedVideos.take(3).toList(growable: false);
    final policy = MediaPrefetchPolicy(MediaResourceResolver(content));

    final decision = policy.nextVideoToDownload(
      playbackScope: videos,
      playedVideoIds: const {},
    );

    expect(decision.shouldDownload, isTrue);
    expect(decision.video?.id, videos.first.id);
  });

  test('skips removed, current, and already requested videos', () async {
    final content = await const AssetContentRepository().load();
    final local = content.videos.firstWhere(
      (item) => item.id == 'pixabay-28707',
    );
    final currentRemote = content.videos.firstWhere(
      (item) => item.id == 'pixabay-228847',
    );
    final skippedRemote = content.videos.firstWhere(
      (item) => item.id == 'pixabay-47213',
    );
    final removedRemote = content.videos.firstWhere(
      (item) => item.id == 'pixabay-271161',
    );
    final nextRemote = content.videos.firstWhere(
      (item) => item.id == 'pixabay-333600',
    );
    final resolver = MediaResourceResolver(
      content,
      catalog: MediaResourceCatalog(
        cachedVideoFiles: {local.id: '/cache/videos/${local.id}.mp4'},
        removedVideoIds: {removedRemote.id},
      ),
    );
    final policy = MediaPrefetchPolicy(resolver);

    final decision = policy.nextVideoToDownload(
      playbackScope: [
        local,
        currentRemote,
        skippedRemote,
        removedRemote,
        nextRemote,
      ],
      playedVideoIds: {local.id},
      skippedVideoIds: {skippedRemote.id},
      currentVideoId: currentRemote.id,
    );

    expect(decision.shouldDownload, isTrue);
    expect(decision.video?.id, nextRemote.id);
  });
}
