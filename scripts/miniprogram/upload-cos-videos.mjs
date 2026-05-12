#!/usr/bin/env node

import { chmodSync, existsSync, mkdirSync, readFileSync, statSync, unlinkSync, writeFileSync } from 'node:fs';
import { dirname, isAbsolute, join, resolve } from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '../..');

const DEFAULTS = Object.freeze({
  alias: 'macify-video',
  coscli: process.env.COSCLI_PATH || '/private/tmp/coscli',
  config: process.env.COSCLI_CONFIG || '/private/tmp/macify-cos.yaml',
  outDir: 'local-miniprogram-1080',
  prefix: 'macify',
  routines: '6',
});

function usage() {
  console.log(`Upload Macify mini program 1080p MP4 files to Tencent COS.

Required:
  --bucket <bucket-appid>      COS bucket full name, for example macify-videos-1250000000
  --region <region>           COS region, for example ap-shanghai or ap-guangzhou
  --cdn-base <url>             CDN base used by the mini program, for example https://video.example.com/macify

Credentials are read from environment variables:
  COS_SECRET_ID / COS_SECRET_KEY
  or TENCENTCLOUD_SECRET_ID / TENCENTCLOUD_SECRET_KEY
  optional COS_SESSION_TOKEN / TENCENTCLOUD_SESSION_TOKEN

Examples:
  COS_SECRET_ID=xxx COS_SECRET_KEY=yyy npm run mini:cos -- \\
    --bucket macify-videos-1250000000 \\
    --region ap-shanghai \\
    --cdn-base https://video.example.com/macify

Options:
  --out-dir <dir>              Generated output directory, default ${DEFAULTS.outDir}
  --prefix <path>              COS object prefix, default ${DEFAULTS.prefix}
  --coscli <path>              COSCLI binary, default ${DEFAULTS.coscli}
  --config <path>              Temporary COSCLI config, default ${DEFAULTS.config}
  --alias <name>               COSCLI bucket alias, default ${DEFAULTS.alias}
  --routines <count>           Concurrent file workers, default ${DEFAULTS.routines}
  --public-read                Set uploaded objects public-readable for direct COS URL testing
  --dry-run                    Print the plan without uploading
`);
}

function argValue(name, fallback = '') {
  const prefix = `${name}=`;
  const inline = process.argv.find((arg) => arg.startsWith(prefix));
  if (inline) return inline.slice(prefix.length);
  const index = process.argv.indexOf(name);
  if (index >= 0 && process.argv[index + 1] && !process.argv[index + 1].startsWith('--')) {
    return process.argv[index + 1];
  }
  return fallback;
}

function hasFlag(name) {
  return process.argv.includes(name);
}

function required(name, value) {
  if (!value) {
    usage();
    throw new Error(`Missing required option: ${name}`);
  }
  return value;
}

function normalizePrefix(prefix) {
  return String(prefix || '')
    .trim()
    .replace(/^\/+/, '')
    .replace(/\/+$/, '');
}

function normalizeBase(base) {
  return String(base || '').trim().replace(/\/+$/, '');
}

function resolveFromRoot(path) {
  return isAbsolute(path) ? path : resolve(ROOT, path);
}

function shellSafe(value) {
  const text = String(value);
  if (/^[a-zA-Z0-9_./:@+-]+$/.test(text)) return text;
  return `'${text.replace(/'/g, `'\\''`)}'`;
}

function yamlString(value) {
  return JSON.stringify(String(value || ''));
}

function csvCell(value) {
  const text = String(value ?? '');
  if (/[",\n\r]/.test(text)) return `"${text.replace(/"/g, '""')}"`;
  return text;
}

function buildCosUrl(alias, prefix, objectPath = '') {
  const cleanObject = String(objectPath || '').replace(/^\/+/, '');
  const parts = [prefix, cleanObject].filter(Boolean).join('/');
  return `cos://${alias}${parts ? `/${parts}` : ''}`;
}

function writeCosConfig(configPath, { secretId, secretKey, sessionToken, bucket, alias, region }) {
  mkdirSync(dirname(configPath), { recursive: true });
  const config = `cos:
  base:
    secretid: ${yamlString(secretId)}
    secretkey: ${yamlString(secretKey)}
    sessiontoken: ${yamlString(sessionToken)}
    protocol: https
  buckets:
  - name: ${yamlString(bucket)}
    alias: ${yamlString(alias)}
    region: ${yamlString(region)}
    endpoint: ${yamlString(`cos.${region}.myqcloud.com`)}
    ofs: false
`;
  writeFileSync(configPath, config);
  chmodSync(configPath, 0o600);
}

function run(coscli, configPath, args, options = {}) {
  const printable = [coscli, ...args].map(shellSafe).join(' ');
  console.log(`> ${printable}`);
  const result = spawnSync(coscli, ['-c', configPath, ...args], {
    cwd: ROOT,
    stdio: options.capture ? 'pipe' : 'inherit',
    encoding: 'utf8',
  });
  if (result.error) throw result.error;
  if (result.status !== 0) {
    const output = [result.stdout, result.stderr].filter(Boolean).join('\n').trim();
    if (output) console.error(output);
    throw new Error(`Command failed with exit code ${result.status}`);
  }
  return result.stdout || '';
}

function updateGeneratedCdnBase(outDir, cdnBase) {
  if (!cdnBase) return;

  const manifestPath = join(outDir, 'manifest.json');
  const csvPath = join(outDir, 'manifest.csv');
  const settingsPath = join(outDir, 'wechat-settings.txt');
  const deployPath = join(outDir, 'deployment.json');
  const manifest = JSON.parse(readFileSync(manifestPath, 'utf8'));
  const rows = manifest.rows || [];

  manifest.options = {
    ...(manifest.options || {}),
    cdnBase,
  };
  for (const row of rows) {
    if (row.outputFile) {
      row.cdnUrl = `${cdnBase}/${row.outputFile}`;
    }
  }
  writeFileSync(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`);

  const columns = [
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
    'error',
  ];
  const csv = [
    columns.join(','),
    ...rows.map((row) => columns.map((column) => csvCell(row[column])).join(',')),
  ].join('\n');
  writeFileSync(csvPath, `${csv}\n`);
  writeFileSync(settingsPath, `${cdnBase}\n`);
  writeFileSync(deployPath, `${JSON.stringify({
    updatedAt: new Date().toISOString(),
    cdnBase,
  }, null, 2)}\n`);
}

function localSummary(outDir) {
  const manifest = JSON.parse(readFileSync(join(outDir, 'manifest.json'), 'utf8'));
  const rows = manifest.rows || [];
  const ready = rows.filter((row) => row.status === 'converted' || row.status === 'skipped');
  const totalBytes = ready.reduce((sum, row) => sum + Number(row.sizeBytes || 0), 0);
  return {
    rows: rows.length,
    converted: ready.length,
    failed: rows.length - ready.length,
    totalMiB: (totalBytes / 1024 / 1024).toFixed(1),
    sampleOutputFile: (ready[0] || rows[0] || {}).outputFile || '',
    videoOutputFiles: ready.map((row) => row.outputFile).filter(Boolean),
  };
}

function main() {
  if (hasFlag('--help') || hasFlag('-h')) {
    usage();
    return;
  }

  const bucket = required('--bucket', argValue('--bucket', process.env.COS_BUCKET || ''));
  const region = required('--region', argValue('--region', process.env.COS_REGION || ''));
  const cdnBase = normalizeBase(required('--cdn-base', argValue('--cdn-base', process.env.CDN_BASE || '')));
  const outDir = resolveFromRoot(argValue('--out-dir', DEFAULTS.outDir));
  const prefix = normalizePrefix(argValue('--prefix', process.env.COS_PREFIX || DEFAULTS.prefix));
  const alias = argValue('--alias', DEFAULTS.alias);
  const coscli = resolveFromRoot(argValue('--coscli', DEFAULTS.coscli));
  const configPath = resolveFromRoot(argValue('--config', DEFAULTS.config));
  const routines = argValue('--routines', DEFAULTS.routines);
  const dryRun = hasFlag('--dry-run');
  const publicRead = hasFlag('--public-read');

  const secretId = process.env.COS_SECRET_ID || process.env.TENCENTCLOUD_SECRET_ID || process.env.TENCENT_SECRET_ID || '';
  const secretKey = process.env.COS_SECRET_KEY || process.env.TENCENTCLOUD_SECRET_KEY || process.env.TENCENT_SECRET_KEY || '';
  const sessionToken = process.env.COS_SESSION_TOKEN || process.env.TENCENTCLOUD_SESSION_TOKEN || process.env.TENCENT_SESSION_TOKEN || '';

  if (!existsSync(coscli)) throw new Error(`COSCLI not found: ${coscli}`);
  if (!existsSync(outDir)) throw new Error(`Output directory not found: ${outDir}`);
  if (!existsSync(join(outDir, 'videos'))) throw new Error(`Videos directory not found: ${join(outDir, 'videos')}`);
  if (!statSync(join(outDir, 'videos')).isDirectory()) throw new Error('videos path is not a directory');
  if (!dryRun && (!secretId || !secretKey)) {
    usage();
    throw new Error('Missing COS credentials in environment variables');
  }

  const summary = localSummary(outDir);
  // COSCLI sync preserves the source directory name, so sync the local
  // videos/ directory to the prefix root to produce <prefix>/videos/*.mp4.
  const videosDestination = `${buildCosUrl(alias, prefix)}/`;
  const rootDestination = buildCosUrl(alias, prefix);

  console.log(`Local output: ${outDir}`);
  console.log(`Videos: ${summary.converted}/${summary.rows}, ${summary.totalMiB} MiB, failed ${summary.failed}`);
  console.log(`COS bucket: ${bucket} (${region})`);
  console.log(`COS prefix: ${prefix || '(bucket root)'}`);
  console.log(`CDN base: ${cdnBase}`);
  console.log(`Object ACL: ${publicRead ? 'public-read' : 'bucket default'}`);
  if (summary.sampleOutputFile) {
    console.log(`Sample URL: ${cdnBase}/${summary.sampleOutputFile}`);
  }

  if (dryRun) {
    console.log('Dry run only. No COS upload was started.');
    return;
  }

  updateGeneratedCdnBase(outDir, cdnBase);
  writeCosConfig(configPath, { secretId, secretKey, sessionToken, bucket, alias, region });
  console.log(`Temporary COSCLI config: ${configPath}`);

  const videoMeta = 'Content-Type:video/mp4#Cache-Control:public,max-age=2592000,immutable';
  try {
    const syncArgs = [
      'sync',
      join(outDir, 'videos'),
      videosDestination,
      '--recursive',
      '--skip-dir',
      '--routines',
      routines,
      '--thread-num',
      '4',
      '--meta',
      videoMeta,
    ];
    if (publicRead) syncArgs.push('--acl', 'public-read');
    run(coscli, configPath, syncArgs);

    if (publicRead) {
      for (const outputFile of summary.videoOutputFiles) {
        run(coscli, configPath, [
          'object-acl',
          '--method',
          'put',
          buildCosUrl(alias, prefix, outputFile),
          '--acl',
          'public-read',
        ]);
      }
    }

    for (const fileName of ['manifest.json', 'manifest.csv', 'wechat-settings.txt', 'README.md', 'deployment.json']) {
      const source = join(outDir, fileName);
      if (existsSync(source)) {
        const cpArgs = [
          'cp',
          source,
          buildCosUrl(alias, prefix, fileName),
          '--meta',
          'Cache-Control:public,max-age=300',
        ];
        if (publicRead) cpArgs.push('--acl', 'public-read');
        run(coscli, configPath, cpArgs);
      }
    }

    run(coscli, configPath, ['du', rootDestination]);
  } finally {
    if (existsSync(configPath)) {
      unlinkSync(configPath);
    }
  }
  console.log('Upload complete.');
  console.log(`Set mini program liteVideoBase to: ${cdnBase}`);
}

try {
  main();
} catch (error) {
  console.error(error.message);
  process.exitCode = 1;
}
