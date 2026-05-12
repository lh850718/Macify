const apple1080Videos = require('../data/apple-aerial-1080.js');
const premiumFreeAerialVideos = require('../data/premium-free-aerial-videos.js');
const {
  DEFAULT_LITE_VIDEO_BASE,
  DEFAULT_PREMIUM_FREE_AERIAL_VIDEO_BASE,
  DEFAULT_VIDEO_LIBRARY,
  getCache,
  getFavoriteVideoKeys,
  setCache,
  videoFavoriteKey,
} = require('./storage.js');

const APPLE_HOST = 'https://sylvan.apple.com';
const VIDEO_SHUFFLE_CACHE_KEY = 'video-shuffle-history-v1';
const FAVORITES_SCOPE = 'favorites';

const APPLE_CATEGORY_OPTIONS = Object.freeze([
  { value: 'all', label: '全部' },
  { value: FAVORITES_SCOPE, label: '收藏' },
  { value: 'Landscapes', label: '自然景观' },
  { value: 'Cities', label: '城市景观' },
  { value: 'Underwater', label: '水下景观' },
  { value: 'Space', label: '太空' },
]);
const PREMIUM_CATEGORY_OPTIONS = Object.freeze([
  { value: 'all', label: '全部' },
  { value: FAVORITES_SCOPE, label: '收藏' },
  { value: 'Landscapes', label: '自然景观' },
  { value: 'Cities', label: '城市景观' },
  { value: 'AnimalsAndPlants', label: '动植物' },
  { value: 'Motion', label: '运转' },
  { value: 'Underwater', label: '水下景观' },
]);
const CATEGORY_OPTIONS = APPLE_CATEGORY_OPTIONS;

const VIDEO_LIBRARY_OPTIONS = Object.freeze([
  { value: 'apple', label: 'Apple 轻量航拍' },
  { value: 'premiumFreeAerial', label: '高端免费航拍' },
]);

function normalizeProxyBase(proxyBase) {
  return String(proxyBase || '').trim().replace(/\/$/, '');
}

function normalizeBase(base) {
  return String(base || '').trim().replace(/\/$/, '');
}

function normalizeVideoLibrary(value) {
  if (value === 'premiumFreeAerial') {
    return 'premiumFreeAerial';
  }
  return DEFAULT_VIDEO_LIBRARY;
}

function activeVideoLibrary(settings) {
  if (!settings || settings.videoSource !== 'lite') {
    return DEFAULT_VIDEO_LIBRARY;
  }
  return normalizeVideoLibrary(settings.videoLibrary);
}

function categoryOptionsForLibrary(library) {
  return normalizeVideoLibrary(library) === 'premiumFreeAerial'
    ? PREMIUM_CATEGORY_OPTIONS
    : APPLE_CATEGORY_OPTIONS;
}

function sourceVideosForSettings(settings) {
  if (activeVideoLibrary(settings) === 'premiumFreeAerial') {
    return premiumFreeAerialVideos.filter((video) => video.qualityTier === 'published');
  }
  return apple1080Videos;
}

function sourceUrlFor(video, settings, library) {
  const url = video.url || '';
  return library === 'apple' ? applyProxy(url, settings) : url;
}

function applyProxy(url, settings) {
  const proxyBase = normalizeProxyBase(settings.proxyBase);
  if (settings.reverseProxy && proxyBase) {
    return url.replace(APPLE_HOST, proxyBase);
  }
  return url;
}

function liteBaseForSettings(settings, library) {
  if (library === 'premiumFreeAerial') {
    return normalizeBase(settings.premiumFreeAerialVideoBase || DEFAULT_PREMIUM_FREE_AERIAL_VIDEO_BASE);
  }
  return normalizeBase(settings.liteVideoBase || DEFAULT_LITE_VIDEO_BASE);
}

function liteUrlFor(video, settings, library) {
  const base = liteBaseForSettings(settings, library);
  if (!base) return '';
  return `${base}/videos/${video.id}.mp4`;
}

function videoUrlFor(video, settings, library) {
  const sourceUrl = sourceUrlFor(video, settings, library);
  if (settings.videoSource === 'lite') {
    return liteUrlFor(video, settings, library) || sourceUrl;
  }
  return sourceUrl;
}

function itemsForSettings(settings) {
  const scope = settings.shuffleScope || 'all';
  const library = activeVideoLibrary(settings);
  const sourceVideos = sourceVideosForSettings(settings);
  let filtered = sourceVideos;

  if (scope === FAVORITES_SCOPE) {
    const favorites = getFavoriteVideoKeys();
    filtered = sourceVideos.filter((video) => favorites.includes(videoFavoriteKey({ ...video, videoLibrary: library })));
  } else if (scope !== 'all') {
    const scoped = sourceVideos.filter((video) => video.category === scope);
    filtered = scoped.length > 0 ? scoped : sourceVideos;
  }

  return filtered.map((video) => {
    const sourceUrl = sourceUrlFor(video, settings, library);
    const liteUrl = settings.videoSource === 'lite' ? liteUrlFor(video, settings, library) : '';
    return {
      id: video.id,
      url: liteUrl || videoUrlFor(video, settings, library),
      fallbackUrl: liteUrl ? sourceUrl : '',
      poster: library === 'apple' ? applyProxy(video.previewImage, settings) : video.previewImage || '',
      name: video.displayName || video.name,
      originalName: video.name,
      category: video.category,
      subcategories: video.subcategories || [],
      timeOfDay: video.timeOfDay || '',
      locationName: video.locationName || '',
      locationCountry: video.locationCountry || '',
      description: video.description || '',
      videoLibrary: library,
      sourceName: video.sourceName || (library === 'apple' ? 'Apple' : ''),
      sourcePage: video.sourcePage || '',
      license: video.license || '',
      attribution: video.attribution || '',
      favoriteKey: videoFavoriteKey({ ...video, videoLibrary: library }),
    };
  });
}

function videoById(settings, id) {
  const sourceVideos = sourceVideosForSettings(settings);
  const video = sourceVideos.find((item) => item.id === id);
  if (!video) return null;
  const library = activeVideoLibrary(settings);
  if (
    settings.shuffleScope === FAVORITES_SCOPE
    && !getFavoriteVideoKeys().includes(videoFavoriteKey({ ...video, videoLibrary: library }))
  ) {
    return null;
  }
  const sourceUrl = sourceUrlFor(video, settings, library);
  const liteUrl = settings.videoSource === 'lite' ? liteUrlFor(video, settings, library) : '';
  return {
    id: video.id,
    url: liteUrl || videoUrlFor(video, settings, library),
    fallbackUrl: liteUrl ? sourceUrl : '',
    poster: library === 'apple' ? applyProxy(video.previewImage, settings) : video.previewImage || '',
    name: video.displayName || video.name,
    originalName: video.name,
    category: video.category,
    subcategories: video.subcategories || [],
    timeOfDay: video.timeOfDay || '',
    locationName: video.locationName || '',
    locationCountry: video.locationCountry || '',
    description: video.description || '',
    videoLibrary: library,
    sourceName: video.sourceName || (library === 'apple' ? 'Apple' : ''),
    sourcePage: video.sourcePage || '',
    license: video.license || '',
    attribution: video.attribution || '',
    favoriteKey: videoFavoriteKey({ ...video, videoLibrary: library }),
  };
}

function shuffleContextKey(settings) {
  const library = activeVideoLibrary(settings);
  const scope = settings.shuffleScope || 'all';
  const source = settings.videoSource || 'lite';
  return `${source}|${library}|${scope}`;
}

function shuffleHistoryFor(settings, items) {
  const cache = getCache(VIDEO_SHUFFLE_CACHE_KEY) || {};
  const key = shuffleContextKey(settings);
  const itemIds = items.map((item) => item.id);
  const knownIds = new Set(itemIds);
  const raw = Array.isArray(cache[key]) ? cache[key] : [];
  const history = raw.filter((id) => knownIds.has(id));
  return {
    cache,
    key,
    history,
    itemIds,
  };
}

function saveShuffleHistory(cache, key, history) {
  cache[key] = history;
  setCache(VIDEO_SHUFFLE_CACHE_KEY, cache);
}

function recordPickedVideo(settings, items, picked) {
  if (!picked || !picked.id || !items.length) return;
  const { cache, key, history, itemIds } = shuffleHistoryFor(settings, items);
  const nextHistory = history.filter((id) => id !== picked.id);
  nextHistory.push(picked.id);
  saveShuffleHistory(cache, key, nextHistory.slice(-itemIds.length));
}

function pickVideo(settings, currentId) {
  const items = itemsForSettings(settings);
  if (!items.length) return null;
  if (items.length === 1) {
    recordPickedVideo(settings, items, items[0]);
    return items[0];
  }

  const { cache, key, history, itemIds } = shuffleHistoryFor(settings, items);
  let seen = history;
  let pool = items.filter((item) => item.id !== currentId && !seen.includes(item.id));

  if (!pool.length) {
    seen = currentId ? [currentId] : [];
    pool = items.filter((item) => item.id !== currentId);
  }

  if (!pool.length) {
    pool = items;
  }

  const picked = pool[Math.floor(Math.random() * pool.length)];
  const nextHistory = seen.filter((id) => id !== picked.id);
  nextHistory.push(picked.id);
  saveShuffleHistory(cache, key, nextHistory.slice(-itemIds.length));
  return picked;
}

function categoryLabel(value, library = DEFAULT_VIDEO_LIBRARY) {
  const options = categoryOptionsForLibrary(library);
  const option = options.find((item) => item.value === value);
  return option ? option.label : options[0].label;
}

module.exports = {
  CATEGORY_OPTIONS,
  VIDEO_LIBRARY_OPTIONS,
  activeVideoLibrary,
  categoryOptionsForLibrary,
  videoById,
  pickVideo,
  categoryLabel,
};
