import 'package:flutter/material.dart';

import '../../content/content_models.dart';

class LicensePage extends StatefulWidget {
  const LicensePage({super.key, required this.content});

  final ContentBundle content;

  @override
  State<LicensePage> createState() => _LicensePageState();
}

class _LicensePageState extends State<LicensePage> {
  var _openSourceExpanded = false;
  var _sourcesExpanded = false;
  String? _expandedPlatform;
  String? _expandedVideoId;

  @override
  Widget build(BuildContext context) {
    final platforms = _buildPlatformSummaries(widget.content.publishedVideos);
    return Theme(
      data: ThemeData(
        brightness: Brightness.light,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF47C7A2),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      child: Scaffold(
        backgroundColor: const Color(0xFFF4F6F8),
        appBar: AppBar(
          title: const Text('© 呼吸Zen'),
          backgroundColor: const Color(0xFFF4F6F8),
          foregroundColor: const Color(0xFF18202A),
          elevation: 0,
          scrolledUnderElevation: 0,
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
            children: [
              const Text(
                '© 呼吸Zen',
                style: TextStyle(
                  color: Color(0xFF18202A),
                  fontSize: 30,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 20),
              _LicenseSection(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        const Text('呼吸Zen 基于 ', style: _bodyStyle),
                        _InlineAction(
                          label: 'Macify',
                          onTap: _toggleOpenSource,
                        ),
                        const Text(' 改造；背景视频按 ', style: _bodyStyle),
                        _InlineAction(label: '公开素材', onTap: _toggleSources),
                        const Text(' 平台许可用于应用内背景体验。', style: _bodyStyle),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      '素材版权归原作者或相应权利人所有；呼吸Zen 不声明拥有这些素材版权，也不提供素材下载、转售或独立素材库分发。',
                      style: _quietStyle,
                    ),
                    if (_openSourceExpanded) ...[
                      const _DetailDivider(),
                      const _OpenSourcePanel(),
                    ],
                    if (_sourcesExpanded) ...[
                      const _DetailDivider(),
                      _SourcePanel(
                        platforms: platforms,
                        expandedPlatform: _expandedPlatform,
                        expandedVideoId: _expandedVideoId,
                        onTogglePlatform: _togglePlatform,
                        onToggleVideo: _toggleVideo,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _toggleOpenSource() {
    setState(() {
      _openSourceExpanded = !_openSourceExpanded;
      _sourcesExpanded = false;
      _expandedPlatform = null;
      _expandedVideoId = null;
    });
  }

  void _toggleSources() {
    setState(() {
      _sourcesExpanded = !_sourcesExpanded;
      _openSourceExpanded = false;
      _expandedPlatform = null;
      _expandedVideoId = null;
    });
  }

  void _togglePlatform(String name) {
    setState(() {
      _sourcesExpanded = true;
      _openSourceExpanded = false;
      _expandedPlatform = _expandedPlatform == name ? null : name;
      _expandedVideoId = null;
    });
  }

  void _toggleVideo(String platformName, String videoId) {
    setState(() {
      _expandedPlatform = platformName;
      _expandedVideoId = _expandedVideoId == videoId ? null : videoId;
    });
  }
}

class _LicenseSection extends StatelessWidget {
  const _LicenseSection({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE6EAF0)),
      ),
      child: child,
    );
  }
}

class _InlineAction extends StatelessWidget {
  const _InlineAction({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Text(
        label,
        style: _bodyStyle.copyWith(
          color: const Color(0xFF26313F),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _OpenSourcePanel extends StatelessWidget {
  const _OpenSourcePanel();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Macify', style: _detailTitleStyle),
        SizedBox(height: 8),
        Text(
          'MIT License · Copyright (c) 2023 Jason Ng',
          style: _detailLineStyle,
        ),
        SizedBox(height: 8),
        Text('原作者：Jason Ng, Dofy, Setilis', style: _detailLineStyle),
        SizedBox(height: 8),
        Text(
          '呼吸Zen 基于 Macify 开源项目改造为微信小程序和移动 App。公开发布版已移除 Apple Aerial 视频源，不展示或播放原项目的 Apple 视频内容。',
          style: _quietStyle,
        ),
      ],
    );
  }
}

class _SourcePanel extends StatelessWidget {
  const _SourcePanel({
    required this.platforms,
    required this.expandedPlatform,
    required this.expandedVideoId,
    required this.onTogglePlatform,
    required this.onToggleVideo,
  });

  final List<_PlatformSummary> platforms;
  final String? expandedPlatform;
  final String? expandedVideoId;
  final ValueChanged<String> onTogglePlatform;
  final void Function(String platformName, String videoId) onToggleVideo;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final platform in platforms)
          _PlatformEntry(
            platform: platform,
            expanded: expandedPlatform == platform.name,
            expandedVideoId: expandedVideoId,
            onTogglePlatform: () => onTogglePlatform(platform.name),
            onToggleVideo: (videoId) => onToggleVideo(platform.name, videoId),
          ),
      ],
    );
  }
}

class _PlatformEntry extends StatelessWidget {
  const _PlatformEntry({
    required this.platform,
    required this.expanded,
    required this.expandedVideoId,
    required this.onTogglePlatform,
    required this.onToggleVideo,
  });

  final _PlatformSummary platform;
  final bool expanded;
  final String? expandedVideoId;
  final VoidCallback onTogglePlatform;
  final ValueChanged<String> onToggleVideo;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFFEEF1F5))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onTogglePlatform,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 13),
              child: Row(
                children: [
                  Expanded(child: Text(platform.name, style: _sourceNameStyle)),
                  Text('${platform.videos.length} 条', style: _quietStyle),
                ],
              ),
            ),
          ),
          if (expanded) ...[
            Text(platform.license, style: _detailLineStyle),
            const SizedBox(height: 8),
            Text(platform.note, style: _quietStyle),
            const SizedBox(height: 12),
            for (final video in platform.videos)
              _VideoLicenseEntry(
                video: video,
                expanded: expandedVideoId == video.id,
                onToggle: () => onToggleVideo(video.id),
              ),
          ],
        ],
      ),
    );
  }
}

class _VideoLicenseEntry extends StatelessWidget {
  const _VideoLicenseEntry({
    required this.video,
    required this.expanded,
    required this.onToggle,
  });

  final VideoItem video;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final location = [
      video.locationName,
      if (video.locationCountry.isNotEmpty) video.locationCountry,
    ].where((item) => item.trim().isNotEmpty).join(' / ');
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFFF1F3F6))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(video.titleForDisplay(), style: _videoTitleStyle),
            ),
          ),
          if (expanded) ...[
            if (location.isNotEmpty)
              Text('地点：$location', style: _detailLineStyle),
            Text(
              '来源：${video.sourceName} / ${_attribution(video)}',
              style: _detailLineStyle,
            ),
            Text('许可证：${video.license}', style: _detailLineStyle),
            if (video.sourceResolution.isNotEmpty || video.duration.isNotEmpty)
              Text(
                '规格：${[video.sourceResolution, video.duration].where((item) => item.trim().isNotEmpty).join(' ')}',
                style: _detailLineStyle,
              ),
            if (video.licenseNotes.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 14),
                child: Text(video.licenseNotes, style: _quietStyle),
              )
            else
              const SizedBox(height: 14),
          ],
        ],
      ),
    );
  }
}

class _DetailDivider extends StatelessWidget {
  const _DetailDivider();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(top: 18, bottom: 16),
      child: Divider(height: 1, color: Color(0xFFEEF1F5)),
    );
  }
}

class _PlatformSummary {
  const _PlatformSummary({
    required this.name,
    required this.license,
    required this.note,
    required this.videos,
  });

  final String name;
  final String license;
  final String note;
  final List<VideoItem> videos;
}

List<_PlatformSummary> _buildPlatformSummaries(List<VideoItem> videos) {
  final grouped = <String, List<VideoItem>>{};
  for (final video in videos) {
    final sourceName = video.sourceName.trim().isEmpty
        ? '其他来源'
        : video.sourceName.trim();
    grouped.putIfAbsent(sourceName, () => []).add(video);
  }
  final names = grouped.keys.toList(growable: false)..sort();
  return [for (final name in names) _platformSummary(name, grouped[name]!)];
}

_PlatformSummary _platformSummary(String name, List<VideoItem> videos) {
  final notice = _platformNotice(name);
  final sortedVideos = [...videos]
    ..sort(
      (left, right) =>
          left.titleForDisplay().compareTo(right.titleForDisplay()),
    );
  return _PlatformSummary(
    name: name,
    license: notice.license,
    note: notice.note,
    videos: sortedVideos,
  );
}

_PlatformNotice _platformNotice(String sourceName) {
  return _sourcePlatformNotices[sourceName] ??
      const _PlatformNotice(license: '按来源页面许可', note: '具体以单条素材页面记录为准。');
}

String _attribution(VideoItem video) =>
    video.attribution.trim().isEmpty ? '无需强制署名' : video.attribution;

const _sourcePlatformNotices = {
  'Mixkit': _PlatformNotice(
    license: 'Mixkit Stock Video Free License',
    note: '部分视频可用于个人或商业项目，通常无需署名；具体以素材页面标注为准。',
  ),
  'Pexels': _PlatformNotice(
    license: 'Pexels License',
    note: '规划候选来源；新增前需逐条确认来源页面与许可记录。',
  ),
  'Pixabay': _PlatformNotice(
    license: 'Pixabay Content License',
    note: '允许按许可使用与改编，通常无需强制署名；禁止将未改动素材作为独立素材库、下载资源或转售内容分发。',
  ),
  'Dareful': _PlatformNotice(
    license: 'Dareful / source-page license',
    note: '规划候选来源；新增前需逐条确认素材页许可与署名要求。',
  ),
  'Coverr': _PlatformNotice(
    license: 'Coverr License',
    note: '规划候选来源；新增前需逐条确认素材页许可与署名要求。',
  ),
};

class _PlatformNotice {
  const _PlatformNotice({required this.license, required this.note});

  final String license;
  final String note;
}

const _bodyStyle = TextStyle(
  color: Color(0xFF344154),
  fontSize: 15,
  height: 1.62,
);

const _quietStyle = TextStyle(
  color: Color(0xFF8B95A3),
  fontSize: 13,
  height: 1.5,
);

const _detailTitleStyle = TextStyle(
  color: Color(0xFF26313F),
  fontSize: 16,
  fontWeight: FontWeight.w600,
  height: 1.35,
);

const _detailLineStyle = TextStyle(
  color: Color(0xFF5F6B79),
  fontSize: 13,
  height: 1.42,
);

const _sourceNameStyle = TextStyle(
  color: Color(0xFF26313F),
  fontSize: 15,
  fontWeight: FontWeight.w600,
  height: 1.35,
);

const _videoTitleStyle = TextStyle(
  color: Color(0xFF344154),
  fontSize: 14,
  fontWeight: FontWeight.w500,
  height: 1.4,
);
