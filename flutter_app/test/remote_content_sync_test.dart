import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:huxi_zen/src/content/content_models.dart';
import 'package:huxi_zen/src/content/remote_content_sync.dart';
import 'package:huxi_zen/src/media/remote_file_client.dart';

void main() {
  test('detects remote manifest version and file changes', () async {
    const localManifest = ContentManifest(
      schemaVersion: 1,
      contentVersion: 'local',
      defaultVideoLibrary: 'premiumFreeAerial',
      files: {
        'videos.json': ManifestFile(bytes: 10, sha256: 'old'),
        'config.json': ManifestFile(bytes: 1, sha256: 'same'),
        'removed.json': ManifestFile(bytes: 2, sha256: 'gone'),
      },
      media: ContentMediaManifest(
        videos: {
          'video-a': ManifestMediaFile(
            path: 'videos/video-a.mp4',
            bytes: 10,
            sha256: 'old-video',
          ),
          'video-removed': ManifestMediaFile(
            path: 'videos/video-removed.mp4',
            bytes: 12,
            sha256: 'removed-video',
          ),
        },
        ambientTracks: {
          'rain': ManifestMediaFile(
            path: 'rain.mp3',
            bytes: 20,
            sha256: 'same-rain',
          ),
          'fire': ManifestMediaFile(
            path: 'fire.mp3',
            bytes: 22,
            sha256: 'old-fire',
          ),
        },
      ),
    );
    final remoteManifest = jsonEncode({
      'schemaVersion': 1,
      'contentVersion': 'remote',
      'defaultVideoLibrary': 'premiumFreeAerial',
      'files': {
        'videos.json': {'bytes': 11, 'sha256': 'new'},
        'config.json': {'bytes': 1, 'sha256': 'same'},
        'ambient-tracks.json': {'bytes': 3, 'sha256': 'added'},
      },
      'media': {
        'videos': {
          'video-a': {
            'path': 'videos/video-a.mp4',
            'bytes': 11,
            'sha256': 'new-video',
          },
          'video-added': {
            'path': 'videos/video-added.mp4',
            'bytes': 13,
            'sha256': 'added-video',
          },
        },
        'ambientTracks': {
          'rain': {'path': 'rain.mp3', 'bytes': 20, 'sha256': 'same-rain'},
          'fire': {'path': 'fire.mp3', 'bytes': 23, 'sha256': 'new-fire'},
        },
      },
    });
    final service = RemoteContentSyncService(
      client: _FakeRemoteFileClient({
        'https://example.com/content-manifest.json': remoteManifest,
      }),
    );

    final result = await service.checkManifest(
      localManifest: localManifest,
      remoteManifestUri: Uri.parse('https://example.com/content-manifest.json'),
    );

    expect(result.hasRemoteChanges, isTrue);
    expect(result.contentVersionChanged, isTrue);
    expect(result.changedFiles, ['ambient-tracks.json', 'videos.json']);
    expect(result.removedFiles, ['removed.json']);
    expect(result.media.changedVideoIds, ['video-a', 'video-added']);
    expect(result.media.removedVideoIds, ['video-removed']);
    expect(result.media.changedAmbientTrackIds, ['fire']);
    expect(result.media.removedAmbientTrackIds, isEmpty);
  });

  test('reports no changes for identical manifest', () {
    const manifest = ContentManifest(
      schemaVersion: 1,
      contentVersion: 'same',
      defaultVideoLibrary: 'premiumFreeAerial',
      files: {'config.json': ManifestFile(bytes: 1, sha256: 'hash')},
    );

    final result = RemoteContentCheck.compare(
      localManifest: manifest,
      remoteManifest: manifest,
    );

    expect(result.hasRemoteChanges, isFalse);
    expect(result.changedFiles, isEmpty);
    expect(result.removedFiles, isEmpty);
  });
}

class _FakeRemoteFileClient implements RemoteFileClient {
  const _FakeRemoteFileClient(this.textByUrl);

  final Map<String, String> textByUrl;

  @override
  Future<int> download(Uri uri, File destination) {
    throw UnimplementedError();
  }

  @override
  Future<String> readString(Uri uri) async {
    final text = textByUrl[uri.toString()];
    if (text == null) throw RemoteFileException('Missing fake text', uri: uri);
    return text;
  }
}
