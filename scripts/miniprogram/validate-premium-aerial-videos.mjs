#!/usr/bin/env node
import { readFileSync } from 'node:fs';
import { dirname, relative, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import vm from 'node:vm';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const DATA_FILE = resolve(ROOT, 'miniprogram/data/premium-free-aerial-videos.js');
const ALLOWED_CATEGORIES = new Set(['Landscapes', 'Underwater', 'AnimalsAndPlants', 'Motion']);
const ALLOWED_QUALITY_TIERS = new Set(['candidate', 'sample-approved', 'rejected', 'published']);
const ALLOWED_SOURCES = new Set(['Mixkit', 'Pexels', 'Pixabay', 'Dareful', 'Coverr']);
const REQUIRED_FIELDS = [
  'id',
  'name',
  'displayName',
  'sourceName',
  'sourcePage',
  'url',
  'category',
  'license',
  'licenseNotes',
  'qualityTier',
];

function loadCommonJsArray(filePath) {
  const sandbox = {
    module: { exports: null },
    exports: null,
  };
  vm.runInNewContext(readFileSync(filePath, 'utf8'), sandbox, { filename: filePath });
  if (!Array.isArray(sandbox.module.exports)) {
    throw new Error(`${relative(ROOT, filePath)} did not export an array`);
  }
  return sandbox.module.exports;
}

function isBlank(value) {
  return String(value ?? '').trim() === '';
}

function checkUrl(value) {
  return /^https:\/\//i.test(String(value || '').trim());
}

const videos = loadCommonJsArray(DATA_FILE);
const errors = [];
const ids = new Set();

videos.forEach((video, index) => {
  const label = video.id || `entry ${index + 1}`;

  REQUIRED_FIELDS.forEach((field) => {
    if (isBlank(video[field])) {
      errors.push(`${label}: missing ${field}`);
    }
  });

  if (video.id) {
    if (ids.has(video.id)) errors.push(`${label}: duplicate id`);
    ids.add(video.id);
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

  ['sourcePage', 'url'].forEach((field) => {
    if (!isBlank(video[field]) && !checkUrl(video[field])) {
      errors.push(`${label}: ${field} must start with https://`);
    }
  });

  if (video.sourceDownloadPage && !checkUrl(video.sourceDownloadPage)) {
    errors.push(`${label}: sourceDownloadPage must start with https://`);
  }

  if (!Array.isArray(video.tags)) {
    errors.push(`${label}: tags must be an array`);
  }

  if (!Array.isArray(video.subcategories)) {
    errors.push(`${label}: subcategories must be an array`);
  }
});

if (errors.length) {
  console.error(`Found ${errors.length} premium aerial data issue(s):`);
  errors.forEach((error) => console.error(`- ${error}`));
  process.exit(1);
}

console.log(`Validated ${videos.length} premium free aerial video candidate(s).`);
