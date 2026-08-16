# CallKit MVP 开源实现调研

调研日期：2026-08-13。

## 结论

第一阶段继续采用原生 SwiftUI + CallKit，不引入 Flutter、React Native、PushKit 或服务器。

真机排查发现 iOS 26.5 的 `callservicesd` 会拒绝 `hasVoIPBackgroundMode: 0` 的 CallKit
Provider，因此项目必须声明 `UIBackgroundModes: voip`。这项声明只解决 Provider 注册；
本地倒计时仍依赖有限后台任务，不能保证 30 秒或 1 分钟后仍执行。

2026-08-14 已在 iPhone 16 / iOS 26.5 验证：10 秒锁屏来电、系统 UI、接听、拒绝和结束
通话成功。微信风格页面只能在 App 前台或接听后由 App 自己显示；锁屏来电仍是系统 UI。

## 参考项目

| 项目 | 状态/技术栈 | 锁屏机制 | 付费/服务依赖 | 采用判断 |
|---|---|---|---|---|
| [OpenTok CallKit](https://github.com/opentok/CallKit) | MIT；Swift/UIKit；2022-06-26 归档 | “3 秒后”按钮调用 `beginBackgroundTask` + `DispatchQueue.asyncAfter` + `reportNewIncomingCall`；项目还声明了旧式 audio/fetch/remote-notification/voip 后台模式 | 完整 Demo 依赖 OpenTok；远程来电依赖 PushKit | 不复制项目；只采用短时后台任务的实验结构和 Provider/Delegate 思路 |
| [flutter_callkit_incoming](https://github.com/hiennguyen92/flutter_callkit_incoming) | MIT；Flutter + iOS CallKit + Android 自定义来电；截至 2026-08-11 仍更新 | iOS 唤醒/终止态明确推荐 PushKit/VoIP，并声明 voip/remote-notification 后台模式 | PushKit/APNs 方案需要相应签名能力与发送端 | 只参考参数模型；MVP 不引入 Flutter 或 PushKit |
| [react-native-callkeep](https://github.com/react-native-webrtc/react-native-callkeep) | React Native；iOS CallKit + Android ConnectionService | 文档说明 iOS 唤醒 App 需配合 VoIP Push | 需要额外跨平台运行时；锁屏可靠方案仍是 PushKit | 不采用；进一步印证框架不能绕过 iOS 后台规则 |
| [WebTrit callkeep](https://github.com/WebTrit/webtrit_callkeep) | Flutter；iOS CallKit/PushKit | 终止态锁屏来电使用 CallKit + PushKit | PushKit/APNs | 不采用；作为现代实现对照 |

## OpenTok 旧 Sample 的关键事实

README 所说“锁屏后 3 秒唤醒”有真实代码对应：

1. 按钮事件调用 `UIApplication.shared.beginBackgroundTask`。
2. 主队列 `asyncAfter` 3 秒。
3. 调用 `reportNewIncomingCall`。
4. completion 中结束后台任务。

因此它不是证明“普通 Timer 在后台永远可靠”，而是证明旧 iOS 上一次用户发起的短时后台任务曾足够覆盖 3 秒延迟。当前 iOS 26.5 是否仍允许相同效果，必须以当前真机实验为准。

旧 Sample 还注册 PushKit、声明 `voip` 等后台模式并连接 OpenTok。当前真机已经单独验证
`voip` 声明是 CallKit Provider 注册所需；PushKit、远程通知和 OpenTok 仍未引入，也不能
用这个声明假装普通定时器拥有长期后台唤醒能力。

## Apple 当前 API/政策边界

- `CXProvider.reportNewIncomingCall` 仍是向系统报告 incoming call 的正式 API。
- 系统可以因勿扰、号码拦截或其他原因拒绝来电，必须记录 completion error。
- Apple 将 CallKit/PushKit描述为真实 VoIP 通话能力。
- VoIP Push 不应被用于非实时网络语音来电；因此第一阶段不启用 PushKit。

## 当前实验设计

1. 前台点击，等待 10 秒：建立 CallKit 基线。
2. 点击后立即回主屏幕：验证有限时后台任务。
3. 点击后立即锁屏：验证响铃、亮屏、系统来电 UI、接听和拒绝。
4. 如果 10 秒成功，再把 UI 增加到 30 秒和 1 分钟分别测试；不能从 10 秒结果推断更长时间可靠。
5. 若失败，依据事件日志区分：延迟闭包没运行、后台任务提前过期、CallKit completion 返回错误，或 CallKit 成功但系统设置抑制声音/界面。
