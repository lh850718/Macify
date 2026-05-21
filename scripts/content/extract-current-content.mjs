#!/usr/bin/env node
import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import vm from 'node:vm';
import {
  CONTENT_DIR,
  MINIPROGRAM_DATA_DIR,
  ROOT,
  writeJsonFile,
} from './content-lib.mjs';

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
      throw new Error(`Unsupported require("${request}") in ${resolved}`);
    },
  };

  vm.runInNewContext(readFileSync(resolved, 'utf8'), sandbox, { filename: resolved });
  return module.exports;
}

const videos = loadCommonJs(resolve(MINIPROGRAM_DATA_DIR, 'premium-free-aerial-videos.js'));
const ambient = loadCommonJs(resolve(MINIPROGRAM_DATA_DIR, 'ambient-audio.js'));
const mixes = loadCommonJs(resolve(MINIPROGRAM_DATA_DIR, 'video-audio-mixes.js'));
const storage = loadCommonJs(resolve(ROOT, 'miniprogram/utils/storage.js'));

const config = {
  schemaVersion: 1,
  contentVersion: storage.PREMIUM_FREE_AERIAL_SOURCE_VERSION,
  defaultVideoLibrary: storage.DEFAULT_VIDEO_LIBRARY,
  defaultVideoBase: storage.DEFAULT_PREMIUM_FREE_AERIAL_VIDEO_BASE,
  defaultAmbientAudioBase: ambient.DEFAULT_AMBIENT_AUDIO_BASE,
};

const ambientTracks = {
  modes: ambient.AMBIENT_AUDIO_MODES,
  maxCustomAmbientTracks: ambient.MAX_CUSTOM_AMBIENT_TRACKS,
  tracks: ambient.AMBIENT_TRACKS,
  customTrackIds: ambient.CUSTOM_AMBIENT_TRACK_IDS,
  customLabels: ambient.CUSTOM_AMBIENT_LABELS,
};

writeJsonFile(resolve(CONTENT_DIR, 'config.json'), config);
writeJsonFile(resolve(CONTENT_DIR, 'videos.json'), videos);
writeJsonFile(resolve(CONTENT_DIR, 'ambient-tracks.json'), ambientTracks);
writeJsonFile(resolve(CONTENT_DIR, 'ambient-rules.json'), ambient.AMBIENT_RULES);
writeJsonFile(resolve(CONTENT_DIR, 'video-audio-mixes.json'), mixes);

console.log(`Extracted ${videos.length} video record(s), ${Object.keys(ambient.AMBIENT_TRACKS).length} ambient track(s).`);
