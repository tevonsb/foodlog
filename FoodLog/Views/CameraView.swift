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
        let shutterBackground = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterialDark))
        shutterBackground.translatesAutoresizingMaskIntoConstraints = false
        shutterBackground.layer.cornerRadius = 38
        shutterBackground.clipsToBounds = true
        view.addSubview(shutterBackground)

        let shutterButton = UIButton(type: .system)
        shutterButton.translatesAutoresizingMaskIntoConstraints = false
        let symbolConfig = UIImage.SymbolConfiguration(pointSize: 72, weight: .light)
        if #available(iOS 26.0, *) {
            var buttonConfig = UIButton.Configuration.prominentGlass()
            buttonConfig.image = UIImage(systemName: "circle.inset.filled", withConfiguration: symbolConfig)
            buttonConfig.baseForegroundColor = .white
            buttonConfig.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12)
            shutterButton.configuration = buttonConfig
            shutterBackground.isHidden = true
        } else {
            shutterButton.setImage(UIImage(systemName: "circle.inset.filled", withConfiguration: symbolConfig), for: .normal)
            shutterButton.tintColor = .white
        }
        shutterButton.addTarget(self, action: #selector(capturePhoto), for: .touchUpInside)
        view.addSubview(shutterButton)

        // Cancel button
        let cancelButton = UIButton(type: .system)
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        if #available(iOS 26.0, *) {
            var cancelConfig = UIButton.Configuration.glass()
            cancelConfig.title = "Cancel"
            cancelConfig.baseForegroundColor = .white
            cancelConfig.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
                var outgoing = incoming
                outgoing.font = .systemFont(ofSize: 18, weight: .semibold)
                return outgoing
            }
            cancelConfig.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12)
            cancelButton.configuration = cancelConfig
        } else {
            var cancelConfig = UIButton.Configuration.plain()
            cancelConfig.title = "Cancel"
            cancelConfig.baseForegroundColor = .white
            cancelConfig.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
                var outgoing = incoming
                outgoing.font = .systemFont(ofSize: 18, weight: .semibold)
                return outgoing
            }
            cancelConfig.background.backgroundColor = UIColor.black.withAlphaComponent(0.35)
            cancelConfig.background.cornerRadius = 16
            cancelConfig.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12)
            cancelButton.configuration = cancelConfig
        }
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        view.addSubview(cancelButton)

        // Barcode indicator (top-right)
        if onBarcodeScanned != nil {
            let iconBackground = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterialDark))
            iconBackground.translatesAutoresizingMaskIntoConstraints = false
            iconBackground.layer.cornerRadius = 16
            iconBackground.clipsToBounds = true
            view.addSubview(iconBackground)

            let iconView = UIImageView()
            iconView.translatesAutoresizingMaskIntoConstraints = false
            let iconConfig = UIImage.SymbolConfiguration(pointSize: 20, weight: .medium)
            iconView.image = UIImage(systemName: "barcode.viewfinder", withConfiguration: iconConfig)
            iconView.tintColor = .white.withAlphaComponent(0.9)
            view.addSubview(iconView)
            barcodeIconView = iconView

            NSLayoutConstraint.activate([
                iconBackground.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
                iconBackground.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
                iconBackground.widthAnchor.constraint(equalToConstant: 32),
                iconBackground.heightAnchor.constraint(equalToConstant: 32),

                iconView.centerXAnchor.constraint(equalTo: iconBackground.centerXAnchor),
                iconView.centerYAnchor.constraint(equalTo: iconBackground.centerYAnchor)
            ])
        }

        // Barcode overlay label (hidden by default)
        let overlay = UILabel()
        overlay.translatesAutoresizingMaskIntoConstraints = false
        overlay.font = .systemFont(ofSize: 16, weight: .semibold)
        overlay.textColor = .white
        overlay.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        overlay.textAlignment = .center
        overlay.layer.cornerRadius = 12
        overlay.clipsToBounds = true
        overlay.isHidden = true
        view.addSubview(overlay)
        barcodeOverlayLabel = overlay

        NSLayoutConstraint.activate([
            shutterBackground.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            shutterBackground.centerYAnchor.constraint(equalTo: shutterButton.centerYAnchor),
            shutterBackground.widthAnchor.constraint(equalToConstant: 76),
            shutterBackground.heightAnchor.constraint(equalToConstant: 76),

            shutterButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            shutterButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -30),

            cancelButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            cancelButton.centerYAnchor.constraint(equalTo: shutterButton.centerYAnchor),

            overlay.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            overlay.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 60),
            overlay.heightAnchor.constraint(equalToConstant: 40)
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

#if DEBUG
private struct CameraPreviewMock: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black, Color.black.opacity(0.75), Color.black],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack {
                HStack {
                    Text("Cancel")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(.black.opacity(0.35), in: Capsule())
                    Spacer()
                    Image(systemName: "barcode.viewfinder")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(8)
                        .background(.thinMaterial, in: Circle())
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)

                Spacer()

                ZStack {
                    Circle()
                        .fill(.thinMaterial)
                        .frame(width: 76, height: 76)
                    Image(systemName: "circle.inset.filled")
                        .font(.system(size: 72, weight: .light))
                        .foregroundStyle(.white)
                }
                .padding(.bottom, 30)
            }
        }
    }
}

#Preview("Camera") {
    CameraPreviewMock()
}
#endif
