import 'dart:convert';
import 'dart:io';

abstract class RemoteFileClient {
  Future<String> readString(Uri uri);

  Future<int> download(Uri uri, File destination);
}

class HttpRemoteFileClient implements RemoteFileClient {
  HttpRemoteFileClient({HttpClient? httpClient})
    : _httpClient = httpClient ?? HttpClient();

  final HttpClient _httpClient;

  @override
  Future<String> readString(Uri uri) async {
    final request = await _httpClient.getUrl(uri);
    final response = await request.close();
    _throwIfUnsuccessful(uri, response.statusCode);
    return response.transform(utf8.decoder).join();
  }

  @override
  Future<int> download(Uri uri, File destination) async {
    final request = await _httpClient.getUrl(uri);
    final response = await request.close();
    _throwIfUnsuccessful(uri, response.statusCode);

    await destination.parent.create(recursive: true);
    final sink = destination.openWrite();
    var bytesWritten = 0;
    try {
      await for (final chunk in response) {
        bytesWritten += chunk.length;
        sink.add(chunk);
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
    return bytesWritten;
  }

  void close({bool force = false}) {
    _httpClient.close(force: force);
  }

  void _throwIfUnsuccessful(Uri uri, int statusCode) {
    if (statusCode < 200 || statusCode >= 300) {
      throw RemoteFileException(
        'Request failed with HTTP $statusCode',
        uri: uri,
        statusCode: statusCode,
      );
    }
  }
}

class RemoteFileException implements Exception {
  const RemoteFileException(this.message, {this.uri, this.statusCode});

  final String message;
  final Uri? uri;
  final int? statusCode;

  @override
  String toString() {
    final parts = [
      'RemoteFileException: $message',
      if (statusCode != null) 'status=$statusCode',
      if (uri != null) 'uri=$uri',
    ];
    return parts.join(' ');
  }
}
