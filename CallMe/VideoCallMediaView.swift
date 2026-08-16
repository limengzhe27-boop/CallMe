import AVFoundation
import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

struct VideoCallMediaView: UIViewRepresentable {
    let session: AVCaptureSession
    let isMirrored: Bool
    let videoURL: URL?
    let avatarData: Data
    var selfAvatarData: Data = Data()
    let isConnected: Bool
    let isSelfViewPrimary: Bool
    let isCameraEnabled: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> VideoCallMediaContainerView {
        let view = VideoCallMediaContainerView()
        view.configure(session: session, player: context.coordinator.player)
        context.coordinator.play(url: videoURL)
        view.update(
            isMirrored: isMirrored,
            avatarData: avatarData,
            selfAvatarData: selfAvatarData,
            hasRemoteVideo: videoURL != nil,
            isConnected: isConnected,
            isSelfViewPrimary: isSelfViewPrimary,
            isCameraEnabled: isCameraEnabled,
            animated: false
        )
        return view
    }

    func updateUIView(_ view: VideoCallMediaContainerView, context: Context) {
        context.coordinator.play(url: videoURL)
        view.configure(session: session, player: context.coordinator.player)
        view.update(
            isMirrored: isMirrored,
            avatarData: avatarData,
            selfAvatarData: selfAvatarData,
            hasRemoteVideo: videoURL != nil,
            isConnected: isConnected,
            isSelfViewPrimary: isSelfViewPrimary,
            isCameraEnabled: isCameraEnabled,
            animated: false
        )
    }

    static func dismantleUIView(
        _ uiView: VideoCallMediaContainerView,
        coordinator: Coordinator
    ) {
        uiView.detachMedia()
        coordinator.stop()
    }

    final class Coordinator {
        let player = AVQueuePlayer()
        private var looper: AVPlayerLooper?
        private var currentURL: URL?

        init() {
            player.isMuted = true
            player.actionAtItemEnd = .none
        }

        func play(url: URL?) {
            guard currentURL != url else { return }
            stop()
            guard let url else { return }
            currentURL = url
            looper = AVPlayerLooper(
                player: player,
                templateItem: AVPlayerItem(url: url)
            )
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

final class VideoCallMediaContainerView: UIView {
    private let cameraContainer = CALayer()
    private let remoteContainer = CALayer()
    private let cameraPreviewLayer = AVCaptureVideoPreviewLayer()
    private let cameraFallbackLayer = CALayer()
    private let cameraFallbackShadeLayer = CALayer()
    private let cameraFallbackAvatarLayer = CALayer()
    private let remotePlayerLayer = AVPlayerLayer()
    private let remoteFallbackLayer = CALayer()
    private let remoteShadeLayer = CALayer()
    private let remoteFallbackAvatarLayer = CALayer()

    private var isConnected = false
    private var isSelfViewPrimary = false
    private var isCameraEnabled = true
    private var hasRemoteVideo = false
    private var previousLayoutState = ""
    private var renderedRemoteAvatarData = Data()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black

        cameraContainer.backgroundColor = UIColor(
            red: 0.06,
            green: 0.07,
            blue: 0.08,
            alpha: 1
        ).cgColor
        cameraContainer.addSublayer(cameraPreviewLayer)
        cameraContainer.addSublayer(cameraFallbackLayer)
        cameraContainer.addSublayer(cameraFallbackShadeLayer)
        cameraContainer.addSublayer(cameraFallbackAvatarLayer)
        cameraPreviewLayer.videoGravity = .resizeAspectFill
        cameraFallbackLayer.contentsGravity = .resizeAspectFill
        cameraFallbackShadeLayer.backgroundColor = UIColor.black.withAlphaComponent(0.46).cgColor
        cameraFallbackAvatarLayer.contentsGravity = .resizeAspectFill
        cameraFallbackAvatarLayer.masksToBounds = true

        remoteContainer.backgroundColor = UIColor(
            red: 0.08,
            green: 0.10,
            blue: 0.12,
            alpha: 1
        ).cgColor
        remoteContainer.addSublayer(remoteFallbackLayer)
        remoteContainer.addSublayer(remoteShadeLayer)
        remoteContainer.addSublayer(remotePlayerLayer)
        remoteContainer.addSublayer(remoteFallbackAvatarLayer)
        remoteFallbackLayer.contentsGravity = .resizeAspectFill
        remotePlayerLayer.videoGravity = .resizeAspectFill
        remoteShadeLayer.backgroundColor = UIColor.black.withAlphaComponent(0.54).cgColor
        remoteFallbackAvatarLayer.contentsGravity = .resizeAspectFill
        remoteFallbackAvatarLayer.masksToBounds = true

        layer.addSublayer(remoteContainer)
        layer.addSublayer(cameraContainer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(session: AVCaptureSession, player: AVPlayer) {
        if cameraPreviewLayer.session !== session {
            cameraPreviewLayer.session = session
        }
        if remotePlayerLayer.player !== player {
            remotePlayerLayer.player = player
        }
    }

    func update(
        isMirrored: Bool,
        avatarData: Data,
        selfAvatarData: Data,
        hasRemoteVideo: Bool,
        isConnected: Bool,
        isSelfViewPrimary: Bool,
        isCameraEnabled: Bool,
        animated: Bool
    ) {
        self.hasRemoteVideo = hasRemoteVideo
        self.isConnected = isConnected
        self.isSelfViewPrimary = isSelfViewPrimary
        self.isCameraEnabled = isCameraEnabled

        let remoteAvatar = UIImage(data: avatarData)
        if renderedRemoteAvatarData != avatarData {
            renderedRemoteAvatarData = avatarData
            remoteFallbackLayer.contents = Self.blurredBackground(from: remoteAvatar)?.cgImage
            remoteFallbackAvatarLayer.contents = remoteAvatar?.cgImage
        }
        cameraFallbackLayer.contents = UIImage(data: selfAvatarData)?.cgImage
        cameraFallbackAvatarLayer.contents = UIImage(data: selfAvatarData)?.cgImage
        remoteFallbackLayer.isHidden = hasRemoteVideo
        remoteShadeLayer.isHidden = hasRemoteVideo
        remoteFallbackAvatarLayer.isHidden = hasRemoteVideo || remoteAvatar == nil
        remotePlayerLayer.isHidden = !hasRemoteVideo
        cameraPreviewLayer.isHidden = !isCameraEnabled
        cameraFallbackLayer.isHidden = isCameraEnabled
        cameraFallbackShadeLayer.isHidden = isCameraEnabled
        cameraFallbackAvatarLayer.isHidden = isCameraEnabled || selfAvatarData.isEmpty
        updateMirroring(isMirrored)

        let state = "\(isConnected)-\(isSelfViewPrimary)-\(isCameraEnabled)"
        let shouldAnimate = animated && state != previousLayoutState && !previousLayoutState.isEmpty
        previousLayoutState = state
        applyLayout(animated: shouldAnimate)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        applyLayout(animated: false)
    }

    func detachMedia() {
        cameraPreviewLayer.session = nil
        remotePlayerLayer.player = nil
    }

    private func applyLayout(animated: Bool) {
        guard bounds.width > 0, bounds.height > 0 else { return }

        let fullFrame = bounds
        let pipSize = CGSize(width: 106, height: 154)
        let pipTop = max(116, safeAreaInsets.top + 54)
        let pipFrame = CGRect(
            x: bounds.maxX - pipSize.width - 20,
            y: pipTop,
            width: pipSize.width,
            height: pipSize.height
        )

        let remoteIsPrimary = isConnected && !isSelfViewPrimary
        let cameraFrame = remoteIsPrimary ? pipFrame : fullFrame
        let remoteFrame = isConnected && isSelfViewPrimary ? pipFrame : fullFrame

        CATransaction.begin()
        CATransaction.setDisableActions(!animated)
        CATransaction.setAnimationDuration(animated ? 0.20 : 0)
        CATransaction.setAnimationTimingFunction(
            CAMediaTimingFunction(name: .easeInEaseOut)
        )

        cameraContainer.frame = cameraFrame
        remoteContainer.frame = remoteFrame
        cameraContainer.cornerRadius = cameraFrame == fullFrame ? 0 : 14
        remoteContainer.cornerRadius = remoteFrame == fullFrame ? 0 : 14
        cameraContainer.masksToBounds = true
        remoteContainer.masksToBounds = true
        cameraContainer.borderWidth = cameraFrame == fullFrame ? 0 : 0.7
        remoteContainer.borderWidth = remoteFrame == fullFrame ? 0 : 0.7
        cameraContainer.borderColor = UIColor.white.withAlphaComponent(0.34).cgColor
        remoteContainer.borderColor = UIColor.white.withAlphaComponent(0.34).cgColor

        if isConnected {
            remoteContainer.isHidden = false
            cameraContainer.zPosition = isSelfViewPrimary ? 0 : 1
            remoteContainer.zPosition = isSelfViewPrimary ? 1 : 0
        } else {
            remoteContainer.isHidden = true
            cameraContainer.zPosition = 1
        }

        cameraPreviewLayer.frame = cameraContainer.bounds
        cameraFallbackLayer.frame = cameraContainer.bounds
        cameraFallbackShadeLayer.frame = cameraContainer.bounds
        let avatarSide = min(cameraContainer.bounds.width, cameraContainer.bounds.height) * 0.48
        cameraFallbackAvatarLayer.frame = CGRect(
            x: (cameraContainer.bounds.width - avatarSide) / 2,
            y: (cameraContainer.bounds.height - avatarSide) / 2,
            width: avatarSide,
            height: avatarSide
        )
        cameraFallbackAvatarLayer.cornerRadius = avatarSide * 0.10
        remoteFallbackLayer.frame = remoteContainer.bounds
        remoteShadeLayer.frame = remoteContainer.bounds
        remotePlayerLayer.frame = remoteContainer.bounds
        let remoteAvatarSide: CGFloat = remoteFrame == fullFrame ? 86 : 52
        let remoteAvatarCenterY = remoteFrame == fullFrame
            ? remoteContainer.bounds.height * 0.31
            : remoteContainer.bounds.midY
        remoteFallbackAvatarLayer.frame = CGRect(
            x: (remoteContainer.bounds.width - remoteAvatarSide) / 2,
            y: remoteAvatarCenterY - remoteAvatarSide / 2,
            width: remoteAvatarSide,
            height: remoteAvatarSide
        )
        remoteFallbackAvatarLayer.cornerRadius = remoteAvatarSide * 0.10
        CATransaction.commit()
    }

    private static func blurredBackground(from image: UIImage?) -> UIImage? {
        guard let image, let input = CIImage(image: image) else { return nil }
        let filter = CIFilter.gaussianBlur()
        filter.inputImage = input.clampedToExtent()
        filter.radius = 24
        guard let output = filter.outputImage else { return image }
        let context = CIContext(options: [.cacheIntermediates: true])
        guard let cgImage = context.createCGImage(output, from: input.extent) else { return image }
        return UIImage(cgImage: cgImage, scale: image.scale, orientation: image.imageOrientation)
    }

    private func updateMirroring(_ mirrored: Bool) {
        guard let connection = cameraPreviewLayer.connection,
              connection.isVideoMirroringSupported else {
            return
        }
        connection.automaticallyAdjustsVideoMirroring = false
        connection.isVideoMirrored = mirrored
    }
}
