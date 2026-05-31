import 'package:flutter_test/flutter_test.dart';
import 'package:huxi_zen/src/content/content_repository.dart';
import 'package:huxi_zen/src/media/media_resource_resolver.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('resolves remote video and ambient audio by default', () async {
    final content = await const AssetContentRepository().load();
    final resolver = MediaResourceResolver(content);
    final video = content.videos.firstWhere(
      (item) => item.id == 'pixabay-28707',
    );
    final audio = content.ambientCatalog.tracks['waterfall']!;

    final videoResource = resolver.videoResourceFor(video);
    final audioResource = resolver.ambientAudioResourceFor(audio);

    expect(videoResource.status, MediaResourceStatus.remote);
    expect(
      videoResource.uri,
      endsWith('/macify-premium/videos/pixabay-28707.mp4'),
    );
    expect(audioResource.status, MediaResourceStatus.remote);
    expect(audioResource.uri, endsWith('/macify-audio/waterfall.mp3'));
  });

  test('prefers cached resource over bundled and remote', () async {
    final content = await const AssetContentRepository().load();
    final video = content.videos.firstWhere(
      (item) => item.id == 'pixabay-28707',
    );
    final audio = content.ambientCatalog.tracks['waterfall']!;
    final resolver = MediaResourceResolver(
      content,
      catalog: const MediaResourceCatalog(
        bundledVideoAssets: {
          'pixabay-28707': 'assets/videos/pixabay-28707.mp4',
        },
        cachedVideoFiles: {'pixabay-28707': '/cache/videos/pixabay-28707.mp4'},
        bundledAmbientAudioAssets: {'waterfall': 'assets/audio/waterfall.mp3'},
        cachedAmbientAudioFiles: {'waterfall': '/cache/audio/waterfall.mp3'},
      ),
    );

    final videoResource = resolver.videoResourceFor(video);
    final audioResource = resolver.ambientAudioResourceFor(audio);

    expect(videoResource.status, MediaResourceStatus.cached);
    expect(videoResource.uri, '/cache/videos/pixabay-28707.mp4');
    expect(videoResource.isLocal, isTrue);
    expect(audioResource.status, MediaResourceStatus.cached);
    expect(audioResource.uri, '/cache/audio/waterfall.mp3');
    expect(audioResource.isPlayable, isTrue);
  });

  test('removed resource wins over stale local copies', () async {
    final content = await const AssetContentRepository().load();
    final video = content.videos.firstWhere(
      (item) => item.id == 'pixabay-28707',
    );
    final audio = content.ambientCatalog.tracks['waterfall']!;
    final resolver = MediaResourceResolver(
      content,
      catalog: const MediaResourceCatalog(
        cachedVideoFiles: {'pixabay-28707': '/cache/videos/pixabay-28707.mp4'},
        removedVideoIds: {'pixabay-28707'},
        cachedAmbientAudioFiles: {'waterfall': '/cache/audio/waterfall.mp3'},
        removedAmbientTrackIds: {'waterfall'},
      ),
    );

    final videoResource = resolver.videoResourceFor(video);
    final audioResource = resolver.ambientAudioResourceFor(audio);

    expect(videoResource.status, MediaResourceStatus.removed);
    expect(videoResource.isPlayable, isFalse);
    expect(audioResource.status, MediaResourceStatus.removed);
    expect(audioResource.uri, isEmpty);
  });
}
