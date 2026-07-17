const { getCache, setCache } = require('./storage.js');
const { activeVideoLibrary } = require('./videos.js');

const LEGACY_CACHE_KEY = 'last-video-file-v1';
const CACHE_KEY = 'video-file-cache-v2';
const CACHE_DIR_NAME = 'macify-video-cache';
const MAX_CACHE_BYTES = 190 * 1024 * 1024;
const MAX_CACHE_FILES = 80;
const DOWNLOAD_HEADROOM_BYTES = 45 * 1024 * 1024;

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

function cacheKeyFor(settings, video) {
  if (!video || !video.id) return '';
  const library = sanitizeFileName(video.videoLibrary || activeVideoLibrary(settings));
  return `${library}:${sourceVersionFor(settings)}:${video.id}`;
}

function localPathFor(settings, video) {
  const dir = cacheDir();
  if (!dir || !video || !video.id) return '';
  const library = sanitizeFileName(video.videoLibrary || activeVideoLibrary(settings));
  const sourceVersion = sanitizeFileName(sourceVersionFor(settings) || 'current');
  return `${dir}/${library}-${sourceVersion}-${sanitizeFileName(video.id)}.mp4`;
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

function fileSize(path) {
  const fs = getFs();
  if (!fs || !path) return 0;
  try {
    const stat = fs.statSync(path);
    return Math.max(0, Number(stat && stat.size) || 0);
  } catch (error) {
    return 0;
  }
}

function readIndex() {
  const raw = getCache(CACHE_KEY);
  const index = raw && raw.entries && typeof raw.entries === 'object'
    ? raw
    : { version: 2, entries: {} };
  index.version = 2;
  index.entries = index.entries || {};
  return index;
}

function writeIndex(index) {
  setCache(CACHE_KEY, {
    version: 2,
    entries: index && index.entries ? index.entries : {},
  });
}

function migrateLegacyCache(settings, index) {
  const legacy = getCache(LEGACY_CACHE_KEY);
  if (!legacy || !legacy.id || !legacy.localPath) return index;

  if (fileExists(legacy.localPath)) {
    const key = cacheKeyFor(settings, legacy);
    if (key) {
      index.entries[key] = {
        id: legacy.id,
        videoLibrary: legacy.videoLibrary || activeVideoLibrary(settings),
        sourceVersion: legacy.sourceVersion || sourceVersionFor(settings),
        localPath: legacy.localPath,
        remoteUrl: legacy.remoteUrl || '',
        bytes: fileSize(legacy.localPath),
        cachedAt: legacy.cachedAt || Date.now(),
        lastAccessedAt: Date.now(),
      };
    }
  }
  setCache(LEGACY_CACHE_KEY, null);
  return index;
}

function entrySortValue(entry) {
  return Math.max(Number(entry.lastAccessedAt) || 0, Number(entry.cachedAt) || 0);
}

function pruneCache(settings, index, keepKey, targetBytes = MAX_CACHE_BYTES) {
  const library = activeVideoLibrary(settings);
  const sourceVersion = sourceVersionFor(settings);
  const entries = index.entries || {};

  Object.keys(entries).forEach((key) => {
    const entry = entries[key];
    if (
      !entry
      || !entry.localPath
      || !fileExists(entry.localPath)
      || (entry.videoLibrary === library && entry.sourceVersion !== sourceVersion)
    ) {
      if (entry && entry.localPath) unlinkFile(entry.localPath);
      delete entries[key];
      return;
    }
    entry.bytes = Number(entry.bytes) || fileSize(entry.localPath);
  });

  let ordered = Object.keys(entries)
    .map((key) => ({ key, entry: entries[key] }))
    .sort((left, right) => entrySortValue(left.entry) - entrySortValue(right.entry));

  let totalBytes = ordered.reduce((sum, item) => sum + (Number(item.entry.bytes) || 0), 0);
  while (
    ordered.length > MAX_CACHE_FILES
    || (totalBytes > targetBytes && ordered.length > 1)
  ) {
    const removableIndex = ordered.findIndex((item) => item.key !== keepKey);
    if (removableIndex < 0) break;
    const [removed] = ordered.splice(removableIndex, 1);
    totalBytes -= Number(removed.entry.bytes) || 0;
    unlinkFile(removed.entry.localPath);
    delete entries[removed.key];
  }

  writeIndex(index);
  return index;
}

function isCacheableVideo(settings, video) {
  return settings
    && video
    && video.id
    && !video.warning
    && /^https:\/\//i.test(video.url || '');
}

function cachedVideoForSettings(settings, findVideoById) {
  if (!settings || !findVideoById) return null;

  let index = migrateLegacyCache(settings, readIndex());
  index = pruneCache(settings, index);
  const library = activeVideoLibrary(settings);
  const sourceVersion = sourceVersionFor(settings);
  const entries = Object.keys(index.entries)
    .map((key) => ({ key, entry: index.entries[key] }))
    .filter(({ entry }) => (
      entry
      && entry.videoLibrary === library
      && entry.sourceVersion === sourceVersion
      && entry.localPath
    ))
    .sort((left, right) => entrySortValue(right.entry) - entrySortValue(left.entry));

  for (let indexInList = 0; indexInList < entries.length; indexInList += 1) {
    const { key, entry } = entries[indexInList];
    if (!fileExists(entry.localPath)) {
      delete index.entries[key];
      writeIndex(index);
      continue;
    }
    const video = findVideoById(settings, entry.id);
    if (!video) continue;

    entry.lastAccessedAt = Date.now();
    entry.bytes = Number(entry.bytes) || fileSize(entry.localPath);
    writeIndex(index);
    return {
      ...video,
      url: entry.localPath,
      fallbackUrl: entry.remoteUrl || video.url,
      cached: true,
    };
  }

  return null;
}

function removeCachedVideo(settings, video) {
  if (!settings || !video) return;
  const key = cacheKeyFor(settings, video);
  if (!key) return;
  const index = migrateLegacyCache(settings, readIndex());
  const entry = index.entries[key];
  if (entry && entry.localPath) unlinkFile(entry.localPath);
  delete index.entries[key];
  writeIndex(index);
}

function isVideoCached(settings, video) {
  if (!settings || !video) return false;
  const key = cacheKeyFor(settings, video);
  if (!key) return false;
  const index = pruneCache(settings, migrateLegacyCache(settings, readIndex()));
  const entry = index.entries[key];
  return !!(entry && entry.localPath && fileExists(entry.localPath));
}

function cacheVideo(settings, video, callbacks = {}) {
  if (!isCacheableVideo(settings, video) || !ensureCacheDir()) return null;

  const localPath = localPathFor(settings, video);
  const key = cacheKeyFor(settings, video);
  if (!localPath || !key) return null;

  const indexBeforeDownload = migrateLegacyCache(settings, readIndex());
  pruneCache(
    settings,
    indexBeforeDownload,
    key,
    Math.max(0, MAX_CACHE_BYTES - DOWNLOAD_HEADROOM_BYTES),
  );

  const meta = {
    id: video.id,
    videoLibrary: video.videoLibrary || activeVideoLibrary(settings),
    sourceVersion: sourceVersionFor(settings),
    localPath,
    remoteUrl: video.url,
    bytes: 0,
    cachedAt: Date.now(),
    lastAccessedAt: Date.now(),
  };

  if (fileExists(localPath)) {
    meta.bytes = fileSize(localPath);
    const index = migrateLegacyCache(settings, readIndex());
    index.entries[key] = meta;
    pruneCache(settings, index, key);
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
      meta.bytes = fileSize(localPath);
      const index = migrateLegacyCache(settings, readIndex());
      index.entries[key] = meta;
      pruneCache(settings, index, key);
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
  isVideoCached,
  removeCachedVideo,
  MAX_CACHE_BYTES,
  MAX_CACHE_FILES,
};
