import AVFAudio
import AudioToolbox
import CallKit
import Combine
import Darwin
import Foundation
import os
import UIKit

enum IncomingCallStyle: String, CaseIterable, Identifiable {
    case phone
    case wechatVoice
    case wechatVideo

    var id: String { rawValue }

    var title: String {
        switch self {
        case .phone: return "手机来电"
        case .wechatVoice: return "微信语音"
        case .wechatVideo: return "微信视频"
        }
    }

    var hasVideo: Bool { self == .wechatVideo }

    var usesCustomForegroundUI: Bool { self != .phone }

    func effectiveRingtone(selected ringtone: IncomingRingtone) -> IncomingRingtone {
        guard self != .phone else {
            return ringtone == .custom ? .system : ringtone
        }
        return ringtone == .system || ringtone == .custom ? .wechatClassic : ringtone
    }

}

enum IncomingRingtone: String, CaseIterable, Identifiable {
    case system
    case wechatClassic
    case callMe
    case chatClassic
    case chatCrystal
    case chatMinimal
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "系统默认"
        case .wechatClassic: return "微信经典"
        case .callMe: return "双音铃声"
        case .chatClassic: return "经典数字"
        case .chatCrystal: return "清脆旋律"
        case .chatMinimal: return "极简轻响"
        case .custom: return "我导入的音效"
        }
    }

    var resourceName: String? {
        switch self {
        case .system, .custom: return nil
        case .wechatClassic: return "WeChatClassic.mp3"
        case .callMe: return "CallMeRingtone.wav"
        case .chatClassic: return "ChatClassic.wav"
        case .chatCrystal: return "ChatCrystal.wav"
        case .chatMinimal: return "ChatMinimal.wav"
        }
    }

    static let phoneChoices: [IncomingRingtone] = [
        .system, .callMe, .wechatClassic, .chatClassic, .chatCrystal, .chatMinimal
    ]

    static let chatChoices: [IncomingRingtone] = [
        .wechatClassic, .chatClassic, .chatCrystal, .chatMinimal, .callMe
    ]
}

final class CallManager: NSObject, ObservableObject, CXProviderDelegate, AVAudioPlayerDelegate {
    @Published private(set) var status = "尚未开始"
    @Published private(set) var scheduledDate: Date?
    @Published private(set) var activeCallUUID: UUID?
    @Published private(set) var isShowingCustomIncoming = false
    @Published private(set) var isShowingCustomConnected = false
    @Published private(set) var isShowingPhoneConnected = false
    @Published private(set) var isConnected = false
    @Published private(set) var connectedAt: Date?
    @Published private(set) var isMicrophoneMuted = false
    @Published private(set) var isSpeakerEnabled = false
    @Published private(set) var isVideoCameraEnabled = true
    @Published private(set) var isSelfViewPrimary = false
    @Published private(set) var activeCallerName = "老板"
    @Published private(set) var activeCallerAvatarData = Data()
    @Published private(set) var activeCallStyle: IncomingCallStyle = .phone
    @Published private(set) var answerAudioName = "无（静音）"
    @Published private(set) var audioStatus = "尚未选择接听音频"
    @Published private(set) var wechatVideoName = "未选择"
    @Published private(set) var videoStatus = "可从相册选择接听后循环播放的视频"
    @Published private(set) var wechatVoiceRingtoneName = "CallMe 内置"
    @Published private(set) var wechatVideoRingtoneName = "CallMe 内置"
    @Published private(set) var previewingRingtone: IncomingRingtone?
    @Published private(set) var previewingRingtoneStyle: IncomingCallStyle?
    @Published private(set) var ringtonePreviewMessage = "点播放按钮试听"
    @Published private(set) var isPreviewingAnswerAudio = false
    @Published private(set) var activeWechatVideoURL: URL?
    @Published private(set) var appPlaybackVolume = 0.35
    @Published private(set) var eventLog: [String] = []

    private let provider: CXProvider
    private let callController = CXCallController()
    private var pendingWorkItem: DispatchWorkItem?
    private var pendingCallerName = "老板"
    private var pendingCallerNumber = "01055550123"
    private var pendingCallerAvatarData = Data()
    private var pendingWechatVideoURL: URL?
    private var pendingCallStyle: IncomingCallStyle = .phone
    private var configuredRingtone: IncomingRingtone = .system
    private var configuredCallStyle: IncomingCallStyle = .phone
    private var backgroundTaskIdentifier: UIBackgroundTaskIdentifier = .invalid
    private let logger = Logger(subsystem: "local.callme.mvp", category: "CallKit")
    private var answerAudioPlayer: AVAudioPlayer?
    private var customRingtonePlayer: AVAudioPlayer?
    private var customVibrationTimer: Timer?
    private var shouldDeactivateAudioSessionAfterPlayback = false
    private var shouldPlayAnswerAudio = false
    private var isCallAudioSessionActive = false
    private var isReportingIncomingCall = false
    private var activeUsesCallKit = true
    private var providerIsReady = false

    private static let answerAudioPathKey = "CallMe.AnswerAudioPath"
    private static let answerAudioNameKey = "CallMe.AnswerAudioName"
    private static let appPlaybackVolumeKey = "CallMe.AppPlaybackVolume"
    private static let wechatVideoFileNameKey = "CallMe.WeChatVideoFileName"
    private static let wechatVideoDisplayNameKey = "CallMe.WeChatVideoDisplayName"
    private static let wechatVoiceRingtonePathKey = "CallMe.WeChatVoiceRingtonePath"
    private static let wechatVoiceRingtoneNameKey = "CallMe.WeChatVoiceRingtoneName"
    private static let wechatVideoRingtonePathKey = "CallMe.WeChatVideoRingtonePath"
    private static let wechatVideoRingtoneNameKey = "CallMe.WeChatVideoRingtoneName"
    private static let eventLogKey = "CallMe.PersistentEventLog"

    override init() {
        provider = CXProvider(
            configuration: Self.providerConfiguration(style: .phone, ringtone: .system)
        )
        super.init()
        provider.setDelegate(self, queue: .main)
        answerAudioName = UserDefaults.standard.string(forKey: Self.answerAudioNameKey)
            ?? "无（静音）"
        wechatVideoName = UserDefaults.standard.string(forKey: Self.wechatVideoDisplayNameKey)
            ?? "未选择"
        wechatVoiceRingtoneName = UserDefaults.standard.string(
            forKey: Self.wechatVoiceRingtoneNameKey
        ) ?? "CallMe 内置"
        wechatVideoRingtoneName = UserDefaults.standard.string(
            forKey: Self.wechatVideoRingtoneNameKey
        ) ?? "CallMe 内置"
        if UserDefaults.standard.object(forKey: Self.appPlaybackVolumeKey) != nil {
            appPlaybackVolume = min(
                1,
                max(0, UserDefaults.standard.double(forKey: Self.appPlaybackVolumeKey))
            )
        }
        eventLog = CallEventHistory.normalized(
            UserDefaults.standard.stringArray(forKey: Self.eventLogKey) ?? []
        )
        appendEvent("CXProvider 已创建")
    }

    deinit {
        pendingWorkItem?.cancel()
        customVibrationTimer?.invalidate()
    }

    func prepareProvider(style: IncomingCallStyle, ringtone: IncomingRingtone) {
        guard activeCallUUID == nil, !isReportingIncomingCall else {
            appendEvent("当前存在系统通话，Provider 配置将在下一次来电前更新")
            return
        }
        let effectiveRingtone = style.effectiveRingtone(selected: ringtone)
        guard configuredRingtone != effectiveRingtone || configuredCallStyle != style else {
            return
        }
        provider.configuration = Self.providerConfiguration(
            style: style,
            ringtone: effectiveRingtone
        )
        configuredCallStyle = style
        configuredRingtone = effectiveRingtone
        appendEvent("已更新 \(style.title) Provider 配置：\(effectiveRingtone.title)")
    }

    func setAppPlaybackVolume(_ volume: Double) {
        let clampedVolume = min(1, max(0, volume))
        appPlaybackVolume = clampedVolume
        customRingtonePlayer?.volume = Float(clampedVolume)
        answerAudioPlayer?.volume = Float(clampedVolume)
        UserDefaults.standard.set(clampedVolume, forKey: Self.appPlaybackVolumeKey)
    }

    func scheduleIncomingCall(
        after delay: TimeInterval = 10,
        callerName: String = "老板",
        callerNumber: String = "01055550123",
        callerAvatarData: Data = Data(),
        style: IncomingCallStyle = .phone,
        ringtone: IncomingRingtone = .system
    ) {
        guard activeCallUUID == nil, !isShowingCustomIncoming, !isReportingIncomingCall else {
            appendEvent("已有通话，未创建新的来电")
            return
        }

        pendingWorkItem?.cancel()
        endBackgroundExecution()
        if isPreviewingAnswerAudio {
            stopAudioPreview()
        }

        resetSessionControls()

        let fireDate = Date().addingTimeInterval(delay)
        pendingCallerName = callerName.trimmingCharacters(in: .whitespacesAndNewlines)
        pendingCallerNumber = callerNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        pendingCallerAvatarData = callerAvatarData
        pendingWechatVideoURL = storedWechatVideoURL()
        pendingCallStyle = style
        prepareProvider(style: style, ringtone: ringtone)
        scheduledDate = fireDate
        status = "已安排 \(style.title)，等待 \(Self.delayDescription(delay))"
        appendEvent(
            "安排 \(style.title)在 \(Self.timeFormatter.string(from: fireDate)) 触发：\(pendingCallerName)"
        )
        beginBackgroundExecution()

        let workItem = DispatchWorkItem { [weak self] in
            self?.triggerIncomingCall(ringtone: ringtone)
        }
        pendingWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    func cancelScheduledCall() {
        guard pendingWorkItem != nil else { return }
        pendingWorkItem?.cancel()
        pendingWorkItem = nil
        endBackgroundExecution()
        scheduledDate = nil
        status = "已取消"
        appendEvent("取消尚未触发的来电")
    }

    func endConnectedCall() {
        guard let uuid = activeCallUUID else { return }

        guard activeUsesCallKit else {
            finishLocalCall(message: "通话已结束")
            return
        }

        let transaction = CXTransaction(action: CXEndCallAction(call: uuid))
        callController.request(transaction) { [weak self] error in
            DispatchQueue.main.async {
                if let error {
                    self?.status = "结束通话失败"
                    self?.appendEvent("CXEndCallAction 失败：\(error.localizedDescription)")
                }
            }
        }
    }

    func answerCustomIncomingCall() {
        guard isShowingCustomIncoming, !activeUsesCallKit else { return }
        isShowingCustomIncoming = false
        isShowingCustomConnected = true
        isShowingPhoneConnected = false
        isConnected = true
        connectedAt = Date()
        status = "\(activeCallStyle.title)通话中"
        appendEvent("用户接听前台自定义\(activeCallStyle.title)")

        // Let SwiftUI commit the connected state before touching AVAudioSession. Audio-session
        // activation can block briefly on a real device and must not delay the visual response.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isConnected else { return }
            self.stopCustomRinging(deactivateAudioSession: false)
            self.playSavedAnswerAudio(context: .localCall)
        }
        if activeCallStyle == .wechatVideo {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
                guard let self, self.isConnected else { return }
                _ = self.setSpeakerEnabled(true)
            }
        }
    }

    func declineCustomIncomingCall() {
        guard isShowingCustomIncoming, !activeUsesCallKit else { return }
        stopCustomRinging(deactivateAudioSession: true)
        isShowingCustomIncoming = false
        isShowingCustomConnected = false
        isShowingPhoneConnected = false
        activeCallUUID = nil
        resetSessionControls()
        status = "已拒绝\(activeCallStyle.title)"
        appendEvent("用户拒绝前台自定义\(activeCallStyle.title)")
    }

    func ignoreCustomIncomingCall() {
        guard isShowingCustomIncoming, !activeUsesCallKit else { return }
        stopCustomRinging(deactivateAudioSession: false)
        appendEvent("用户忽略前台自定义\(activeCallStyle.title)，已停止铃声和震动")
    }

    func recordLifecycle(_ message: String) {
        appendEvent(message)
    }

    func clearEventLog() {
        eventLog.removeAll()
        UserDefaults.standard.removeObject(forKey: Self.eventLogKey)
        logger.info("Persistent event history cleared")
    }

    func appDidEnterBackground() {
        guard isShowingCustomIncoming, !activeUsesCallKit else { return }
        stopCustomRinging(deactivateAudioSession: true)
        isShowingCustomIncoming = false
        activeCallUUID = nil
        appendEvent("微信通话进入后台，切换到系统来电界面")
        beginBackgroundExecution()
        reportCallKitIncomingCall()
    }

    func appDidBecomeActive() {
        guard activeUsesCallKit, isConnected else { return }
        if activeCallStyle == .phone {
            isShowingPhoneConnected = true
            appendEvent("手机通话回到前台，显示通话中页面")
        } else {
            isShowingCustomConnected = true
            appendEvent("微信通话回到前台")
        }
    }

    @discardableResult
    func setSpeakerEnabled(_ enabled: Bool) -> Bool {
        do {
            try AVAudioSession.sharedInstance().overrideOutputAudioPort(enabled ? .speaker : .none)
            isSpeakerEnabled = enabled
            appendEvent(enabled ? "音频已切换到扬声器" : "音频已切换到听筒/默认输出")
            return true
        } catch {
            appendEvent("切换音频输出失败：\(error.localizedDescription)")
            return false
        }
    }

    func setCallMuted(_ muted: Bool) {
        isMicrophoneMuted = muted
        guard let uuid = activeCallUUID, activeUsesCallKit else {
            appendEvent(muted ? "麦克风已静音" : "麦克风已取消静音")
            return
        }
        let transaction = CXTransaction(action: CXSetMutedCallAction(call: uuid, muted: muted))
        callController.request(transaction) { [weak self] error in
            DispatchQueue.main.async {
                if let error {
                    self?.appendEvent("切换静音失败：\(error.localizedDescription)")
                }
            }
        }
    }

    func setVideoCameraEnabled(_ enabled: Bool) {
        isVideoCameraEnabled = enabled
        appendEvent(enabled ? "视频摄像头已开启" : "视频摄像头已关闭")
    }

    func setSelfViewPrimary(_ enabled: Bool) {
        isSelfViewPrimary = enabled
    }

    func playDTMF(_ digit: String) {
        guard let uuid = activeCallUUID,
              activeUsesCallKit,
              "0123456789*#".contains(digit),
              digit.count == 1 else { return }
        let action = CXPlayDTMFCallAction(call: uuid, digits: digit, type: .singleTone)
        callController.request(CXTransaction(action: action)) { [weak self] error in
            DispatchQueue.main.async {
                if let error {
                    self?.appendEvent("拨号音 \(digit) 播放失败：\(error.localizedDescription)")
                }
            }
        }
    }

    func importWechatVideo(from sourceURL: URL, displayName: String) {
        do {
            let directory = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let fileExtension = sourceURL.pathExtension.isEmpty ? "mov" : sourceURL.pathExtension
            let fileName = "wechat-video.\(fileExtension)"
            let destinationURL = directory.appendingPathComponent(fileName)

            if let oldFileName = UserDefaults.standard.string(
                forKey: Self.wechatVideoFileNameKey
            ) {
                let oldURL = directory.appendingPathComponent(oldFileName)
                if oldURL != destinationURL {
                    try? FileManager.default.removeItem(at: oldURL)
                }
            }
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)

            UserDefaults.standard.set(fileName, forKey: Self.wechatVideoFileNameKey)
            UserDefaults.standard.set(displayName, forKey: Self.wechatVideoDisplayNameKey)
            wechatVideoName = displayName
            videoStatus = "接听微信视频后将静音循环播放"
            appendEvent("已导入微信视频素材：\(displayName)")
        } catch {
            videoStatus = "视频导入失败"
            appendEvent("微信视频导入失败：\(error.localizedDescription)")
        }
    }

    func clearWechatVideo() {
        if let url = storedWechatVideoURL() {
            try? FileManager.default.removeItem(at: url)
        }
        UserDefaults.standard.removeObject(forKey: Self.wechatVideoFileNameKey)
        UserDefaults.standard.removeObject(forKey: Self.wechatVideoDisplayNameKey)
        wechatVideoName = "未选择"
        videoStatus = "可从相册选择接听后循环播放的视频"
        appendEvent("已清除微信视频素材")
    }

    func recordWechatVideoSelectionFailure(_ message: String) {
        videoStatus = "视频选择失败"
        appendEvent("微信视频选择失败：\(message)")
    }

    func wechatRingtoneName(for style: IncomingCallStyle) -> String {
        switch style {
        case .wechatVoice: return wechatVoiceRingtoneName
        case .wechatVideo: return wechatVideoRingtoneName
        case .phone: return "不适用"
        }
    }

    func hasCustomWechatRingtone(for style: IncomingCallStyle) -> Bool {
        storedWechatRingtoneURL(for: style) != nil
    }

    @discardableResult
    func importWechatRingtone(from sourceURL: URL, for style: IncomingCallStyle) -> Bool {
        guard style != .phone else { return false }
        let hasSecurityAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if hasSecurityAccess { sourceURL.stopAccessingSecurityScopedResource() }
        }

        do {
            let directory = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            ).appendingPathComponent("incoming-sounds", isDirectory: true)
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            let fileExtension = sourceURL.pathExtension.isEmpty ? "audio" : sourceURL.pathExtension
            let baseName = style == .wechatVoice ? "wechat-voice" : "wechat-video"
            let destinationURL = directory
                .appendingPathComponent(baseName)
                .appendingPathExtension(fileExtension)

            if let oldPath = UserDefaults.standard.string(forKey: ringtonePathKey(for: style)) {
                try? FileManager.default.removeItem(atPath: oldPath)
            }
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)

            // 立即解码一次，避免保存一个 AVAudioPlayer 无法播放的文件。
            _ = try AVAudioPlayer(contentsOf: destinationURL)
            UserDefaults.standard.set(destinationURL.path, forKey: ringtonePathKey(for: style))
            UserDefaults.standard.set(sourceURL.lastPathComponent, forKey: ringtoneNameKey(for: style))
            setWechatRingtoneName(sourceURL.lastPathComponent, for: style)
            appendEvent("已导入\(style.title)提示音：\(sourceURL.lastPathComponent)")
            return true
        } catch {
            appendEvent("\(style.title)提示音导入失败：\(error.localizedDescription)")
            return false
        }
    }

    func toggleRingtonePreview(
        for style: IncomingCallStyle,
        ringtone: IncomingRingtone
    ) {
        if previewingRingtoneStyle == style,
           previewingRingtone == ringtone,
           customRingtonePlayer?.isPlaying == true {
            stopRingtonePreview()
            return
        }
        previewRingtone(for: style, ringtone: ringtone)
    }

    func previewRingtone(
        for style: IncomingCallStyle,
        ringtone: IncomingRingtone
    ) {
        stopCustomRinging(deactivateAudioSession: false)
        guard ringtone != .system else {
            ringtonePreviewMessage = "系统默认铃声只能在实际来电时由 iPhone 播放"
            return
        }
        guard appPlaybackVolume > 0 else {
            ringtonePreviewMessage = "应用内音量为 0%，调高后才能试听"
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
            let effectiveRingtone = style.effectiveRingtone(selected: ringtone)
            let url = ringtone == .custom
                ? storedWechatRingtoneURL(for: style)
                : Bundle.main.url(forResource: effectiveRingtone.resourceName, withExtension: nil)
            guard let url else {
                ringtonePreviewMessage = "找不到这个音效文件"
                appendEvent("找不到可试听的\(style.title)提示音")
                return
            }
            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = self
            player.numberOfLoops = 0
            player.volume = Float(appPlaybackVolume)
            player.prepareToPlay()
            guard player.play() else {
                ringtonePreviewMessage = "无法开始播放"
                try? session.setActive(false, options: [.notifyOthersOnDeactivation])
                return
            }
            customRingtonePlayer = player
            previewingRingtoneStyle = style
            previewingRingtone = ringtone
            ringtonePreviewMessage = "正在试听：\(ringtone.title)"
            appendEvent("试听\(style.title)提示音")
        } catch {
            ringtonePreviewMessage = "试听失败：\(error.localizedDescription)"
            appendEvent("\(style.title)提示音试听失败：\(error.localizedDescription)")
        }
    }

    func stopRingtonePreview() {
        stopCustomRinging(deactivateAudioSession: true)
        ringtonePreviewMessage = "已停止试听"
    }

    func clearWechatRingtone(for style: IncomingCallStyle) {
        guard style != .phone else { return }
        stopRingtonePreview()
        if let oldPath = UserDefaults.standard.string(forKey: ringtonePathKey(for: style)) {
            try? FileManager.default.removeItem(atPath: oldPath)
        }
        UserDefaults.standard.removeObject(forKey: ringtonePathKey(for: style))
        UserDefaults.standard.removeObject(forKey: ringtoneNameKey(for: style))
        setWechatRingtoneName("CallMe 内置", for: style)
        appendEvent("已恢复\(style.title)内置提示音")
    }

    func importAnswerAudio(from sourceURL: URL) {
        let hasSecurityAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if hasSecurityAccess { sourceURL.stopAccessingSecurityScopedResource() }
        }

        do {
            let directory = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let extensionName = sourceURL.pathExtension.isEmpty ? "audio" : sourceURL.pathExtension
            let destinationURL = directory
                .appendingPathComponent("answer-audio")
                .appendingPathExtension(extensionName)

            if let existingPath = UserDefaults.standard.string(forKey: Self.answerAudioPathKey) {
                try? FileManager.default.removeItem(atPath: existingPath)
            }
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)

            UserDefaults.standard.set(destinationURL.path, forKey: Self.answerAudioPathKey)
            UserDefaults.standard.set(sourceURL.lastPathComponent, forKey: Self.answerAudioNameKey)
            answerAudioName = sourceURL.lastPathComponent
            audioStatus = "接听后将播放：\(answerAudioName)"
            appendEvent("已导入接听后音频：\(answerAudioName)")
        } catch {
            audioStatus = "音频导入失败"
            appendEvent("音频导入失败：\(error.localizedDescription)")
        }
    }

    func clearAnswerAudio() {
        stopAnswerAudio(deactivateAudioSession: true)
        if let existingPath = UserDefaults.standard.string(forKey: Self.answerAudioPathKey) {
            try? FileManager.default.removeItem(atPath: existingPath)
        }
        UserDefaults.standard.removeObject(forKey: Self.answerAudioPathKey)
        UserDefaults.standard.removeObject(forKey: Self.answerAudioNameKey)
        answerAudioName = "无（静音）"
        audioStatus = "尚未选择接听音频"
        appendEvent("已清除接听后音频")
    }

    func previewAnswerAudio() {
        playSavedAnswerAudio(context: .preview)
    }

    func toggleAnswerAudioPreview() {
        if isPreviewingAnswerAudio {
            stopAudioPreview()
        } else {
            previewAnswerAudio()
        }
    }

    func stopAudioPreview() {
        answerAudioPlayer?.stop()
        answerAudioPlayer = nil
        isPreviewingAnswerAudio = false
        shouldDeactivateAudioSessionAfterPlayback = false
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        audioStatus = "已停止试听"
    }

    private func triggerIncomingCall(ringtone: IncomingRingtone) {
        let plannedDate = scheduledDate
        pendingWorkItem = nil
        scheduledDate = nil

        if let plannedDate {
            let deviationMilliseconds = Int(Date().timeIntervalSince(plannedDate) * 1_000)
            appendEvent("定时器实际触发偏差：\(deviationMilliseconds) ms")
        }

        let applicationState = UIApplication.shared.applicationState
        appendEvent("触发时 App 状态：\(Self.description(for: applicationState))")

        // Scene 在控制中心、系统转场等瞬间可能短暂变成 inactive，但画面仍在前台。
        // 只有确定进入 background 才交给 CallKit；若随后锁屏，appDidEnterBackground
        // 会把已经显示的微信风格页面切换成系统来电。
        if pendingCallStyle.usesCustomForegroundUI, applicationState != .background {
            showCustomIncomingCall(ringtone: ringtone)
        } else {
            reportCallKitIncomingCall()
        }
    }

    private func reportCallKitIncomingCall() {
        isShowingCustomIncoming = false
        isShowingCustomConnected = false
        isShowingPhoneConnected = false
        let uuid = UUID()

        // Freeze the metadata for this exact call before asking CallKit to present it. The user
        // can answer as soon as the system surface appears, which may be earlier than the
        // reportNewIncomingCall completion handler on a real device.
        activeCallUUID = uuid
        activeUsesCallKit = true
        activeCallerName = pendingCallerName
        activeCallerAvatarData = pendingCallerAvatarData
        activeWechatVideoURL = pendingWechatVideoURL
        activeCallStyle = pendingCallStyle

        let update = CXCallUpdate()
        let handleType: CXHandle.HandleType = pendingCallStyle == .phone ? .phoneNumber : .generic
        update.remoteHandle = CXHandle(type: handleType, value: pendingCallerNumber)
        update.localizedCallerName = pendingCallerName
        update.hasVideo = pendingCallStyle.hasVideo
        update.supportsDTMF = pendingCallStyle == .phone
        update.supportsHolding = false
        update.supportsGrouping = false
        update.supportsUngrouping = false

        status = "正在调用 CallKit…"
        isReportingIncomingCall = true
        if !providerIsReady {
            appendEvent("CallKit Provider 尚未回调就绪，继续尝试上报")
        }
        appendEvent("开始 reportNewIncomingCall，UUID：\(uuid.uuidString)")

        provider.reportNewIncomingCall(with: uuid, update: update) { [weak self] error in
            guard let self else { return }
            self.isReportingIncomingCall = false

            if let error {
                let nsError = error as NSError
                if self.activeCallUUID == uuid, !self.isConnected {
                    self.activeCallUUID = nil
                    self.activeUsesCallKit = false
                }
                self.status = "CallKit 拒绝了来电"
                self.appendEvent(
                    "reportNewIncomingCall 失败：domain=\(nsError.domain) code=\(nsError.code) \(error.localizedDescription)"
                )
                self.logger.error("reportNewIncomingCall failed: \(error.localizedDescription, privacy: .public)")
            } else {
                self.status = "系统已接受来电报告"
                self.appendEvent("reportNewIncomingCall 成功")
                self.logger.info("Incoming call reported: \(uuid.uuidString, privacy: .public)")
            }

            self.endBackgroundExecution()
        }
    }

    private func showCustomIncomingCall(ringtone: IncomingRingtone) {
        activeCallUUID = UUID()
        activeUsesCallKit = false
        activeCallerName = pendingCallerName
        activeCallerAvatarData = pendingCallerAvatarData
        activeWechatVideoURL = pendingWechatVideoURL
        activeCallStyle = pendingCallStyle
        isShowingCustomConnected = false
        isShowingPhoneConnected = false
        isShowingCustomIncoming = true
        status = "正在显示前台\(pendingCallStyle.title)页面"
        startCustomRinging(ringtone: ringtone)
        appendEvent("已显示前台自定义\(pendingCallStyle.title)页面")
        endBackgroundExecution()
    }

    private func beginBackgroundExecution() {
        backgroundTaskIdentifier = UIApplication.shared.beginBackgroundTask(
            withName: "CallMe.LocalDelay"
        ) { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                self.appendEvent("系统即将终止有限时后台任务")
                self.pendingWorkItem?.cancel()
                self.pendingWorkItem = nil
                self.scheduledDate = nil
                self.status = "后台执行时间已用尽，计划未触发"
                self.endBackgroundExecution()
            }
        }

        if backgroundTaskIdentifier == .invalid {
            appendEvent("未获得有限时后台执行机会")
        } else {
            appendEvent("已开始有限时后台任务")
        }
    }

    private func endBackgroundExecution() {
        guard backgroundTaskIdentifier != .invalid else { return }
        let identifier = backgroundTaskIdentifier
        backgroundTaskIdentifier = .invalid
        UIApplication.shared.endBackgroundTask(identifier)
        appendEvent("已结束有限时后台任务")
    }

    private func startCustomRinging(ringtone: IncomingRingtone) {
        stopCustomRinging(deactivateAudioSession: false)

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)

            // 自定义前台页面无法读取系统电话铃声；系统选项使用内置提示音作为安全回退。
            let effectiveRingtone = pendingCallStyle.effectiveRingtone(selected: ringtone)
            let resourceName = effectiveRingtone.resourceName ?? "CallMeRingtone.wav"
            let url = ringtone == .custom
                ? storedWechatRingtoneURL(for: pendingCallStyle)
                    ?? Bundle.main.url(forResource: resourceName, withExtension: nil)
                : Bundle.main.url(forResource: resourceName, withExtension: nil)
            guard let url else {
                appendEvent("找不到前台自定义来电提示音")
                return
            }
            customRingtonePlayer = try AVAudioPlayer(contentsOf: url)
            customRingtonePlayer?.numberOfLoops = -1
            customRingtonePlayer?.volume = Float(appPlaybackVolume)
            customRingtonePlayer?.prepareToPlay()
            customRingtonePlayer?.play()
        } catch {
            appendEvent("前台自定义来电提示音播放失败：\(error.localizedDescription)")
        }

        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        customVibrationTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        }
    }

    private func stopCustomRinging(deactivateAudioSession: Bool) {
        customVibrationTimer?.invalidate()
        customVibrationTimer = nil
        customRingtonePlayer?.stop()
        customRingtonePlayer = nil
        previewingRingtone = nil
        previewingRingtoneStyle = nil
        if deactivateAudioSession {
            try? AVAudioSession.sharedInstance().setActive(
                false,
                options: [.notifyOthersOnDeactivation]
            )
        }
    }

    private func finishLocalCall(message: String) {
        isShowingCustomIncoming = false
        isShowingCustomConnected = false
        isShowingPhoneConnected = false
        isConnected = false
        connectedAt = nil
        activeCallUUID = nil
        resetSessionControls()
        status = "通话已结束"
        appendEvent(message)

        // Remove the full-screen call surface first. Session teardown follows on the next run-loop
        // turn so camera/audio cleanup cannot make the hang-up button feel stuck.
        DispatchQueue.main.async { [weak self] in
            self?.stopCustomRinging(deactivateAudioSession: false)
            self?.stopAnswerAudio(deactivateAudioSession: true)
        }
    }

    private func resetSessionControls() {
        isMicrophoneMuted = false
        isSpeakerEnabled = false
        isVideoCameraEnabled = true
        isSelfViewPrimary = false
    }

    private func appendEvent(_ message: String) {
        let line = "\(Self.timeFormatter.string(from: Date()))  \(message)"
        eventLog.insert(line, at: 0)
        eventLog = CallEventHistory.normalized(eventLog)
        UserDefaults.standard.set(eventLog, forKey: Self.eventLogKey)
        fputs("CALLME_EVENT \(line)\n", stderr)
        fflush(stderr)
        logger.info("\(message, privacy: .public)")
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    // MARK: - CXProviderDelegate

    func providerDidBegin(_ provider: CXProvider) {
        providerIsReady = true
        appendEvent("CallKit Provider 已就绪")
    }

    func providerDidReset(_ provider: CXProvider) {
        let wasReporting = isReportingIncomingCall
        let hadCallKitCall = activeUsesCallKit && activeCallUUID != nil
        providerIsReady = false
        isReportingIncomingCall = false
        isCallAudioSessionActive = false
        if hadCallKitCall {
            activeCallUUID = nil
            isShowingCustomConnected = false
            isShowingPhoneConnected = false
            isConnected = false
            connectedAt = nil
            stopAnswerAudio(deactivateAudioSession: false)
        }
        if wasReporting {
            status = "CallKit Provider 在上报时被重置"
            endBackgroundExecution()
        } else if hadCallKitCall {
            status = "系统已重置通话"
        }
        appendEvent("providerDidReset")
    }

    func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        do {
            try configureCallAudioSession()
            activeCallUUID = action.callUUID
            activeUsesCallKit = true
            // Re-read the frozen request before exposing the connected surface. This is
            // intentionally done before action.fulfill(), so foreground activation cannot show
            // the dashboard for even one render pass.
            activeCallStyle = pendingCallStyle
            activeCallerName = pendingCallerName
            activeCallerAvatarData = pendingCallerAvatarData
            isConnected = true
            connectedAt = Date()
            let isAppActive = UIApplication.shared.applicationState == .active
            // Set this before fulfilling the action even while the app is inactive. CallKit may
            // activate the provider app before or after this callback; keeping the published
            // state true removes that race and guarantees the connected page is already waiting.
            isShowingPhoneConnected = activeCallStyle == .phone
            isShowingCustomConnected = activeCallStyle != .phone && isAppActive
            shouldPlayAnswerAudio = true
            status = "通话中"
            appendEvent("用户接听，CallKit 音频会话已配置")
            action.fulfill()
            if isCallAudioSessionActive {
                shouldPlayAnswerAudio = false
                playSavedAnswerAudio(context: .callKit)
            }
        } catch {
            status = "接听失败：无法配置音频"
            appendEvent("CallKit 音频会话配置失败：\(error.localizedDescription)")
            action.fail()
        }
    }

    func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        let wasConnected = isConnected
        activeCallUUID = nil
        isShowingCustomConnected = false
        isShowingPhoneConnected = false
        isConnected = false
        connectedAt = nil
        resetSessionControls()
        stopAnswerAudio(deactivateAudioSession: false)
        status = wasConnected ? "通话已结束" : "来电已拒绝"
        appendEvent(wasConnected ? "用户结束通话" : "用户拒绝来电")
        action.fulfill()
    }

    func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
        appendEvent(action.isMuted ? "通话已静音" : "通话已取消静音")
        action.fulfill()
    }

    func provider(_ provider: CXProvider, perform action: CXPlayDTMFCallAction) {
        appendEvent("已输入拨号键：\(action.digits)")
        action.fulfill()
    }

    func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        isCallAudioSessionActive = true
        appendEvent("CallKit 已激活音频会话")
        if shouldPlayAnswerAudio {
            shouldPlayAnswerAudio = false
            playSavedAnswerAudio(context: .callKit)
        }
    }

    func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
        isCallAudioSessionActive = false
        stopAnswerAudio(deactivateAudioSession: false)
        appendEvent("CallKit 已停用音频会话")
    }

    private enum AnswerAudioContext {
        case preview
        case callKit
        case localCall
    }

    private func configureCallAudioSession() throws {
        try AVAudioSession.sharedInstance().setCategory(
            .playAndRecord,
            mode: .voiceChat,
            options: [.allowBluetoothHFP]
        )
    }

    private func playSavedAnswerAudio(context: AnswerAudioContext) {
        guard let path = UserDefaults.standard.string(forKey: Self.answerAudioPathKey) else {
            audioStatus = "未设置接听后音频"
            if case .localCall = context {
                try? AVAudioSession.sharedInstance().setActive(
                    false,
                    options: [.notifyOthersOnDeactivation]
                )
            }
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            switch context {
            case .callKit:
                isPreviewingAnswerAudio = false
                shouldDeactivateAudioSessionAfterPlayback = false
            case .preview:
                isPreviewingAnswerAudio = true
                shouldDeactivateAudioSessionAfterPlayback = true
                try session.setCategory(.playback, mode: .default)
                try session.setActive(true)
            case .localCall:
                isPreviewingAnswerAudio = false
                shouldDeactivateAudioSessionAfterPlayback = true
                try configureCallAudioSession()
                try session.setActive(true)
                try session.overrideOutputAudioPort(.none)
            }
            answerAudioPlayer = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: path))
            answerAudioPlayer?.delegate = self
            answerAudioPlayer?.volume = Float(appPlaybackVolume)
            answerAudioPlayer?.prepareToPlay()
            answerAudioPlayer?.play()
            audioStatus = "正在播放：\(answerAudioName)"
            appendEvent("开始播放接听后音频")
        } catch {
            audioStatus = "音频播放失败"
            appendEvent("音频播放失败：\(error.localizedDescription)")
        }
    }

    private func stopAnswerAudio(deactivateAudioSession: Bool) {
        shouldPlayAnswerAudio = false
        isPreviewingAnswerAudio = false
        answerAudioPlayer?.stop()
        answerAudioPlayer = nil
        if deactivateAudioSession || shouldDeactivateAudioSessionAfterPlayback {
            try? AVAudioSession.sharedInstance().setActive(
                false,
                options: [.notifyOthersOnDeactivation]
            )
        }
        shouldDeactivateAudioSessionAfterPlayback = false
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        if customRingtonePlayer === player {
            customRingtonePlayer = nil
            previewingRingtone = nil
            previewingRingtoneStyle = nil
            ringtonePreviewMessage = flag ? "试听完成" : "音效未能完整播放"
            try? AVAudioSession.sharedInstance().setActive(
                false,
                options: [.notifyOthersOnDeactivation]
            )
            return
        }
        let wasPreview = isPreviewingAnswerAudio
        if answerAudioPlayer === player {
            answerAudioPlayer = nil
        }
        isPreviewingAnswerAudio = false
        if shouldDeactivateAudioSessionAfterPlayback {
            try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        }
        shouldDeactivateAudioSessionAfterPlayback = false
        audioStatus = flag ? "播放完成" : "音频未能完整播放"
        let kind = wasPreview ? "试听音频" : "接听后音频"
        appendEvent(flag ? "\(kind)播放完成" : "\(kind)播放中断")
    }

    private static func providerConfiguration(
        style: IncomingCallStyle,
        ringtone: IncomingRingtone
    ) -> CXProviderConfiguration {
        let configuration = CXProviderConfiguration()
        configuration.maximumCallGroups = 1
        configuration.maximumCallsPerCallGroup = 1
        configuration.supportedHandleTypes = [.phoneNumber, .generic]
        configuration.supportsVideo = style.hasVideo
        configuration.includesCallsInRecents = false
        configuration.ringtoneSound = ringtone.resourceName
        return configuration
    }

    private static func delayDescription(_ delay: TimeInterval) -> String {
        CallExperimentRules.delayDescription(delay)
    }

    private func storedWechatVideoURL() -> URL? {
        guard let fileName = UserDefaults.standard.string(
            forKey: Self.wechatVideoFileNameKey
        ),
        let directory = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        ) else {
            return nil
        }
        let url = directory.appendingPathComponent(fileName)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private func storedWechatRingtoneURL(for style: IncomingCallStyle) -> URL? {
        guard style != .phone,
              let path = UserDefaults.standard.string(forKey: ringtonePathKey(for: style)),
              FileManager.default.fileExists(atPath: path) else {
            return nil
        }
        return URL(fileURLWithPath: path)
    }

    private func ringtonePathKey(for style: IncomingCallStyle) -> String {
        style == .wechatVideo
            ? Self.wechatVideoRingtonePathKey
            : Self.wechatVoiceRingtonePathKey
    }

    private func ringtoneNameKey(for style: IncomingCallStyle) -> String {
        style == .wechatVideo
            ? Self.wechatVideoRingtoneNameKey
            : Self.wechatVoiceRingtoneNameKey
    }

    private func setWechatRingtoneName(_ name: String, for style: IncomingCallStyle) {
        if style == .wechatVideo {
            wechatVideoRingtoneName = name
        } else if style == .wechatVoice {
            wechatVoiceRingtoneName = name
        }
    }

    private static func description(for applicationState: UIApplication.State) -> String {
        switch applicationState {
        case .active: return "active（前台）"
        case .inactive: return "inactive（前台转场）"
        case .background: return "background（后台）"
        @unknown default: return "未知"
        }
    }
}
