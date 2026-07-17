import 'package:flutter_test/flutter_test.dart';
import 'package:huxi_zen/src/content/ambient_resolver.dart';
import 'package:huxi_zen/src/content/content_models.dart';

void main() {
  test('normalizes ambient mix weights to the loudest selected track', () {
    final resolver = AmbientResolver(_content);

    final mix = resolver.ambientMixFromSpec(const [
      AmbientMixSpec(trackId: 'a', volume: 0.4),
      AmbientMixSpec(trackId: 'b', volume: 0.3),
      AmbientMixSpec(trackId: 'c', volume: 0.1),
    ]);

    expect(mix?.tracks.map((track) => track.volume), [
      1,
      closeTo(0.75, 0.0001),
      0.25,
    ]);
  });

  test('normalizes custom ambient mixes without changing stored weights', () {
    final resolver = AmbientResolver(_content);

    final mix = resolver.ambientMixFromCustomSettings(const [
      CustomAmbientSetting(trackId: 'a', volume: 0.54),
      CustomAmbientSetting(trackId: 'b', volume: 0.15),
    ]);

    expect(mix?.tracks.first.volume, 1);
    expect(mix?.tracks.last.volume, closeTo(0.2778, 0.0001));
  });

  test('single non-zero ambient track resolves to full playback volume', () {
    final resolver = AmbientResolver(_content);

    final mix = resolver.ambientMixFromSpec(const [
      AmbientMixSpec(trackId: 'a', volume: 0.4),
    ]);

    expect(mix?.tracks.single.volume, 1);
  });

  test('all-zero ambient mix resolves as unavailable', () {
    final resolver = AmbientResolver(_content);

    final mix = resolver.ambientMixFromSpec(const [
      AmbientMixSpec(trackId: 'a', volume: 0),
      AmbientMixSpec(trackId: 'b', volume: 0),
    ]);

    expect(mix, isNull);
  });
}

const _content = ContentBundle(
  manifest: ContentManifest(
    schemaVersion: 1,
    contentVersion: 'test',
    defaultVideoLibrary: 'premiumFreeAerial',
    files: {},
  ),
  config: ContentConfig(
    schemaVersion: 1,
    contentVersion: 'test',
    defaultVideoLibrary: 'premiumFreeAerial',
    defaultVideoBase: 'https://example.com/video',
    defaultAmbientAudioBase: 'https://example.com/audio',
  ),
  videos: [],
  ambientCatalog: AmbientCatalog(
    modes: {'VIDEO': 'video', 'CUSTOM': 'custom'},
    maxCustomAmbientTracks: 5,
    tracks: {
      'a': AmbientTrack(
        id: 'a',
        label: 'A',
        file: 'a.mp3',
        durationMs: 1000,
        volume: 0.4,
      ),
      'b': AmbientTrack(
        id: 'b',
        label: 'B',
        file: 'b.mp3',
        durationMs: 1000,
        volume: 0.3,
      ),
      'c': AmbientTrack(
        id: 'c',
        label: 'C',
        file: 'c.mp3',
        durationMs: 1000,
        volume: 0.1,
      ),
    },
    customTrackIds: ['a', 'b', 'c'],
    customLabels: {},
  ),
  ambientRules: [],
  videoAudioMixes: [],
);
