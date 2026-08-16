import AVFoundation
import SwiftUI
import UIKit

// MARK: - Phone

struct ReferencePhoneConnectedCallView: View {
    let callerName: String
    let avatarData: Data
    let connectedAt: Date
    let onHangUp: () -> Void
    let onMutedChanged: (Bool) -> Void
    let onSpeakerChanged: (Bool) -> Bool
    let onDigit: (String) -> Void

    @State private var isMuted = false
    @State private var isSpeakerEnabled = false
    @State private var page: PhonePage = .controls

    private enum PhonePage { case controls, keypad, more }

    // UIKit's full-screen presenter can still hand a conditional SwiftUI root its ideal width
    // during the first render. Use the physical screen canvas for this phone-only portrait UI so
    // the controls never collapse to the middle column on a real device.
    private var callCanvasSize: CGSize {
        UIScreen.main.bounds.size
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                ReferencePhoneBackdrop()

                switch page {
                case .controls:
                    controlsPage(proxy)
                case .keypad:
                    keypadPage(proxy)
                case .more:
                    morePage(proxy)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .background(Color.black)
        .ignoresSafeArea()
        .frame(width: callCanvasSize.width, height: callCanvasSize.height)
        .layoutPriority(1)
        .animation(.easeInOut(duration: 0.18), value: page)
    }

    private func controlsPage(_ proxy: GeometryProxy) -> some View {
        VStack(spacing: 0) {
            phoneHeader(topInset: proxy.safeAreaInsets.top)
            Spacer()

            VStack(spacing: 26) {
                HStack(spacing: 12) {
                    PhoneReferenceControl(icon: "speaker.wave.3.fill", title: "音频", selected: isSpeakerEnabled) {
                        let proposed = !isSpeakerEnabled
                        if onSpeakerChanged(proposed) { isSpeakerEnabled = proposed }
                    }
                    .frame(maxWidth: .infinity)
                    PhoneReferenceControl(
                        icon: "video.badge.questionmark",
                        title: "FaceTime 通话"
                    ) { }
                    .frame(maxWidth: .infinity)
                    PhoneReferenceControl(icon: "mic.slash.fill", title: "静音", selected: isMuted) {
                        isMuted.toggle()
                        onMutedChanged(isMuted)
                    }
                    .frame(maxWidth: .infinity)
                }

                HStack(spacing: 12) {
                    PhoneReferenceControl(icon: "ellipsis", title: "更多") { page = .more }
                        .frame(maxWidth: .infinity)
                    PhoneReferenceControl(icon: "phone.down.fill", title: "结束", color: .red) { onHangUp() }
                        .frame(maxWidth: .infinity)
                    PhoneReferenceControl(icon: "circle.grid.3x3.fill", title: "拨号键盘") { page = .keypad }
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, max(74, proxy.safeAreaInsets.bottom + 52))
            .frame(width: callCanvasSize.width)
        }
        .frame(width: callCanvasSize.width, height: callCanvasSize.height)
    }

    private func morePage(_ proxy: GeometryProxy) -> some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                phoneHeader(topInset: proxy.safeAreaInsets.top)
                Spacer()
            }
            .frame(width: callCanvasSize.width, height: callCanvasSize.height)
            .contentShape(Rectangle())
            .onTapGesture { page = .controls }

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button {
                        page = .controls
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.82))
                            .frame(width: 34, height: 34)
                            .background(.white.opacity(0.10), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("关闭更多")
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 2)

                PhoneMoreRow(
                    icon: "person.crop.circle.badge.plus",
                    color: Color(red: 0.05, green: 0.67, blue: 0.96),
                    title: "添加他人"
                )
                PhoneMoreRow(
                    icon: String(callerName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1)),
                    color: Color(red: 0.24, green: 0.22, blue: 0.35),
                    title: "联系人名片",
                    isTextIcon: true
                )
                Divider().overlay(.white.opacity(0.18)).padding(.horizontal, 26)
                PhoneMoreRow(
                    icon: "record.circle",
                    color: Color(red: 0.98, green: 0.19, blue: 0.17),
                    title: "通话录音",
                    subtitle: "录音和转写"
                )
                PhoneMoreRow(
                    icon: "phone.badge.waveform",
                    color: Color(red: 1.00, green: 0.53, blue: 0.13),
                    title: "通话保留助理",
                    subtitle: "需要接听时，获取通知"
                )
                PhoneMoreRow(
                    icon: "rectangle.on.rectangle.angled",
                    color: Color(red: 0.34, green: 0.31, blue: 0.84),
                    title: "屏幕共享",
                    subtitle: "共享并远程控制"
                )
                PhoneMoreRow(
                    icon: "person.2.wave.2.fill",
                    color: Color(red: 0.08, green: 0.79, blue: 0.22),
                    title: "同播共享",
                    subtitle: "观看、聆听并协作"
                )
            }
            .padding(.vertical, 14)
            .background(.black.opacity(0.58), in: RoundedRectangle(cornerRadius: 38, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 38, style: .continuous)
                    .stroke(.white.opacity(0.16), lineWidth: 0.6)
            }
            .padding(.horizontal, 10)
            .padding(.bottom, max(10, proxy.safeAreaInsets.bottom))
            .gesture(
                DragGesture(minimumDistance: 12)
                    .onEnded { value in
                        if value.translation.height > 34 { page = .controls }
                    }
            )
        }
        .frame(width: callCanvasSize.width, height: callCanvasSize.height)
    }

    private func keypadPage(_ proxy: GeometryProxy) -> some View {
        ZStack {
            VStack(spacing: 0) {
                phoneHeader(topInset: proxy.safeAreaInsets.top)
                Spacer()
            }
            .frame(width: callCanvasSize.width, height: callCanvasSize.height)

            ForEach(Array(keypadItems.enumerated()), id: \.offset) { index, item in
                Button {
                    onDigit(item.digit)
                } label: {
                    VStack(spacing: -1) {
                        Text(item.digit)
                            .font(.system(size: 36, weight: .light))
                        Text(item.letters)
                            .font(.system(size: 9, weight: .semibold))
                            .tracking(1.7)
                            .frame(height: 11)
                    }
                    .foregroundStyle(.white)
                    .frame(width: 78, height: 78)
                    .background(.white.opacity(0.12), in: Circle())
                    .overlay { Circle().stroke(.white.opacity(0.27), lineWidth: 0.8) }
                }
                .buttonStyle(.plain)
                .position(
                    x: proxy.size.width * (0.20 + CGFloat(index % 3) * 0.30),
                    y: proxy.size.height * (0.37 + CGFloat(index / 3) * 0.12)
                )
            }

            HStack(spacing: 28) {
                Button(action: onHangUp) {
                    Image(systemName: "phone.down.fill")
                        .font(.system(size: 27, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 78, height: 78)
                        .background(Color.red, in: Circle())
                }
                .buttonStyle(.plain)

                Button("隐藏拨号键盘") { page = .controls }
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white)
            }
            .position(
                x: proxy.size.width / 2 + 37,
                y: proxy.size.height * 0.87
            )
        }
        .frame(width: callCanvasSize.width, height: callCanvasSize.height)
    }

    private func phoneHeader(topInset: CGFloat) -> some View {
        VStack(spacing: 5) {
            HStack(spacing: 7) {
                Text("主号")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(.white, in: RoundedRectangle(cornerRadius: 3))
                TimelineView(.periodic(from: connectedAt, by: 1)) { context in
                    Text(referenceDuration(context.date.timeIntervalSince(connectedAt)))
                        .font(.system(size: 24, weight: .regular).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.64))
                }
            }
            Text(callerName)
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .padding(.top, max(104, topInset + 68))
        .padding(.horizontal, 28)
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

private struct PhoneReferenceControl: View {
    let icon: String
    let title: String
    var selected = false
    var color: Color? = nil
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 9) {
                PhoneReferenceGlyph(icon: icon)
                    .foregroundStyle(selected ? .black : .white)
                    .frame(width: 78, height: 78)
                    .background(color ?? (selected ? .white : .white.opacity(0.13)), in: Circle())
                    .overlay { Circle().stroke(.white.opacity(color == nil ? 0.28 : 0), lineWidth: 0.7) }
                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.52)
    }
}

private struct PhoneReferenceGlyph: View {
    let icon: String

    private var standardIconSize: CGFloat {
        switch icon {
        case "speaker.wave.3.fill": 27
        case "mic.slash.fill": 27
        case "ellipsis": 28
        case "phone.down.fill": 28
        case "circle.grid.3x3.fill": 29
        default: 27
        }
    }

    var body: some View {
        if icon == "video.badge.questionmark" {
            ZStack {
                Image(systemName: "video.fill")
                    .font(.system(size: 29, weight: .regular))
                Text("?")
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color(red: 0.43, green: 0.34, blue: 0.28))
                    .offset(x: -4, y: -0.5)
            }
        } else {
            Image(systemName: icon)
                .symbolRenderingMode(.monochrome)
                .font(.system(size: standardIconSize, weight: .regular))
        }
    }
}

private struct PhoneMoreRow: View {
    let icon: String
    let color: Color
    let title: String
    var subtitle: String? = nil
    var isTextIcon = false

    var body: some View {
        HStack(spacing: 14) {
            Group {
                if isTextIcon {
                    Text(icon).font(.system(size: 22, weight: .medium))
                } else {
                    Image(systemName: icon).font(.system(size: 20, weight: .semibold))
                }
            }
            .foregroundStyle(.white)
            .frame(width: 46, height: 46)
            .background(color, in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 17, weight: .medium)).foregroundStyle(.white)
                if let subtitle {
                    Text(subtitle).font(.system(size: 13)).foregroundStyle(.white.opacity(0.38))
                }
            }
            Spacer()
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 6)
    }
}

// MARK: - WeChat voice

struct ReferenceWeChatVoiceCallView: View {
    let callerName: String
    let avatarData: Data
    let isConnected: Bool
    let connectedAt: Date?
    let isMuted: Bool
    let isSpeakerEnabled: Bool
    let onAnswer: () -> Void
    let onDecline: () -> Void
    let onHangUp: () -> Void
    let onIgnore: () -> Void
    let onMutedChanged: (Bool) -> Void
    let onSpeakerChanged: (Bool) -> Void

    @State private var ignored = false

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                ReferenceWeChatBackdrop(name: callerName, avatarData: avatarData, video: false)
                if isConnected {
                    connected(proxy)
                } else {
                    incoming(proxy)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .background(Color(red: 0.14, green: 0.14, blue: 0.14))
        .ignoresSafeArea()
    }

    private func incoming(_ proxy: GeometryProxy) -> some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    ignored = true
                    onIgnore()
                } label: {
                    Label(ignored ? "已忽略" : "忽略", systemImage: "bell.slash.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.86))
                        .padding(.horizontal, 14)
                        .frame(height: 42)
                        .background(.white.opacity(0.10), in: Capsule())
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(.top, max(52, proxy.safeAreaInsets.top + 10))
            .padding(.horizontal, 24)

            Spacer()

            ReferenceAvatar(name: callerName, avatarData: avatarData, size: 112)
            Text(callerName)
                .font(.system(size: 25, weight: .medium))
                .foregroundStyle(.white)
                .padding(.top, 18)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.65)
                .padding(.horizontal, 28)
            Text("邀请你语音通话…")
                .font(.system(size: 16))
                .foregroundStyle(.white.opacity(0.43))
                .padding(.top, 118)

            Spacer()

            HStack(spacing: 94) {
                WeChatReferenceControl(icon: "phone.down.fill", title: "拒绝", fill: .red, size: 76, action: onDecline)
                WeChatReferenceControl(icon: "phone.fill", title: "接听", fill: .green, size: 76, action: onAnswer)
            }
            .padding(.bottom, max(42, proxy.safeAreaInsets.bottom + 26))
        }
    }

    private func connected(_ proxy: GeometryProxy) -> some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "rectangle.on.rectangle")
                    .font(.system(size: 23, weight: .regular))
                Spacer()
                if let connectedAt {
                    TimelineView(.periodic(from: connectedAt, by: 1)) { context in
                        Text(referenceDuration(context.date.timeIntervalSince(connectedAt)))
                            .font(.system(size: 20, weight: .regular).monospacedDigit())
                    }
                }
                Spacer()
                Image(systemName: "plus")
                    .font(.system(size: 30, weight: .light))
            }
            .foregroundStyle(.white.opacity(0.92))
            .padding(.horizontal, 28)
            .padding(.top, max(64, proxy.safeAreaInsets.top + 18))

            Spacer()

            ReferenceAvatar(name: callerName, avatarData: avatarData, size: 112)
            Text(callerName)
                .font(.system(size: 25, weight: .medium))
                .foregroundStyle(.white)
                .padding(.top, 18)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.65)
                .padding(.horizontal, 28)

            Spacer()

            HStack(spacing: 28) {
                WeChatReferenceControl(
                    icon: isMuted ? "mic.slash.fill" : "mic.fill",
                    title: isMuted ? "麦克风已关" : "麦克风已开",
                    fill: isMuted ? .black.opacity(0.40) : .white,
                    foreground: isMuted ? .white : .black,
                    size: 76
                ) { onMutedChanged(!isMuted) }
                WeChatReferenceControl(icon: "phone.down.fill", title: "挂断", fill: .red, size: 76, action: onHangUp)
                WeChatReferenceControl(
                    icon: isSpeakerEnabled ? "speaker.wave.3.fill" : "speaker.slash.fill",
                    title: isSpeakerEnabled ? "扬声器已开" : "扬声器已关",
                    fill: isSpeakerEnabled ? .white : .black.opacity(0.40),
                    foreground: isSpeakerEnabled ? .black : .white,
                    size: 76
                ) {
                    onSpeakerChanged(!isSpeakerEnabled)
                }
            }
            .padding(.bottom, max(46, proxy.safeAreaInsets.bottom + 28))
        }
    }
}

// MARK: - WeChat video

struct ReferenceWeChatVideoCallView: View {
    let callerName: String
    let avatarData: Data
    let selfAvatarData: Data
    let videoURL: URL?
    let isConnected: Bool
    let connectedAt: Date?
    let isMuted: Bool
    let isSpeakerEnabled: Bool
    let isCameraEnabled: Bool
    let isSelfViewPrimary: Bool
    @ObservedObject var cameraController: CameraController
    let onAnswer: () -> Void
    let onDecline: () -> Void
    let onHangUp: () -> Void
    let onIgnore: () -> Void
    let onMutedChanged: (Bool) -> Void
    let onSpeakerChanged: (Bool) -> Void
    let onCameraChanged: (Bool) -> Void
    let onSelfViewPrimaryChanged: (Bool) -> Void

    @State private var blur = false
    @State private var showMore = false
    @State private var ignored = false

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if !isConnected && !isCameraEnabled {
                    ReferenceIncomingCameraOffBackdrop(
                        callerName: callerName,
                        callerAvatarData: avatarData
                    )
                } else {
                    VideoCallMediaView(
                        session: cameraController.session,
                        isMirrored: cameraController.isUsingFrontCamera,
                        videoURL: videoURL,
                        avatarData: avatarData,
                        selfAvatarData: selfAvatarData,
                        isConnected: isConnected,
                        isSelfViewPrimary: isSelfViewPrimary,
                        isCameraEnabled: isCameraEnabled
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .blur(radius: blur ? 13 : 0)
                    .ignoresSafeArea()
                }

                LinearGradient(
                    colors: [.black.opacity(0.28), .clear, .black.opacity(0.56)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                .allowsHitTesting(false)

                if isConnected {
                    connected(proxy)
                } else {
                    incoming(proxy)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .background(Color.black)
        .ignoresSafeArea()
    }

    private func incoming(_ proxy: GeometryProxy) -> some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    ignored = true
                    onIgnore()
                } label: {
                    Label(ignored ? "已忽略" : "忽略", systemImage: "bell.slash.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.92))
                        .padding(.horizontal, 14)
                        .frame(height: 42)
                        .background(.black.opacity(0.25), in: Capsule())
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, max(52, proxy.safeAreaInsets.top + 10))

            Spacer().frame(height: 72)

            ReferenceAvatar(name: callerName, avatarData: avatarData, size: 84)
            Text(callerName)
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.38), radius: 5, y: 1)
                .padding(.top, 14)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.65)
                .padding(.horizontal, 28)
            Text("•••")
                .font(.system(size: 21, weight: .bold))
                .foregroundStyle(.white.opacity(0.62))
                .padding(.top, 12)

            Spacer()

            HStack(spacing: 14) {
                WeChatReferenceControl(icon: isMuted ? "mic.slash.fill" : "mic.fill", title: isMuted ? "麦克风已关" : "麦克风已开", fill: isMuted ? .black.opacity(0.40) : .white, foreground: isMuted ? .white : .black, size: 62) { onMutedChanged(!isMuted) }
                WeChatReferenceControl(icon: isCameraEnabled ? "video.fill" : "video.slash.fill", title: isCameraEnabled ? "摄像头已开" : "摄像头已关", fill: isCameraEnabled ? .white : .black.opacity(0.40), foreground: isCameraEnabled ? .black : .white, size: 62) { toggleCamera() }
                WeChatReferenceControl(icon: "person.crop.square", title: blur ? "关闭模糊" : "模糊背景", fill: .black.opacity(0.40), size: 62) { blur.toggle() }
                    .disabled(!isCameraEnabled)
                    .opacity(isCameraEnabled ? 1 : 0.28)
                WeChatReferenceControl(icon: "arrow.triangle.2.circlepath.camera.fill", title: "翻转", fill: .black.opacity(0.40), size: 62) { cameraController.flipCamera() }
                    .disabled(!isCameraEnabled)
                    .opacity(isCameraEnabled ? 1 : 0.28)
            }

            HStack {
                WeChatReferenceControl(icon: "phone.down.fill", title: "拒绝", fill: .red, size: 68, action: onDecline)
                Spacer()
                WeChatReferenceControl(icon: "video.fill", title: "接听", fill: .green, size: 68, action: onAnswer)
            }
            .padding(.horizontal, 28)
            .padding(.top, 24)
            .padding(.bottom, max(28, proxy.safeAreaInsets.bottom + 16))
        }
    }

    private func connected(_ proxy: GeometryProxy) -> some View {
        ZStack {
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "rectangle.on.rectangle")
                        .frame(width: 44, height: 44)
                        .background(.black.opacity(0.42), in: Circle())
                    Spacer()
                    if let connectedAt {
                        TimelineView(.periodic(from: connectedAt, by: 1)) { context in
                            Text(referenceDuration(context.date.timeIntervalSince(connectedAt)))
                                .font(.system(size: 20).monospacedDigit())
                        }
                    }
                    Spacer()
                    HStack(spacing: 10) {
                        Image(systemName: "lock.open.fill")
                            .frame(width: 44, height: 44)
                            .background(.black.opacity(0.42), in: Circle())
                        Image(systemName: "person.badge.plus")
                            .frame(width: 44, height: 44)
                            .background(.black.opacity(0.42), in: Circle())
                    }
                }
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .padding(.top, max(50, proxy.safeAreaInsets.top + 6))

                Spacer()

                if isCameraEnabled {
                    cameraOnConnectedControls(proxy)
                } else {
                    cameraOffConnectedControls(proxy)
                }
            }

            Button { onSelfViewPrimaryChanged(!isSelfViewPrimary) } label: {
                Color.clear
                    .frame(width: 106, height: 154)
                    .contentShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .position(
                x: proxy.size.width - 73,
                y: max(116, proxy.safeAreaInsets.top + 54) + 77
            )
            .accessibilityLabel("切换本机和对方画面")

            if showMore {
                VStack(spacing: 0) {
                    Button { blur.toggle(); showMore = false } label: {
                        Label(blur ? "关闭模糊背景" : "打开模糊背景", systemImage: "person.crop.square")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 20)
                            .frame(height: 62)
                    }
                    Divider()
                }
                .font(.system(size: 17))
                .foregroundStyle(.black)
                .background(.white.opacity(0.94), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .frame(width: min(290, proxy.size.width - 74))
                .position(x: min(188, proxy.size.width / 2), y: proxy.size.height - max(250, proxy.safeAreaInsets.bottom + 232))
                .shadow(color: .black.opacity(0.25), radius: 18, y: 8)
            }
        }
    }

    private func toggleCamera() {
        let enabled = !isCameraEnabled
        onCameraChanged(enabled)
        if enabled { cameraController.start() } else { cameraController.stop() }
    }

    private func cameraOnConnectedControls(_ proxy: GeometryProxy) -> some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3),
            spacing: 22
        ) {
            WeChatReferenceControl(icon: isMuted ? "mic.slash.fill" : "mic.fill", title: isMuted ? "麦克风已关" : "麦克风已开", fill: isMuted ? .black.opacity(0.42) : .white, foreground: isMuted ? .white : .black, size: 68) { onMutedChanged(!isMuted) }
            WeChatReferenceControl(icon: isSpeakerEnabled ? "speaker.wave.3.fill" : "speaker.slash.fill", title: isSpeakerEnabled ? "扬声器已开" : "扬声器已关", fill: isSpeakerEnabled ? .white : .black.opacity(0.42), foreground: isSpeakerEnabled ? .black : .white, size: 68) { onSpeakerChanged(!isSpeakerEnabled) }
            WeChatReferenceControl(icon: "video.fill", title: "摄像头已开", fill: .white, foreground: .black, size: 68) { toggleCamera() }
            WeChatReferenceControl(icon: "ellipsis", title: "更多", fill: .black.opacity(0.42), size: 68) { showMore.toggle() }
            WeChatReferenceControl(icon: "phone.down.fill", title: "挂断", fill: .red, size: 68, action: onHangUp)
            WeChatReferenceControl(icon: "arrow.triangle.2.circlepath.camera.fill", title: "翻转摄像头", fill: .black.opacity(0.42), size: 68) { cameraController.flipCamera() }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, max(34, proxy.safeAreaInsets.bottom + 18))
    }

    private func cameraOffConnectedControls(_ proxy: GeometryProxy) -> some View {
        VStack(spacing: 24) {
            HStack(spacing: 30) {
                WeChatReferenceControl(icon: isMuted ? "mic.slash.fill" : "mic.fill", title: isMuted ? "麦克风已关" : "麦克风已开", fill: isMuted ? .black.opacity(0.42) : .white, foreground: isMuted ? .white : .black, size: 68) { onMutedChanged(!isMuted) }
                WeChatReferenceControl(icon: isSpeakerEnabled ? "speaker.wave.3.fill" : "speaker.slash.fill", title: isSpeakerEnabled ? "扬声器已开" : "扬声器已关", fill: isSpeakerEnabled ? .white : .black.opacity(0.42), foreground: isSpeakerEnabled ? .black : .white, size: 68) { onSpeakerChanged(!isSpeakerEnabled) }
                WeChatReferenceControl(icon: "video.slash.fill", title: "摄像头已关", fill: .black.opacity(0.42), size: 68) { toggleCamera() }
            }
            WeChatReferenceControl(icon: "phone.down.fill", title: "挂断", fill: .red, size: 68, action: onHangUp)
        }
        .padding(.bottom, max(28, proxy.safeAreaInsets.bottom + 14))
    }
}

private struct ReferenceCameraOffVideoScene: View {
    let callerName: String
    let callerAvatarData: Data
    let selfAvatarData: Data
    let isSelfViewPrimary: Bool
    let isLocalCameraEnabled: Bool
    let session: AVCaptureSession
    let isMirrored: Bool

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if isSelfViewPrimary {
                    localCameraOrAvatar
                    remoteCameraOff
                        .frame(width: 106, height: 154)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay { pipBorder }
                        .position(x: proxy.size.width - 73, y: max(131, proxy.safeAreaInsets.top + 82))
                } else {
                    remoteCameraOff
                    localCameraOrAvatar
                        .frame(width: 106, height: 154)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay { pipBorder }
                        .position(x: proxy.size.width - 73, y: max(131, proxy.safeAreaInsets.top + 82))
                }
            }
        }
        .ignoresSafeArea()
    }

    private var remoteCameraOff: some View {
        ZStack {
            blurredBackground(name: callerName, data: callerAvatarData)
            ReferenceAvatar(name: callerName, avatarData: callerAvatarData, size: 86)
        }
    }

    @ViewBuilder
    private var localCameraOrAvatar: some View {
        if isLocalCameraEnabled {
            ReferenceLocalCameraPreview(session: session, isMirrored: isMirrored)
        } else {
            ZStack {
                blurredBackground(name: "我", data: selfAvatarData)
                ReferenceAvatar(name: "我", avatarData: selfAvatarData, size: 64)
            }
        }
    }

    private var pipBorder: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .stroke(.white.opacity(0.22), lineWidth: 0.7)
    }

    @ViewBuilder
    private func blurredBackground(name: String, data: Data) -> some View {
        if let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .scaleEffect(1.28)
                .blur(radius: 34, opaque: true)
                .overlay(Color.black.opacity(0.54))
                .clipped()
        } else {
            LinearGradient(
                colors: [
                    Color(red: 0.19, green: 0.18, blue: 0.18),
                    Color(red: 0.10, green: 0.09, blue: 0.09),
                    .black
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .overlay {
                Text(String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1)))
                    .font(.system(size: 160, weight: .medium))
                    .foregroundStyle(.white.opacity(0.05))
                    .blur(radius: 12)
            }
        }
    }
}

private struct ReferenceIncomingCameraOffBackdrop: View {
    let callerName: String
    let callerAvatarData: Data

    var body: some View {
        ZStack {
            if let image = UIImage(data: callerAvatarData), !callerAvatarData.isEmpty {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .scaleEffect(1.32)
                    .blur(radius: 36, opaque: true)
                    .overlay(Color.black.opacity(0.56))
            } else {
                LinearGradient(
                    colors: [Color(white: 0.20), Color(white: 0.08), .black],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
        .ignoresSafeArea()
    }
}

private struct ReferenceLocalCameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    let isMirrored: Bool

    func makeUIView(context: Context) -> LocalCameraPreviewContainer {
        let view = LocalCameraPreviewContainer()
        view.update(session: session, isMirrored: isMirrored)
        return view
    }

    func updateUIView(_ view: LocalCameraPreviewContainer, context: Context) {
        view.update(session: session, isMirrored: isMirrored)
    }

    static func dismantleUIView(_ uiView: LocalCameraPreviewContainer, coordinator: Void) {
        uiView.detach()
    }
}

private final class LocalCameraPreviewContainer: UIView {
    private let previewLayer = AVCaptureVideoPreviewLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        previewLayer.videoGravity = .resizeAspectFill
        layer.addSublayer(previewLayer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer.frame = bounds
    }

    func update(session: AVCaptureSession, isMirrored: Bool) {
        if previewLayer.session !== session { previewLayer.session = session }
        guard let connection = previewLayer.connection,
              connection.isVideoMirroringSupported else { return }
        connection.automaticallyAdjustsVideoMirroring = false
        connection.isVideoMirrored = isMirrored
    }

    func detach() { previewLayer.session = nil }
}

// MARK: - Shared

private struct WeChatReferenceControl: View {
    let icon: String
    let title: String
    let fill: Color
    var foreground: Color = .white
    let size: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: size * 0.35, weight: .medium))
                    .foregroundStyle(foreground)
                    .frame(width: size, height: size)
                    .background(fill, in: Circle())
                Text(title)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct ReferenceAvatar: View {
    let name: String
    let avatarData: Data
    let size: CGFloat

    var body: some View {
        Group {
            if let image = UIImage(data: avatarData), !avatarData.isEmpty {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Text(String(name.prefix(1)))
                    .font(.system(size: size * 0.42, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(red: 0.28, green: 0.26, blue: 0.37))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.10, style: .continuous))
    }
}

private struct ReferenceWeChatBackdrop: View {
    let name: String
    let avatarData: Data
    let video: Bool

    var body: some View {
        ZStack {
            if let image = UIImage(data: avatarData), !avatarData.isEmpty {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .scaleEffect(1.7)
                    .blur(radius: video ? 30 : 58)
                    .saturation(0.52)
            } else {
                LinearGradient(
                    colors: [Color(red: 0.19, green: 0.19, blue: 0.18), Color(red: 0.10, green: 0.09, blue: 0.09)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Text(String(name.prefix(1)))
                    .font(.system(size: 300, weight: .bold))
                    .foregroundStyle(.white.opacity(0.05))
                    .blur(radius: 12)
            }
            Color.black.opacity(video ? 0.26 : 0.42)
        }
        .ignoresSafeArea()
    }
}

private struct ReferencePhoneBackdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(
                stops: [
                    .init(color: Color(red: 0.22, green: 0.22, blue: 0.19), location: 0),
                    .init(color: Color(red: 0.31, green: 0.20, blue: 0.15), location: 0.38),
                    .init(color: Color(red: 0.28, green: 0.27, blue: 0.23), location: 1)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            RadialGradient(
                colors: [Color(red: 0.47, green: 0.22, blue: 0.14).opacity(0.42), .clear],
                center: UnitPoint(x: 0.60, y: 0.34),
                startRadius: 18,
                endRadius: 330
            )
            Color.black.opacity(0.10)
        }
        .ignoresSafeArea()
    }
}

private func referenceDuration(_ interval: TimeInterval) -> String {
    let seconds = max(0, Int(interval))
    return String(format: "%02d:%02d", seconds / 60, seconds % 60)
}
