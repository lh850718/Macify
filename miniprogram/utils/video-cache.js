const { getCache, setCache } = require('./storage.js');
const { activeVideoLibrary } = require('./videos.js');

const CACHE_KEY = 'last-video-file-v1';
const CACHE_DIR_NAME = 'macify-video-cache';

function getFs() {
  return wx.getFileSystemManager ? wx.getFileSystemManager() : null;
}

function cacheDir() {
  if (!wx.env || !wx.env.USER_DATA_PATH) return '';
  return `${wx.env.USER_DATA_PATH}/${CACHE_DIR_NAME}`;
}

function sanitizeFileName(value) {
  return String(value || '').replace(/[^a-z0-9_-]/gi, '-').replace(/-+/g, '-');
}

function sourceVersionFor(settings) {
  const library = activeVideoLibrary(settings);
  return library === 'premiumFreeAerial'
    ? settings.premiumFreeAerialSourceVersion
    : settings.liteSourceVersion;
}

function localPathFor(video) {
  const dir = cacheDir();
  if (!dir || !video || !video.id) return '';
  const library = sanitizeFileName(video.videoLibrary || activeVideoLibrary({}));
  return `${dir}/${library}-${sanitizeFileName(video.id)}.mp4`;
}

function ensureCacheDir() {
  const fs = getFs();
  const dir = cacheDir();
  if (!fs || !dir) return false;
  try {
    fs.accessSync(dir);
  } catch (error) {
    try {
      fs.mkdirSync(dir, true);
    } catch (mkdirError) {
      console.warn('Video cache mkdir failed:', mkdirError);
      return false;
    }
  }
  return true;
}

function fileExists(path) {
  const fs = getFs();
  if (!fs || !path) return false;
  try {
    fs.accessSync(path);
    return true;
  } catch (error) {
    return false;
  }
}

function unlinkFile(path) {
  const fs = getFs();
  if (!fs || !path) return;
  try {
    fs.unlinkSync(path);
  } catch (error) {
    // Missing or already-cleaned files are fine.
  }
}

function clearPreviousCachedFile(nextPath) {
  const previous = getCache(CACHE_KEY);
  if (!previous || !previous.localPath || previous.localPath === nextPath) return;
  unlinkFile(previous.localPath);
}

function isCacheableVideo(settings, video) {
  return settings
    && settings.videoSource === 'lite'
    && video
    && video.id
    && !video.warning
    && /^https:\/\//i.test(video.url || '');
}

function cachedVideoForSettings(settings, findVideoById) {
  if (!settings || settings.videoSource !== 'lite') return null;

  const meta = getCache(CACHE_KEY);
  if (!meta || !meta.id || !meta.localPath) return null;

  const library = activeVideoLibrary(settings);
  if (meta.videoLibrary !== library || meta.sourceVersion !== sourceVersionFor(settings)) {
    return null;
  }

  if (!fileExists(meta.localPath)) {
    setCache(CACHE_KEY, null);
    return null;
  }

  const video = findVideoById(settings, meta.id);
  if (!video) return null;

  return {
    ...video,
    url: meta.localPath,
    fallbackUrl: video.url,
    cached: true,
  };
}

function cacheVideo(settings, video, callbacks = {}) {
  if (!isCacheableVideo(settings, video) || !ensureCacheDir()) return null;

  const localPath = localPathFor(video);
  if (!localPath) return null;

  const meta = {
    id: video.id,
    videoLibrary: video.videoLibrary || activeVideoLibrary(settings),
    sourceVersion: sourceVersionFor(settings),
    localPath,
    remoteUrl: video.url,
    cachedAt: Date.now(),
  };

  if (fileExists(localPath)) {
    clearPreviousCachedFile(localPath);
    setCache(CACHE_KEY, meta);
    if (callbacks.success) callbacks.success(meta);
    return null;
  }

  unlinkFile(localPath);
  return wx.downloadFile({
    url: video.url,
    filePath: localPath,
    success(res) {
      if (res.statusCode !== 200) {
        unlinkFile(localPath);
        if (callbacks.fail) callbacks.fail(res);
        return;
      }
      clearPreviousCachedFile(localPath);
      setCache(CACHE_KEY, meta);
      if (callbacks.success) callbacks.success(meta);
    },
    fail(error) {
      unlinkFile(localPath);
      if (callbacks.fail) callbacks.fail(error);
    },
  });
}

module.exports = {
  cacheVideo,
  cachedVideoForSettings,
  fileExists,
};
