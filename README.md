# CallMe

[English](README.en.md) · [安装与使用](docs/INSTALLATION.md) · [Android 说明](android/README.md)

CallMe 是一个供个人使用的本地来电安排工具。遇到不方便直接离开的饭局、谈话、会议或
其他尴尬场合时，可以提前安排一通电话，让手机在指定时间响起，再借接电话自然结束当前
场景。整个过程只在自己的手机上运行，不需要另一部手机配合。

它同时也是一个原生移动端来电体验实验：iPhone 使用 CallKit，Android 使用 Telecom、
精确闹钟和全屏来电通知。微信语音和微信视频采用本地自绘界面。CallMe 不连接微信、不
拨出真实电话，也没有服务器、账号或云同步。

当前版本包含两个独立工程：

- iOS 2.2（SwiftUI + CallKit，最低 iOS 16）
- Android 0.24（Kotlin + Jetpack Compose + Telecom，最低 Android 8）

> **发布提示**：仓库保留了从用户本人设备提取的微信经典铃声，用于本地个人验证。
> 该文件没有公开再分发授权。因此，包含该音频的仓库应保持为 **Private**，也不应直接
> 公开发布 APK、IPA 或 Release。其他内置音效的来源见
> [`docs/audio-sources.md`](docs/audio-sources.md)。

## 它可以帮你做什么

- **需要自然离场**：在饭局、聚会或长时间谈话前安排一通来电，以“需要接电话”为由暂时
  离开或结束当前场景。
- **给自己一个明确提醒**：把普通倒计时变成更难忽略的响铃、亮屏和来电画面。
- **演练不同来电体验**：比较 iPhone 和不同 Android 品牌在前台、后台与锁屏时的表现。
- **准备自己的固定模板**：保存“老板”“家人”等常用联系人、头像、来电方式和接听音频，
  下次快速安排。

### 一个 30 秒解围示例

1. 打开 CallMe，把来电人设为“老板”。
2. 选择“手机来电”或“微信语音”，延迟选择 30 秒。
3. 点击安排来电，然后回到桌面或锁屏。
4. 手机响起后接听，在通话页面停留片刻，再自然离开当前场合。

> CallMe 只在本机呈现来电体验。它不会联系所填写的人，也不会产生真实通话或通话费用。

## 界面截图

下面是 iPhone 真机上使用本地示例模板的截图。它们展示的是 CallMe 的本地体验，不代表
真实运营商或微信通话。

<p align="center">
  <img src="docs/assets/screenshots/ios-home.png" alt="CallMe 首页：联系人、快速模板、来电方式、来电时间与安排来电按钮" width="280"><br>
  <sub>首页总览：选择联系人、来电方式和时间后，点击“安排来电”即可开始。</sub>
</p>

<table>
  <tr>
    <td align="center" width="33%"><img src="docs/assets/screenshots/ios-scheduled-phone.png" alt="已安排手机来电的倒计时页面" width="220"><br><sub>安排后：倒计时与锁屏提示</sub></td>
    <td align="center" width="33%"><img src="docs/assets/screenshots/ios-incoming-phone.png" alt="手机来电接听页面" width="220"><br><sub>手机来电：接听或拒绝</sub></td>
    <td align="center" width="33%"><img src="docs/assets/screenshots/ios-connected-phone.png" alt="接听后的手机通话控制页面" width="220"><br><sub>接听后：音频、静音、键盘与更多控制</sub></td>
  </tr>
  <tr>
    <td align="center" width="33%"><img src="docs/assets/screenshots/ios-incoming-wechat-voice.png" alt="微信语音样式来电页面" width="220"><br><sub>微信语音样式：本地来电页</sub></td>
    <td align="center" width="33%"><img src="docs/assets/screenshots/ios-connected-wechat-voice.png" alt="微信语音样式接听后页面" width="220"><br><sub>微信语音样式：接听后控制</sub></td>
    <td align="center" width="33%"><img src="docs/assets/screenshots/ios-ringtone-picker.png" alt="内置来电铃声的试听与选择页面" width="220"><br><sub>声音设置：微信经典铃声可试听与选择</sub></td>
  </tr>
</table>

Android 的界面会因当前默认电话 App 和厂商系统而变化；Android 自绘微信样式界面的截图
将在对应真机素材完成后单独补充。

## 内置铃声

仓库已经包含并实际引用微信经典铃声：

- iOS：`CallMe/WeChatClassic.mp3`
- Android：`android/app/src/main/res/raw/wechat_classic.mp3`

微信语音或微信视频模式默认可以选择“微信经典”。其他内置音效包括经典数字、清脆旋律
和极简轻响；两端也支持从本地导入接听音频。系统手机来电的铃声仍由 iOS 或 Android 的
系统电话能力控制。

## 项目状态与当前能力

| 能力 | iOS | Android | 当前证据 |
| --- | --- | --- | --- |
| 延迟安排手机来电 | CallKit | Telecom / 默认电话 App | 已实现；iPhone 与小米真机验证过核心链路 |
| 微信语音样式 | SwiftUI 自绘页面 | Compose 自绘页面 | 已实现；仅是本地视觉与音频模拟 |
| 微信视频样式 | 摄像头、本地视频、画中画 | 摄像头、画中画、镜头切换 | 已实现；不建立真实通话 |
| 自定义联系人 | 姓名、号码、头像 | 姓名、号码、头像 | 已实现，本地保存 |
| 来电时间 | 1 秒至 24 小时 | 1 秒至 24 小时 | 前台可用；长时间后台可靠性受系统限制 |
| 铃声与接听音频 | 内置、试听、本地导入 | 内置、试听、本地导入 | 已实现；系统电话铃声仍由操作系统控制 |
| 模板与诊断 | 本地模板、事件记录 | 本地模板、事件记录 | 已实现 |

## 两个平台如何适配来电界面

### iPhone

“手机来电”交给 CallKit，由 iOS 显示系统来电和通话界面。App 不能修改系统电话页面的
布局，也不能让单个 App 绕过静音、专注模式或系统铃声音量。

微信语音和微信视频在 App 前台使用自绘页面；锁屏或进入后台后，为了保留亮屏、响铃、
接听和拒绝能力，会切换为 CallKit 系统页面。普通本地计时器不能保证 App 被系统挂起后
仍按任意长延迟准时执行。

### Android 界面策略

“手机来电”通过 `TelecomManager.addNewIncomingCall` 报告给系统，接听页面由设备当前的
默认电话 App 决定。因此小米、三星、华为或其他品牌会自然显示各自的系统电话样式。

微信语音和微信视频是 CallMe 自己绘制的页面。Android 0.24 不再给所有设备套用同一组
小米尺寸，而是按厂商选择布局和权限入口：

- 小米 / Redmi / POCO：已按小米真机截图校准
- 华为 / 荣耀
- OPPO / 一加 / realme
- vivo / iQOO
- Samsung Galaxy
- Google / AOSP 通用

除小米外目前是响应式适配基线，并不代表已经逐台复刻相应品牌。设置页会显示当前检测到
的配置；得到对应品牌真机截图后，可以只调整该厂商参数而不影响其他手机。

## 最短使用流程

1. 在首页设置来电人、来电方式和延迟。
2. 首次使用时，按设置页提示完成系统权限。
3. 先用“立即预览”验证页面、铃声和接听操作。
4. 再安排 10 秒来电，回到主屏幕或锁屏测试。
5. 失败时复制“设置与诊断”里的完整报告，区分定时、权限、系统来电或自绘页面问题。

完整安装步骤见 [`docs/INSTALLATION.md`](docs/INSTALLATION.md)。

## 本地构建

### iOS

1. 用 Xcode 打开 `CallMe.xcodeproj`。
2. 在 Target 的 **Signing & Capabilities** 中选择自己的 Personal Team。
3. 如 Bundle Identifier 冲突，改成自己的唯一标识。
4. 连接 iPhone、开启开发者模式并运行。

普通 Apple ID 可以安装到自己的设备，但 Personal Team 签名通常需要定期重新安装。让其他
人长期使用需要他们自行用 Xcode 签名，或由项目所有者加入 Apple Developer Program 后选择
合适的正式分发方式。

### Android 构建

```bash
cd android
./gradlew testDebugUnitTest assembleDebug
```

生成的调试 APK 位于：

```text
android/app/build/outputs/apk/debug/app-debug.apk
```

其他测试者可以自行编译，或在私下获得可信 APK 后允许“安装未知应用”并安装。首次运行仍
需分别授予通知、全屏来电、精确闹钟、相机和通话账户等权限；不同品牌还可能要求自启动、
后台弹窗或关闭电池优化。

## 架构

```text
用户安排来电
  ├─ iOS 手机来电 ───────→ CallKit ─────────→ iOS 系统来电/通话页
  ├─ iOS 微信模式 ───────→ 前台 SwiftUI / 后台 CallKit
  ├─ Android 手机来电 ───→ AlarmManager → Telecom → 默认电话 App
  └─ Android 微信模式 ───→ AlarmManager → 前台响铃服务 → Compose 全屏页
```

项目不会调用 Android `TelecomManager.placeCall()`，不会拨出真实电话。

## 验证

Android 0.24 已执行：

```bash
./gradlew testDebugUnitTest assembleDebug
```

并安装到小米 `2206122SC`，设备端确认 `versionCode=24`。厂商识别逻辑有单元测试覆盖。

iOS 项目包含 `CallMeTests/CallExperimentRulesTests.swift`。当前工程曾在 iPhone 16 / iOS
26.5 上验证 10 秒 CallKit 响铃、亮屏、系统来电页、接听与拒绝；更长时间锁屏或后台触发
仍属于实验结果，不应写成可靠保证。

## 已知限制

- 这是原型和平台能力实验，不是生产级通讯产品。
- iOS 后台本地定时受系统挂起策略限制；没有使用 PushKit、APNs 或服务器。
- Android 的全屏通知、精确闹钟和后台启动会受到系统版本与厂商策略影响。
- 系统手机来电的铃声、音量、静音和页面样式由操作系统或默认电话 App 控制。
- 微信样式页面和音效不代表腾讯、微信或其他第三方的授权、合作或背书。
- 仓库目前没有开源许可证；在许可证和第三方素材范围明确前，不应把代码或二进制视为可自由再分发。

## 文档

- [`docs/INSTALLATION.md`](docs/INSTALLATION.md)：他人如何安装、权限设置与排错
- [`android/README.md`](android/README.md)：Android 实现与测试路径
- [`MVP_TEST_PLAN.md`](MVP_TEST_PLAN.md)：iPhone 真机实验表
- [`ANDROID_MVP_PLAN.md`](ANDROID_MVP_PLAN.md)：Android 技术路线
- [`docs/research.md`](docs/research.md)：实现调研与技术取舍
- [`docs/audio-sources.md`](docs/audio-sources.md)：音效来源和使用边界
- [`docs/GITHUB_PUBLISHING.md`](docs/GITHUB_PUBLISHING.md)：建议的 GitHub 描述、Topics 与发布边界
