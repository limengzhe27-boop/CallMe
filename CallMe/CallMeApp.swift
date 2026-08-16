import SwiftUI

@main
struct CallMeApp: App {
    @StateObject private var callManager = CallManager()
    @Environment(\.scenePhase) private var scenePhase
    @State private var didRunCommandLineTest = false

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(callManager)
                .onAppear {
                    callManager.recordLifecycle("界面已显示")
                    runCommandLineTestIfNeeded()
                }
                .onChange(of: scenePhase) { phase in
                    if phase == .background {
                        callManager.appDidEnterBackground()
                    } else if phase == .active {
                        callManager.appDidBecomeActive()
                    }
                    callManager.recordLifecycle("App 状态：\(description(for: phase))")
                }
        }
    }

    private func runCommandLineTestIfNeeded() {
        guard !didRunCommandLineTest,
              ProcessInfo.processInfo.arguments.contains("--callkit-autotest") else {
            return
        }
        didRunCommandLineTest = true
        callManager.recordLifecycle("启动参数触发 3 秒前台 CallKit 自动测试")
        callManager.scheduleIncomingCall(after: 3)
    }

    private func description(for phase: ScenePhase) -> String {
        switch phase {
        case .active:
            return "前台"
        case .inactive:
            return "非活跃"
        case .background:
            return "后台"
        @unknown default:
            return "未知"
        }
    }
}
