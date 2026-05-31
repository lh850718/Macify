import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../content/content_models.dart';
import 'media_resource_resolver.dart';

const defaultBundledMediaManifestAsset = 'assets/media/bundled-media.json';

Future<MediaResourceCatalog> loadBundledMediaCatalog(
  ContentBundle content, {
  AssetBundle? bundle,
  String assetPath = defaultBundledMediaManifestAsset,
}) async {
  final assetBundle = bundle ?? rootBundle;
  late final Object? decoded;
  try {
    decoded = jsonDecode(await assetBundle.loadString(assetPath));
  } on FlutterError {
    return const MediaResourceCatalog.empty();
  } on FormatException {
    return const MediaResourceCatalog.empty();
  }

  final json = _jsonMap(decoded);
  final knownVideoIds = content.videos.map((video) => video.id).toSet();
  final knownAmbientTrackIds = content.ambientCatalog.tracks.keys.toSet();

  return MediaResourceCatalog(
    bundledVideoAssets: _assetMap(
      json['videos'],
      allowedIds: knownVideoIds,
      requiredPrefix: 'assets/media/videos/',
    ),
    bundledAmbientAudioAssets: _assetMap(
      json['ambientTracks'],
      allowedIds: knownAmbientTrackIds,
      requiredPrefix: 'assets/media/audio/',
    ),
  );
}

Map<String, Object?> _jsonMap(Object? value) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) {
    return value.map((key, item) => MapEntry(key.toString(), item));
  }
  return const {};
}

Map<String, String> _assetMap(
  Object? value, {
  required Set<String> allowedIds,
  required String requiredPrefix,
}) {
  if (value is! Map) return const {};

  final assets = <String, String>{};
  for (final entry in value.entries) {
    final id = entry.key.toString().trim();
    final asset = entry.value?.toString().trim() ?? '';
    if (id.isEmpty ||
        asset.isEmpty ||
        !allowedIds.contains(id) ||
        !asset.startsWith(requiredPrefix)) {
      continue;
    }
    assets[id] = asset;
  }
  return assets;
}
