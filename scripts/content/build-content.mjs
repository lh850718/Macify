#!/usr/bin/env node
import { resolve } from 'node:path';
import {
  DEFAULT_FLUTTER_CONTENT_DIR,
  MINIPROGRAM_DATA_DIR,
  REMOTE_CONTENT_DIR,
  ROOT,
  commonJsExport,
  readContent,
  relativeToRoot,
  sha256,
  stringifyJson,
  validateContent,
  writeTextIfChanged,
} from './content-lib.mjs';

const content = readContent();
const { errors, summary } = validateContent(content);

if (errors.length) {
  console.error(`Found ${errors.length} content data issue(s):`);
  errors.forEach((error) => console.error(`- ${error}`));
  process.exit(1);
}

const flutterContentDir = process.env.FLUTTER_CONTENT_DIR
  ? resolve(ROOT, process.env.FLUTTER_CONTENT_DIR)
  : DEFAULT_FLUTTER_CONTENT_DIR;

const miniprogramConfig = {
  schemaVersion: content.config.schemaVersion,
  contentVersion: content.config.contentVersion,
  defaultVideoLibrary: content.config.defaultVideoLibrary,
  defaultPremiumFreeAerialVideoBase: content.config.defaultVideoBase,
  defaultAmbientAudioBase: content.config.defaultAmbientAudioBase,
};

const ambientContent = {
  DEFAULT_AMBIENT_AUDIO_BASE: content.config.defaultAmbientAudioBase,
  AMBIENT_AUDIO_MODES: content.ambientTracks.modes,
  AMBIENT_TRACKS: content.ambientTracks.tracks,
  CUSTOM_AMBIENT_TRACK_IDS: content.ambientTracks.customTrackIds,
  CUSTOM_AMBIENT_LABELS: content.ambientTracks.customLabels,
  MAX_CUSTOM_AMBIENT_TRACKS: content.ambientTracks.maxCustomAmbientTracks,
  AMBIENT_RULES: content.ambientRules,
};

const flutterFiles = {
  'config.json': stringifyJson(content.config),
  'videos.json': stringifyJson(content.videos),
  'ambient-tracks.json': stringifyJson(content.ambientTracks),
  'ambient-rules.json': stringifyJson(content.ambientRules),
  'video-audio-mixes.json': stringifyJson(content.videoAudioMixes),
};

const manifest = {
  schemaVersion: content.config.schemaVersion,
  contentVersion: content.config.contentVersion,
  defaultVideoLibrary: content.config.defaultVideoLibrary,
  files: Object.fromEntries(
    Object.entries(flutterFiles).map(([fileName, text]) => [
      fileName,
      {
        bytes: Buffer.byteLength(text),
        sha256: sha256(text),
      },
    ]),
  ),
};

flutterFiles['content-manifest.json'] = stringifyJson(manifest);

const outputs = [
  {
    filePath: resolve(MINIPROGRAM_DATA_DIR, 'content-config.js'),
    text: commonJsExport(miniprogramConfig),
  },
  {
    filePath: resolve(MINIPROGRAM_DATA_DIR, 'premium-free-aerial-videos.js'),
    text: commonJsExport(content.videos),
  },
  {
    filePath: resolve(MINIPROGRAM_DATA_DIR, 'ambient-content.js'),
    text: commonJsExport(ambientContent),
  },
  {
    filePath: resolve(MINIPROGRAM_DATA_DIR, 'video-audio-mixes.js'),
    text: commonJsExport(content.videoAudioMixes),
  },
];

Object.entries(flutterFiles).forEach(([fileName, text]) => {
  outputs.push({
    filePath: resolve(flutterContentDir, fileName),
    text,
  });
  outputs.push({
    filePath: resolve(REMOTE_CONTENT_DIR, fileName),
    text,
  });
});

let changed = 0;
outputs.forEach(({ filePath, text }) => {
  if (writeTextIfChanged(filePath, text)) {
    changed += 1;
    console.log(`Wrote ${relativeToRoot(filePath)}`);
  }
});

console.log(
  `Built content ${content.config.contentVersion}: ${summary.videos} videos, `
    + `${summary.ambientTracks} ambient tracks, ${summary.videoAudioMixes} explicit mixes.`,
);

if (!changed) console.log('All generated content files are up to date.');
