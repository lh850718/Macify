# 呼吸Zen Flutter App

Flutter 版移动端工程。开发前先读：

- `PROJECT.md`
- `docs/release-readiness.md`
- `../macifytowechatmini.md`
- `../docs/content-pipeline.md`

内容源仍在仓库根目录 `content/`；`assets/content/*.json` 是生成产物，不要手改。

```bash
flutter test
flutter run
```

当前 Flutter 端已接入 `assets/content/`，首页骨架、同源语录、环境音匹配 resolver、前台视频 / 音频原型、呼吸页、天气请求和授权页会直接消费共享 JSON 或同源业务规则。隐私 / 权限边界记录在 `PROJECT.md` 和 `docs/release-readiness.md`，设置页不放独立关于区；生产级后台音频、振动和发布准备仍按 `PROJECT.md` 的阶段路线继续实现。
