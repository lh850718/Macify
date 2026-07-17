#!/usr/bin/env node
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import vm from 'node:vm';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
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
      if (request.startsWith('.')) return loadCommonJs(resolve(dirname(resolved), request));
      throw new Error(`Unsupported require("${request}")`);
    },
  };

  vm.runInNewContext(readFileSync(resolved, 'utf8'), sandbox, { filename: resolved });
  return module.exports;
}

const { normalizeAmbientMixVolumes } = loadCommonJs(
  resolve(root, 'miniprogram/data/ambient-audio.js'),
);

function normalizedVolumes(values) {
  return Array.from(normalizeAmbientMixVolumes(
    values.map((volume, index) => ({
      id: `track-${index}`,
      volume,
    })),
  ), (track) => Number(track.volume.toFixed(4)));
}

assert.deepEqual(normalizedVolumes([0.4, 0.3, 0.1]), [1, 0.75, 0.25]);
assert.deepEqual(normalizedVolumes([0.54, 0.15]), [1, 0.2778]);
assert.deepEqual(normalizedVolumes([0.4]), [1]);
assert.deepEqual(normalizedVolumes([0, 0, 0]), []);

console.log('Ambient volume normalization checks passed.');
