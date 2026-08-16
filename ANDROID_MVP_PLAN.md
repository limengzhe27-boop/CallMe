# CallMe Android MVP 方案与任务

## 1. 当前目标

先验证 Android 能否以 0 成本、本地运行的方式实现：

`设置延迟 → 锁屏 → 到点响铃/震动 → 屏幕亮起 → 系统来电界面 → 接听/拒绝 → 模拟通话状态`

第一阶段不做服务器、账号、数据库、推送、跨平台框架和完整产品 UI。

## 2. 开源调研结论

### DDOneApps/FakeCall

- 地址：https://github.com/DDOneApps/FakeCall
- 最贴近当前目标：通过 Android Telecom Framework 注册 Phone Account，并让系统电话 App 展示来电。
- 已实现精确定时、系统拨号器来电、接听/拒绝、接听后音频和通话记录。
- 项目较活跃，源码使用 Kotlin、Jetpack Compose，目标 Android API 36。
- 许可证为 GPL-3.0。若直接复制或派生其代码，Android 项目需要遵守 GPL；因此本项目只参考技术路径和实验方法，不复制源码。
- 已知风险：部分 OnePlus、Vivo 等设备在锁屏后不触发；不同系统电话 App 的姓名、铃声和电话账户设置行为不同；上游还有一条“被显示为 112/911”的未解决报告。

### msusman1/Amadz

- 地址：https://github.com/msusman1/Amadz
- 完整的开源电话 App，使用 `NotificationCompat.CallStyle` 和 full-screen intent。
- Apache-2.0 许可，可参考其通知和全屏来电组织方式。
- 它是默认拨号器替代品，范围远超本 MVP，不作为项目基础。

### flutter_callkit_incoming

- 地址：https://github.com/hiennguyen92/flutter_callkit_incoming
- Android 使用自定义来电 UI，iOS 使用 CallKit。
- 可用于跨平台 VoIP 产品，但当前项目已经分别采用 Swift 和 Kotlin；引入 Flutter 会增加工具链和调试复杂度，因此不采用。

## 3. 推荐技术路线

使用原生 Kotlin + Jetpack Compose，独立放在 `android/` 目录，不影响现有 iOS 工程。

### 主路线：系统电话 App 来电

1. App 注册一个 `PhoneAccount`。
2. 用户首次在系统设置中启用这个电话账户。
3. 用户点击“10 秒后模拟来电”。
4. `AlarmManager.setExactAndAllowWhileIdle()` 安排本地唤醒事件。
5. `BroadcastReceiver` 到点调用 `TelecomManager.addNewIncomingCall()`。
6. Android Telecom 绑定本项目的 `ConnectionService`。
7. `Connection` 进入 ringing 状态，由系统默认电话 App 响铃并展示来电 UI。
8. 接听时进入 active；拒绝或挂断时进入 disconnected。

这条路线的优势是来电画面由用户真实的系统电话 App 提供，比自绘页面更自然；也不需要自己通过 full-screen intent 强行拉起 Activity。

### 备用路线：CallStyle 全屏通知

仅当目标 Android 手机无法启用 Phone Account，或默认电话 App 不展示 managed ConnectionService 来电时，再实现：

- 高优先级来电通知频道。
- `NotificationCompat.CallStyle.forIncomingCall()`。
- full-screen intent + 自定义锁屏 Activity。
- 接听和拒绝 BroadcastReceiver。

Android 14+ 对 full-screen intent 有特殊权限和商店政策限制，所以不作为第一选择。

## 4. MVP 权限原则

第一版只申请实现验证所必需的能力：

- `SCHEDULE_EXACT_ALARM`：Android 12+ 需要用户在特殊访问设置中授权。
- `BIND_TELECOM_CONNECTION_SERVICE`：用于声明 ConnectionService，由系统绑定。
- 电话状态相关权限只在真机证明必需后添加。

第一版不申请联系人、麦克风、存储、无障碍服务、忽略电池优化等权限，也不加入接听后音频。

## 5. 第一版 UI

- 标题：模拟来电
- 来电人：老板（固定）
- 号码：使用明确的非紧急测试号码
- 延迟：10 秒（第一轮固定）
- 按钮：10 秒后模拟来电
- 状态区：电话账户、精确定时权限、已安排/已触发/接听/拒绝
- 事件日志：显示每个关键 API 是否成功

## 6. 任务清单

### A. 环境准备

1. 安装免费的 Android Studio 和 Android SDK。
2. 配置 Android API 36、Build Tools、Platform Tools 和一个 Pixel 模拟器。
3. 确认 JDK 17、Gradle、`adb` 和模拟器可用。

当前 Mac 已有 JDK 17 和 IntelliJ IDEA，但没有 Android Studio、Android SDK 或 `adb`。

### B. 最小 Telecom 实验

1. 创建 Kotlin + Compose 单模块 App。
2. 声明并实现最小 `ConnectionService`。
3. 注册 `PhoneAccount.CAPABILITY_CALL_PROVIDER`。
4. 提供“启用电话账户”入口。
5. 先做“立即模拟来电”按钮，确认系统电话 App 能展示来电。
6. 实现接听、拒绝、挂断状态回调和日志。

### C. 锁屏定时实验

1. 加入 `AlarmManager` 和显式 `BroadcastReceiver`。
2. 检测并引导用户授予精确定时权限。
3. 实现固定 10 秒 `RTC_WAKEUP + setExactAndAllowWhileIdle`。
4. 测试前台、后台、立即锁屏、锁屏 10 秒。
5. 记录不同厂商对后台与锁屏的限制。

### D. UI 与实验记录

1. 完成最小 Compose 页面。
2. 增加电话账户、权限与定时状态提示。
3. 增加事件日志。
4. 建立与 iPhone 相同的响铃、亮屏、来电 UI、接听、拒绝测试表。

### E. 仅在主路线失败时

1. 实现 CallStyle + full-screen intent 备用实验。
2. 检测 `canUseFullScreenIntent()`。
3. 对比系统 Telecom 路线和自定义 UI 路线的锁屏可靠性。

## 7. 成功标准

Android 第一阶段只有在真机锁屏后出现明显铃声或震动、亮屏、来电界面，并能接听/拒绝时才算成功。普通通知、仅在 App 前台出现页面、或依赖用户主动查看通知都不算成功。

## 8. 风险控制

- 不调用 `TelecomManager.placeCall()`，避免任何真实呼出可能；只使用 `addNewIncomingCall()`。
- 使用明确的非紧急测试号码，不使用 110、112、119、120、911 等号码。
- 先在自己的设备测试，不直接发布到应用商店。
- 不直接复制 GPL 项目代码；实现依据以 Android 官方 API 文档为准。
- 若特定厂商锁屏后杀死任务，先记录机型、系统、日志和授权状态，再决定是否增加电池优化引导或备用路线。
