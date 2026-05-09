const videos = require('../data/videos.js');

const APPLE_HOST = 'https://sylvan.apple.com';

const CATEGORY_OPTIONS = Object.freeze([
  { value: 'all', label: '全部' },
  { value: 'Landscapes', label: '自然景观' },
  { value: 'Cities', label: '城市景观' },
  { value: 'Underwater', label: '水下景观' },
  { value: 'Space', label: '地球' },
  { value: 'Mac', label: 'Mac' },
]);

// WeChat Mini Program playback is much less forgiving than desktop Chrome.
// Keep the default Apple pool to videos that are still Apple-hosted but are
// comparatively small in Apple's catalog (<= ~200MB by HEAD Content-Length).
const STABLE_APPLE_VIDEO_IDS = new Set([
  'C42AADA1-9110-472A-BF86-B1EF306DA846',
  'D8C8FC8B-9D11-4803-944F-DF284B35FE58',
  'DD7690D7-1B94-4FAA-910C-993C182B6874',
  '94383DC9-59D3-43EC-9E8E-A783DA633E06',
  'F439B0A7-D18C-4B14-9681-6520E6A74FE9',
  '6324F6EB-E0F1-468F-AC2E-A983EBDDD53B',
  '8C31B06F-91A4-4F7C-93ED-56146D7F48B9',
  '03EC0F5E-CCA8-4E0A-9FEC-5BD1CE151182',
  '149E7795-DBDA-4F5D-B39A-14712F841118',
  'E5DB138A-F04E-4619-B896-DE5CB538C534',
  '12318CCB-3F78-43B7-A854-EFDCCE5312CD',
  '1088217C-1410-4CF7-BDE9-8F573A4DBCD9',
  'AFA22C08-A486-4CE8-9A13-E355B6C38559',
  '537A4DAB-83B0-4B66-BCD1-05E5DBB4A268',
  '35693AEA-F8C4-4A80-B77D-C94B20A68956',
]);

function normalizeProxyBase(proxyBase) {
  return String(proxyBase || '').trim().replace(/\/$/, '');
}

function normalizeBase(base) {
  return String(base || '').trim().replace(/\/$/, '');
}

function applyProxy(url, settings) {
  const proxyBase = normalizeProxyBase(settings.proxyBase);
  if (settings.reverseProxy && proxyBase) {
    return url.replace(APPLE_HOST, proxyBase);
  }
  return url;
}

function liteUrlFor(video, settings) {
  const base = normalizeBase(settings.liteVideoBase);
  if (!base) return '';
  return `${base}/videos/${video.id}.mp4`;
}

function videoUrlFor(video, settings) {
  if (settings.videoSource === 'lite') {
    return liteUrlFor(video, settings) || applyProxy(video.url, settings);
  }
  return applyProxy(video.url, settings);
}

function itemsForSettings(settings) {
  const scope = settings.shuffleScope || 'all';
  const scoped =
    scope === 'all' ? videos : videos.filter((video) => video.category === scope);
  const stableApple =
    settings.videoSource === 'lite'
      ? scoped
      : scoped.filter((video) => STABLE_APPLE_VIDEO_IDS.has(video.id));
  const filtered = stableApple.length > 0 ? stableApple : scoped;

  return filtered.map((video) => ({
    id: video.id,
    url: videoUrlFor(video, settings),
    poster: applyProxy(video.previewImage, settings),
    name: video.name,
    category: video.category,
    subcategories: video.subcategories || [],
    timeOfDay: video.timeOfDay || '',
  }));
}

function pickVideo(settings, currentId) {
  const items = itemsForSettings(settings);
  if (!items.length) return null;
  if (items.length === 1) return items[0];

  let picked = items[Math.floor(Math.random() * items.length)];
  while (picked.id === currentId) {
    picked = items[Math.floor(Math.random() * items.length)];
  }
  return picked;
}

function categoryLabel(value) {
  const option = CATEGORY_OPTIONS.find((item) => item.value === value);
  return option ? option.label : CATEGORY_OPTIONS[0].label;
}

module.exports = {
  CATEGORY_OPTIONS,
  pickVideo,
  categoryLabel,
};
