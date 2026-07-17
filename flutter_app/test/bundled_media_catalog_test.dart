import 'package:flutter_test/flutter_test.dart';
import 'package:huxi_zen/src/content/content_repository.dart';
import 'package:huxi_zen/src/media/bundled_media_catalog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('loads the bundled media asset catalog', () async {
    final content = await const AssetContentRepository().load();

    final catalog = await loadBundledMediaCatalog(content);

    expect(catalog.bundledVideoAssets, hasLength(19));
    expect(catalog.bundledAmbientAudioAssets, hasLength(12));
    expect(catalog.bundledVideoAssets.keys, isNot(contains('pixabay-159703')));
    expect(catalog.bundledAmbientAudioAssets.keys, isNot(contains('tractor')));
    expect(
      catalog.bundledVideoAssets['pixabay-339840'],
      'assets/media/videos/pixabay-339840.mp4',
    );
    expect(
      catalog.bundledAmbientAudioAssets['waterfall'],
      'assets/media/audio/waterfall.mp3',
    );
  });
}
