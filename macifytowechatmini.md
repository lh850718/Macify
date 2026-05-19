# 呼吸Zen / Macify WeChat Mini Program Handoff

本文记录把 Macify 从 Chrome 扩展改造成微信小程序“呼吸Zen”的当前进展、技术选择、已实现内容、踩坑原因，以及下一步可直接继续执行的路线。

注意：本文后半包含大量历史过程记录。若历史记录与顶部“必须先读：当前硬性原则”冲突，一律以顶部硬性原则和当前代码为准。

## 必须先读：当前硬性原则

任何新的聊天窗口、接手者或自动化任务，在继续处理视频源之前必须先遵守本节。下面不是过程记录，而是当前项目决策。

### 公开发布版不展示或打包 Apple 源

- 公开发布版统一使用 `premiumFreeAerial` 背景视频池，用户侧不展示 Apple / 高端免费航拍 / Mixkit / Pixabay 等素材来源选择，只展示分类筛选。
- 公开发布版运行时代码不得 `require` / `import` `miniprogram/data/apple-aerial-1080.js` 或 `miniprogram/data/video-intros.js`。
- `project.config.json` 与 `miniprogram/project.config.json` 必须通过 `packOptions.ignore` 排除 Apple 清单和 Apple 介绍数据，避免进入上传包。
- 仓库内暂时保留 `miniprogram/data/apple-aerial-1080.js` 作为历史回滚资料，不在公开版播放池中使用；未来若确认彻底不用，可再单独删除。
- 不要覆盖腾讯云 COS 的 Apple 历史路径：

```text
macify/videos/<apple-video-id>.mp4
https://macify-videos-1430886267.cos.ap-beijing.myqcloud.com/macify
```

- 新增公开视频只能走独立清单和独立 COS 前缀。

### NPS / publicDomain 路线已废弃

- 完全抛弃 `npsPublicDomain` / `publicDomain` / NPS 99 条清单。
- 不要恢复、重建或继续执行：

```text
miniprogram/data/public-domain-videos.js
scripts/miniprogram/fetch-public-domain-videos.mjs
local-miniprogram-public-domain/
--source publicDomain
macify-public/
```

- 已转码的 NPS 小样质量不符合 Macify，需要保持删除状态。

### 非 Apple 新方向只有 Premium Free Aerial

非 Apple 视频库统一命名：

```text
videoLibrary: 'premiumFreeAerial'
内部素材库名: premiumFreeAerial
用户侧文案: 不展示素材库来源，只展示分类
清单: miniprogram/data/premium-free-aerial-videos.js
COS base: https://macify-videos-1430886267.cos.ap-beijing.myqcloud.com/macify-premium
COS path: macify-premium/videos/<source-video-id>.mp4
```

允许候选来源：

```text
Mixkit
Pexels
Pixabay
Dareful
Coverr
```

每个来源一期目标是 100 条候选。100 条不是永久上限，后续可以继续扩充；但每次扩充都必须质量优先，不能为了凑数量牺牲 Apple Aerial 级质感。

### 候选数量记录

每次新增、删除或改状态后，都要同步更新本表。

| 来源 | 一期目标 | 当前候选数 | sample-approved | published | 备注 |
| --- | ---: | ---: | ---: | ---: | --- |
| Mixkit | 100 | 7 | 0 | 7 | 已发布 7 条；日本主题通过 3 条已上传 COS 并标记 published；其余 12 条已删除 |
| Pexels | 100 | 0 | 0 | 0 | 未开始 |
| Pixabay | 100 | 92 | 0 | 92 | 已发布 92 条；本轮 7 条 Pixabay 样片已通过审片并上传 COS，`pixabay-183960` 重复输入已跳过，`pixabay-316029` 因 AI generated / low quality 未写入 |
| Dareful | 100 | 0 | 0 | 0 | 未开始 |
| Coverr | 100 | 0 | 0 | 0 | 未开始 |

### 每条视频和文案必须用户看过才新增/发布

- 未来每一条非 Apple 视频都必须先做本地样片给用户看。
- 未来每一条非 Apple 视频的 `displayName`、`locationName`、`description` 也必须随样片一起给用户审阅；用户确认前，不能把文案视为定稿，不能新增/发布。
- 后续 `description` 可以比早期文案更长一点，信息量更大，同时保留克制的文艺感。优先写地点、人文、自然知识、动物/植物生态、地貌成因、季节与光线意象；避免写“适合做背景”“镜头如何”“近景/航拍如何取胜”这类对拍摄方法或使用场景的评论。
- 用户确认之前，`qualityTier` 只能是 `candidate` 或 `sample-approved`，不得标记为 `published`。
- 用户确认之前，不上传 COS。
- 每次生成样片后，必须在回复里给用户一个可点击/可打开的视频链接，例如：

```markdown
![样片](/Users/hui/Projects/Macify/local-miniprogram-premium-aerial/videos/<id>.mp4)
```

### 审美标准比数量重要

目标是接近 Apple Aerial 的高端、安静、屏保级航拍质感，不是普通免费风景素材。

必须优先：

- 航拍、飞越、海岸、山脉、云层、湖泊、森林、峡谷、日出日落、自然延时
- 慢、稳、干净、无明显 stock 味
- 无人物、无字幕、无水印、无 logo、无品牌、无讲解、无游客主体、无车船主体
- 原始分辨率优先 4K，其次高质量 1080p

直接排除：

- 人物主体、采访、旅游 vlog、机构宣传、教程/教育片、强广告感素材
- 无人机炫技快速运动、严重晃动、过曝、过饱和、构图混乱
- 授权不清、editorial-only、AI/iStock/付费入口混排且无法确认免费授权的素材

### 分类必须保持简洁

公开发布版设置页只展示统一背景视频池的分类筛选，不展示 Apple 原始 `Space` 分类。当前公开背景视频池只使用：

```text
Landscapes
Cities
AnimalsAndPlants
Motion
Underwater
```

其中 `AnimalsAndPlants` 是代码枚举名，产品和中文记录里显示为“动植物”，用于鸟类、野生动物、海洋动物、植物、花卉和相关近景。旧枚举 `Animals` 已废弃，不再用于 Premium Free Aerial 清单。

`Motion` 是代码枚举名，产品里显示为“运转”。用于火苗、篝火、壁炉、烟火等燃烧/化学现象，也用于齿轮转动、唱片机、风车/风机、收割机械等人造物品或机械运动。火山、熔岩这类仍以地貌为主的素材，默认继续归入 `Landscapes`，除非画面重点明显是燃烧/反应本身。

不要使用 `Mac` / `其他` 分类。原本可能想归到 `Mac` 的视频，必须重新判断并归入上面这些主分类之一；如果无法归入，说明它不适合当前库。

不要新增 `Ocean`、`Mountains`、`Forest`、`Desert` 等主分类。海岸、山脉、湖泊、森林、日落等细节写入：

```text
tags
subcategories
locationName
description
```

如果视频有明确地点、城市或地标，`description` 应尽量带一点轻量人文介绍，例如地标气质、城市肌理、海港/建筑/历史语境；仍然保持屏保式克制，不写成旅游攻略或广告文案。

### 每条清单记录必须完整

新增到 `premium-free-aerial-videos.js` 的每条视频至少要包含：

```text
id
name
displayName
locationName
locationCountry
sourceName
sourcePage
sourceDownloadPage
url
previewImage
category
subcategories
tags
timeOfDay
description
sourceResolution
duration
license
attribution
licenseNotes
qualityTier
```

新增或修改后必须运行：

```bash
npm run mini:premium:validate
```

### 素材与授权页策略

- 呼吸Zen 基于 GitHub 开源项目 `jason5ng32/Macify` 改造。原项目采用 MIT License，版权声明为 `Copyright (c) 2023 Jason Ng`，README Credits 记录创建者 `Jason Ng, Dofy, Setilis`；公开发布版必须在 `© 呼吸Zen` 授权记录页保留开源项目声明，并在 `miniprogram/OPEN_SOURCE_NOTICES.txt` 保留 MIT License 原文和项目链接，确保小程序上传包也带有许可声明。
- 每条公开视频必须保留 `sourceName`、`sourcePage`、`sourceDownloadPage`、`license`、`attribution`、`licenseNotes`，这些字段是版权和授权追溯记录。
- `description` 只写地点、人文、自然知识或公版诗句意象，不写素材来源、许可证、上传状态、候选状态或技术信息。
- 版权声明不要塞进单条视频介绍文案。设置页左上标题直接显示 `© 呼吸Zen`，点击标题进入 `miniprogram/pages/licenses/licenses.*`；不要额外放右上角入口或“关于”区域。
- 授权记录页只保留首屏概要区域，不单独展示“记录”或“视频素材”区域。首屏不直接展示 `Mixkit`、`Pixabay` 等来源平台名。点 `Macify` 展示开源声明；点“公开素材”四个字才在同一区域内展示来源平台；点平台展示该平台视频名列表；点视频名展示作者/署名、许可证和备注。
- 来源平台详情由 `premium-free-aerial-videos.js` 中 `qualityTier: 'published'` 的条目按 `sourceName` 自动生成；`SOURCE_PLATFORMS` 只保存平台许可说明文案，未来新增 `sourceName` 时同步补齐对应说明。
- 未来每次新增公开视频、改来源平台、改许可证字段或新增 `sourceName`，都必须同步检查并更新授权记录页；如果只是新增同平台视频且清单字段完整，页面清单会自动带出，但仍要确认平台声明是否准确。
- 当前 Mixkit 与 Pixabay 条目都记录为无需强制署名，但仍应在授权记录页的单条详情里保留署名状态；来源链接保留在数据字段和 `OPEN_SOURCE_NOTICES.txt`，不在页面上直接展示。
- 如果未来做收费 App，不能只靠声明版权解决授权风险。必须确认每个来源的许可允许商业 App 内使用，且 App 不是把素材作为独立视频、壁纸、素材库或下载资源转售。单纯裁切、转码、调色通常不足以把素材变成新的创作。
- 版权页总声明使用：

```text
呼吸Zen 基于 Macify 改造；背景视频按公开素材平台许可用于应用内背景体验。素材版权归原作者或相应权利人所有；呼吸Zen 不声明拥有这些素材版权，也不提供素材下载、转售或独立素材库分发。
```

- 建议单条声明格式：

```text
<视频标题>
来源：<sourceName> / <attribution>
许可证：<license>
备注：<licenseNotes>
```

### 小程序播放与缓存策略

- 用户不主动手势切换视频时，当前视频循环播放，不自动切下一条；首页循环不依赖 `<video>` 原生硬切 `loop`，而是在接近结尾约 3.5 秒时启动第二个同源视频，旧视频保持不透明兜底，新视频从开头用约 3 秒淡入覆盖，减少循环跳跃感且避免交接时暗一下。
- 首页、呼吸页和纯视频模式都使用上下滑动手势切换视频：向上滑动播放本地播放序列中的下一条；如果刚向下回退过，则优先沿已有序列向前回到之前看过的视频，直到序列末端才从本次临时随机队列取新视频；向下滑动沿播放序列回退，可一直回到本次播放序列第一条，到头后提示没有上一条视频。
- 首页和呼吸页使用横向手势切换主功能：首页右滑进入呼吸页、左滑进入设置页；呼吸页左滑返回首页、右滑启动自定义呼吸。进入设置页时通过 `from=home` / `from=zen` 记录来源；设置页点击“保存返回”时，应返回对应的首页普通状态或呼吸页状态。
- 首页普通状态单击背景进入纯视频模式：触发一次短触感反馈并隐藏标题、天气、时钟、名言、冥想入口、底部按钮、弹层和遮罩，只保留背景视频；纯视频模式下仍支持上滑/下滑切换视频，单击背景恢复普通首页。
- 首页、呼吸页和纯视频模式都支持双击背景收藏当前视频；再次双击同一视频取消收藏，并用页面内小字提示 `已收藏` / `已取消收藏`，不要使用大 toast 打断观看。
- 用户主动向上滑动切换视频时，随机策略要尽量避免同一播放范围内很快刷到同一条视频；当前实现按 `videoSource`、`videoLibrary`、`shuffleScope` 记录本地随机历史，一轮内优先播放未出现过的视频，直到范围耗尽后再允许重复。
- 首页底部不再保留引号 / 格言切换按钮，避免可操作入口过多。用户想切换格言时，直接点击中心语录区域即可调用 `nextQuote()`。
- 首页底部普通状态只保留设置 `···` 和环境音 `♪` 两个入口；视频切换只通过上下滑动手势触发，横向手势用于首页 / 呼吸页切换，以及首页进入设置页。
- 小程序系统下拉刷新不再作为换视频入口，避免和“向下滑动回到上一条”冲突。
- 只缓存 `videoSource === 'lite'` 的 MP4。
- 每次打开首页或切换播放范围时，按当前范围在本地临时生成一条随机播放队列；队列用完前按队列顺序播放，不重复抽到同一条。
- 如果队列用完，再按当前范围重新洗牌生成下一轮队列；只有范围内视频少于 2 条时才可能连续重复。
- 为避免“每次打开都看到上一条”，首页首条也从本次临时队列中选择，不再直接把上一次缓存视频作为首条。缓存仍用于下载和后续播放优化。
- 用户主动向上滑动切换视频时，播放本次队列中的下一条。
- 本地缓存只保留最近一条，避免越积越多。

### 首页环境音与自定义混音策略

- 首页背景视频默认无声音；每次退出、切后台或重新进入小程序，都必须恢复为无声音。这里的退出 / 切后台指小程序生命周期事件，不包括首页、呼吸页、设置页之间的页面内导航。
- 首页右下角 `♪` 是环境音开关；呼吸页也保留同一个 `♪`。这两个入口的 UI 不要再增加模式选择，用户在设置页选好后，点击 `♪` 只负责按当前设置打开 / 关闭声音。
- `ambientSoundOn` 表示用户本次使用里“想不想开环境音”的意图，不等同于当前是否真的有音频实例在播放。页面跳转、进入设置页、首页 / 呼吸页互切、当前视频无匹配音频，都不能擅自把这个用户意图改成 `false`。
- 首页进入设置页、呼吸页进入设置页、设置页保存返回首页 / 呼吸页时，只能暂停或销毁当前 `InnerAudioContext`，不能关闭 `♪` 状态；返回后如果 `ambientSoundOn === true` 且当前视频 / 自定义混音有可播放音轨，应自动恢复环境音。
- 首页和呼吸页共用同一个 `♪` 开关状态。用户从首页开着环境音进入呼吸页，或从呼吸页返回首页，状态必须一致；只有用户主动点击 `♪` 才能切换该状态。
- 切换视频时，如果视频 A 有音源且用户开着环境音，滑到视频 B 因无音源而暂时无声，再滑到视频 C 有音源时，必须按用户原本的开声意图自动恢复 C 的环境音。视频 B 的“无音源”只能造成临时静音，不能永久关闭 `ambientSoundOn`。
- 小程序真正切后台、退出、从微信切走后再回来时，声音安全优先：必须关闭环境音用户意图并停止播放器，避免用户忘记后手机突然发声。
- 设置页“视频背景音”当前有两种模式：
  - `视频自带音频`：产品文案如此显示，但实际仍然播放 `miniprogram/data/ambient-audio.js` 中为视频预制 / 匹配的 COS 环境音，不播放 `<video>` 原始音轨，视频元素继续保持静音。
  - `自定义混音`：忽略当前视频匹配关系，所有视频都固定播放用户保存的 `customAmbientMix`。
- 自定义混音设置保存在 `settings.customAmbientMix`，模式保存在 `settings.ambientAudioMode`。每条混音记录是 `{ trackId, volume }`，音量范围 `0-1`。
- 自定义混音候选列表使用人类可懂的简洁名，例如 `林中风`、`瀑布`、`高空`、`火`、`小雨`、`溪流`、`鸟叫`、`山中鸟叫` 等；`tractor-harvesting.mp3` / `收割机` 只保留给 `麦田收割` 这类特殊视频，不作为用户自定义混音候选。
- 自定义混音最多允许 5 个声音。不要轻易改成 10 个：每个声音平时占 1 个 `InnerAudioContext`，交叉循环瞬间会变成 2 个；5 个声音瞬间约 10 路，10 个声音瞬间约 20 路，iPhone / 低端机更容易耗电、延迟、卡顿或丢声。除非做过真机压力测试，否则保持 5。
- 自定义混音里每个音轨选中后高亮，右侧显示音量滑杆；默认音量为 `0`。用户点击“开始试听”后可边调音边试听，试听和首页播放都按所有非零音量音轨混合，并为每个音轨独立交叉淡入淡出自动循环。
- 首页 / 呼吸页 `♪` 打开自定义混音时，如果用户尚未把任何音轨音量调到非零，应提示去设置里调大混音音量。
- 环境音使用 `wx.createInnerAudioContext({ useWebAudioImplement: true })`；循环播放不依赖硬 `loop`，而是在接近结尾时启动第二个同源音频实例，并用约 `2.6s` 交叉淡入淡出，避免循环断点。
- 环境音切换视频时，如果新视频映射到另一种音频，也使用旧音频淡出、新音频淡入；如果新视频没有映射音频，则淡出当前环境音并显示无可用音轨状态，但保留 `ambientSoundOn`，等下一条有音源的视频自动恢复。
- 少数视频允许多轨混音。多轨时每条音轨都必须有独立的播放 channel、独立循环定时器和独立交叉淡入淡出管理，不能共用一个全局 current/next 音频实例。
- 音量必须克制。已用 `ffmpeg volumedetect` 检查原始音频响度，并转码出上线用 128kbps MP3；代码里还按素材实际响度设置单独 `volume`，避免交叉叠放时过吵或过弱。
- 环境音映射只做窄匹配，不硬配。城市、星空、烟火、火山、黑胶、猫、部分山云/瀑布等当前没有足够贴合的音频，保持无音频；机械类默认不硬配，只有 `麦田收割` 这类已显式确认的特殊视频才使用 `tractor-harvesting.mp3`。
- 环境音音轨、通用规则和播放端解析函数在：

```text
miniprogram/data/ambient-audio.js
```

- 每条视频的显式混音覆盖记录在：

```text
miniprogram/data/video-audio-mixes.js
```

后续优化视频和音频对照关系时，优先改 `video-audio-mixes.js`。每条记录必须写 `videoId`、`mix` 和 `notes`；`mix: null` 表示明确无音频，`mix` 数组表示一条或多条音轨及可选音量。改完必须运行：

```bash
npm run mini:ambient:validate
```

- 当前环境音 COS base：

```text
https://macify-videos-1430886267.cos.ap-beijing.myqcloud.com/macify-audio
```

- 当前上传并验证通过的环境音文件：

```text
macify-audio/ocean-soft-waves.mp3
macify-audio/gentle-ocean-waves-birdsong-and-gull.mp3
macify-audio/underwater-ambience.mp3
macify-audio/forest-ambience.mp3
macify-audio/forest-wind-and-birds.mp3
macify-audio/river-stream.mp3
macify-audio/waterfall.mp3
macify-audio/mountain-sky-ambience.mp3
macify-audio/birds.mp3
macify-audio/wind-in-trees.mp3
macify-audio/light-rain.mp3
macify-audio/fire-crackling.mp3
macify-audio/tractor-harvesting.mp3
```

- 当前待上传 COS 的环境音文件：

```text
无
```

- 本地转码产物目录是：

```text
local-miniprogram-ambient-audio/
```

该目录已加入 `.gitignore`，不要打进小程序包。环境音走远程 COS，不放入 `miniprogram/assets/`。

当前 99 条公开视频的环境音映射统计（按音轨计数；多轨视频会在多个音轨里各计 1 次）：

```text
海浪 ocean-soft-waves.mp3: 16 条
海鸥海浪 gentle-ocean-waves-birdsong-and-gull.mp3: 1 条
水下 underwater-ambience.mp3: 22 条
森林 forest-ambience.mp3: 5 条
山林风鸟 forest-wind-and-birds.mp3: 3 条
鸟鸣 birds.mp3: 5 条
雨声 light-rain.mp3: 2 条
炉火 fire-crackling.mp3: 3 条
溪流 river-stream.mp3: 3 条
瀑布 waterfall.mp3: 5 条
风声 wind-in-trees.mp3: 3 条
天空 mountain-sky-ambience.mp3: 18 条
收割机 tractor-harvesting.mp3: 1 条
无音频: 15 条
```

当前用户指定的强制映射 / 排除：

```text
阿尔卑斯山径 pixabay-305657 -> forest-wind-and-birds.mp3
淡水鱼群 pixabay-108366 -> underwater-ambience.mp3
苔径深林 pixabay-287510 -> river-stream.mp3
麦田收割 pixabay-232561 -> tractor-harvesting.mp3
雪羽海鸥 pixabay-191159 -> wind-in-trees.mp3
樱光春枝 pixabay-268528 -> 无音频
落日泻湖 mixkit-sunset-reveal-over-scenic-lagoon-101208 -> mountain-sky-ambience.mp3
里斯本圣像 pixabay-260895 -> mountain-sky-ambience.mp3
瑞士雾海 pixabay-260397 -> wind-in-trees.mp3
青苔溪石 pixabay-271161 -> waterfall.mp3
金云暮天 pixabay-204006 -> mountain-sky-ambience.mp3
云隙光束 pixabay-221180 -> mountain-sky-ambience.mp3
尼亚加拉白潮 pixabay-28707 -> waterfall.mp3
雪河气泡 pixabay-159703 -> river-stream.mp3
云峰落日 pixabay-347325 -> mountain-sky-ambience.mp3
摩纳哥港 pixabay-323513 -> mountain-sky-ambience.mp3
春林直道 pixabay-266987 -> mountain-sky-ambience.mp3 + birds.mp3（sky 为主）
富士晨塔 pixabay-240841 -> mountain-sky-ambience.mp3 + birds.mp3（sky 音量 1.0，鸟声 0.08）
山涧白瀑 pixabay-228847 -> waterfall.mp3
古堡帆影 pixabay-175876 -> mountain-sky-ambience.mp3 + wind-in-trees.mp3（低音量轻混）
暮海群鸥 pixabay-140111 -> gentle-ocean-waves-birdsong-and-gull.mp3
稻田风机 pixabay-307864 -> mountain-sky-ambience.mp3
西峡鸟影 pixabay-276047 -> mountain-sky-ambience.mp3
山田星田 pixabay-283431 -> mountain-sky-ambience.mp3
雪原冷林 pixabay-325502 -> mountain-sky-ambience.mp3
晴空云影 pixabay-111179 -> mountain-sky-ambience.mp3
晨雾阿尔卑斯 pixabay-328740 -> mountain-sky-ambience.mp3
东京暮色 mixkit-aerial-view-of-a-city-during-the-night-4308 -> mountain-sky-ambience.mp3
东京夜城 mixkit-city-of-tokyo-at-night-4383 -> mountain-sky-ambience.mp3
冰岛火丘 pixabay-253436 -> mountain-sky-ambience.mp3
木舟渔人 pixabay-181376 -> birds.mp3
雏鸭草间 pixabay-265501 -> forest-wind-and-birds.mp3
```

瀑布类通用匹配到 `waterfall.mp3`，包括但不限于 `岩瀑白浪`、`青苔溪石`、`山涧白瀑`、`多洛米蒂瀑河`、`尼亚加拉白潮`。阿尔卑斯 / Alps 类通用匹配到 `forest-wind-and-birds.mp3`。

### 呼吸节奏与自定义练习策略

- 设置页“呼吸节奏”区提供两类设置：`默认呼吸` 和 `自定义练习`。
- 默认呼吸节奏字段为：吸气、屏息、呼气、屏息，默认值 `5-0-5-0`。用户每次打开呼吸页进入的普通呼吸模式都使用这组默认节奏。
- 自定义练习节奏字段为：吸气、屏息、呼气、屏息、组数，默认值 `4-7-8-0-8`。自定义练习只用于一次短时练习，完成后自动恢复默认呼吸模式。
- 呼吸动画必须按设置节奏驱动：吸气为花朵从最小放大到最大；吸气后屏息为最大状态轻微明暗变化；呼气为最大缩小到最小；呼气后屏息为最小状态轻微明暗变化。屏息值为 `0` 时跳过该阶段，不能卡在最大或最小状态。
- 呼吸页底部保留 `触感`、`颂钵音`、`自定义练习` 三个入口；点击自定义练习或在呼吸页右滑后，花朵先隐藏，中央显示 `3 / 2 / 1` 倒计时，并展示练习说明。
- 设置页的 `保留呼吸页设置` 只影响呼吸页底部的 `触感` 和 `颂钵音` 两个开关，不影响首页 / 呼吸页环境音 `♪`。
- `保留呼吸页设置` 关闭时，重新进入小程序会自动关闭 `zenHaptics` 和 `zenSound`；打开时可以在未切后台的同一次前台使用中保留触感和颂钵音偏好。
- 无论 `保留呼吸页设置` 是否打开，只要小程序真正切后台、退出、从微信切走后再回来，都必须先把 `zenSound` 关掉并停止颂钵音，避免手机突然发声。触感是否保留仍按 `rememberZenCues` 设置执行。
- 自定义练习说明格式为三行：`本次练习*组`、按非零阶段拼接的节奏行、`可在设置中修改`。阶段值为 `0` 时，对应文字和箭头都不展示。
- 自定义练习倒计时结束后，不能让数字 `1` 二次闪现；小花和 `吸气` 字样需要淡入后再启动正式吸气动画。
- 呼吸舞台、倒计时数字、小花和呼吸字样必须固定在屏幕中心附近，不得因为下方提示从三行变成一行而跳位；提示文字单独定位在呼吸舞台下方。
- 自定义练习正式开始后，同一位置显示剩余组数；完成后花朵用约 3 秒散开并淡到完全透明，同时显示 `本次练习完成，恢复默认呼吸`。
- 完成动画结束后必须先把花朵隐藏并重置到最小状态，再淡入小花和 `吸气` 字样，最后启动默认呼吸；不得在完成文字还未消失时提前启动默认呼吸，避免出现小花突然跳成大花。
- 呼吸触感只在用户打开 `触感` 时触发。吸气触感随吸气时长缩放；有屏息阶段时，在屏息切换到下一阶段的节点播放轻触感提示；未开启触感或对应屏息为 `0` 时不得振动。

### 小程序直接 URL 已删除

- 设置页不再提供“直接 URL”视频源，`videoSource: 'direct'` 的旧本地设置会在启动时自动归回 `lite`。
- 后续不要恢复 `directVideoUrl` 输入框。临时测试单个外部视频时，应先把素材放到自有 COS/CDN，并作为素材库条目或根域名规则接入。
- 不要把网页链接、下载页、短链、需要 Cookie/登录/Referer/防盗链的地址直接塞给小程序 `<video>`。`https://pixabay.com/videos/download/x-2118_medium.mp4` 这类 Pixabay 下载页实测会返回 `403 text/html` 的 Cloudflare 验证页，不是稳定的视频响应。

### 小程序收藏与偏好策略

- 首页普通状态、呼吸页和纯视频模式都支持双击背景收藏当前视频；同一视频再次双击取消收藏。收藏状态变化只用页面内小字提示 `已收藏` / `已取消收藏`，避免大 toast 打断屏保体验。
- 视频介绍浮层里仍保留收藏入口，点击爱心后变为红心；再次点击取消收藏。该入口也应使用同一套小字提示反馈。

- 收藏数据当前只存在用户本地小程序 storage，键格式为：

```text
<videoLibrary>:<video-id>
```

- 设置页“播放范围”必须包含“收藏”分类；选择收藏后只在当前视频库已收藏的视频范围内随机播放。
- 如果用户选择“收藏”但当前视频库没有收藏视频，首页应提示用户先收藏视频，不能静默回退到全部视频。
- 收藏范围也遵守“不快速重复”策略。
- 如果未来要统计全体用户最喜欢的视频，不要把本地收藏误认为后台可见数据；必须额外做事件上报。建议先只上报匿名聚合事件：`favorite_add`、`favorite_remove`、`play_start`、`quick_skip`，后台按视频聚合收藏率和跳过率。若使用 `openid`、设备标识或其他可识别标识做去重/画像，必须同步更新小程序隐私保护指引与隐私政策。

### 小程序信息浮层与天气策略

- 左上角视频标题点击后，介绍浮层不要从底部弹出；必须基于点击位置原地展开为顶部锚点浮层。
- 天气点击后也不要从底部弹出；必须基于天气卡片点击位置原地展开。
- 天气详情不要只展示 3 天。当前使用 Open-Meteo 7 天预报，并展示当前温度、体感、湿度、风速，以及每日天气、最高/最低温、降水概率、降水量、风速、紫外线、日出和日落。
- 设置页不再单独保留“天气”大区块。天气城市设置放在“显示”区的天气开关下面；只有 `settings.showWeather` 打开时才展示一行紧凑设置：城市输入框 + 摄氏度按钮 + 华氏度按钮。
- 默认天气城市现在写中文 `北京`，空值也回落到 `北京`。`miniprogram/utils/weather.js` 已内置北京 / 上海经纬度，默认北京不再依赖 `geocoding-api.open-meteo.com`，只需要请求 `api.open-meteo.com`。
- 天气请求失败时首页不能静默消失。首页应先显示 `--° 天气加载中`，失败后显示 `--° 天气暂不可用`；如果本地已有旧天气缓存，请求失败时优先沿用旧缓存。
- `wx.request` 可能在 iPhone 真机上把 JSON 作为字符串返回，天气工具层必须兼容字符串 JSON 解析。DevTools 正常不代表真机一定正常。
- 真机天气仍需要微信公众平台配置 `request` 合法域名：`https://api.open-meteo.com` 和 `https://geocoding-api.open-meteo.com`。默认北京只依赖前者，用户输入其他城市仍依赖后者。
- 旧历史记录里若仍写着“底部天气详情面板”或“3 日天气”，已过时，以本节为准。

### 设置页密度策略

- 设置页要尽量短，不要为每个开关都拆出独立大区块。
- 背景视频播放范围必须直接铺开，不用 picker；当前设计为 4 列网格，避免页面过长。
- 天气城市和温度单位合并为一行，只在天气开关打开时显示。
- 视频背景音模式使用两个并排按钮；自定义混音列表只在选择“自定义混音”后展开。

### 文档同步原则

- 任何功能修改、产品行为修改、数据结构修改、配置/设置项修改、外部服务接入修改或隐私/统计边界修改，都必须同步更新本文顶部“当前硬性原则”区域。
- 本次已同步记录播放随机策略、收藏/偏好、设置页收藏分类、天气/信息浮层、天气数据范围、本地缓存和未来数据上报边界；后续若修改其他功能，也必须按同一原则补充到本文。
- 本文后半历史记录可以保留旧过程，但只要和顶部硬性原则冲突，一律以顶部为准；新增改造不要只写代码不写交接说明。

### 上传和密钥原则

- 不要上传未经用户确认的样片。
- Premium 上传只走：

```text
macify-premium/
```

- 首页环境音上传只走：

```text
macify-audio/
```

- 永远不要上传到或覆盖：

```text
macify/videos/
```

- 上传前必须重新向用户索取 `COS_SECRET_ID` / `COS_SECRET_KEY`。
- 不要从历史聊天、文档或文件里找密钥，不要把密钥写入任何文件。
- 上传后提醒用户禁用/删除 `macify-cos-uploader` 或删除该 API 密钥。

### 资源托管与备份仓库当前状态

- 当前可确认用于小程序静态资源托管的是腾讯云 COS，不是传统服务器。Bucket：

```text
macify-videos-1430886267
region: ap-beijing
默认访问域名: https://macify-videos-1430886267.cos.ap-beijing.myqcloud.com
```

- 已有路径前缀：

```text
macify/videos/          旧 Apple 视频资源；新项目不要混用或覆盖
macify-premium/videos/  呼吸Zen 公开视频资源
macify-audio/           呼吸Zen 环境音资源
```

- 另一个小程序如果要放图片、音频、视频等静态资源，建议新建独立 bucket；如果复用当前 bucket，至少必须使用独立前缀，例如 `<project-name>/images/`、`<project-name>/audio/`、`<project-name>/videos/`，不要混到呼吸Zen现有路径。
- 新小程序真机访问资源时，需要把对应 COS 默认域名或后续 CDN / 自有备案 HTTPS 域名加入微信公众平台合法域名。图片 / 视频下载通常看 `downloadFile` 合法域名；天气这类接口看 `request` 合法域名。
- GitHub 私有备份仓库当前为：

```text
backup remote: git@github.com:lh850718/HuxiZenbackup.git
local branch: backup-audio-feature-20260517
remote branch: main
deploy key: ~/.ssh/huxizenbackup_ed25519
```

- 2026-05-17 首次推送失败时，GitHub 报 `remote unpack failed: index-pack failed` / `did not receive expected object ...`。原因是本地仓库仍是 shallow clone。已通过 `git fetch --unshallow origin` 补全历史，再用 `git push --no-thin` 推送成功。
- 2026-05-17 已将自定义混音功能提交并推送到 backup/main：

```text
commit: f0a101d3bfba7017dc2cd302f807a19f049dae8f
message: 增加自定义混音功能
```

- 之后的首页去掉引号按钮、设置页紧凑天气 / 4 列播放范围、天气真机兜底、横向手势、双击收藏、单击纯视频、播放序列回退和本文档更新，是该提交之后的新本地改动；若要备份，需另行提交并推送。

### 腾讯云 COS 敏感信息记录

本节只记录账号上下文，不保存可用密钥。`SecretId` / `SecretKey` 属于敏感凭证，不能写入仓库、文档、脚本、日志或配置文件；每次上传 COS 前必须由用户在当前会话重新提供，并仅作为当前上传命令的环境变量使用。

```text
主账号 ID: 100048756855
子账号用户名: macify-cos-uploader
登录密码: 未设置 / 不记录
快捷登录: https://cloud.tencent.com/login/subAccount/100048756855?type=subAccount&username=macify-cos-uploader
SecretId: 敏感凭证，不保存
SecretKey: 敏感凭证，不保存
```

### ICP / CDN / 小程序上线当前状态

截至 2026-05-13 用户反馈的最新腾讯云 ICP 状态：

```text
备案订单号: 30177839176900401
订单类型: 新增服务（原备案不在腾讯云）
创建时间: 2026-05-10 13:42:49
当前阶段: 腾讯云审核中
已完成: 1 提交初审
进行中: 2 腾讯云审核
后续: 3 待提交管局、4 工信部短信核验、5 管局审核
审核提醒: 腾讯云将在 1-2 个工作日内给李慧（手机号 136****7633、135****2101）致电；第一次未接通 1 小时内再次拨打，均未接通会导致驳回。
```

用户应立即做：

- 把腾讯云审核电话加入通讯录，临时关闭骚扰拦截，保持 `136****7633` 和 `135****2101` 可接通。
- 腾讯云初审通过后，工信部短信核验必须在 24 小时内完成。
- 管局审核预计 1-20 个工作日。

上线相关状态：

- 备案域名：`huxizen.com`
- 计划 CDN 域名：`video.huxizen.com`
- 当前代码默认视频源仍是 COS 默认域名：`https://macify-videos-1430886267.cos.ap-beijing.myqcloud.com/macify-premium`
- 备案通过并完成 CDN 接入前，不要把代码默认视频源切到 `video.huxizen.com`。
- 备案通过后，接入 CDN 到 COS `macify-premium/`，再把 `DEFAULT_PREMIUM_FREE_AERIAL_VIDEO_BASE` 改为 `https://video.huxizen.com/macify-premium`，并 bump `PREMIUM_FREE_AERIAL_SOURCE_VERSION`，强制旧缓存刷新。

微信小程序后台上线前必须检查：

```text
request 合法域名:
https://api.open-meteo.com
https://geocoding-api.open-meteo.com

downloadFile 合法域名（备案/CDN 前临时）:
https://macify-videos-1430886267.cos.ap-beijing.myqcloud.com

downloadFile 合法域名（备案/CDN 后正式）:
https://video.huxizen.com
```

注意区分两类备案：

- 腾讯云当前这单是 `huxizen.com` 的网站/域名 ICP 备案，主要服务于后续 `video.huxizen.com` CDN 域名。
- 微信公众平台里还要检查小程序本体备案状态。若后台显示小程序未备案或待补充备案，必须在微信公众平台完成小程序备案后才能最终发布。

当前小程序只用 `wx.request` 获取天气、`wx.downloadFile` 缓存视频、`wx.createInnerAudioContext` 播放用户手动开启的 COS 环境音；没有 `wx.login`、`wx.getUserProfile`、`wx.getLocation`、上传文件、支付、订阅消息或用户事件上报。隐私指引里不要声明不存在的数据采集；若后续增加定位、openid、统计或收藏上报，必须同步更新隐私保护指引。

### 当前下一步

当前已发布样片：

```text
id: mixkit-large-lake-sunset-aerial-4998
file: local-miniprogram-premium-aerial/videos/mixkit-large-lake-sunset-aerial-4998.mp4
status: published，用户已确认样片质感，已上传 COS 到 macify-premium/videos/，未触碰 Apple 路径
cosUrl: https://macify-videos-1430886267.cos.ap-beijing.myqcloud.com/macify-premium/videos/mixkit-large-lake-sunset-aerial-4998.mp4

id: mixkit-drone-pullback-over-lake-101513
file: local-miniprogram-premium-aerial/videos/mixkit-drone-pullback-over-lake-101513.mp4
status: published，用户已确认样片质感，已上传 COS 到 macify-premium/videos/，未触碰 Apple 路径
cosUrl: https://macify-videos-1430886267.cos.ap-beijing.myqcloud.com/macify-premium/videos/mixkit-drone-pullback-over-lake-101513.mp4

id: mixkit-sunset-reveal-over-scenic-lagoon-101208
file: local-miniprogram-premium-aerial/videos/mixkit-sunset-reveal-over-scenic-lagoon-101208.mp4
status: published，用户已确认样片质感，已上传 COS 到 macify-premium/videos/，未触碰 Apple 路径
cosUrl: https://macify-videos-1430886267.cos.ap-beijing.myqcloud.com/macify-premium/videos/mixkit-sunset-reveal-over-scenic-lagoon-101208.mp4

id: mixkit-swiss-alps-snow-timelapse-4283
file: local-miniprogram-premium-aerial/videos/mixkit-swiss-alps-snow-timelapse-4283.mp4
status: published，用户已确认样片质感，已上传 COS 到 macify-premium/videos/，未触碰 Apple 路径
cosUrl: https://macify-videos-1430886267.cos.ap-beijing.myqcloud.com/macify-premium/videos/mixkit-swiss-alps-snow-timelapse-4283.mp4

id: mixkit-aerial-view-of-a-city-during-the-night-4308
file: local-miniprogram-premium-aerial/videos/mixkit-aerial-view-of-a-city-during-the-night-4308.mp4
status: published，用户已确认样片质感，已上传 COS 到 macify-premium/videos/，未触碰 Apple 路径
cosUrl: https://macify-videos-1430886267.cos.ap-beijing.myqcloud.com/macify-premium/videos/mixkit-aerial-view-of-a-city-during-the-night-4308.mp4

id: mixkit-city-of-tokyo-at-night-4383
file: local-miniprogram-premium-aerial/videos/mixkit-city-of-tokyo-at-night-4383.mp4
status: published，用户已确认样片质感，已上传 COS 到 macify-premium/videos/，未触碰 Apple 路径
cosUrl: https://macify-videos-1430886267.cos.ap-beijing.myqcloud.com/macify-premium/videos/mixkit-city-of-tokyo-at-night-4383.mp4

id: mixkit-top-view-of-tokyo-cargo-port-4445
file: local-miniprogram-premium-aerial/videos/mixkit-top-view-of-tokyo-cargo-port-4445.mp4
status: published，用户已确认样片质感，已上传 COS 到 macify-premium/videos/，未触碰 Apple 路径
cosUrl: https://macify-videos-1430886267.cos.ap-beijing.myqcloud.com/macify-premium/videos/mixkit-top-view-of-tokyo-cargo-port-4445.mp4
```

本轮 18 条 Pixabay 候选已审片通过，已上传 COS 到 `macify-premium/videos/`，逐条验证 `200 video/mp4`，并在 `premium-free-aerial-videos.js` 标记为 `published`：

```text
pixabay-348904
pixabay-347325
pixabay-257593
pixabay-344380
pixabay-76681
pixabay-339840
pixabay-345244
pixabay-328740
pixabay-333600
pixabay-334716
pixabay-330898
pixabay-323513
pixabay-181376
pixabay-326677
pixabay-260895
pixabay-326739
pixabay-325502
pixabay-338904
```

本轮用户拒绝 4 条样片，已从清单和本地样片删除，不上传 COS，不标记 published：

```text
mixkit-fly-over-huge-vegetated-canyon-41401
mixkit-aerial-panorama-coast-reliefs-36615
mixkit-tour-high-above-city-dusk-41375
mixkit-chichen-itza-pyramid-4106
```

本轮用户拒绝 3 条雷同样片，已从清单和本地样片删除，不上传 COS，不标记 published：

```text
mixkit-aerial-zoom-over-cloudy-hills-101508
mixkit-drone-shot-over-hills-and-dock-101506
mixkit-majestic-hills-and-sky-reflections-101510
```

本轮 15 条日本主题候选已审片，用户保留 3 条，已在 `premium-free-aerial-videos.js` 标记为 `published`，并上传 COS 到 `macify-premium/videos/`：

```text
mixkit-aerial-view-of-a-city-during-the-night-4308
mixkit-city-of-tokyo-at-night-4383
mixkit-top-view-of-tokyo-cargo-port-4445
```

本轮用户拒绝其余 12 条日本样片，已从清单和本地样片删除，不上传 COS，不标记 published：

```text
mixkit-tokyo-aerial-time-lapse-4309
mixkit-atop-the-city-of-tokyo-at-night-4455
mixkit-rainbow-bridge-in-japan-over-the-sea-4382
mixkit-modern-buildings-at-dusk-4409
mixkit-tower-of-the-tree-of-heaven-tokyo-4411
mixkit-panning-shot-of-tokyo-city-4448
mixkit-sensoji-shrine-in-tokyo-japan-4403
mixkit-cherry-trees-blooming-by-the-river-in-tokyo-30141
mixkit-large-japanese-building-sticking-out-from-the-trees-36338
mixkit-himeji-castle-seen-from-below-during-a-sunny-day-36367
mixkit-japanese-castle-and-the-city-skyline-39433
mixkit-osaka-japanese-temple-and-the-sky-in-the-background-39432
```

2026-05-11 用户最新提供的 14 条 Pixabay 链接已写入 `premium-free-aerial-videos.js`；本地 1080p 竖屏样片已生成到 `local-miniprogram-premium-aerial/videos/`。用户审片和审文案后确认“其他都 ok”，已上传到 `macify-premium/videos/`，逐条验证 `200 video/mp4`，并全部标记为 `qualityTier: 'published'`。为避免远端 4K 大文件卡住，`prepare-lite-videos.mjs` 已支持可选 `sampleUrl`：正式 `url` 仍保留 large 源，样片转码可走 medium 源，输出报告会同时记录 `sourceUrl` 和 `sampleSourceUrl`。

```text
pixabay-305657
pixabay-306155
pixabay-307864
pixabay-258799
pixabay-152085
pixabay-308073
pixabay-293788
pixabay-296958
pixabay-287510
pixabay-286278
pixabay-276047
pixabay-283431
pixabay-275983
pixabay-271161
```

本次上传只使用临时目录 `/private/tmp/macify-premium-approved-20260511-14`，其中只包含上述 14 个 MP4，避免同步本地目录里其他历史文件。上传后已确认 `/private/tmp/macify-cos.yaml` 不存在，并扫描仓库确认本次明文 `SecretId` / `SecretKey` 没有写入文件。请禁用/删除本次 `macify-cos-uploader` API 密钥。

2026-05-12 用户提供的 11 条 Pixabay 链接已完成重裁和发布。用户要求调整 `樱光春枝` 左移、`椰影海湾` 右移、`兰卡林蜥` 右移、`富士晨塔` 按尾帧富士山居中、`麦田收割` 拖拉机居中；对应清单已保留 `cropFocusX`：`pixabay-268528` 0.42、`pixabay-218714` 0.68、`pixabay-265271` 0.64、`pixabay-240841` 0.38、`pixabay-232561` 0.35。本地 1080p 竖屏样片已重生成到 `local-miniprogram-premium-aerial/videos/`，上传到 `macify-premium/videos/`，逐条验证 `200 video/mp4`，并全部标记为 `qualityTier: 'published'`：

```text
pixabay-268528
pixabay-266987
pixabay-218714
pixabay-265501
pixabay-265271
pixabay-260397
pixabay-214409
pixabay-253436
pixabay-240841
pixabay-225661
pixabay-232561
```

本次上传使用 `scripts/miniprogram/upload-cos-videos.mjs` 同步完整 `local-miniprogram-premium-aerial` 输出目录：11 个视频上传，39 个历史视频跳过，并刷新远端完整 50 条 manifest。未触碰 Apple 路径。已将 `PREMIUM_FREE_AERIAL_SOURCE_VERSION` bump 到 `premium-free-aerial-1080p-cos-20260512`，更新后会失效旧 Premium 本地缓存。

2026-05-12 用户随后提供 18 条 Pixabay 链接并审阅本地 1080p 竖屏样片和文案。用户要求删除 `金阁池影`（`pixabay-214940`），其余 17 条继续上传。已删除本地 `local-miniprogram-premium-aerial/videos/pixabay-214940.mp4`，未写入清单、未上传该条。其余 17 条已写入 `premium-free-aerial-videos.js`，上传到 `macify-premium/videos/`，逐条验证 `200 video/mp4`，并全部标记为 `qualityTier: 'published'`：

```text
pixabay-204006
pixabay-191159
pixabay-215484
pixabay-221180
pixabay-148594
pixabay-190776
pixabay-183960
pixabay-228847
pixabay-47213
pixabay-38388
pixabay-28707
pixabay-175876
pixabay-140111
pixabay-66810
pixabay-65438
pixabay-42420
pixabay-34855
```

本次先使用临时目录 `/private/tmp/macify-premium-approved-20260512-17` 上传 17 个新视频，避免带上被删除的 `pixabay-214940`。随后刷新 `local-miniprogram-premium-aerial/manifest.json` / `manifest.csv` 为完整 67 条记录，并再次运行 `scripts/miniprogram/upload-cos-videos.mjs` 刷新远端完整 67 条 manifest；第二次同步显示 67 个视频全部 skip，只补 ACL 和 manifest。未触碰 Apple 路径。已将 `PREMIUM_FREE_AERIAL_SOURCE_VERSION` bump 到 `premium-free-aerial-1080p-cos-20260512-67`，更新后会失效旧 Premium 本地缓存。

2026-05-12 新增 Premium Free Aerial 主分类 `Motion`，产品显示为“运转”。已把 `夜营火光`、`夜空烟火`、`稻田风机`、`琵琶湖烟火`、`麦田收割`、`营火煮茶`、`炉火冬夜`、`黑胶回声`、`齿轮流光` 归入该分类；验证脚本允许 `Motion`。随后删除“直接 URL”视频源和设置页输入框；旧本地设置里如果仍是 `videoSource: 'direct'`，会自动归回 `lite`。Apple 原始 `Space` 分类在设置页恢复显示，但中文名改为“太空”，不再显示“地球”。Pixabay 下载页、B 站页面、需要 Cookie/登录/防盗链的链接都不要直接塞给小程序 `<video>`，应先转到自有 COS/CDN 或正式素材库流程。

2026-05-13 用户提供 8 条 Pixabay 链接和人工分类，其中 `pixabay-204006` 已在 2026-05-12 批次发布，本次不重复写入。其余 7 条已通过 ImageURLGenerator 的 `/api/pixabay` 代理解析到稳定 `cdn.pixabay.com` large/medium 直链；`pixabay.com/videos/download/...` 下载地址仍会返回 Cloudflare 403，不作为小程序运行时 URL。当前公开版分类仍只使用既有枚举，因此 3 条“太空”素材写入 `Landscapes`，并在 `subcategories` / `tags` 中保留 `Space`。本轮新增条目为：

```text
pixabay-2118
pixabay-31420
pixabay-201404
pixabay-11722
pixabay-111179
pixabay-67358
pixabay-264272
```

本次已上传到 `macify-premium/videos/`，同步报告显示 7 个新视频上传、67 个历史视频跳过；随后刷新远端完整 74 条 `manifest.json` / `manifest.csv`，并逐条验证上述 7 个公开视频为 `200 OK` / `video/mp4`。未触碰 Apple 路径。已将 `PREMIUM_FREE_AERIAL_SOURCE_VERSION` bump 到 `premium-free-aerial-1080p-cos-20260513-74`，更新后会失效旧 Premium 本地缓存。

如果用户感觉没有刷到这批新视频，原因通常是 COS 已上传但小程序包还没有重新编译/上传：视频随机池来自打包进小程序的 `miniprogram/data/premium-free-aerial-videos.js`，不是远端 manifest。高端免费航拍随机池只读取 `qualityTier: 'published'` 的记录，避免后续候选样片混进正式池。测试时请确认设置里视频库选的是“高端免费航拍”、分类是“全部”。

2026-05-13 用户继续提供 6 条 Pixabay 链接和人工分类。已通过 ImageURLGenerator 的 `/api/pixabay` 代理解析到稳定 `cdn.pixabay.com` large/medium 直链，并追加到 `premium-free-aerial-videos.js`。已给用户审阅本地 1080p 竖屏样片和文案，用户回复“样片文案 ok”，本轮 6 条已标记为 `qualityTier: 'published'`，上传到 `macify-premium/videos/`，并刷新远端完整 80 条 `manifest.json` / `manifest.csv`。本轮发布为：

```text
pixabay-213616
pixabay-26818
pixabay-16166
pixabay-83061
pixabay-63427
pixabay-27784
```

其中用户标记为“自然”的两条水下海浪素材，按当前公开版枚举落到 `Underwater`；用户标记为“动植物”的水母、鱼类素材落到 `AnimalsAndPlants`。版权页的 Pixabay 平台声明已存在，授权记录页会按 `published` 条目自动把这 6 条纳入“公开素材 / Pixabay”列表。已将 `PREMIUM_FREE_AERIAL_SOURCE_VERSION` bump 到 `premium-free-aerial-1080p-cos-20260513-80`，更新后会失效旧 Premium 本地缓存。

2026-05-13 用户继续提供 6 条 Pixabay 链接和人工分类，其中 `pixabay-4286600` 是图片页转轻微动效样片，`pixabay-216270` 为水下甲壳动物样片。用户审片后要求删除 `水面晴云`（`pixabay-4286600`）和 `礁间小蟹`（`pixabay-216270`），这两条已删除本地样片，未写入清单、未上传 COS。其余 4 条已追加到 `premium-free-aerial-videos.js`，标记为 `qualityTier: 'published'`，并上传到 `macify-premium/videos/`：

```text
pixabay-182908
pixabay-128014
pixabay-216282
pixabay-159703
```

本轮保留条目中，`pixabay-182908`、`pixabay-128014` 按用户“动植物”分类归入 `AnimalsAndPlants`；`pixabay-216282`、`pixabay-159703` 按用户“水下”分类归入 `Underwater`。已刷新本地和远端完整 84 条 `manifest.json` / `manifest.csv`，上传同步显示 4 个新视频上传、80 个历史视频跳过，并逐条验证上述 4 个新 COS 地址为 `200 OK` / `video/mp4`。版权页的 Pixabay 平台声明已存在，授权记录页会按 `published` 条目自动纳入这 4 条。已将 `PREMIUM_FREE_AERIAL_SOURCE_VERSION` bump 到 `premium-free-aerial-1080p-cos-20260513-84`，更新后会失效旧 Premium 本地缓存。

2026-05-13 用户继续提供 9 条 Pixabay 链接和人工分类，其中 `pixabay-64630` 重复出现一次，已去重为 8 条唯一候选。已通过 ImageURLGenerator 的 `/api/pixabay` 代理解析到稳定 `cdn.pixabay.com` large/medium 直链，追加到 `premium-free-aerial-videos.js`。用户审片后回复“继续”，本轮 8 条已标记为 `qualityTier: 'published'`，上传到 `macify-premium/videos/`，并刷新本地和远端完整 92 条 `manifest.json` / `manifest.csv`。上传同步显示 8 个新视频上传、84 个历史视频跳过；已给 92 条 ready 视频补 `public-read` ACL，并逐条验证本轮 8 个 COS 地址为 `200 OK` / `video/mp4`。分类映射：用户“水下”进入 `Underwater`；“动植物”进入 `AnimalsAndPlants`；“化学生物”按当前公开枚举进入 `Motion`；“生活人物”因公开版无该枚举且画面核心为泳池水下波光，暂归 `Underwater` 并在 `subcategories` / `tags` 保留 `Pool` / `Model` / `Reflection`。版权页已补充 Pixabay 平台说明；授权记录页会按 `published` 条目自动纳入“公开素材 / Pixabay”列表。已将 `PREMIUM_FREE_AERIAL_SOURCE_VERSION` bump 到 `premium-free-aerial-1080p-cos-20260514-92`，更新后会失效旧 Premium 本地缓存。

2026-05-14 用户继续提供 9 条 Pixabay 链接和人工分类，其中 `pixabay-183960` 已在 2026-05-12 批次发布，本次不重复写入；`pixabay-316029` 由 Pixabay API 标注为 `isAiGenerated: true` 且 `isLowQuality: true`，按当前审美硬性标准暂不写入候选清单、不生成入库样片。其余 7 条已通过 Pixabay API 解析到稳定 `cdn.pixabay.com` large/medium/small 直链，并以 `qualityTier: 'candidate'` 追加到 `premium-free-aerial-videos.js` 生成本地样片。用户审片和审文案后回复“可以 继续”，本轮 7 条已标记为 `qualityTier: 'published'`，上传到 `macify-premium/videos/`，并刷新本地和远端完整 99 条 `manifest.json` / `manifest.csv`。本轮发布为：

```text
pixabay-4294
pixabay-127713
pixabay-6636
pixabay-185096
pixabay-227567
pixabay-24216
pixabay-4006
```

分类映射：用户“动植物”进入 `AnimalsAndPlants`；用户“自然”进入 `Landscapes`；用户“生活人物”的 `pixabay-185096` 因公开版无该枚举且画面核心为海边书页与海岸环境，暂归 `Landscapes` 并在 `subcategories` / `tags` 保留 `Book` / `Literature` / `Beach` / `Ocean`。上传同步显示 7 个新视频上传、92 个历史视频跳过；已给 99 条 ready 视频补 `public-read` ACL，并逐条验证本轮 7 个 COS 地址与远端 `manifest.json` 均为 `200 OK`，视频为 `Content-Type: video/mp4`。版权页的 Pixabay 平台声明已存在，授权记录页会按 `published` 条目自动纳入“公开素材 / Pixabay”列表。已将 `PREMIUM_FREE_AERIAL_SOURCE_VERSION` bump 到 `premium-free-aerial-1080p-cos-20260514-99`，更新后会失效旧 Premium 本地缓存。

2026-05-16 新增首页环境音。用户下载的原始音频位于 `/Users/hui/Downloads/sound/`，当前只选用与视频画面明确贴合的 6 类：海浪、水下、森林、鸟鸣、雨声、炉火；其他音频和没有贴合画面的类别暂不硬配。已新增：

```text
miniprogram/data/ambient-audio.js
```

首页新增右下角 `♪` 环境音开关。默认无声音；每次退出、切后台或重新进入小程序都会关闭；首页和呼吸页之间切换时保持同一个环境音开关状态。用户主动点 `♪` 但当前视频无匹配音频时提示“当前视频暂无匹配音频”；如果是滑动切到无音源视频，则只临时淡出静音，不关闭用户开声意图，下一条有音源时自动恢复。环境音通过 `wx.createInnerAudioContext({ useWebAudioImplement: true })` 播放，循环时使用两个音频实例约 `2.6s` 交叉淡入淡出；切换到不同环境音时也做淡入淡出。呼吸页 `颂钵音` 仍使用 `miniprogram/assets/breath.mp3`，与首页环境音互不共享状态。

`miniprogram/utils/videos.js` 已把 `tags` 暴露给首页视频对象，供 `ambientTrackForVideo` 做窄匹配。当前 99 条发布视频的映射统计：

```text
海浪 ocean-soft-waves.mp3: 19 条
水下 underwater-ambience.mp3: 22 条
森林 forest-ambience.mp3: 13 条
鸟鸣 birds.mp3: 6 条
雨声 light-rain.mp3: 2 条
炉火 fire-crackling.mp3: 3 条
无音频: 34 条
```

完整映射以 `miniprogram/data/ambient-audio.js` 的规则实时计算。当前明确不配音频的类型包括城市、星空、烟火、火山、黑胶、猫、部分山云/瀑布等，避免声音和画面不贴；机械类原则上不硬配，后续仅在用户明确确认的特殊视频上做显式覆盖。

已用 `ffmpeg loudnorm` / `volumedetect` 把 6 个上线用 MP3 转成 128kbps 并检查响度，输出目录：

```text
local-miniprogram-ambient-audio/audio/
```

该目录已加入 `.gitignore`，不要提交或打包进小程序。当前上线音频已上传到腾讯云 COS：

```text
macify-audio/birds.mp3
macify-audio/fire-crackling.mp3
macify-audio/forest-ambience.mp3
macify-audio/light-rain.mp3
macify-audio/ocean-soft-waves.mp3
macify-audio/underwater-ambience.mp3
```

公开视频 URL 均已验证为 `HTTP 200 OK` / `Content-Type: audio/mpeg` / `Cache-Control: public,max-age=2592000,immutable`，示例：

```text
https://macify-videos-1430886267.cos.ap-beijing.myqcloud.com/macify-audio/ocean-soft-waves.mp3
```

上传时第一次 `sync` 误把本地目录名带到了 COS，额外生成了：

```text
macify-audio/audio/*.mp3
```

这份多余对象不被代码引用，不影响小程序；后续可清理以节省约 12MB COS 空间，但不要误删正确的 `macify-audio/*.mp3`。用户在聊天中提供过 `macify-cos-uploader` 的 SecretId/SecretKey；本次只作为命令环境变量使用，未写入文档或文件。上传完成后必须提醒用户禁用或删除该 API 密钥。

本次已执行：

```bash
node --check miniprogram/pages/index/index.js
node --check miniprogram/utils/videos.js
node --check miniprogram/data/ambient-audio.js
npm run mini:premium:validate
```

2026-05-16 继续微调首页环境音映射。用户指定：

```text
阿尔卑斯山径 -> forest-wind-and-birds.mp3
淡水鱼群 -> underwater-ambience.mp3
苔径深林 -> river-stream.mp3
麦田收割 -> tractor-harvesting.mp3
多洛米蒂瀑河、岩瀑白浪等瀑布类 -> waterfall.mp3
雪羽海鸥 -> wind-in-trees.mp3
樱光春枝 -> 无音频
```

已在 `miniprogram/data/ambient-audio.js` 增加显式视频覆盖规则，避免具体视频被通用规则抢错；同时新增 `waterfall`、`river`、`wind`、`tractor`、`forestWindBirds` 音轨。新增本地转码文件：

```text
local-miniprogram-ambient-audio/audio/forest-wind-and-birds.mp3
local-miniprogram-ambient-audio/audio/river-stream.mp3
local-miniprogram-ambient-audio/audio/waterfall.mp3
local-miniprogram-ambient-audio/audio/wind-in-trees.mp3
local-miniprogram-ambient-audio/audio/tractor-harvesting.mp3
```

这些新增 MP3 已做 128kbps 转码和响度检查，并已于 2026-05-16 23:21 上传 COS。上传目标是：

```text
macify-audio/
```

新增文件均已逐条验证为 `HTTP 200 OK` / `Content-Type: audio/mpeg` / `Cache-Control: public,max-age=2592000,immutable`：

```text
macify-audio/forest-wind-and-birds.mp3
macify-audio/river-stream.mp3
macify-audio/waterfall.mp3
macify-audio/wind-in-trees.mp3
macify-audio/tractor-harvesting.mp3
```

本次上传只在当前命令进程中使用用户重新提供的 `COS_SECRET_ID` / `COS_SECRET_KEY`，未写入仓库、文档或脚本；临时配置 `/private/tmp/macify-cos-audio.yaml` 已删除。上传后应提醒用户禁用或删除 `macify-cos-uploader` 的本次 API 密钥。

本次调整后的映射统计：

```text
海浪: 19
水下: 23
森林: 8
山林风鸟: 4
鸟鸣: 5
雨声: 2
炉火: 3
溪流: 2
瀑布: 5
风声: 1
收割机: 1
无音频: 26
```

2026-05-16 继续按用户指定微调环境音：`落日泻湖`、`金云暮天`、`里斯本圣像`、`云隙光束` 改为 `mountain-sky-ambience.mp3`；`瑞士雾海` 改为 `wind-in-trees.mp3`；`雪河气泡` 改为 `river-stream.mp3`；`尼亚加拉白潮`、`青苔溪石` 明确覆盖为 `waterfall.mp3`。代码里均写为视频级覆盖，不把 `sky` 做成全局泛匹配。

本地已从 `/Users/hui/Downloads/sound/mountain and sky ambience.mp3` 转码出：

```text
local-miniprogram-ambient-audio/audio/mountain-sky-ambience.mp3
```

该文件为 128kbps MP3，约 48.024 秒，响度检查约 `mean_volume: -29.7 dB` / `max_volume: -17.5 dB`。已于 2026-05-16 23:30 上传 COS，并验证为 `HTTP 200 OK` / `Content-Type: audio/mpeg` / `Cache-Control: public,max-age=2592000,immutable`：

```text
macify-audio/mountain-sky-ambience.mp3
```

本次上传只在当前命令进程中使用用户重新提供的 `COS_SECRET_ID` / `COS_SECRET_KEY`，未写入仓库、文档或脚本；临时配置 `/private/tmp/macify-cos-audio.yaml` 已删除。上传后应提醒用户禁用或删除 `macify-cos-uploader` 的本次 API 密钥。

本次调整后的映射统计：

```text
海浪: 18
水下: 22
森林: 8
山林风鸟: 3
鸟鸣: 5
雨声: 2
炉火: 3
溪流: 3
瀑布: 5
风声: 2
天空: 4
收割机: 1
无音频: 23
```

2026-05-16 继续按用户指定微调环境音并升级首页多轨混音：`富士晨塔`、`春林直道` 使用 `mountain-sky-ambience.mp3 + birds.mp3`，sky 为主、鸟鸣轻铺；`古堡帆影` 使用 `mountain-sky-ambience.mp3 + wind-in-trees.mp3`，两条都压低音量以保持安静；`山涧白瀑` 明确使用 `waterfall.mp3`；`摩纳哥港`、`云峰落日` 使用 `mountain-sky-ambience.mp3`；`淡水鱼群` 保持 `underwater-ambience.mp3`；`暮海群鸥` 使用新音频 `gentle-ocean-waves-birdsong-and-gull.mp3`。

为支持多轨，`miniprogram/data/ambient-audio.js` 现在可以返回 `tracks[]`；`miniprogram/pages/index/index.js` 将首页环境音拆成多个独立 channel。每个 channel 维护自己的 current audio、下一段 loop 定时器和淡入淡出 timer；多轨混音不会共用一个全局 current/next，也不会让一条音轨的 loop 干扰另一条音轨。

本地已从 `/Users/hui/Downloads/sound/gentle-ocean-waves-birdsong-and-gull.mp3` 转码出：

```text
local-miniprogram-ambient-audio/audio/gentle-ocean-waves-birdsong-and-gull.mp3
```

该文件为 128kbps MP3，约 115.152 秒，响度检查约 `mean_volume: -34.9 dB` / `max_volume: -16.9 dB`。已于 2026-05-16 23:43 上传 COS，并验证为 `HTTP 200 OK` / `Content-Type: audio/mpeg` / `Cache-Control: public,max-age=2592000,immutable`：

```text
macify-audio/gentle-ocean-waves-birdsong-and-gull.mp3
```

本次上传只在当前命令进程中使用用户重新提供的 `COS_SECRET_ID` / `COS_SECRET_KEY`，未写入仓库、文档或脚本；临时配置 `/private/tmp/macify-cos-audio.yaml` 已删除。上传后应提醒用户禁用或删除 `macify-cos-uploader` 的本次 API 密钥。

本次调整后的映射统计（按音轨计数，多轨视频会在多个音轨里各计 1 次）：

```text
海浪: 16
海鸥海浪: 1
水下: 22
森林: 6
山林风鸟: 3
鸟鸣: 6
雨声: 2
炉火: 3
溪流: 3
瀑布: 5
风声: 3
天空: 9
收割机: 1
无音频: 22
```

2026-05-16 继续按用户指定微调环境音：`稻田风机`、`西峡鸟影`、`山田星田`、`雪原冷林`、`晴空云影`、`晨雾阿尔卑斯`、`东京暮色`、`东京夜城` 改为 `mountain-sky-ambience.mp3`；`木舟渔人` 改为 `birds.mp3`；`雏鸭草间` 改为 `forest-wind-and-birds.mp3`。本次只使用已上传音频，不需要新增转码或上传 COS。

2026-05-16 用户要求单独调整 `富士晨塔` 混音：`mountain-sky-ambience.mp3` 音量加大一倍，实际设置到小程序音量上限 `1.0`；`birds.mp3` 鸟声降低 50%，从 `0.16` 改为 `0.08`。只影响 `pixabay-240841`，不改变 `春林直道` 的 sky + birds 混音比例。

2026-05-16 继续按用户指定微调环境音：`冰岛火丘` 改为 `mountain-sky-ambience.mp3`。本次只使用已上传音频，不需要新增转码或上传 COS。

本次调整后的映射统计（按音轨计数，多轨视频会在多个音轨里各计 1 次）：

```text
海浪: 16
海鸥海浪: 1
水下: 22
森林: 5
山林风鸟: 3
鸟鸣: 5
雨声: 2
炉火: 3
溪流: 3
瀑布: 5
风声: 3
天空: 18
收割机: 1
无音频: 15
```

2026-05-17 继续完善设置页、背景音和真机天气：

- 新增设置页“视频背景音”功能，支持 `视频自带音频` 与 `自定义混音` 两种模式。`视频自带音频` 实际播放当前视频对应的预制环境音；`自定义混音` 会在所有视频上固定播放用户保存的混音。
- 自定义混音候选来自 `miniprogram/data/ambient-audio.js`，使用简洁中文名：林中风、瀑布、高空、火、小雨、溪流、鸟叫、山中鸟叫、森林、海浪、海鸥海浪、水下。`tractor` / 收割机音频不进入候选。
- 自定义混音最多 5 个声音；每个声音默认音量 0，选中后高亮并出现音量滑杆。设置页提供“开始试听”，试听和首页播放都使用每个音轨独立 channel + 交叉淡入淡出循环。
- 已讨论 10 个声音混音的风险：10 个声音平时约 10 路音频、交叉循环瞬间约 20 路，可能增加耗电、卡顿、延迟或丢声；当前保持 5 个。
- 自定义混音功能已提交并推送到 private backup 仓库 `lh850718/HuxiZenbackup` 的 `main`，提交 `f0a101d3bfba7017dc2cd302f807a19f049dae8f`，提交备注 `增加自定义混音功能`。
- 首页底部去掉引号 / 格言切换按钮；格言仍可通过点击中心语录区域切换。
- 设置页天气配置改为紧凑布局：城市输入框 + 摄氏度 / 华氏度按钮放在“显示”区天气开关下方，只有天气开关打开时展示；默认城市改为 `北京`。
- 背景视频播放范围改成 4 列网格，减少设置页长度。
- iPhone 真机天气显示问题已加固：北京 / 上海使用内置经纬度；天气请求中支持 JSON 字符串解析；首页天气加载 / 失败时不再静默消失，而显示 `--° 天气加载中` 或 `--° 天气暂不可用`；请求失败时优先沿用旧缓存。
- 首页 / 呼吸页横向手势已调整：首页右滑进入呼吸页、左滑进入设置页；呼吸页左滑返回首页、右滑启动自定义呼吸。设置页新增“保存返回”，并根据 `from=home` / `from=zen` 返回对应状态。
- 首页纯视频模式由长按进入改为单击背景进入，纯视频模式单击背景返回普通首页；首页、呼吸页、纯视频模式都支持双击背景收藏 / 取消收藏当前视频，并显示小字提示。
- 播放回退从“只保留一条上一条”改为本地播放序列索引：下滑可连续回退到本次序列第一条；回退后上滑优先沿序列向前，再从当前随机队列取新视频。
- 环境音显式视频覆盖已从 `ambient-audio.js` 拆到 `miniprogram/data/video-audio-mixes.js`，每条记录包含 `videoId`、`mix` 和 `notes`，为未来 Flutter 版本共用视频 / 音频 / 混音关系做准备。
- 新增 `npm run mini:ambient:validate`，校验音轨、显式视频混音、音量范围、视频 ID、音轨 ID，并统计 published 视频的环境音覆盖情况。当前结果：13 条音轨、32 条显式视频混音、84/99 条公开视频有环境音、15 条无音频。
- 上述“去掉引号按钮 / 设置页紧凑布局 / 天气真机兜底 / 手势与播放序列 / 环境音混音数据抽离 / 文档更新”是在 `f0a101d` 之后的新本地改动；截至本条记录写入时尚未提交和推送。

继续工作时可以继续找下一批候选。下一次上传 COS 前必须重新向用户索取新的 `COS_SECRET_ID` / `COS_SECRET_KEY`。视频只允许上传到 `macify-premium/videos/`；首页环境音只允许上传到 `macify-audio/`；不要触碰 Apple 历史路径 `macify/videos/`。

### 2026-05-10 暂停交接：Pixabay 批量候选待继续

用户随后提供了一批 Pixabay 链接，要求继续做本地裁切样片，并特别说明：

```text
campfire-flames-night-fire-camp-257593 这一条火苗在画面偏右，裁切时注意让火苗在画面中央。
```

用户还问“视频制作记录里有没有保留源链接，方便后面其他尺寸裁切”。答复要点：

- 是的，正式清单 `miniprogram/data/premium-free-aerial-videos.js` 每条都保留 `sourcePage`、`sourceDownloadPage`、`url`、`previewImage`。
- 本地输出 `local-miniprogram-premium-aerial/manifest.json` 也保留 `sourceUrl`。
- 后续做横屏、平板、不同码率、不同裁切时，应优先复用这些字段。

本轮已完成但尚未收尾：

1. 已从用户列表去重，`winter-river-forest-landscape-330898` 重复出现一次，只保留 1 条；当前待处理 Pixabay 唯一候选数为 18。
2. 已通过 ImageURLGenerator 的 `/api/pixabay` 代理拿到官方 `cdn.pixabay.com` MP4 直链。该代理前端说明其底层使用官方 Pixabay API；Pixabay 官方 API 文档说明视频响应包含 `large/medium/small/tiny` MP4 URL，并建议把视频存到自己的服务上。
3. 已用 `ffprobe` 探测源视频分辨率、时长、帧率。
4. 已修改 `scripts/miniprogram/prepare-lite-videos.mjs`，新增可选清单字段：

```text
cropFocusX: 0..1
cropFocusY: 0..1
```

默认仍为中心裁切 `0.5 / 0.5`。如果某条视频设置了 `cropFocusX`，竖屏 9:16 裁切会把该横向焦点尽量放到画面中央。下一轮给火堆条目应设置：

```js
cropFocusX: 0.63
```

尚未完成：

- 尚未把这 18 条 Pixabay 写入 `miniprogram/data/premium-free-aerial-videos.js`。
- 尚未更新顶部候选数量表里的 Pixabay 数量。
- 尚未运行新增后的 `npm run mini:premium:validate`。
- 尚未生成这 18 条本地 1080p 样片。
- 尚未检查火堆样片截图确认火苗居中。
- 没有上传 COS，也不要上传；这些只是 candidate 样片。

下一轮继续步骤：

1. 在 `premium-free-aerial-videos.js` 末尾追加下面 18 条，`sourceName: 'Pixabay'`，`qualityTier: 'candidate'`。
2. 同步顶部候选数量表：

```text
Pixabay | 100 | 18 | 0 | 0 | 本轮新增 18 条 Pixabay 候选，待用户审片，不上传 COS
```

3. 运行：

```bash
npm run mini:premium:validate
```

4. 只为这 18 条生成本地样片：

```bash
node scripts/miniprogram/prepare-lite-videos.mjs \
  --source premiumFreeAerial \
  --out-dir local-miniprogram-premium-aerial \
  --height 1080 \
  --duration 45 \
  --profile main \
  --crf 20 \
  --maxrate 8000k \
  --bufsize 16000k \
  --cdn-base https://macify-videos-1430886267.cos.ap-beijing.myqcloud.com/macify-premium \
  --id pixabay-348904,pixabay-347325,pixabay-257593,pixabay-344380,pixabay-76681,pixabay-339840,pixabay-345244,pixabay-328740,pixabay-333600,pixabay-334716,pixabay-330898,pixabay-323513,pixabay-181376,pixabay-326677,pixabay-260895,pixabay-326739,pixabay-325502,pixabay-338904 \
  --overwrite
```

5. 为火堆样片抽帧检查：

```bash
ffmpeg -y -ss 00:00:05 \
  -i local-miniprogram-premium-aerial/videos/pixabay-257593.mp4 \
  -frames:v 1 /private/tmp/pixabay-257593-campfire-check.jpg
```

6. 回复用户时给出 18 个本地样片链接。用户确认前不得上传 COS，不得标记 `published`。

Pixabay 待追加候选源信息：

```text
id: pixabay-348904
displayName: 岩岸海浪
sourcePage: https://pixabay.com/videos/wave-rock-horizon-ocean-sun-beach-348904/
url: https://cdn.pixabay.com/video/2026/04/25/348904_large.mp4
previewImage: https://cdn.pixabay.com/video/2026/04/25/348904_large.jpg
sourceResolution: 4K 3840x2160
duration: 0:42
attribution: Mario_Krimer / Pixabay

id: pixabay-347325
displayName: 云峰落日
sourcePage: https://pixabay.com/videos/mountains-peaks-clouds-sunset-sky-347325/
url: https://cdn.pixabay.com/video/2026/04/17/347325_large.mp4
previewImage: https://cdn.pixabay.com/video/2026/04/17/347325_large.jpg
sourceResolution: 4K 3840x2160
duration: 0:20
attribution: doktorkleinmusic / Pixabay

id: pixabay-257593
displayName: 夜营火光
sourcePage: https://pixabay.com/videos/campfire-flames-night-fire-camp-257593/
url: https://cdn.pixabay.com/video/2025/02/10/257593_large.mp4
previewImage: https://cdn.pixabay.com/video/2025/02/10/257593_large.jpg
sourceResolution: 4K 3840x2160
duration: 0:15
attribution: JoshuaWoroniecki / Pixabay
cropFocusX: 0.63

id: pixabay-344380
displayName: 蓝海航岸
sourcePage: https://pixabay.com/videos/aerial-view-beach-blue-water-carbon-344380/
url: https://cdn.pixabay.com/video/2026/04/03/344380_large.mp4
previewImage: https://cdn.pixabay.com/video/2026/04/03/344380_large.jpg
sourceResolution: 4K 3840x2160
duration: 0:15
attribution: Shutter_Footage / Pixabay

id: pixabay-76681
displayName: 岩瀑白浪
sourcePage: https://pixabay.com/videos/waterfall-rock-foaming-roaring-76681/
url: https://cdn.pixabay.com/video/2021/06/06/76681-559745365_large.mp4
previewImage: https://cdn.pixabay.com/video/2021/06/06/76681-559745365_large.jpg
sourceResolution: 4K 3840x2160
duration: 0:16
attribution: xat-ch / Pixabay

id: pixabay-339840
displayName: 海上冲浪
sourcePage: https://pixabay.com/videos/surfer-nature-sea-beach-surfboard-339840/
url: https://cdn.pixabay.com/video/2026/03/12/339840_large.mp4
previewImage: https://cdn.pixabay.com/video/2026/03/12/339840_large.jpg
sourceResolution: 4K 3840x2160
duration: 0:29
attribution: TonyDias7 / Pixabay
note: 含人物主体，需用户重点审片决定是否保留。

id: pixabay-345244
displayName: 翠鸟河畔
sourcePage: https://pixabay.com/videos/kingfisher-bird-fauna-river-345244/
url: https://cdn.pixabay.com/video/2026/04/08/345244_large.mp4
previewImage: https://cdn.pixabay.com/video/2026/04/08/345244_large.jpg
sourceResolution: Full HD 1920x1080
duration: 0:10
attribution: danydory / Pixabay

id: pixabay-328740
displayName: 晨雾阿尔卑斯
sourcePage: https://pixabay.com/videos/alps-sunrise-fog-sea-of-fog-clouds-328740/
url: https://cdn.pixabay.com/video/2026/01/19/328740_large.mp4
previewImage: https://cdn.pixabay.com/video/2026/01/19/328740_large.jpg
sourceResolution: 4K 3840x2160
duration: 0:46
attribution: adege / Pixabay

id: pixabay-333600
displayName: 冬梅红花
sourcePage: https://pixabay.com/videos/flowers-red-plum-winter-flowers-333600/
url: https://cdn.pixabay.com/video/2026/02/09/333600_large.mp4
previewImage: https://cdn.pixabay.com/video/2026/02/09/333600_large.jpg
sourceResolution: 4K 3840x2160
duration: 0:24
attribution: Kanenori / Pixabay

id: pixabay-334716
displayName: 佛得角海岸
sourcePage: https://pixabay.com/videos/boa-vista-cape-verde-nature-sea-334716/
url: https://cdn.pixabay.com/video/2026/02/15/334716_large.mp4
previewImage: https://cdn.pixabay.com/video/2026/02/15/334716_large.jpg
sourceResolution: QHD 2560x1440
duration: 1:20
attribution: JonPauling / Pixabay

id: pixabay-330898
displayName: 冬河森林
sourcePage: https://pixabay.com/videos/winter-river-forest-landscape-330898/
url: https://cdn.pixabay.com/video/2026/01/28/330898_large.mp4
previewImage: https://cdn.pixabay.com/video/2026/01/28/330898_large.jpg
sourceResolution: 4K 4096x2160
duration: 0:08
attribution: danydory / Pixabay

id: pixabay-323513
displayName: 摩纳哥港
sourcePage: https://pixabay.com/videos/monaco-wealth-yachts-money-marina-323513/
url: https://cdn.pixabay.com/video/2025/12/21/323513_large.mp4
previewImage: https://cdn.pixabay.com/video/2025/12/21/323513_large.jpg
sourceResolution: 4K 3840x2160
duration: 0:41
attribution: D-GM / Pixabay
note: 船只主体较多，需用户重点审片决定是否保留。

id: pixabay-181376
displayName: 木舟渔人
sourcePage: https://pixabay.com/videos/boat-man-fishing-boat-wooden-boat-181376/
url: https://cdn.pixabay.com/video/2023/09/20/181376-866506956_large.mp4
previewImage: https://cdn.pixabay.com/video/2023/09/20/181376-866506956_large.jpg
sourceResolution: 4K 3840x2160
duration: 0:16
attribution: NickyPe / Pixabay
note: 含人物和船主体，需用户重点审片决定是否保留。

id: pixabay-326677
displayName: 夜空烟火
sourcePage: https://pixabay.com/videos/fireworks-party-celebrate-new-year-326677/
url: https://cdn.pixabay.com/video/2026/01/08/326677_large.mp4
previewImage: https://cdn.pixabay.com/video/2026/01/08/326677_large.jpg
sourceResolution: 4K 3840x2160
duration: 0:17
attribution: Gylfi / Pixabay

id: pixabay-260895
displayName: 里斯本圣像
sourcePage: https://pixabay.com/videos/statue-jesus-cristo-rey-lisbon-260895/
url: https://cdn.pixabay.com/video/2025/02/25/260895_large.mp4
previewImage: https://cdn.pixabay.com/video/2025/02/25/260895_large.jpg
sourceResolution: 4K 3840x2160
duration: 0:12
attribution: Obsidian_Ardor / Pixabay

id: pixabay-326739
displayName: 姬路城竖景
sourcePage: https://pixabay.com/videos/japanese-castle-castle-himeji-castle-326739/
url: https://cdn.pixabay.com/video/2026/01/09/326739_large.mp4
previewImage: https://cdn.pixabay.com/video/2026/01/09/326739_large.jpg
sourceResolution: Vertical 4K 2160x3840
duration: 0:28
attribution: Kanenori / Pixabay

id: pixabay-325502
displayName: 雪原冷林
sourcePage: https://pixabay.com/videos/winter-snow-nature-cold-frost-325502/
url: https://cdn.pixabay.com/video/2026/01/02/325502_large.mp4
previewImage: https://cdn.pixabay.com/video/2026/01/02/325502_large.jpg
sourceResolution: 4K 3840x2160
duration: 0:20
attribution: reelcity / Pixabay

id: pixabay-338904
displayName: 浅滩海纹
sourcePage: https://pixabay.com/videos/beach-nature-sea-sand-ocean-water-338904/
url: https://cdn.pixabay.com/video/2026/03/08/338904_large.mp4
previewImage: https://cdn.pixabay.com/video/2026/03/08/338904_large.jpg
sourceResolution: 4K 3840x2160
duration: 0:24
attribution: TonyDias7 / Pixabay
```

### 2026-05-10 续作完成：Pixabay 18 条候选样片

已完成：

- 已将上述 18 条 Pixabay 写入 `miniprogram/data/premium-free-aerial-videos.js`，初始为 `qualityTier: 'candidate'`；用户随后确认都没问题，已上传 COS 到 `macify-premium/videos/`，逐条验证 `200 video/mp4`，并改为 `qualityTier: 'published'`。
- 已同步顶部候选数量表：`Pixabay | 100 | 18 | 0 | 18 | 18 条 Pixabay 样片已通过审片并上传 COS，已标记 published`。
- 已运行 `npm run mini:premium:validate`，结果通过：`Validated 25 premium free aerial video candidate(s).`
- 已生成 18 条本地 1080p 样片到 `local-miniprogram-premium-aerial/videos/`，并重建 `local-miniprogram-premium-aerial/manifest.json` / `manifest.csv`，报告包含 18 行。
- 火堆 `pixabay-257593` 原交接建议 `cropFocusX: 0.72`，抽帧后发现火苗偏左；已改为 `cropFocusX: 0.63` 并重生成该样片。最终检查图：`/private/tmp/pixabay-257593-campfire-check.jpg`。

注意：

- `pixabay-181376` 转码时 Pixabay CDN 曾提前断流，但 ffmpeg 仍写出 14.67s 的本地 MP4，`ffprobe` 可正常读取。该条本身含人物和船主体，审片时应重点看是否保留。
- 本轮已上传并验证完成。收尾时已确认 `/private/tmp/macify-cos.yaml` 不存在；请禁用/删除本次 `macify-cos-uploader` API 密钥。

如果用户明确说某条或某批样片“可以 / 通过 / 合格 / 上传”，接手者应直接跑完整流程：改为 `sample-approved`、上传 COS、验证公开视频 `200 OK`、改为 `published`、同步本文档和计数、运行 `npm run mini:premium:validate`，最后一次性汇报。中间不要停在 `sample-approved` 等用户二次确认；唯一例外是上传前仍必须重新索取本次 `COS_SECRET_ID` / `COS_SECRET_KEY`。

### 高端免费航拍单条视频快捷 SOP

后续每一条非 Apple 视频都按下面流程走。任何步骤如果和顶部硬性原则冲突，一律停下并回到顶部硬性原则。

1. 选候选：只从 `Mixkit` / `Pexels` / `Pixabay` / `Dareful` / `Coverr` 选，优先 4K、慢、稳、干净、无人物/水印/logo/字幕的航拍或自然延时。
2. 补清单：在 `miniprogram/data/premium-free-aerial-videos.js` 新增记录，字段必须补齐来源、授权、地点/场景、中文说明，`category` 只能是 `Landscapes` / `Cities` / `AnimalsAndPlants` / `Motion` / `Underwater`，初始 `qualityTier: 'candidate'`。本地样片给用户审片时，必须同时列出 `displayName`、`locationName`、`description` 供用户确认。
3. 本地样片：先运行校验，再只生成这条样片：

```bash
npm run mini:premium:validate
node scripts/miniprogram/prepare-lite-videos.mjs \
  --source premiumFreeAerial \
  --out-dir local-miniprogram-premium-aerial \
  --height 1080 \
  --duration 45 \
  --profile main \
  --crf 20 \
  --maxrate 8000k \
  --bufsize 16000k \
  --cdn-base https://macify-videos-1430886267.cos.ap-beijing.myqcloud.com/macify-premium \
  --id <video-id> \
  --overwrite
```

4. 给用户审片：回复里必须给本地视频链接，例如：

```markdown
![样片](/Users/hui/Projects/Macify/local-miniprogram-premium-aerial/videos/<video-id>.mp4)
```

5. 用户确认前：不得上传 COS，不得改 `published`。用户确认通过的样片先改 `qualityTier: 'sample-approved'`；用户未通过的样片直接从 `premium-free-aerial-videos.js` 删除，并删除对应本地 MP4，不保留 `rejected`。删除后必须同步顶部候选数量表并运行 `npm run mini:premium:validate`。
6. 删除未通过样片后，必须重新生成本地输出报告，确保 `local-miniprogram-premium-aerial/manifest.json` / `manifest.csv` 只包含当前有效集合，避免上传时误带已删除样片。已有 MP4 可以被脚本标记为 `skipped`，这是正常状态。

```bash
node scripts/miniprogram/prepare-lite-videos.mjs \
  --source premiumFreeAerial \
  --out-dir local-miniprogram-premium-aerial \
  --height 1080 \
  --duration 45 \
  --profile main \
  --crf 20 \
  --maxrate 8000k \
  --bufsize 16000k \
  --cdn-base https://macify-videos-1430886267.cos.ap-beijing.myqcloud.com/macify-premium \
  --id <comma-separated-current-valid-video-ids>
```

7. 如果用户明确说“可以 / 通过 / 合格 / 上传”，确认通过的样片不要停在中间状态；上传前必须在当前会话重新向用户索取 `COS_SECRET_ID` / `COS_SECRET_KEY`，不能从历史、文档或文件里找密钥，不能把密钥写入任何文件。
8. 上传 Premium：只允许上传到 `macify-premium/videos/`，推荐命令：

```bash
npm run mini:cos -- \
  --bucket macify-videos-1430886267 \
  --region ap-beijing \
  --cdn-base https://macify-videos-1430886267.cos.ap-beijing.myqcloud.com/macify-premium \
  --out-dir local-miniprogram-premium-aerial \
  --prefix macify-premium \
  --public-read
```

9. 上传脚本遇到旧视频可能显示 `skip 1 files`，这不是失败。`--public-read` 会对 manifest 里的 ready 视频逐个补 `object-acl --acl public-read`，即使视频被 `sync` 跳过，也必须确保 ACL 被补上。
10. 上传后验证：用 `curl -L -I https://macify-videos-1430886267.cos.ap-beijing.myqcloud.com/macify-premium/videos/<video-id>.mp4` 逐条确认返回 `200 OK` 且 `Content-Type: video/mp4`。不要只看 manifest 成功。
11. 标记发布：公开视频可访问后，才把该条改为 `qualityTier: 'published'`，同步顶部候选数量表和当前下一步记录，再运行 `npm run mini:premium:validate`。
12. 收尾安全：确认 `/private/tmp/macify-cos.yaml` 不存在；用 `rg` 扫描仓库，确认本次明文 `SecretId` / `SecretKey` 没有写入文件；提醒用户禁用/删除 `macify-cos-uploader` 或删除本次 API 密钥。

## 当前仓库状态

- 仓库路径：`/Users/hui/Projects/Macify`
- 小程序路径：`/Users/hui/Projects/Macify/miniprogram`
- 当前已有本地 commit：`2b633cd Add WeChat mini program prototype`
- 该 commit 只是本地 Git 提交，尚未 push 到 GitHub。
- 当前工作区在该 commit 之后又做了 Apple 1080 H264 改造，尚未提交。

## 为什么做微信小程序版

原项目是 Chrome 扩展，用 Svelte + Vite + CRX，把 Chrome 新标签页替换成 Apple macOS Aerial 视频背景，并叠加时间、天气、语录、Top Sites 等组件。

微信小程序不能直接复用 Chrome 扩展能力：

- 没有 Chrome `topSites`
- 没有 Chrome extension storage
- 没有浏览器扩展后台脚本
- Svelte/CRX 打包方式不适用于原生小程序

因此采用“保留原 Chrome 版本，新增原生小程序目录”的方式，而不是直接改坏原项目。

## 当前小程序架构

新增目录：

```text
miniprogram/
  app.js
  app.json
  app.wxss
  project.config.json
  sitemap.json
  data/
    quotes.js
    apple-aerial-1080.js
  pages/
    index/
    settings/
  utils/
    quotes.js
    storage.js
    videos.js
    weather.js
```

根目录也保留了 `project.config.json`，其中设置：

```json
"miniprogramRoot": "miniprogram/"
```

这样微信开发者工具选择根目录或 `miniprogram` 目录都能运行。更推荐选择：

```text
/Users/hui/Projects/Macify/miniprogram
```

后端服务选择 `Use no cloud service`，当前没有使用微信云开发。

## 已实现功能

首页：

- 全屏 Apple 航拍视频背景
- 时间和日期
- 天气卡片，点击后打开底部天气详情面板
- 随机语录，点击语录会换一条
- 当前视频名
- 左下角小圆圈进入基础冥想模式
- 右下角低调图标：
  - `↻` 换视频
  - `···` 设置

设置页：

- 时间开关
- 天气开关
- 语录开关
- 视频信息开关
- 保留呼吸页设置，默认关闭；只影响触感和颂钵音，切后台再回来仍先静音
- 城市设置
- 摄氏/华氏
- 视频播放范围，已从 picker 改成 6 个直接铺开的高亮选项
- 视频源选择
  - 内置 1080P视频
  - 轻量 CDN
- 反向代理开关
- 代理根域名，只有打开反向代理时显示
- 轻量 CDN 根域名，只有选择轻量 CDN 时显示

网络：

- 天气使用 Open-Meteo：
  - `https://api.open-meteo.com`
  - `https://geocoding-api.open-meteo.com`
- Apple 视频默认直连：
  - `https://sylvan.apple.com`

微信公众平台合法域名需要配置：

```text
request 合法域名:
https://api.open-meteo.com;https://geocoding-api.open-meteo.com

downloadFile 合法域名:
https://sylvan.apple.com
```

注意后台输入多个域名时使用英文分号 `;` 分隔，不要在末尾加多余分号。

## 从 4K 改到 1080 H264 的前因后果

### 初始问题

一开始小程序复用了原项目的 `src/data/videos.json`，也复制成：

```text
miniprogram/data/videos.js
```

这份数据来自新 macOS Aerial manifest，视频 URL 主要是：

```text
https://sylvan.apple.com/itunes-assets/..._sdr_4k_...mov
```

也就是 Apple 新版 `url-4K-SDR-240FPS` 源。

真机测试发现：

- 微信开发者工具模拟器卡
- 真机 Preview 也卡
- 大约 3 秒左右就断或卡顿

这说明问题不是模拟器，而是小程序直接播放 Apple 4K `.mov` 源不稳定。

### 为什么 Chrome 扩展不卡，小程序卡

Chrome on Mac 播放不卡，不代表微信小程序能播得动。

差异点：

- 桌面 Chrome/Mac 使用更强的媒体栈和硬件解码
- 桌面浏览器的缓冲、Range 请求、内存和解码容忍度更强
- 微信小程序 `<video>` 是微信内置组件，不等同于 Chrome 播放器
- Apple 新源很多是 4K、HEVC、MOV、240fps、高码率
- 小程序真机更容易受内存、缓存、解码和网络策略限制

同样是蜂窝网络，播放器能力和缓存策略也完全不同。

### 实测 Apple 4K 文件大小

新增脚本：

```text
scripts/miniprogram/fetch-apple-video-sizes.mjs
```

用于对 Apple 4K URL 做 HEAD 请求，读取 `content-length`。

结果记录在：

```text
scripts/miniprogram/video-size-cache.json
```

实测发现 156 条中很多非常大：

- Tahoe Day：约 445MB
- Goa Coast：约 1042MB
- Reservoir Day：约 1047MB
- Iceland 某些超过 1.4GB
- 小于 50MB：4 条
- 小于 150MB：9 条
- 小于 200MB：15 条
- 小于 300MB：44 条

因此直接随机播放 156 条 4K 原片，必然经常撞到几百 MB 到 1GB+ 的视频，小程序 3 秒断很合理。

### 关于 macOS manifest 和 1080 URL 的误解

本机新 macOS manifest 路径：

```text
~/Library/Application Support/com.apple.wallpaper/aerials/manifest/entries.json
```

系统 fallback manifest：

```text
/System/Library/PrivateFrameworks/WallpaperAerialAssets.framework/Versions/A/Resources/entries.json
```

本机检查结果：

```text
用户 manifest: 只有 url-4K-SDR-240FPS，共 156 条
系统 manifest: 只有 url-4K-SDR-240FPS，共 152 条
```

没有：

```text
url-1080-SDR-240FPS
url-1080-HDR-240FPS
```

这只说明“当前新版 macOS manifest 没有 1080 字段”，不是说 Apple 所有 Aerial feed 都没有 1080。

原项目下载器中有：

```text
scripts/aerial_downloader/manifest.py
```

其中 `FALLBACK_URL_KEYS` 包含：

```python
"url-1080-SDR-240FPS",
"url-1080-HDR-240FPS",
```

这表示下载器能识别这些字段；但字段是否真实存在，取决于具体 manifest。

### 联网发现 Apple 旧版 Aerial feed 有 1080

联网查询后发现 Apple 旧版/tvOS Aerial feed 仍可访问：

```text
https://sylvan.apple.com/Aerials/2x/entries.json
https://sylvan.apple.com/Aerials/resources-16.tar
```

`Aerials/2x/entries.json` 有少量：

```text
url-1080-SDR
url-4K-SDR
```

更关键的是：

```text
https://sylvan.apple.com/Aerials/resources-16.tar
```

里面的 `entries.json` 有 114 条视频，每条都有：

```text
url-1080-H264
url-1080-SDR
url-1080-HDR
url-4K-SDR
url-4K-HDR
```

其中 `url-1080-H264` 最适合微信小程序，因为：

- 仍然是 Apple 官方视频 URL
- 1080/2K，比 4K 轻
- H.264/AVC 通常比 HEVC 在小程序里更兼容
- URL 路径形如：

```text
https://sylvan.apple.com/Videos/..._2K_AVC.mov
```

示例：

```text
https://sylvan.apple.com/Videos/SE_A016_C009_SDR_20190717_SDR_2K_AVC.mov
```

### 当前已实施的 1080 改造

新增数据文件：

```text
miniprogram/data/apple-aerial-1080.js
```

生成来源：

```text
https://sylvan.apple.com/Aerials/resources-16.tar
```

取其中：

```text
assets[*]["url-1080-H264"]
```

共 114 条。

历史当时 `miniprogram/utils/storage.js` 默认：

```js
videoSource: 'apple1080'
```

并兼容旧本地设置：

```js
if (settings.videoSource === 'apple' || settings.videoSource === 'original4k') {
  settings.videoSource = 'apple1080';
}
```

`miniprogram/utils/videos.js` 当前逻辑：

- `apple1080`：使用 `miniprogram/data/apple-aerial-1080.js`
- `lite`：使用自定义 CDN 地址 `https://your-cdn.example.com/videos/<id>.mp4`

设置页显示为：

- 内置 1080P视频
- 轻量 CDN

注意：这一段是 1080 改造早期记录。当前默认已经改为 Apple 轻量 MP4，即 `videoSource: 'lite'`，Apple COS base 为 `https://macify-videos-1430886267.cos.ap-beijing.myqcloud.com/macify`；进入小程序默认播放范围应为 `all`；“直接 URL”入口已删除。

轻量 CDN 不能随便填一个单独视频 URL。当前逻辑会把这里当成 CDN 根域名，然后拼接：

```text
<liteVideoBase>/videos/<video-id>.mp4
```

所以 CDN 上需要按 Apple Aerial 的视频 ID 准备同名 mp4 文件。

注意：Bilibili 这类页面链接不是视频直链，例如：

```text
https://www.bilibili.com/video/BV...
https://b23.tv/...
```

Pixabay 的 `https://pixabay.com/videos/download/...` 下载地址也不适合直接塞给小程序 `<video>`，可能返回网页验证或被防盗链拦截。更稳的方式是先把素材转码/上传到自有 COS/CDN，再走素材库流程。

小程序 `<video>` 不能直接播放网页地址。即使拿到 B 站内部媒体 URL，也可能因为鉴权、Referer、防盗链、短期签名或合法域名限制而无法稳定播放；更稳的方式是使用自有 CDN 或服务端代理/转码后的地址。

### 1080 后仍需注意

1080 H264 仍然不算小。抽样 HEAD：

- `SE_A016...2K_AVC.mov` 约 274MB
- `comp_A114...2K_AVC.mov` 约 220MB

相比 4K 几百 MB 到 1.4GB 明显好很多，但仍然会消耗较多流量，也可能受小程序视频组件影响。

如果真机仍卡，下一步应考虑：

1. 用 `/Videos/*` 反向代理改善连接稳定性
2. 只播放更小的 1080 H264 子集
3. 做服务器端 HLS/MP4 轻量转码
4. 或改原生 iOS/Android App，用更强的播放器和缓存能力

## 反向代理和 Worker

原 `cloudflare-worker/worker.js` 只允许：

```text
/itunes-assets/*
```

但 Apple 1080 H264 feed 使用：

```text
/Videos/*
```

因此当前已修改 Worker：

```js
const ALLOWED_PATH_PREFIXES = ['/itunes-assets/', '/Videos/'];
```

后续如果使用代理域名，要确保 Cloudflare Worker 路由覆盖：

```text
https://your-host.example.com/itunes-assets/*
https://your-host.example.com/Videos/*
```

小程序设置页中：

- 打开 `反向代理`
- 代理域名只填根域名，例如：

```text
https://your-host.example.com
```

不要填 `/Videos`，不要加最后的 `/`。

## UI 调整记录

首页底部按钮经历过一次误改：

- 曾改成大按钮 `换视频 / 设置`
- 用户认为太丑，已恢复为低调图标

当前右下角为普通 `view`，不是小程序 `button`，因为 `button` 默认样式会撑歪布局。

当前图标：

```text
↻   换视频
··· 设置
```

天气卡片已往下挪，避免和微信右上角胶囊按钮重合。

左上角不再显示“全部”，只显示视频名。此前“全部”表示播放全部分类，但看起来像不可点击标签，已移除。

视频名交互已新增：

- 点击左上角视频名会打开底部介绍面板
- 介绍使用 `miniprogram/data/video-intros.js`
- 当前按 52 个唯一视频名称覆盖 114 条 Apple 1080 H264 视频
- 内容是地点/场景的人文气质短介绍，不展示视频源、分类等技术信息
- 该文案表约 8.6KB，不会造成 preview 包体积明显膨胀

设置页交互已调整：

- 播放范围不再使用 picker，改为 6 个铺开的选项，当前选中项高亮
- 反向代理的域名输入框只在打开反向代理后显示
- 轻量 CDN 的域名输入框只在视频源选择轻量 CDN 后显示
- 轻量 CDN 输入的是根域名，不是单个视频 URL；小程序会自动拼接 `/videos/<video-id>.mp4`
- `直接 URL` 视频源已删除，不再作为设置项
- 底部操作区只保留主按钮 `保存并返回`，会先主动提交当前输入框里的值再返回；`恢复默认` 操作已移除

天气交互已补回：

- Chrome 版是 hover 展开天气详情
- 小程序没有 hover，当前改成点击天气卡片打开底部详情面板
- 面板展示当前温度、体感、3 日天气、降水概率、风速

语录交互已补回：

- 点击中心语录区域会调用 `nextQuote()` 换一条

冥想功能已从基础版对齐到 Chrome 版核心体验：

- 左下角入口改为和 Chrome 扩展一致的 `mingcute/zazen-line` 坐禅 icon
- 进入后隐藏普通叠层，保留视频背景
- 中间呼吸动画改为 Chrome 版同款 6 花瓣结构
- 默认使用 Chrome 版 `coherent` 呼吸节奏：5 秒吸气展开、5 秒呼气收拢
- 花朵缩放范围对齐 Chrome：`0.45 -> 1.2 -> 0.45`
- 花朵持续 36 秒慢旋转，花瓣尺寸、角度和径向渐变复用 Chrome 版参数
- 标签显示 `吸气 / 呼气`
- 冥想页内新增 `触感` 开关，默认关闭
- 重新进入小程序时，默认（未开启“保留呼吸页设置”）会自动关闭触感和颂钵音，避免突然振动或响声
- 设置页新增 `保留呼吸页设置`，默认关闭；打开后会记住上次触感/颂钵音偏好，但切后台再回来仍先关闭颂钵音，避免自动恢复声音
- 触感 / 颂钵音控制放在冥想页最底部，不放在花朵和呼吸标签附近
- 控制不使用 `switch`，直接点击 `触感` / `颂钵音` 两个字切换状态
- 开启态文字微亮，关闭态文字非常暗，保持冥想画面低干扰
- 退出控件从 `退出` 文字改成右下角低存在感小箭头 `‹`
- 触感节奏和花朵同步：
  - 触感相对视觉吸气提前约 `850ms` 发出指令，用来抵消真机 `wx.vibrateShort` 约 1 秒的系统触发延迟
  - 指令从呼气最后 `850ms` 开始预排队，实际手感目标仍覆盖吸气阶段
  - 吸气阶段：15 次短振动，开头保持较密，后半段平缓提升，不在末尾突然堆高频
  - 强度随吸气推进从 `light -> medium -> heavy`
  - 呼气阶段：显式清空所有振动 timer，不振动，让身体自然放松
  - 触感调度使用明确的 5 秒吸气 / 5 秒呼气相位循环，不再用轮询判断相位，避免振动串到呼气阶段
  - 点击 `触感` 时弹出 `需要打开手机振动功能`，2 秒后消失
- 冥想页内新增 `颂钵音` 开关，默认关闭
- 颂钵音方案：
  - 使用本地 `miniprogram/assets/breath.mp3`，不增加合法域名
  - 打开颂钵音后持续播放，不再和吸气/呼气相位绑定
  - 用户提供的原始 `breath.mp3` 约 85.68 秒，末尾约 8 秒无效，已按 MP3 帧裁剪到约 77.66 秒
  - 2026-05-10 又发现 77.66 秒版本开头仍有明显空白；用 `ffmpeg silencedetect` 和 PCM 采样检测确认：
    - `-80dB` / `-70dB` 口径声音起点约 `14.280125s`
    - `-60dB` 口径声音起点约 `14.301375s`
    - 结尾没有同等意义的完全空白，只是最后约 0.1 秒音量较低
  - 已保守裁掉开头 `14.280125s`，新文件约 `63.383875s`，约 `1.21MB`
  - 原始裁剪前文件已备份到 `local-miniprogram-audio/breath-original-before-trim-20260510.mp3`，该目录已加入 `.gitignore`
  - 旧的 `breath-inhale.wav` 和 `breath-exhale.wav` 已删除
  - 播放不再依赖 `loop = true` 硬循环；当前使用两个 `wx.createInnerAudioContext({ useWebAudioImplement: true })` 实例，在音频结束前约 `2.2s` 启动下一条并交叉淡入淡出
  - `onTimeUpdate` 会优先按真实 `duration/currentTime` 触发交叉；另有 `63.384s` 固定时长定时器兜底；`onEnded` 只作为漏触发时的兜底
- 右下角 `退出` 离开冥想
- 当前小程序版尚未接入 Chrome 版的音乐、自动退出、提醒追踪、完整呼吸模式设置
- Chrome 版 Zen mode 依赖 fullscreen API 和音频资源；小程序需另行设计音乐资源和播放策略

## 已新增脚本

### 1. 探测 Apple 4K 文件大小

```text
scripts/miniprogram/fetch-apple-video-sizes.mjs
```

用途：

```bash
node scripts/miniprogram/fetch-apple-video-sizes.mjs 8
```

输出：

```text
scripts/miniprogram/video-size-cache.json
```

注意：

- 网络可能偶发 DNS/SSL 失败
- 已经生成过一次结果

### 2. 准备自建轻量视频

```text
scripts/miniprogram/prepare-lite-videos.mjs
```

用途：把 Apple 横屏 `.mov` 源批量裁成竖屏中间区域，再转成安卓微信更稳的 H.264 MP4，并生成可上传 CDN 的目录：

```text
local-miniprogram-lite/
  videos/<video-id>.mp4
  manifest.json
  manifest.csv
  README.md
  wechat-settings.txt
```

默认读取：

```text
miniprogram/data/apple-aerial-1080.js
```

也可以读取原 Chrome/macOS 4K 源：

```bash
npm run mini:lite -- --source apple4k --limit 5 --cdn-base https://your-cdn.example.com/macify
```

默认输出：

```text
9:16 竖屏中心裁切 / 1080p 高 / 30fps / H.264 / yuv420p / 前 45 秒
```

以当前 1920x1080 Apple AVC 源为例，默认输出约 `606x1080`。像素量约为原横屏的三分之一，体积和解码压力都会下降，同时比整张横屏缩小更适合竖屏手机。这样比直接播放 Apple `.mov` 更适合安卓微信小程序。`local-miniprogram-lite/` 已加入 `.gitignore`，避免把转码产物提交进仓库。

只看计划，不实际转码：

```bash
npm run mini:lite -- --limit 5 --dry-run
```

生成一小批测试视频：

```bash
npm run mini:lite -- --limit 5 --cdn-base https://your-cdn.example.com/macify
```

生成全部视频：

```bash
npm run mini:lite -- --cdn-base https://your-cdn.example.com/macify
```

如需全片而不是前 45 秒：

```bash
npm run mini:lite -- --full --cdn-base https://your-cdn.example.com/macify
```

如需保留整张横屏画面而不是竖屏裁切：

```bash
npm run mini:lite -- --mode fit --height 720 --limit 5 --cdn-base https://your-cdn.example.com/macify
```

输出后上传整个 `local-miniprogram-lite/` 到 CDN，保持 `/videos/<video-id>.mp4` 路径。小程序设置页选择 `轻量 CDN`，填写 CDN 根域名，例如：

```text
https://your-cdn.example.com/macify
```

微信公众平台还需要把 CDN 根域名配置进 `downloadFile` 合法域名。

本机已检测到：

```bash
/opt/homebrew/bin/ffmpeg
/opt/homebrew/bin/ffprobe
```

旧版整帧 720p 样片验证曾输出 `1280x720`。改成竖屏裁切后，已做端到端样片验证：

```bash
npm run mini:lite -- --limit 1 --duration 2 --out-dir /private/tmp/macify-lite-portrait-test --cdn-base https://cdn.example.com/macify --overwrite
```

结果：成功从 Apple CDN 拉取 `Seals`，输出 2 秒竖屏 MP4：

```text
codec: h264
profile: Main
size: 606x1080
pix_fmt: yuv420p
fps: 30
duration: 2s
sizeBytes: 458662
```

## 2026-05-10 本轮低端安卓 MP4 落地记录

用户明确希望“不只是给方案和脚本”，而是直接把 Apple 原视频替换成低端安卓微信也更稳的竖屏 MP4，并尽量不花钱做存储。

本轮已直接执行：

- 改造 `scripts/miniprogram/prepare-lite-videos.mjs` 默认转码参数：
  - `9:16` 竖屏中心裁切
  - `720p` 高，实际约 `404x720`
  - `30fps`
  - H.264 `baseline`
  - `-tune fastdecode`
  - `yuv420p`
  - 前 `45s`
  - `maxrate 1200k` / `bufsize 2400k`
- 实际批量转码全部 114 条 Apple 1080/2K AVC 源，输出到：

```text
local-miniprogram-lite/
  videos/*.mp4
  manifest.json
  manifest.csv
  README.md
  wechat-settings.txt
```

转码结果：

```text
MP4 数量: 114
成功: 114
失败: 0
目录大小: 约 224MB
manifest 记录总字节: 190,750,118 bytes
单文件最大: 6,859,646 bytes
单文件最小: 73,434 bytes
```

抽样 `ffprobe` 结果：

```text
codec: h264
profile: Constrained Baseline
size: 404x720
pix_fmt: yuv420p
fps: 30
duration: 45s
```

小程序侧已改为默认轻量 MP4：

```js
videoSource: 'lite'
liteVideoBase: 'https://lh850718.github.io/Macify'
liteSourceVersion: 'mp4-720p-20260510'
```

并新增轻量源失败回退逻辑：

- `miniprogram/utils/videos.js` 在轻量 MP4 URL 旁保留 Apple 1080 fallback URL
- `miniprogram/pages/index/index.js` 在轻量 MP4 播放失败时，当前条自动回退 Apple 1080 源，避免黑屏
- 设置页文案从 `轻量 CDN` 调整为 `轻量 MP4`

免费存储尝试：

- 已准备 GitHub Pages 静态发布目录：

```text
/private/tmp/macify-pages-deploy-20260510-1
```

- 该目录是独立 Git 仓库，分支为 `gh-pages`
- 已提交：

```text
113347e Publish lite mini program videos
```

- 计划发布地址：

```text
https://lh850718.github.io/Macify
```

- 计划视频地址示例：

```text
https://lh850718.github.io/Macify/videos/83C65C90-270C-4490-9C69-F51FE03D7F06.mp4
```

但当前机器没有 GitHub CLI/HTTPS 凭据：

```text
gh not found
git push origin gh-pages -> fatal: could not read Username for 'https://github.com': Device not configured
```

因此视频已经全部生成并准备好发布，但还没有成功推到 GitHub Pages。当前抽样访问 GitHub Pages URL 返回 `404`。等 GitHub 凭据可用后，在 `/private/tmp/macify-pages-deploy-20260510-1` 执行推送即可发布；如果 GitHub Pages 未自动启用，需要在 GitHub 仓库 Settings -> Pages 选择 `gh-pages` / root。

免费存储判断：

- GitHub Pages：免费，官方限制是 Published site 不超过 `1GB`、软流量限制 `100GB/month`；本轮 224MB 以内，适合早期测试，但可能需要仓库 Pages 设置和 GitHub 登录。
- Cloudflare Pages：免费，但官方单个静态文件最大 `25MiB`；本轮单文件最大约 `6.9MB`，也满足限制。
- Cloudflare R2：免费额度 `10GB-month` 存储、免公网 egress；更适合长期正式托管，但需要 Cloudflare 账号/API token，超免费额度后会计费。

微信公众平台还需要把最终托管域名加入 `downloadFile` 合法域名。若用默认 GitHub Pages，则是：

```text
https://lh850718.github.io
```

## 当前验证结果

已执行：

```bash
node --check cloudflare-worker/worker.js
node --check miniprogram/pages/index/index.js
node --check miniprogram/pages/settings/settings.js
node --check miniprogram/utils/storage.js
node --check miniprogram/utils/videos.js
node --check miniprogram/utils/weather.js
```

结果：通过。

已验证配置 JSON：

```text
project.config.json
miniprogram/project.config.json
miniprogram/app.json
miniprogram/sitemap.json
miniprogram/pages/index/index.json
miniprogram/pages/settings/settings.json
```

## 2026-05-10 1080p COS/CDN 迁移进展

用户明确要求小程序真机视频源不要再用 GitHub Pages，也不要 720p MP4；正式方向改为中国大陆可访问的腾讯云 COS + 腾讯云 CDN + 自有备案 HTTPS 域名。

本地 1080p 产物已经完成：

```text
local-miniprogram-1080/
  videos/*.mp4
  manifest.json
  manifest.csv
  README.md
  wechat-settings.txt
```

当前校验结果：

```text
MP4 数量: 114
成功: 114
失败: 0
目录大小: 626MB
manifest 记录总字节: 599,227,664 bytes
manifest 总体积: 571.5 MiB
单文件最大: 28.4 MiB, Bumpheads, 687D03A2-18A5-4181-8E85-38F3A13409B9.mp4
单文件最小: 0.9 MiB, Hawaii, 258A6797-CC13-4C3A-AB35-4F25CA3BF474.mp4
编码: H.264 Main
尺寸: 606x1080
像素格式: yuv420p
帧率: 30fps
时长: 每条前 45 秒
```

抽样 `ffprobe`：

```text
codec: h264
profile: Main
size: 606x1080
pix_fmt: yuv420p
fps: 30
duration: 45s
```

COSCLI 已下载到：

```text
/private/tmp/coscli
```

本机没有发现现成的腾讯云 COSCLI 配置、腾讯云环境变量或可直接使用的桶信息：

```text
~/.cos.yaml 不存在
~/.cos.conf 不存在
~/.tccli 不存在
COS/TENCENT 相关环境变量未发现
```

已新增上传脚本：

```text
scripts/miniprogram/upload-cos-videos.mjs
npm run mini:cos
```

脚本用途：

- 从环境变量读取 `COS_SECRET_ID` / `COS_SECRET_KEY`
- 生成临时 COSCLI 配置，不把密钥写进仓库
- 上传 `local-miniprogram-1080/videos/` 到 COS 的 `macify/videos/`
- 给 MP4 设置 `Content-Type:video/mp4`
- 给 MP4 设置长缓存 `Cache-Control:public,max-age=2592000,immutable`
- 将 `manifest.json` / `manifest.csv` / `wechat-settings.txt` / `README.md` 上传到 `macify/`

待用户提供或在机器上配置：

```text
COS Bucket 全名，例如 macify-videos-1250000000
COS Region，例如 ap-shanghai 或 ap-guangzhou
CDN HTTPS 根域名，例如 https://video.yourdomain.com/macify
COS_SECRET_ID
COS_SECRET_KEY
如使用临时密钥，还需要 COS_SESSION_TOKEN
```

拿到参数后执行：

```bash
COS_SECRET_ID=xxx COS_SECRET_KEY=yyy npm run mini:cos -- \
  --bucket macify-videos-1250000000 \
  --region ap-shanghai \
  --cdn-base https://video.yourdomain.com/macify
```

上传完成后再修改小程序默认轻量源：

```text
miniprogram/utils/storage.js
DEFAULT_LITE_VIDEO_BASE = https://video.yourdomain.com/macify
LITE_SOURCE_VERSION = mp4-1080p-cos-20260510
```

微信公众平台 `downloadFile` 合法域名应填写 CDN 根域名，不包含路径：

```text
https://video.yourdomain.com
```

结果：通过。

已抽样验证默认 URL：

```text
https://sylvan.apple.com/Videos/..._2K_AVC.mov
```

确认默认不再使用 `/itunes-assets/...4k...`。

小程序包体积处理记录：

```text
2026-05-10 发现 WeChat DevTools Preview 包体积约 2075KB，超过 2MB preview 上限。
```

主要原因不再是视频数据，而是本地资源和数据：

- `miniprogram/assets/breath.mp3` 原约 1.48MB，裁掉开头静音后约 1.21MB
- `miniprogram/data/quotes.js` 原始排版较松，约 480KB
- `miniprogram/data/videos.js` 的 Apple 4K 备选源不适合小程序真机预览
- `miniprogram/data/apple-aerial-1080.js` 也有可压缩空白
- `.DS_Store` / `miniprogram/README.md` 不应进入小程序包

已处理：

- 压缩 `quotes.js`、`apple-aerial-1080.js` 为等价紧凑 CommonJS 数据，内容数量不变
- 移除小程序运行包里的 `miniprogram/data/videos.js` 和设置页 `Apple 4K 原片` 选项；历史本地设置 `original4k` 会自动迁回 `apple1080`
- 删除 `miniprogram/.DS_Store` 和 `miniprogram/data/.DS_Store`
- 在根 `project.config.json` 和 `miniprogram/project.config.json` 的 `packOptions.ignore` 中排除 `.DS_Store` 和 `miniprogram/README.md`

当前 `miniprogram` 文件实际总量扣除 `packOptions.ignore` 的 README 后为 1,799,346 bytes，明显低于 2MB preview 上限。最终以微信开发者工具重新 Preview 的包体积为准。

## 语录审查清理记录

`miniprogram/data/quotes.js` 已按微信小程序审核风险做整条删除，不做关键词替换。

清理前：

```text
quotes.js: 4306 条
```

第一轮清理规则：

- 作者包含高风险政治人物 / 意识形态人物：
  - `毛泽东`
  - `马克思`
  - `列宁`
  - `恩格斯`
  - `特朗普`
  - `希特勒`
  - `曼德拉`
  - `甘地`
  - `丘吉尔`
  - `林肯`
  - `切·格瓦拉`
- 正文包含下列审查高风险词或组合时整条删除：
  - `谁主沉浮`
  - `革命不是请客吃饭`
  - `政治是不流血的战争`
  - `自由`
  - `革命`
  - `政治`
  - `权力`
  - `统治`
  - `国家`
  - `人民`
  - `言论`
  - `审查`
  - `战争`
  - `斗争`
  - `民主`
  - `共产`
  - `社会主义`
  - `资本主义`
  - `改变世界`
  - `自由意志`
  - `觉醒`
  - `压迫`
  - `反抗`
  - `推翻`
  - `独裁`
  - `真理`
  - `信仰`

第一轮结果：

```text
删除 369 条
剩余 3937 条
```

第二轮按用户要求继续清理：

```text
作者或正文包含 `佛陀` 的条目：删除 15 条
```

当前最终结果：

```text
quotes.js: 3922 条
deletequote.js: 384 条
```

被删除的所有文本已保存到仓库根目录：

```text
deletequote.js
```

注意：`deletequote.js` 故意放在仓库根目录，不放进 `miniprogram/data/`，避免被删敏感文本继续进入微信小程序运行包。每条删除记录保留：

```text
content
author
matchedAuthorTerms
matchedContentTerms
```

主要聚合删除数：

```text
毛泽东相关：165
马克思相关：25
丘吉尔相关：23
甘地相关：22
林肯相关：21
曼德拉相关：14
特朗普相关：2
佛陀相关：15
```

已验证：

```bash
node --check miniprogram/data/quotes.js
node --check deletequote.js
```

## 当前未提交改动

本地 commit `2b633cd` 之后，又新增/修改：

```text
cloudflare-worker/worker.js
.gitignore
macifytowechatmini.md
deletequote.js
package.json
project.config.json
miniprogram/README.md
miniprogram/project.config.json
miniprogram/assets/breath.mp3
miniprogram/assets/zazen-line.svg
miniprogram/pages/index/index.js
miniprogram/pages/index/index.wxml
miniprogram/pages/index/index.wxss
miniprogram/pages/settings/settings.js
miniprogram/pages/settings/settings.wxml
miniprogram/pages/settings/settings.wxss
miniprogram/utils/storage.js
miniprogram/utils/videos.js
scripts/miniprogram/prepare-lite-videos.mjs
miniprogram/data/quotes.js
miniprogram/data/videos.js（删除）
miniprogram/data/apple-aerial-1080.js
miniprogram/data/video-intros.js
```

建议真机测试通过后再提交一个新 commit，例如：

```bash
git add cloudflare-worker/worker.js project.config.json macifytowechatmini.md miniprogram
git commit -m "Switch mini program to Apple 1080 H264 videos"
```

如果测试失败，需要回退到本地 commit：

```bash
git checkout -- cloudflare-worker/worker.js project.config.json miniprogram/README.md miniprogram/project.config.json miniprogram/data/quotes.js miniprogram/data/videos.js miniprogram/pages/settings/settings.js miniprogram/pages/settings/settings.wxml miniprogram/pages/settings/settings.wxss miniprogram/utils/storage.js miniprogram/utils/videos.js
rm miniprogram/data/apple-aerial-1080.js
```

不要轻易 `git reset --hard`，避免丢失用户其它本地改动。

## 下一步建议

1. 在 WeChat DevTools 里重新编译。
2. 进入设置页确认视频源是 `内置 1080P视频`。
3. 真机 Preview，用蜂窝网络测试：
   - 能否稳定播放超过 30 秒
   - 切换视频是否正常
   - 不同分类是否有视频
   - 点击天气是否弹出详情
   - 点击语录是否换一条
   - 左下角冥想入口和退出是否正常
4. 如果仍然 3 秒断：
   - 先不要回到 4K
   - 试 `/Videos/*` Cloudflare 反向代理
   - 若代理仍断，再筛选更小 1080 子集或做 HLS/轻量转码
5. 真机测试通过后提交：

```bash
git add cloudflare-worker/worker.js project.config.json macifytowechatmini.md miniprogram
git commit -m "Switch mini program to Apple 1080 H264 videos"
```

## 重要结论

当前最优路线不是“直接播放 Apple 新版 4K 原片”，而是：

```text
Apple 官方旧 Aerial feed -> url-1080-H264 -> 微信小程序 video
```

这样仍然使用 Apple 视频，但避开了新 macOS manifest 中 4K/240fps/HEVC/MOV 巨型文件对小程序的压力。

## 2026-05-10 14:19 腾讯云 COS / CDN / 备案 / 上传密钥进展

本节是给下一个聊天窗口的接力说明。用户当前目标仍然是：把本地已经转好的 1080p MP4 上传到中国大陆可访问的视频存储上，让微信小程序真机不用 GitHub Pages，也不用 720p。

### 已完成的本地视频产物

本地 1080p 视频已经全部生成，位置：

```text
/Users/hui/Projects/Macify/local-miniprogram-1080/
```

内容：

```text
videos/*.mp4
manifest.json
manifest.csv
README.md
wechat-settings.txt
```

关键校验：

```text
MP4 数量: 114
成功: 114
失败: 0
manifest 总体积: 571.5 MiB
目录显示大小: 626MB
编码: H.264 Main
尺寸: 606x1080
像素格式: yuv420p
帧率: 30fps
每条: 前 45 秒
```

### 已创建的腾讯云 COS 存储桶

用户已经创建 COS Bucket：

```text
Bucket: macify-videos-1430886267
Region: ap-beijing
地域: 北京
访问权限: 私有读写
COS 默认请求域名: macify-videos-1430886267.cos.ap-beijing.myqcloud.com
```

用户创建 Bucket 时曾看到“请求域名高风险”，已解释：这是 COS 原始域名风险提示。正式路线应该是 COS 存文件，CDN + 自有备案 HTTPS 域名给小程序访问。

当前临时测试路线：

```text
先把视频上传到 COS 的 macify/videos/
先用 COS 默认域名测试小程序视频播放
等备案通过后，再改为 CDN 域名 video.huxizen.com
```

临时测试的 liteVideoBase 应为：

```text
https://macify-videos-1430886267.cos.ap-beijing.myqcloud.com/macify
```

示例视频 URL：

```text
https://macify-videos-1430886267.cos.ap-beijing.myqcloud.com/macify/videos/83C65C90-270C-4490-9C69-F51FE03D7F06.mp4
```

### 已开通 CDN 服务，但还没接入域名

用户已在腾讯云 CDN 页面开通 CDN 服务，选择的是：

```text
CDN 服务
静态内容 / 网站加速
按流量后付费模式
```

CDN 的意义已向用户解释为：COS 是仓库，CDN 是全国快递站。视频放在 COS，北京等地用户可以从更近的 CDN 节点取视频，小程序播放更稳。

CDN 域名接入还没完成，原因是域名未备案。

### 用户要备案的域名

用户明确要备案：

```text
huxizen.com
```

后续计划用作视频 CDN 的子域名：

```text
video.huxizen.com
```

注意：用户之前在 CDN 输入过 `video.huizeng.com`，后来纠正为真正要备案和使用的是：

```text
huxizen.com
video.huxizen.com
```

### 备案进展

用户进入腾讯云 ICP 备案流程，选择了：

```text
应用服务类型: 网站/域名
域名: huxizen.com
备案主体: 个人
证件类型: 居民身份证
备案区域: 北京
```

此前备案系统要求选择云资源。用户账号一开始没有可用云资源，曾引导用户购买最低成本备案资源：

```text
轻量应用服务器
地域: 北京
配置: 入门型 2核 CPU / 2GB 内存 / 40GB SSD / 100GB 月流量包
价格: 35 元/月
备案最低要求: 3 个月及以上
页面应付: 105 元
搭配购买: 全部不勾
自动续费: 建议取消
```

2026-05-13 用户反馈最新状态：备案已提交腾讯云初审，不再卡在云资源选择或实名认证等待。

```text
备案订单号: 30177839176900401
订单类型: 新增服务（原备案不在腾讯云）
创建时间: 2026-05-10 13:42:49
当前阶段: 腾讯云审核中
流程状态:
1 提交初审: 已提交
2 腾讯云审核: 审核中
3 待提交管局: 预计 24 小时
4 工信部短信核验: 24 小时内核验
5 管局审核: 1-20 个工作日
```

审核说明：腾讯云将在 1-2 个工作日内给李慧（手机号 `136****7633`、`135****2101`）致电。第一次未接通 1 小时内会再次拨打，两次均未接通会导致驳回。用户需要把审核电话加入通讯录或临时关闭骚扰拦截。

下一步：等待腾讯云审核电话和初审结论；初审通过后立刻完成工信部短信核验；之后等待管局审核。备案通过前 CDN 域名 `video.huxizen.com` 不能作为正式小程序视频域名。

### 已创建 CAM 子用户和上传密钥

用户已在腾讯云 CAM 创建子用户：

```text
用户名: macify-cos-uploader
账号 ID: 100048757794
主账号 ID: 100048756855
备注: Macify COS video uploader
访问方式: 编程访问
控制台登录: 未启用
```

用户已经生成了 SecretId / SecretKey，并在聊天里发过。不要把密钥写进本文档，不要提交到 Git。下一窗口如果需要上传，应让用户重新提供或从当前聊天可见内容取用，但上传完成后要提醒用户删除/禁用该子用户或密钥。

用户已在该子用户上完成权限设置，当前截图显示已关联：

```text
QcloudCOSDataFullControl
```

该权限含义：

```text
对象存储 COS 数据读、写、删除、列出的访问权限
```

这是为了让 COSCLI 上传、覆盖、列出文件。上传完成后建议删除该子用户或解除权限。

### 上传脚本状态

已新增并修改脚本：

```text
scripts/miniprogram/upload-cos-videos.mjs
```

`package.json` 已新增：

```text
npm run mini:cos
```

脚本能力：

- 从环境变量读取 `COS_SECRET_ID` / `COS_SECRET_KEY`
- 生成临时 COSCLI 配置：`/private/tmp/macify-cos.yaml`
- 上传 `local-miniprogram-1080/videos/` 到 `cos://macify-video/macify/videos/`
- 上传 manifest / README / wechat-settings 到 `macify/`
- 支持 `--public-read`，用于这次 COS 默认域名临时直连测试
- 上传视频时设置：

```text
Content-Type: video/mp4
Cache-Control: public,max-age=2592000,immutable
ACL: public-read（仅临时测试用）
```

- 脚本会在结束时删除临时 COSCLI 配置文件，避免密钥残留在 `/private/tmp/macify-cos.yaml`

已验证：

```bash
node --check scripts/miniprogram/upload-cos-videos.mjs
npm run mini:cos -- --bucket macify-videos-1430886267 --region ap-beijing --cdn-base https://macify-videos-1430886267.cos.ap-beijing.myqcloud.com/macify --public-read --dry-run
```

dry-run 输出确认：

```text
Videos: 114/114, 571.5 MiB, failed 0
COS bucket: macify-videos-1430886267 (ap-beijing)
COS prefix: macify
CDN base: https://macify-videos-1430886267.cos.ap-beijing.myqcloud.com/macify
Object ACL: public-read
Sample URL: https://macify-videos-1430886267.cos.ap-beijing.myqcloud.com/macify/videos/83C65C90-270C-4490-9C69-F51FE03D7F06.mp4
```

### 已尝试上传但失败过一次

曾尝试执行真实上传：

```bash
COS_SECRET_ID=... COS_SECRET_KEY=... npm run mini:cos -- \
  --bucket macify-videos-1430886267 \
  --region ap-beijing \
  --cdn-base https://macify-videos-1430886267.cos.ap-beijing.myqcloud.com/macify \
  --public-read
```

第一次普通权限运行因本地沙箱写 `manifest.json` 被拦截：

```text
EPERM: operation not permitted, open 'local-miniprogram-1080/manifest.json'
```

随后已用 escalated 权限重跑，脚本开始上传，但 COS 返回：

```text
HEAD https://macify-videos-1430886267.cos.ap-beijing.myqcloud.com/: 403
```

当时判断原因：子用户权限还不够或权限尚未完成关联。用户随后已完成权限关联，截图显示 `QcloudCOSDataFullControl` 已关联。

### 下一窗口第一件事

不要重新解释全部背景。下一窗口应该直接继续：

1. 确认用户已经完成 `QcloudCOSDataFullControl` 权限关联。
2. 重新执行真实上传命令。
3. 上传完成后，用 curl/浏览器抽样验证一个 MP4 URL 是否 200、是否 `Content-Type: video/mp4`。
4. 如果可以访问，再把小程序默认轻量源临时改为 COS 默认域名。

上传命令模板，注意不要把真实 Secret 写入文件或文档：

```bash
COS_SECRET_ID='用户提供的 SecretId' COS_SECRET_KEY='用户提供的 SecretKey' npm run mini:cos -- \
  --bucket macify-videos-1430886267 \
  --region ap-beijing \
  --cdn-base https://macify-videos-1430886267.cos.ap-beijing.myqcloud.com/macify \
  --public-read
```

上传成功后验证：

```bash
curl -I https://macify-videos-1430886267.cos.ap-beijing.myqcloud.com/macify/videos/83C65C90-270C-4490-9C69-F51FE03D7F06.mp4
```

期望看到：

```text
HTTP/2 200
content-type: video/mp4
```

随后临时修改：

```text
miniprogram/utils/storage.js
DEFAULT_LITE_VIDEO_BASE = 'https://macify-videos-1430886267.cos.ap-beijing.myqcloud.com/macify'
LITE_SOURCE_VERSION = 'mp4-1080p-cos-20260510'
```

再做：

```bash
node --check miniprogram/utils/storage.js
node --check miniprogram/utils/videos.js
```

微信小程序后台临时 `downloadFile` 合法域名需要填：

```text
https://macify-videos-1430886267.cos.ap-beijing.myqcloud.com
```

正式备案/CDN 完成后，再切换为：

```text
https://video.huxizen.com/macify
```

微信小程序后台正式 `downloadFile` 合法域名应填：

```text
https://video.huxizen.com
```

### 安全提醒

用户已经在聊天中发过 SecretId / SecretKey。上传完成后必须提醒用户在腾讯云 CAM 中执行至少一项：

```text
禁用 macify-cos-uploader
删除 macify-cos-uploader
或删除该用户的 API 密钥
```

不要把 SecretId / SecretKey 写入 `macifytowechatmini.md`、README、脚本、环境文件或 Git。

## 2026-05-10 15:14 COS 上传完成 / 小程序临时切到 COS

本节是本轮续接结果。

### COS 上传结果

已用 `macify-cos-uploader` 临时密钥完成真实上传，密钥没有写入仓库或本文档。

第一次上传成功但发现路径多了一层：

```text
macify/videos/videos/<video-id>.mp4
```

原因是 COSCLI `sync` 会保留本地源目录名，脚本原先把本地 `videos/` 同步到远端 `macify/videos/`，于是生成了 `macify/videos/videos/`。

已修正：

```text
scripts/miniprogram/upload-cos-videos.mjs
```

现在视频同步目标是：

```text
cos://macify-video/macify/
```

这样本地 `local-miniprogram-1080/videos/` 会落到远端：

```text
macify/videos/<video-id>.mp4
```

第二次上传完成：

```text
视频: 114/114
辅助文件: manifest.json / manifest.csv / wechat-settings.txt / README.md / deployment.json
最终 COS 对象数: 119
最终 COS 大小: 571.58 MB
```

第一次误传的重复前缀已删除：

```text
macify/videos/videos/
删除对象数: 114
```

临时 COSCLI 配置文件已确认删除：

```text
/private/tmp/macify-cos.yaml
/private/tmp/macify-cos-debug.yaml
/private/tmp/macify-cos-cleanup.yaml
```

### 公开访问验证

已验证示例视频：

```bash
curl -I https://macify-videos-1430886267.cos.ap-beijing.myqcloud.com/macify/videos/83C65C90-270C-4490-9C69-F51FE03D7F06.mp4
```

结果：

```text
HTTP/1.1 200 OK
Content-Type: video/mp4
Cache-Control: public,max-age=2592000,immutable
```

也抽样验证：

```text
https://macify-videos-1430886267.cos.ap-beijing.myqcloud.com/macify/videos/4109D42A-D717-46A7-A9A2-FE53A82B25C0.mp4
HTTP/1.1 200 OK
Content-Type: video/mp4
```

`manifest.json` 已验证：

```text
HTTP/1.1 200 OK
Content-Type: application/json
```

### 小程序默认源已临时切换

已修改：

```text
miniprogram/utils/storage.js
```

当前默认值：

```text
DEFAULT_LITE_VIDEO_BASE = 'https://macify-videos-1430886267.cos.ap-beijing.myqcloud.com/macify'
LITE_SOURCE_VERSION = 'mp4-1080p-cos-20260510'
```

已执行：

```bash
node --check miniprogram/utils/storage.js
node --check miniprogram/utils/videos.js
```

均通过。

### 当前下一步

微信小程序后台临时 `downloadFile` 合法域名需要填：

```text
https://macify-videos-1430886267.cos.ap-beijing.myqcloud.com
```

之后真机测试小程序视频播放。如果 COS 默认域名测试通过，等备案完成后再把 CDN 域名接入并切换为：

```text
https://video.huxizen.com/macify
```

CDN 域名申请下来后不需要重新上传视频。视频已经在 COS 的：

```text
macify/videos/<video-id>.mp4
```

只需要让 CDN 回源到当前 COS Bucket，并把小程序默认轻量源从 COS 默认域名替换为：

```text
DEFAULT_LITE_VIDEO_BASE = 'https://video.huxizen.com/macify'
```

同时把版本号改成新的值，例如：

```text
LITE_SOURCE_VERSION = 'mp4-1080p-cdn-202605xx'
```

版本号必须变化，这样已预览/安装过的小程序会刷新旧设置，不会继续沿用 COS 默认域名。

微信小程序后台正式 `downloadFile` 合法域名需要填：

```text
https://video.huxizen.com
```

安全提醒：上传已完成，建议立刻在腾讯云 CAM 中禁用或删除 `macify-cos-uploader`，或者至少删除该用户的 API 密钥。

## 2026-05-10 15:55 公共领域素材通道首条验证（已废弃）

废弃说明：本节仅保留历史记录。2026-05-10 后用户明确要求完全抛弃 `npsPublicDomain` / NPS 公共领域路线；相关清单、抓取脚本、本地小样目录和 `publicDomain` 转码入口已删除。后续不要按本节继续执行。

本节记录替换 Apple Aerial 源的首个独立公共领域素材通道，不覆盖现有 COS 上的：

```text
macify/videos/<video-id>.mp4
```

### 新增/修改文件

新增：

```text
scripts/miniprogram/fetch-public-domain-videos.mjs
miniprogram/data/public-domain-videos.js
```

修改：

```text
scripts/miniprogram/prepare-lite-videos.mjs
.gitignore
```

`prepare-lite-videos.mjs` 新增 source：

```text
publicDomain -> miniprogram/data/public-domain-videos.js
```

并且转码报告 rows / CSV 会保留：

```text
sourceName
sourcePage
license
attribution
licenseNotes
```

这样后续每个转码输出都能追溯授权来源。

`.gitignore` 已加入：

```text
local-miniprogram-public-domain/
```

### 首条素材

当前清单只有一个已人工核验的 NPS 素材：

```text
id: nps-yosemite-stock-footage-2021
name: Yosemite Stock Footage (2021)
sourceName: National Park Service
sourcePage: https://www.nps.gov/media/video/view.htm?id=A45A7B7C-295C-4718-B5FA-FE30882C291F
license: Public domain
attribution: National Park Service / Yosemite National Park
direct mp4: https://www.nps.gov/nps-audiovideo/audiovideo/787c8143-9811-4037-ac56-8c873be9b7981080p.mp4
```

NPS 页面描述写明：

```text
All footage is in the public domain and may be used for any purpose.
```

并且 NPS Usage Info 说明 credited to NPS 且没有 copyright symbol 的多媒体可视为 public domain。仍然建议保留 attribution，不要暗示 NPS 为产品背书。

### 脚本能力

生成/维护清单：

```bash
node scripts/miniprogram/fetch-public-domain-videos.mjs
```

默认只写入保守的 NPS seed。也预留了 NASA Images API 通道：

```bash
node scripts/miniprogram/fetch-public-domain-videos.mjs --source nasa --nasa-query "earth clouds from space" --nasa-limit 8
node scripts/miniprogram/fetch-public-domain-videos.mjs --source all --nasa-limit 8
```

NASA 通道做了保守过滤：优先 earth / clouds / aurora / timelapse / orbit 等关键词，排除 rocket / launch / astronaut / people / logo / briefing / Dr / scientist / researcher / b-roll / campaign / airborne / aircraft 等机构感、人物感或肖像风险较高的素材。NASA 素材仍需人工复核，避免使用 logo、人物肖像、机构背书语境。

### 本地转码验证

已执行真实转码：

```bash
node scripts/miniprogram/prepare-lite-videos.mjs --source publicDomain --out-dir local-miniprogram-public-domain --height 1080 --duration 45 --profile main --crf 26 --maxrate 2500k --bufsize 5000k --cdn-base https://macify-videos-1430886267.cos.ap-beijing.myqcloud.com/macify-public
```

输出：

```text
local-miniprogram-public-domain/videos/nps-yosemite-stock-footage-2021.mp4
local-miniprogram-public-domain/manifest.json
local-miniprogram-public-domain/manifest.csv
local-miniprogram-public-domain/README.md
local-miniprogram-public-domain/wechat-settings.txt
```

验证结果：

```text
源 MP4: HTTP 200, Content-Type: video/mp4, Content-Length: 543884806
输出 MP4: H.264 Main, yuv420p, 606x1080, 30fps, 45s, 2684590 bytes
转码结果: 1 converted, 0 failed
```

已执行：

```bash
node --check scripts/miniprogram/fetch-public-domain-videos.mjs
node --check scripts/miniprogram/prepare-lite-videos.mjs
node --check miniprogram/data/public-domain-videos.js
```

均通过。

### 下一步

如果要把这条公共领域小样上传 COS，使用新前缀，不覆盖 Apple 源：

```text
COS prefix: macify-public
期望路径: macify-public/videos/nps-yosemite-stock-footage-2021.mp4
临时 base: https://macify-videos-1430886267.cos.ap-beijing.myqcloud.com/macify-public
```

真实上传需要重新向用户索取：

```text
COS_SECRET_ID
COS_SECRET_KEY
```

不要从历史聊天、文档或文件中寻找/恢复密钥。

## 2026-05-10：小程序新增 NPS 视频库选项（已废弃）

废弃说明：本节仅保留历史记录。后续用户明确要求完全抛弃 `npsPublicDomain` / NPS 公共领域路线；相关清单、抓取脚本、本地小样目录和 `publicDomain` 转码入口已删除。不要按本节继续执行。

本轮不是替换 Apple 源，而是在小程序里新增独立的公共领域素材库选择。

已接入：

- `miniprogram/utils/storage.js`
  - 新增 `videoLibrary: 'apple' | 'npsPublicDomain'`
  - 保留 Apple 默认轻量 base：`https://macify-videos-1430886267.cos.ap-beijing.myqcloud.com/macify`
  - 新增 NPS 默认轻量 base：`https://macify-videos-1430886267.cos.ap-beijing.myqcloud.com/macify-public`
  - 新增 NPS 源版本字段 `npsPublicDomainSourceVersion`
- `miniprogram/utils/videos.js`
  - 同时加载 `apple-aerial-1080.js` 与 `public-domain-videos.js`
  - `videoSource === 'lite'` 时按 `videoLibrary` 切换清单与 COS base
  - Apple 轻量源仍走 `macify/videos/<apple-video-id>.mp4`
  - NPS 公共领域源走 `macify-public/videos/<nps-video-id>.mp4`
  - Apple 官方 1080 逻辑保留；直接 URL 入口后续已删除
- `miniprogram/pages/settings/*`
  - 在轻量 MP4 模式下新增“素材源”选择：`Apple 轻量航拍` / `NPS 公共领域`
  - Apple 与 NPS 使用各自的根域名输入字段
  - 选择 NPS 会保持 `videoSource: 'lite'`，并重置播放范围为全部，避免沿用 Apple-only 分类
- `miniprogram/pages/index/index.js`
  - NPS 轻量源加载失败时，提示“正在尝试源站回退”，不再误写成 Apple 回退

已验证：

```bash
node --check miniprogram/utils/storage.js
node --check miniprogram/utils/videos.js
node --check miniprogram/pages/settings/settings.js
node --check miniprogram/pages/index/index.js
node --check miniprogram/data/public-domain-videos.js
```

本地 CommonJS 沙盒验证：

```text
Apple 轻量 URL 前缀: .../macify/videos/
NPS 轻量 URL 前缀: .../macify-public/videos/
NPS 分类选项: all, Landscapes, Underwater
```

仍未完成：

- NPS 99 条尚未批量转码完成
- NPS 尚未上传 COS
- 上传前仍需重新向用户索取 `COS_SECRET_ID` / `COS_SECRET_KEY`
- 上传后建议禁用/删除 `macify-cos-uploader` 或删除该 API 密钥

### 2026-05-10 质量判断更新

用户查看已转码 NPS 小样后认为画质和气质太差，不适合 Macify 小程序；目标视觉需要更接近 Apple Aerial 的高端、安静、航拍屏保感。

因此后续不要继续批量转码当前 99 条 NPS 清单，也不要上传到 COS。当前 `public-domain-videos.js` 应视为原始候选池，而不是可发布的视频库。

下一步方向应调整为：

- 保留 Apple 轻量源作为默认和稳定主源
- 该中间方向已被后续 `premiumFreeAerial` / 高端免费航拍路线取代
- 优先筛选：
  - 航拍、飞越、峡谷/海岸/云层/日出日落/延时
  - 无人物、无讲解、无教育/机构宣传、无游客、无车船
  - 运动稳定、构图干净、没有字幕/标题卡、色彩和曝光接近屏保
- 先做 5-10 条高质量小样，用更高码率参数验证，例如 `--crf 20-22 --maxrate 8000k --bufsize 16000k`
- 不再使用 `macify-public/`；后续 Premium Free Aerial 只走 `macify-premium/`，仍然不能覆盖 Apple 的 `macify/videos/`

## 2026-05-10：高端免费航拍源整体计划

用户确认：不要把 NPS 作为唯一非 Apple 方向。Mixkit、Pexels、Pixabay、Dareful、Coverr 等免费航拍网页的视觉质量明显更接近 Macify 需要的高端 Apple Aerial 气质，可以全部纳入候选来源。

核心目标：

- Apple 轻量源继续作为默认主源，不删除、不覆盖、不替换。
- 新增非 Apple 视频库应从 `NPS 公共领域` 升级为更准确的 `高端免费航拍` / `Premium Free Aerial`。
- 各来源一期目标先抓取或人工整理 100 条候选：
  - Mixkit: 100
  - Pexels: 100
  - Pixabay: 100
  - Dareful: 100，若站内第一期高质量航拍不足 100 条则先取全部合格条目，后续可继续补
  - Coverr: 100，优先真实拍摄，避开 AI / iStock / 付费入口
- 不按数量盲目发布。500 条是一阶段目标，不是永久上限；后续可以继续扩充。
- 第一次执行时可以分批完成：先做 20-30 条顶级小样，确认审美、码率、裁切和小程序播放体验，再逐步完成每源一期 100 条候选。

### 免费源优先级

1. Mixkit
   - 入口：
     - `https://mixkit.co/free-stock-video/aerial/`
     - `https://mixkit.co/free-stock-video/drone/`
     - `https://mixkit.co/free-stock-video/scenery/`
   - 质量判断：当前最适合优先筛选，素材更像广告片、网站背景、屏保背景。
   - 授权要点：Mixkit 页面说明 Free License 可用于商业项目、无水印、无需署名；但 Mixkit 有 Free License 和 Restricted License 两种，必须逐条确认只用 Free License。

2. Pexels
   - 入口：
     - `https://www.pexels.com/search/videos/aerial%20shot/`
     - 示例：`https://www.pexels.com/video/4k-aerial-view-of-mountain-landscape-with-clouds-37404855/`
     - 示例：`https://www.pexels.com/video/aerial-view-of-the-ocean-and-mountains-19950957/`
   - 质量判断：量大，很多 4K 航拍、海岸、山脉、云层素材非常接近 Apple Aerial。
   - 授权要点：Pexels License 允许免费使用、修改、无需署名；但不允许把未改动素材作为 stock/wallpaper 平台素材再分发。Macify 不是素材下载站，但视频是核心体验，需保留来源和授权记录，避免提供原片下载。
   - API：`https://www.pexels.com/api/documentation/`，可搜索视频；需要 API key。

3. Pixabay
   - 入口：
     - `https://pixabay.com/videos/search/aerial/`
     - `https://pixabay.com/videos/search/aerial%20ocean/`
     - `https://pixabay.com/videos/search/aerial%20mountains/`
   - 质量判断：数量最大，适合用 API 初筛，再人工挑高端片段。
   - 授权要点：Pixabay Content License 允许免费使用、无需署名、可修改；禁止 standalone 方式分发素材。不要做原视频下载入口。
   - API：`https://pixabay.com/api/docs/`，可用 `editors_choice=true`、`min_width=3840`、`safesearch=true`、`order=popular` 初筛。API 文档建议不要永久热链，使用时应下载到自有服务/COS。

4. Dareful
   - 入口：
     - `https://dareful.com/videos/aerial/`
     - `https://dareful.com/videos/flying/`
   - 质量判断：数量比 Pexels/Pixabay 少，但作者和风格更稳定，适合补高质量自然航拍。
   - 授权要点：Creative Commons Attribution 4.0，可商用、可修改，但必须署名 Dareful/作者。小程序需要有“素材来源/致谢”页或设置页入口记录 attribution。

5. Coverr
   - 入口：
     - `https://coverr.co/stock-video-footage/aerial`
     - `https://coverr.co/stock-video-footage/drone`
   - 质量判断：有不少 cinema-quality 航拍，但当前页面混有 AI、iStock、付费入口，需要更严格人工过滤。
   - 授权要点：Coverr License 允许商业使用，但免费下载的署名要求页面文字存在差异；在确认前按“需要署名”处理，并避开 AI 生成、可识别商标/地标/人物/私有物业风险素材。

暂不主推但可作为后备：

- Videvo / Videezy / Vidsplay 等平台授权逐条差异更大，常见 attribution、editorial-only 或 premium 混排，适合作为后备，不适合作为第一批高端库主来源。
- NPS 当前 99 条不再作为候选池，不继续批量转码，不上传 COS。

### 审美筛选标准

目标不是“免费风景视频”，而是“Macify 屏保级背景”：

- 必须：
  - 高端航拍、飞越、云层、海岸、山脉、峡谷、湖泊、森林、日出日落、延时
  - 构图干净，画面慢、稳、安静，能长时间作为首页背景
  - 原始分辨率优先 4K，其次高质量 1080p
  - 无水印、无字幕、无标题卡、无 logo、无明显品牌
  - 无可识别人脸、游客、采访、讲解、车流主体、船只主体、商业建筑主体
- 谨慎：
  - 城市航拍、道路、车辆、桥梁、地标建筑，除非非常接近 Apple Aerial 的高级城市屏保感
  - AI 生成素材，除非用户明确接受，并且视觉完全稳定无瑕疵
  - 太短、镜头晃动、过曝、过饱和、锐化过强、明显 stock 味的片段
- 直接排除：
  - 人物主体、商业品牌、字幕包装、教程/宣传/教育片、明显旅游 vlog、无人机炫技快速运动、激烈运动、广告植入、军事/政治/宗教场景

### 分类和视频说明策略

分类不要新增太多，优先沿用当前 Apple 视频库的分类体系，保持设置页和首页体验干净：

```text
Landscapes   自然景观
Cities       城市景观
AnimalsAndPlants 动植物
Motion       运转
Underwater   水下景观
```

`all` 只是设置页的“全部”选项，不写进单条视频的 `category` 字段。

非 Apple 高端航拍的分类映射：

- 海岸、山脉、森林、峡谷、湖泊、沙漠、云层、日出日落、自然延时：统一归入 `Landscapes`
- 鸟类、野生动物、海洋动物、植物、花卉和动植物近景：归入 `AnimalsAndPlants`
- 真正水下镜头：归入 `Underwater`
- 城市航拍、夜景、建筑群、道路网：只有非常高级、干净、接近 Apple 城市屏保时才归入 `Cities`
- 火苗、篝火、壁炉、烟火等燃烧/化学现象，以及齿轮、唱片机、风机、收割机械等机械运动：归入 `Motion`
- 不使用 `Mac` / `其他` 作为 Premium Free Aerial 分类；原本想归到 `Mac` 的视频必须归入上面这些主分类之一，否则不适合当前库

不要新增 `Ocean`、`Mountains`、`Forest`、`Desert` 等主分类；这些细节放到 `tags`、`subcategories`、`locationName` 和 `description`。这样用户看到的分类仍然简洁，而每条视频仍有足够说明信息。

每新增一条视频，都要同步补齐用户可见说明：

- `displayName`：小程序里显示的短标题，可以比素材站原名更优雅
- `locationName`：地点或场景；不知道精确地点时写更宽泛的场景，如 `Mountain coastline` / `Lake landscape`
- `locationCountry`：能确认再写，不能确认留空
- `timeOfDay`：`Sunrise` / `Day` / `Sunset` / `Night` / `Timelapse` 等
- `description`：点击视频名时展示的 1-2 句中文说明，语气接近 Apple 视频介绍，不写授权和技术信息；如果有明确地点、城市或地标，尽量带一点轻量人文介绍
- `tags` / `subcategories`：用于内部筛选和后续搜索，不直接膨胀设置页分类

### 数据与代码改造计划

建议新增独立清单，而不是继续沿用 `public-domain-videos.js`：

```text
miniprogram/data/premium-free-aerial-videos.js
```

每条记录建议字段：

```js
{
  id: 'mixkit-lake-sunset-aerial-001',
  name: 'Landscape of a large lake during sunset from the air',
  displayName: '落日湖湾',
  locationName: 'Lake landscape',
  locationCountry: '',
  sourceName: 'Mixkit',
  sourcePage: 'https://...',
  sourceDownloadPage: 'https://...',
  url: 'https://...',              // 原始下载或直链，仅用于转码脚本
  category: 'Landscapes',
  subcategories: ['Lake', 'Sunset', 'Aerial'],
  tags: ['aerial', 'lake', 'sunset'],
  timeOfDay: 'Sunset',
  description: '航拍镜头低低掠过湖面，落日把水面染成金色，远处山脉慢慢沉入剪影。',
  sourceResolution: '4K',
  duration: '00:35',
  license: 'Mixkit Free License',
  attribution: '',
  licenseNotes: 'Free commercial use, no attribution required; verified as Free License.',
  qualityTier: 'candidate'         // candidate | sample-approved | rejected | published
}
```

设置字段：

```text
videoLibrary: 'apple' | 'premiumFreeAerial'
```

不再保留 `npsPublicDomain` 作为可选视频库；COS 前缀继续使用独立路径，避免覆盖 Apple：

```text
macify-premium/videos/<source>-<video-id>.mp4
https://macify-videos-1430886267.cos.ap-beijing.myqcloud.com/macify-premium
```

不要使用：

```text
macify/videos/
```

### 执行阶段

Phase 1：候选清单，不下载原片

- 先为 Mixkit / Pexels / Pixabay / Dareful / Coverr 建候选抓取或人工录入脚本。
- 每源一期目标 100 条候选，保留 sourcePage、license、attribution、preview/thumb、sourceResolution、duration；100 不是永久上限，后续可以继续增加。
- Pexels/Pixabay 可以优先走 API；Mixkit/Dareful/Coverr 先人工精选或半自动抓页面。
- 输出候选清单和人工验片表，不进入转码。

Phase 2：人工验片

- 从 500 条候选里先挑 20-30 条最像 Apple Aerial 的片段。
- 标记 `qualityTier: 'sample-approved'`。
- 记录拒绝原因，例如 `people`、`too stocky`、`shaky`、`vehicle subject`、`license unclear`。

Phase 3：高质量小样转码

- 只转 5-10 条样片，先不用上传 COS。
- 建议参数：

```bash
node scripts/miniprogram/prepare-lite-videos.mjs \
  --source premiumFreeAerial \
  --out-dir local-miniprogram-premium-aerial \
  --height 1080 \
  --duration 45 \
  --profile main \
  --crf 20 \
  --maxrate 8000k \
  --bufsize 16000k \
  --cdn-base https://macify-videos-1430886267.cos.ap-beijing.myqcloud.com/macify-premium
```

- 如果文件体积过大，再试 `--crf 22 --maxrate 6000k --bufsize 12000k`。
- 先用本地 ffprobe 和真机预览确认画质、体积、播放稳定性。

Phase 4：小程序接入

- 保留 Apple 默认：

```text
Apple base: https://macify-videos-1430886267.cos.ap-beijing.myqcloud.com/macify
Apple path: macify/videos/<apple-video-id>.mp4
```

- 新增高端免费航拍：

```text
Premium base: https://macify-videos-1430886267.cos.ap-beijing.myqcloud.com/macify-premium
Premium path: macify-premium/videos/<source>-<video-id>.mp4
```

- 设置页文案建议：

```text
Apple 轻量航拍
高端免费航拍
```

不建议显示 `NPS 公共领域`，因为后续主来源会变成多平台精选。

Phase 5：上传 COS

- 只有小样被用户确认质量后才上传。
- 上传仍需重新向用户索取 `COS_SECRET_ID` / `COS_SECRET_KEY`。
- 不从历史聊天、文档或文件中找密钥，不把密钥写入任何文件。
- 上传命令大致：

```bash
COS_SECRET_ID=xxx COS_SECRET_KEY=yyy node scripts/miniprogram/upload-cos-videos.mjs \
  --bucket macify-videos-1430886267 \
  --region ap-beijing \
  --out-dir local-miniprogram-premium-aerial \
  --prefix macify-premium \
  --cdn-base https://macify-videos-1430886267.cos.ap-beijing.myqcloud.com/macify-premium \
  --public-read
```

上传后提醒用户禁用/删除 `macify-cos-uploader` 或删除该 API 密钥。

### 当前决策

- 完全抛弃 `npsPublicDomain` 路线。
- 不再继续执行当前 NPS 99 条批量转码。
- 不上传 `local-miniprogram-public-domain/` 的 NPS 小样到 COS。
- 已转码的 NPS 本地小样目录应删除，不保留为后续候选。
- 下一轮优先任务是建立 `premium-free-aerial` 候选数据和采集/筛选脚本，然后先做 5-10 条样片。

### 2026-05-10：开始下载前已完成的准备

本轮先把“高端免费航拍”路线落成代码和文档准备，不下载、不转码、不上传。

核心策略：

- Apple 轻量源继续作为默认主源，路径仍然是 `macify/videos/<apple-video-id>.mp4`。
- 非 Apple 源统一命名为 `premiumFreeAerial`，产品文案为“高端免费航拍”。
- 非 Apple 视频统一走独立清单、独立 COS base、独立 COS 前缀：

```text
miniprogram/data/premium-free-aerial-videos.js
https://macify-videos-1430886267.cos.ap-beijing.myqcloud.com/macify-premium
macify-premium/videos/<source-video-id>.mp4
```

必须遵循的原则：

- 先候选、再验片、再小样、最后才批量转码和上传。
- 5 个来源每源一期目标 100 条候选；100 不是永久上限，后续可以继续扩充，但不能为了凑数牺牲质感。
- 当前 Premium Free Aerial 主分类只使用：`Landscapes`、`Cities`、`AnimalsAndPlants`、`Motion`、`Underwater`；Apple 原始 `Space` 分类在设置页显示为“太空”。
- 不使用 `Mac` / `其他` 分类；原本可能归入 `Mac` 的视频必须归入上面这些主分类之一，否则不进入当前库。
- 海岸、山脉、森林、湖泊、日落等细节只写入 `tags` / `subcategories` / `locationName` / `description`。
- 每条视频必须保留来源页、授权、署名、授权备注、地点/场景、中文说明；后续审片必须同步审阅标题、地点和介绍文案。
- 不做原片下载入口，不把素材作为 stock/wallpaper 平台再分发。
- 任何上传都必须走 `macify-premium/`，不得覆盖 Apple 的 `macify/videos/`。
- 上传前仍需重新向用户索取 `COS_SECRET_ID` / `COS_SECRET_KEY`，不从历史聊天、文档或文件里找密钥。

已完成的代码准备：

- 新增空清单：

```text
miniprogram/data/premium-free-aerial-videos.js
```

- `miniprogram/utils/storage.js`
  - 新增 `premiumFreeAerialVideoBase`
  - 新增 `premiumFreeAerialSourceVersion`
  - 默认 base 指向 `macify-premium`
  - 不再保留旧 `npsPublicDomain` 兼容分支；未知视频库会回到 Apple
- `miniprogram/utils/videos.js`
  - 读取 `premium-free-aerial-videos.js`
  - `premiumFreeAerial` 走独立 base
  - 支持 `displayName`、`originalName`、`locationName`、`locationCountry`、`description`
- `miniprogram/pages/settings/*`
  - 设置页文案改为“高端免费航拍”
  - 根域名字段改为 `premiumFreeAerialVideoBase`
  - 提示独立 COS 前缀 `macify-premium/videos/`
- `miniprogram/pages/index/index.js`
  - 视频介绍优先使用清单内 `description`
  - Apple 仍按 `video-intros.js` 回退
- `scripts/miniprogram/prepare-lite-videos.mjs`
  - 新增 `--source premiumFreeAerial`
- 新增数据校验脚本：

```text
scripts/miniprogram/validate-premium-aerial-videos.mjs
npm run mini:premium:validate
```

下载 5 个源之前，下一步应先做：

1. 为 Mixkit / Pexels / Pixabay / Dareful / Coverr 建候选采集逻辑或人工录入表。
2. 每条候选补齐清单字段并运行 `npm run mini:premium:validate`。
3. 先从候选中人工挑 20-30 条最像 Apple Aerial 的片段。
4. 只转 5-10 条高质量小样，用户确认后再扩展到每源 100 条候选。

### 2026-05-10：NPS 删除和本地视频缓存策略

用户明确要求完全抛弃 `npsPublicDomain`，并且未来每一条非 Apple 视频都必须用户看过、确认质量后才能新增。

已执行/应保持：

- 删除 `miniprogram/data/public-domain-videos.js`
- 删除 `scripts/miniprogram/fetch-public-domain-videos.mjs`
- 删除本地 NPS 小样目录 `local-miniprogram-public-domain/`
- `scripts/miniprogram/prepare-lite-videos.mjs` 删除 `--source publicDomain`
- 小程序 active code 中不再出现 `npsPublicDomain`
- `.gitignore` 改为忽略 `local-miniprogram-premium-aerial/`

本地缓存策略：

- 只缓存 `videoSource === 'lite'` 的 MP4，不缓存 Apple 官方 MOV。
- 用户第一次进入时：
  - 如果找到上一次缓存的视频文件，继续播放这条本地文件。
  - 如果找不到缓存，则随机选择一条当前视频库的视频。
- 用户不点击换视频时：
  - 当前视频循环播放，不再自动切下一条。
  - 如果当前视频是远程 MP4，小程序后台下载到 `wx.env.USER_DATA_PATH/macify-video-cache/`。
  - 下载完成后记录为“上一次满意的视频”，之后优先使用本地文件。
- 用户点击右下角换视频或下拉刷新时：
  - 才主动随机选择新视频。
  - 新视频会重新进入缓存流程，并替换“上一次缓存视频”记录。
- 如果本地文件被微信清理或不存在：
  - 小程序自动回退为随机远程视频，并重新开始缓存。

这样可以让满意当前视频的用户长期看同一条本地循环视频，减少重复下载，降低 COS 流量成本。

### 2026-05-10：第一条高端免费航拍候选样片

已开始第一条视频，但仍按用户要求保持为 `candidate`，未上传 COS，未标记发布。

候选：

```text
id: mixkit-large-lake-sunset-aerial-4998
source: Mixkit
sourcePage: https://mixkit.co/free-stock-video/landscape-of-a-large-lake-during-sunset-from-the-air-4998/
sourceFile: https://assets.mixkit.co/videos/4998/4998-2160.mp4
license: Mixkit Stock Video Free License
category: Landscapes
displayName: 落日湖岛
qualityTier: candidate
```

已写入：

```text
miniprogram/data/premium-free-aerial-videos.js
```

本地样片：

```text
local-miniprogram-premium-aerial/videos/mixkit-large-lake-sunset-aerial-4998.mp4
```

转码命令：

```bash
node scripts/miniprogram/prepare-lite-videos.mjs \
  --source premiumFreeAerial \
  --id mixkit-large-lake-sunset-aerial-4998 \
  --out-dir local-miniprogram-premium-aerial \
  --height 1080 \
  --duration 45 \
  --profile main \
  --crf 20 \
  --maxrate 8000k \
  --bufsize 16000k \
  --cdn-base https://macify-videos-1430886267.cos.ap-beijing.myqcloud.com/macify-premium \
  --overwrite
```

转码结果：

```text
H.264 Main
yuv420p
606x1080
30fps
20.033333s
2466993 bytes
```

说明：

- 源视频为 4K 4096x2160，页面标注 Free Download、commercial or personal use、Mixkit Stock Video Free License。
- 源片实际时长只有约 20 秒，因此输出样片也是 20 秒；小程序会循环播放。
- 首次转码发现脚本缩放公式在 9:16 / 1080p 时可能产生 607px 奇数宽度，已修复为偶数宽度公式，输出稳定为 606x1080。
- 用户还未审片确认，不得上传 COS，不得改为 `published`。
