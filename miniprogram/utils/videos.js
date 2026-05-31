const premiumFreeAerialVideos = require('../data/premium-free-aerial-videos.js');
const {
  DEFAULT_PREMIUM_FREE_AERIAL_VIDEO_BASE,
  DEFAULT_VIDEO_LIBRARY,
  getCache,
  getFavoriteVideoKeys,
  setCache,
  videoFavoriteKey,
} = require('./storage.js');

const VIDEO_SHUFFLE_CACHE_KEY = 'video-shuffle-history-v1';
const FAVORITES_SCOPE = 'favorites';

const CATEGORY_OPTIONS = Object.freeze([
  { value: 'all', label: '全部' },
  { value: FAVORITES_SCOPE, label: '收藏' },
  { value: 'Landscapes', label: '自然景观' },
  { value: 'AnimalsAndPlants', label: '动植物' },
  { value: 'Motion', label: '运转' },
  { value: 'Underwater', label: '水下景观' },
]);

const VIDEO_LIBRARY_OPTIONS = Object.freeze([
  { value: DEFAULT_VIDEO_LIBRARY, label: '背景视频' },
]);

function normalizeBase(base) {
  return String(base || '').trim().replace(/\/$/, '');
}

function normalizeVideoLibrary() {
  return DEFAULT_VIDEO_LIBRARY;
}

function activeVideoLibrary() {
  return DEFAULT_VIDEO_LIBRARY;
}

function categoryOptionsForLibrary() {
  return CATEGORY_OPTIONS;
}

function sourceVideosForSettings() {
  return premiumFreeAerialVideos.filter((video) => video.qualityTier === 'published');
}

function sourceUrlFor(video) {
  return video.url || '';
}

function liteBaseForSettings(settings) {
  return normalizeBase(settings.premiumFreeAerialVideoBase || DEFAULT_PREMIUM_FREE_AERIAL_VIDEO_BASE);
}

function liteUrlFor(video, settings) {
  const base = liteBaseForSettings(settings);
  if (!base) return '';
  return `${base}/videos/${video.id}.mp4`;
}

function videoUrlFor(video, settings) {
  const sourceUrl = sourceUrlFor(video);
  if (settings.videoSource === 'lite') {
    return liteUrlFor(video, settings) || sourceUrl;
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
    const sourceUrl = sourceUrlFor(video);
    const liteUrl = settings.videoSource === 'lite' ? liteUrlFor(video, settings) : '';
    return {
      id: video.id,
      url: liteUrl || videoUrlFor(video, settings),
      fallbackUrl: liteUrl ? sourceUrl : '',
      poster: video.previewImage || '',
      name: video.displayName || video.name,
      originalName: video.name,
      category: video.category,
      subcategories: video.subcategories || [],
      tags: video.tags || [],
      timeOfDay: video.timeOfDay || '',
      locationName: video.locationName || '',
      locationCountry: video.locationCountry || '',
      description: video.description || '',
      videoLibrary: library,
      sourceName: video.sourceName || '',
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
  const sourceUrl = sourceUrlFor(video);
  const liteUrl = settings.videoSource === 'lite' ? liteUrlFor(video, settings) : '';
  return {
    id: video.id,
    url: liteUrl || videoUrlFor(video, settings),
    fallbackUrl: liteUrl ? sourceUrl : '',
    poster: video.previewImage || '',
    name: video.displayName || video.name,
    originalName: video.name,
    category: video.category,
    subcategories: video.subcategories || [],
    tags: video.tags || [],
    timeOfDay: video.timeOfDay || '',
    locationName: video.locationName || '',
    locationCountry: video.locationCountry || '',
    description: video.description || '',
    videoLibrary: library,
    sourceName: video.sourceName || '',
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

function shuffledItems(items, currentId) {
  const result = items.slice();
  for (let index = result.length - 1; index > 0; index -= 1) {
    const swapIndex = Math.floor(Math.random() * (index + 1));
    const current = result[index];
    result[index] = result[swapIndex];
    result[swapIndex] = current;
  }

  if (currentId && result.length > 1 && result[0].id === currentId) {
    const swapIndex = result.findIndex((item) => item.id !== currentId);
    if (swapIndex > 0) {
      const current = result[0];
      result[0] = result[swapIndex];
      result[swapIndex] = current;
    }
  }

  return result;
}

function shuffledVideoQueue(settings, currentId) {
  return shuffledItems(itemsForSettings(settings), currentId);
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

function categoryLabel(value) {
  const option = CATEGORY_OPTIONS.find((item) => item.value === value);
  return option ? option.label : CATEGORY_OPTIONS[0].label;
}

module.exports = {
  CATEGORY_OPTIONS,
  VIDEO_LIBRARY_OPTIONS,
  activeVideoLibrary,
  categoryOptionsForLibrary,
  videoById,
  pickVideo,
  shuffledVideoQueue,
  categoryLabel,
};
