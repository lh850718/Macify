# 呼吸Zen Flutter App 项目文档

本文是呼吸Zen Flutter App 版的唯一主项目文档。新窗口、新接手者或自动化任务在开发 Flutter 前，必须先阅读本文，并把本文当作 Flutter 侧的事实来源。

## 必须先读

- `flutter_app/` 是后续 Flutter App 的开发目录。
- 当前 `flutter_app/` 还不是正式 Flutter 工程；现有内容只是由共享内容管线生成的 `assets/content/*.json` 资产。
- Flutter App 的默认目标是复刻当前微信小程序体验。除非用户明确要求 Flutter 版本差异，否则功能、交互、数据策略、审美标准都必须和小程序一致。
- 任何未来 Flutter 功能变更、资源策略变更、内容结构变更、平台能力结论、依赖选择、权限/隐私边界变化、远端同步策略变化，都必须同步更新本 `PROJECT.md`。
- 每次开发前必须核对小程序主文档顶部“当前硬性原则”，并检查 Flutter 是否产生功能差异。
- 不允许只改代码不更新项目文档。未来任何更新必须同步更新本文档。

必须经常核对的文档：

```text
Flutter 主项目文档: /Users/hui/Projects/Macify/flutter_app/PROJECT.md
小程序主项目文档: /Users/hui/Projects/Macify/macifytowechatmini.md
小程序 README: /Users/hui/Projects/Macify/miniprogram/README.md
根 README: /Users/hui/Projects/Macify/README.md
共享内容管线附录: /Users/hui/Projects/Macify/docs/content-pipeline.md
```

相对链接：

- [小程序主项目文档](../macifytowechatmini.md)
- [小程序 README](../miniprogram/README.md)
- [根 README](../README.md)
- [共享内容管线附录](../docs/content-pipeline.md)

`macifytowechatmini.md` 是小程序事实来源；如果本文和小程序主文档冲突，先以小程序主文档顶部“当前硬性原则”为准，并同步修正本文。

## 产品目标

Flutter App 要完整复刻小程序当前体验，包括但不限于：

- 沉浸式视频首页。
- 上下滑动切换视频。
- 首页、呼吸页和纯视频模式的视频播放体验。
- 首页时间、日期、天气、语录叠层。
- 点击语录切换语录。
- 点击视频标题打开视频信息浮层。
- 点击天气打开天气详情。
- 单击背景进入/退出纯视频模式。
- 双击背景收藏/取消收藏当前视频。
- 设置页。
- 分类播放范围。
- 收藏播放范围。
- 天气城市和温度单位设置。
- 显示项开关。
- 环境音 `♪` 开关。
- 视频匹配环境音模式。
- 自定义混音模式。
- 自定义混音试听和音量调节。
- 呼吸页。
- 默认呼吸节奏。
- 自定义呼吸练习。
- 呼吸触感。
- 颂钵音。
- 授权和素材来源记录。

Flutter App 允许并必须增强的能力：

- 锁屏/后台持续播放环境音。
- 锁屏/后台振动能力攻关。
- 本地资源优先。
- 启动后远端内容校验。
- 远端新增内容按需下载并长期缓存。
- 最小化腾讯云 COS 流量。

除非用户明确批准，Flutter 不得删减小程序已有体验。任何 Flutter 独有差异都必须写入本文，并说明为什么允许差异。

## 共享内容源

`content/` 是视频、环境音、视频/音频混合方案的唯一来源。小程序和 Flutter 都必须从同一内容源生成自己的运行时数据。

只允许维护这些源文件：

```text
/Users/hui/Projects/Macify/content/videos.json
/Users/hui/Projects/Macify/content/ambient-tracks.json
/Users/hui/Projects/Macify/content/video-audio-mixes.json
/Users/hui/Projects/Macify/content/ambient-rules.json
/Users/hui/Projects/Macify/content/config.json
```

不要手改生成产物：

```text
/Users/hui/Projects/Macify/miniprogram/data/premium-free-aerial-videos.js
/Users/hui/Projects/Macify/miniprogram/data/ambient-content.js
/Users/hui/Projects/Macify/miniprogram/data/video-audio-mixes.js
/Users/hui/Projects/Macify/flutter_app/assets/content/*.json
/Users/hui/Projects/Macify/content-dist/*.json
```

后续新增视频、音频或调整视频/音频匹配关系时，只改 `content/*.json`，然后运行：

```bash
npm run content:validate
npm run content:build
```

生成结果：

- 小程序继续读取 `miniprogram/data/*.js`。
- Flutter 读取 `flutter_app/assets/content/*.json`。
- 未来远端内容包使用 `content-dist/*.json` 上传 COS/CDN。

Flutter 不得在 Dart 里单独维护视频清单、音频清单、混音覆盖或匹配规则。Flutter 只能实现 resolver，消费同一份 JSON 数据。

音频匹配规则必须保持：

1. `video-audio-mixes.json` 显式匹配优先。
2. 显式 `mix: null` 表示该视频明确无环境音。
3. 没有显式匹配时，按 `ambient-rules.json` 的标签/分类/地点规则匹配。
4. 仍无匹配时，当前视频无环境音。

## 资源策略

Flutter App 需要同时兼顾安装包体验、离线体验和 COS 流量成本。

首包资源：

- 内置全部正式环境音。
- 人工精选 20-30 条视频作为首包视频。
- 首包视频必须审美质量高、分类分布合理、体积可控。
- 当前不把全部 99 条视频直接打入首包；本地 99 条轻量视频约 831MB，全部打包会显著影响安装体积和商店分发。
- 当前正式环境音约 27MB，可以内置。

远端资源：

- 远端 `content-manifest.json` 是权威内容索引。
- 启动后可以轻量校验远端 manifest 和 JSON 差异。
- 不允许首次打开 App 就批量下载所有远端视频。
- 用户先播放首包本地视频。
- 首包本地视频完整播放一轮后，再考虑按需下载远端新增视频。
- 视频或音频下载一次后长期使用本地缓存，不再重复拉取 COS。
- 远端 manifest 标记删除或资源版本变更时，本地缓存必须同步清理或更新。
- 下载中断必须可恢复或重试，不能让播放队列卡死。

资源状态建议分层：

```text
bundled: 首包内置资源
remote: 远端 manifest 可用但尚未下载
cached: 已下载到本地缓存
removed: 远端已删除，本地应清理
```

应用商店版和自有安装包版都要考虑：

- iOS 可承受较大首包，但仍要避免安装包过大影响安装转化。
- Android 商店版需要预留 Play Asset Delivery 或等价资源分发路线。
- 自有安装包可以更激进地内置资源，但也不能牺牲安装体验。

## 播放体验硬性要求

Flutter 必须复刻小程序当前“无明显断点”的播放体验。

视频播放：

- 前台视频不能依赖硬 `loop`。
- 当前视频接近结尾时，必须预热第二个同源视频实例。
- 旧视频保持不透明兜底，新视频从头开始淡入覆盖。
- 交叉淡入淡出目标约 3 秒。
- 循环处不能黑屏、不能暗一下、不能硬切。
- 用户主动上下滑切换视频时，也要平滑切换，避免突兀闪动。

环境音播放：

- 音频必须支持多轨混音。
- 少数视频可以同时播放多条音轨。
- 每条音轨必须有独立 channel。
- 每个 channel 必须维护自己的 current 播放器、next 播放器、循环定时器、淡入淡出状态和目标音量。
- 不允许用一个全局 current/next 管理所有音轨。
- 不允许使用播放器硬 `loop=true` 作为最终循环方案。
- 每条音轨接近结尾时，必须启动同源下一实例，旧实例淡出，新实例淡入。
- 音频交叉淡入淡出目标约 2.5-3 秒。
- 切换视频或混音时，仍存在的 channel 应保留并调整音量；新增 channel 淡入；移除 channel 淡出。
- 新视频无环境音时，只能临时淡出当前音频，不能永久关闭用户的环境音开关意图。

锁屏/后台播放：

- 锁屏/后台不能退化成单个 MP3 文件循环播放。
- 锁屏/后台必须尽量保持和前台相同的多轨混音语义。
- 后台循环也要避免每一分钟或每段音频结尾出现断点。
- 如果 Flutter/Dart 后台 timer 不可靠，必须升级到 iOS/Android 原生后台音频实现。

优先技术方向：

- Flutter 层可先评估 `audio_service` 作为后台音频入口。
- Flutter 层可先评估 `just_audio` 管理多播放器原型。
- iOS 必须评估 `AVAudioSession` playback + background audio。
- Android 必须评估 Media3 `MediaSessionService` / foreground service。
- 若第三方 Flutter 插件无法满足多轨交叉淡入淡出和锁屏稳定性，必须写原生桥接。

## 锁屏与振动

Flutter App 做锁屏/后台能力，是从小程序转 App 的核心原因之一。

平台目标：

- iOS 和 Android 同步开发。
- 锁屏音频必须作为核心能力攻关。
- 锁屏/后台振动也必须作为核心能力攻关。
- 第一阶段必须做 iOS/Android 原生 spike，验证后台/锁屏振动的真实可行性。

振动策略：

- 呼吸触感是呼吸 App 的核心体验，不可轻易降级。
- 前台必须支持按呼吸节奏触发振动。
- 锁屏/后台必须优先尝试按呼吸节奏触发振动。
- 如果 iOS 或 Android 对后台持续振动有系统硬限制，必须在本文档记录：
  - 平台。
  - 系统限制。
  - 验证方式。
  - 失败现象。
  - 可接受的最接近替代方案。

锁屏替代方案只能在平台确认硬限制后讨论，不能在实现前默认放弃。

## 功能一致性清单

除非用户特别批准，Flutter 必须实现并保持与小程序一致：

| 功能 | Flutter 要求 |
| --- | --- |
| 统一背景视频池 | 必须实现，只展示分类，不展示素材来源选择 |
| 视频分类 | 必须实现 `全部`、`收藏`、`自然景观`、`城市景观`、`动植物`、`运转`、`水下景观` |
| 上下滑切换视频 | 必须实现，向上下一条，向下回到上一条 |
| 横向导航 | 必须实现首页、呼吸页、设置页之间的自然切换 |
| 纯视频模式 | 必须实现，单击背景隐藏/恢复 UI |
| 双击收藏 | 必须实现，首页、呼吸页、纯视频模式都支持 |
| 收藏播放范围 | 必须实现，无收藏时提示用户先收藏 |
| 随机播放策略 | 必须避免同一范围内快速重复 |
| 视频循环 | 必须双实例交叉淡入淡出，不能硬 loop |
| 视频信息浮层 | 必须实现，基于标题点击位置展开 |
| 天气 | 必须实现当前天气和 7 天预报，失败时有兜底显示 |
| 语录 | 必须实现展示和点击切换 |
| 设置页 | 必须保持小程序的紧凑策略 |
| 环境音开关 | 必须实现首页和呼吸页共用 `♪` 状态 |
| 视频匹配环境音 | 必须实现，使用共享内容源 resolver |
| 自定义混音 | 必须实现，最多 5 个声音，支持试听和音量 |
| 多轨混音 | 必须实现，每轨独立 channel |
| 呼吸页 | 必须实现默认呼吸和自定义练习 |
| 呼吸节奏设置 | 必须实现默认节奏和自定义练习节奏 |
| 呼吸触感 | 必须实现，后台/锁屏继续攻关 |
| 颂钵音 | 必须实现，App 版需评估后台行为 |
| 授权记录 | 必须实现，保留 Macify MIT 和素材来源记录 |
| 隐私边界 | 必须同步记录，新增统计/登录/定位前先更新文档 |

小程序中明确废弃的能力，Flutter 也不得恢复：

- 不展示 Apple 源。
- 不打包或公开使用 Apple 清单。
- 不恢复 NPS / publicDomain 路线。
- 不恢复直接 URL 视频源。
- 不把未审阅、未确认授权、未确认文案的视频加入正式池。

## 开发顺序

第一阶段：创建真实 Flutter 工程。

- 在 `flutter_app/` 内初始化正式 Flutter 工程。
- 保留现有 `assets/content/`。
- 配置 `pubspec.yaml` 读取 `assets/content/`。
- 建立基础目录结构和平台工程。

第二阶段：接入共享内容。

- 实现 `ContentRepository`。
- 读取 `content-manifest.json`、`config.json`、`videos.json`、`ambient-tracks.json`、`ambient-rules.json`、`video-audio-mixes.json`。
- 实现视频筛选、分类、收藏 key、播放范围。
- 实现 Flutter 版 `AmbientResolver`。

第三阶段：本地资源与缓存层。

- 定义 bundled / remote / cached / removed 状态。
- 支持首包内置视频和音频。
- 支持远端 manifest 校验。
- 支持按需下载远端新增资源。
- 支持远端删除和版本变更后的本地清理。

第四阶段：视频体验。

- 实现沉浸式首页。
- 实现双 slot 视频播放。
- 实现循环交叉淡入淡出。
- 实现上下滑切换、播放序列、回退序列和避免快速重复。
- 实现纯视频模式。

第五阶段：信息层和设置。

- 实现时间、日期、天气、语录。
- 实现视频信息浮层和天气详情。
- 实现设置页。
- 实现分类、收藏、显示项、天气城市、温度单位。

第六阶段：音频体验。

- 实现环境音开关。
- 实现视频匹配环境音。
- 实现自定义混音。
- 实现多轨独立 channel。
- 实现每轨独立交叉淡入淡出循环。
- 实现切换视频时音频平滑过渡。

第七阶段：后台音频和振动 spike。

- iOS 验证锁屏多轨音频、交叉淡入淡出和振动。
- Android 验证锁屏多轨音频、交叉淡入淡出和振动。
- 记录平台限制、插件限制、原生桥接需求。
- 决定是否升级到原生音频引擎。

第八阶段：呼吸页。

- 实现默认呼吸。
- 实现自定义练习。
- 实现倒计时、完成动画、恢复默认呼吸。
- 实现前台触感。
- 接入后台/锁屏振动 spike 结果。
- 接入颂钵音。

第九阶段：授权、隐私和发布。

- 实现授权记录页。
- 审核隐私权限。
- 明确 iOS/Android 权限说明。
- 处理 App Store / Google Play / 自有安装包的资源打包差异。

## 文档维护规则

本文档不是一次性说明，而是 Flutter App 的持续项目记录。

必须更新本文档的情况：

- 完成任何 Flutter 功能。
- 修复任何与小程序行为不一致的问题。
- 决定 Flutter 和小程序允许存在某个差异。
- 改变资源打包策略。
- 改变远端 manifest 或缓存策略。
- 改变内容 JSON 结构。
- 改变播放器、音频、后台服务或振动技术路线。
- 新增、删除或替换 Flutter 依赖。
- 改变 iOS/Android 权限、后台模式、隐私声明或统计边界。
- 小程序主文档顶部“当前硬性原则”发生变化，且可能影响 Flutter。

更新规则：

- 先更新代码或内容时，必须在同一轮同步更新本文档。
- 如果发现本文档和 `macifytowechatmini.md` 冲突，必须先核对小程序顶部硬性原则，再修正文档。
- 如果 Flutter 因平台限制无法完全复刻小程序行为，必须在本文记录限制、验证方式和最终产品决策。
- 不允许把关键决策只写在聊天记录里。
- 不允许把密钥、SecretId、SecretKey、登录密码写入本文档。

## 当前状态

截至当前文档创建时：

- `flutter_app/` 不是正式 Flutter 工程。
- `flutter_app/assets/content/*.json` 已由 `npm run content:build` 生成。
- 小程序已经接入共享内容源。
- Flutter 尚未实现 Dart 代码、播放器、缓存、后台音频、振动或 UI。
- 下一步应先创建正式 Flutter 工程，并保留/接入 `assets/content/`。

## 验收标准

新窗口只读本文档后，必须能回答：

- Flutter App 要复刻小程序哪些功能。
- 哪些能力是 Flutter 版额外增强。
- 视频、音频、混音数据以后从哪里改。
- 为什么不能两端各维护一套数据。
- 首包资源和远端资源怎么分层。
- COS 流量如何最小化。
- 锁屏音频和振动要怎么攻关。
- 每次更新文档要遵守什么规则。

