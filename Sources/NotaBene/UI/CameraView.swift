#if canImport(UIKit) && canImport(AVFoundation)
import SwiftUI
import AVFoundation
import UIKit

struct CameraView: UIViewControllerRepresentable {
    let onCapture: (Data) -> Void
    let onError: (String) -> Void
    @Binding var captureToken: UUID?

    func makeUIViewController(context: Context) -> CameraViewController {
        let vc = CameraViewController()
        vc.onCapture = onCapture
        vc.onError = onError
        return vc
    }

    func updateUIViewController(_ vc: CameraViewController, context: Context) {
        vc.onCapture = onCapture
        vc.onError = onError
        if let token = captureToken, vc.lastCaptureToken != token {
            vc.lastCaptureToken = token
            vc.snap()
        }
    }
}

final class CameraViewController: UIViewController, AVCapturePhotoCaptureDelegate {
    var onCapture: ((Data) -> Void)?
    var onError: ((String) -> Void)?
    var lastCaptureToken: UUID?

    private let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private var previewLayer: AVCaptureVideoPreviewLayer?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        requestAccessAndConfigure()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        startSession()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopSession()
    }

    private func requestAccessAndConfigure() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted { self?.configureSession() } else {
                        self?.onError?("Camera permission denied")
                    }
                }
            }
        case .denied, .restricted:
            onError?("Camera permission denied")
        @unknown default:
            onError?("Camera permission unknown state")
        }
    }

    private func configureSession() {
        session.beginConfiguration()
        session.sessionPreset = .photo

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            session.commitConfiguration()
            onError?("Camera unavailable")
            return
        }
        session.addInput(input)
        guard session.canAddOutput(output) else {
            session.commitConfiguration()
            onError?("Capture output unavailable")
            return
        }
        session.addOutput(output)

        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.bounds
        view.layer.addSublayer(layer)
        previewLayer = layer

        session.commitConfiguration()
        startSession()
    }

    private func startSession() {
        guard !session.isRunning else { return }
        DispatchQueue.global(qos: .userInitiated).async { [session] in
            session.startRunning()
        }
    }

    private func stopSession() {
        guard session.isRunning else { return }
        DispatchQueue.global(qos: .userInitiated).async { [session] in
            session.stopRunning()
        }
    }

    func snap() {
        let settings = AVCapturePhotoSettings()
        output.capturePhoto(with: settings, delegate: self)
    }

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        if let error {
            onError?(error.localizedDescription)
            return
        }
        guard let data = photo.fileDataRepresentation() else {
            onError?("No image data")
            return
        }
        onCapture?(data)
    }
}
#endif
