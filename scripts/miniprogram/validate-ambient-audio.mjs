#!/usr/bin/env node
import { readFileSync } from 'node:fs';
import { dirname, relative, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import vm from 'node:vm';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const VIDEOS_FILE = resolve(ROOT, 'miniprogram/data/premium-free-aerial-videos.js');
const AMBIENT_FILE = resolve(ROOT, 'miniprogram/data/ambient-audio.js');
const MIXES_FILE = resolve(ROOT, 'miniprogram/data/video-audio-mixes.js');

const moduleCache = new Map();

function loadCommonJs(filePath) {
  const resolved = resolve(filePath);
  if (moduleCache.has(resolved)) return moduleCache.get(resolved).exports;

  const module = { exports: {} };
  moduleCache.set(resolved, module);

  const sandbox = {
    console,
    module,
    exports: module.exports,
    require(request) {
      if (request.startsWith('.')) {
        return loadCommonJs(resolve(dirname(resolved), request));
      }
      throw new Error(`Unsupported require("${request}") in ${relative(ROOT, resolved)}`);
    },
  };

  vm.runInNewContext(readFileSync(resolved, 'utf8'), sandbox, { filename: resolved });
  return module.exports;
}

function isBlank(value) {
  return String(value ?? '').trim() === '';
}

function isValidVolume(value) {
  const number = Number(value);
  return Number.isFinite(number) && number >= 0 && number <= 1;
}

function tracksForMix(mix) {
  if (mix == null) return [];
  return Array.isArray(mix) ? mix : [mix];
}

const videos = loadCommonJs(VIDEOS_FILE);
const ambient = loadCommonJs(AMBIENT_FILE);
const mixes = loadCommonJs(MIXES_FILE);

const errors = [];
const videoIds = new Set(videos.map((video) => video.id).filter(Boolean));
const publishedVideos = videos.filter((video) => video.qualityTier === 'published');
const trackIds = new Set(Object.keys(ambient.AMBIENT_TRACKS || {}));
const trackFileNames = new Set();

Object.entries(ambient.AMBIENT_TRACKS || {}).forEach(([key, track]) => {
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

(ambient.CUSTOM_AMBIENT_TRACK_IDS || []).forEach((trackId) => {
  if (!trackIds.has(trackId)) errors.push(`custom track ${trackId}: missing ambient track`);
});

(ambient.AMBIENT_RULES || []).forEach((rule, index) => {
  const label = `rule ${index + 1}`;
  if (!trackIds.has(rule.trackId)) errors.push(`${label}: unknown trackId ${rule.trackId}`);
  if (!Array.isArray(rule.any) || !rule.any.length) errors.push(`${label}: any must be a non-empty array`);
  if (rule.none && !Array.isArray(rule.none)) errors.push(`${label}: none must be an array`);
});

if (!Array.isArray(mixes)) {
  errors.push('video-audio-mixes.js must export an array');
} else {
  const seenMixVideoIds = new Set();
  mixes.forEach((entry, index) => {
    const label = entry && entry.videoId ? entry.videoId : `mix entry ${index + 1}`;
    if (!entry || typeof entry !== 'object') {
      errors.push(`${label}: mix entry must be an object`);
      return;
    }
    if (isBlank(entry.videoId)) errors.push(`${label}: missing videoId`);
    if (entry.videoId) {
      if (seenMixVideoIds.has(entry.videoId)) errors.push(`${label}: duplicate video mix`);
      seenMixVideoIds.add(entry.videoId);
      if (!videoIds.has(entry.videoId)) errors.push(`${label}: videoId not found in premium video data`);
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

const trackUsage = new Map();
let videosWithAudio = 0;
let videosWithoutAudio = 0;

publishedVideos.forEach((video) => {
  const mix = ambient.ambientTrackForVideo(video);
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
    if (!/^https:\/\//i.test(String(track.url || ''))) errors.push(`${video.id}: resolved track ${track.id} has invalid url`);
    if (!isValidVolume(track.volume)) errors.push(`${video.id}: resolved track ${track.id} volume must be between 0 and 1`);
    trackUsage.set(track.id, (trackUsage.get(track.id) || 0) + 1);
  });
});

if (errors.length) {
  console.error(`Found ${errors.length} ambient audio data issue(s):`);
  errors.forEach((error) => console.error(`- ${error}`));
  process.exit(1);
}

const usageSummary = [...trackUsage.entries()]
  .sort((left, right) => right[1] - left[1])
  .map(([trackId, count]) => `${trackId}:${count}`)
  .join(', ');

console.log(`Validated ${Object.keys(ambient.AMBIENT_TRACKS).length} ambient track(s).`);
console.log(`Validated ${mixes.length} explicit video mix override(s).`);
console.log(`Resolved ambient audio for ${videosWithAudio}/${publishedVideos.length} published video(s); ${videosWithoutAudio} without audio.`);
console.log(`Track usage: ${usageSummary || 'none'}`);
