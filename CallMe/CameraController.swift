import AVFoundation
import Combine
import SwiftUI
import UIKit

final class CameraController: ObservableObject {
    @Published private(set) var authorizationStatus = AVCaptureDevice.authorizationStatus(
        for: .video
    )
    @Published private(set) var isRunning = false
    @Published private(set) var isUsingFrontCamera = true
    @Published private(set) var isSwitchingCamera = false
    @Published private(set) var errorMessage: String?

    let session = AVCaptureSession()

    private let sessionQueue = DispatchQueue(label: "local.callme.camera-session")
    private var currentInput: AVCaptureDeviceInput?
    private var isConfigured = false

    var isAuthorized: Bool { authorizationStatus == .authorized }
    var isDenied: Bool { authorizationStatus == .denied || authorizationStatus == .restricted }

    func start() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        updateAuthorizationStatus(status)

        switch status {
        case .authorized:
            configureAndStart(position: isUsingFrontCamera ? .front : .back)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard let self else { return }
                let newStatus = AVCaptureDevice.authorizationStatus(for: .video)
                self.updateAuthorizationStatus(newStatus)
                if granted {
                    self.configureAndStart(position: .front)
                } else {
                    self.publishError("未获得摄像头权限")
                }
            }
        case .denied, .restricted:
            publishError("摄像头权限已关闭，请到系统设置中允许 CallMe 使用摄像头")
        @unknown default:
            publishError("无法确认摄像头权限状态")
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
            DispatchQueue.main.async {
                self.isRunning = false
            }
        }
    }

    func flipCamera() {
        guard !isSwitchingCamera else { return }
        guard isAuthorized else {
            start()
            return
        }
        isSwitchingCamera = true
        let targetPosition: AVCaptureDevice.Position = isUsingFrontCamera ? .back : .front
        sessionQueue.async { [weak self] in
            self?.replaceInput(position: targetPosition)
        }
    }

    private func configureAndStart(position: AVCaptureDevice.Position) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if !self.isConfigured {
                self.session.beginConfiguration()
                self.session.sessionPreset = .high
                let configured = self.addInput(position: position)
                self.session.commitConfiguration()
                self.isConfigured = configured
                guard configured else { return }
            }

            guard !self.session.isRunning else { return }
            self.session.startRunning()
            DispatchQueue.main.async {
                self.isRunning = true
                self.errorMessage = nil
            }
        }
    }

    private func replaceInput(position: AVCaptureDevice.Position) {
        defer {
            DispatchQueue.main.async {
                self.isSwitchingCamera = false
            }
        }
        guard let newDevice = camera(position: position),
              let newInput = try? AVCaptureDeviceInput(device: newDevice) else {
            publishError("找不到可用的摄像头")
            return
        }

        session.beginConfiguration()
        let oldInput = currentInput
        if let oldInput {
            session.removeInput(oldInput)
        }

        if session.canAddInput(newInput) {
            session.addInput(newInput)
            currentInput = newInput
            session.commitConfiguration()
            DispatchQueue.main.async {
                self.isUsingFrontCamera = position == .front
                self.errorMessage = nil
            }
        } else {
            if let oldInput, session.canAddInput(oldInput) {
                session.addInput(oldInput)
            }
            session.commitConfiguration()
            publishError("无法切换摄像头")
        }
    }

    private func addInput(position: AVCaptureDevice.Position) -> Bool {
        guard let device = camera(position: position),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            publishError("找不到可用的摄像头")
            return false
        }
        session.addInput(input)
        currentInput = input
        DispatchQueue.main.async {
            self.isUsingFrontCamera = position == .front
        }
        return true
    }

    private func camera(position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera],
            mediaType: .video,
            position: position
        )
        return discovery.devices.first
    }

    private func updateAuthorizationStatus(_ status: AVAuthorizationStatus) {
        DispatchQueue.main.async {
            self.authorizationStatus = status
        }
    }

    private func publishError(_ message: String) {
        DispatchQueue.main.async {
            self.errorMessage = message
            self.isRunning = false
        }
    }
}

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    let isMirrored: Bool

    func makeUIView(context: Context) -> CameraPreviewContainerView {
        let view = CameraPreviewContainerView()
        view.previewLayer.session = session
        view.updateMirroring(isMirrored)
        return view
    }

    func updateUIView(_ uiView: CameraPreviewContainerView, context: Context) {
        uiView.previewLayer.session = session
        uiView.updateMirroring(isMirrored)
    }
}

final class CameraPreviewContainerView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        previewLayer.videoGravity = .resizeAspectFill
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        previewLayer.videoGravity = .resizeAspectFill
    }

    func updateMirroring(_ mirrored: Bool) {
        guard let connection = previewLayer.connection else { return }
        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = mirrored
        }
    }
}
