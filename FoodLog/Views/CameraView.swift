import SwiftUI
import AVFoundation
import UIKit

struct CameraView: UIViewControllerRepresentable {
    let onImageCaptured: (Data) -> Void
    let onBarcodeScanned: ((String) -> Void)?
    @Environment(\.dismiss) private var dismiss

    init(onImageCaptured: @escaping (Data) -> Void, onBarcodeScanned: ((String) -> Void)? = nil) {
        self.onImageCaptured = onImageCaptured
        self.onBarcodeScanned = onBarcodeScanned
    }

    func makeUIViewController(context: Context) -> BarcodeCameraViewController {
        let vc = BarcodeCameraViewController()
        vc.onImageCaptured = { data in
            onImageCaptured(data)
            dismiss()
        }
        vc.onBarcodeScanned = { barcode in
            onBarcodeScanned?(barcode)
            dismiss()
        }
        vc.onCancel = {
            dismiss()
        }
        return vc
    }

    func updateUIViewController(_ uiViewController: BarcodeCameraViewController, context: Context) {}
}

// MARK: - AVFoundation Camera Controller

class BarcodeCameraViewController: UIViewController {
    var onImageCaptured: ((Data) -> Void)?
    var onBarcodeScanned: ((String) -> Void)?
    var onCancel: (() -> Void)?

    private let captureSession = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let metadataOutput = AVCaptureMetadataOutput()
    private var previewLayer: AVCaptureVideoPreviewLayer!

    private var hasScannedBarcode = false
    private var barcodeOverlayLabel: UILabel?
    private var barcodeIconView: UIImageView?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupCamera()
        setupUI()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.captureSession.startRunning()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        captureSession.stopRunning()
    }

    // MARK: - Camera Setup

    private func setupCamera() {
        captureSession.sessionPreset = .photo

        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: camera) else { return }

        if captureSession.canAddInput(input) {
            captureSession.addInput(input)
        }

        // Photo output
        if captureSession.canAddOutput(photoOutput) {
            captureSession.addOutput(photoOutput)
        }

        // Barcode metadata output (only if barcode callback provided)
        if onBarcodeScanned != nil, captureSession.canAddOutput(metadataOutput) {
            captureSession.addOutput(metadataOutput)
            metadataOutput.setMetadataObjectsDelegate(self, queue: .main)

            let barcodeTypes: [AVMetadataObject.ObjectType] = [.ean13, .ean8, .upce]
            let supported = barcodeTypes.filter { metadataOutput.availableMetadataObjectTypes.contains($0) }
            metadataOutput.metadataObjectTypes = supported
        }

        // Preview
        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = view.bounds
        view.layer.addSublayer(previewLayer)
    }

    // MARK: - UI

    private func setupUI() {
        // Shutter button
        let shutterButton = UIButton(type: .system)
        shutterButton.translatesAutoresizingMaskIntoConstraints = false
        let config = UIImage.SymbolConfiguration(pointSize: 72, weight: .light)
        shutterButton.setImage(UIImage(systemName: "circle.inset.filled", withConfiguration: config), for: .normal)
        shutterButton.tintColor = .white
        shutterButton.addTarget(self, action: #selector(capturePhoto), for: .touchUpInside)
        view.addSubview(shutterButton)

        // Cancel button
        let cancelButton = UIButton(type: .system)
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.setTitle("Cancel", for: .normal)
        cancelButton.titleLabel?.font = .systemFont(ofSize: 18)
        cancelButton.tintColor = .white
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        view.addSubview(cancelButton)

        // Barcode indicator (top-right)
        if onBarcodeScanned != nil {
            let iconView = UIImageView()
            iconView.translatesAutoresizingMaskIntoConstraints = false
            let iconConfig = UIImage.SymbolConfiguration(pointSize: 20, weight: .medium)
            iconView.image = UIImage(systemName: "barcode.viewfinder", withConfiguration: iconConfig)
            iconView.tintColor = .white.withAlphaComponent(0.7)
            view.addSubview(iconView)
            barcodeIconView = iconView

            NSLayoutConstraint.activate([
                iconView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
                iconView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            ])
        }

        // Barcode overlay label (hidden by default)
        let overlay = UILabel()
        overlay.translatesAutoresizingMaskIntoConstraints = false
        overlay.font = .systemFont(ofSize: 16, weight: .semibold)
        overlay.textColor = .white
        overlay.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        overlay.textAlignment = .center
        overlay.layer.cornerRadius = 12
        overlay.clipsToBounds = true
        overlay.isHidden = true
        view.addSubview(overlay)
        barcodeOverlayLabel = overlay

        NSLayoutConstraint.activate([
            shutterButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            shutterButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -30),

            cancelButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            cancelButton.centerYAnchor.constraint(equalTo: shutterButton.centerYAnchor),

            overlay.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            overlay.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 60),
            overlay.heightAnchor.constraint(equalToConstant: 40),
        ])
    }

    @objc private func capturePhoto() {
        let settings = AVCapturePhotoSettings()
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    @objc private func cancelTapped() {
        onCancel?()
    }
}

// MARK: - Photo Capture

extension BarcodeCameraViewController: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil,
              let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data),
              let resized = resizeImage(image, maxDimension: 1024),
              let jpegData = resized.jpegData(compressionQuality: 0.8) else { return }
        onImageCaptured?(jpegData)
    }

    private func resizeImage(_ image: UIImage, maxDimension: CGFloat) -> UIImage? {
        let size = image.size
        let maxSide = max(size.width, size.height)
        guard maxSide > maxDimension else { return image }

        let scale = maxDimension / maxSide
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)

        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}

// MARK: - Barcode Detection

extension BarcodeCameraViewController: AVCaptureMetadataOutputObjectsDelegate {
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard !hasScannedBarcode,
              let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let barcode = object.stringValue else { return }

        hasScannedBarcode = true

        // Haptic feedback
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)

        // Show barcode overlay briefly
        barcodeOverlayLabel?.text = "  \(barcode)  "
        barcodeOverlayLabel?.isHidden = false

        // Dismiss after short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.onBarcodeScanned?(barcode)
        }
    }
}
