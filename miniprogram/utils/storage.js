const SETTINGS_KEY = 'macify.settings.v1';
const {
  AMBIENT_AUDIO_MODES,
  normalizeCustomAmbientMix,
} = require('../data/ambient-audio.js');
const CONTENT_CONFIG = require('../data/content-config.js');
const CACHE_PREFIX = 'macify.cache.';
const FAVORITE_VIDEOS_KEY = 'favorite-videos-v1';
const DEFAULT_PREMIUM_FREE_AERIAL_VIDEO_BASE = CONTENT_CONFIG.defaultPremiumFreeAerialVideoBase;
const PREMIUM_FREE_AERIAL_SOURCE_VERSION = CONTENT_CONFIG.contentVersion;
const SHUFFLE_SCOPE_VERSION = 'default-all-20260510';
const DEFAULT_VIDEO_LIBRARY = CONTENT_CONFIG.defaultVideoLibrary;
const DEFAULT_BREATH_RHYTHM = Object.freeze({
  inhale: 5,
  holdAfterInhale: 0,
  exhale: 5,
  holdAfterExhale: 0,
});
const DEFAULT_CUSTOM_BREATH_RHYTHM = Object.freeze({
  inhale: 4,
  holdAfterInhale: 7,
  exhale: 8,
  holdAfterExhale: 0,
  cycles: 8,
});
const PUBLIC_SHUFFLE_SCOPES = Object.freeze([
  'all',
  'favorites',
  'Landscapes',
  'Cities',
  'AnimalsAndPlants',
  'Motion',
  'Underwater',
]);

const DEFAULT_SETTINGS = Object.freeze({
  city: '北京',
  tempUnit: 'celsius',
  showClock: true,
  showWeather: true,
  showQuote: true,
  showVideoMeta: true,
  shuffleScope: 'all',
  shuffleScopeVersion: SHUFFLE_SCOPE_VERSION,
  videoLibrary: DEFAULT_VIDEO_LIBRARY,
  videoSource: 'lite',
  premiumFreeAerialVideoBase: DEFAULT_PREMIUM_FREE_AERIAL_VIDEO_BASE,
  premiumFreeAerialSourceVersion: PREMIUM_FREE_AERIAL_SOURCE_VERSION,
  ambientAudioMode: AMBIENT_AUDIO_MODES.VIDEO,
  customAmbientMix: [],
  zenHaptics: false,
  zenSound: false,
  rememberZenCues: false,
  defaultBreathRhythm: DEFAULT_BREATH_RHYTHM,
  customBreathRhythm: DEFAULT_CUSTOM_BREATH_RHYTHM,
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

function normalizeNumber(value, fallback, min, max) {
  const number = Number(value);
  if (!Number.isFinite(number)) return fallback;
  return Math.max(min, Math.min(max, Math.round(number)));
}

function normalizeBreathRhythm(raw, defaults, includeCycles = false) {
  const source = raw || {};
  const rhythm = {
    inhale: normalizeNumber(source.inhale, defaults.inhale, 1, 60),
    holdAfterInhale: normalizeNumber(source.holdAfterInhale, defaults.holdAfterInhale, 0, 60),
    exhale: normalizeNumber(source.exhale, defaults.exhale, 1, 60),
    holdAfterExhale: normalizeNumber(source.holdAfterExhale, defaults.holdAfterExhale, 0, 60),
  };

  if (includeCycles) {
    rhythm.cycles = normalizeNumber(source.cycles, defaults.cycles, 1, 99);
  }

  return rhythm;
}

function normalizeSettings(raw) {
  const settings = {
    ...DEFAULT_SETTINGS,
    ...(raw || {}),
  };
  // Public release uses the licensed free-video library only. Keep old preview
  // installs normalized so they cannot keep playing removed source modes.
  settings.videoLibrary = DEFAULT_VIDEO_LIBRARY;
  settings.videoSource = 'lite';
  settings.city = String(settings.city || '').trim() || DEFAULT_SETTINGS.city;
  if (!raw || raw.shuffleScopeVersion !== SHUFFLE_SCOPE_VERSION) {
    settings.shuffleScope = 'all';
    settings.shuffleScopeVersion = SHUFFLE_SCOPE_VERSION;
  }
  if (settings.shuffleScope === 'Animals') {
    settings.shuffleScope = 'AnimalsAndPlants';
  }
  if (!PUBLIC_SHUFFLE_SCOPES.includes(settings.shuffleScope)) {
    settings.shuffleScope = 'all';
  }
  if (!settings.premiumFreeAerialVideoBase) {
    settings.premiumFreeAerialVideoBase = DEFAULT_PREMIUM_FREE_AERIAL_VIDEO_BASE;
  }
  if (settings.premiumFreeAerialSourceVersion !== PREMIUM_FREE_AERIAL_SOURCE_VERSION) {
    settings.premiumFreeAerialSourceVersion = PREMIUM_FREE_AERIAL_SOURCE_VERSION;
  }
  if (!Object.keys(AMBIENT_AUDIO_MODES).some((key) => AMBIENT_AUDIO_MODES[key] === settings.ambientAudioMode)) {
    settings.ambientAudioMode = AMBIENT_AUDIO_MODES.VIDEO;
  }
  settings.customAmbientMix = normalizeCustomAmbientMix(settings.customAmbientMix);
  settings.defaultBreathRhythm = normalizeBreathRhythm(
    settings.defaultBreathRhythm,
    DEFAULT_BREATH_RHYTHM,
  );
  settings.customBreathRhythm = normalizeBreathRhythm(
    settings.customBreathRhythm,
    DEFAULT_CUSTOM_BREATH_RHYTHM,
    true,
  );
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

function resetZenSoundForForeground() {
  const settings = getSettings();
  if (!settings.zenSound) return settings;
  return saveSettings({
    ...settings,
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
  DEFAULT_BREATH_RHYTHM,
  DEFAULT_CUSTOM_BREATH_RHYTHM,
  DEFAULT_PREMIUM_FREE_AERIAL_VIDEO_BASE,
  DEFAULT_VIDEO_LIBRARY,
  PREMIUM_FREE_AERIAL_SOURCE_VERSION,
  SHUFFLE_SCOPE_VERSION,
  getSettings,
  saveSettings,
  setSetting,
  resetZenCuesForEntry,
  resetZenSoundForForeground,
  getCache,
  setCache,
  getFavoriteVideoKeys,
  isFavoriteVideo,
  toggleFavoriteVideo,
  videoFavoriteKey,
};
