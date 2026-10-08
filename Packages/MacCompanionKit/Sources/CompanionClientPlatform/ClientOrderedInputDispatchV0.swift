import CompanionInteractiveWire
import Foundation

package enum ClientOrderedInputDispatchErrorV0: Error { case queueFull, inactive }

/// Queue only unsequenced gestures. The reliable sender owns every byte once
/// dispatch begins. Adjacent cursor positions are the only replaceable inputs.
@MainActor
package final class ClientOrderedInputDispatchV0 {
    private let send: @MainActor ([InteractiveInputPayload]) async throws -> Void
    private let failure: @MainActor (any Error) -> Void
    private var pending: [InteractiveInputPayload] = []
    private var worker: Task<Void, Never>?
    private var active = false
    private var generation: UInt64 = 0
    private var lastMove: ContinuousClock.Instant?
    private var lastDispatch: ContinuousClock.Instant?
    private var terminalError: (any Error)?

    package init(send: @escaping @MainActor ([InteractiveInputPayload]) async throws -> Void,
                 failure: @escaping @MainActor (any Error) -> Void) {
        self.send = send; self.failure = failure
    }

    package func setActive(_ value: Bool) {
        guard active != value else { return }
        active = value
        if value { terminalError = nil }
        if !value { generation &+= 1; pending.removeAll(keepingCapacity: true) }
    }

    package func submit(_ payloads: [InteractiveInputPayload]) {
        guard active else { return }
        for payload in payloads {
            if payload.kind == .pointerMove, pending.last?.kind == .pointerMove {
                pending[pending.count - 1] = payload
            } else {
                guard pending.count < 256 else {
                    terminalError = ClientOrderedInputDispatchErrorV0.queueFull
                    setActive(false); failure(ClientOrderedInputDispatchErrorV0.queueFull); return
                }
                pending.append(payload)
            }
        }
        startWorker()
    }

    package func submitAndDrain(_ payloads: [InteractiveInputPayload]) async throws {
        guard active else { throw ClientOrderedInputDispatchErrorV0.inactive }
        let admittedGeneration = generation
        submit(payloads)
        await worker?.value
        if let terminalError { throw terminalError }
        guard active, generation == admittedGeneration else { throw ClientOrderedInputDispatchErrorV0.inactive }
    }

    package func fenceAndDrain() async {
        setActive(false)
        await worker?.value
    }

    package func close() {
        setActive(false)
        worker?.cancel()
    }

    private func startWorker() {
        guard worker == nil, active, !pending.isEmpty else { return }
        let admittedGeneration = generation
        worker = Task { [weak self] in
            guard let self else { return }
            defer {
                self.worker = nil
                self.startWorker()
            }
            while self.active, self.generation == admittedGeneration, !Task.isCancelled,
                  let next = self.pending.first {
                // Stay below 120 moves/s; select the latest pending position
                // after this wait, before assigning a reliable sequence.
                var earliest = self.lastDispatch?.advanced(by: .microseconds(4_500))
                if next.kind == .pointerMove, let last = self.lastMove {
                    let moveDeadline = last.advanced(by: .milliseconds(9))
                    earliest = earliest.map { max($0, moveDeadline) } ?? moveDeadline
                }
                if let earliest {
                    do { try await Task.sleep(until: earliest, clock: .continuous) }
                    catch { return }
                }
                guard self.active, self.generation == admittedGeneration,
                      !Task.isCancelled, !self.pending.isEmpty else { return }
                let payload = self.pending.removeFirst()
                self.lastDispatch = .now
                if payload.kind == .pointerMove { self.lastMove = .now }
                do { try await self.send([payload]) }
                catch {
                    guard self.active, self.generation == admittedGeneration, !Task.isCancelled else { return }
                    self.terminalError = error
                    self.setActive(false)
                    self.failure(error)
                    return
                }
            }
        }
    }
}
