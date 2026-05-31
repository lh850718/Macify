import 'dart:convert';

import '../media/remote_file_client.dart';
import 'content_models.dart';

abstract class ContentSyncService {
  Future<RemoteContentCheck> checkManifest({
    required ContentManifest localManifest,
    required Uri remoteManifestUri,
  });
}

class RemoteContentSyncService implements ContentSyncService {
  const RemoteContentSyncService({required this.client});

  final RemoteFileClient client;

  @override
  Future<RemoteContentCheck> checkManifest({
    required ContentManifest localManifest,
    required Uri remoteManifestUri,
  }) async {
    final raw = await client.readString(remoteManifestUri);
    final remoteManifest = ContentManifest.fromJson(_jsonMap(jsonDecode(raw)));
    return RemoteContentCheck.compare(
      localManifest: localManifest,
      remoteManifest: remoteManifest,
    );
  }
}

class RemoteContentCheck {
  const RemoteContentCheck({
    required this.localManifest,
    required this.remoteManifest,
    required this.contentVersionChanged,
    required this.changedFiles,
    required this.removedFiles,
    this.media = const RemoteMediaChanges.empty(),
  });

  final ContentManifest localManifest;
  final ContentManifest remoteManifest;
  final bool contentVersionChanged;
  final List<String> changedFiles;
  final List<String> removedFiles;
  final RemoteMediaChanges media;

  bool get hasRemoteChanges =>
      contentVersionChanged ||
      changedFiles.isNotEmpty ||
      removedFiles.isNotEmpty ||
      media.hasChanges;

  factory RemoteContentCheck.compare({
    required ContentManifest localManifest,
    required ContentManifest remoteManifest,
  }) {
    final changed = <String>[];
    for (final entry in remoteManifest.files.entries) {
      final local = localManifest.files[entry.key];
      if (local == null ||
          local.bytes != entry.value.bytes ||
          local.sha256 != entry.value.sha256) {
        changed.add(entry.key);
      }
    }
    changed.sort();

    final removed =
        localManifest.files.keys
            .where((fileName) => !remoteManifest.files.containsKey(fileName))
            .toList(growable: false)
          ..sort();

    return RemoteContentCheck(
      localManifest: localManifest,
      remoteManifest: remoteManifest,
      contentVersionChanged:
          localManifest.contentVersion != remoteManifest.contentVersion,
      changedFiles: changed,
      removedFiles: removed,
      media: RemoteMediaChanges.compare(
        localManifest: localManifest,
        remoteManifest: remoteManifest,
      ),
    );
  }
}

class RemoteMediaChanges {
  const RemoteMediaChanges({
    required this.changedVideoIds,
    required this.removedVideoIds,
    required this.changedAmbientTrackIds,
    required this.removedAmbientTrackIds,
  });

  const RemoteMediaChanges.empty()
    : changedVideoIds = const [],
      removedVideoIds = const [],
      changedAmbientTrackIds = const [],
      removedAmbientTrackIds = const [];

  final List<String> changedVideoIds;
  final List<String> removedVideoIds;
  final List<String> changedAmbientTrackIds;
  final List<String> removedAmbientTrackIds;

  bool get hasChanges =>
      changedVideoIds.isNotEmpty ||
      removedVideoIds.isNotEmpty ||
      changedAmbientTrackIds.isNotEmpty ||
      removedAmbientTrackIds.isNotEmpty;

  factory RemoteMediaChanges.compare({
    required ContentManifest localManifest,
    required ContentManifest remoteManifest,
  }) {
    final videoChanges = _compareMediaFileMap(
      localManifest.media.videos,
      remoteManifest.media.videos,
    );
    final audioChanges = _compareMediaFileMap(
      localManifest.media.ambientTracks,
      remoteManifest.media.ambientTracks,
    );
    return RemoteMediaChanges(
      changedVideoIds: videoChanges.changedIds,
      removedVideoIds: videoChanges.removedIds,
      changedAmbientTrackIds: audioChanges.changedIds,
      removedAmbientTrackIds: audioChanges.removedIds,
    );
  }
}

_MediaFileMapChanges _compareMediaFileMap(
  Map<String, ManifestMediaFile> local,
  Map<String, ManifestMediaFile> remote,
) {
  final changed = <String>[];
  for (final entry in remote.entries) {
    final localFile = local[entry.key];
    if (localFile == null ||
        localFile.path != entry.value.path ||
        localFile.bytes != entry.value.bytes ||
        localFile.sha256 != entry.value.sha256) {
      changed.add(entry.key);
    }
  }
  changed.sort();

  final removed =
      local.keys.where((id) => !remote.containsKey(id)).toList(growable: false)
        ..sort();

  return _MediaFileMapChanges(changedIds: changed, removedIds: removed);
}

class _MediaFileMapChanges {
  const _MediaFileMapChanges({
    required this.changedIds,
    required this.removedIds,
  });

  final List<String> changedIds;
  final List<String> removedIds;
}

Map<String, Object?> _jsonMap(Object? value) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) {
    return value.map((key, item) => MapEntry(key.toString(), item));
  }
  return const {};
}
