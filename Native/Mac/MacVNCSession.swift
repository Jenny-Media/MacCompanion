#if os(macOS) && MACCOMPANION_VNC_DEVELOPMENT
import AppKit
import Observation

struct MacVNCDisplay: Identifiable {
    let id: UInt32
    let normalized: CGRect
}

@MainActor @Observable final class MacVNCSession {
    let mac: DirectMacRecordV1
    let inputOnly: Bool
    private(set) var image: NSImage?
    private(set) var connected = false
    private(set) var connecting = false
    private(set) var status = "Sign in to Screen Sharing"
    private(set) var framebuffer = CGSize.zero
    private(set) var displays: [MacVNCDisplay] = []
    private(set) var layoutAspect: CGFloat = 0
    private(set) var recovery: DirectRecoveryNotice?
    private(set) var cursorImage: NSImage?
    private(set) var cursorHotspot = CGPoint.zero
    var selectedID: UInt32?
    var zoom: CGFloat = 1
    var pan = CGPoint.zero
    var trackpad: Bool
    var pointerSpeed: Double
    var followCursor: Bool
    var cursorPosition = CGPoint.zero
    var resetInput: (() -> Void)?
    private var transport: CompanionVNCSession?
    private var generation = UUID()
    private var closed = false
    private var pendingLogin: DesktopCredentialStoreV1.Login?
    private let removeSavedLogin: (UUID) throws -> Void
    private let makeTransport: () -> CompanionVNCSession
    private let canAccess: () -> Bool
    init(mac: DirectMacRecordV1, inputOnly: Bool, removeSavedLogin: @escaping (UUID) throws -> Void = DesktopCredentialStoreV1.remove,
         makeTransport: @escaping () -> CompanionVNCSession = { CompanionVNCSession() },
         canAccess: @escaping () -> Bool = { DirectAppLockV1.shared.canAccess }) {
        self.mac = mac; self.inputOnly = inputOnly
        self.removeSavedLogin = removeSavedLogin
        self.makeTransport = makeTransport
        self.canAccess = canAccess
        selectedID = VNCSessionPreferences.display(mac.id)?.uint32Value
        trackpad = inputOnly || VNCSessionPreferences.trackpad(mac.id)
        pointerSpeed = VNCSessionPreferences.speed(mac.id)
        followCursor = VNCSessionPreferences.followCursor(mac.id)
    }
    var canInput: Bool { connected && !closed && canAccess() && transport?.connected == true }
    var crop: CGRect {
        let full = CGRect(origin: .zero, size: framebuffer)
        guard framebuffer.height > 0, layoutAspect > 0,
              abs(framebuffer.width / framebuffer.height - layoutAspect) / layoutAspect < 0.03,
              let selectedID, let display = displays.first(where: { $0.id == selectedID }) else { return full }
        let rect = display.normalized
        return CGRect(x: round(rect.minX * framebuffer.width), y: round(rect.minY * framebuffer.height),
                      width: round(rect.maxX * framebuffer.width) - round(rect.minX * framebuffer.width),
                      height: round(rect.maxY * framebuffer.height) - round(rect.minY * framebuffer.height))
    }
    func connect(username: String, password: String, remember: Bool) {
        guard !closed, !connecting, canAccess(), !username.isEmpty, !password.isEmpty else { return }
        do { try MacLoginPolicy.prepareVNC(username: username, password: password, remember: remember, macID: mac.id, remove: removeSavedLogin) }
        catch MacLoginPolicy.Failure.invalidLogin {
            recovery = .make(.loginRejected, message: "Enter a Mac account and password of 1–63 UTF-8 bytes per field, with no NUL characters."); return
        } catch {
            recovery = .make(.removeFailed, message: "The old saved Desktop login couldn’t be removed. This connection wasn’t started. Retry when local Keychain is available."); return
        }
        retire(); let token = UUID(); generation = token
        let next = makeTransport(); transport = next; next.inputOnly = inputOnly
        connecting = true; recovery = nil; status = "Connecting…"
        pendingLogin = remember ? .init(username: username, password: password) : nil
        next.frameHandler = { [weak self, weak next] image in
            MainActor.assumeIsolated {
                guard let self, let next, self.transport === next, self.generation == token, !self.closed else { return }
                self.image = image
            }
        }
        next.cursorHandler = { [weak self, weak next] image, hotspot, position, known in
            MainActor.assumeIsolated {
                guard let self, let next, self.transport === next, self.generation == token, !self.closed else { return }
                self.cursorImage = image; self.cursorHotspot = hotspot
                if known { self.cursorPosition = position }
            }
        }
        next.displayLayoutHandler = { [weak self, weak next] value in
            MainActor.assumeIsolated {
                guard let self, let next, self.transport === next, self.generation == token, !self.closed,
                      let value else { return }
                self.layoutAspect = (value["aspectRatio"] as? NSNumber)?.doubleValue ?? 0
                self.displays = (value["views"] as? [[String: Any]] ?? []).compactMap { row in
                    guard let id = row["id"] as? NSNumber, let x = row["x"] as? NSNumber, let y = row["y"] as? NSNumber,
                          let width = row["width"] as? NSNumber, let height = row["height"] as? NSNumber else { return nil }
                    return .init(id: id.uint32Value, normalized: CGRect(x: x.doubleValue, y: y.doubleValue, width: width.doubleValue, height: height.doubleValue))
                }
                if let selected = self.selectedID, !self.displays.isEmpty, !self.displays.contains(where: { $0.id == selected }) { self.selectDisplay(nil) }
                self.resetInput?(); self.fit()
            }
        }
        next.stateHandler = { [weak self, weak next] state, counters in
            MainActor.assumeIsolated {
                guard let self, let next, self.transport === next, self.generation == token, !self.closed else { return }
                self.status = state ?? "Connection ended"
                self.framebuffer = CGSize(width: (counters?["framebufferWidth"] as? NSNumber)?.doubleValue ?? 0,
                                          height: (counters?["framebufferHeight"] as? NSNumber)?.doubleValue ?? 0)
                if state == "Connected" {
                    let first = !self.connected
                    guard !first || self.canAccess() else { self.disconnect(); return }
                    self.connected = true; self.connecting = false
                    if first {
                        self.cursorPosition = CGPoint(x: self.crop.midX, y: self.crop.midY)
                        if let login = self.pendingLogin {
                            self.pendingLogin = nil
                            do { try DesktopCredentialStoreV1.save(login, hostID: self.mac.id) }
                            catch { self.recovery = .make(.saveFailed, message: "Connected, but the login couldn’t be saved on this Mac.") }
                        }
                    }
                } else if !next.running {
                    self.resetInput?(); self.connected = false; self.connecting = false; self.image = nil
                    self.pendingLogin = nil
                    self.recovery = .make(.desktopDisconnected, message: self.status)
                }
            }
        }
        next.connectAddresses(mac.addresses, port: mac.port, username: username, password: password)
    }
    func selectDisplay(_ id: UInt32?) {
        resetInput?(); selectedID = id; VNCSessionPreferences.setDisplay(id.map(NSNumber.init(value:)), mac: mac.id)
        cursorPosition = CGPoint(x: crop.midX, y: crop.midY); fit(); transport?.viewChanged()
    }
    func fit() { zoom = 1; pan = .zero }
    func keys(_ events: [MacVNCKeyEvent]) {
        guard canInput, !events.isEmpty else { return }
        if transport?.tryKeyEvents(events.map(\.dictionary)) != true { inputAdmissionFailed() }
    }
    func releaseKeys(_ events: [MacVNCKeyEvent]) {
        guard transport?.connected == true else { return }
        let releases = events.filter { !$0.down }
        if !releases.isEmpty, transport?.tryKeyEvents(releases.map(\.dictionary)) != true { inputAdmissionFailed() }
    }
    func releasePointer() {
        guard transport?.connected == true else { return }
        transport?.pointerX(Int(cursorPosition.x), y: Int(cursorPosition.y), mask: 0)
    }
    func reloadPreferences() {
        pointerSpeed = VNCSessionPreferences.speed(mac.id)
        followCursor = VNCSessionPreferences.followCursor(mac.id)
    }
    func quickAction(_ action: VNCQuickAction) {
        let mode: DirectControlMode = inputOnly ? .trackpad : .desktop
        guard canInput, action.enabled, action.valid, action.compatible(with: mode) else { return }
        if [.shortcut, .text].contains(action.kind), !DirectProAccess.shared.hasPro { return }
        resetInput?()
        switch action.kind {
        case .mode: trackpad.toggle(); VNCSessionPreferences.setTrackpad(trackpad, mac: mac.id)
        case .fit: fit()
        case .rightClick: pointer(cursorPosition, mask: 4); pointer(cursorPosition, mask: 0)
        case .text: text(action.text)
        case .shortcut:
            keys(action.modifiers.map { .init(key: $0, down: true) }
                 + [.init(key: action.key, down: true), .init(key: action.key, down: false)]
                 + action.modifiers.reversed().map { .init(key: $0, down: false) })
        case .escape, .tab, .returnKey:
            let key: UInt32 = action.kind == .escape ? 0xff1b : action.kind == .tab ? 0xff09 : 0xff0d
            keys([.init(key: key, down: true), .init(key: key, down: false)])
        default: break
        }
    }
    func pointer(_ point: CGPoint, mask: Int) {
        guard canInput else { return }
        let admitted = CGPoint(x: max(crop.minX, min(crop.maxX - 1, point.x)), y: max(crop.minY, min(crop.maxY - 1, point.y)))
        cursorPosition = admitted
        transport?.pointerX(Int(admitted.x), y: Int(admitted.y), mask: mask)
    }
    func text(_ text: String) {
        guard canInput else { return }
        let keyboard = CompanionVNCKeyboard { [weak self] events in
            MainActor.assumeIsolated {
                guard let self, self.canInput else { return }
                if self.transport?.tryKeyEvents(events ?? []) != true { self.inputAdmissionFailed() }
            }
        }
        keyboard.text(text)
    }
    func disconnect() { retire(); status = "Disconnected" }
    func pauseInput() {
        resetInput?()
        // Retire an unfinished login before it can save credentials while the
        // Mac is locked. A connected background window may keep receiving.
        if connecting { disconnect() }
    }
    func close() { guard !closed else { return }; retire(); closed = true }
    private func retire() {
        resetInput?(); generation = UUID()
        transport?.frameHandler = nil; transport?.cursorHandler = nil
        transport?.stateHandler = nil; transport?.displayLayoutHandler = nil
        transport?.stop(); transport = nil
        connected = false; connecting = false; image = nil; framebuffer = .zero; cursorImage = nil; pendingLogin = nil
        displays = []; layoutAspect = 0; fit()
    }
    private func inputAdmissionFailed() {
        // Disconnect before clearing the view's keyboard state so a failed
        // release cannot recursively submit to an already full queue. The
        // transport owns balanced remote key/button teardown.
        let owner = transport; transport = nil; generation = UUID()
        owner?.frameHandler = nil; owner?.cursorHandler = nil
        owner?.stateHandler = nil; owner?.displayLayoutHandler = nil; owner?.stop()
        connected = false; connecting = false; image = nil; pendingLogin = nil
        resetInput?(); recovery = .make(.inputPaused); status = "Input paused. Reconnect to continue."
    }
}
#endif
