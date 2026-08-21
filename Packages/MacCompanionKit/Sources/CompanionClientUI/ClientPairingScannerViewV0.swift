#if os(iOS)
import AVFoundation
import SwiftUI
import UIKit
import Vision
import VisionKit

@available(iOS 17.0, *)
public struct ClientPairingScannerViewV0: UIViewControllerRepresentable {
    private let onScan: (String) -> Void
    private let onCancel: () -> Void

    public init(
        onScan: @escaping (String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.onScan = onScan
        self.onCancel = onCancel
    }

    public func makeUIViewController(
        context: Context
    ) -> ClientPairingScannerViewControllerV0 {
        ClientPairingScannerViewControllerV0(
            onScan: onScan,
            onCancel: onCancel
        )
    }

    public func updateUIViewController(
        _ uiViewController: ClientPairingScannerViewControllerV0,
        context: Context
    ) {}

    public static func dismantleUIViewController(
        _ uiViewController: ClientPairingScannerViewControllerV0,
        coordinator: Void
    ) {
        uiViewController.stop()
    }
}

@available(iOS 17.0, *)
@MainActor
public final class ClientPairingScannerViewControllerV0:
    UIViewController,
    DataScannerViewControllerDelegate
{
    private let onScan: (String) -> Void
    private let onCancel: () -> Void
    private let statusLabel = UILabel()
    private let detailLabel = UILabel()
    private let spinner = UIActivityIndicatorView(style: .large)
    private let cancelButton = UIButton(type: .system)
    private var scanner: DataScannerViewController?
    private var preparationTask: Task<Void, Never>?
    private var onscreen = false
    private var visible = false
    private var completed = false
    private var failureShown = false

    public init(
        onScan: @escaping (String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.onScan = onScan
        self.onCancel = onCancel
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        view.accessibilityIdentifier = "Pairing code scanner"
        configureStatusUI()
        showPreparing()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationWillResignActive),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        onscreen = true
        resumeIfPossible()
    }

    public override func viewWillDisappear(_ animated: Bool) {
        onscreen = false
        pause()
        super.viewWillDisappear(animated)
    }

    public func stop() {
        onscreen = false
        pause()
    }

    private func pause() {
        visible = false
        preparationTask?.cancel()
        preparationTask = nil
        stopScanner()
    }

    private func resumeIfPossible() {
        guard onscreen, !completed else { return }
        visible = true
        guard preparationTask == nil, scanner == nil else { return }
        showPreparing()
        preparationTask = Task { [weak self] in
            await self?.prepareAndStart()
        }
    }

    public func dataScanner(
        _ dataScanner: DataScannerViewController,
        didAdd addedItems: [RecognizedItem],
        allItems: [RecognizedItem]
    ) {
        guard !completed else { return }
        for item in addedItems {
            guard case let .barcode(barcode) = item,
                  let candidate = barcode.payloadStringValue,
                  let admitted = ClientPairingScanFilterV0.admit(candidate) else {
                continue
            }
            completed = true
            stopScanner()
            onScan(admitted)
            return
        }
    }

    public func dataScanner(
        _ dataScanner: DataScannerViewController,
        becameUnavailableWithError error: DataScannerViewController.ScanningUnavailable
    ) {
        guard visible else { return }
        showFailure(
            title: "Camera Unavailable",
            detail: "The system scanner stopped. Close it and try pairing again."
        )
    }

    private func configureStatusUI() {
        statusLabel.font = .preferredFont(forTextStyle: .title2)
        statusLabel.textColor = .white
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0

        detailLabel.font = .preferredFont(forTextStyle: .body)
        detailLabel.textColor = .lightGray
        detailLabel.textAlignment = .center
        detailLabel.numberOfLines = 0

        spinner.color = .white
        spinner.hidesWhenStopped = true

        var configuration = UIButton.Configuration.borderedProminent()
        configuration.title = "Cancel"
        configuration.baseBackgroundColor = .white
        configuration.baseForegroundColor = .black
        cancelButton.configuration = configuration
        cancelButton.addTarget(self, action: #selector(cancel), for: .touchUpInside)
        cancelButton.accessibilityIdentifier = "Cancel pairing scan"

        let stack = UIStackView(arrangedSubviews: [spinner, statusLabel, detailLabel])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        view.addSubview(cancelButton)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),
            cancelButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            cancelButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
        ])
    }

    private func showPreparing() {
        failureShown = false
        statusLabel.text = "Preparing camera…"
        detailLabel.text = nil
        spinner.startAnimating()
    }

    private func showScanning() {
        failureShown = false
        statusLabel.text = "Point at the pairing code on your Mac"
        detailLabel.text = "Only Mac Companion pairing codes are accepted."
        spinner.stopAnimating()
    }

    private func showFailure(title: String, detail: String) {
        guard !completed, !failureShown else { return }
        failureShown = true
        stopScanner()
        statusLabel.text = title
        detailLabel.text = detail
        spinner.stopAnimating()
        view.bringSubviewToFront(cancelButton)
    }

    private func prepareAndStart() async {
        guard DataScannerViewController.isSupported else {
            showFailure(
                title: "Scanner Unavailable",
                detail: "This device does not support the system code scanner."
            )
            return
        }

        let authorized: Bool
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            authorized = true
        case .notDetermined:
            authorized = await AVCaptureDevice.requestAccess(for: .video)
        case .denied, .restricted:
            authorized = false
        @unknown default:
            authorized = false
        }
        guard !Task.isCancelled, visible, !completed else { return }
        guard authorized else {
            showFailure(
                title: "Camera Access Needed",
                detail: "Allow camera access in Settings, then try pairing again."
            )
            return
        }
        guard DataScannerViewController.isAvailable else {
            showFailure(
                title: "Camera Unavailable",
                detail: "Camera access is restricted or another system condition prevents scanning."
            )
            return
        }
        startScanner()
    }

    private func startScanner() {
        guard scanner == nil, visible, !completed else { return }
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        scanner.delegate = self
        addChild(scanner)
        scanner.view.translatesAutoresizingMaskIntoConstraints = false
        view.insertSubview(scanner.view, at: 0)
        NSLayoutConstraint.activate([
            scanner.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scanner.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scanner.view.topAnchor.constraint(equalTo: view.topAnchor),
            scanner.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        scanner.didMove(toParent: self)
        self.scanner = scanner
        showScanning()
        do {
            try scanner.startScanning()
        } catch {
            showFailure(
                title: "Couldn’t Start Scanner",
                detail: "Close the scanner and try again."
            )
        }
    }

    private func stopScanner() {
        guard let scanner else { return }
        scanner.stopScanning()
        scanner.willMove(toParent: nil)
        scanner.view.removeFromSuperview()
        scanner.removeFromParent()
        self.scanner = nil
    }

    @objc private func cancel() {
        guard !completed else { return }
        completed = true
        stop()
        onCancel()
    }

    @objc private func applicationWillResignActive() {
        pause()
    }

    @objc private func applicationDidBecomeActive() {
        resumeIfPossible()
    }
}
#endif
