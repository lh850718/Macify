# 呼吸Zen Flutter App 发布准备清单

更新日期：2026-06-28

本文记录 Flutter App 上架或自有安装包发布前需要核对的资源、授权、隐私和权限边界。它是发布准备草案，不替代 App Store Connect、Google Play Console 或法律审核里的最终填写。

## 当前代码事实

- App 名称：`呼吸Zen`。
- Flutter 项目：`huxi_zen`。
- Android applicationId：`com.huxizen.huxi_zen`。
- iOS bundle id：`com.huxizen.huxiZen`。
- 当前不登录、不注册账号、不请求定位、不读取通讯录、相册、相机或麦克风。
- 当前不上传用户文件，不接入广告，不接入第三方统计 SDK。
- 本地保存：收藏、显示设置、天气城市和温度单位、自定义混音、呼吸节奏、颂钵音和人声提示开关、媒体缓存索引、天气缓存。
- 网络请求：COS 视频 / 音频 / 内容清单，Open-Meteo 天气接口；生产入口已配置 COS 远端 `content-manifest.json`，启动仍先展示本地内容，远端检查失败不阻塞首页。
- 当前内容池：43 条公开视频，其中 42 条 Pixabay、1 条 Mixkit。
- 当前首包资源：19 条 bundled 视频，12 条 bundled 环境音；其余视频走 remote / cached。
- 当前首包视频授权来源：19 条均为 Pixabay。

## 资源分层

资源状态仍保持 `bundled` / `remote` / `cached` / `removed` 四层。不同发布渠道只调整首包资源比例，不改变播放和缓存语义。

### iOS App Store 版

- 首包保留 19 条人工精选视频和 12 条正式环境音。
- 其余 24 条视频通过 COS remote 播放，播放后由 App 长期缓存策略逐步写入本地。
- 默认远端视频缓存预算为 `1GB`，用于降低重复 COS 流量。
- 不把全部 43 条视频一次性打入首包，避免安装包过大影响下载和安装转化。

### Android 商店版

- 当前 debug / prototype 仍按 Flutter asset 首包打入 19 条视频和 12 条环境音。
- Google Play 发布前需要评估包体体积；若正式包体过大，预留 Play Asset Delivery 或等价资源分发方案。
- Android 后台音频和触感仍需真机锁屏 / 熄屏验证后才能定稿。
- 当前 arm64 release APK 约 219.7MB，Google Play 发布前必须继续评估 AAB / 资源包拆分。

### 自有安装包版

- 可以比商店版更积极地内置资源，但仍不建议直接内置全部 43 条视频。
- 资源策略仍保持 `bundled` / `remote` / `cached` / `removed` 四层。
- 自有安装包若增加首包视频数量，必须同步更新 `assets/media/bundled-media.json`、体积记录和授权核对结果。

## 包体评估

当前本机实测：

| 项目 | 体积 |
| --- | ---: |
| `assets/media/videos/` | 166MB |
| `assets/media/audio/` | 24MB |
| `assets/content/` | 476KB |
| Android arm64 release APK | Flutter 输出 `219.7MB`，文件 `219,734,941` bytes |
| Android arm64 release AAB | Flutter 输出 `218.4MB`，文件 `218,367,397` bytes |
| iOS release Runner.app（no-codesign） | Flutter 输出 `218.3MB` |
| iOS release Runner.app（Apple Development 签名） | 2026-06-21 已安装到真机 |
| iOS Runner.xcarchive（no-codesign） | Flutter 输出 `366.2MB` |

构建记录：

```bash
flutter build apk --release --target-platform android-arm64
flutter build appbundle --release --target-platform android-arm64
flutter build ios --release --no-codesign
flutter build ipa --release --no-codesign
```

结果：

- 2026-06-20 成功生成 `build/app/outputs/flutter-apk/app-release.apk`，Flutter 输出大小 `219.7MB`。
- 2026-06-20 成功生成 `build/app/outputs/bundle/release/app-release.aab`，Flutter 输出大小 `218.4MB`。
- 2026-06-20 成功生成 `build/ios/iphoneos/Runner.app`，Flutter 输出大小 `218.3MB`；构建使用 `--no-codesign`，只能验证代码和 iOS 工程，不能直接上架或真机安装。
- 2026-06-20 成功生成 `build/ios/archive/Runner.xcarchive`，Flutter 输出大小 `366.2MB`；因为 `--no-codesign`，Flutter 跳过 IPA 导出。
- 2026-06-21 通过 `flutter run -d 00008150-001428D81AF0401C --release --no-resident` 完成 Apple Development 签名 release 构建，并用 `xcrun devicectl device install app` 成功安装到 `李慧’s iPhone`；命令行启动因设备锁屏被 `SBMainWorkspace` 拒绝，需解锁后手动打开验证。

注意：

- 未限定 ABI 的通用 release APK 仍未在本轮重测；Google Play 推荐使用 AAB，自有分发如需 universal APK 再单独构建。
- 2026-06-21 App Icon 已替换为用户提供的彩色呼吸花图标，iOS AppIcon 全尺寸和 Android launcher mipmap 均为 RGB PNG、无 alpha。Launch Image 仍是 Flutter 默认占位资源，发布前必须替换为正式启动图。
- Android Gradle release 已支持读取 `android/key.properties` 和 keystore 做正式签名；当前仓库未发现 Android keystore / `key.properties`、iOS signing 证书或导出配置，真正上传 Google Play / App Store 前必须补齐签名材料。

结论：

- 2026-06-05 内容池清理到 43 条后，Android / iOS release 构建均已在本机走通。
- 只改 APK 为 AAB 不会明显降低首包大小；主要体积来自 bundled MP4。
- 商店版应优先评估 Play Asset Delivery / 减少首包视频数。
- 自有安装包可以接受更大的首包，但仍需权衡下载转化。

## 授权核对

每次发布前必须重新执行：

```bash
npm run content:validate
flutter test test/content_repository_test.dart test/bundled_media_catalog_test.dart
```

核对项：

- `assets/content/videos.json` 中每条 `qualityTier: "published"` 视频必须有 `sourceName`、`sourcePage`、`license`、`licenseNotes`。
- `sourceName` 当前只应出现 `Pixabay` 和 `Mixkit`；新增来源前必须先补授权页展示规则。
- 已删除视频不能继续出现在 `content-dist`、COS manifest、Flutter bundled catalog 或小程序发布池里。
- `assets/media/bundled-media.json` 里的视频 ID 必须仍存在于共享内容源，并且不能被远端 manifest 标记为 removed。
- Flutter 授权页入口保留 `© 呼吸Zen`，展示 Macify MIT 声明和公开素材授权记录。
- App 不提供素材下载、转售或独立素材库分发入口。

当前授权页实现：

- `lib/src/features/licenses/license_page.dart`
- 入口位于设置页版权标题 `© 呼吸Zen`

## 隐私表草案

### App Store Connect App Privacy

当前建议填写方向：

- Data Used to Track You：无。
- Data Linked to You：无。
- Data Not Linked to You：无。
- Tracking：不跟踪，不使用 IDFA，不接入广告或跨 App / 网站追踪。
- Contact Info、Health and Fitness、Location、Contacts、User Content、Identifiers、Usage Data、Diagnostics、Other Data：当前 App 代码不收集。

需要人工确认：

- COS 与 Open-Meteo 的服务器日志可能记录 IP、User-Agent、请求路径等传输层信息。若发布审核要求把服务端日志也纳入披露，需要按实际云端日志保留策略补充。
- 若后续接入统计、崩溃分析、登录、支付或推送，必须重新填写隐私表。

### Google Play Data Safety

当前建议填写方向：

- Does your app collect or share any of the required user data types? 当前 App 代码不主动收集或共享 Google Play 数据安全表里的用户数据类型。
- Data encrypted in transit：网络请求使用 HTTPS URL 时为加密传输；发布前必须确认 COS 和 Open-Meteo 配置均为 HTTPS。
- Data deletion：当前无账号和云端用户数据，不提供账号级删除流程；本地设置和缓存可随卸载删除。
- App functionality：本地保存的偏好、缓存、天气城市只用于 App 功能。

需要人工确认：

- Android `POST_NOTIFICATIONS` 目前服务于未来前台媒体服务通知；发布前若默认不展示通知，应确认权限请求时机和文案。
- 若未来添加后台媒体通知、崩溃收集或统计 SDK，需要重新评估收集、共享和删除流程。

## 权限说明

### Android

- `INTERNET`：播放 COS 远端视频 / 音频、检查内容清单、请求 Open-Meteo 天气。
- `WAKE_LOCK`：为后台媒体播放 / 原型服务保留。
- `VIBRATE`：呼吸触感提示。
- `FOREGROUND_SERVICE`：后台媒体播放 service 原型。
- `FOREGROUND_SERVICE_MEDIA_PLAYBACK`：Android 媒体前台服务类型。
- `POST_NOTIFICATIONS`：Android 13+ 前台服务通知预留；发布前需确认实际请求时机。

### iOS

- `UIBackgroundModes audio`：为后台音频播放验证和未来生产实现预留。
- 当前不声明定位、相机、相册、麦克风、通讯录等权限。

## 发布前阻塞项

- 重新确认 App Store / Google Play 隐私表与当前代码、云端日志策略一致。
- 替换默认 Launch Image；App Icon 已在 2026-06-21 替换，启动图仍待处理。
- 补齐 Android release signing（keystore、`key.properties` 或 CI secret）和 iOS App Store signing（Apple Developer Team、bundle id、证书 / profile、ExportOptions）。
- 如需自有 universal APK，在网络稳定环境重新构建 Android universal APK，并记录 arm64、universal、AAB 体积差异。
- Android / iOS 真机锁屏音频、呼吸提示音、人声提示和触感强度校准。
- Android 前台服务通知交互和权限请求时机。
- iOS 后台音频真机稳定性；2026-06-20 已改为启动即配置 `AVAudioSession.playback` 并避免业务生命周期主动停掉 `♪` / 呼吸提示音，仍需重新安装真机 release 包后验证锁屏持续播放。
- iOS 前台触感；2026-06-20 已接入 `huxi_zen/background_audio` haptic pattern，2026-06-21 已改为贴近小程序 `wx.vibrateShort` 的吸气短震队列：`light` 使用 `UISelectionFeedbackGenerator`，`medium` / `heavy` 使用系统 impact feedback，Flutter 点击兜底为 `HapticFeedback.selectionClick()`。仍需真机确认体感；iOS 后台持续触感仍按系统限制视为不可靠。
- 生产入口已启用远端 manifest URL；发布前必须在真机上确认删除 / 更新资源能正确清理 cached 文件。

## 官方参考

- Apple App Privacy Details: https://developer.apple.com/app-store/app-privacy-details/
- App Store Review Guidelines: https://developer.apple.com/app-store/review/guidelines/
- Google Play Data Safety: https://support.google.com/googleplay/android-developer/answer/10787469
