# Shared Content Pipeline

`content/` is now the single source of truth for video, ambient audio, and video/audio mix data. The mini program data files and Flutter JSON assets are generated from it.

## Files To Edit

- `content/videos.json`: premium free aerial video records.
- `content/ambient-tracks.json`: ambient audio tracks and custom-mix labels.
- `content/video-audio-mixes.json`: explicit per-video audio mix overrides.
- `content/ambient-rules.json`: fallback tag/category/location matching rules.
- `content/config.json`: content version and default CDN bases.

Do not hand-edit generated files under `miniprogram/data/`, `flutter_app/assets/content/`, or `content-dist/`.

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

`content-dist/` is ignored by git and is the upload-ready remote content package for a future COS/CDN manifest flow.

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
