const SETTINGS_KEY = 'macify.settings.v1';
const CACHE_PREFIX = 'macify.cache.';
const FAVORITE_VIDEOS_KEY = 'favorite-videos-v1';
const DEFAULT_LITE_VIDEO_BASE = 'https://macify-videos-1430886267.cos.ap-beijing.myqcloud.com/macify';
const DEFAULT_PREMIUM_FREE_AERIAL_VIDEO_BASE = 'https://macify-videos-1430886267.cos.ap-beijing.myqcloud.com/macify-premium';
const LITE_SOURCE_VERSION = 'mp4-1080p-cos-20260510';
const PREMIUM_FREE_AERIAL_SOURCE_VERSION = 'premium-free-aerial-1080p-cos-20260512-67';
const SHUFFLE_SCOPE_VERSION = 'default-all-20260510';
const DEFAULT_VIDEO_LIBRARY = 'apple';

const VIDEO_LIBRARIES = Object.freeze({
  apple: 'apple',
  premiumFreeAerial: 'premiumFreeAerial',
});

const DEFAULT_SETTINGS = Object.freeze({
  city: 'Shanghai',
  tempUnit: 'celsius',
  showClock: true,
  showWeather: true,
  showQuote: true,
  showVideoMeta: true,
  shuffleScope: 'all',
  shuffleScopeVersion: SHUFFLE_SCOPE_VERSION,
  videoLibrary: DEFAULT_VIDEO_LIBRARY,
  videoSource: 'lite',
  liteVideoBase: DEFAULT_LITE_VIDEO_BASE,
  liteSourceVersion: LITE_SOURCE_VERSION,
  premiumFreeAerialVideoBase: DEFAULT_PREMIUM_FREE_AERIAL_VIDEO_BASE,
  premiumFreeAerialSourceVersion: PREMIUM_FREE_AERIAL_SOURCE_VERSION,
  reverseProxy: false,
  proxyBase: '',
  zenHaptics: false,
  zenSound: false,
  rememberZenCues: false,
});

function readJson(key, fallback) {
  try {
    const value = wx.getStorageSync(key);
    return value || fallback;
  } catch (error) {
    console.warn('Storage read failed:', key, error);
    return fallback;
  }
}

function writeJson(key, value) {
  try {
    wx.setStorageSync(key, value);
  } catch (error) {
    console.warn('Storage write failed:', key, error);
  }
}

function normalizeSettings(raw) {
  const settings = {
    ...DEFAULT_SETTINGS,
    ...(raw || {}),
  };
  if (!Object.prototype.hasOwnProperty.call(VIDEO_LIBRARIES, settings.videoLibrary)) {
    settings.videoLibrary = DEFAULT_VIDEO_LIBRARY;
  }
  if (settings.videoSource === 'apple' || settings.videoSource === 'original4k') {
    settings.videoSource = 'apple1080';
  }
  if (settings.videoSource !== 'lite' && settings.videoSource !== 'apple1080') {
    settings.videoSource = 'lite';
  }
  if (!raw || raw.shuffleScopeVersion !== SHUFFLE_SCOPE_VERSION) {
    settings.shuffleScope = 'all';
    settings.shuffleScopeVersion = SHUFFLE_SCOPE_VERSION;
  }
  if (settings.shuffleScope === 'Animals') {
    settings.shuffleScope = 'AnimalsAndPlants';
  }
  if (settings.shuffleScope === 'Space') {
    settings.shuffleScope = 'all';
  }
  if (!raw || raw.liteSourceVersion !== LITE_SOURCE_VERSION) {
    if (!raw || settings.videoSource === 'apple1080') {
      settings.videoSource = 'lite';
    }
    if (!settings.liteVideoBase) {
      settings.liteVideoBase = DEFAULT_LITE_VIDEO_BASE;
    }
    settings.liteSourceVersion = LITE_SOURCE_VERSION;
  }
  if (settings.videoSource === 'lite' && !settings.liteVideoBase) {
    settings.liteVideoBase = DEFAULT_LITE_VIDEO_BASE;
  }
  if (!settings.premiumFreeAerialVideoBase) {
    settings.premiumFreeAerialVideoBase = DEFAULT_PREMIUM_FREE_AERIAL_VIDEO_BASE;
  }
  if (settings.premiumFreeAerialSourceVersion !== PREMIUM_FREE_AERIAL_SOURCE_VERSION) {
    settings.premiumFreeAerialSourceVersion = PREMIUM_FREE_AERIAL_SOURCE_VERSION;
  }
  return settings;
}

function getSettings() {
  return normalizeSettings(readJson(SETTINGS_KEY, null));
}

function saveSettings(settings) {
  const next = normalizeSettings(settings);
  writeJson(SETTINGS_KEY, next);
  return next;
}

function setSetting(key, value) {
  const settings = getSettings();
  settings[key] = value;
  return saveSettings(settings);
}

function resetZenCuesForEntry() {
  const settings = getSettings();
  if (settings.rememberZenCues || (!settings.zenHaptics && !settings.zenSound)) {
    return settings;
  }
  return saveSettings({
    ...settings,
    zenHaptics: false,
    zenSound: false,
  });
}

function getCache(key) {
  return readJson(CACHE_PREFIX + key, null);
}

function setCache(key, value) {
  writeJson(CACHE_PREFIX + key, value);
}

function videoFavoriteKey(video) {
  if (!video || !video.id) return '';
  return `${video.videoLibrary || DEFAULT_VIDEO_LIBRARY}:${video.id}`;
}

function getFavoriteVideoKeys() {
  const value = getCache(FAVORITE_VIDEOS_KEY);
  if (!Array.isArray(value)) return [];
  return value.filter(Boolean);
}

function saveFavoriteVideoKeys(keys) {
  const unique = [];
  (keys || []).forEach((key) => {
    if (key && !unique.includes(key)) unique.push(key);
  });
  setCache(FAVORITE_VIDEOS_KEY, unique);
  return unique;
}

function isFavoriteVideo(video) {
  const key = videoFavoriteKey(video);
  return key ? getFavoriteVideoKeys().includes(key) : false;
}

function toggleFavoriteVideo(video) {
  const key = videoFavoriteKey(video);
  if (!key) {
    return {
      favorited: false,
      favorites: getFavoriteVideoKeys(),
    };
  }

  const favorites = getFavoriteVideoKeys();
  const index = favorites.indexOf(key);
  if (index >= 0) {
    favorites.splice(index, 1);
    return {
      favorited: false,
      favorites: saveFavoriteVideoKeys(favorites),
    };
  }

  favorites.unshift(key);
  return {
    favorited: true,
    favorites: saveFavoriteVideoKeys(favorites),
  };
}

module.exports = {
  DEFAULT_SETTINGS,
  DEFAULT_LITE_VIDEO_BASE,
  DEFAULT_PREMIUM_FREE_AERIAL_VIDEO_BASE,
  DEFAULT_VIDEO_LIBRARY,
  LITE_SOURCE_VERSION,
  PREMIUM_FREE_AERIAL_SOURCE_VERSION,
  SHUFFLE_SCOPE_VERSION,
  getSettings,
  saveSettings,
  setSetting,
  resetZenCuesForEntry,
  getCache,
  setCache,
  getFavoriteVideoKeys,
  isFavoriteVideo,
  toggleFavoriteVideo,
  videoFavoriteKey,
};
