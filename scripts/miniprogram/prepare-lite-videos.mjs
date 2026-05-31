#!/usr/bin/env node
import { spawnSync } from 'node:child_process';
import {
  existsSync,
  mkdirSync,
  readFileSync,
  renameSync,
  rmSync,
  statSync,
  writeFileSync,
} from 'node:fs';
import { basename, dirname, join, relative, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import vm from 'node:vm';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const DEFAULT_OUT_DIR = 'local-miniprogram-lite';
const VIDEO_SOURCES = Object.freeze({
  mini: {
    label: 'mini program Apple 1080/2K AVC',
    path: resolve(ROOT, 'miniprogram/data/apple-aerial-1080.js'),
    type: 'commonjs',
  },
  apple4k: {
    label: 'Chrome/macOS Apple 4K SDR',
    path: resolve(ROOT, 'src/data/videos.json'),
    type: 'json',
  },
  premiumFreeAerial: {
    label: 'Premium free aerial source videos',
    path: resolve(ROOT, 'miniprogram/data/premium-free-aerial-videos.js'),
    type: 'commonjs',
  },
});

function help() {
  console.log(`Macify mini program lite CDN video builder

Usage:
  node scripts/miniprogram/prepare-lite-videos.mjs [options]

Common:
  --source mini              Source list: mini, apple4k, or premiumFreeAerial. Default: mini
  --limit 5                  Convert the first N selected videos
  --category Landscapes      Filter by category: Landscapes, AnimalsAndPlants, Motion, Underwater, Space
  --id <uuid[,uuid]>         Convert only one or more video ids
  --name <text>              Filter by video name substring
  --out-dir <dir>            Output root. Default: ${DEFAULT_OUT_DIR}
  --cdn-base <url>           CDN root used in generated manifest and instructions
  --dry-run                  Print selected videos and ffmpeg commands only

Encoding defaults:
  --mode portrait-crop       Transform mode: portrait-crop or fit. Default: portrait-crop
  --aspect 9:16              Target crop aspect ratio for portrait-crop
  --height 720               Output height. 720 is safer for low-end Android devices
  --fps 30                   Downsample to 30fps for Android WeChat compatibility
  --duration 45              Use the first 45 seconds for lightweight looping clips
  --full                     Convert full source videos instead of clipping
  --crf 28                   H.264 quality. Lower is larger/better, 23-30 is reasonable
  --profile baseline         H.264 profile: baseline, main, or high. Baseline is safest
  --tune fastdecode          x264 tune. Empty string disables it
  --preset veryfast          ffmpeg x264 preset
  --maxrate 1200k            H.264 VBV maxrate. Empty string disables it
  --bufsize 2400k            H.264 VBV bufsize. Empty string disables it
  --overwrite                Rebuild existing mp4 files

Examples:
  node scripts/miniprogram/prepare-lite-videos.mjs --limit 5 --dry-run
  node scripts/miniprogram/prepare-lite-videos.mjs --limit 5 --cdn-base https://cdn.example.com/macify
  node scripts/miniprogram/prepare-lite-videos.mjs --category Landscapes --duration 60
  node scripts/miniprogram/prepare-lite-videos.mjs --source apple4k --height 1080 --limit 5
  node scripts/miniprogram/prepare-lite-videos.mjs --source premiumFreeAerial --out-dir local-miniprogram-premium-aerial --height 1080 --duration 45 --profile main --crf 20 --maxrate 8000k --bufsize 16000k --cdn-base https://cdn.example.com/macify-premium
  node scripts/miniprogram/prepare-lite-videos.mjs --mode fit --height 720 --limit 5
`);
}

function hasFlag(name) {
  return process.argv.includes(name);
}

function argValue(name, fallback = '') {
  const index = process.argv.indexOf(name);
  return index >= 0 ? process.argv[index + 1] || fallback : fallback;
}

function numberArg(name, fallback) {
  const value = Number(argValue(name, String(fallback)));
  return Number.isFinite(value) ? value : fallback;
}

function listArg(name) {
  const values = [];
  for (let i = 0; i < process.argv.length; i += 1) {
    if (process.argv[i] === name && process.argv[i + 1]) {
      values.push(...process.argv[i + 1].split(',').map((item) => item.trim()).filter(Boolean));
    }
  }
  return values;
}

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

function loadVideoData(sourceName) {
  const source = VIDEO_SOURCES[sourceName];
  if (!source) {
    throw new Error(`Unknown --source "${sourceName}". Use one of: ${Object.keys(VIDEO_SOURCES).join(', ')}`);
  }
  if (source.type === 'json') {
    return {
      source,
      videos: JSON.parse(readFileSync(source.path, 'utf8')),
    };
  }
  return {
    source,
    videos: loadCommonJsArray(source.path),
  };
}

function commandAvailable(command) {
  return spawnSync(command, ['-version'], { stdio: 'ignore' }).status === 0;
}

function normalizeBase(url) {
  return String(url || '').trim().replace(/\/+$/, '');
}

function outputPaths(rawOutDir) {
  const absolute = resolve(ROOT, rawOutDir || DEFAULT_OUT_DIR);
  if (basename(absolute) === 'videos') {
    return {
      outRoot: dirname(absolute),
      videosDir: absolute,
    };
  }
  return {
    outRoot: absolute,
    videosDir: join(absolute, 'videos'),
  };
}

function shellQuote(value) {
  return JSON.stringify(String(value));
}

function aspectParts(aspect) {
  const [width, height] = String(aspect || '9:16').split(':').map(Number);
  if (!Number.isFinite(width) || !Number.isFinite(height) || width <= 0 || height <= 0) {
    throw new Error(`Invalid --aspect "${aspect}". Use a value like 9:16.`);
  }
  return { width, height };
}

function clampNumber(value, fallback, min, max) {
  const number = Number(value);
  if (!Number.isFinite(number)) return fallback;
  return Math.min(max, Math.max(min, number));
}

function videoFilter(video, options) {
  const filters = [];

  if (options.mode === 'portrait-crop') {
    const aspect = aspectParts(options.aspect);
    const focusX = clampNumber(video.cropFocusX, 0.5, 0, 1);
    const focusY = clampNumber(video.cropFocusY, 0.5, 0, 1);
    const cropWidth =
      `trunc(if(gt(iw/ih\\,${aspect.width}/${aspect.height})\\,ih*${aspect.width}/${aspect.height}\\,iw)/2)*2`;
    const cropHeight =
      `trunc(if(gt(iw/ih\\,${aspect.width}/${aspect.height})\\,ih\\,iw*${aspect.height}/${aspect.width})/2)*2`;
    const cropX = `trunc(min(max(iw*${focusX}-ow/2\\,0)\\,iw-ow)/2)*2`;
    const cropY = `trunc(min(max(ih*${focusY}-oh/2\\,0)\\,ih-oh)/2)*2`;
    filters.push(`crop=w='${cropWidth}':h='${cropHeight}':x='${cropX}':y='${cropY}'`);
  } else if (options.mode !== 'fit') {
    throw new Error(`Invalid --mode "${options.mode}". Use portrait-crop or fit.`);
  }

  if (options.fps > 0) {
    filters.push(`fps=${options.fps}`);
  }

  if (options.height > 0) {
    filters.push(`scale=w='trunc(${options.height}*iw/ih/2)*2':h=${options.height}`);
  }

  filters.push('format=yuv420p');
  return filters.join(',');
}

function ffmpegArgsFor(video, output, options) {
  const inputUrl = video.sampleUrl || video.url;
  const args = [
    '-hide_banner',
    '-y',
    '-i',
    inputUrl,
  ];

  if (!options.full && options.duration > 0) {
    args.push('-t', String(options.duration));
  }

  args.push(
    '-map',
    '0:v:0',
    '-an',
    '-vf',
    videoFilter(video, options),
    '-c:v',
    'libx264',
    '-profile:v',
    options.profile,
    '-level:v',
    options.height > 720 ? '4.0' : '3.1',
    '-preset',
    options.preset,
    '-crf',
    String(options.crf),
    '-pix_fmt',
    'yuv420p',
    '-movflags',
    '+faststart',
    '-tag:v',
    'avc1',
  );

  if (options.tune) args.push('-tune', options.tune);
  if (options.maxrate) args.push('-maxrate', options.maxrate);
  if (options.bufsize) args.push('-bufsize', options.bufsize);

  args.push('-f', 'mp4');
  args.push(output);
  return args;
}

function ffprobe(filePath) {
  if (!commandAvailable('ffprobe')) return null;

  const result = spawnSync('ffprobe', [
    '-v',
    'error',
    '-select_streams',
    'v:0',
    '-show_entries',
    'stream=codec_name,profile,width,height,pix_fmt,avg_frame_rate:format=duration,size,format_name',
    '-of',
    'json',
    filePath,
  ], { encoding: 'utf8' });

  if (result.status !== 0) return null;

  try {
    const parsed = JSON.parse(result.stdout);
    const stream = parsed.streams && parsed.streams[0] ? parsed.streams[0] : {};
    const format = parsed.format || {};
    return {
      codec: stream.codec_name || '',
      profile: stream.profile || '',
      width: stream.width || 0,
      height: stream.height || 0,
      pixFmt: stream.pix_fmt || '',
      frameRate: stream.avg_frame_rate || '',
      durationSeconds: format.duration ? Number(format.duration) : 0,
      sizeBytes: format.size ? Number(format.size) : statSync(filePath).size,
      format: format.format_name || '',
    };
  } catch {
    return null;
  }
}

function csvEscape(value) {
  const text = String(value ?? '');
  return /[",\n]/.test(text) ? `"${text.replace(/"/g, '""')}"` : text;
}

function writeCsv(filePath, rows) {
  const header = [
    'id',
    'name',
    'category',
    'status',
    'outputFile',
    'cdnUrl',
    'sizeBytes',
    'durationSeconds',
    'width',
    'height',
    'codec',
    'sourceUrl',
    'sourceName',
    'sourcePage',
    'license',
    'attribution',
    'licenseNotes',
    'sampleSourceUrl',
    'error',
  ];
  const lines = [
    header.join(','),
    ...rows.map((row) => header.map((key) => csvEscape(row[key])).join(',')),
  ];
  writeFileSync(filePath, `${lines.join('\n')}\n`);
}

function reportMetadata(video) {
  return {
    sourceName: video.sourceName || '',
    sourcePage: video.sourcePage || '',
    license: video.license || '',
    attribution: video.attribution || '',
    licenseNotes: video.licenseNotes || '',
  };
}

function writeReadme(filePath, options, rows) {
  const succeeded = rows.filter((row) => row.status === 'converted' || row.status === 'skipped');
  const failed = rows.filter((row) => row.status === 'failed');
  const cdnBase = normalizeBase(options.cdnBase);
  const sample = succeeded[0];
  const sampleUrl = cdnBase && sample ? `${cdnBase}/${sample.outputFile}` : '';

  writeFileSync(filePath, `# Macify Lite CDN Output

Generated by:

\`\`\`bash
node scripts/miniprogram/prepare-lite-videos.mjs ${process.argv.slice(2).map(shellQuote).join(' ')}
\`\`\`

## Result

- Ready videos: ${succeeded.length}
- Failed videos: ${failed.length}
- Source: ${VIDEO_SOURCES[options.source].label}
- Encoding: H.264 MP4 (${options.profile}${options.tune ? `, ${options.tune}` : ''}), yuv420p, ${options.mode}${options.mode === 'portrait-crop' ? ` ${options.aspect}` : ''}, ${options.height}p output height, ${options.fps}fps${options.full ? ', full duration' : `, first ${options.duration}s`}
- Video directory: \`videos/\`

## Upload

Upload this whole output directory to your CDN, preserving the \`videos/<video-id>.mp4\` paths.

The mini program builds lite video URLs as:

\`\`\`text
<liteVideoBase>/videos/<video-id>.mp4
\`\`\`

${cdnBase ? `Use this value in the mini program settings:\n\n\`\`\`text\n${cdnBase}\n\`\`\`\n` : 'After upload, set the mini program "轻量 CDN 根域名" to your CDN root, for example `https://cdn.example.com/macify`.\n'}
${sampleUrl ? `Sample generated URL:\n\n\`\`\`text\n${sampleUrl}\n\`\`\`\n` : ''}
## WeChat Domain

Add your CDN root domain to the WeChat Mini Program \`downloadFile\` legal domain list.

## Files

- \`videos/\`: MP4 files to serve from CDN
- \`manifest.json\`: machine-readable build report
- \`manifest.csv\`: spreadsheet-friendly build report
- \`wechat-settings.txt\`: value to copy into Macify settings when \`--cdn-base\` is provided
`);
}

function selectVideos(videos, options) {
  const ids = new Set(options.ids);
  const name = options.name.toLowerCase();
  const category = options.category;
  let selected = videos.filter((video) => {
    if (ids.size && !ids.has(video.id)) return false;
    if (category && video.category !== category) return false;
    if (name && !video.name.toLowerCase().includes(name)) return false;
    return true;
  });

  if (options.start > 0) selected = selected.slice(options.start);
  if (options.limit > 0) selected = selected.slice(0, options.limit);
  return selected;
}

if (hasFlag('--help') || hasFlag('-h')) {
  help();
  process.exit(0);
}

const options = {
  source: argValue('--source', 'mini'),
  rawOutDir: argValue('--out-dir', DEFAULT_OUT_DIR),
  category: argValue('--category', ''),
  name: argValue('--name', ''),
  ids: listArg('--id'),
  start: numberArg('--start', 0),
  limit: numberArg('--limit', 0),
  mode: argValue('--mode', 'portrait-crop'),
  aspect: argValue('--aspect', '9:16'),
  height: numberArg('--height', 720),
  fps: numberArg('--fps', 30),
  duration: numberArg('--duration', 45),
  full: hasFlag('--full'),
  crf: numberArg('--crf', 28),
  profile: argValue('--profile', 'baseline'),
  tune: argValue('--tune', 'fastdecode'),
  preset: argValue('--preset', 'veryfast'),
  maxrate: argValue('--maxrate', '1200k'),
  bufsize: argValue('--bufsize', '2400k'),
  cdnBase: normalizeBase(argValue('--cdn-base', '')),
  dryRun: hasFlag('--dry-run'),
  overwrite: hasFlag('--overwrite'),
};

if (options.height < 240) {
  console.error('--height is too small; use at least 240.');
  process.exit(1);
}

const { source, videos } = loadVideoData(options.source);
const selected = selectVideos(videos, options);
const { outRoot, videosDir } = outputPaths(options.rawOutDir);

if (!selected.length) {
  console.error('No videos matched. Try removing filters or using --category Landscapes.');
  process.exit(1);
}

console.log(`Selected ${selected.length} of ${videos.length} ${source.label} source video(s).`);
console.log(`Output root: ${outRoot}`);
console.log(`Target: H.264 MP4 (${options.profile}${options.tune ? `, ${options.tune}` : ''}), yuv420p, ${options.mode}${options.mode === 'portrait-crop' ? ` ${options.aspect}` : ''}, ${options.height}p output height, ${options.fps}fps${options.full ? ', full duration' : `, first ${options.duration}s`}`);
if (options.cdnBase) console.log(`CDN base: ${options.cdnBase}`);
console.log('');

if (!options.dryRun && !commandAvailable('ffmpeg')) {
  console.error('ffmpeg is required. Install it first, for example: brew install ffmpeg');
  process.exit(1);
}

if (!options.dryRun) {
  mkdirSync(videosDir, { recursive: true });
}

const rows = [];
let failed = 0;

for (const [index, video] of selected.entries()) {
  const output = join(videosDir, `${video.id}.mp4`);
  const outputFile = `videos/${video.id}.mp4`;
  const tempOutput = `${output}.part`;
  const cdnUrl = options.cdnBase ? `${options.cdnBase}/${outputFile}` : '';
  const args = ffmpegArgsFor(video, tempOutput, options);

  console.log(`[${index + 1}/${selected.length}] ${video.name} (${video.category})`);
  console.log(`source: ${video.url}`);
  if (video.sampleUrl) console.log(`sample source: ${video.sampleUrl}`);

  if (existsSync(output) && !options.overwrite) {
    const probe = ffprobe(output) || {};
    rows.push({
      id: video.id,
      name: video.name,
      category: video.category,
      status: 'skipped',
      outputFile,
      cdnUrl,
      sourceUrl: video.url,
      sampleSourceUrl: video.sampleUrl || '',
      ...reportMetadata(video),
      ...probe,
    });
    console.log(`skip existing: ${outputFile}\n`);
    continue;
  }

  console.log(`ffmpeg ${args.map(shellQuote).join(' ')}`);

  if (options.dryRun) {
    rows.push({
      id: video.id,
      name: video.name,
      category: video.category,
      status: 'planned',
      outputFile,
      cdnUrl,
      sourceUrl: video.url,
      sampleSourceUrl: video.sampleUrl || '',
      ...reportMetadata(video),
    });
    console.log('');
    continue;
  }

  rmSync(tempOutput, { force: true });
  const result = spawnSync('ffmpeg', args, { stdio: 'inherit' });

  if (result.status !== 0) {
    rmSync(tempOutput, { force: true });
    failed += 1;
    rows.push({
      id: video.id,
      name: video.name,
      category: video.category,
      status: 'failed',
      outputFile,
      cdnUrl,
      sourceUrl: video.url,
      sampleSourceUrl: video.sampleUrl || '',
      ...reportMetadata(video),
      error: `ffmpeg exited with ${result.status}`,
    });
    console.error(`failed: ${video.name}\n`);
    continue;
  }

  renameSync(tempOutput, output);
  const probe = ffprobe(output) || { sizeBytes: statSync(output).size };
  rows.push({
    id: video.id,
    name: video.name,
    category: video.category,
    status: 'converted',
    outputFile,
    cdnUrl,
    sourceUrl: video.url,
    sampleSourceUrl: video.sampleUrl || '',
    ...reportMetadata(video),
    ...probe,
  });
  console.log(`wrote: ${outputFile} (${Math.round((probe.sizeBytes || 0) / 1024 / 1024 * 10) / 10} MB)\n`);
}

if (!options.dryRun) {
  const manifestPath = join(outRoot, 'manifest.json');
  const csvPath = join(outRoot, 'manifest.csv');
  const readmePath = join(outRoot, 'README.md');
  const settingsPath = join(outRoot, 'wechat-settings.txt');

  writeFileSync(manifestPath, `${JSON.stringify({
    generatedAt: new Date().toISOString(),
    sourceData: relative(ROOT, source.path),
    sourceLabel: source.label,
    options,
    rows,
  }, null, 2)}\n`);
  writeCsv(csvPath, rows);
  writeReadme(readmePath, options, rows);
  if (options.cdnBase) {
    writeFileSync(settingsPath, `${options.cdnBase}\n`);
  }

  console.log(`Build report: ${relative(ROOT, manifestPath)}`);
  console.log(`CSV report:   ${relative(ROOT, csvPath)}`);
  console.log(`Instructions: ${relative(ROOT, readmePath)}`);
  if (options.cdnBase) console.log(`Settings:     ${relative(ROOT, settingsPath)}`);
}

if (failed > 0) {
  console.error(`Done with ${failed} failed video(s). Check manifest.json for details.`);
  process.exit(1);
}

console.log('Done.');
