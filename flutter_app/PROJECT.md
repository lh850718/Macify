# 呼吸Zen Flutter App 项目文档

本文是呼吸Zen Flutter App 版的唯一主项目文档。新窗口、新接手者或自动化任务在开发 Flutter 前，必须先阅读本文，并把本文当作 Flutter 侧的事实来源。

## 必须先读

- `flutter_app/` 是 Flutter App 的开发目录，当前已初始化为正式 Flutter 工程。
- `flutter_app/assets/content/*.json` 是由共享内容管线生成的资产，不要手改。
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
- 自定义混音试听和百分比音量调节。
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
- 当前不把全部 60 条公开视频直接打入首包；本地历史 99 条轻量视频约 831MB，全部打包会显著影响安装体积和商店分发。
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
| 视频分类 | 必须实现 `全部`、`收藏`、`自然景观`、`动植物`、`运转`、`水下景观` |
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
| 自定义混音 | 必须实现，最多 5 个声音，支持试听和百分比音量 |
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

截至 2026-05-25：

- `flutter_app/` 已初始化为正式 Flutter 工程，当前项目名为 `huxi_zen`，移动端平台为 iOS 和 Android。
- `pubspec.yaml` 已配置读取 `assets/content/`。
- `flutter_app/assets/content/*.json` 已由 `npm run content:build` 生成。
- 小程序已经接入共享内容源。
- Flutter 已实现第一版 Dart 内容接入：`ContentRepository` 会读取 `content-manifest.json`、`config.json`、`videos.json`、`ambient-tracks.json`、`ambient-rules.json`、`video-audio-mixes.json`；`content-manifest.json` 现在同时包含 JSON 文件 hash 和媒体文件 `media.videos` / `media.ambientTracks` 的 `path`、`bytes`、`sha256` 元数据。
- Flutter 已实现第一版 `AmbientResolver`，规则保持小程序语义：显式 `video-audio-mixes` 优先，显式 `mix: null` 表示无音频，没有显式匹配时按 `ambient-rules` 匹配。
- Flutter 已实现内容驱动的首页骨架：读取公开视频、内存收藏、上下滑队列、标题信息浮层、`♪` 状态和环境音标签。
- Flutter 首页底部已按小程序普通状态收紧为右下角 `···` 和 `♪` 两个入口；分类条、视频计数和爱心按钮不在首页普通状态展示。双击背景收藏/取消收藏，并用页面内小字提示。
- Flutter 已实现第一版设置页骨架：显示开关、天气城市/温度单位占位、背景视频播放范围、视频背景音模式和自定义混音选择。自定义混音已支持最多 5 个声音、每轨百分比滑杆、设置页试听和 `shared_preferences` 持久化；保存后首页 / 呼吸页 `♪` 会按自定义比例播放多轨混音。收藏、播放范围和当前设置页已有的偏好已接入本地持久化；`♪` 仍按小程序原则作为本次使用的开声意图，启动默认静音。
- 当前已新增 `video_player 2.11.1` 作为第一阶段前台视频播放原型依赖；已新增 `just_audio 0.10.5` 作为第一阶段前台环境音播放原型依赖；已新增 `shared_preferences 2.5.5` 保存本地收藏和偏好；已新增 `path_provider 2.1.5` 获取 App 支持目录下的长期媒体缓存目录；已新增 `crypto 3.0.7` 为媒体下载提供可选 sha256 校验；Android 已声明 `INTERNET` 权限用于远端 COS 视频和音频播放。后续如果插件无法满足双实例交叉淡入淡出、多轨混音、预热、后台行为或平台稳定性，需要继续记录限制并评估原生桥接。
- Flutter 已实现第一版双 slot 视频背景原型：用户不主动上滑/下滑时，当前视频循环播放，不自动切到下一条；接近结尾约 3.5 秒时预热同源下一实例，新实例用约 3 秒淡入覆盖，旧实例保持不透明兜底；主动切换视频时才进入上一条/下一条，并使用短淡入过渡。视频播放端已能按资源状态播放 remote / cached / bundled。
- Flutter 已实现第一版前台环境音播放原型：`♪` 表示用户开声意图；当前视频无可用环境音时只临时无声，不关闭用户意图；有环境音时按 `AmbientResolver` 播放远端 COS MP3。多轨 mix 中每条音轨使用独立 channel；每个 channel 独立维护 current/next 播放器、循环 timer、淡入淡出和目标音量；切视频时保留仍存在的 channel，新增 channel 淡入，移除 channel 淡出。当前仍是前台原型，尚未做后台音频。
- 2026-05-21 已修复第一版前台环境音原型的静音问题：`just_audio` 的 `play()` 不再被 `await` 阻塞，播放器完成 `setUrl` 后立即异步播放，音量淡入可以正常执行。
- 2026-05-21 已加固第一版双 slot 视频背景原型的释放流程：页面 detach、停播、切换和循环预热交叠时，旧 `VideoPlayerController` 只走一次释放任务；异步释放完成后会重新检查 `mounted` 和 generation，避免已释放页面重新启动监控 timer。针对 `video_player` 在 `completed` 事件里异步 `pause().then(...seekTo)` 的内部行为，旧 controller 释放前增加短退场缓冲，避免 `seekTo` 回调落到已 dispose controller 上。
- 2026-05-21 已新增第一版媒体资源状态模型：`MediaResourceResolver` 会把视频和环境音解析为 `bundled` / `cached` / `remote` / `removed`，优先级为 `removed` > `cached` > `bundled` > `remote`，确保远端删除或版本变更能先阻止播放旧缓存。`CrossfadeVideoBackground` 和 `AmbientResolver` 已能消费该资源 resolver，默认无缓存时仍使用 COS 远端资源。
- 2026-05-21 已新增第一版媒体缓存索引：`MediaCacheIndex` 使用 `shared_preferences` 持久化已缓存的视频路径、已缓存的环境音路径、远端标记删除的视频和环境音，并可转换为 `MediaResourceCatalog` 供资源 resolver 使用。索引层负责失效路径清理和 removed 本地文件清理；下载、原子替换和可选 hash 校验由 `MediaDownloadService` 负责。
- 2026-05-21 已新增第一版远端 manifest 检查和单文件下载能力：`RemoteContentSyncService` 能拉取远端 `content-manifest.json` 并比较 `contentVersion`、新增/变化/删除文件；`MediaDownloadService` 能把单个视频或环境音下载到临时文件，校验字节数和可选 sha256 后原子替换为缓存文件，并返回更新后的 `MediaCacheIndex`。当前尚未做断点续传或批量下载。
- 2026-05-21 视频和音频播放端已预留资源状态入口：`CrossfadeVideoBackground` 可按 `MediaResourceStatus` 使用远端 URL、包内 asset 或本地缓存文件；`AmbientAudioEngine` 可按音频 URI 选择 `setUrl`、`setAsset` 或 `setFilePath`。默认状态仍走 COS 远端播放，不改变当前可听见的环境音行为。
- 2026-05-21 已接入可选的启动后轻量远端 manifest 检查：App 默认不配置远端 manifest URL，因此仍离线优先、不主动联网；未来配置 `remoteManifestUri` 后，会在本地内容加载完成后后台检查远端 manifest，失败不影响首页启动。
- 2026-05-21 首页已开始读取 `MediaCacheIndex` 并把缓存索引转换为 `MediaResourceCatalog` 交给 `MediaResourceResolver` 和 `AmbientResolver`，因此已缓存的视频和环境音会优先使用本地文件；未缓存资源仍回落到 COS 远端播放。
- 2026-05-21 已新增第一版远端视频按需预取策略 `MediaPrefetchPolicy`：只有当前播放范围内存在 bundled/cached 本地视频，且这些本地视频已经完整看过一轮后，才允许挑选下一条 remote 视频进入下载队列；策略会跳过 removed、当前正在播放和本轮已请求过的视频，避免首次启动就批量拉取远端资源。
- 2026-05-21 已把视频预取策略接入真实单文件下载队列 `MediaVideoPrefetchQueue`：前台视频播放到接近结尾并触发同源交叉循环时，首页会记录该视频已完成一轮；若策略允许，则用 `MediaDownloadService` 下载一条 remote 视频到 App 支持目录的 `media-cache/videos/`，成功后保存 `MediaCacheIndex` 并刷新播放端 resolver。下载成功的视频会立即成为新的 cached 本地资源，因此下一条远端下载必须等这条新缓存视频也完整播过一轮后才会继续，避免批量拉取 COS。
- 2026-05-21 已新增缓存索引失效文件清理：启动读取 `MediaCacheIndex` 后会检查 cached 视频和环境音文件是否仍存在，若文件已被系统或用户清掉，则从索引移除并保存，避免播放端拿到已经不存在的本地路径；若索引里同时存在 cached 路径和 removed 标记，则会删除对应本地文件，并保留 removed 状态阻止再次播放旧缓存。
- 2026-05-21 `MediaDownloadService` 已支持可选 `expectedSha256` 校验：下载先落到 `.download` 临时文件，字节数和 sha256 都通过后才原子替换缓存文件；校验失败会删除临时文件，不污染缓存索引。
- 2026-05-25 共享内容构建已扩展媒体 manifest：`npm run content:build` 会从 `local-miniprogram-premium-aerial/videos/<video-id>.mp4` 和 `local-miniprogram-ambient-audio/audio/<track-file>.mp3` 读取本地正式媒体文件，向 `content-manifest.json` 写入 `media.videos` 和 `media.ambientTracks`，每条包含远端相对 `path`、`bytes`、`sha256`。当前已生成 60 条视频和 13 条环境音的媒体元数据。
- 2026-05-25 Flutter `ContentManifest` 已解析 `media` 元数据，`MediaVideoPrefetchQueue` 下载远端视频时会把 manifest 中对应视频的 `bytes` 和 `sha256` 传给 `MediaDownloadService` 校验，缓存写入前会验证真实 MP4 内容。
- 2026-05-25 远端 manifest 比较已覆盖媒体资源：`RemoteContentCheck` 会比较 `media.videos` 和 `media.ambientTracks`，识别新增/变更和删除的视频、环境音资源。首页启动后的远端检查会把这些媒体变化应用到 `MediaCacheIndex`：删除的资源进入 `removed` 并清理本地文件，变更的资源会删除旧缓存但允许重新走 remote/后续重下。
- 2026-05-25 已修复视频播放端 removed fallback：当 resolver 返回 `MediaResourceStatus.removed` 时，`CrossfadeVideoBackground` 不再回落到远端 URL 播放同一 ID，避免远端已删除或版本变更后继续播放旧资源。
- 2026-05-25 已新增第一版环境音按需下载队列 `MediaAmbientDownloadQueue`：用户打开 `♪` 且当前视频有可播放 mix 时，只下载当前 mix 实际用到的 MP3，使用 `content-manifest.json` 中 `media.ambientTracks` 的 `bytes` / `sha256` 做缓存写入校验；下载成功后刷新同一份 `MediaCacheIndex` 和播放端 resolver，`AmbientAudioEngine` 会在音轨 URL 从 remote 变为 cached 时平滑替换 channel。cached / bundled / removed 音轨不会重复下载；环境音下载队列和视频预取队列提交结果时都会基于首页最新 `MediaCacheIndex` 合并，避免两个队列并发完成时互相覆盖缓存项。
- 2026-05-25 已把 13 条正式环境音加入 Flutter 首包资源：MP3 位于 `assets/media/audio/`，`pubspec.yaml` 已声明该目录；首页会从 `assets/media/bundled-media.json` 读取 bundled 环境音 catalog，所以当前正式环境音默认从 asset 播放，远端下载队列主要用于未来新增但尚未进入首包的音轨。若远端 manifest 标记删除，`removed` 仍优先于 bundled，避免继续播放已删除资源。
- 2026-05-31 环境音显示名已统一到共享内容源 `content/ambient-tracks.json`，小程序生成文件、Flutter 本地内容资产和远端 `content-dist` 使用同一套简洁名称：`海浪`、`海浪海鸥`、`水下`、`森林`、`山林鸟鸣`、`溪流`、`瀑布`、`鸟鸣`、`风声`、`天空`、`雨声`、`炉火`、`收割机`。`收割机` 仍只用于特殊视频匹配，不进入自定义混音候选。手工筛选表 `manual-video-screening-list.md` 已同步这些名称和默认音量比例。
- 2026-05-31 已按 `manual-video-screening-list.md` 完成首包 bundled 视频筛选：共享公开池保留 60 条，删除 39 条；`城市景观` 9 条整类删除，分类入口同步移除。`assets/media/bundled-media.json` 记录 20 条必选内置视频和 13 条内置环境音，备选 40 条仅走远端 / 缓存；视频文件位于 `assets/media/videos/`，总视频体积约 189MB，当前 `assets/media/` 总体积约 217MB。`loadBundledMediaCatalog` 会读取该资源清单并过滤不在共享内容源里的 ID，首页再把 bundled catalog 与 `MediaCacheIndex` 合并；`removed` 仍优先于 bundled。
- 2026-05-31 已完成 COS 远端发布与物理清理：`macify-premium/videos/` 下 39 条筛掉视频对象已删除并公开 URL 不再返回 200；60 条保留视频公开 URL 全部返回 200。`content-dist/*.json` 已上传到 `macify-premium/` 和 `macify-premium/content/` 两套路径，推荐远端 manifest URL 为 `https://macify-videos-1430886267.cos.ap-beijing.myqcloud.com/macify-premium/content/content-manifest.json`；远端 `manifest.json` 已刷新为 60 条，不再包含已删除视频。
- 2026-05-31 已清理本地正式视频输出目录 `local-miniprogram-premium-aerial/videos/`，删除 39 个不在当前公开池里的历史 MP4，目录现保留 60 个文件约 629MB。环境音循环衔接也已加强：小程序首页 / 设置试听、Flutter 前台 `AmbientAudioEngine` 和 Android `BackgroundAudioService` 的 loop 交叉淡入淡出从 2.6 秒扩到 6 秒，并按当前播放进度重新计算下一次 loop；Flutter / Android 增加播放结束 fallback，避免计时器错过后出现明显断一下再重启。
- 2026-05-25 Android 首次 debug 构建与运行验证已通过：`flutter build apk --debug` 成功生成 `build/app/outputs/flutter-apk/app-debug.apk`；`flutter run -d emulator-5554 --debug --no-resident` 已在 `Pixel_8_API_36` 模拟器安装并启动 App；ADB 确认前台焦点为 `com.huxizen.huxi_zen/.MainActivity`，截图验证首页可正常渲染首包 bundled 视频。首次构建过程中本机 Android SDK 自动补齐 Platform 35。`flutter doctor -v` 显示 Android toolchain、Xcode 和连接设备可用，但 Network resources 对 `https://cocoapods.org/` 有 TLS 握手告警，后续做 iOS CocoaPods 相关操作时需复查网络。
- 2026-05-25 已新增第一版后台音频/振动能力探针：Dart `PlatformCapabilityProbe` 通过 `huxi_zen/platform_capabilities` MethodChannel 读取原生平台报告，并可触发一次前台 haptic pulse 用于设备验证。Android 已声明 `VIBRATE`、`FOREGROUND_SERVICE`、`FOREGROUND_SERVICE_MEDIA_PLAYBACK`、`POST_NOTIFICATIONS`；原生报告会返回 SDK、振动器、振幅控制和前台服务权限状态，并明确后台振动需放进 foreground service + 通知约束下继续验证。iOS 已声明 `UIBackgroundModes` / `audio`，原生探针会设置 `AVAudioSession` playback category 并报告 Core Haptics 可用性；当前结论仍是 iOS 后台 haptics 先按“不支持持续后台触感”处理，除非后续真机 spike 证明可行。
- 2026-05-25 `PlatformCapabilityProbe` 集成验证已在 Android API 36 模拟器和 iOS 26.5 模拟器跑通。Android 报告显示后台音频声明、foreground service、media playback foreground service、wake lock、通知和振动权限均为 true，`MediaSessionService` 已在 manifest 声明，振动器与振幅控制可用，前台 `pulseHaptic` 返回 true；iOS 报告显示 `UIBackgroundModes audio` 已声明、`AVAudioSession` playback category 已配置，模拟器 Core Haptics 不可用但前台 `pulseHaptic` 调用返回 true。两端 `backgroundAudioReadyForSpike` 均为 true；锁屏/后台触感仍必须继续真机验证。
- 2026-05-25 已新增 Android Media3 后台音频 service 原型：`BackgroundAudioService` 继承 `MediaSessionService`，通过原生 `huxi_zen/background_audio` MethodChannel 支持 start / stop / status，可用 foreground media session 播放 bundled asset、远端 URL 或本地缓存文件；当前 integration test 已在 Android API 36 模拟器验证 bundled `assets/media/audio/waterfall.mp3` 能启动到 `ready`，stop 后 status 回到 stopped。当前只是后台音频服务通路验证，首页前台 `AmbientAudioEngine` 仍使用 `just_audio`，尚未把生产多轨混音、交叉淡入淡出和呼吸页颂钵音迁入 service。
- 2026-05-27 Android `AmbientAudioEngine` 已接入 Media3 foreground service 原型：Android 运行时不再用页面内 `just_audio` 承担环境音，而是把当前 `AmbientMix` 的 channelId、track id、asset/URL/file URI、durationMs 和 volume 通过 `BackgroundAudioServiceBridge.sync` 同步给原生 service；iOS 仍保持现有 `just_audio` 前台原型。原生 `BackgroundAudioService` 已按 channel 保留播放器，支持同源循环交叉淡入淡出、音量平滑调整、移除 channel 淡出释放、资源 URI 变化时单 channel 替换，并继续用 primary channel 暴露 MediaSession。Android integration test 已验证两个 bundled MP3 channel 可启动到 `ready`，随后 sync 成单 channel，最后 stop 回到 stopped。
- 2026-05-29 Android `BackgroundAudioService` 已新增第一版后台呼吸触感 pattern 通路：`BackgroundAudioServiceBridge.startHapticPattern` / `stopHaptics` 会把 Dart 侧 phase 列表通过同一 `huxi_zen/background_audio` MethodChannel 传给原生 service；原生 service 会按 phase 循环调度短振动，并在 `status()` 中暴露 `hapticsRunning`、`hapticPatternId`、`hapticPhase`、`hapticPhaseIndex`。`BackgroundHapticPattern` 已支持 `cycles`，用于自定义练习按组数自动结束。2026-05-30 已在 `emulator-5554` 跑通 `integration_test/android_background_audio_service_integration_test.dart`，验证两个 bundled MP3 channel、haptic pattern、sync 成单 channel、stop 状态都正常；同时修复原生 service 状态上报，避免 `primaryUri` 被最后 ready 的副音轨覆盖。
- 2026-05-29 已新增第一版 Flutter 呼吸节奏模型和触感控制器：`BreathingRhythm.defaultBreath()` 表示默认 `5-0-5-0`；`BreathingRhythm.defaultExercise()` 表示小程序自定义练习默认 `4-7-8 呼吸，8 组`（吸气 4 秒、屏息 7 秒、呼气 8 秒、呼气后屏息 0 秒，`cycles=8`）；零秒屏息 phase 会被跳过，不能把组数误写成第五段节奏。`BreathingHapticController` 负责把节奏转成 `BackgroundHapticPattern` 并调用 Android background service bridge，非 Android / MissingPlugin 场景会安全返回 unavailable。
- 2026-05-30 已接入第一版 Flutter 呼吸页 UI：首页左下角新增呼吸入口，呼吸页以全屏 overlay 复用当前背景视频和共享 `♪` 环境音状态；默认呼吸按设置里的 `defaultBreathRhythm` 循环；自定义练习先显示 `3 / 2 / 1` 倒计时和“本次练习8组 / 吸4秒->屏息7秒->呼8秒”，正式开始后显示剩余组数，完成后显示“本次练习完成，恢复默认呼吸”并回到默认呼吸。底部已接入 `触感`、`颂钵音`、`自定义练习` 三个入口，`触感` 通过 `BreathingHapticController` 同步到 Android service，`颂钵音` 使用小程序同源 `breath.mp3` 前台循环播放。设置页已新增第一版默认呼吸和自定义练习节奏调节，并持久化 `zenHaptics`、`zenSound`、两组呼吸节奏和 `cycles`。
- 2026-05-30 Flutter 呼吸花朵动画已按小程序/Chrome 版参数重做：6 个花瓣使用同样的 `56%` 尺寸、`translateY(-26%)` 环形布局、蓝白径向渐变、screen 混合和 36 秒慢旋转；呼吸舞台固定在屏幕中心，`吸气/呼气/屏息` 标签和练习说明按小程序的固定位置布局，不再用整列居中导致花朵上移。屏息阶段已按小程序时序做“前半段淡到 0.76、后半段回到 1”的明暗变化；自定义练习完成时已实现 3 秒整体放大/旋转/淡出，并让 6 个花瓣分别向外散开，结束后先隐藏重置再淡入默认呼吸。
- 2026-05-30 Flutter 首页已接入第一版前后台生命周期策略：`ZenHomePage` 监听 `AppLifecycleState`，进入 inactive / hidden / paused / detached 时会关闭首页/呼吸页共享 `♪` 环境音、卸载呼吸 overlay 以清掉前台 phase timer / haptic timer / 颂钵音播放器；`zenSound` 会强制落盘为 `false`，`rememberZenCues=false` 时同时把 `zenHaptics` 落盘为 `false`，`rememberZenCues=true` 时保留触感偏好但不自动恢复颂钵音。回到 resumed 时，如果之前正在呼吸页，会重新进入默认呼吸页，但环境音和颂钵音保持关闭。
- 2026-05-30 后台音频/振动 spike 当前完成了原生能力探针、平台声明、Android MediaSession foreground service 通路验证、Android 首页环境音到 foreground service 的第一版接入、Android foreground service 内呼吸触感 pattern 的桥接与调度、Flutter 呼吸节奏到 haptic pattern 的业务模型、呼吸页 UI 第一版接入、Flutter 前后台生命周期保护，以及 Android 模拟器 integration test；但尚未完成生产级后台多轨音频/触感：Android 仍需真机锁屏/熄屏长时间播放验证、通知交互完善、异常恢复、真机触感强度校准；iOS 仍需真机锁屏播放测试当前 `just_audio` 多轨语义是否能稳定保持，必要时升级原生音频引擎。
- Flutter 尚未实现断点续传、完整生产级后台音频、生产级振动、天气请求、授权记录页；呼吸页已是第一版，后续仍需补齐横向手势细节、颂钵音无缝交叉循环和真机校准。
- 下一步应在 Android 真机上验证呼吸页进入锁屏/熄屏后的环境音、颂钵音和触感表现，重点确认生命周期保护是否真的停止前台 timer / service / 播放器，并校准 `BreathingHapticController` 的触感强度；随后补 iOS 真机锁屏多轨音频和触感结论。

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
