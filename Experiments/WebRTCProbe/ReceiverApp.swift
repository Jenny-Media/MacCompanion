import UIKit
import Foundation
@preconcurrency import WebRTC

@main
@MainActor
final class ReceiverApp: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        RTCInitializeSSL()
        return true
    }
    func application(_ application: UIApplication, configurationForConnecting session: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: "Probe", sessionRole: session.role)
        configuration.delegateClass = ReceiverScene.self
        return configuration
    }
}

@MainActor
final class ReceiverScene: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private var controller: ReceiverController?
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: scene)
        let controller = ReceiverController()
        self.controller = controller
        window.rootViewController = controller
        window.makeKeyAndVisible(); self.window = window
    }
    func sceneDidEnterBackground(_ scene: UIScene) { controller?.suspend() }
    func sceneDidBecomeActive(_ scene: UIScene) { controller?.resume() }
}

/// A generation-specific UI proxy rejects queued callbacks after Stop/replacement.
final class ReceiverDisplay: NSObject, RTCVideoRenderer, @unchecked Sendable {
    private weak var owner: ReceiverController?
    private let session: String
    private let lock = NSLock()
    private var latest: RTCVideoFrame?
    private var scheduled = false
    @MainActor init(owner: ReceiverController, session: String) { self.owner = owner; self.session = session }
    func setSize(_ size: CGSize) {}
    func renderFrame(_ frame: RTCVideoFrame?) {
        let enqueue = lock.withLock {
            latest = frame
            if scheduled { return false }
            scheduled = true; return true
        }
        guard enqueue else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            let frame = self.takeFrame()
            guard let owner, owner.currentSession == session else { return }
            owner.present(frame)
        }
    }
    private func takeFrame() -> RTCVideoFrame? {
        lock.withLock { let frame = latest; latest = nil; scheduled = false; return frame }
    }
}

@MainActor
final class ReceiverController: UIViewController {
    let video = RTCMTLVideoView(frame: .zero)
    private let label = UILabel()
    private let stopButton = UIButton(type: .system)
    private let worker = DispatchQueue(label: "WebRTCProbe.receiver")
    private var peer: MediaPeer?
    private var sink: FrameSink?
    private var timer: Timer?
    private var processed = Set<String>()
    private var expiresAt = 0.0
    private var pending = false
    private var statisticsPending = false
    private var nextStatistics = Date.distantPast
    private var latestStatistics: [[String: Any]] = []
    private var lastPresentedAt = ProcessInfo.processInfo.systemUptime
    private let stalledVideoInterval: TimeInterval = 1.5
    private var connectionState = -1
    private var iceState = -1
    private var resumeOffer: ProbeExchange?
    private var pendingReconnect: String?
    private var resumeOnForeground = false
    private var reconnectCount = 0
    private var retryAt: Date?
    private var consecutiveFailures = 0
    private var automaticRetryCount = 0
    private var userStopCount = 0
    private var attemptStartedAt = ProcessInfo.processInfo.systemUptime
    private var pendingSince = Date.distantPast
    private var transitions: [[String: Any]] = []
    private var observedState = ""
    private var injectedFailuresRemaining = CommandLine.arguments.contains("--fail-reconnect-once") ? 1 : 0
    private(set) var currentSession: String?
    private var state = "Waiting for test connection"
    private var statusURL: URL { documents.appendingPathComponent("status.json") }
    private var documents: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        video.videoContentMode = .scaleAspectFit
        video.isHidden = true
        video.accessibilityIdentifier = "video"
        label.numberOfLines = 0; label.textAlignment = .center
        label.font = .preferredFont(forTextStyle: .body)
        label.accessibilityIdentifier = "status"
        stopButton.setTitle("Stop test", for: .normal)
        stopButton.accessibilityIdentifier = "stop-test"
        stopButton.addTarget(self, action: #selector(stopTapped), for: .touchUpInside)
        let stack = UIStackView(arrangedSubviews: [label, video, stopButton])
        stack.axis = .vertical; stack.spacing = 12; stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            video.heightAnchor.constraint(greaterThanOrEqualToConstant: 200),
            stopButton.heightAnchor.constraint(equalToConstant: 48),
        ])
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        tick()
    }
    @objc private func stopTapped() {
        userStopCount += 1
        trace("userStopTapped")
        stop(reason: "stopped")
    }

    func present(_ frame: RTCVideoFrame?) {
        guard UIApplication.shared.applicationState == .active,
              let frame, peer?.connection.connectionState == .connected else { return }
        lastPresentedAt = ProcessInfo.processInfo.systemUptime
        if (sink?.count ?? 0) >= 30 { consecutiveFailures = 0 }
        state = "Receiving"
        video.setSize(CGSize(width: Int(frame.width), height: Int(frame.height)))
        video.renderFrame(frame)
        video.isHidden = false
    }

    func stop(reason: String) {
        trace("terminalStop", detail: reason)
        retryAt = nil
        resumeOffer = nil; pendingReconnect = nil; resumeOnForeground = false
        retire(reason: reason)
    }

    private func retire(reason: String) {
        let oldPeer = peer
        currentSession = nil; peer = nil; pending = false
        UIApplication.shared.isIdleTimerDisabled = false
        statisticsPending = false; nextStatistics = .distantPast
        sink?.retire(); video.renderFrame(nil); video.isHidden = true
        state = reason
        worker.async { oldPeer?.close() }
        record()
    }

    func suspend() {
        trace("enteredBackground")
        guard resumeOffer != nil else { record(); return }
        resumeOnForeground = true
        retryAt = nil
        retire(reason: "background")
    }

    func resume() {
        trace("becameActive")
        guard resumeOnForeground else { return }
        resumeOnForeground = false
        retryAt = nil
        consecutiveFailures = 0
        requestResume()
    }

    private func requestResume() {
        guard let offer = resumeOffer, (try? offer.validate()) != nil else { stop(reason: "expired"); return }
        if pendingReconnect == nil {
            guard reconnectCount < 32 else { stop(reason: "Reconnect limit reached"); return }
            let request = ProbeReconnectRequest(request: UUID().uuidString, previousSession: offer.session,
                generation: offer.generation, expiresAt: offer.expiresAt)
            do {
                try request.write(documents.appendingPathComponent("reconnect-request.json"))
                pendingReconnect = request.request; reconnectCount += 1
                pendingSince = Date()
                trace("resumeRequested")
            } catch { stop(reason: "Reconnect request failed"); return }
        }
        UIApplication.shared.isIdleTimerDisabled = true
        state = "Reconnecting"
        record()
        tick()
    }

    private func recover(_ reason: String) {
        guard let offer = resumeOffer, (try? offer.validate()) != nil else { stop(reason: "expired"); return }
        trace("connectionAttemptFailed", detail: reason)
        // A failed peer does not cancel the user's bounded resume intent.
        // Only a peer for an admitted offer reaches this path, so its session
        // is also the host's current session when the next request is relayed.
        pendingReconnect = nil
        retire(reason: "Reconnecting")
        resumeOnForeground = true
        consecutiveFailures += 1
        if UIApplication.shared.applicationState == .active && consecutiveFailures <= 3 {
            automaticRetryCount += 1
            retryAt = Date().addingTimeInterval(pow(2, Double(consecutiveFailures - 1)))
        } else {
            state = "Connection unavailable — return to retry"
            record()
        }
    }

    private func tick() {
        if (currentSession != nil || pendingReconnect != nil || resumeOnForeground || retryAt != nil),
           Date().timeIntervalSince1970 >= expiresAt { stop(reason: "expired") }
        if UIApplication.shared.applicationState == .active, let deadline = retryAt, Date() >= deadline {
            retryAt = nil; resumeOnForeground = false
            requestResume()
            return
        }
        if pendingReconnect != nil && Date().timeIntervalSince(pendingSince) > 15 {
            state = "Waiting for Mac to reconnect"
        }
        if UIApplication.shared.applicationState == .active,
           let offer = try? ProbeExchange.read(documents.appendingPathComponent("offer.json")),
           !processed.contains(offer.session), !pending,
           offer.reconnectRequest == nil || offer.reconnectRequest == pendingReconnect {
            if processed.count >= 32 { stop(reason: "Restart app before further sessions"); return }
            retire(reason: "replacing")
            retryAt = nil; resumeOnForeground = false; pendingReconnect = nil
            resumeOffer = offer
            trace("offerAdmitted", detail: offer.session)
            processed.insert(offer.session)
            currentSession = offer.session; expiresAt = offer.expiresAt; pending = true
            UIApplication.shared.isIdleTimerDisabled = true
            connectionState = -1; iceState = -1
            latestStatistics = []
            lastPresentedAt = ProcessInfo.processInfo.systemUptime
            attemptStartedAt = lastPresentedAt
            state = "Connecting"
            let injectFailure = offer.reconnectRequest != nil && injectedFailuresRemaining > 0
            if injectFailure { injectedFailuresRemaining -= 1; trace("injectedReconnectFailure") }
            let newSink = FrameSink(generation: offer.generation)
            newSink.setDisplay(ReceiverDisplay(owner: self, session: offer.session))
            sink = newSink
            let answerURL = documents.appendingPathComponent("answer.json")
            worker.async { [weak self] in
                var createdPeer: MediaPeer?
                do {
                    if injectFailure { throw MediaProbeError.missingPeer }
                    let peer = try MediaPeer(sending: false, sink: newSink, localNetworkOnly: true)
                    createdPeer = peer
                    let answer = try peer.answer(offer.sdp)
                    try ProbeExchange(session: offer.session, generation: offer.generation, expiresAt: offer.expiresAt,
                                      sdp: answer, capture: offer.capture, reconnectRequest: offer.reconnectRequest).write(answerURL)
                    Task { @MainActor in
                        guard let self, self.currentSession == offer.session else { peer.close(); return }
                        self.peer = peer; self.pending = false; self.state = "Connecting"
                    }
                } catch {
                    createdPeer?.close()
                    Task { @MainActor in
                        guard let self, self.currentSession == offer.session else { return }
                        self.recover("Negotiation failed: \(error)")
                    }
                }
            }
        }
        if let peer {
            connectionState = peer.connection.connectionState.rawValue
            iceState = peer.connection.iceConnectionState.rawValue
            switch peer.connection.connectionState {
            case .failed, .closed:
                recover("Peer connection lost")
                return
            case .disconnected:
                state = "Connection interrupted"
                video.renderFrame(nil); video.isHidden = true
            case .connected:
                if (sink?.count ?? 0) > 0,
                   ProcessInfo.processInfo.systemUptime - lastPresentedAt > stalledVideoInterval {
                    // Missing frames indicate a stall, not necessarily a lost network.
                    state = "Waiting for video"
                    video.renderFrame(nil); video.isHidden = true
                }
            default: state = "Connecting"
            }
            if (sink?.count ?? 0) == 0 && ProcessInfo.processInfo.systemUptime - attemptStartedAt > 15 {
                recover("Timed out waiting for the first video frame")
                return
            }
        }
        if let peer, let session = currentSession, !statisticsPending, Date() >= nextStatistics {
            statisticsPending = true
            nextStatistics = Date().addingTimeInterval(5)
            worker.async { [weak self] in
                let data = try? JSONSerialization.data(withJSONObject: peer.statistics())
                Task { @MainActor in
                    guard let self, self.currentSession == session else { return }
                    self.statisticsPending = false
                    if let data, let values = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                        self.latestStatistics = values
                    }
                }
            }
        }
        record()
    }

    private func trace(_ event: String, detail: String? = nil) {
        var row: [String: Any] = ["event": event, "uptime": ProcessInfo.processInfo.systemUptime]
        if let detail { row["detail"] = String(detail.prefix(256)) }
        if let currentSession { row["session"] = currentSession }
        transitions.append(row)
        if transitions.count > 64 { transitions.removeFirst(transitions.count - 64) }
    }

    private func record() {
        if state != observedState { trace("stateChanged", detail: state); observedState = state }
        var result: [String: Any] = ["state": state, "videoHidden": video.isHidden,
            "orientation": UIDevice.current.orientation.rawValue, "viewWidth": video.bounds.width,
            "viewHeight": video.bounds.height, "mediaStatistics": latestStatistics,
            "connectionState": connectionState, "iceState": iceState,
            "idleTimerDisabled": UIApplication.shared.isIdleTimerDisabled,
            "reconnectCount": reconnectCount,
            "automaticRetryCount": automaticRetryCount,
            "userStopCount": userStopCount,
            "retryScheduled": retryAt != nil,
            "transitionLog": transitions,
            "resumeOnForeground": resumeOnForeground,
            "reconnectPending": pendingReconnect != nil,
            "networkPolicy": "local network; VPN and cellular adapters excluded"]
        if let currentSession { result["session"] = currentSession }
        if currentSession != nil, (sink?.count ?? 0) > 0 {
            result["lastFrameAgeSeconds"] = ProcessInfo.processInfo.systemUptime - lastPresentedAt
        }
        // One paired-device file read carries both diagnostics and resume intent.
        // The relay applies the same session, generation, and expiry checks.
        if let request = pendingReconnect, let offer = resumeOffer {
            result["reconnectRequest"] = ["request": request, "previousSession": offer.session,
                "generation": offer.generation, "expiresAt": offer.expiresAt] as [String: Any]
        }
        if let sink { result["frames"] = sink.summary() }
        label.text = "\(state)\nDecoded frames: \(sink?.count ?? 0)"
        label.accessibilityValue = currentSession ?? "none"
        writeProbeStatus(result, to: statusURL)
    }
}
