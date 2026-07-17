import 'package:flutter/material.dart';

import 'src/app.dart';
import 'src/content/remote_content_sync.dart';
import 'src/media/remote_file_client.dart';

const _productionRemoteManifestUrl =
    'https://macify-videos-1430886267.cos.ap-beijing.myqcloud.com/'
    'macify-premium/content/content-manifest.json';

void main() {
  final remoteClient = HttpRemoteFileClient();
  runApp(
    HuxiZenApp(
      contentSyncService: RemoteContentSyncService(client: remoteClient),
      remoteManifestUri: Uri.parse(_productionRemoteManifestUrl),
      mediaDownloadClient: remoteClient,
    ),
  );
}
