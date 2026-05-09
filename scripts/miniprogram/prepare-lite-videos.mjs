#!/usr/bin/env node
import { spawnSync } from 'node:child_process';
import { mkdirSync, readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const videos = JSON.parse(readFileSync(resolve(ROOT, 'src/data/videos.json'), 'utf8'));

function argValue(name, fallback = '') {
  const index = process.argv.indexOf(name);
  return index >= 0 ? process.argv[index + 1] || fallback : fallback;
}

function hasFlag(name) {
  return process.argv.includes(name);
}

const outDir = resolve(ROOT, argValue('--out-dir', 'local-miniprogram-lite/videos'));
const height = Number(argValue('--height', '720'));
const duration = Number(argValue('--duration', '30'));
const limit = Number(argValue('--limit', '0'));
const category = argValue('--category', '');
const dryRun = hasFlag('--dry-run');

const selected = videos
  .filter((video) => !category || video.category === category)
  .slice(0, limit > 0 ? limit : undefined);

if (!selected.length) {
  console.error('No videos matched. Try --category Landscapes or remove the category filter.');
  process.exit(1);
}

if (!dryRun) {
  mkdirSync(outDir, { recursive: true });
}

console.log(`Preparing ${selected.length} video(s) into ${outDir}`);
console.log(`Target: ${height}p H.264 MP4, first ${duration}s of each source\n`);

for (const video of selected) {
  const output = resolve(outDir, `${video.id}.mp4`);
  const args = [
    '-y',
    '-i',
    video.url,
    '-t',
    String(duration),
    '-an',
    '-vf',
    `scale=-2:${height}`,
    '-c:v',
    'libx264',
    '-preset',
    'veryfast',
    '-crf',
    '28',
    '-movflags',
    '+faststart',
    output,
  ];

  console.log(`${video.name}`);
  console.log(`ffmpeg ${args.map((part) => JSON.stringify(part)).join(' ')}`);

  if (dryRun) {
    console.log('');
    continue;
  }

  const result = spawnSync('ffmpeg', args, { stdio: 'inherit' });
  if (result.status !== 0) {
    console.error(`Failed: ${video.name}`);
    process.exit(result.status || 1);
  }
  console.log('');
}

console.log('Done. Upload the videos/ folder to your CDN, preserving <video-id>.mp4 filenames.');
