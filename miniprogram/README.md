# Macify 微信小程序版

这是原 Chrome 扩展的原生微信小程序起步版。当前保留的核心功能：

- 航拍视频沉浸式首页
- 随机切换视频
- 时间、日期、天气、语录叠层
- 视频分类、天气城市、温度单位、代理域名设置
- 默认播放 Apple 竖屏 1080p H.264 MP4，托管失败时自动回退 Apple 官方 1080 H264 航拍源
- 轻量 MP4 模式可在 Apple 航拍库和高端免费航拍库之间切换

## 在微信开发者工具中打开

1. 打开微信开发者工具。
2. 导入小程序目录：`/Users/hui/Projects/Macify/miniprogram`。
3. 如果没有小程序 AppID，先使用测试号或游客模式。
4. 后端服务选择 **Use no cloud service**。

## 网络域名

开发阶段 `project.config.json` 里关闭了 URL 校验，方便先跑通界面。准备真机预览、上传或发布时，需要在微信公众平台配置合法域名：

- `https://api.open-meteo.com`
- `https://geocoding-api.open-meteo.com`
- `https://macify-videos-1430886267.cos.ap-beijing.myqcloud.com`，用于腾讯云 COS 承载的默认 1080p MP4 视频
- `https://sylvan.apple.com`，或你自己的 Cloudflare 反向代理域名，用于轻量源不可用时回退

默认视频源是已转码的 Apple 竖屏 1080p MP4，地址形如 `https://macify-videos-1430886267.cos.ap-beijing.myqcloud.com/macify/videos/<video-id>.mp4`。GitHub Pages 在中国大陆访问不稳定，已不再作为正式小程序视频源。小程序会在 Apple 轻量源播放失败时回退到 Apple 旧版 Aerial feed 的 `url-1080-H264` 字段；如果直连 Apple 视频在小程序里不可用，建议继续沿用原项目的 Cloudflare Worker 反向代理，在设置页打开“反向代理”并填写代理域名。代理路由需要覆盖 `/Videos/*`；仓库里的 `cloudflare-worker/worker.js` 已经允许 `/itunes-assets/*` 和 `/Videos/*`。

## 轻量视频源

小程序首页默认使用 Apple 轻量 MP4 URL。设置页里也保留了“内置 1080P视频”，方便回退到 Apple 官方 1080 源。轻量 MP4 模式下可选择两个素材库：

```text
Apple 轻量航拍:
https://macify-videos-1430886267.cos.ap-beijing.myqcloud.com/macify/videos/<apple-video-id>.mp4

高端免费航拍:
https://macify-videos-1430886267.cos.ap-beijing.myqcloud.com/macify-premium/videos/<source-video-id>.mp4
```

例如：

```text
https://macify-videos-1430886267.cos.ap-beijing.myqcloud.com/macify/videos/83C65C90-270C-4490-9C69-F51FE03D7F06.mp4
```

仓库里有一条完整的轻量 CDN 生成流水线。默认读取小程序正在使用的 `miniprogram/data/apple-aerial-1080.js`，把 Apple 横屏 `.mov` 裁成竖屏中间区域，再转成安卓微信更稳的 H.264 MP4：

```text
local-miniprogram-1080/
  videos/<video-id>.mp4
  manifest.json
  manifest.csv
  README.md
  wechat-settings.txt
```

第一次使用前需要安装 `ffmpeg`：

```bash
brew install ffmpeg
```

先检查将要转哪些视频，不实际转码：

```bash
npm run mini:lite -- --limit 5 --dry-run
```

生成一小批竖屏裁切、45 秒的 1080p 测试视频：

```bash
npm run mini:lite -- --height 1080 --profile main --maxrate 6000k --bufsize 12000k --limit 5 --cdn-base https://video.yourdomain.com/macify --out-dir local-miniprogram-1080
```

生成全部视频：

```bash
npm run mini:lite -- --height 1080 --profile main --maxrate 6000k --bufsize 12000k --cdn-base https://video.yourdomain.com/macify --out-dir local-miniprogram-1080
```

当前推荐参数是 `9:16 竖屏中心裁切 / 1080p 高 / 30fps / H.264 Main / fastdecode / yuv420p / 前 45 秒 / 6000k 峰值码率`。以当前 Apple 1080/2K AVC 源为例，输出约为 `606x1080`。如果要转完整视频，加 `--full`：

```bash
npm run mini:lite -- --height 1080 --profile main --maxrate 6000k --bufsize 12000k --full --cdn-base https://video.yourdomain.com/macify --out-dir local-miniprogram-1080
```

如果想用原 Chrome/macOS 4K 源做更高质量的竖屏裁切输入，可加 `--source apple4k`。输出仍会转成小程序友好的 MP4：

```bash
npm run mini:lite -- --source apple4k --limit 5 --cdn-base https://your-cdn.example.com/macify
```

如果想保留整张横屏画面而不是竖屏裁切，可使用旧式 fit 模式：

```bash
npm run mini:lite -- --mode fit --height 720 --limit 5 --cdn-base https://your-cdn.example.com/macify
```

生成后，把 `local-miniprogram-1080/videos/` 上传到腾讯云 COS 的 `macify/videos/` 路径，并用腾讯云 CDN 绑定自有备案 HTTPS 域名。仓库提供了 COSCLI 包装脚本，密钥只从环境变量读取：

```bash
COS_SECRET_ID=xxx COS_SECRET_KEY=yyy npm run mini:cos -- \
  --bucket macify-videos-1250000000 \
  --region ap-shanghai \
  --cdn-base https://video.yourdomain.com/macify
```

上传完成后，在小程序设置页选择“轻量 CDN”，填写 CDN 根域名 `https://video.yourdomain.com/macify`。微信公众平台的 `downloadFile` 合法域名填写根域名 `https://video.yourdomain.com`。

高端免费航拍素材使用独立清单 `miniprogram/data/premium-free-aerial-videos.js` 和独立 COS 前缀 `macify-premium/`，不要上传到 `macify/videos/`。每条新增视频都要先补齐来源、授权、分类、地点和中文说明，并通过校验：

```bash
npm run mini:premium:validate
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

首页会优先复用上一次已缓存的轻量 MP4。用户不主动换视频时，当前视频会循环播放；远程 MP4 会后台下载到小程序本地文件目录，之后重新进入小程序会继续播放这条本地文件。如果缓存被系统清理或不存在，才会随机选择一条视频并重新缓存。

设置页已移除“直接 URL”。临时测试单个外部视频请先放到受控 COS/CDN，并作为素材库条目或根域名规则接入；不要把 B 站页面、Pixabay 下载页、需要 Cookie/Referer/防盗链的地址直接塞进小程序 `<video>`。

## 和原 Chrome 版本的差异

- Chrome `topSites` 在小程序没有等价能力，已移除。
- Chrome extension storage 已替换为 `wx.getStorageSync` / `wx.setStorageSync`。
- Svelte 组件没有直接复用，页面改为原生 `wxml + wxss + js`。
- Zen mode、音乐、浏览器扩展后台脚本暂未迁移。
