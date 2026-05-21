import { createHash } from 'node:crypto';
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, relative, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

export const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
export const CONTENT_DIR = resolve(ROOT, 'content');
export const MINIPROGRAM_DATA_DIR = resolve(ROOT, 'miniprogram/data');
export const DEFAULT_FLUTTER_CONTENT_DIR = resolve(ROOT, 'flutter_app/assets/content');
export const REMOTE_CONTENT_DIR = resolve(ROOT, 'content-dist');

export const REQUIRED_VIDEO_FIELDS = [
  'id',
  'name',
  'displayName',
  'locationName',
  'locationCountry',
  'sourceName',
  'sourcePage',
  'sourceDownloadPage',
  'url',
  'previewImage',
  'category',
  'subcategories',
  'tags',
  'timeOfDay',
  'description',
  'sourceResolution',
  'duration',
  'license',
  'attribution',
  'licenseNotes',
  'qualityTier',
];

const NON_BLANK_VIDEO_FIELDS = [
  'id',
  'name',
  'displayName',
  'locationName',
  'sourceName',
  'sourcePage',
  'sourceDownloadPage',
  'url',
  'previewImage',
  'category',
  'timeOfDay',
  'description',
  'sourceResolution',
  'duration',
  'license',
  'licenseNotes',
  'qualityTier',
];

const ALLOWED_CATEGORIES = new Set(['Landscapes', 'Cities', 'Underwater', 'AnimalsAndPlants', 'Motion']);
const ALLOWED_QUALITY_TIERS = new Set(['candidate', 'sample-approved', 'rejected', 'published']);
const ALLOWED_SOURCES = new Set(['Mixkit', 'Pexels', 'Pixabay', 'Dareful', 'Coverr']);

function contentPath(fileName) {
  return resolve(CONTENT_DIR, fileName);
}

function readJsonFile(filePath) {
  return JSON.parse(readFileSync(filePath, 'utf8'));
}

export function readContent() {
  return {
    config: readJsonFile(contentPath('config.json')),
    videos: readJsonFile(contentPath('videos.json')),
    ambientTracks: readJsonFile(contentPath('ambient-tracks.json')),
    ambientRules: readJsonFile(contentPath('ambient-rules.json')),
    videoAudioMixes: readJsonFile(contentPath('video-audio-mixes.json')),
  };
}

function isBlank(value) {
  return String(value ?? '').trim() === '';
}

function isHttpsUrl(value) {
  return /^https:\/\//i.test(String(value || '').trim());
}

function isValidVolume(value) {
  const number = Number(value);
  return Number.isFinite(number) && number >= 0 && number <= 1;
}

function collectTerms(video) {
  if (!video) return [];
  return [
    video.category,
    video.timeOfDay,
    video.locationName,
    video.name,
    video.originalName,
    ...(video.subcategories || []),
    ...(video.tags || []),
  ]
    .filter(Boolean)
    .map((item) => String(item).trim().toLowerCase())
    .filter(Boolean);
}

function hasAnyTerm(terms, matches) {
  return (matches || []).some((match) => terms.includes(String(match).trim().toLowerCase()));
}

function matchesRule(terms, rule) {
  if (rule.none && hasAnyTerm(terms, rule.none)) return false;
  return hasAnyTerm(terms, rule.any || []);
}

function tracksForMix(mix) {
  if (mix == null) return [];
  return Array.isArray(mix) ? mix : [mix];
}

function ambientMixFromSpec(spec, tracksById, audioBase) {
  if (!spec) return null;

  const specs = Array.isArray(spec) ? spec : [spec];
  const tracks = specs
    .map((item) => {
      const trackId = typeof item === 'string' ? item : item && item.trackId;
      const track = tracksById[trackId];
      if (!track) return null;
      return {
        ...track,
        id: track.id,
        volume: item && typeof item === 'object' && item.volume != null ? Number(item.volume) : track.volume,
        url: `${String(audioBase || '').replace(/\/$/, '')}/${track.file}`,
      };
    })
    .filter(Boolean);

  if (!tracks.length) return null;

  return {
    tracks,
  };
}

function ambientTrackForVideo(video, content) {
  const tracksById = content.ambientTracks.tracks || {};
  const override = (content.videoAudioMixes || []).find((item) => item.videoId === video.id);

  if (override) {
    return ambientMixFromSpec(override.mix, tracksById, content.config.defaultAmbientAudioBase);
  }

  const terms = collectTerms(video);
  const rule = (content.ambientRules || []).find((item) => matchesRule(terms, item));
  if (!rule) return null;

  return ambientMixFromSpec(rule.trackId, tracksById, content.config.defaultAmbientAudioBase);
}

export function validateContent(content) {
  const errors = [];
  const trackUsage = new Map();
  let videosWithAudio = 0;
  let videosWithoutAudio = 0;

  const config = content.config || {};
  if (Number(config.schemaVersion) !== 1) errors.push('config: schemaVersion must be 1');
  if (isBlank(config.contentVersion)) errors.push('config: missing contentVersion');
  if (isBlank(config.defaultVideoLibrary)) errors.push('config: missing defaultVideoLibrary');
  if (!isHttpsUrl(config.defaultVideoBase)) errors.push('config: defaultVideoBase must start with https://');
  if (!isHttpsUrl(config.defaultAmbientAudioBase)) {
    errors.push('config: defaultAmbientAudioBase must start with https://');
  }

  const videos = Array.isArray(content.videos) ? content.videos : [];
  if (!Array.isArray(content.videos)) errors.push('videos.json must be an array');

  const videoIds = new Set();
  videos.forEach((video, index) => {
    const label = video && video.id ? video.id : `video ${index + 1}`;
    if (!video || typeof video !== 'object') {
      errors.push(`${label}: video must be an object`);
      return;
    }

    REQUIRED_VIDEO_FIELDS.forEach((field) => {
      if (!Object.prototype.hasOwnProperty.call(video, field)) {
        errors.push(`${label}: missing field ${field}`);
      }
    });

    NON_BLANK_VIDEO_FIELDS.forEach((field) => {
      if (isBlank(video[field])) errors.push(`${label}: ${field} cannot be blank`);
    });

    if (video.id) {
      if (videoIds.has(video.id)) errors.push(`${label}: duplicate id`);
      videoIds.add(video.id);
    }

    if (video.category && !ALLOWED_CATEGORIES.has(video.category)) {
      errors.push(`${label}: category must be one of ${[...ALLOWED_CATEGORIES].join(', ')}`);
    }

    if (video.qualityTier && !ALLOWED_QUALITY_TIERS.has(video.qualityTier)) {
      errors.push(`${label}: qualityTier must be one of ${[...ALLOWED_QUALITY_TIERS].join(', ')}`);
    }

    if (video.sourceName && !ALLOWED_SOURCES.has(video.sourceName)) {
      errors.push(`${label}: sourceName must be one of ${[...ALLOWED_SOURCES].join(', ')}`);
    }

    ['sourcePage', 'sourceDownloadPage', 'url', 'previewImage'].forEach((field) => {
      if (!isBlank(video[field]) && !isHttpsUrl(video[field])) {
        errors.push(`${label}: ${field} must start with https://`);
      }
    });

    if (!Array.isArray(video.tags)) errors.push(`${label}: tags must be an array`);
    if (!Array.isArray(video.subcategories)) errors.push(`${label}: subcategories must be an array`);
  });

  const ambientTracks = content.ambientTracks || {};
  const tracksById = ambientTracks.tracks || {};
  const trackIds = new Set(Object.keys(tracksById));
  const trackFileNames = new Set();

  if (!ambientTracks.modes || ambientTracks.modes.VIDEO !== 'video' || ambientTracks.modes.CUSTOM !== 'custom') {
    errors.push('ambient-tracks: modes must include VIDEO/CUSTOM values');
  }

  if (!Number.isInteger(Number(ambientTracks.maxCustomAmbientTracks)) || Number(ambientTracks.maxCustomAmbientTracks) <= 0) {
    errors.push('ambient-tracks: maxCustomAmbientTracks must be positive');
  }

  Object.entries(tracksById).forEach(([key, track]) => {
    const label = track && (track.id || key);
    if (!track || typeof track !== 'object') {
      errors.push(`${key}: ambient track must be an object`);
      return;
    }
    if (track.id !== key) errors.push(`${label}: track id must match object key "${key}"`);
    if (isBlank(track.label)) errors.push(`${label}: missing label`);
    if (isBlank(track.file)) errors.push(`${label}: missing file`);
    if (!/\.mp3$/i.test(String(track.file || ''))) errors.push(`${label}: file must be an mp3`);
    if (track.file) {
      if (trackFileNames.has(track.file)) errors.push(`${label}: duplicate file ${track.file}`);
      trackFileNames.add(track.file);
    }
    if (!Number.isFinite(Number(track.durationMs)) || Number(track.durationMs) <= 0) {
      errors.push(`${label}: durationMs must be positive`);
    }
    if (!isValidVolume(track.volume)) errors.push(`${label}: volume must be between 0 and 1`);
  });

  (ambientTracks.customTrackIds || []).forEach((trackId) => {
    if (!trackIds.has(trackId)) errors.push(`custom track ${trackId}: missing ambient track`);
  });

  Object.entries(ambientTracks.customLabels || {}).forEach(([trackId, label]) => {
    if (!trackIds.has(trackId)) errors.push(`custom label ${trackId}: missing ambient track`);
    if (isBlank(label)) errors.push(`custom label ${trackId}: label cannot be blank`);
  });

  if (!Array.isArray(content.ambientRules)) {
    errors.push('ambient-rules.json must be an array');
  } else {
    content.ambientRules.forEach((rule, index) => {
      const label = `rule ${index + 1}`;
      if (!trackIds.has(rule.trackId)) errors.push(`${label}: unknown trackId ${rule.trackId}`);
      if (!Array.isArray(rule.any) || !rule.any.length) errors.push(`${label}: any must be a non-empty array`);
      if (rule.none && !Array.isArray(rule.none)) errors.push(`${label}: none must be an array`);
    });
  }

  if (!Array.isArray(content.videoAudioMixes)) {
    errors.push('video-audio-mixes.json must be an array');
  } else {
    const seenMixVideoIds = new Set();
    content.videoAudioMixes.forEach((entry, index) => {
      const label = entry && entry.videoId ? entry.videoId : `mix entry ${index + 1}`;
      if (!entry || typeof entry !== 'object') {
        errors.push(`${label}: mix entry must be an object`);
        return;
      }
      if (isBlank(entry.videoId)) errors.push(`${label}: missing videoId`);
      if (entry.videoId) {
        if (seenMixVideoIds.has(entry.videoId)) errors.push(`${label}: duplicate video mix`);
        seenMixVideoIds.add(entry.videoId);
        if (!videoIds.has(entry.videoId)) errors.push(`${label}: videoId not found in video data`);
      }
      if (isBlank(entry.notes)) errors.push(`${label}: missing notes`);
      if (entry.mix === undefined) {
        errors.push(`${label}: mix must be an array or null`);
        return;
      }
      if (entry.mix === null) return;
      if (!Array.isArray(entry.mix) || !entry.mix.length) {
        errors.push(`${label}: mix must be a non-empty array or null`);
        return;
      }

      const seenTrackIds = new Set();
      entry.mix.forEach((trackSpec, trackIndex) => {
        const trackLabel = `${label} mix ${trackIndex + 1}`;
        if (!trackSpec || typeof trackSpec !== 'object') {
          errors.push(`${trackLabel}: track spec must be an object`);
          return;
        }
        if (!trackIds.has(trackSpec.trackId)) errors.push(`${trackLabel}: unknown trackId ${trackSpec.trackId}`);
        if (seenTrackIds.has(trackSpec.trackId)) errors.push(`${trackLabel}: duplicate trackId ${trackSpec.trackId}`);
        seenTrackIds.add(trackSpec.trackId);
        if (trackSpec.volume != null && !isValidVolume(trackSpec.volume)) {
          errors.push(`${trackLabel}: volume must be between 0 and 1`);
        }
      });
    });
  }

  videos
    .filter((video) => video.qualityTier === 'published')
    .forEach((video) => {
      const mix = ambientTrackForVideo(video, content);
      if (!mix) {
        videosWithoutAudio += 1;
        return;
      }

      const tracks = tracksForMix(mix.tracks && mix.tracks.length ? mix.tracks : mix);
      if (!tracks.length) {
        errors.push(`${video.id}: resolved mix has no tracks`);
        return;
      }

      videosWithAudio += 1;
      tracks.forEach((track) => {
        if (!trackIds.has(track.id)) errors.push(`${video.id}: resolved unknown track ${track.id}`);
        if (!isHttpsUrl(track.url)) errors.push(`${video.id}: resolved track ${track.id} has invalid url`);
        if (!isValidVolume(track.volume)) errors.push(`${video.id}: resolved track ${track.id} volume must be between 0 and 1`);
        trackUsage.set(track.id, (trackUsage.get(track.id) || 0) + 1);
      });
    });

  return {
    errors,
    summary: {
      videos: videos.length,
      publishedVideos: videos.filter((video) => video.qualityTier === 'published').length,
      ambientTracks: trackIds.size,
      ambientRules: Array.isArray(content.ambientRules) ? content.ambientRules.length : 0,
      videoAudioMixes: Array.isArray(content.videoAudioMixes) ? content.videoAudioMixes.length : 0,
      videosWithAudio,
      videosWithoutAudio,
      trackUsage: [...trackUsage.entries()].sort((left, right) => right[1] - left[1]),
    },
  };
}

export function stringifyJson(value) {
  return `${JSON.stringify(value, null, 2)}\n`;
}

export function writeTextIfChanged(filePath, text) {
  mkdirSync(dirname(filePath), { recursive: true });
  if (existsSync(filePath) && readFileSync(filePath, 'utf8') === text) return false;
  writeFileSync(filePath, text);
  return true;
}

export function writeJsonFile(filePath, value) {
  return writeTextIfChanged(filePath, stringifyJson(value));
}

export function generatedHeader() {
  return '// This file is generated by npm run content:build. Edit content/*.json instead.\n\n';
}

export function commonJsExport(value) {
  return `${generatedHeader()}module.exports = Object.freeze(${JSON.stringify(value, null, 2)});\n`;
}

export function sha256(text) {
  return createHash('sha256').update(text).digest('hex');
}

export function relativeToRoot(filePath) {
  return relative(ROOT, filePath);
}
