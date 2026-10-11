#if os(visionOS) && MACCOMPANION_VNC_DEVELOPMENT
import Foundation

/// The window installs this receiver before SSH starts. Presentation timing
/// cannot lose output or move it into a replacement shell.
@MainActor final class VisionTerminalOutput {
    private weak var session: DirectTerminalSession?
    private var generation: UUID
    private var pending: [UInt8] = []
    private var receiver: (@MainActor ([UInt8]) -> Void)?
    private var attachment: UUID?
    var pendingByteCount: Int { pending.count }
    init(session: DirectTerminalSession) {
        self.session = session; generation = session.outputGeneration
        session.received = { [weak self] in self?.receive($0) }
    }
    private func retireOldGeneration() {
        guard let session, generation != session.outputGeneration else { return }
        generation = session.outputGeneration; pending.removeAll(keepingCapacity: false)
        receiver = nil; attachment = nil
    }
    private func receive(_ bytes: [UInt8]) {
        retireOldGeneration()
        if let receiver { receiver(bytes); return }
        guard bytes.count <= DirectTerminalSession.maximumPausedOutputBytes - pending.count else {
            pending.removeAll(keepingCapacity: false); session?.failNativeInputAdmission(); return
        }
        pending.append(contentsOf: bytes)
    }
    @discardableResult func attach(_ receiver: @escaping @MainActor ([UInt8]) -> Void) -> UUID {
        retireOldGeneration()
        let token = UUID(); attachment = token; self.receiver = receiver
        let bytes = pending; pending.removeAll(keepingCapacity: false)
        if !bytes.isEmpty { receiver(bytes) }
        return token
    }
    func detach(_ token: UUID) {
        guard attachment == token else { return }
        attachment = nil; receiver = nil; pending.removeAll(keepingCapacity: false)
    }
    func owns(_ token: UUID) -> Bool { attachment == token && session?.outputGeneration == generation }
}
#endif
