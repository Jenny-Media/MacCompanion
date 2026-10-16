#if os(visionOS) && MACCOMPANION_VNC_DEVELOPMENT
import Foundation
import Observation
import UIKit

/// One owner per native window. Never accepts a raw Screen Sharing socket.
@MainActor @Observable final class VisionDesktopSession {
    struct Display: Identifiable { let id: UInt32; let rect: CGRect }
    let mac: DirectMacRecordV1
    private(set) var image: UIImage?
    private(set) var cursor: UIImage?
    private(set) var cursorHotspot = CGPoint.zero
    private(set) var cursorPosition = CGPoint.zero
    private(set) var framebuffer = CGSize.zero
    private(set) var displays: [Display] = []
    private(set) var connected = false
    private(set) var connecting = false
    private(set) var suspended = false
    private(set) var status = "Sign in to Screen Sharing over SSH"
    var recovery: DirectRecoveryNotice?
    var trust: DirectTerminalSession.TrustRequest?
    var zoom: CGFloat = 1
    var pan = CGPoint.zero
    private(set) var selectedID: UInt32?
    var inputAvailable: @MainActor () -> Bool = { false }
    var resetInput: (@MainActor () -> Void)?
    var invalidatePhysicalPresses: (@MainActor () -> Void)?
    var clearComposition: (@MainActor () -> Void)?
    private var layoutAspect: Double = 0
    private var generation = UUID()
    private var transport: CompanionVNCSession?
    private var tunnel: DirectDesktopSSHTunnel?
    private var work: Task<Void, Never>?
    private var trustReply: CheckedContinuation<Bool, Never>?
    private var held = VisionHeldInput()
    private var wheelDistance = VisionScrollDistance()
    private var nativeScroll = false
    private(set) var inputGeneration = UUID()
    private var pendingLogin: DesktopCredentialStoreV1.Login?
    private(set) var closed = false
    @ObservationIgnored private var removalObserver: DirectMacRemovalObservation?
    init(mac: DirectMacRecordV1, libraryURL: URL = DirectMacLibraryV1.defaultURL) {
        self.mac = mac; selectedID = VNCSessionPreferences.display(mac.id)?.uint32Value
        removalObserver = DirectMacRemovalObservation(macID: mac.id, libraryURL: libraryURL) { [weak self] in
            self?.close()
            self?.status = "Mac removed"
        }
    }
    var canInput: Bool { !closed && !suspended && connected && transport?.connected == true && inputAvailable() && DirectAppLockV1.shared.canAccess }
    var pointerHeld: Bool { held.buttons != 0 }
    var crop: CGRect {
        let full = CGRect(origin: .zero, size: framebuffer)
        guard framebuffer.height > 0, layoutAspect > 0,
              abs(framebuffer.width / framebuffer.height - layoutAspect) / layoutAspect < 0.03,
              let selectedID, let display = displays.first(where: { $0.id == selectedID }) else { return full }
        let rect = display.rect
        return CGRect(x: round(rect.minX * framebuffer.width), y: round(rect.minY * framebuffer.height),
                      width: round(rect.maxX * framebuffer.width) - round(rect.minX * framebuffer.width),
                      height: round(rect.maxY * framebuffer.height) - round(rect.minY * framebuffer.height))
    }
    func connect(username: String, password: String, remember: Bool) {
        guard !closed, !connecting, !connected, DirectAppLockV1.shared.canAccess else { return }
        guard !username.isEmpty, !password.isEmpty, username.utf8.count <= 63, password.utf8.count <= 63,
              !username.contains("\0"), !password.contains("\0") else {
            recovery = .make(.loginRejected, message: "Enter a Mac account and password of 1–63 UTF-8 bytes each, with no NUL characters."); return
        }
        do { if !remember { try DesktopCredentialStoreV1.remove(mac.id) } }
        catch { recovery = .make(.removeFailed); return }
        retire(); let token = generation
        let next = CompanionVNCSession(); transport = next
        connecting = true; recovery = nil; status = "Opening encrypted connection…"
        pendingLogin = remember ? .init(username: username, password: password) : nil
        next.frameHandler = { [weak self, weak next] image in
            MainActor.assumeIsolated {
                guard let self, let next, self.transport === next, self.generation == token, !self.suspended else { return }
                self.image = image
            }
        }
        next.cursorHandler = { [weak self, weak next] image, hotspot, position, known in
            MainActor.assumeIsolated {
                guard let self, let next, self.transport === next, self.generation == token, !self.suspended else { return }
                self.cursor = image; self.cursorHotspot = hotspot
                if known { self.cursorPosition = position }
            }
        }
        next.displayLayoutHandler = { [weak self, weak next] layout in
            MainActor.assumeIsolated {
                guard let self, let next, self.transport === next, self.generation == token, let layout else { return }
                self.releaseInput()
                self.layoutAspect = (layout["aspectRatio"] as? NSNumber)?.doubleValue ?? 0
                self.displays = (layout["views"] as? [[String: Any]] ?? []).compactMap { row in
                    guard let id = row["id"] as? NSNumber, let x = row["x"] as? NSNumber, let y = row["y"] as? NSNumber,
                          let w = row["width"] as? NSNumber, let h = row["height"] as? NSNumber else { return nil }
                    let rect = CGRect(x: x.doubleValue, y: y.doubleValue, width: w.doubleValue, height: h.doubleValue)
                    guard [rect.minX, rect.minY, rect.width, rect.height].allSatisfy(\.isFinite),
                          rect.width > 0, rect.height > 0, rect.minX >= 0, rect.minY >= 0, rect.maxX <= 1, rect.maxY <= 1 else { return nil }
                    return Display(id: id.uint32Value, rect: rect)
                }
                if let id = self.selectedID, !self.displays.contains(where: { $0.id == id }) { self.selectedID = nil }
                self.fit()
            }
        }
        next.stateHandler = { [weak self, weak next] state, counters in
            MainActor.assumeIsolated {
                guard let self, let next, self.transport === next, self.generation == token else { return }
                self.status = state ?? "Connection ended"
                let size = CGSize(width: (counters?["framebufferWidth"] as? NSNumber)?.doubleValue ?? 0,
                                  height: (counters?["framebufferHeight"] as? NSNumber)?.doubleValue ?? 0)
                if size != self.framebuffer { self.releaseInput(); self.framebuffer = size; self.fit() }
                if state == "Connected" {
                    guard DirectAppLockV1.shared.canAccess, !self.suspended else { self.disconnect(); return }
                    let first = !self.connected; self.connected = true; self.connecting = false
                    if first {
                        self.cursorPosition = CGPoint(x: self.crop.midX, y: self.crop.midY)
                        if let login = self.pendingLogin {
                            self.pendingLogin = nil
                            do { try DesktopCredentialStoreV1.save(login, hostID: self.mac.id) }
                            catch { self.recovery = .make(.saveFailed, message: "Connected, but the Screen Sharing login couldn’t be saved on this device.") }
                        }
                    }
                } else if !next.running {
                    let notice = DirectRecoveryNotice.make(.desktopDisconnected, message: self.status)
                    self.retire(); self.recovery = notice; self.status = notice.title
                }
            }
        }
        work = Task { [weak self] in
            guard let self else { return }
            do {
                let tunnel = try await DirectDesktopSSHTunnel.open(addresses: mac.addresses, sshPort: mac.sshPort,
                    screenSharingPort: mac.port, username: username, password: password,
                    validateHost: { [weak self] key in
                        guard let self, self.generation == token, DirectAppLockV1.shared.canAccess else { throw CancellationError() }
                        if let saved = try TerminalSecretStore.hostKey(self.mac.id) {
                            guard saved == key else { throw TerminalSecretStore.Failure.changedKey }; return
                        }
                        guard let fingerprint = TerminalSecretStore.fingerprint(key) else { throw TerminalSecretStore.Failure.rejectedKey }
                        self.trust = .init(fingerprint: fingerprint)
                        let accepted = await withCheckedContinuation { self.trustReply = $0 }
                        self.trust = nil
                        guard accepted, self.generation == token, DirectAppLockV1.shared.canAccess else { throw TerminalSecretStore.Failure.rejectedKey }
                        try TerminalSecretStore.approveHostKey(key, id: self.mac.id)
                    }, progress: { [weak self] progress in
                        guard let self, self.generation == token else { return }; self.status = progress
                    })
                guard self.generation == token, !Task.isCancelled, !self.suspended, DirectAppLockV1.shared.canAccess else {
                    await tunnel.close(); return
                }
                self.tunnel = tunnel
                let fd = tunnel.takeSocket()
                self.status = "Signing in to Screen Sharing…"
                next.connectSocket(fd, username: username, password: password)
            } catch {
                guard self.generation == token else { return }
                let reason = DirectTerminalSession.reason(for: error, keyLogin: false)
                self.retire(); self.recovery = .make(reason); self.status = self.recovery?.title ?? "Connection ended"
            }
        }
    }
    func answerTrust(_ accepted: Bool) {
        let reply = trustReply; trustReply = nil; trust = nil; reply?.resume(returning: accepted)
        if !accepted { disconnect() }
    }
    func fit() { invalidatePhysicalPresses?(); zoom = 1; pan = .zero }
    func selectDisplay(_ id: UInt32?) {
        releaseInput(); selectedID = id; fit(); transport?.viewChanged()
        VNCSessionPreferences.setDisplay(id.map(NSNumber.init(value:)), mac: mac.id)
    }
    func key(_ key: UInt32, down: Bool) {
        guard canInput else { return }
        if down { guard held.down(key) else { disconnect(); return } }
        else { guard held.up(key) else { return } }
        admit([["key": key, "down": down]])
    }
    func text(_ text: String) {
        guard canInput, text.utf8.count <= 16_384 else { return }
        let keyboard = CompanionVNCKeyboard { [weak self] events in
            MainActor.assumeIsolated { guard let self, self.canInput else { return }; self.admit(events ?? []) }
        }
        keyboard.text(text)
    }
    func pointer(_ point: CGPoint, mask: Int) {
        guard canInput, [point.x, point.y].allSatisfy(\.isFinite), crop.width > 0, crop.height > 0 else { return }
        cursorPosition = CGPoint(x: max(crop.minX, min(crop.maxX - 1, point.x)), y: max(crop.minY, min(crop.maxY - 1, point.y)))
        held.pointer(mask)
        transport?.pointerX(Int(cursorPosition.x), y: Int(cursorPosition.y), mask: mask)
    }
    func click(_ point: CGPoint, button: Int = 1) {
        guard canInput, [point.x, point.y].allSatisfy(\.isFinite), crop.width > 0, crop.height > 0 else { return }
        cursorPosition = CGPoint(x: max(crop.minX, min(crop.maxX - 1, point.x)), y: max(crop.minY, min(crop.maxY - 1, point.y)))
        if transport?.tryClickX(Int(cursorPosition.x), y: Int(cursorPosition.y), mask: button) != true {
            disconnect(); recovery = .make(.inputPaused)
        }
    }
    func scroll(_ point: CGPoint, dx: CGFloat, dy: CGFloat) {
        guard canInput, [point.x, point.y, dx, dy].allSatisfy(\.isFinite), abs(dx) <= 16_384, abs(dy) <= 16_384,
              !pointerHeld, crop.width > 0, crop.height > 0 else { return }
        let point = CGPoint(x: max(crop.minX, min(crop.maxX - 1, point.x)), y: max(crop.minY, min(crop.maxY - 1, point.y)))
        cursorPosition = point
        if transport?.nativeScrollingSupported == true {
            guard let updates = VisionNativeScroll.packets(dx: dx, dy: dy), !updates.isEmpty else { return }
            let token = inputGeneration
            if !nativeScroll {
                guard transport?.beginScrollX(Int(point.x), y: Int(point.y)) == true else { disconnect(); return }
                nativeScroll = true
            }
            for update in updates {
                guard inputGeneration == token, canInput, nativeScroll else { return }
                if transport?.changeScrollX(Double(update.x), y: Double(update.y)) != true {
                    disconnect(); recovery = .make(.inputPaused); return
                }
            }
            return
        }
        guard let pulses = wheelDistance.accumulate(dx: dx, dy: dy) else { return }
        // Each pulse is one atomic group; it never enters the held-button ledger.
        for (count, positive, negative) in [(pulses.vertical, VisionScrollDistance.positiveVertical, VisionScrollDistance.negativeVertical),
            (pulses.horizontal, VisionScrollDistance.positiveHorizontal, VisionScrollDistance.negativeHorizontal)] {
            for _ in 0..<abs(count) {
                guard transport?.tryClickX(Int(point.x), y: Int(point.y), mask: count > 0 ? positive : negative) == true else {
                    disconnect(); recovery = .make(.inputPaused); return
                }
            }
        }
    }
    /// Completes only this gesture, retaining physical keyboard modifiers.
    func finishGesture() {
        if held.buttons != 0 {
            held.pointer(0)
            transport?.pointerX(Int(cursorPosition.x), y: Int(cursorPosition.y), mask: 0)
        }
        finishScrolling()
    }
    /// Wheel completion cannot release a button owned by the drag recognizer.
    func finishScrolling() {
        if nativeScroll { transport?.endScroll(); nativeScroll = false }
        wheelDistance = .init()
    }
    func quickAction(_ action: VNCQuickAction) {
        guard canInput, action.enabled, action.valid, action.compatible(with: .desktop),
              action.kind != .rightClick,
              ![.shortcut, .text].contains(action.kind) || DirectProAccess.shared.hasPro else { return }
        releaseInput()
        switch action.kind {
        case .fit: fit()
        case .text: text(action.text)
        case .shortcut:
            admit(action.modifiers.map { ["key": $0, "down": true] }
                  + [["key": action.key, "down": true], ["key": action.key, "down": false]]
                  + action.modifiers.reversed().map { ["key": $0, "down": false] })
        case .escape, .tab, .returnKey:
            let key: UInt32 = action.kind == .escape ? 0xff1b : action.kind == .tab ? 0xff09 : 0xff0d
            admit([["key": key, "down": true], ["key": key, "down": false]])
        default: break
        }
    }
    private func admit(_ events: [[AnyHashable: Any]]) {
        if transport?.tryKeyEvents(events) != true { disconnect(); recovery = .make(.inputPaused) }
    }
    func releaseInput(discardComposition: Bool = true) {
        inputGeneration = UUID(); nativeScroll = false; wheelDistance = .init()
        let releases = held.release()
        if transport?.connected == true {
            if !releases.keys.isEmpty { admit(releases.keys.map { ["key": $0, "down": false] }) }
            if releases.pointer { transport?.pointerX(Int(cursorPosition.x), y: Int(cursorPosition.y), mask: 0) }
            transport?.cancelNativeGestures()
        }
        resetInput?()
        if discardComposition { clearComposition?() }
    }
    func pause() {
        releaseInput()
        if connecting { disconnect(); return }
        suspended = true; image = nil; cursor = nil
        transport?.pause(completion: {})
    }
    func resume() { guard !closed, connected, DirectAppLockV1.shared.canAccess else { return }; suspended = false; transport?.resume() }
    func disconnect() { retire(); status = "Disconnected" }
    func close() { guard !closed else { return }; retire(); closed = true }
    private func retire() {
        releaseInput(); generation = UUID()
        trustReply?.resume(returning: false); trustReply = nil; trust = nil
        work?.cancel(); work = nil
        let old = transport; transport = nil
        old?.frameHandler = nil; old?.stateHandler = nil; old?.cursorHandler = nil; old?.displayLayoutHandler = nil; old?.stop()
        let previousTunnel = tunnel; tunnel = nil; previousTunnel?.cancelReads()
        Task { await previousTunnel?.close() }
        connected = false; connecting = false; suspended = false; pendingLogin = nil
        image = nil; cursor = nil; framebuffer = .zero; displays = []; layoutAspect = 0; fit()
    }
}
#endif
