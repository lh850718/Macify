import 'package:flutter_test/flutter_test.dart';
import 'package:huxi_zen/src/content/ambient_resolver.dart';
import 'package:huxi_zen/src/content/content_repository.dart';
import 'package:huxi_zen/src/media/media_resource_resolver.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('loads generated content assets', () async {
    final content = await const AssetContentRepository().load();

    expect(content.config.defaultVideoLibrary, 'premiumFreeAerial');
    expect(content.manifest.contentVersion, content.config.contentVersion);
    expect(content.publishedVideos, hasLength(60));
    expect(content.ambientCatalog.tracks.keys, contains('sky'));
    expect(content.manifest.media.videos, hasLength(60));
    expect(content.manifest.media.ambientTracks, hasLength(13));
    expect(
      content.manifest.media.videos['pixabay-28707']?.path,
      'videos/pixabay-28707.mp4',
    );
    expect(
      content.manifest.media.videos['pixabay-28707']?.bytes,
      greaterThan(0),
    );
    expect(
      content.manifest.media.videos['pixabay-28707']?.sha256,
      hasLength(64),
    );
    expect(
      content.manifest.media.ambientTracks['waterfall']?.path,
      'waterfall.mp3',
    );
  });

  test('resolves screened explicit video ambient mix', () async {
    final content = await const AssetContentRepository().load();
    final resolver = AmbientResolver(content);
    final video = content.videos.firstWhere(
      (item) => item.id == 'pixabay-339840',
    );

    final mix = resolver.ambientTrackForVideo(video);

    expect(mix?.label, '海浪海鸥 + 风声');
    expect(mix?.tracks.map((track) => track.channelId), ['oceanGulls', 'wind']);
    expect(mix?.tracks.map((track) => track.volume), [0.64, 0.2]);
  });

  test('omits videos deleted by manual screening', () async {
    final content = await const AssetContentRepository().load();

    expect(
      content.videos.any(
        (item) => item.id == 'mixkit-large-lake-sunset-aerial-4998',
      ),
      isFalse,
    );
  });

  test('uses screened multi-track waterfall mix', () async {
    final content = await const AssetContentRepository().load();
    final resolver = AmbientResolver(content);
    final video = content.videos.firstWhere(
      (item) => item.id == 'pixabay-28707',
    );

    final mix = resolver.ambientTrackForVideo(video);

    expect(mix?.label, '风声 + 瀑布 + 海浪');
    expect(mix?.tracks.map((track) => track.channelId), [
      'wind',
      'waterfall',
      'ocean',
    ]);
  });

  test('ambient resolver can use cached resource locations', () async {
    final content = await const AssetContentRepository().load();
    final mediaResolver = MediaResourceResolver(
      content,
      catalog: const MediaResourceCatalog(
        cachedAmbientAudioFiles: {'waterfall': '/cache/audio/waterfall.mp3'},
      ),
    );
    final resolver = AmbientResolver(content, mediaResolver: mediaResolver);
    final video = content.videos.firstWhere(
      (item) => item.id == 'pixabay-28707',
    );

    final mix = resolver.ambientTrackForVideo(video);

    expect(
      mix?.tracks.firstWhere((track) => track.channelId == 'waterfall').url,
      '/cache/audio/waterfall.mp3',
    );
  });

  test('ambient resolver omits removed resource locations', () async {
    final content = await const AssetContentRepository().load();
    final mediaResolver = MediaResourceResolver(
      content,
      catalog: const MediaResourceCatalog(
        removedAmbientTrackIds: {'wind', 'waterfall', 'ocean'},
      ),
    );
    final resolver = AmbientResolver(content, mediaResolver: mediaResolver);
    final video = content.videos.firstWhere(
      (item) => item.id == 'pixabay-28707',
    );

    expect(resolver.ambientTrackForVideo(video), isNull);
  });
}
