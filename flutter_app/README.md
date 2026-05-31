# 呼吸Zen Flutter App

Flutter 版移动端工程。开发前先读：

- `PROJECT.md`
- `../macifytowechatmini.md`
- `../docs/content-pipeline.md`

内容源仍在仓库根目录 `content/`；`assets/content/*.json` 是生成产物，不要手改。

```bash
flutter test
flutter run
```

当前 Flutter 端已接入 `assets/content/`，首页骨架和环境音匹配 resolver 会直接消费共享 JSON。视频播放器、音频引擎、后台音频、振动、天气和授权页仍按 `PROJECT.md` 的阶段路线继续实现。
