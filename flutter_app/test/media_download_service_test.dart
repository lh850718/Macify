import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huxi_zen/src/content/content_repository.dart';
import 'package:huxi_zen/src/media/media_cache_index.dart';
import 'package:huxi_zen/src/media/media_download_service.dart';
import 'package:huxi_zen/src/media/media_resource_resolver.dart';
import 'package:huxi_zen/src/media/remote_file_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('huxi-download-test-');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('downloads video into cache and updates cache index', () async {
    final content = await const AssetContentRepository().load();
    final video = content.videos.firstWhere(
      (item) => item.id == 'pixabay-28707',
    );
    final client = _FakeRemoteFileClient({
      video.remoteVideoUrl(content.config.defaultVideoBase): utf8.encode('mp4'),
    });
    final service = MediaDownloadService(
      content: content,
      cacheRoot: tempDir,
      client: client,
    );

    final result = await service.downloadVideo(
      const MediaCacheIndex(),
      video,
      expectedBytes: 3,
    );

    expect(result.bytesWritten, 3);
    expect(result.resource.status, MediaResourceStatus.cached);
    expect(result.index.cachedVideoFiles[video.id], result.resource.uri);
    expect(await File(result.resource.uri).readAsString(), 'mp4');
  });

  test('downloads ambient audio into cache and updates cache index', () async {
    final content = await const AssetContentRepository().load();
    final track = content.ambientCatalog.tracks['waterfall']!;
    final audioUrl = '${content.config.defaultAmbientAudioBase}/${track.file}';
    final client = _FakeRemoteFileClient({audioUrl: utf8.encode('mp3')});
    final service = MediaDownloadService(
      content: content,
      cacheRoot: tempDir,
      client: client,
    );

    final result = await service.downloadAmbientTrack(
      const MediaCacheIndex(),
      track,
      expectedBytes: 3,
    );

    expect(result.bytesWritten, 3);
    expect(result.resource.status, MediaResourceStatus.cached);
    expect(result.index.cachedAmbientAudioFiles[track.id], result.resource.uri);
    expect(await File(result.resource.uri).readAsString(), 'mp3');
  });

  test('removes temporary file when byte validation fails', () async {
    final content = await const AssetContentRepository().load();
    final video = content.videos.firstWhere(
      (item) => item.id == 'pixabay-28707',
    );
    final client = _FakeRemoteFileClient({
      video.remoteVideoUrl(content.config.defaultVideoBase): utf8.encode('mp4'),
    });
    final service = MediaDownloadService(
      content: content,
      cacheRoot: tempDir,
      client: client,
    );

    await expectLater(
      service.downloadVideo(const MediaCacheIndex(), video, expectedBytes: 99),
      throwsA(isA<MediaDownloadException>()),
    );

    final downloadDir = Directory(
      '${tempDir.path}${Platform.pathSeparator}videos',
    );
    if (await downloadDir.exists()) {
      final leftovers = await downloadDir.list().toList();
      expect(leftovers, isEmpty);
    }
  });

  test('validates optional sha256 before moving download into cache', () async {
    final content = await const AssetContentRepository().load();
    final video = content.videos.firstWhere(
      (item) => item.id == 'pixabay-28707',
    );
    final bytes = utf8.encode('mp4');
    final client = _FakeRemoteFileClient({
      video.remoteVideoUrl(content.config.defaultVideoBase): bytes,
    });
    final service = MediaDownloadService(
      content: content,
      cacheRoot: tempDir,
      client: client,
    );

    final result = await service.downloadVideo(
      const MediaCacheIndex(),
      video,
      expectedSha256: sha256.convert(bytes).toString(),
    );

    expect(await File(result.resource.uri).readAsString(), 'mp4');
  });

  test('removes temporary file when sha256 validation fails', () async {
    final content = await const AssetContentRepository().load();
    final video = content.videos.firstWhere(
      (item) => item.id == 'pixabay-28707',
    );
    final client = _FakeRemoteFileClient({
      video.remoteVideoUrl(content.config.defaultVideoBase): utf8.encode('mp4'),
    });
    final service = MediaDownloadService(
      content: content,
      cacheRoot: tempDir,
      client: client,
    );

    await expectLater(
      service.downloadVideo(
        const MediaCacheIndex(),
        video,
        expectedSha256: 'not-a-real-hash',
      ),
      throwsA(isA<MediaDownloadException>()),
    );

    final downloadDir = Directory(
      '${tempDir.path}${Platform.pathSeparator}videos',
    );
    if (await downloadDir.exists()) {
      final leftovers = await downloadDir.list().toList();
      expect(leftovers, isEmpty);
    }
  });
}

class _FakeRemoteFileClient implements RemoteFileClient {
  const _FakeRemoteFileClient(this.bytesByUrl);

  final Map<String, List<int>> bytesByUrl;

  @override
  Future<int> download(Uri uri, File destination) async {
    final bytes = bytesByUrl[uri.toString()];
    if (bytes == null) {
      throw RemoteFileException('Missing fake bytes', uri: uri);
    }
    await destination.parent.create(recursive: true);
    await destination.writeAsBytes(bytes);
    return bytes.length;
  }

  @override
  Future<String> readString(Uri uri) async {
    final bytes = bytesByUrl[uri.toString()];
    if (bytes == null) throw RemoteFileException('Missing fake text', uri: uri);
    return utf8.decode(bytes);
  }
}
