# GitHub 发布信息 / GitHub presentation

## 建议仓库设置

- 仓库名：`CallMe`
- 默认语言：中文 README，顶部链接英文版
- 可见性：**Private**（当前包内微信铃声没有公开再分发授权）
- Homepage：暂不填写，项目没有可验证的线上演示
- Issues：可开启，用于收集不同手机的真机截图和诊断报告
- Releases：暂不开启公开二进制发布

### About 描述（中文优先）

> 在需要自然离开尴尬场合时，提前安排一通本地来电；支持 iPhone、Android 及微信语音/视频样式。

### About description (English alternative)

> Schedule an on-device incoming call as a natural exit cue, with iPhone, Android, and WeChat-style voice/video surfaces.

### Topics

`callkit`, `swiftui`, `android-telecom`, `jetpack-compose`, `ios`, `android`,
`incoming-call`, `mobile-prototype`

## 对外说明原则

- 明确标注这是个人原型和平台能力实验，不是通讯服务。
- “已实现”和“真机验证”分开写，不把计划或对话结论写成已验证事实。
- 系统电话 UI 由 iOS 或 Android 默认电话 App 控制；微信模式是本地自绘页面。
- 除小米外的 Android 厂商配置目前只是响应式基线。
- 不上传带个人姓名、聊天列表、桌面图标或联系人信息的参考截图。
- 公开仓库或公开 Release 之前，必须先解决微信铃声再分发授权和项目许可证。

## Before a public repository

Before changing the repository from private to public:

1. Resolve redistribution rights for every bundled media asset.
2. Select a source-code license and confirm it is compatible with all dependencies and assets.
3. Capture sanitized screenshots directly from CallMe, without personal contacts or unrelated apps.
4. Re-run the build, unit tests, README validation, and secret scan.
5. Verify the rendered README, links, repository metadata, and release artifacts on GitHub.
