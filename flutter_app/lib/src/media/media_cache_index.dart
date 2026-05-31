import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import '../content/remote_content_sync.dart';
import 'media_resource_resolver.dart';

class MediaCacheIndex {
  const MediaCacheIndex({
    this.cachedVideoFiles = const {},
    this.cachedAmbientAudioFiles = const {},
    this.removedVideoIds = const {},
    this.removedAmbientTrackIds = const {},
  });

  static const _storageKey = 'media-cache-index-v1';

  final Map<String, String> cachedVideoFiles;
  final Map<String, String> cachedAmbientAudioFiles;
  final Set<String> removedVideoIds;
  final Set<String> removedAmbientTrackIds;

  static Future<MediaCacheIndex> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) return const MediaCacheIndex();

    try {
      final decoded = jsonDecode(raw);
      return MediaCacheIndex.fromJson(_jsonMap(decoded));
    } on FormatException {
      return const MediaCacheIndex();
    }
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, jsonEncode(toJson()));
  }

  Future<MediaCacheIndex> pruneMissingFiles() async {
    return (await cleanupLocalFiles()).index;
  }

  Future<MediaCacheCleanupResult> cleanupLocalFiles() async {
    final videos = await _cleanupFiles(
      cachedVideoFiles,
      removedIds: removedVideoIds,
    );
    final audio = await _cleanupFiles(
      cachedAmbientAudioFiles,
      removedIds: removedAmbientTrackIds,
    );
    final nextIndex = copyWith(
      cachedVideoFiles: videos.files,
      cachedAmbientAudioFiles: audio.files,
    );
    return MediaCacheCleanupResult(
      index: nextIndex,
      deletedFilePaths: [...videos.deletedFilePaths, ...audio.deletedFilePaths],
      missingVideoIds: videos.missingIds,
      missingAmbientTrackIds: audio.missingIds,
    );
  }

  Future<MediaCacheReconcileResult> reconcileRemoteMediaChanges(
    RemoteMediaChanges changes,
  ) async {
    final videos = await _reconcileFiles(
      cachedVideoFiles,
      changedIds: changes.changedVideoIds.toSet(),
      removedIds: changes.removedVideoIds.toSet(),
    );
    final audio = await _reconcileFiles(
      cachedAmbientAudioFiles,
      changedIds: changes.changedAmbientTrackIds.toSet(),
      removedIds: changes.removedAmbientTrackIds.toSet(),
    );

    final nextRemovedVideoIds = Set<String>.of(removedVideoIds)
      ..addAll(changes.removedVideoIds)
      ..removeAll(changes.changedVideoIds);
    final nextRemovedAmbientTrackIds = Set<String>.of(removedAmbientTrackIds)
      ..addAll(changes.removedAmbientTrackIds)
      ..removeAll(changes.changedAmbientTrackIds);
    final restoredVideoIds = changes.changedVideoIds
        .where(removedVideoIds.contains)
        .toSet();
    final restoredAmbientTrackIds = changes.changedAmbientTrackIds
        .where(removedAmbientTrackIds.contains)
        .toSet();

    final nextIndex = copyWith(
      cachedVideoFiles: videos.files,
      cachedAmbientAudioFiles: audio.files,
      removedVideoIds: nextRemovedVideoIds,
      removedAmbientTrackIds: nextRemovedAmbientTrackIds,
    );

    return MediaCacheReconcileResult(
      index: nextIndex,
      deletedFilePaths: [...videos.deletedFilePaths, ...audio.deletedFilePaths],
      invalidatedVideoIds: videos.invalidatedIds,
      removedVideoIds: changes.removedVideoIds.toSet(),
      restoredVideoIds: restoredVideoIds,
      invalidatedAmbientTrackIds: audio.invalidatedIds,
      removedAmbientTrackIds: changes.removedAmbientTrackIds.toSet(),
      restoredAmbientTrackIds: restoredAmbientTrackIds,
    );
  }

  factory MediaCacheIndex.fromJson(Map<String, Object?> json) {
    return MediaCacheIndex(
      cachedVideoFiles: _stringMap(json['cachedVideoFiles']),
      cachedAmbientAudioFiles: _stringMap(json['cachedAmbientAudioFiles']),
      removedVideoIds: _stringSet(json['removedVideoIds']),
      removedAmbientTrackIds: _stringSet(json['removedAmbientTrackIds']),
    );
  }

  Map<String, Object?> toJson() {
    return {
      'cachedVideoFiles': cachedVideoFiles,
      'cachedAmbientAudioFiles': cachedAmbientAudioFiles,
      'removedVideoIds': _sorted(removedVideoIds),
      'removedAmbientTrackIds': _sorted(removedAmbientTrackIds),
    };
  }

  MediaResourceCatalog toResourceCatalog({
    MediaResourceCatalog bundled = const MediaResourceCatalog.empty(),
  }) {
    return MediaResourceCatalog(
      bundledVideoAssets: bundled.bundledVideoAssets,
      cachedVideoFiles: cachedVideoFiles,
      removedVideoIds: removedVideoIds,
      bundledAmbientAudioAssets: bundled.bundledAmbientAudioAssets,
      cachedAmbientAudioFiles: cachedAmbientAudioFiles,
      removedAmbientTrackIds: removedAmbientTrackIds,
    );
  }

  MediaCacheIndex withCachedVideo(String videoId, String filePath) {
    final nextCached = Map<String, String>.of(cachedVideoFiles)
      ..[videoId] = filePath;
    final nextRemoved = Set<String>.of(removedVideoIds)..remove(videoId);
    return copyWith(cachedVideoFiles: nextCached, removedVideoIds: nextRemoved);
  }

  MediaCacheIndex withCachedAmbientTrack(String trackId, String filePath) {
    final nextCached = Map<String, String>.of(cachedAmbientAudioFiles)
      ..[trackId] = filePath;
    final nextRemoved = Set<String>.of(removedAmbientTrackIds)..remove(trackId);
    return copyWith(
      cachedAmbientAudioFiles: nextCached,
      removedAmbientTrackIds: nextRemoved,
    );
  }

  MediaCacheIndex withRemovedVideo(String videoId) {
    final nextCached = Map<String, String>.of(cachedVideoFiles)
      ..remove(videoId);
    final nextRemoved = Set<String>.of(removedVideoIds)..add(videoId);
    return copyWith(cachedVideoFiles: nextCached, removedVideoIds: nextRemoved);
  }

  MediaCacheIndex withRemovedAmbientTrack(String trackId) {
    final nextCached = Map<String, String>.of(cachedAmbientAudioFiles)
      ..remove(trackId);
    final nextRemoved = Set<String>.of(removedAmbientTrackIds)..add(trackId);
    return copyWith(
      cachedAmbientAudioFiles: nextCached,
      removedAmbientTrackIds: nextRemoved,
    );
  }

  MediaCacheIndex copyWith({
    Map<String, String>? cachedVideoFiles,
    Map<String, String>? cachedAmbientAudioFiles,
    Set<String>? removedVideoIds,
    Set<String>? removedAmbientTrackIds,
  }) {
    return MediaCacheIndex(
      cachedVideoFiles: cachedVideoFiles ?? this.cachedVideoFiles,
      cachedAmbientAudioFiles:
          cachedAmbientAudioFiles ?? this.cachedAmbientAudioFiles,
      removedVideoIds: removedVideoIds ?? this.removedVideoIds,
      removedAmbientTrackIds:
          removedAmbientTrackIds ?? this.removedAmbientTrackIds,
    );
  }
}

class MediaCacheCleanupResult {
  const MediaCacheCleanupResult({
    required this.index,
    this.deletedFilePaths = const [],
    this.missingVideoIds = const {},
    this.missingAmbientTrackIds = const {},
  });

  final MediaCacheIndex index;
  final List<String> deletedFilePaths;
  final Set<String> missingVideoIds;
  final Set<String> missingAmbientTrackIds;

  bool get changed =>
      deletedFilePaths.isNotEmpty ||
      missingVideoIds.isNotEmpty ||
      missingAmbientTrackIds.isNotEmpty;
}

class MediaCacheReconcileResult {
  const MediaCacheReconcileResult({
    required this.index,
    this.deletedFilePaths = const [],
    this.invalidatedVideoIds = const {},
    this.removedVideoIds = const {},
    this.restoredVideoIds = const {},
    this.invalidatedAmbientTrackIds = const {},
    this.removedAmbientTrackIds = const {},
    this.restoredAmbientTrackIds = const {},
  });

  final MediaCacheIndex index;
  final List<String> deletedFilePaths;
  final Set<String> invalidatedVideoIds;
  final Set<String> removedVideoIds;
  final Set<String> restoredVideoIds;
  final Set<String> invalidatedAmbientTrackIds;
  final Set<String> removedAmbientTrackIds;
  final Set<String> restoredAmbientTrackIds;

  bool get changed =>
      deletedFilePaths.isNotEmpty ||
      invalidatedVideoIds.isNotEmpty ||
      removedVideoIds.isNotEmpty ||
      restoredVideoIds.isNotEmpty ||
      invalidatedAmbientTrackIds.isNotEmpty ||
      removedAmbientTrackIds.isNotEmpty ||
      restoredAmbientTrackIds.isNotEmpty;
}

Map<String, Object?> _jsonMap(Object? value) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) {
    return value.map((key, item) => MapEntry(key.toString(), item));
  }
  return const {};
}

Map<String, String> _stringMap(Object? value) {
  if (value is! Map) return const {};
  return value.map(
    (key, item) => MapEntry(key.toString(), item?.toString() ?? ''),
  )..removeWhere((key, item) => key.trim().isEmpty || item.trim().isEmpty);
}

Set<String> _stringSet(Object? value) {
  if (value is! List) return const {};
  return value
      .map((item) => item.toString().trim())
      .where((item) => item.isNotEmpty)
      .toSet();
}

List<String> _sorted(Set<String> values) {
  return values.toList(growable: false)..sort();
}

Future<_CacheFileCleanup> _cleanupFiles(
  Map<String, String> files, {
  required Set<String> removedIds,
}) async {
  final existing = <String, String>{};
  final deleted = <String>[];
  final missing = <String>{};
  for (final entry in files.entries) {
    final file = File(entry.value);
    if (removedIds.contains(entry.key)) {
      if (await file.exists()) {
        try {
          await file.delete();
          deleted.add(entry.value);
        } on FileSystemException {
          // Cache cleanup is best-effort. Removed ids still leave the playable
          // index so stale files cannot be selected again.
        }
      }
      continue;
    }
    if (await file.exists()) {
      existing[entry.key] = entry.value;
    } else {
      missing.add(entry.key);
    }
  }
  return _CacheFileCleanup(
    files: existing,
    deletedFilePaths: deleted,
    missingIds: missing,
  );
}

class _CacheFileCleanup {
  const _CacheFileCleanup({
    required this.files,
    required this.deletedFilePaths,
    required this.missingIds,
  });

  final Map<String, String> files;
  final List<String> deletedFilePaths;
  final Set<String> missingIds;
}

Future<_CacheFileReconcile> _reconcileFiles(
  Map<String, String> files, {
  required Set<String> changedIds,
  required Set<String> removedIds,
}) async {
  final next = Map<String, String>.of(files);
  final deleted = <String>[];
  final invalidated = <String>{};
  final affectedIds = {...changedIds, ...removedIds};

  for (final id in affectedIds) {
    final path = next.remove(id);
    if (path == null || path.isEmpty) continue;
    invalidated.add(id);
    final file = File(path);
    if (await file.exists()) {
      try {
        await file.delete();
        deleted.add(path);
      } on FileSystemException {
        // Best effort. The index still stops selecting this stale cache entry.
      }
    }
  }

  return _CacheFileReconcile(
    files: next,
    deletedFilePaths: deleted,
    invalidatedIds: invalidated,
  );
}

class _CacheFileReconcile {
  const _CacheFileReconcile({
    required this.files,
    required this.deletedFilePaths,
    required this.invalidatedIds,
  });

  final Map<String, String> files;
  final List<String> deletedFilePaths;
  final Set<String> invalidatedIds;
}
