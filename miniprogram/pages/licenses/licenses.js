const premiumFreeAerialVideos = require('../../data/premium-free-aerial-videos.js');

const SOURCE_PLATFORMS = Object.freeze([
  {
    name: 'Mixkit',
    license: 'Mixkit Stock Video Free License',
    note: '部分视频可用于个人或商业项目，通常无需署名；具体以素材页面标注为准。',
  },
  {
    name: 'Pexels',
    license: 'Pexels License',
    note: '规划候选来源；新增前需逐条确认来源页面与许可记录。',
  },
  {
    name: 'Pixabay',
    license: 'Pixabay Content License',
    note: '允许按许可使用与改编，通常无需强制署名；禁止将未改动素材作为独立素材库、下载资源或转售内容分发。',
  },
  {
    name: 'Dareful',
    license: 'Dareful / source-page license',
    note: '规划候选来源；新增前需逐条确认素材页许可与署名要求。',
  },
  {
    name: 'Coverr',
    license: 'Coverr License',
    note: '规划候选来源；新增前需逐条确认素材页许可与署名要求。',
  },
]);
const OPEN_SOURCE_NOTICES = Object.freeze([
  {
    name: 'Macify',
    license: 'MIT License',
    copyright: 'Copyright (c) 2023 Jason Ng',
    authors: 'Jason Ng, Dofy, Setilis',
    note: '呼吸Zen 基于 Macify 开源项目改造为微信小程序。公开发布版已移除 Apple Aerial 视频源，不展示或播放原项目的 Apple 视频内容。',
  },
]);

function currentLicenseItems() {
  return premiumFreeAerialVideos
    .filter((video) => video.qualityTier === 'published')
    .map((video) => ({
      id: video.id,
      title: video.displayName || video.name,
      sourceName: video.sourceName || '',
      attribution: video.attribution || '无需强制署名',
      license: video.license || '',
      licenseNotes: video.licenseNotes || '',
      sourceResolution: video.sourceResolution || '',
      duration: video.duration || '',
      location: [video.locationName, video.locationCountry].filter(Boolean).join(' / '),
      expanded: false,
    }));
}

function platformNotice(sourceName) {
  return SOURCE_PLATFORMS.find((platform) => platform.name === sourceName) || {
    name: sourceName,
    license: '按来源页面许可',
    note: '具体以单条素材页面记录为准。',
  };
}

function withSummarySeparators(platforms) {
  return platforms.map((platform, index) => ({
    ...platform,
    summarySeparator: index === platforms.length - 1 ? '' : '、',
  }));
}

function buildPlatformSummaries(licenseItems) {
  const grouped = licenseItems.reduce((result, item) => {
    const sourceName = item.sourceName || '其他来源';
    if (!result.has(sourceName)) {
      result.set(sourceName, []);
    }
    result.get(sourceName).push(item);
    return result;
  }, new Map());

  return withSummarySeparators(Array.from(grouped.entries()).map(([sourceName, videos]) => {
    const notice = platformNotice(sourceName);
    return {
      name: sourceName,
      license: notice.license,
      note: notice.note,
      videoCount: videos.length,
      videos,
      expanded: false,
    };
  }));
}

function collapsedPlatforms(platforms) {
  return withSummarySeparators(platforms.map((platform) => ({
    ...platform,
    expanded: false,
    videos: platform.videos.map((video) => ({
      ...video,
      expanded: false,
    })),
  })));
}

Page({
  data: {
    openSourceNotice: OPEN_SOURCE_NOTICES[0],
    isOpenSourceExpanded: false,
    isSourcesExpanded: false,
    platformSummaries: [],
  },

  onLoad() {
    const licenseItems = currentLicenseItems();
    this.setData({
      platformSummaries: buildPlatformSummaries(licenseItems),
    });
  },

  toggleOpenSource() {
    this.setData({
      isOpenSourceExpanded: !this.data.isOpenSourceExpanded,
      isSourcesExpanded: false,
      platformSummaries: collapsedPlatforms(this.data.platformSummaries),
    });
  },

  toggleSources() {
    this.setData({
      isOpenSourceExpanded: false,
      isSourcesExpanded: !this.data.isSourcesExpanded,
      platformSummaries: collapsedPlatforms(this.data.platformSummaries),
    });
  },

  togglePlatform(event) {
    const name = event.currentTarget.dataset.name;
    const platformSummaries = withSummarySeparators(this.data.platformSummaries.map((platform) => {
      const shouldExpand = platform.name === name ? !platform.expanded : false;
      return {
        ...platform,
        expanded: shouldExpand,
        videos: platform.videos.map((video) => ({
          ...video,
          expanded: false,
        })),
      };
    }));

    this.setData({
      isOpenSourceExpanded: false,
      isSourcesExpanded: true,
      platformSummaries,
    });
  },

  toggleVideo(event) {
    const platformName = event.currentTarget.dataset.platform;
    const videoId = event.currentTarget.dataset.id;
    const platformSummaries = withSummarySeparators(this.data.platformSummaries.map((platform) => {
      if (platform.name !== platformName) {
        return platform;
      }

      return {
        ...platform,
        videos: platform.videos.map((video) => ({
          ...video,
          expanded: video.id === videoId ? !video.expanded : false,
        })),
      };
    }));

    this.setData({
      platformSummaries,
    });
  },
});
