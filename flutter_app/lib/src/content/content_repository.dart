import 'dart:convert';

import 'package:flutter/services.dart';

import 'content_models.dart';

abstract class ContentRepository {
  Future<ContentBundle> load();
}

class AssetContentRepository implements ContentRepository {
  const AssetContentRepository({this.assetRoot = 'assets/content'});

  final String assetRoot;

  @override
  Future<ContentBundle> load() async {
    final manifest = ContentManifest.fromJson(
      await _loadMap('content-manifest.json'),
    );
    final config = ContentConfig.fromJson(await _loadMap('config.json'));
    final videos = (await _loadList('videos.json'))
        .map((item) => VideoItem.fromJson(_jsonMap(item)))
        .toList(growable: false);
    final ambientCatalog = AmbientCatalog.fromJson(
      await _loadMap('ambient-tracks.json'),
    );
    final ambientRules = (await _loadList('ambient-rules.json'))
        .map((item) => AmbientRule.fromJson(_jsonMap(item)))
        .toList(growable: false);
    final mixes = (await _loadList('video-audio-mixes.json'))
        .map((item) => VideoAudioMix.fromJson(_jsonMap(item)))
        .where((item) => item.videoId.isNotEmpty)
        .toList(growable: false);

    return ContentBundle(
      manifest: manifest,
      config: config,
      videos: videos,
      ambientCatalog: ambientCatalog,
      ambientRules: ambientRules,
      videoAudioMixes: mixes,
    );
  }

  Future<JsonMap> _loadMap(String fileName) async {
    final raw = await rootBundle.loadString('$assetRoot/$fileName');
    final decoded = jsonDecode(raw);
    return _jsonMap(decoded);
  }

  Future<List<Object?>> _loadList(String fileName) async {
    final raw = await rootBundle.loadString('$assetRoot/$fileName');
    final decoded = jsonDecode(raw);
    return decoded is List ? decoded.cast<Object?>() : const [];
  }
}

JsonMap _jsonMap(Object? value) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) {
    return value.map((key, item) => MapEntry(key.toString(), item));
  }
  return const {};
}
