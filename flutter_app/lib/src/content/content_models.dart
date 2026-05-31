class ContentBundle {
  const ContentBundle({
    required this.manifest,
    required this.config,
    required this.videos,
    required this.ambientCatalog,
    required this.ambientRules,
    required this.videoAudioMixes,
  });

  final ContentManifest manifest;
  final ContentConfig config;
  final List<VideoItem> videos;
  final AmbientCatalog ambientCatalog;
  final List<AmbientRule> ambientRules;
  final List<VideoAudioMix> videoAudioMixes;

  List<VideoItem> get publishedVideos => videos
      .where((video) => video.qualityTier == 'published')
      .toList(growable: false);
}

class ContentManifest {
  const ContentManifest({
    required this.schemaVersion,
    required this.contentVersion,
    required this.defaultVideoLibrary,
    required this.files,
    this.media = const ContentMediaManifest.empty(),
  });

  final int schemaVersion;
  final String contentVersion;
  final String defaultVideoLibrary;
  final Map<String, ManifestFile> files;
  final ContentMediaManifest media;

  factory ContentManifest.fromJson(JsonMap json) {
    final rawFiles = json['files'];
    return ContentManifest(
      schemaVersion: _intValue(json['schemaVersion']),
      contentVersion: _stringValue(json['contentVersion']),
      defaultVideoLibrary: _stringValue(json['defaultVideoLibrary']),
      files: rawFiles is Map
          ? rawFiles.map(
              (key, value) => MapEntry(
                key.toString(),
                ManifestFile.fromJson(_jsonMap(value)),
              ),
            )
          : const {},
      media: ContentMediaManifest.fromJson(_jsonMap(json['media'])),
    );
  }
}

class ContentMediaManifest {
  const ContentMediaManifest({
    required this.videos,
    required this.ambientTracks,
  });

  const ContentMediaManifest.empty()
    : videos = const {},
      ambientTracks = const {};

  final Map<String, ManifestMediaFile> videos;
  final Map<String, ManifestMediaFile> ambientTracks;

  factory ContentMediaManifest.fromJson(JsonMap json) {
    return ContentMediaManifest(
      videos: _mediaFileMap(json['videos']),
      ambientTracks: _mediaFileMap(json['ambientTracks']),
    );
  }
}

class ManifestFile {
  const ManifestFile({required this.bytes, required this.sha256});

  final int bytes;
  final String sha256;

  factory ManifestFile.fromJson(JsonMap json) {
    return ManifestFile(
      bytes: _intValue(json['bytes']),
      sha256: _stringValue(json['sha256']),
    );
  }
}

class ManifestMediaFile extends ManifestFile {
  const ManifestMediaFile({
    required super.bytes,
    required super.sha256,
    required this.path,
  });

  final String path;

  factory ManifestMediaFile.fromJson(JsonMap json) {
    return ManifestMediaFile(
      path: _stringValue(json['path']),
      bytes: _intValue(json['bytes']),
      sha256: _stringValue(json['sha256']),
    );
  }
}

class ContentConfig {
  const ContentConfig({
    required this.schemaVersion,
    required this.contentVersion,
    required this.defaultVideoLibrary,
    required this.defaultVideoBase,
    required this.defaultAmbientAudioBase,
  });

  final int schemaVersion;
  final String contentVersion;
  final String defaultVideoLibrary;
  final String defaultVideoBase;
  final String defaultAmbientAudioBase;

  factory ContentConfig.fromJson(JsonMap json) {
    return ContentConfig(
      schemaVersion: _intValue(json['schemaVersion']),
      contentVersion: _stringValue(json['contentVersion']),
      defaultVideoLibrary: _stringValue(json['defaultVideoLibrary']),
      defaultVideoBase: _stringValue(json['defaultVideoBase']),
      defaultAmbientAudioBase: _stringValue(json['defaultAmbientAudioBase']),
    );
  }
}

class VideoItem {
  const VideoItem({
    required this.id,
    required this.name,
    required this.displayName,
    required this.locationName,
    required this.locationCountry,
    required this.sourceName,
    required this.sourcePage,
    required this.sourceDownloadPage,
    required this.url,
    required this.previewImage,
    required this.category,
    required this.subcategories,
    required this.tags,
    required this.timeOfDay,
    required this.description,
    required this.sourceResolution,
    required this.duration,
    required this.license,
    required this.attribution,
    required this.licenseNotes,
    required this.qualityTier,
  });

  final String id;
  final String name;
  final String displayName;
  final String locationName;
  final String locationCountry;
  final String sourceName;
  final String sourcePage;
  final String sourceDownloadPage;
  final String url;
  final String previewImage;
  final String category;
  final List<String> subcategories;
  final List<String> tags;
  final String timeOfDay;
  final String description;
  final String sourceResolution;
  final String duration;
  final String license;
  final String attribution;
  final String licenseNotes;
  final String qualityTier;

  String titleForDisplay() => displayName.isNotEmpty ? displayName : name;

  String favoriteKey(String videoLibrary) => '$videoLibrary:$id';

  String remoteVideoUrl(String videoBase) {
    final base = _normalizeBase(videoBase);
    return base.isEmpty ? url : '$base/videos/$id.mp4';
  }

  factory VideoItem.fromJson(JsonMap json) {
    return VideoItem(
      id: _stringValue(json['id']),
      name: _stringValue(json['name']),
      displayName: _stringValue(json['displayName']),
      locationName: _stringValue(json['locationName']),
      locationCountry: _stringValue(json['locationCountry']),
      sourceName: _stringValue(json['sourceName']),
      sourcePage: _stringValue(json['sourcePage']),
      sourceDownloadPage: _stringValue(json['sourceDownloadPage']),
      url: _stringValue(json['url']),
      previewImage: _stringValue(json['previewImage']),
      category: _stringValue(json['category']),
      subcategories: _stringList(json['subcategories']),
      tags: _stringList(json['tags']),
      timeOfDay: _stringValue(json['timeOfDay']),
      description: _stringValue(json['description']),
      sourceResolution: _stringValue(json['sourceResolution']),
      duration: _stringValue(json['duration']),
      license: _stringValue(json['license']),
      attribution: _stringValue(json['attribution']),
      licenseNotes: _stringValue(json['licenseNotes']),
      qualityTier: _stringValue(json['qualityTier']),
    );
  }
}

class AmbientCatalog {
  const AmbientCatalog({
    required this.modes,
    required this.maxCustomAmbientTracks,
    required this.tracks,
    required this.customTrackIds,
    required this.customLabels,
  });

  final Map<String, String> modes;
  final int maxCustomAmbientTracks;
  final Map<String, AmbientTrack> tracks;
  final List<String> customTrackIds;
  final Map<String, String> customLabels;

  factory AmbientCatalog.fromJson(JsonMap json) {
    final rawModes = json['modes'];
    final rawTracks = json['tracks'];
    final rawLabels = json['customLabels'];
    return AmbientCatalog(
      modes: rawModes is Map
          ? rawModes.map(
              (key, value) => MapEntry(key.toString(), value.toString()),
            )
          : const {},
      maxCustomAmbientTracks: _intValue(json['maxCustomAmbientTracks']),
      tracks: rawTracks is Map
          ? rawTracks.map(
              (key, value) => MapEntry(
                key.toString(),
                AmbientTrack.fromJson(
                  _jsonMap(value),
                  fallbackId: key.toString(),
                ),
              ),
            )
          : const {},
      customTrackIds: _stringList(json['customTrackIds']),
      customLabels: rawLabels is Map
          ? rawLabels.map(
              (key, value) => MapEntry(key.toString(), value.toString()),
            )
          : const {},
    );
  }
}

class AmbientTrack {
  const AmbientTrack({
    required this.id,
    required this.label,
    required this.file,
    required this.durationMs,
    required this.volume,
  });

  final String id;
  final String label;
  final String file;
  final int durationMs;
  final double volume;

  factory AmbientTrack.fromJson(JsonMap json, {String fallbackId = ''}) {
    return AmbientTrack(
      id: _stringValue(json['id'], fallback: fallbackId),
      label: _stringValue(json['label']),
      file: _stringValue(json['file']),
      durationMs: _intValue(json['durationMs']),
      volume: _doubleValue(json['volume']),
    );
  }
}

class AmbientRule {
  const AmbientRule({
    required this.trackId,
    required this.any,
    required this.none,
  });

  final String trackId;
  final List<String> any;
  final List<String> none;

  factory AmbientRule.fromJson(JsonMap json) {
    return AmbientRule(
      trackId: _stringValue(json['trackId']),
      any: _stringList(json['any']),
      none: _stringList(json['none']),
    );
  }
}

class VideoAudioMix {
  const VideoAudioMix({
    required this.videoId,
    required this.mix,
    required this.notes,
  });

  final String videoId;
  final List<AmbientMixSpec>? mix;
  final String notes;

  factory VideoAudioMix.fromJson(JsonMap json) {
    final rawMix = json['mix'];
    return VideoAudioMix(
      videoId: _stringValue(json['videoId']),
      mix: rawMix is List
          ? rawMix
                .map((item) => AmbientMixSpec.fromJson(_jsonMap(item)))
                .where((item) => item.trackId.isNotEmpty)
                .toList(growable: false)
          : null,
      notes: _stringValue(json['notes']),
    );
  }
}

class AmbientMixSpec {
  const AmbientMixSpec({required this.trackId, this.volume, this.label});

  final String trackId;
  final double? volume;
  final String? label;

  factory AmbientMixSpec.fromJson(JsonMap json) {
    return AmbientMixSpec(
      trackId: _stringValue(json['trackId']),
      volume: json.containsKey('volume') ? _doubleValue(json['volume']) : null,
      label: json.containsKey('label') ? _stringValue(json['label']) : null,
    );
  }
}

class CustomAmbientSetting {
  const CustomAmbientSetting({required this.trackId, required this.volume});

  final String trackId;
  final double volume;
}

class AmbientMix {
  const AmbientMix({
    required this.id,
    required this.label,
    required this.tracks,
  });

  final String id;
  final String label;
  final List<ResolvedAmbientTrack> tracks;
}

class ResolvedAmbientTrack {
  const ResolvedAmbientTrack({
    required this.id,
    required this.channelId,
    required this.label,
    required this.file,
    required this.durationMs,
    required this.volume,
    required this.url,
  });

  final String id;
  final String channelId;
  final String label;
  final String file;
  final int durationMs;
  final double volume;
  final String url;
}

typedef JsonMap = Map<String, Object?>;

JsonMap _jsonMap(Object? value) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) {
    return value.map((key, item) => MapEntry(key.toString(), item));
  }
  return const {};
}

Map<String, ManifestMediaFile> _mediaFileMap(Object? value) {
  if (value is! Map) return const {};
  return value.map(
    (key, item) =>
        MapEntry(key.toString(), ManifestMediaFile.fromJson(_jsonMap(item))),
  );
}

String _stringValue(Object? value, {String fallback = ''}) {
  final text = value == null ? fallback : value.toString();
  return text.trim();
}

int _intValue(Object? value) {
  if (value is int) return value;
  if (value is num) return value.round();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

double _doubleValue(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

List<String> _stringList(Object? value) {
  if (value is! List) return const [];
  return value
      .map((item) => item.toString().trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}

String _normalizeBase(String value) =>
    value.trim().replaceFirst(RegExp(r'/$'), '');
