# 呼吸Zen 微信小程序版

这是从原 Macify Chrome 扩展改造来的原生微信小程序。公开发布版面向中文用户，不展示素材来源选择，统一使用已审阅并记录授权来源的免费视频背景池。当前保留的核心功能：

- 航拍视频沉浸式首页
- 上下滑动切换视频
- 时间、日期、天气、语录叠层
- 视频分类、天气城市、温度单位设置
- 设置页左上标题显示低调的 `© 呼吸Zen` 授权记录入口
- 授权记录页只保留首屏概要区；点“公开素材”后才分层展示素材平台和单条视频来源
- 小程序包内保留 `OPEN_SOURCE_NOTICES.txt`，包含 Macify 的 MIT License 原文

## 在微信开发者工具中打开

1. 打开微信开发者工具。
2. 优先导入项目根目录：`/Users/hui/Projects/Macify`。根目录 `project.config.json` 已配置 `miniprogramRoot: "miniprogram/"` 和正式 AppID。
3. 如果直接导入小程序目录：`/Users/hui/Projects/Macify/miniprogram`，该目录下的 `project.config.json` 也已配置同一个正式 AppID。
4. 后端服务选择 **Use no cloud service**。

## 网络域名

开发阶段可在微信开发者工具里关闭 URL 校验，方便先跑通界面。准备真机预览、上传或发布时，需要在微信公众平台配置合法域名：

- `https://api.open-meteo.com`
- `https://geocoding-api.open-meteo.com`
- `https://macify-videos-1430886267.cos.ap-beijing.myqcloud.com`，用于腾讯云 COS 承载的默认 1080p MP4 视频

默认视频源是腾讯云 COS 上的竖屏 1080p MP4，地址形如 `https://macify-videos-1430886267.cos.ap-beijing.myqcloud.com/macify-premium/videos/<source-video-id>.mp4`。公开发布包不再引用或打包 Apple Aerial 清单。

## 上线检查

截至 2026-05-13，`huxizen.com` 的腾讯云 ICP 备案订单 `30177839176900401` 处于「腾讯云审核中」。当前上线前要优先保证审核电话能接通；腾讯云初审通过后，工信部短信核验要在 24 小时内完成。

备案和 CDN 完成前，代码默认视频源先继续使用 COS 默认域名：

```text
https://macify-videos-1430886267.cos.ap-beijing.myqcloud.com/macify-premium
```

微信公众平台后台需要配置：

```text
request 合法域名:
https://api.open-meteo.com
https://geocoding-api.open-meteo.com

downloadFile 合法域名（当前临时）:
https://macify-videos-1430886267.cos.ap-beijing.myqcloud.com
```

同时在微信公众平台检查小程序本体备案状态。腾讯云这单是 `huxizen.com` 的网站/域名 ICP 备案，主要用于后续 CDN 域名；小程序本体如果仍显示未备案，也必须在微信公众平台完成备案后才能最终发布。

备案通过并接入 CDN 后，再把 `miniprogram/utils/storage.js` 中 `DEFAULT_PREMIUM_FREE_AERIAL_VIDEO_BASE` 改为：

```text
https://video.huxizen.com/macify-premium
```

同时更新 `PREMIUM_FREE_AERIAL_SOURCE_VERSION`，并把微信公众平台 `downloadFile` 合法域名切到：

```text
https://video.huxizen.com
```

当前代码只使用城市天气请求和视频下载缓存；没有登录、定位、用户资料、支付、上传、订阅消息或用户行为上报。提交审核前，小程序后台隐私保护指引要按这个事实填写。

## 背景视频源

小程序首页默认使用统一背景视频池。用户侧只展示分类，不展示素材平台或内部素材库名称：

```text
https://macify-videos-1430886267.cos.ap-beijing.myqcloud.com/macify-premium/videos/<source-video-id>.mp4
```

视频、环境音和视频/音频混合关系的单一来源在仓库根目录 `content/`。`miniprogram/data/premium-free-aerial-videos.js` 是生成产物，不要手改。每条新增视频都要先在 `content/videos.json` 补齐来源、授权、分类、地点和中文说明，并通过校验：

```bash
npm run content:validate
npm run content:build
```

先生成 5-10 条小样，不上传：

```bash
node scripts/miniprogram/prepare-lite-videos.mjs --source premiumFreeAerial --out-dir local-miniprogram-premium-aerial --height 1080 --duration 45 --profile main --crf 20 --maxrate 8000k --bufsize 16000k --cdn-base https://macify-videos-1430886267.cos.ap-beijing.myqcloud.com/macify-premium
```

小样确认后再上传：

```bash
COS_SECRET_ID=xxx COS_SECRET_KEY=yyy node scripts/miniprogram/upload-cos-videos.mjs \
  --bucket macify-videos-1430886267 \
  --region ap-beijing \
  --out-dir local-miniprogram-premium-aerial \
  --prefix macify-premium \
  --cdn-base https://macify-videos-1430886267.cos.ap-beijing.myqcloud.com/macify-premium \
  --public-read
```

首页会优先复用上一次已缓存的轻量 MP4。用户不主动手势切换视频时，当前视频会循环播放；远程 MP4 会后台下载到小程序本地文件目录，之后重新进入小程序会继续播放这条本地文件。如果缓存被系统清理或不存在，才会随机选择一条视频并重新缓存。

设置页已移除“直接 URL”。临时测试单个外部视频请先放到受控 COS/CDN，并作为素材库条目或根域名规则接入；不要把 B 站页面、Pixabay 下载页、需要 Cookie/Referer/防盗链的地址直接塞进小程序 `<video>`。

新增视频或新增来源平台时，必须同步检查 `pages/licenses/licenses.js` 的来源平台声明，并确保授权记录页能分层展示当前视频的来源、许可证和授权备注。

## 和原 Chrome 版本的差异

- Chrome `topSites` 在小程序没有等价能力，已移除。
- Chrome extension storage 已替换为 `wx.getStorageSync` / `wx.setStorageSync`。
- Svelte 组件没有直接复用，页面改为原生 `wxml + wxss + js`。
- Zen mode、音乐、浏览器扩展后台脚本暂未迁移。
