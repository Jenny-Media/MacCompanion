import AppKit
import CoreImage
import CoreMedia
import CoreVideo
import Foundation
import ScreenCaptureKit
@preconcurrency import WebRTC

final class CaptureOutput: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private var peer: MediaPeer
    private let lock = NSLock()
    private var frames = 0
    private var failure: String?
    init(peer: MediaPeer) { self.peer = peer }
    func replacePeer(_ peer: MediaPeer) { lock.withLock { self.peer = peer } }
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let status = attachments.first?[.status] as? Int, status == SCFrameStatus.complete.rawValue,
              let buffer = sampleBuffer.imageBuffer else { return }
        let peer = lock.withLock { frames += 1; return self.peer }
        let timestamp = Int64(CMTimeGetSeconds(sampleBuffer.presentationTimeStamp) * 1_000_000_000)
        peer.submit(buffer, timestampNs: timestamp)
    }
    func stream(_ stream: SCStream, didStopWithError error: Error) { lock.withLock { failure = String(describing: error) } }
    func summary() -> [String: Any] { lock.withLock { ["completeCapturedFrames":frames,"captureError":failure ?? ""] } }
}

@main
@MainActor
final class CaptureApp: NSObject, NSApplicationDelegate {
    private var target: NSWindow!
    private var controls: NSWindow!
    private var imageView: NSImageView!
    private var label: NSTextField!
    private var timer: Timer?
    private var monitor: Timer?
    private var stream: SCStream?
    private var output: CaptureOutput?
    private var peer: MediaPeer?
    private var sequence: UInt32 = 0
    private var work: URL!
    private var expiresAt = 0.0
    private var session = UUID().uuidString
    private var generation: UInt8 = 71
    private var synthetic = false
    private var state = "Preparing"
    private var accepting = false
    private var reconnecting = false
    private var stopped = false
    private var reconnectCount = 0
    private var statisticsPending = false
    private var nextStatistics = Date.distantPast
    private var latestStatistics: [[String: Any]] = []
    private let worker = DispatchQueue(label: "WebRTCProbe.capture-owner")
    private let imageContext = CIContext()

    static func main() {
        let app = NSApplication.shared
        let delegate = CaptureApp()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { app.run() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = CommandLine.arguments
        func option(_ name: String) -> String? {
            guard let index = args.firstIndex(of: name), index + 1 < args.count else { return nil }
            return args[index + 1]
        }
        guard let directory = option("--work-dir"), directory.hasPrefix("/private/tmp/maccompanion-webrtc-") else {
            NSApp.terminate(nil); return
        }
        work = URL(fileURLWithPath: directory, isDirectory: true)
        synthetic = args.contains("--synthetic")
        let seconds = min(3600, max(30, Double(option("--seconds") ?? "300") ?? 300))
        expiresAt = Date().timeIntervalSince1970 + seconds
        generation = UInt8(option("--generation") ?? "71") ?? 71
        setupWindows()
        monitor = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
        RTCInitializeSSL()
        worker.async { [weak self, generation] in
            do {
                let peer = try MediaPeer(sending: true, sink: FrameSink(generation: generation), localNetworkOnly: true)
                Task { @MainActor in
                    guard let self else { peer.close(); return }
                    self.peer = peer
                    await self.begin()
                }
            } catch { Task { @MainActor in self?.record("Failed: \(error)") } }
        }
    }

    private func setupWindows() {
        target = NSWindow(contentRect: NSRect(x: 100, y: 150, width: 640, height: 360),
                          styleMask: [.borderless], backing: .buffered, defer: false)
        target.title = "WebRTC Synthetic Target"
        imageView = NSImageView(frame: NSRect(x: 0, y: 0, width: 640, height: 360))
        imageView.imageScaling = .scaleAxesIndependently
        target.contentView = imageView
        target.orderFrontRegardless()
        controls = NSWindow(contentRect: NSRect(x: 120, y: 540, width: 530, height: 120),
                            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        controls.title = "WebRTC Capture Test"
        label = NSTextField(labelWithString: "Preparing test")
        label.frame = NSRect(x: 20, y: 60, width: 490, height: 40)
        label.maximumNumberOfLines = 2
        let stop = NSButton(title: "Stop test", target: self, action: #selector(stopTest))
        stop.frame = NSRect(x: 20, y: 14, width: 120, height: 32)
        controls.contentView?.addSubview(label); controls.contentView?.addSubview(stop)
        controls.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: false)
    }

    private func begin() async {
        guard let peer else { return }
        if !synthetic && !CGPreflightScreenCaptureAccess() {
            record("Screen Recording permission required; allow this app, then relaunch")
            _ = CGRequestScreenCaptureAccess()
            return
        }
        do {
            try animate()
            if !synthetic {
                let window = try await waitForTargetWindow()
                let configuration = SCStreamConfiguration()
                configuration.width = 1280; configuration.height = 720
                configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
                configuration.pixelFormat = kCVPixelFormatType_32BGRA
                configuration.queueDepth = 3
                configuration.capturesAudio = false; configuration.showsCursor = false
                configuration.ignoreShadowsSingleWindow = true
                let output = CaptureOutput(peer: peer)
                let stream = SCStream(filter: SCContentFilter(desktopIndependentWindow: window), configuration: configuration, delegate: output)
                try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: DispatchQueue(label: "WebRTCProbe.capture-frames"))
                try await stream.startCapture()
                self.stream = stream; self.output = output
            }
            timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    do { try self?.animate() } catch { self?.record("Frame error: \(error)") }
                }
            }
            record("Preparing connection")
            let work = self.work!; let session = self.session; let generation = self.generation
            let expiresAt = self.expiresAt; let synthetic = self.synthetic
            worker.async { [weak self] in
                do {
                    let offer = try peer.offer()
                    try ProbeExchange(session: session, generation: generation, expiresAt: expiresAt,
                                      sdp: offer, capture: !synthetic).write(work.appendingPathComponent("offer.json"))
                    Task { @MainActor in self?.record("Waiting for receiver") }
                } catch { Task { @MainActor in self?.record("Offer failed: \(error)") } }
            }
        } catch { record("Capture failed: \(error)") }
    }

    /// WindowServer can publish a newly ordered window after the first content query.
    /// Retry only this app's exact window; never fall back to another window/display.
    private func waitForTargetWindow() async throws -> SCWindow {
        let identifier = CGWindowID(target.windowNumber)
        for _ in 0..<20 {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            if let window = content.windows.first(where: { $0.windowID == identifier }) { return window }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw MediaProbeError.timeout("owned capture window did not become available")
    }

    private func animate() throws {
        sequence += 1
        let buffer = try SyntheticFrames.make(sequence: sequence, generation: generation)
        if let cg = imageContext.createCGImage(CIImage(cvPixelBuffer: buffer), from: CGRect(x: 0, y: 0, width: 1280, height: 720)) {
            imageView.image = NSImage(cgImage: cg, size: NSSize(width: 640, height: 360))
        }
        if synthetic { peer?.submit(buffer, timestampNs: Int64(ProcessInfo.processInfo.systemUptime * 1_000_000_000)) }
    }

    private func poll() {
        if Date().timeIntervalSince1970 >= expiresAt { stopTest(); return }
        if !reconnecting, !stopped, reconnectCount < 32,
           let request = try? ProbeReconnectRequest.read(work.appendingPathComponent("reconnect-request.json")),
           request.previousSession == session, request.generation == generation, request.expiresAt == expiresAt {
            reconnect(request)
        }
        if reconnecting { record("Reconnecting"); return }
        if !accepting, let answer = try? ProbeExchange.read(work.appendingPathComponent("answer.json")),
           answer.session == session, answer.generation == generation, answer.expiresAt == expiresAt, let peer {
            accepting = true
            let expectedSession = session
            worker.async { [weak self] in
                do {
                    try peer.acceptAnswer(answer.sdp)
                    Task { @MainActor in
                        guard let self, !self.stopped, self.session == expectedSession else { return }
                        self.record("Streaming")
                    }
                } catch {
                    Task { @MainActor in
                        guard let self, !self.stopped, self.session == expectedSession else { return }
                        self.record("Answer failed: \(error)")
                    }
                }
            }
        }
        if accepting, let peer {
            switch peer.connection.connectionState {
            case .connected: state = "Streaming"
            case .disconnected: state = "Connection interrupted"
            case .failed, .closed: state = "Connection lost"
            default: state = "Connecting"
            }
        }
        if accepting, let peer, !statisticsPending, Date() >= nextStatistics {
            statisticsPending = true
            nextStatistics = Date().addingTimeInterval(5)
            worker.async { [weak self] in
                let data = try? JSONSerialization.data(withJSONObject: peer.statistics())
                Task { @MainActor in
                    guard let self, self.peer === peer else { return }
                    self.statisticsPending = false
                    if let data, let values = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                        self.latestStatistics = values
                    }
                }
            }
        }
        record(state)
    }

    private func reconnect(_ request: ProbeReconnectRequest) {
        reconnecting = true; accepting = false; reconnectCount += 1
        let nextSession = UUID().uuidString
        session = nextSession
        let generation = self.generation; let expiresAt = self.expiresAt
        let synthetic = self.synthetic; let work = self.work!
        worker.async { [weak self] in
            var created: MediaPeer?
            do {
                let next = try MediaPeer(sending: true, sink: FrameSink(generation: generation), localNetworkOnly: true)
                created = next
                let sdp = try next.offer()
                Task { @MainActor in
                    guard let self, !self.stopped, self.session == nextSession,
                          Date().timeIntervalSince1970 < expiresAt else { next.close(); return }
                    let old = self.peer
                    self.peer = next; self.output?.replacePeer(next)
                    self.latestStatistics = []; self.statisticsPending = false; self.nextStatistics = .distantPast
                    old?.close()
                    do {
                        try ProbeExchange(session: nextSession, generation: generation, expiresAt: expiresAt,
                            sdp: sdp, capture: !synthetic, reconnectRequest: request.request)
                            .write(work.appendingPathComponent("offer.json"))
                        self.reconnecting = false; self.record("Waiting for receiver")
                    } catch { self.reconnecting = false; self.record("Reconnect failed: \(error)") }
                }
            } catch {
                created?.close()
                Task { @MainActor in
                    guard let self, !self.stopped, self.session == nextSession else { return }
                    self.reconnecting = false; self.record("Reconnect failed: \(error)")
                }
            }
        }
    }

    private func record(_ value: String) {
        state = value; label?.stringValue = value
        guard let work else { return }
        writeProbeStatus(["state": value, "session": session, "synthetic": synthetic,
            "networkPolicy": "local network; VPN and cellular adapters excluded",
            "connectionState": peer?.connection.connectionState.rawValue ?? -1,
            "iceState": peer?.connection.iceConnectionState.rawValue ?? -1,
            "generatedFrames": sequence, "reconnectCount": reconnectCount, "capture": output?.summary() ?? [:],
            "mediaStatistics": latestStatistics], to: work.appendingPathComponent("host-status.json"))
    }
    @objc private func stopTest() {
        stopped = true
        timer?.invalidate(); monitor?.invalidate()
        record("Stopped")
        let oldPeer = peer; peer = nil
        oldPeer?.close()
        Task { if let stream { try? await stream.stopCapture() }; NSApp.terminate(nil) }
    }
    func applicationWillTerminate(_ notification: Notification) { timer?.invalidate(); monitor?.invalidate(); peer?.close() }
}
