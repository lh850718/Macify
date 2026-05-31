import 'dart:io';

import 'package:flutter/material.dart';

import 'content/content_repository.dart';
import 'content/remote_content_sync.dart';
import 'features/home/zen_home_page.dart';
import 'media/media_resource_resolver.dart';
import 'media/remote_file_client.dart';

class HuxiZenApp extends StatelessWidget {
  const HuxiZenApp({
    super.key,
    ContentRepository? repository,
    this.loadRemoteImages = true,
    this.contentSyncService,
    this.remoteManifestUri,
    this.onRemoteContentCheck,
    this.enableMediaDownloads = true,
    this.mediaCacheRoot,
    this.mediaDownloadClient,
    this.bundledMediaCatalog,
  }) : repository = repository ?? const AssetContentRepository();

  final ContentRepository repository;
  final bool loadRemoteImages;
  final ContentSyncService? contentSyncService;
  final Uri? remoteManifestUri;
  final ValueChanged<RemoteContentCheck>? onRemoteContentCheck;
  final bool enableMediaDownloads;
  final Directory? mediaCacheRoot;
  final RemoteFileClient? mediaDownloadClient;
  final MediaResourceCatalog? bundledMediaCatalog;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '呼吸Zen',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF47C7A2),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: Colors.black,
        useMaterial3: true,
      ),
      home: ZenHomePage(
        repository: repository,
        loadRemoteImages: loadRemoteImages,
        contentSyncService: contentSyncService,
        remoteManifestUri: remoteManifestUri,
        onRemoteContentCheck: onRemoteContentCheck,
        enableMediaDownloads: enableMediaDownloads,
        mediaCacheRoot: mediaCacheRoot,
        mediaDownloadClient: mediaDownloadClient,
        bundledMediaCatalog: bundledMediaCatalog,
      ),
    );
  }
}
