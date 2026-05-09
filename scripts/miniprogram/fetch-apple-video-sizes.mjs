#!/usr/bin/env node
import { spawnSync } from 'node:child_process';
import { readFileSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';

const ROOT = resolve(new URL('../..', import.meta.url).pathname);
const videos = JSON.parse(readFileSync(resolve(ROOT, 'src/data/videos.json'), 'utf8'));
const outPath = resolve(ROOT, 'scripts/miniprogram/video-size-cache.json');

const concurrency = Number(process.argv[2] || 8);
const queue = [...videos];
const results = [];

function head(video) {
  const response = spawnSync(
    'curl',
    ['-I', '-L', '--max-time', '20', '--silent', '--show-error', video.url],
    { encoding: 'utf8' },
  );
  if (response.status !== 0) {
    throw new Error(response.stderr || `curl exited ${response.status}`);
  }
  const matches = [...response.stdout.matchAll(/^content-length:\s*(\d+)/gim)];
  const length = Number(matches.at(-1)?.[1] || 0);
  return {
    id: video.id,
    shotID: video.shotID,
    name: video.name,
    category: video.category,
    url: video.url,
    bytes: Number.isFinite(length) ? length : 0,
    mb: Number.isFinite(length) ? Math.round((length / 1024 / 1024) * 10) / 10 : 0,
  };
}

async function worker() {
  while (queue.length) {
    const video = queue.shift();
    try {
      const result = await head(video);
      results.push(result);
      console.log(`${String(results.length).padStart(3, '0')}/${videos.length} ${result.mb}MB ${result.name}`);
    } catch (error) {
      results.push({
        id: video.id,
        shotID: video.shotID,
        name: video.name,
        category: video.category,
        url: video.url,
        bytes: 0,
        mb: 0,
        error: String(error && error.message ? error.message : error),
      });
      console.warn(`failed ${video.name}: ${error.message || error}`);
    }
  }
}

await Promise.all(Array.from({ length: concurrency }, () => worker()));
results.sort((a, b) => a.bytes - b.bytes);
writeFileSync(outPath, JSON.stringify(results, null, 2) + '\n');

const buckets = {
  under50: results.filter((item) => item.bytes > 0 && item.mb <= 50).length,
  under100: results.filter((item) => item.bytes > 0 && item.mb <= 100).length,
  under150: results.filter((item) => item.bytes > 0 && item.mb <= 150).length,
  under200: results.filter((item) => item.bytes > 0 && item.mb <= 200).length,
};

console.log(`\nwrote ${outPath}`);
console.log(buckets);
