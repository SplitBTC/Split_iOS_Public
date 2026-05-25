//
//  QRCodeScannerView.swift
//  Split
//
//  A reusable QR code scanner view using AVFoundation.
//  Emits the first decoded QR string via `onCodeScanned`.
//

import SwiftUI
import AVFoundation

struct QRCodeScannerView: UIViewRepresentable {
    let onCodeScanned: (String) -> Void
    let preferredZoomFactor: CGFloat

    init(
        preferredZoomFactor: CGFloat = 1,
        onCodeScanned: @escaping (String) -> Void
    ) {
        self.preferredZoomFactor = preferredZoomFactor
        self.onCodeScanned = onCodeScanned
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            preferredZoomFactor: preferredZoomFactor,
            onCodeScanned: onCodeScanned
        )
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black

        let coordinator = context.coordinator

        // Handle camera permission
        let authStatus = AVCaptureDevice.authorizationStatus(for: .video)
        switch authStatus {
        case .authorized:
            coordinator.configureSessionIfNeeded(in: view)

        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted {
                        coordinator.configureSessionIfNeeded(in: view)
                    } else {
                        coordinator.reportError("Camera access was denied.")
                    }
                }
            }

        case .denied, .restricted:
            coordinator.reportError("Camera access is restricted or denied. Enable it in Settings to scan QR codes.")

        @unknown default:
            coordinator.reportError("Unknown camera authorization status.")
        }

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        // Keep the preview layer sized correctly when layout changes
        context.coordinator.previewLayer?.frame = uiView.bounds
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.stopSession()
        coordinator.previewLayer?.removeFromSuperlayer()
        coordinator.previewLayer = nil
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        let onCodeScanned: (String) -> Void
        let preferredZoomFactor: CGFloat

        var previewLayer: AVCaptureVideoPreviewLayer?
        var didScanCode = false

        private static let sessionQueue = DispatchQueue(label: "split.qr-code-scanner.session", qos: .userInitiated)
        private static var sharedSession: AVCaptureSession?
        private static var sharedOutput: AVCaptureMetadataOutput?
        private static weak var sharedDevice: AVCaptureDevice?
        private static weak var activeCoordinator: Coordinator?
        private static var stopGeneration = 0

        init(
            preferredZoomFactor: CGFloat,
            onCodeScanned: @escaping (String) -> Void
        ) {
            self.preferredZoomFactor = preferredZoomFactor
            self.onCodeScanned = onCodeScanned
        }

        func metadataOutput(
            _ output: AVCaptureMetadataOutput,
            didOutput metadataObjects: [AVMetadataObject],
            from connection: AVCaptureConnection
        ) {
            guard !didScanCode,
                  let first = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
                  first.type == .qr,
                  let value = first.stringValue,
                  !value.isEmpty else {
                return
            }

            didScanCode = true
            stopSession()
            onCodeScanned(value)
        }

        func reportError(_ message: String) {
            // For now we just log; if you want, we can later
            // add a binding to surface camera errors into SwiftUI.
            print("QR Scanner error:", message)
        }

        func configureSessionIfNeeded(in view: UIView) {
            Self.sessionQueue.async { [weak self, weak view] in
                guard let self else { return }

                Self.stopGeneration += 1
                Self.activeCoordinator = self

                let session: AVCaptureSession

                if let existingSession = Self.sharedSession {
                    Self.sharedOutput?.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
                    if let device = Self.sharedDevice {
                        self.configureCameraDevice(device)
                    }
                    session = existingSession
                } else {
                    let newSession = AVCaptureSession()

                    if newSession.canSetSessionPreset(.hd1920x1080) {
                        newSession.sessionPreset = .hd1920x1080
                    } else if newSession.canSetSessionPreset(.high) {
                        newSession.sessionPreset = .high
                    }

                    guard let device = self.preferredCameraDevice() else {
                        self.reportError("No camera available on this device.")
                        return
                    }

                    self.configureCameraDevice(device)

                    guard let input = try? AVCaptureDeviceInput(device: device),
                          newSession.canAddInput(input) else {
                        self.reportError("Unable to access camera input.")
                        return
                    }

                    do {
                        newSession.beginConfiguration()
                        defer { newSession.commitConfiguration() }

                        newSession.addInput(input)

                        let output = AVCaptureMetadataOutput()
                        guard newSession.canAddOutput(output) else {
                            self.reportError("Unable to read camera output.")
                            return
                        }

                        newSession.addOutput(output)
                        output.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
                        output.metadataObjectTypes = [.qr]
                        Self.sharedOutput = output
                    }

                    Self.sharedDevice = device
                    Self.sharedSession = newSession
                    session = newSession
                }

                let previewLayer = AVCaptureVideoPreviewLayer(session: session)
                previewLayer.videoGravity = .resizeAspectFill

                DispatchQueue.main.async { [weak self, weak view] in
                    guard let self, let view else { return }
                    previewLayer.frame = view.bounds
                    view.layer.addSublayer(previewLayer)
                    self.previewLayer = previewLayer
                }

                if !session.isRunning {
                    session.startRunning()
                }
            }
        }

        private func preferredCameraDevice() -> AVCaptureDevice? {
            let discoverySession = AVCaptureDevice.DiscoverySession(
                deviceTypes: [
                    .builtInTripleCamera,
                    .builtInDualWideCamera,
                    .builtInDualCamera,
                    .builtInWideAngleCamera
                ],
                mediaType: .video,
                position: .back
            )

            return discoverySession.devices.first
                ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
                ?? AVCaptureDevice.default(for: .video)
        }

        private func configureCameraDevice(_ device: AVCaptureDevice) {
            do {
                try device.lockForConfiguration()
                defer { device.unlockForConfiguration() }

                if device.isFocusModeSupported(.continuousAutoFocus) {
                    device.focusMode = .continuousAutoFocus
                } else if device.isFocusModeSupported(.autoFocus) {
                    device.focusMode = .autoFocus
                }

                if device.isExposureModeSupported(.continuousAutoExposure) {
                    device.exposureMode = .continuousAutoExposure
                }

                if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                    device.whiteBalanceMode = .continuousAutoWhiteBalance
                }

                if device.isSmoothAutoFocusSupported {
                    device.isSmoothAutoFocusEnabled = true
                }

                if device.isSubjectAreaChangeMonitoringEnabled == false {
                    device.isSubjectAreaChangeMonitoringEnabled = true
                }

                let requestedZoom = max(preferredZoomFactor, 1)
                let cappedZoom = min(requestedZoom, device.activeFormat.videoMaxZoomFactor)
                if abs(device.videoZoomFactor - cappedZoom) > 0.01 {
                    device.videoZoomFactor = cappedZoom
                }
            } catch {
                reportError("Unable to configure camera: \(error.localizedDescription)")
            }
        }

        func stopSession() {
            Self.sessionQueue.async { [self] in
                guard Self.activeCoordinator === self || Self.activeCoordinator == nil else {
                    return
                }

                if Self.activeCoordinator === self {
                    Self.activeCoordinator = nil
                    Self.sharedOutput?.setMetadataObjectsDelegate(nil, queue: nil)
                }

                Self.stopGeneration += 1
                let stopGeneration = Self.stopGeneration

                Self.sessionQueue.asyncAfter(deadline: .now() + 0.35) {
                    guard Self.stopGeneration == stopGeneration,
                          Self.activeCoordinator == nil,
                          let session = Self.sharedSession,
                          session.isRunning else {
                        return
                    }

                    session.stopRunning()
                }
            }
        }
    }
}
