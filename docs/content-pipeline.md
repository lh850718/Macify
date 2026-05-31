# Shared Content Pipeline

`content/` is now the single source of truth for video, ambient audio, and video/audio mix data. The mini program data files and Flutter JSON assets are generated from it.

## Files To Edit

- `content/videos.json`: premium free aerial video records.
- `content/ambient-tracks.json`: ambient audio tracks and custom-mix labels.
- `content/video-audio-mixes.json`: explicit per-video audio mix overrides.
- `content/ambient-rules.json`: fallback tag/category/location matching rules.
- `content/config.json`: content version and default CDN bases.

Do not hand-edit generated files under `miniprogram/data/`, `flutter_app/assets/content/`, or `content-dist/`.

## Ambient Audio Names

Use `content/ambient-tracks.json` as the only editable source for audio display names. The same labels are generated for the mini program, Flutter local assets, and remote content package.

Current public names: `海浪`, `海浪海鸥`, `水下`, `森林`, `山林鸟鸣`, `溪流`, `瀑布`, `鸟鸣`, `风声`, `天空`, `雨声`, `炉火`, `收割机`.

`收割机` is reserved for special video matches such as `麦田收割`; it should not be added to user custom-mix choices unless that product decision changes.

## Current Video Pool

The current published shared pool has 60 videos: `Landscapes` 34, `Motion` 8, `AnimalsAndPlants` 13, and `Underwater` 5. `Cities` / `城市景观` was removed as a public category after manual screening on 2026-05-31.

Flutter bundled video assets are the 20 rows marked `必选` in `manual-video-screening-list.md`; rows marked `备选` remain published but should be fetched remotely / cached instead of bundled.

## Commands

```bash
npm run content:validate
npm run content:build
```

`npm run content:build` validates first, then writes:

- `miniprogram/data/content-config.js`
- `miniprogram/data/premium-free-aerial-videos.js`
- `miniprogram/data/ambient-content.js`
- `miniprogram/data/video-audio-mixes.js`
- `flutter_app/assets/content/*.json`
- `content-dist/*.json`

`content-dist/` is ignored by git and is the upload-ready remote content package for the COS/CDN manifest flow. The current package is published both at `macify-premium/*.json` and `macify-premium/content/*.json`; prefer `https://macify-videos-1430886267.cos.ap-beijing.myqcloud.com/macify-premium/content/content-manifest.json` for remote manifest checks.

`content-manifest.json` includes two index layers:

- `files`: generated JSON files with `bytes` and `sha256`.
- `media`: downloadable media files with relative remote `path`, `bytes`, and `sha256`.

The media manifest is generated from local production media when present:

- videos: `local-miniprogram-premium-aerial/videos/<video-id>.mp4`
- ambient audio: `local-miniprogram-ambient-audio/audio/<track-file>.mp3`

If a local media file is absent, that media item is omitted from `media` so content builds can still run in environments that only have JSON source files. Flutter treats missing media metadata as “download without strict hash/byte validation” and uses present metadata for cache validation.

## Adding Content

1. Add or update records in `content/videos.json`, `content/ambient-tracks.json`, `content/video-audio-mixes.json`, or `content/ambient-rules.json`.
2. Bump `content.config.contentVersion` in `content/config.json` when published video files or remote cache keys should invalidate.
3. Run `npm run content:validate`.
4. Run `npm run content:build`.
5. Test the mini program with the generated `miniprogram/data/*` files.

For a real Flutter app, either keep using `flutter_app/assets/content` or point generation at an existing app:

```bash
FLUTTER_CONTENT_DIR=/path/to/flutter_app/assets/content npm run content:build
```

Then include the generated directory in `pubspec.yaml`:

```yaml
flutter:
  assets:
    - assets/content/
```
