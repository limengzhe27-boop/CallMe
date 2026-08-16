import AVFoundation
import CoreTransferable
import SwiftUI
import PhotosUI
import UIKit
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var callManager: CallManager
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage("callerName") private var callerName = "老板"
    @AppStorage("callerNumber") private var callerNumber = "13800138000"
    @AppStorage("callStyle") private var storedCallStyle = IncomingCallStyle.phone.rawValue
    @AppStorage("phoneRingtone") private var storedPhoneRingtone = IncomingRingtone.system.rawValue
    @AppStorage("wechatVoiceRingtone") private var storedWechatVoiceRingtone = IncomingRingtone.wechatClassic.rawValue
    @AppStorage("wechatVideoRingtone") private var storedWechatVideoRingtone = IncomingRingtone.wechatClassic.rawValue
    @AppStorage("didMigrateToWechatClassic") private var didMigrateToWechatClassic = false
    @AppStorage("delaySeconds") private var selectedDelay = 10.0
    @AppStorage("callerAvatarData") private var callerAvatarData = Data()
    @AppStorage("selfAvatarData") private var selfAvatarData = Data()

    @State private var customDelayValue = ""
    @State private var customDelayUnit = CallDelayUnit.minutes
    @State private var isSelectingAnswerAudio = false
    @State private var isSelectingWechatRingtone = false
    @State private var wechatRingtoneImportStyle = IncomingCallStyle.wechatVoice
    @State private var selectedAvatarItem: PhotosPickerItem?
    @State private var selectedSelfAvatarItem: PhotosPickerItem?
    @State private var selectedVideoItem: PhotosPickerItem?
    @State private var isShowingContactEditor = false
    @State private var isShowingSoundSettings = false
    @State private var isShowingDiagnostics = false
    @State private var isShowingCustomDelay = false
    @State private var diagnosticCopied = false
    @State private var eventLogCopied = false
    @State private var isConfirmingEventLogClear = false
    @State private var templates: [CallTemplate] = []
    @StateObject private var cameraController = CameraController()

    private let delayOptions: [(TimeInterval, String)] = [
        (10, "10 秒"),
        (30, "30 秒"),
        (60, "1 分钟")
    ]

    private var selectedStyle: Binding<IncomingCallStyle> {
        Binding(
            get: { IncomingCallStyle(rawValue: storedCallStyle) ?? .phone },
            set: {
                storedCallStyle = $0.rawValue
                callManager.prepareProvider(style: $0, ringtone: selectedRingtone.wrappedValue)
            }
        )
    }

    private var selectedRingtone: Binding<IncomingRingtone> {
        Binding(
            get: {
                let rawValue: String
                switch selectedStyle.wrappedValue {
                case .phone: rawValue = storedPhoneRingtone
                case .wechatVoice: rawValue = storedWechatVoiceRingtone
                case .wechatVideo: rawValue = storedWechatVideoRingtone
                }
                return IncomingRingtone(rawValue: rawValue) ?? .system
            },
            set: {
                switch selectedStyle.wrappedValue {
                case .phone: storedPhoneRingtone = $0.rawValue
                case .wechatVoice: storedWechatVoiceRingtone = $0.rawValue
                case .wechatVideo: storedWechatVideoRingtone = $0.rawValue
                }
                callManager.prepareProvider(style: selectedStyle.wrappedValue, ringtone: $0)
            }
        )
    }

    private var nameError: String? {
        CallExperimentRules.callerNameError(callerName)
    }

    private var numberError: String? {
        CallExperimentRules.callerNumberError(callerNumber)
    }

    private var phoneConnectedPresentation: Binding<Bool> {
        Binding(
            get: {
                callManager.isShowingPhoneConnected && callManager.connectedAt != nil
            },
            set: { presented in
                // Interactive dismissal is disabled below. Keep this fallback so an unexpected
                // UIKit dismissal cannot leave a live CallKit call with no visible controls.
                if !presented, callManager.isShowingPhoneConnected {
                    callManager.endConnectedCall()
                }
            }
        )
    }

    var body: some View {
        ZStack {
            NavigationStack {
                Group {
                    if let scheduledDate = callManager.scheduledDate {
                        WaitingCallView(
                            scheduledDate: scheduledDate,
                            callerName: callerName,
                            style: selectedStyle.wrappedValue,
                            onCancel: callManager.cancelScheduledCall
                        )
                    } else {
                        homeDashboard
                    }
                }
                .onAppear {
                    templates = CallTemplateStore.load()
                    if !didMigrateToWechatClassic {
                        storedWechatVoiceRingtone = IncomingRingtone.wechatClassic.rawValue
                        storedWechatVideoRingtone = IncomingRingtone.wechatClassic.rawValue
                        didMigrateToWechatClassic = true
                    }
                    callManager.prepareProvider(
                        style: selectedStyle.wrappedValue,
                        ringtone: selectedRingtone.wrappedValue
                    )
                }
                .onChange(of: selectedAvatarItem) { item in
                    guard let item else { return }
                    Task {
                        let data = try? await item.loadTransferable(type: Data.self)
                        let preparedData = data.flatMap(preparedAvatarData)
                        await MainActor.run {
                            if let preparedData { callerAvatarData = preparedData }
                            selectedAvatarItem = nil
                        }
                    }
                }
                .onChange(of: selectedSelfAvatarItem) { item in
                    guard let item else { return }
                    Task {
                        let data = try? await item.loadTransferable(type: Data.self)
                        let preparedData = data.flatMap(preparedAvatarData)
                        await MainActor.run {
                            if let preparedData { selfAvatarData = preparedData }
                            selectedSelfAvatarItem = nil
                        }
                    }
                }
                .onChange(of: selectedVideoItem) { item in
                    guard let item else { return }
                    Task {
                        do {
                            guard let pickedVideo = try await item.loadTransferable(type: PickedVideo.self) else {
                                await MainActor.run {
                                    callManager.recordWechatVideoSelectionFailure("无法读取所选视频")
                                }
                                return
                            }
                            await MainActor.run {
                                callManager.importWechatVideo(
                                    from: pickedVideo.url,
                                    displayName: pickedVideo.displayName
                                )
                            }
                            try? FileManager.default.removeItem(at: pickedVideo.url)
                        } catch {
                            await MainActor.run {
                                callManager.recordWechatVideoSelectionFailure(error.localizedDescription)
                            }
                        }
                    }
                }
                .fileImporter(
                    isPresented: $isSelectingAnswerAudio,
                    allowedContentTypes: [.audio],
                    allowsMultipleSelection: false
                ) { result in
                    switch result {
                    case .success(let urls):
                        if let url = urls.first { callManager.importAnswerAudio(from: url) }
                    case .failure(let error):
                        callManager.recordLifecycle("音频选择失败：\(error.localizedDescription)")
                    }
                }
                .fileImporter(
                    isPresented: $isSelectingWechatRingtone,
                    allowedContentTypes: [.audio],
                    allowsMultipleSelection: false
                ) { result in
                    switch result {
                    case .success(let urls):
                        if let url = urls.first {
                            if callManager.importWechatRingtone(
                                from: url,
                                for: wechatRingtoneImportStyle
                            ) {
                                selectedRingtone.wrappedValue = .custom
                            }
                        }
                    case .failure(let error):
                        callManager.recordLifecycle(
                            "\(wechatRingtoneImportStyle.title)提示音选择失败：\(error.localizedDescription)"
                        )
                    }
                }
                .sheet(isPresented: $isShowingCustomDelay) { customDelayEditor }
                .onChange(of: scenePhase) { phase in
                    guard callManager.activeCallStyle == .wechatVideo,
                          callManager.isShowingCustomIncoming || callManager.isShowingCustomConnected else {
                        return
                    }
                    if phase == .active, callManager.isVideoCameraEnabled {
                        cameraController.start()
                    } else {
                        cameraController.stop()
                    }
                }
            }

            activeCallOverlay
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .zIndex(10)
        }
        // The phone controls must not live inside activeCallOverlay's conditional ViewBuilder.
        // On iPhone that builder repeatedly collapsed to one grid column even though its
        // background rendered edge-to-edge (IMG_2777/IMG_2779). A dedicated presentation gets
        // its size directly from UIKit's full-screen presentation controller.
        .fullScreenCover(isPresented: phoneConnectedPresentation) {
            if let connectedAt = callManager.connectedAt {
                ReferencePhoneConnectedCallView(
                    callerName: callManager.activeCallerName,
                    avatarData: callManager.activeCallerAvatarData,
                    connectedAt: connectedAt,
                    onHangUp: callManager.endConnectedCall,
                    onMutedChanged: callManager.setCallMuted,
                    onSpeakerChanged: callManager.setSpeakerEnabled,
                    onDigit: callManager.playDTMF
                )
                .interactiveDismissDisabled()
            } else {
                Color.black.ignoresSafeArea()
            }
        }
    }

    @ViewBuilder
    private var activeCallOverlay: some View {
        if callManager.isShowingCustomIncoming || callManager.isShowingCustomConnected {
            Group {
                if callManager.activeCallStyle == .wechatVideo {
                    ReferenceWeChatVideoCallView(
                        callerName: callManager.activeCallerName,
                        avatarData: callManager.activeCallerAvatarData,
                        selfAvatarData: selfAvatarData,
                        videoURL: callManager.activeWechatVideoURL,
                        isConnected: callManager.isShowingCustomConnected,
                        connectedAt: callManager.connectedAt,
                        isMuted: callManager.isMicrophoneMuted,
                        isSpeakerEnabled: callManager.isSpeakerEnabled,
                        isCameraEnabled: callManager.isVideoCameraEnabled,
                        isSelfViewPrimary: callManager.isSelfViewPrimary,
                        cameraController: cameraController,
                        onAnswer: callManager.answerCustomIncomingCall,
                        onDecline: callManager.declineCustomIncomingCall,
                        onHangUp: callManager.endConnectedCall,
                        onIgnore: callManager.ignoreCustomIncomingCall,
                        onMutedChanged: callManager.setCallMuted,
                        onSpeakerChanged: { _ = callManager.setSpeakerEnabled($0) },
                        onCameraChanged: callManager.setVideoCameraEnabled,
                        onSelfViewPrimaryChanged: callManager.setSelfViewPrimary
                    )
                } else {
                    ReferenceWeChatVoiceCallView(
                        callerName: callManager.activeCallerName,
                        avatarData: callManager.activeCallerAvatarData,
                        isConnected: callManager.isShowingCustomConnected,
                        connectedAt: callManager.connectedAt,
                        isMuted: callManager.isMicrophoneMuted,
                        isSpeakerEnabled: callManager.isSpeakerEnabled,
                        onAnswer: callManager.answerCustomIncomingCall,
                        onDecline: callManager.declineCustomIncomingCall,
                        onHangUp: callManager.endConnectedCall,
                        onIgnore: callManager.ignoreCustomIncomingCall,
                        onMutedChanged: callManager.setCallMuted,
                        onSpeakerChanged: { _ = callManager.setSpeakerEnabled($0) }
                    )
                }
            }
            .onAppear {
                if callManager.activeCallStyle == .wechatVideo,
                   callManager.isVideoCameraEnabled {
                    cameraController.start()
                }
            }
            .onDisappear { cameraController.stop() }
        }
    }

    private var homeDashboard: some View {
        List {
            Section("来电人") {
                NavigationLink {
                    contactEditor
                } label: {
                    HStack(spacing: 14) {
                        CallerAvatar(name: callerName, size: 46, avatarData: callerAvatarData)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(callerName.isEmpty ? "未设置" : callerName)
                                .font(.body)
                                .foregroundStyle(.primary)
                            Text(callerNumber)
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if !templates.isEmpty {
                Section("快速模板") {
                    ForEach(Array(templates.prefix(3))) { template in
                        Button {
                            applyTemplate(template)
                        } label: {
                            HStack(spacing: 12) {
                                CallerAvatar(
                                    name: template.callerName,
                                    size: 38,
                                    avatarData: template.callerAvatarData
                                )
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(template.callerName)
                                        .foregroundStyle(.primary)
                                    Text("\(template.style.title) · \(delayDescription(template.delay))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "arrow.down.circle")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .swipeActions {
                            Button("删除", role: .destructive) {
                                deleteTemplate(template)
                            }
                        }
                    }
                }
            }

            Section("来电方式") {
                Picker("来电方式", selection: selectedStyle) {
                    ForEach(IncomingCallStyle.allCases) { style in
                        Text(homeStyleTitle(style)).tag(style)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            Section("来电时间") {
                Picker("来电时间", selection: $selectedDelay) {
                    ForEach(delayOptions, id: \.0) { seconds, label in
                        Text(label).tag(seconds)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                Button(action: showCustomDelayEditor) {
                    HStack {
                        Text("自定义")
                        Spacer()
                        if delayOptions.allSatisfy({ $0.0 != selectedDelay }) {
                            Text(delayDescription(selectedDelay))
                                .foregroundStyle(.secondary)
                        }
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .foregroundStyle(.primary)
            }

            Section {
                Button(action: scheduleSelectedCall) {
                    Label("安排来电", systemImage: "phone.fill")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                    }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.green)
                .disabled(nameError != nil || numberError != nil || callManager.activeCallUUID != nil)
            } footer: {
                Text("\(delayDescription(selectedDelay))后来电")
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
            }

            if let error = nameError ?? numberError {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("CallMe")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                NavigationLink {
                    settingsHome
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("设置")
            }
        }
    }

    private var settingsHome: some View {
        List {
            Section {
                NavigationLink {
                    templatesView
                } label: {
                    Label("来电模板", systemImage: "person.crop.rectangle.stack")
                }
                NavigationLink {
                    soundSettings
                } label: {
                    Label("声音与接听", systemImage: "speaker.wave.2")
                }
            }

            Section("开发") {
                NavigationLink {
                    diagnosticsView
                } label: {
                    Label("状态与诊断", systemImage: "wrench.and.screwdriver")
                }
            }
        }
        .navigationTitle("设置")
    }

    private var templatesView: some View {
        List {
            Section {
                Button {
                    saveCurrentTemplate()
                } label: {
                    Label("保存当前配置", systemImage: "plus.circle.fill")
                }
                .disabled(nameError != nil || numberError != nil)
                Text("模板保存在本机，包含联系人、头像、来电方式、时间和铃声选择。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("我的模板") {
                if templates.isEmpty {
                    Label("还没有模板", systemImage: "person.crop.rectangle.stack")
                        .foregroundStyle(.secondary)
                    Text("先在首页完成配置，然后保存为模板。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(templates) { template in
                        Button {
                            applyTemplate(template)
                        } label: {
                            HStack(spacing: 12) {
                                CallerAvatar(
                                    name: template.callerName,
                                    size: 42,
                                    avatarData: template.callerAvatarData
                                )
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(template.callerName).foregroundStyle(.primary)
                                    Text(template.callerNumber)
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                    Text("\(template.style.title) · \(delayDescription(template.delay))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("套用")
                                    .font(.caption.weight(.semibold))
                            }
                        }
                        .swipeActions {
                            Button("删除", role: .destructive) {
                                deleteTemplate(template)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("来电模板")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func homeStyleTitle(_ style: IncomingCallStyle) -> String {
        switch style {
        case .phone: return "电话"
        case .wechatVoice: return "微信语音"
        case .wechatVideo: return "微信视频"
        }
    }

    private func scheduleSelectedCall() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        callManager.scheduleIncomingCall(
            after: selectedDelay,
            callerName: callerName,
            callerNumber: callerNumber,
            callerAvatarData: callerAvatarData,
            style: selectedStyle.wrappedValue,
            ringtone: selectedRingtone.wrappedValue
        )
    }

    private func showCustomDelayEditor() {
        if delayOptions.allSatisfy({ $0.0 != selectedDelay }) {
            if selectedDelay >= 3_600,
               selectedDelay.truncatingRemainder(dividingBy: 3_600) == 0 {
                customDelayValue = String(Int(selectedDelay / 3_600))
                customDelayUnit = .hours
            } else if selectedDelay >= 60,
                      selectedDelay.truncatingRemainder(dividingBy: 60) == 0 {
                customDelayValue = String(Int(selectedDelay / 60))
                customDelayUnit = .minutes
            } else {
                customDelayValue = String(Int(selectedDelay))
                customDelayUnit = .seconds
            }
        } else {
            customDelayValue = ""
            customDelayUnit = .minutes
        }
        isShowingCustomDelay = true
    }

    private var contactEditor: some View {
        Form {
                Section {
                    HStack(spacing: 16) {
                        CallerAvatar(name: callerName, size: 72, avatarData: callerAvatarData)
                        PhotosPicker(selection: $selectedAvatarItem, matching: .images) {
                            Text(callerAvatarData.isEmpty ? "选择头像" : "更换头像")
                        }
                        if !callerAvatarData.isEmpty {
                            Button("移除", role: .destructive) {
                                callerAvatarData = Data()
                                selectedAvatarItem = nil
                            }
                        }
                    }
                }
                Section("来电人") {
                    TextField("姓名", text: $callerName)
                    TextField("显示号码", text: $callerNumber)
                        .keyboardType(.phonePad)
                    Button("生成随机手机号") { callerNumber = randomMobileNumber() }
                    if let nameError { Text(nameError).foregroundStyle(.red) }
                    if let numberError { Text(numberError).foregroundStyle(.red) }
                }
                Section("视频通话中的我") {
                    HStack(spacing: 16) {
                        CallerAvatar(name: "我", size: 58, avatarData: selfAvatarData)
                        PhotosPicker(selection: $selectedSelfAvatarItem, matching: .images) {
                            Text(selfAvatarData.isEmpty ? "选择我的头像" : "更换我的头像")
                        }
                        if !selfAvatarData.isEmpty {
                            Button("移除", role: .destructive) {
                                selfAvatarData = Data()
                                selectedSelfAvatarItem = nil
                            }
                        }
                    }
                    Text("关闭摄像头后，这张头像会显示在本机画面中。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section {
                    Text("号码只用于界面显示，不会拨出真实电话。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
        }
        .navigationTitle("来电人")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var soundSettings: some View {
        Form {
            Section("应用内音量") {
                LabeledContent(
                    "当前音量",
                    value: "\(Int((callManager.appPlaybackVolume * 100).rounded()))%"
                )
                Slider(
                    value: Binding(
                        get: { callManager.appPlaybackVolume },
                        set: { callManager.setAppPlaybackVolume($0) }
                    ),
                    in: 0...1,
                    step: 0.05
                )
                if callManager.appPlaybackVolume == 0 {
                    Label("当前为静音，调高后才能试听", systemImage: "speaker.slash.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Text(selectedStyle.wrappedValue == .phone
                     ? "只影响 App 内试听和接听后音频；系统来电音量由 iPhone 控制。"
                     : "影响微信来电提示音、试听和接听后音频，不改变其他 App 的音量。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("来电铃声") {
                let style = selectedStyle.wrappedValue
                LabeledContent("当前场景", value: homeStyleTitle(style))

                ForEach(ringtoneChoices(for: style)) { ringtone in
                    ringtoneChoiceRow(ringtone, style: style)
                }

                Text(callManager.ringtonePreviewMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if style != .phone {
                    Button {
                        wechatRingtoneImportStyle = style
                        isSelectingWechatRingtone = true
                    } label: {
                        Label("导入其他音效", systemImage: "square.and.arrow.down")
                    }

                    if callManager.hasCustomWechatRingtone(for: style) {
                        Button("删除已导入音效", role: .destructive) {
                            callManager.clearWechatRingtone(for: style)
                            selectedRingtone.wrappedValue = .wechatClassic
                        }
                    }
                }

                Text(style == .phone
                     ? "“系统默认”无法在 App 内读取或试听；其他内置铃声可点右侧播放按钮试听。实际来电仍受静音模式、专注模式和系统铃声音量控制。"
                     : "点名称选择铃声，点右侧播放按钮试听。微信语音和微信视频分别保存选择。锁屏时由 CallKit 显示，只能使用安装包内置铃声。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("接听后播放") {
                LabeledContent("音频", value: callManager.answerAudioName)
                Button("选择音频") { isSelectingAnswerAudio = true }
                Button {
                    callManager.toggleAnswerAudioPreview()
                } label: {
                    Label(
                        callManager.isPreviewingAnswerAudio ? "停止播放" : "播放接听音频",
                        systemImage: callManager.isPreviewingAnswerAudio
                            ? "stop.circle.fill"
                            : "play.circle"
                    )
                }
                .disabled(callManager.answerAudioName == "无（静音）")
                Button("清除音频", role: .destructive) { callManager.clearAnswerAudio() }
                    .disabled(callManager.answerAudioName == "无（静音）")
                Text(callManager.audioStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if selectedStyle.wrappedValue == .wechatVideo {
                Section("微信视频素材") {
                    LabeledContent("对方画面", value: callManager.wechatVideoName)
                    PhotosPicker(selection: $selectedVideoItem, matching: .videos) {
                        Text(callManager.wechatVideoName == "未选择" ? "选择视频" : "更换视频")
                    }
                    Button("清除视频", role: .destructive) { callManager.clearWechatVideo() }
                        .disabled(callManager.wechatVideoName == "未选择")
                }
            }
        }
        .navigationTitle("声音与接听")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func ringtoneChoices(for style: IncomingCallStyle) -> [IncomingRingtone] {
        var choices = style == .phone
            ? IncomingRingtone.phoneChoices
            : IncomingRingtone.chatChoices
        if style != .phone, callManager.hasCustomWechatRingtone(for: style) {
            choices.append(.custom)
        }
        return choices
    }

    private func ringtoneChoiceTitle(
        _ ringtone: IncomingRingtone,
        style: IncomingCallStyle
    ) -> String {
        ringtone == .custom
            ? callManager.wechatRingtoneName(for: style)
            : ringtone.title
    }

    private func ringtoneChoiceRow(
        _ ringtone: IncomingRingtone,
        style: IncomingCallStyle
    ) -> some View {
        let isSelected = selectedRingtone.wrappedValue == ringtone
        let isPlaying = callManager.previewingRingtone == ringtone
            && callManager.previewingRingtoneStyle == style

        return HStack(spacing: 12) {
            Button {
                selectedRingtone.wrappedValue = ringtone
                UISelectionFeedbackGenerator().selectionChanged()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ringtoneChoiceTitle(ringtone, style: style))
                            .foregroundStyle(.primary)
                        if ringtone == .system {
                            Text("由 iPhone 系统提供")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                callManager.toggleRingtonePreview(for: style, ringtone: ringtone)
            } label: {
                Image(systemName: isPlaying ? "stop.circle.fill" : "play.circle")
                    .font(.title2)
                    .foregroundStyle(
                        ringtone == .system
                            ? Color.secondary.opacity(0.45)
                            : Color.accentColor
                    )
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(isPlaying ? "停止试听" : "试听\(ringtoneChoiceTitle(ringtone, style: style))")
        }
    }

    private var diagnosticsView: some View {
        Form {
            Section("设备") {
                LabeledContent("设备", value: UIDevice.current.model)
                LabeledContent(
                    "系统",
                    value: "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)"
                )
                LabeledContent("App", value: diagnosticAppVersion)
                LabeledContent("前后台状态", value: diagnosticScenePhase)
                LabeledContent("摄像头权限", value: diagnosticCameraAuthorization)
            }
            Section("当前状态") {
                Text(callManager.status)
                LabeledContent("来电方式", value: selectedStyle.wrappedValue.title)
                LabeledContent("来电人", value: callerName)
                LabeledContent("延迟", value: delayDescription(selectedDelay))
                if let scheduledDate = callManager.scheduledDate {
                    LabeledContent(
                        "计划触发",
                        value: scheduledDate.formatted(date: .abbreviated, time: .standard)
                    )
                }
            }
            Section("诊断报告") {
                Button {
                    UIPasteboard.general.string = diagnosticReport
                    diagnosticCopied = true
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                } label: {
                    Label(
                        diagnosticCopied ? "诊断报告已复制" : "复制完整诊断报告",
                        systemImage: diagnosticCopied ? "checkmark.circle.fill" : "doc.on.doc"
                    )
                }
                Text("报告仅包含设备、权限、当前配置和最近活动，不包含头像、音频或视频文件。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("测试") {
                Button("立即预览当前来电") {
                    callManager.scheduleIncomingCall(
                        after: 0.4,
                        callerName: callerName,
                        callerNumber: callerNumber,
                        callerAvatarData: callerAvatarData,
                        style: selectedStyle.wrappedValue,
                        ringtone: selectedRingtone.wrappedValue
                    )
                }
                .disabled(callManager.activeCallUUID != nil)
            }
            Section("活动记录") {
                if callManager.eventLog.isEmpty {
                    Text("暂无记录").foregroundStyle(.secondary)
                } else {
                    Button {
                        UIPasteboard.general.string = callManager.eventLog.joined(separator: "\n")
                        eventLogCopied = true
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                    } label: {
                        Label(
                            eventLogCopied ? "活动记录已复制" : "复制全部活动记录",
                            systemImage: eventLogCopied ? "checkmark.circle.fill" : "list.clipboard"
                        )
                    }
                    Button("清空活动记录", role: .destructive) {
                        isConfirmingEventLogClear = true
                    }
                    ForEach(Array(callManager.eventLog.prefix(50).enumerated()), id: \.offset) { _, event in
                        Text(event).font(.caption.monospaced())
                    }
                }
            }
        }
        .confirmationDialog(
            "确定清空所有活动记录？",
            isPresented: $isConfirmingEventLogClear,
            titleVisibility: .visible
        ) {
            Button("清空", role: .destructive) {
                callManager.clearEventLog()
                eventLogCopied = false
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("清空后无法恢复。")
        }
        .navigationTitle("状态与诊断")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var customDelayEditor: some View {
        NavigationStack {
            Form {
                Section("自定义时间") {
                    TextField("数值", text: $customDelayValue)
                        .keyboardType(.numberPad)
                    Picker("单位", selection: $customDelayUnit) {
                        ForEach(CallDelayUnit.allCases) { unit in
                            Text(unit.title).tag(unit)
                        }
                    }
                    Text("可设置 1 秒到 24 小时。超过 1 分钟时，iPhone 锁屏或进入后台后的准时触发不受保证。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("什么时候响？")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { isShowingCustomDelay = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("使用") {
                        applyCustomDelay()
                        isShowingCustomDelay = false
                    }
                    .disabled(parsedCustomDelay == nil)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var legacyBody: some View {
        NavigationStack {
            List {
                Section("来电类型") {
                    Picker("类型", selection: selectedStyle) {
                        ForEach(IncomingCallStyle.allCases) { style in
                            Text(style.title).tag(style)
                        }
                    }
                    .pickerStyle(.segmented)

                    if selectedStyle.wrappedValue == .phone {
                        Label(
                            "手机来电使用 iPhone 系统来电界面。",
                            systemImage: "iphone"
                        )
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    } else {
                        Label(
                            "前台显示微信通话界面；锁屏或后台时使用 iPhone 系统来电界面。",
                            systemImage: "message.fill"
                        )
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }
                }

                Section("来电人") {
                    if selectedStyle.wrappedValue != .phone {
                        HStack(spacing: 14) {
                            CallerAvatar(name: callerName, size: 58, avatarData: callerAvatarData)
                            VStack(alignment: .leading, spacing: 6) {
                                PhotosPicker(selection: $selectedAvatarItem, matching: .images) {
                                    Text(callerAvatarData.isEmpty ? "选择微信联系人头像" : "更换微信联系人头像")
                                }
                                if !callerAvatarData.isEmpty {
                                    Button("移除头像", role: .destructive) {
                                        callerAvatarData = Data()
                                        selectedAvatarItem = nil
                                    }
                                    .font(.caption)
                                }
                            }
                        }
                    } else {
                        Text("系统手机来电页显示姓名和号码。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    TextField("姓名", text: $callerName)
                    HStack {
                        TextField("显示号码", text: $callerNumber)
                            .keyboardType(.phonePad)
                        if selectedStyle.wrappedValue == .phone {
                            Button("随机号码") {
                                callerNumber = randomMobileNumber()
                            }
                            .buttonStyle(.bordered)
                        }
                    }

                    if let nameError {
                        Label(nameError, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    if let numberError {
                        Label(numberError, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    Text("号码只用于来电显示，不会拨出真实电话。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("多久后来电") {
                    Picker("延迟", selection: $selectedDelay) {
                        ForEach(delayOptions, id: \.0) { seconds, label in
                            Text(label).tag(seconds)
                        }
                        if delayOptions.allSatisfy({ $0.0 != selectedDelay }) {
                            Text(delayDescription(selectedDelay)).tag(selectedDelay)
                        }
                    }

                    HStack {
                        TextField("自定义数值", text: $customDelayValue)
                            .keyboardType(.numberPad)
                        Picker("单位", selection: $customDelayUnit) {
                            ForEach(CallDelayUnit.allCases) { unit in
                                Text(unit.title).tag(unit)
                            }
                        }
                        .labelsHidden()
                        Button("使用") { applyCustomDelay() }
                            .disabled(parsedCustomDelay == nil)
                    }
                    Text("可设置 1 秒到 24 小时；锁屏或后台长时间触发不受保证。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("声音") {
                    LabeledContent(
                        selectedStyle.wrappedValue == .phone ? "接听后音频音量" : "CallMe 音量"
                    ) {
                        Text("\(Int((callManager.appPlaybackVolume * 100).rounded()))%")
                            .monospacedDigit()
                    }
                    Slider(
                        value: Binding(
                            get: { callManager.appPlaybackVolume },
                            set: { callManager.setAppPlaybackVolume($0) }
                        ),
                        in: 0...1,
                        step: 0.05
                    ) {
                        Text(selectedStyle.wrappedValue == .phone ? "接听后音频音量" : "CallMe 音量")
                    } minimumValueLabel: {
                        Image(systemName: "speaker.slash.fill")
                    } maximumValueLabel: {
                        Image(systemName: "speaker.wave.3.fill")
                    }
                    Text(
                        selectedStyle.wrappedValue == .phone
                            ? "此滑块只调节接听后音频。手机来电铃声由 iPhone 控制，不受此滑块影响。"
                            : "调节微信提示音、试听和接听后音频，不改变其他 App 的音量。锁屏后的系统铃声仍由 iPhone 控制。"
                    )
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if selectedStyle.wrappedValue == .phone {
                        Picker("手机系统来电铃声", selection: selectedRingtone) {
                            ForEach(IncomingRingtone.phoneChoices) { ringtone in
                                Text(ringtone.title).tag(ringtone)
                            }
                        }
                        Label("来电音量由 iPhone 的铃声与提醒音量、静音模式和专注模式控制。", systemImage: "speaker.wave.2.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("微信提示音", selection: selectedRingtone) {
                            ForEach(IncomingRingtone.chatChoices) { ringtone in
                                Text(ringtone.title).tag(ringtone)
                            }
                        }
                        Text("前台由 CallMe 播放并服从上方应用内音量；锁屏时由 CallKit 播放所选内置提示音。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    LabeledContent("接听后播放", value: callManager.answerAudioName)
                    HStack {
                        Button("选择音频") { isSelectingAnswerAudio = true }
                            .disabled(
                                callManager.scheduledDate != nil
                                    || callManager.activeCallUUID != nil
                            )
                        Button("试听") { callManager.previewAnswerAudio() }
                            .disabled(callManager.answerAudioName == "无（静音）")
                        Button("停止") { callManager.stopAudioPreview() }
                        Button("清除", role: .destructive) { callManager.clearAnswerAudio() }
                            .disabled(
                                callManager.answerAudioName == "无（静音）"
                                    || callManager.scheduledDate != nil
                                    || callManager.activeCallUUID != nil
                            )
                    }
                    Text(callManager.audioStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if selectedStyle.wrappedValue == .wechatVideo {
                    Section("微信视频通话") {
                        LabeledContent("本机实时画面", value: "来电时开启摄像头")
                        LabeledContent("对方画面", value: callManager.wechatVideoName)
                        HStack {
                            PhotosPicker(selection: $selectedVideoItem, matching: .videos) {
                                Text(callManager.wechatVideoName == "未选择" ? "选择对方视频" : "更换对方视频")
                            }
                            .disabled(
                                callManager.scheduledDate != nil
                                    || callManager.activeCallUUID != nil
                            )
                            Button("清除", role: .destructive) {
                                callManager.clearWechatVideo()
                            }
                            .disabled(
                                callManager.wechatVideoName == "未选择"
                                    || callManager.scheduledDate != nil
                                    || callManager.activeCallUUID != nil
                            )
                        }
                        Text(callManager.videoStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("视频来电页出现时即开启前置摄像头，接听后保持连续；所选视频作为对方画面静音循环。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Button {
                        callManager.scheduleIncomingCall(
                            after: selectedDelay,
                            callerName: callerName,
                            callerNumber: callerNumber,
                            callerAvatarData: callerAvatarData,
                            style: selectedStyle.wrappedValue,
                            ringtone: selectedRingtone.wrappedValue
                        )
                    } label: {
                        Text("\(delayDescription(selectedDelay))后来电")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(
                        nameError != nil ||
                        numberError != nil ||
                        callManager.scheduledDate != nil ||
                        callManager.activeCallUUID != nil
                    )

                    if callManager.scheduledDate != nil {
                        Button("取消已安排来电", role: .cancel) {
                            callManager.cancelScheduledCall()
                        }
                        .frame(maxWidth: .infinity)
                    }

                    if callManager.isConnected && !callManager.isShowingCustomConnected {
                        Button("结束当前系统通话", role: .destructive) {
                            callManager.endConnectedCall()
                        }
                        .frame(maxWidth: .infinity)
                    }
                }

                Section("当前状态") {
                    Text(callManager.status)
                    if let scheduledDate = callManager.scheduledDate {
                        LabeledContent("预计触发") {
                            Text(scheduledDate, style: .relative)
                                .monospacedDigit()
                        }
                        LabeledContent("准确时间") {
                            Text(scheduledDate, format: .dateTime.hour().minute().second())
                                .monospacedDigit()
                        }
                    }
                }

                Section("活动记录（最新在前）") {
                    if callManager.eventLog.isEmpty {
                        Text("暂无记录")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(callManager.eventLog.enumerated()), id: \.offset) { _, event in
                            Text(event)
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                        }
                    }
                }
            }
            .navigationTitle("CallMe")
            .onAppear {
                callManager.prepareProvider(
                    style: selectedStyle.wrappedValue,
                    ringtone: selectedRingtone.wrappedValue
                )
            }
            .onChange(of: selectedAvatarItem) { item in
                guard let item else { return }
                Task {
                    let data = try? await item.loadTransferable(type: Data.self)
                    let preparedData = data.flatMap(preparedAvatarData)
                    await MainActor.run {
                        if let preparedData { callerAvatarData = preparedData }
                        selectedAvatarItem = nil
                    }
                }
            }
            .onChange(of: selectedVideoItem) { item in
                guard let item else { return }
                Task {
                    do {
                        guard let pickedVideo = try await item.loadTransferable(
                            type: PickedVideo.self
                        ) else {
                            await MainActor.run {
                                callManager.recordWechatVideoSelectionFailure("无法读取所选视频")
                            }
                            return
                        }
                        await MainActor.run {
                            callManager.importWechatVideo(
                                from: pickedVideo.url,
                                displayName: pickedVideo.displayName
                            )
                        }
                        try? FileManager.default.removeItem(at: pickedVideo.url)
                    } catch {
                        await MainActor.run {
                            callManager.recordWechatVideoSelectionFailure(error.localizedDescription)
                        }
                    }
                }
            }
            .fileImporter(
                isPresented: $isSelectingAnswerAudio,
                allowedContentTypes: [.audio],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first {
                        callManager.importAnswerAudio(from: url)
                    }
                case .failure(let error):
                    callManager.recordLifecycle("音频选择失败：\(error.localizedDescription)")
                }
            }
            .fullScreenCover(
                isPresented: Binding(
                    get: {
                        callManager.isShowingCustomIncoming
                            || callManager.isShowingCustomConnected
                    },
                    set: { presented in
                        if !presented {
                            if callManager.isShowingCustomIncoming {
                                callManager.declineCustomIncomingCall()
                            } else if callManager.isShowingCustomConnected {
                                callManager.endConnectedCall()
                            }
                        }
                    }
                )
            ) {
                Group {
                    if callManager.activeCallStyle == .wechatVideo {
                        ReferenceWeChatVideoCallView(
                            callerName: callManager.activeCallerName,
                            avatarData: callManager.activeCallerAvatarData,
                            selfAvatarData: selfAvatarData,
                            videoURL: callManager.activeWechatVideoURL,
                            isConnected: callManager.isShowingCustomConnected,
                            connectedAt: callManager.connectedAt,
                            isMuted: callManager.isMicrophoneMuted,
                            isSpeakerEnabled: callManager.isSpeakerEnabled,
                            isCameraEnabled: callManager.isVideoCameraEnabled,
                            isSelfViewPrimary: callManager.isSelfViewPrimary,
                            cameraController: cameraController,
                            onAnswer: callManager.answerCustomIncomingCall,
                            onDecline: callManager.declineCustomIncomingCall,
                            onHangUp: callManager.endConnectedCall,
                            onIgnore: callManager.ignoreCustomIncomingCall,
                            onMutedChanged: callManager.setCallMuted,
                            onSpeakerChanged: { _ = callManager.setSpeakerEnabled($0) },
                            onCameraChanged: callManager.setVideoCameraEnabled,
                            onSelfViewPrimaryChanged: callManager.setSelfViewPrimary
                        )
                    } else {
                        ReferenceWeChatVoiceCallView(
                            callerName: callManager.activeCallerName,
                            avatarData: callManager.activeCallerAvatarData,
                            isConnected: callManager.isShowingCustomConnected,
                            connectedAt: callManager.connectedAt,
                            isMuted: callManager.isMicrophoneMuted,
                            isSpeakerEnabled: callManager.isSpeakerEnabled,
                            onAnswer: callManager.answerCustomIncomingCall,
                            onDecline: callManager.declineCustomIncomingCall,
                            onHangUp: callManager.endConnectedCall,
                            onIgnore: callManager.ignoreCustomIncomingCall,
                            onMutedChanged: callManager.setCallMuted,
                            onSpeakerChanged: { _ = callManager.setSpeakerEnabled($0) }
                        )
                    }
                }
                .onAppear {
                    if callManager.activeCallStyle == .wechatVideo,
                       callManager.isVideoCameraEnabled {
                        cameraController.start()
                    }
                }
                .onDisappear {
                    cameraController.stop()
                }
                .interactiveDismissDisabled()
            }
            .onChange(of: scenePhase) { phase in
                guard callManager.activeCallStyle == .wechatVideo,
                      callManager.isShowingCustomIncoming || callManager.isShowingCustomConnected else {
                    return
                }
                if phase == .active, callManager.isVideoCameraEnabled {
                    cameraController.start()
                } else {
                    cameraController.stop()
                }
            }
        }
    }

    private var parsedCustomDelay: TimeInterval? {
        CallExperimentRules.customDelay(customDelayValue, unit: customDelayUnit)
    }

    private var diagnosticAppVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        switch (version, build) {
        case let (.some(version), .some(build)): return "\(version) (\(build))"
        case let (.some(version), nil): return version
        default: return "开发版"
        }
    }

    private var diagnosticScenePhase: String {
        switch scenePhase {
        case .active: return "前台"
        case .inactive: return "非活跃"
        case .background: return "后台"
        @unknown default: return "未知"
        }
    }

    private var diagnosticCameraAuthorization: String {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return "已允许"
        case .denied: return "已拒绝"
        case .restricted: return "受限制"
        case .notDetermined: return "未询问"
        @unknown default: return "未知"
        }
    }

    private var diagnosticReport: String {
        let scheduled = callManager.scheduledDate?.formatted(.iso8601) ?? "无"
        let events = callManager.eventLog.prefix(100).joined(separator: "\n")
        return """
        CallMe iPhone 诊断报告
        生成时间：\(Date().formatted(.iso8601))
        设备：\(UIDevice.current.model)
        系统：\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)
        App：\(diagnosticAppVersion)
        前后台状态：\(diagnosticScenePhase)
        摄像头权限：\(diagnosticCameraAuthorization)
        当前状态：\(callManager.status)
        来电方式：\(selectedStyle.wrappedValue.title)
        来电人：\(callerName)
        显示号码：\(callerNumber)
        延迟：\(delayDescription(selectedDelay))
        计划触发：\(scheduled)
        活跃系统通话：\(callManager.activeCallUUID == nil ? "否" : "是")
        接听音频：\(callManager.answerAudioName)
        微信语音提示音：\(callManager.wechatVoiceRingtoneName)
        微信视频提示音：\(callManager.wechatVideoRingtoneName)
        视频素材：\(callManager.wechatVideoName)
        应用内音量：\(Int((callManager.appPlaybackVolume * 100).rounded()))%

        最近活动：
        \(events.isEmpty ? "暂无记录" : events)
        """
    }

    private func applyCustomDelay() {
        guard let parsedCustomDelay else { return }
        selectedDelay = parsedCustomDelay
    }

    private func saveCurrentTemplate() {
        let matchingIndex = templates.firstIndex {
            $0.callerName == callerName &&
                $0.callerNumber == callerNumber &&
                $0.styleRawValue == selectedStyle.wrappedValue.rawValue
        }
        let template = CallTemplate(
            id: matchingIndex.map { templates[$0].id } ?? UUID(),
            callerName: callerName,
            callerNumber: callerNumber,
            callerAvatarData: callerAvatarData,
            styleRawValue: selectedStyle.wrappedValue.rawValue,
            delay: selectedDelay,
            ringtoneRawValue: selectedRingtone.wrappedValue.rawValue,
            updatedAt: Date()
        )
        if let matchingIndex {
            templates.remove(at: matchingIndex)
        }
        templates.insert(template, at: 0)
        templates = Array(templates.prefix(12))
        CallTemplateStore.save(templates)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private func applyTemplate(_ template: CallTemplate) {
        callerName = template.callerName
        callerNumber = template.callerNumber
        callerAvatarData = template.callerAvatarData
        storedCallStyle = template.style.rawValue
        selectedDelay = template.delay
        selectedRingtone.wrappedValue = template.ringtone
        callManager.prepareProvider(style: template.style, ringtone: template.ringtone)
        if let index = templates.firstIndex(where: { $0.id == template.id }) {
            var recentlyUsed = templates.remove(at: index)
            recentlyUsed.updatedAt = Date()
            templates.insert(recentlyUsed, at: 0)
            CallTemplateStore.save(templates)
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func deleteTemplate(_ template: CallTemplate) {
        templates.removeAll { $0.id == template.id }
        CallTemplateStore.save(templates)
    }

    private func delayDescription(_ seconds: TimeInterval) -> String {
        CallExperimentRules.delayDescription(seconds)
    }

    private func randomMobileNumber() -> String {
        let prefixes = [
            "130", "131", "132", "133", "135", "136", "137", "138", "139",
            "150", "151", "152", "153", "155", "156", "157", "158", "159",
            "166", "173", "175", "176", "177", "178", "180", "181", "182",
            "183", "185", "186", "187", "188", "189", "191", "193", "195",
            "196", "198", "199"
        ]
        let prefix = prefixes.randomElement() ?? "138"
        let suffix = String(format: "%08d", Int.random(in: 0...99_999_999))
        return prefix + suffix
    }

    private func preparedAvatarData(_ data: Data) -> Data? {
        guard let sourceImage = UIImage(data: data) else { return nil }
        let side = min(sourceImage.size.width, sourceImage.size.height)
        let cropRect = CGRect(
            x: (sourceImage.size.width - side) / 2,
            y: (sourceImage.size.height - side) / 2,
            width: side,
            height: side
        )
        guard let cgImage = sourceImage.cgImage?.cropping(to: cropRect) else {
            return sourceImage.jpegData(compressionQuality: 0.78)
        }
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 512, height: 512))
        let resizedImage = renderer.image { _ in
            UIImage(cgImage: cgImage).draw(in: CGRect(x: 0, y: 0, width: 512, height: 512))
        }
        return resizedImage.jpegData(compressionQuality: 0.78)
    }
}

private struct WaitingCallView: View {
    let scheduledDate: Date
    let callerName: String
    let style: IncomingCallStyle
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            TimelineView(.periodic(from: .now, by: 1)) { context in
                let remaining = max(0, Int(ceil(scheduledDate.timeIntervalSince(context.date))))
                Text(remainingText(remaining))
                    .font(.system(size: 64, weight: .regular, design: .rounded).monospacedDigit())
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.22), value: remaining)
            }

            Text("\(callerName) · \(style.title)")
                .font(.headline)

            Text("预计 \(scheduledDate.formatted(date: .omitted, time: .standard)) 来电")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()

            Label("现在可以锁屏", systemImage: "lock.fill")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button("取消安排", role: .cancel, action: onCancel)
                .buttonStyle(.bordered)
                .controlSize(.large)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(Color(uiColor: .systemBackground))
        .navigationTitle("已安排")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
    }

    private func remainingText(_ seconds: Int) -> String {
        String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

private struct SimulatedIncomingCallView: View {
    let callerName: String
    let avatarData: Data
    let style: IncomingCallStyle
    @ObservedObject var cameraController: CameraController
    let onAnswer: () -> Void
    let onDecline: () -> Void

    var body: some View {
        ZStack {
            incomingBackdrop

            VStack(spacing: 10) {
                HStack {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.90))
                        .frame(width: 40, height: 40)
                        .background(.black.opacity(0.20), in: Circle())
                    Spacer()
                }

                Spacer().frame(height: 34)

                CallerAvatar(name: callerName, size: 82, avatarData: avatarData)

                Text(callerName)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.24), radius: 6, y: 2)
                    .padding(.top, 6)

                Text(style == .wechatVideo ? "邀请你视频通话…" : "邀请你语音通话…")
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.74))
                    .shadow(color: .black.opacity(0.24), radius: 5, y: 1)

                Spacer()

                HStack(spacing: 78) {
                    WeChatRoundControl(
                        icon: "phone.down.fill",
                        title: "拒绝",
                        fill: Color(red: 1.0, green: 0.31, blue: 0.34),
                        action: onDecline
                    )
                    WeChatRoundControl(
                        icon: style == .wechatVideo ? "video.fill" : "phone.fill",
                        title: "接听",
                        fill: Color(red: 0.13, green: 0.77, blue: 0.37),
                        action: onAnswer
                    )
                }
            }
            .padding(.horizontal, 26)
            .padding(.top, 10)
            .padding(.bottom, 48)
        }
    }

    @ViewBuilder
    private var incomingBackdrop: some View {
        if style == .wechatVideo, cameraController.isAuthorized {
            CameraPreviewView(
                session: cameraController.session,
                isMirrored: cameraController.isUsingFrontCamera
            )
            .ignoresSafeArea()
            .overlay {
                LinearGradient(
                    colors: [.black.opacity(0.38), .black.opacity(0.05), .black.opacity(0.56)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        } else {
            WeChatCallBackdrop(
                name: callerName,
                avatarData: avatarData,
                video: style == .wechatVideo
            )
            if style == .wechatVideo {
                VStack {
                    Spacer()
                    Label(
                        cameraController.isDenied ? "摄像头权限未开启" : "正在准备摄像头",
                        systemImage: cameraController.isDenied ? "video.slash.fill" : "video.fill"
                    )
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.72))
                    .padding(.bottom, 170)
                }
            }
        }
    }
}

private struct WeChatVideoCallView: View {
    let callerName: String
    let avatarData: Data
    let videoURL: URL?
    let isConnected: Bool
    let connectedAt: Date?
    @ObservedObject var cameraController: CameraController
    let onAnswer: () -> Void
    let onDecline: () -> Void
    let onHangUp: () -> Void
    let onSpeakerChanged: (Bool) -> Void

    @State private var isSelfViewPrimary = false
    @State private var isMuted = false
    @State private var isCameraEnabled = true
    @State private var isSpeakerEnabled = true
    @State private var isBackgroundBlurred = false
    @State private var isShowingMoreControls = false

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black
                continuousMedia
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()

                if isBackgroundBlurred && isConnected {
                    Color.black.opacity(0.20)
                        .allowsHitTesting(false)
                }

                LinearGradient(
                    colors: [.black.opacity(0.43), .clear, .black.opacity(0.64)],
                    startPoint: .top,
                    endPoint: .bottom
                )

                if isConnected {
                    connectedOverlay
                        .transition(.opacity)
                } else {
                    incomingOverlay
                        .transition(.opacity)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .background(Color.black)
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.20), value: isConnected)
        .onChange(of: isConnected) { connected in
            guard connected else { return }
            isSpeakerEnabled = true
            onSpeakerChanged(true)
        }
    }

    private var continuousMedia: some View {
        VideoCallMediaView(
            session: cameraController.session,
            isMirrored: cameraController.isUsingFrontCamera,
            videoURL: videoURL,
            avatarData: avatarData,
            isConnected: isConnected,
            isSelfViewPrimary: isSelfViewPrimary,
            isCameraEnabled: isCameraEnabled
        )
    }

    private var incomingOverlay: some View {
        VStack(spacing: 10) {
            HStack {
                Image(systemName: "chevron.down")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(.black.opacity(0.30), in: Circle())
                Spacer()
                Button {
                    cameraController.flipCamera()
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath.camera.fill")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 42, height: 42)
                        .background(.black.opacity(0.30), in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(cameraController.isSwitchingCamera)
            }

            Spacer().frame(height: 20)

            CallerAvatar(name: callerName, size: 78, avatarData: avatarData)
            Text(callerName)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.45), radius: 7, y: 2)
                .padding(.top, 5)
            Text("邀请你视频通话…")
                .font(.system(size: 15))
                .foregroundStyle(.white.opacity(0.82))
                .shadow(color: .black.opacity(0.45), radius: 5, y: 1)

            Spacer()

            if !cameraController.isAuthorized {
                Label(
                    cameraController.isDenied ? "摄像头权限未开启" : "正在准备摄像头",
                    systemImage: cameraController.isDenied ? "video.slash.fill" : "video.fill"
                )
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.80))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.black.opacity(0.28), in: Capsule())
                .padding(.bottom, 20)
            }

            HStack(spacing: 76) {
                WeChatRoundControl(
                    icon: "phone.down.fill",
                    title: "拒绝",
                    fill: Color(red: 1.0, green: 0.28, blue: 0.31),
                    action: onDecline
                )
                WeChatRoundControl(
                    icon: "video.fill",
                    title: "接听",
                    fill: Color(red: 0.10, green: 0.76, blue: 0.35),
                    action: onAnswer
                )
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 56)
        .padding(.bottom, 48)
    }

    private var connectedOverlay: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(callerName)
                        .font(.system(size: 15, weight: .semibold))
                    if let connectedAt {
                        TimelineView(.periodic(from: connectedAt, by: 1)) { context in
                            Text(callDurationText(context.date.timeIntervalSince(connectedAt)))
                                .font(.system(size: 12).monospacedDigit())
                        }
                    }
                }
                .foregroundStyle(.white.opacity(0.94))
                .padding(.horizontal, 13)
                .padding(.vertical, 9)
                .background(.black.opacity(0.28), in: Capsule())

                Spacer()

                Button {
                    isSelfViewPrimary.toggle()
                } label: {
                    Rectangle()
                        .fill(.clear)
                        .frame(width: 106, height: 154)
                        .contentShape(RoundedRectangle(cornerRadius: 14))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(.white.opacity(0.34), lineWidth: 0.7)
                        }
                        .overlay(alignment: .bottomTrailing) {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(6)
                                .background(.black.opacity(0.46), in: Circle())
                                .padding(6)
                        }
                        .shadow(color: .black.opacity(0.36), radius: 10, y: 4)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("交换本机和对方画面")
            }
            .padding(.horizontal, 20)
            .padding(.top, 54)

            Spacer()

            if isShowingMoreControls {
                moreControls
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.bottom, 18)
            }

            HStack(spacing: 20) {
                WeChatRoundControl(
                    icon: "ellipsis",
                    title: "更多",
                    fill: isShowingMoreControls ? .white : .black.opacity(0.44),
                    foreground: isShowingMoreControls ? .black : .white
                ) {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
                        isShowingMoreControls.toggle()
                    }
                }
                WeChatRoundControl(
                    icon: "phone.down.fill",
                    title: "挂断",
                    fill: Color(red: 1.0, green: 0.28, blue: 0.31),
                    action: onHangUp
                )
                WeChatRoundControl(
                    icon: "arrow.triangle.2.circlepath.camera.fill",
                    title: cameraController.isSwitchingCamera ? "切换中" : "翻转",
                    fill: .black.opacity(0.44)
                ) { cameraController.flipCamera() }
            }
            .padding(.bottom, 42)
        }
    }

    private var moreControls: some View {
        HStack(spacing: 12) {
            videoOptionControl(
                icon: isMuted ? "mic.slash.fill" : "mic.fill",
                title: isMuted ? "取消静音" : "静音",
                selected: isMuted
            ) { isMuted.toggle() }
            videoOptionControl(
                icon: isCameraEnabled ? "video.fill" : "video.slash.fill",
                title: isCameraEnabled ? "关闭摄像头" : "打开摄像头",
                selected: !isCameraEnabled
            ) {
                isCameraEnabled.toggle()
                if isCameraEnabled {
                    cameraController.start()
                } else {
                    cameraController.stop()
                }
            }
            videoOptionControl(
                icon: "speaker.wave.3.fill",
                title: "扬声器",
                selected: isSpeakerEnabled
            ) {
                isSpeakerEnabled.toggle()
                onSpeakerChanged(isSpeakerEnabled)
            }
            videoOptionControl(
                icon: "drop.halffull",
                title: "弱化背景",
                selected: isBackgroundBlurred
            ) { isBackgroundBlurred.toggle() }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(.black.opacity(0.48), in: RoundedRectangle(cornerRadius: 24))
        .overlay {
            RoundedRectangle(cornerRadius: 24)
                .stroke(.white.opacity(0.10), lineWidth: 0.5)
        }
        .padding(.horizontal, 14)
    }

    private func videoOptionControl(
        icon: String,
        title: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(selected ? .black : .white)
                    .frame(width: 46, height: 46)
                    .background(selected ? .white : .white.opacity(0.14), in: Circle())
                Text(title)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.86))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

}

private struct PhoneConnectedCallView: View {
    let callerName: String
    let avatarData: Data
    let connectedAt: Date
    let onHangUp: () -> Void
    let onMutedChanged: (Bool) -> Void
    let onSpeakerChanged: (Bool) -> Bool
    let onDigit: (String) -> Void

    @State private var isMuted = false
    @State private var isSpeakerEnabled = false
    @State private var isShowingKeypad = false
    @State private var enteredDigits = ""

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                phoneBackdrop
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()

                if isShowingKeypad {
                    keypad(
                        topInset: proxy.safeAreaInsets.top,
                        bottomInset: proxy.safeAreaInsets.bottom
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    callControls(
                        topInset: proxy.safeAreaInsets.top,
                        bottomInset: proxy.safeAreaInsets.bottom
                    )
                    .transition(.opacity)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .background(Color.black)
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.20), value: isShowingKeypad)
    }

    private var phoneBackdrop: some View {
        ZStack {
            if let image = UIImage(data: avatarData), !avatarData.isEmpty {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .scaleEffect(1.7)
                    .blur(radius: 64)
                    .saturation(0.55)
            } else {
                LinearGradient(
                    colors: [
                        Color(red: 0.24, green: 0.27, blue: 0.30),
                        Color(red: 0.08, green: 0.09, blue: 0.10)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
            Color.black.opacity(0.44)
        }
    }

    private func callControls(topInset: CGFloat, bottomInset: CGFloat) -> some View {
        VStack(spacing: 0) {
            Spacer().frame(height: max(54, topInset + 22))

            CallerAvatar(name: callerName, size: 92, avatarData: avatarData)

            Text(callerName)
                .font(.system(size: 32, weight: .regular))
                .foregroundStyle(.white)
                .padding(.top, 18)

            TimelineView(.periodic(from: connectedAt, by: 1)) { context in
                Text(callDurationText(context.date.timeIntervalSince(connectedAt)))
                    .font(.system(size: 16).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.72))
            }
            .padding(.top, 7)

            Spacer()

            HStack(alignment: .top, spacing: 20) {
                PhoneCallControl(
                    icon: isMuted ? "mic.slash.fill" : "mic.fill",
                    title: "静音",
                    selected: isMuted
                ) {
                    isMuted.toggle()
                    onMutedChanged(isMuted)
                }
                PhoneCallControl(icon: "circle.grid.3x3.fill", title: "键盘") {
                    isShowingKeypad = true
                }
                PhoneCallControl(
                    icon: "speaker.wave.3.fill",
                    title: "免提",
                    selected: isSpeakerEnabled
                ) {
                    let proposed = !isSpeakerEnabled
                    if onSpeakerChanged(proposed) {
                        isSpeakerEnabled = proposed
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 28)

            Spacer()

            Button(action: onHangUp) {
                Image(systemName: "phone.down.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 74, height: 74)
                    .background(Color(red: 1.0, green: 0.22, blue: 0.22), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("挂断")
            .padding(.bottom, max(34, bottomInset + 24))
        }
    }

    private func keypad(topInset: CGFloat, bottomInset: CGFloat) -> some View {
        VStack(spacing: 0) {
            Spacer().frame(height: max(42, topInset + 16))

            Text(enteredDigits.isEmpty ? callerName : enteredDigits)
                .font(.system(size: enteredDigits.isEmpty ? 26 : 30, weight: .regular))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .padding(.horizontal, 30)

            Text(enteredDigits.isEmpty ? "通话中" : " ")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.62))
                .padding(.top, 5)

            Spacer()

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 18), count: 3),
                spacing: 14
            ) {
                ForEach(keypadItems, id: \.digit) { item in
                    Button {
                        enteredDigits.append(item.digit)
                        onDigit(item.digit)
                    } label: {
                        VStack(spacing: 0) {
                            Text(item.digit)
                                .font(.system(size: 31, weight: .regular))
                            Text(item.letters)
                                .font(.system(size: 9, weight: .semibold))
                                .tracking(1.4)
                                .frame(height: 12)
                        }
                        .foregroundStyle(.white)
                        .frame(width: 76, height: 76)
                        .background(.white.opacity(0.17), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(item.digit)
                }
            }
            .padding(.horizontal, 52)

            Spacer()

            HStack(spacing: 38) {
                Button {
                    isShowingKeypad = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 64, height: 64)
                        .background(.white.opacity(0.16), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("关闭键盘")

                Button(action: onHangUp) {
                    Image(systemName: "phone.down.fill")
                        .font(.system(size: 25, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 64, height: 64)
                        .background(Color(red: 1.0, green: 0.22, blue: 0.22), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("挂断")

                Button {
                    if !enteredDigits.isEmpty { enteredDigits.removeLast() }
                } label: {
                    Image(systemName: "delete.left.fill")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 64, height: 64)
                        .background(.white.opacity(enteredDigits.isEmpty ? 0.06 : 0.16), in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(enteredDigits.isEmpty)
                .accessibilityLabel("删除数字")
            }
            .padding(.bottom, max(26, bottomInset + 16))
        }
    }

    private var keypadItems: [(digit: String, letters: String)] {
        [
            ("1", ""), ("2", "ABC"), ("3", "DEF"),
            ("4", "GHI"), ("5", "JKL"), ("6", "MNO"),
            ("7", "PQRS"), ("8", "TUV"), ("9", "WXYZ"),
            ("*", ""), ("0", "+"), ("#", "")
        ]
    }
}

private struct PhoneCallControl: View {
    let icon: String
    let title: String
    var selected = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(selected ? .black : .white)
                    .frame(width: 68, height: 68)
                    .background(selected ? .white : .white.opacity(0.17), in: Circle())
                Text(title)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.88))
            }
            .frame(width: 86)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

private struct WeChatConnectedCallView: View {
    let callerName: String
    let avatarData: Data
    let style: IncomingCallStyle
    let videoURL: URL?
    let connectedAt: Date
    @ObservedObject var cameraController: CameraController
    let onHangUp: () -> Void
    let onSpeakerChanged: (Bool) -> Void

    @State private var isMuted = false
    @State private var speakerEnabled = false
    @State private var backgroundBlurEnabled = true
    @State private var isShowingMoreControls = false

    var body: some View {
        Group {
            if style == .wechatVideo {
                videoCallBody
            } else {
                voiceCallBody
            }
        }
        .confirmationDialog("视频通话设置", isPresented: $isShowingMoreControls) {
            Button(backgroundBlurEnabled ? "关闭模糊背景" : "打开模糊背景") {
                backgroundBlurEnabled.toggle()
            }
            Button("取消", role: .cancel) {}
        }
    }

    private var voiceCallBody: some View {
        ZStack {
            WeChatCallBackdrop(name: callerName, avatarData: avatarData, video: false)
            VStack(spacing: 10) {
                callTimer
                    .padding(.top, 22)
                Spacer()
                CallerAvatar(name: callerName, size: 88, avatarData: avatarData)
                Text(callerName)
                    .font(.system(size: 21, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.top, 8)
                Text("语音通话")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.52))
                Spacer()
                HStack(spacing: 22) {
                    WeChatRoundControl(
                        icon: isMuted ? "mic.slash.fill" : "mic.fill",
                        title: isMuted ? "静音" : "麦克风",
                        fill: isMuted ? .white : .black.opacity(0.34),
                        foreground: isMuted ? .black : .white
                    ) { isMuted.toggle() }
                    WeChatRoundControl(
                        icon: "phone.down.fill",
                        title: "挂断",
                        fill: Color(red: 1.0, green: 0.31, blue: 0.34),
                        action: onHangUp
                    )
                    WeChatRoundControl(
                        icon: "speaker.wave.3.fill",
                        title: "扬声器",
                        fill: speakerEnabled ? .white : .black.opacity(0.34),
                        foreground: speakerEnabled ? .black : .white
                    ) {
                        speakerEnabled.toggle()
                        onSpeakerChanged(speakerEnabled)
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 46)
        }
    }

    private var videoCallBody: some View {
        ZStack {
            remoteVideoBackground
            LinearGradient(
                colors: [.black.opacity(0.32), .clear, .black.opacity(0.58)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                callTimer
                    .padding(.top, 18)

                HStack {
                    Spacer()
                    selfCameraPreview
                        .frame(width: 104, height: 152)
                        .background(.black.opacity(0.28))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(.white.opacity(0.20), lineWidth: 0.5)
                        }
                }
                .padding(.top, 14)

                Spacer()

                HStack(spacing: 22) {
                    WeChatRoundControl(
                        icon: "ellipsis",
                        title: "更多",
                        fill: .black.opacity(0.42)
                    ) { isShowingMoreControls = true }
                    WeChatRoundControl(
                        icon: "phone.down.fill",
                        title: "挂断",
                        fill: Color(red: 1.0, green: 0.31, blue: 0.34),
                        action: onHangUp
                    )
                    WeChatRoundControl(
                        icon: "arrow.triangle.2.circlepath.camera.fill",
                        title: "翻转",
                        fill: .black.opacity(0.42)
                    ) { cameraController.flipCamera() }
                }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 46)
        }
    }

    @ViewBuilder
    private var remoteVideoBackground: some View {
        if let videoURL {
            LoopingVideoView(url: videoURL)
                .ignoresSafeArea()
        } else {
            WeChatCallBackdrop(
                name: callerName,
                avatarData: avatarData,
                video: true,
                blurEnabled: backgroundBlurEnabled
            )
            VStack(spacing: 12) {
                CallerAvatar(name: callerName, size: 82, avatarData: avatarData)
                Text(callerName)
                    .font(.system(size: 21, weight: .medium))
                    .foregroundStyle(.white)
                Text("视频通话")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.56))
            }
        }
    }

    private var callTimer: some View {
        TimelineView(.periodic(from: connectedAt, by: 1)) { context in
            Text(callDurationText(context.date.timeIntervalSince(connectedAt)))
                .font(.system(size: 14).monospacedDigit())
                .foregroundStyle(.white.opacity(0.90))
                .padding(.horizontal, 13)
                .padding(.vertical, 7)
                .background(.black.opacity(0.22), in: Capsule())
        }
    }

    @ViewBuilder
    private var selfCameraPreview: some View {
        if cameraController.isAuthorized {
            CameraPreviewView(
                session: cameraController.session,
                isMirrored: cameraController.isUsingFrontCamera
            )
        } else {
            VStack(spacing: 7) {
                Image(systemName: cameraController.isDenied ? "video.slash.fill" : "video.fill")
                    .font(.title2)
                Text(cameraController.isDenied ? "未允许摄像头" : "正在准备摄像头")
                    .font(.system(size: 9))
                    .multilineTextAlignment(.center)
                if cameraController.isDenied {
                    Button("去设置") {
                        guard let url = URL(string: UIApplication.openSettingsURLString) else {
                            return
                        }
                        UIApplication.shared.open(url)
                    }
                    .font(.system(size: 9, weight: .medium))
                }
            }
            .foregroundStyle(.white.opacity(0.76))
            .padding(6)
        }
    }
}

private struct PickedVideo: Transferable {
    let url: URL
    let displayName: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { video in
            SentTransferredFile(video.url)
        } importing: { receivedFile in
            let sourceURL = receivedFile.file
            let fileExtension = sourceURL.pathExtension.isEmpty ? "mov" : sourceURL.pathExtension
            let destinationURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("callme-picked-\(UUID().uuidString)")
                .appendingPathExtension(fileExtension)
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            return PickedVideo(
                url: destinationURL,
                displayName: sourceURL.deletingPathExtension().lastPathComponent
            )
        }
    }
}

private struct LoopingVideoView: UIViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> LoopingPlayerView {
        let view = LoopingPlayerView()
        view.player = context.coordinator.player
        context.coordinator.play(url: url)
        return view
    }

    func updateUIView(_ uiView: LoopingPlayerView, context: Context) {
        guard context.coordinator.currentURL != url else { return }
        context.coordinator.play(url: url)
    }

    static func dismantleUIView(_ uiView: LoopingPlayerView, coordinator: Coordinator) {
        coordinator.stop()
        uiView.player = nil
    }

    final class Coordinator {
        let player = AVQueuePlayer()
        var looper: AVPlayerLooper?
        var currentURL: URL?

        init() {
            player.isMuted = true
        }

        func play(url: URL) {
            stop()
            currentURL = url
            let item = AVPlayerItem(url: url)
            looper = AVPlayerLooper(player: player, templateItem: item)
            player.play()
        }

        func stop() {
            player.pause()
            looper = nil
            player.removeAllItems()
            currentURL = nil
        }
    }
}

private final class LoopingPlayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }

    private var playerLayer: AVPlayerLayer {
        layer as! AVPlayerLayer
    }

    var player: AVPlayer? {
        get { playerLayer.player }
        set {
            playerLayer.player = newValue
            playerLayer.videoGravity = .resizeAspectFill
        }
    }
}

private struct CallerAvatar: View {
    let name: String
    let size: CGFloat
    let avatarData: Data

    var body: some View {
        Group {
            if let image = UIImage(data: avatarData), !avatarData.isEmpty {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Text(String(name.prefix(1)))
                    .font(.system(size: size * 0.43, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(uiColor: .tertiarySystemFill))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.20))
    }
}

private struct WeChatCallBackdrop: View {
    let name: String
    let avatarData: Data
    let video: Bool
    var blurEnabled = true

    var body: some View {
        ZStack {
            if let image = UIImage(data: avatarData), !avatarData.isEmpty {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .scaleEffect(1.55)
                    .blur(radius: blurEnabled ? (video ? 36 : 54) : 8)
                    .saturation(0.72)
            } else {
                LinearGradient(
                    colors: video
                        ? [Color(red: 0.15, green: 0.17, blue: 0.19), .black]
                        : [Color(red: 0.22, green: 0.31, blue: 0.27), Color(red: 0.06, green: 0.08, blue: 0.07)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Text(String(name.prefix(1)))
                    .font(.system(size: 310, weight: .bold))
                    .foregroundStyle(.white.opacity(0.07))
                    .blur(radius: 10)
            }
            Color.black.opacity(video ? 0.50 : 0.44)
            LinearGradient(
                colors: [.black.opacity(0.12), .clear, .black.opacity(0.42)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }
}

private struct WeChatRoundControl: View {
    let icon: String
    let title: String
    let fill: Color
    var foreground: Color = .white
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: 25, weight: .medium))
                    .foregroundStyle(foreground)
                    .frame(width: 70, height: 70)
                    .background(fill, in: Circle())
                Text(title)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.82))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(width: 92)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

private func callDurationText(_ interval: TimeInterval) -> String {
    let totalSeconds = max(0, Int(interval))
    return String(format: "%02d:%02d", totalSeconds / 60, totalSeconds % 60)
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(CallManager())
    }
}
