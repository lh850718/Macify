const SETTINGS_KEY = 'macify.settings.v1';
const CACHE_PREFIX = 'macify.cache.';

const DEFAULT_SETTINGS = Object.freeze({
  city: 'Shanghai',
  tempUnit: 'celsius',
  showClock: true,
  showWeather: true,
  showQuote: true,
  showVideoMeta: true,
  shuffleScope: 'all',
  videoSource: 'apple',
  liteVideoBase: '',
  reverseProxy: false,
  proxyBase: '',
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
  return {
    ...DEFAULT_SETTINGS,
    ...(raw || {}),
  };
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

function resetSettings() {
  writeJson(SETTINGS_KEY, { ...DEFAULT_SETTINGS });
  return getSettings();
}

function getCache(key) {
  return readJson(CACHE_PREFIX + key, null);
}

function setCache(key, value) {
  writeJson(CACHE_PREFIX + key, value);
}

module.exports = {
  DEFAULT_SETTINGS,
  getSettings,
  saveSettings,
  setSetting,
  resetSettings,
  getCache,
  setCache,
};
