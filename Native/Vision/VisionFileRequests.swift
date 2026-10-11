#if os(visionOS) && MACCOMPANION_VNC_DEVELOPMENT
import SwiftUI
import UniformTypeIdentifiers

/// The identity belongs to one system presentation, not the form's current state.
struct VisionFileRequest: Identifiable, Equatable {
    let id = UUID()
    let generation: UUID
}

@MainActor @Observable final class VisionFileRequests {
    private(set) var current: VisionFileRequest?
    var scenePhase: ScenePhase = .inactive

    @discardableResult func begin(generation: UUID) -> VisionFileRequest {
        let request = VisionFileRequest(generation: generation)
        current = request
        return request
    }
    func invalidate() { current = nil }

    func completion<Value>(for request: VisionFileRequest,
                           generation: @escaping () -> UUID,
                           available: @escaping () -> Bool,
                           receive: @escaping (Result<Value, Error>) -> Void) -> (Result<Value, Error>) -> Void {
        return { [weak self] result in
            guard let self, self.current == request else { return }
            // Consume even a denied completion, so reactivation cannot replay it.
            self.current = nil
            guard request.generation == generation(), self.scenePhase == .active, available() else { return }
            receive(result)
        }
    }
}

/// Parents key these hosts by request.id. An old system callback therefore keeps
/// its original completion even when another presentation replaces it.
struct VisionKeyFileImporter: View {
    let completion: (Result<URL, Error>) -> Void
    @State private var presented = false
    var body: some View {
        Color.clear.frame(width: 0, height: 0)
            .fileImporter(isPresented: $presented, allowedContentTypes: [.data, .plainText], onCompletion: completion)
            .onAppear { presented = true }
    }
}

struct VisionKeyFileExporter: View {
    let document: SSHKeyDocument
    let filename: String
    let completion: (Result<URL, Error>) -> Void
    @State private var presented = false
    var body: some View {
        Color.clear.frame(width: 0, height: 0)
            .fileExporter(isPresented: $presented, document: document, contentType: .data, defaultFilename: filename, onCompletion: completion)
            .onAppear { presented = true }
    }
}
#endif
