import '../media/media_resource_resolver.dart';
import 'content_models.dart';

class AmbientResolver {
  AmbientResolver(this.content, {MediaResourceResolver? mediaResolver})
    : _mediaResolver = mediaResolver ?? MediaResourceResolver(content),
      _overrides = {
        for (final mix in content.videoAudioMixes) mix.videoId: mix,
      };

  final ContentBundle content;
  final MediaResourceResolver _mediaResolver;
  final Map<String, VideoAudioMix> _overrides;

  AmbientMix? ambientTrackForVideo(VideoItem? video, {String? audioBase}) {
    if (video == null) return null;

    if (_overrides.containsKey(video.id)) {
      return ambientMixFromSpec(
        _overrides[video.id]?.mix,
        audioBase: audioBase,
      );
    }

    final terms = _collectTerms(video);
    AmbientRule? rule;
    for (final item in content.ambientRules) {
      if (_matchesRule(terms, item)) {
        rule = item;
        break;
      }
    }
    if (rule == null) return null;
    return ambientMixFromSpec(rule.trackId, audioBase: audioBase);
  }

  AmbientMix? ambientMixFromSpec(Object? spec, {String? audioBase}) {
    if (spec == null) return null;

    final specs = switch (spec) {
      String trackId => [AmbientMixSpec(trackId: trackId)],
      AmbientMixSpec mixSpec => [mixSpec],
      List<AmbientMixSpec> mixSpecs => mixSpecs,
      _ => const <AmbientMixSpec>[],
    };
    if (specs.isEmpty) return null;

    final baseOverride = audioBase == null ? null : _normalizeBase(audioBase);
    if (audioBase != null && baseOverride!.isEmpty) return null;

    final tracks = specs
        .map((item) => _hydrateTrack(item, baseOverride))
        .whereType<ResolvedAmbientTrack>()
        .toList(growable: false);
    final normalizedTracks = _normalizeMixVolumes(tracks);
    if (normalizedTracks.isEmpty) return null;

    final label = normalizedTracks.map((track) => track.label).join(' + ');
    final id = normalizedTracks.length == 1
        ? normalizedTracks.first.id
        : 'mix:${normalizedTracks.map((track) => '${track.id}@${track.volume}').join('+')}';
    return AmbientMix(id: id, label: label, tracks: normalizedTracks);
  }

  List<CustomAmbientTrackOption> customAmbientTrackOptions() {
    return content.ambientCatalog.customTrackIds
        .map((trackId) {
          final track = content.ambientCatalog.tracks[trackId];
          if (track == null) return null;
          return CustomAmbientTrackOption(
            id: trackId,
            label: customAmbientTrackLabel(trackId),
          );
        })
        .whereType<CustomAmbientTrackOption>()
        .toList(growable: false);
  }

  List<CustomAmbientSetting> normalizeCustomAmbientMix(
    List<CustomAmbientSetting> raw,
  ) {
    final normalized = <CustomAmbientSetting>[];
    for (final item in raw) {
      if (!content.ambientCatalog.customTrackIds.contains(item.trackId)) {
        continue;
      }
      if (normalized.any((track) => track.trackId == item.trackId)) continue;
      if (normalized.length >= content.ambientCatalog.maxCustomAmbientTracks) {
        break;
      }
      normalized.add(
        CustomAmbientSetting(
          trackId: item.trackId,
          volume: item.volume.clamp(0, 1).toDouble(),
        ),
      );
    }
    return normalized;
  }

  AmbientMix? ambientMixFromCustomSettings(
    List<CustomAmbientSetting> customMix, {
    String? audioBase,
  }) {
    final specs = normalizeCustomAmbientMix(customMix)
        .where((item) => item.volume > 0)
        .map(
          (item) => AmbientMixSpec(
            trackId: item.trackId,
            label: customAmbientTrackLabel(item.trackId),
            volume: item.volume,
          ),
        )
        .toList(growable: false);

    return ambientMixFromSpec(specs, audioBase: audioBase);
  }

  String customAmbientTrackLabel(String trackId) {
    return content.ambientCatalog.customLabels[trackId] ??
        content.ambientCatalog.tracks[trackId]?.label ??
        trackId;
  }

  ResolvedAmbientTrack? _hydrateTrack(AmbientMixSpec spec, String? base) {
    final track = content.ambientCatalog.tracks[spec.trackId];
    if (track == null) return null;
    final resource = base == null
        ? _mediaResolver.ambientAudioResourceFor(track)
        : MediaResource(
            kind: MediaResourceKind.ambientAudio,
            id: track.id,
            status: MediaResourceStatus.remote,
            uri: '$base/${track.file}',
          );
    if (!resource.isPlayable) return null;
    return ResolvedAmbientTrack(
      id: track.id,
      channelId: track.id,
      label: spec.label?.isNotEmpty == true ? spec.label! : track.label,
      file: track.file,
      durationMs: track.durationMs,
      volume: (spec.volume ?? track.volume).clamp(0, 1).toDouble(),
      url: resource.uri,
    );
  }

  List<ResolvedAmbientTrack> _normalizeMixVolumes(
    List<ResolvedAmbientTrack> tracks,
  ) {
    var maxVolume = 0.0;
    for (final track in tracks) {
      maxVolume = maxVolume < track.volume ? track.volume : maxVolume;
    }
    if (maxVolume <= 0) return const [];
    return tracks
        .map(
          (track) => ResolvedAmbientTrack(
            id: track.id,
            channelId: track.channelId,
            label: track.label,
            file: track.file,
            durationMs: track.durationMs,
            volume: track.volume / maxVolume,
            url: track.url,
          ),
        )
        .toList(growable: false);
  }

  List<String> _collectTerms(VideoItem video) {
    return [
          video.category,
          video.timeOfDay,
          video.locationName,
          video.titleForDisplay(),
          video.name,
          ...video.subcategories,
          ...video.tags,
        ]
        .where((item) => item.trim().isNotEmpty)
        .map((item) => item.trim().toLowerCase())
        .toList(growable: false);
  }

  bool _matchesRule(List<String> terms, AmbientRule rule) {
    if (_hasAnyTerm(terms, rule.none)) return false;
    return _hasAnyTerm(terms, rule.any);
  }

  bool _hasAnyTerm(List<String> terms, List<String> matches) {
    return matches.any((match) => terms.contains(match.trim().toLowerCase()));
  }
}

class CustomAmbientTrackOption {
  const CustomAmbientTrackOption({required this.id, required this.label});

  final String id;
  final String label;
}

String _normalizeBase(String value) =>
    value.trim().replaceFirst(RegExp(r'/$'), '');
