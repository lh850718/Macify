# Macify 微信小程序版

这是原 Chrome 扩展的原生微信小程序起步版。当前保留的核心功能：

- 航拍视频沉浸式首页
- 随机切换视频
- 时间、日期、天气、语录叠层
- 视频分类、天气城市、温度单位、代理域名设置

## 在微信开发者工具中打开

1. 打开微信开发者工具。
2. 导入小程序目录：`/Users/hui/Projects/Macify/miniprogram`。
3. 如果没有小程序 AppID，先使用测试号或游客模式。
4. 后端服务选择 **Use no cloud service**。

## 网络域名

开发阶段 `project.config.json` 里关闭了 URL 校验，方便先跑通界面。准备真机预览、上传或发布时，需要在微信公众平台配置合法域名：

- `https://api.open-meteo.com`
- `https://geocoding-api.open-meteo.com`
- `https://sylvan.apple.com`，或你自己的 Cloudflare 反向代理域名

如果直连 Apple 视频在小程序里不可用，建议继续沿用原项目的 Cloudflare Worker 反向代理，在设置页打开“反向代理”并填写代理域名。

## 轻量视频源

小程序首页可以切换到“轻量 CDN”。轻量源使用固定文件名：

```text
https://your-cdn.example.com/videos/<video-id>.mp4
```

例如：

```text
https://your-cdn.example.com/videos/4C108785-A7BA-422E-9C79-B0129F1D5550.mp4
```

可以用仓库里的脚本先生成一小批 720p、30 秒的测试视频：

```bash
node scripts/miniprogram/prepare-lite-videos.mjs --limit 5 --height 720 --duration 30
```

只看命令、不实际转码：

```bash
node scripts/miniprogram/prepare-lite-videos.mjs --limit 5 --dry-run
```

生成后，把 `local-miniprogram-lite/videos/` 上传到你的 CDN，然后在小程序设置页选择“轻量 CDN”，填写 CDN 根域名，例如 `https://your-cdn.example.com`。

## 和原 Chrome 版本的差异

- Chrome `topSites` 在小程序没有等价能力，已移除。
- Chrome extension storage 已替换为 `wx.getStorageSync` / `wx.setStorageSync`。
- Svelte 组件没有直接复用，页面改为原生 `wxml + wxss + js`。
- Zen mode、音乐、浏览器扩展后台脚本暂未迁移。
