import 'dart:io';

import 'package:crypto/crypto.dart';

import '../content/content_models.dart';
import 'media_cache_index.dart';
import 'media_resource_resolver.dart';
import 'remote_file_client.dart';

class MediaDownloadService {
  const MediaDownloadService({
    required this.content,
    required this.cacheRoot,
    required this.client,
  });

  final ContentBundle content;
  final Directory cacheRoot;
  final RemoteFileClient client;

  Future<MediaDownloadResult> downloadVideo(
    MediaCacheIndex index,
    VideoItem video, {
    int? expectedBytes,
    String? expectedSha256,
  }) async {
    final remoteUri = Uri.parse(
      video.remoteVideoUrl(content.config.defaultVideoBase),
    );
    final target = File(
      _join(cacheRoot.path, 'videos', '${_safeFileName(video.id)}.mp4'),
    );
    final bytesWritten = await _downloadAtomically(
      remoteUri,
      target,
      expectedBytes: expectedBytes,
      expectedSha256: expectedSha256,
    );
    final nextIndex = index.withCachedVideo(video.id, target.path);
    return MediaDownloadResult(
      index: nextIndex,
      resource: MediaResource(
        kind: MediaResourceKind.video,
        id: video.id,
        status: MediaResourceStatus.cached,
        uri: target.path,
      ),
      bytesWritten: bytesWritten,
    );
  }

  Future<MediaDownloadResult> downloadAmbientTrack(
    MediaCacheIndex index,
    AmbientTrack track, {
    int? expectedBytes,
    String? expectedSha256,
  }) async {
    final audioBase = _normalizeBase(content.config.defaultAmbientAudioBase);
    if (audioBase.isEmpty) {
      throw const MediaDownloadException('Ambient audio base URL is empty');
    }

    final remoteUri = Uri.parse('$audioBase/${track.file}');
    final target = File(
      _join(cacheRoot.path, 'audio', _safeFileName(track.file)),
    );
    final bytesWritten = await _downloadAtomically(
      remoteUri,
      target,
      expectedBytes: expectedBytes,
      expectedSha256: expectedSha256,
    );
    final nextIndex = index.withCachedAmbientTrack(track.id, target.path);
    return MediaDownloadResult(
      index: nextIndex,
      resource: MediaResource(
        kind: MediaResourceKind.ambientAudio,
        id: track.id,
        status: MediaResourceStatus.cached,
        uri: target.path,
      ),
      bytesWritten: bytesWritten,
    );
  }

  Future<int> _downloadAtomically(
    Uri remoteUri,
    File target, {
    int? expectedBytes,
    String? expectedSha256,
  }) async {
    await target.parent.create(recursive: true);
    final temp = File('${target.path}.download');
    if (await temp.exists()) await temp.delete();

    try {
      final bytesWritten = await client.download(remoteUri, temp);
      if (expectedBytes != null && bytesWritten != expectedBytes) {
        throw MediaDownloadException(
          'Downloaded $bytesWritten bytes, expected $expectedBytes',
        );
      }
      final expectedHash = expectedSha256?.trim().toLowerCase();
      if (expectedHash != null && expectedHash.isNotEmpty) {
        final actualHash = await _sha256File(temp);
        if (actualHash != expectedHash) {
          throw MediaDownloadException(
            'Downloaded sha256 $actualHash, expected $expectedHash',
          );
        }
      }
      if (await target.exists()) await target.delete();
      await temp.rename(target.path);
      return bytesWritten;
    } catch (_) {
      if (await temp.exists()) await temp.delete();
      rethrow;
    }
  }
}

Future<String> _sha256File(File file) async {
  final digest = await sha256.bind(file.openRead()).first;
  return digest.toString();
}

class MediaDownloadResult {
  const MediaDownloadResult({
    required this.index,
    required this.resource,
    required this.bytesWritten,
  });

  final MediaCacheIndex index;
  final MediaResource resource;
  final int bytesWritten;
}

class MediaDownloadException implements Exception {
  const MediaDownloadException(this.message);

  final String message;

  @override
  String toString() => 'MediaDownloadException: $message';
}

String _join(String first, String second, [String? third]) {
  final separator = Platform.pathSeparator;
  final parts = [first.replaceFirst(RegExp(r'[/\\]$'), ''), second, ?third];
  return parts.join(separator);
}

String _safeFileName(String value) {
  return value.trim().replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
}

String _normalizeBase(String value) =>
    value.trim().replaceFirst(RegExp(r'/$'), '');
