#if (os(iOS) || os(macOS)) && MACCOMPANION_VNC_DEVELOPMENT
import SwiftUI
import UniformTypeIdentifiers
#if os(iOS)
import UIKit
struct DirectFilesDocumentPicker: UIViewControllerRepresentable {
    var exporting: URL?
    let completion: @MainActor (Result<[URL], Error>) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(completion: completion) }
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = exporting.map { UIDocumentPickerViewController(forExporting: [$0], asCopy: true) }
            ?? UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: false)
        picker.allowsMultipleSelection = exporting == nil
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let completion: @MainActor (Result<[URL], Error>) -> Void
        init(completion: @escaping @MainActor (Result<[URL], Error>) -> Void) { self.completion = completion }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { completion(.success(urls)) }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { completion(.failure(CancellationError())) }
    }
}
#else
import AppKit
private final class FilesExportLease: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    func check() throws { lock.lock(); defer { lock.unlock() }; if cancelled { throw CancellationError() } }
}
@MainActor final class DirectFilesMacPicker {
    private var panel: NSSavePanel?
    private var lease: FilesExportLease?
    func cancel() { lease?.cancel(); lease = nil; panel?.cancel(nil); panel = nil }
    func save(_ source: URL, completion: @escaping @MainActor (Result<Void, Error>) -> Void) {
        cancel()
        let lease = FilesExportLease(); self.lease = lease
        let panel = NSSavePanel(); panel.nameFieldStringValue = source.lastPathComponent
        self.panel = panel
        panel.canCreateDirectories = true
        panel.begin { [weak self] response in
            guard let self, self.lease === lease, response == .OK, let target = panel.url, DirectAppLockV1.shared.canAccess else { completion(.failure(CancellationError())); return }
            self.panel = nil
            Task {
                let result = await Task.detached {
                    try lease.check()
                    let access = target.startAccessingSecurityScopedResource()
                    defer { if access { target.stopAccessingSecurityScopedResource() } }
                    var error: NSError?, outcome: Result<Void, Error> = .failure(DirectFilesFailure.unavailable)
                    NSFileCoordinator().coordinate(writingItemAt: target, options: .forReplacing, error: &error) { url in
                        outcome = Result {
                            // Stage beside the chosen destination, preserving the private download for another Save.
                            let temporary = url.deletingLastPathComponent().appendingPathComponent(".maccompanion-save-" + UUID().uuidString)
                            guard FileManager.default.createFile(atPath: temporary.path, contents: nil, attributes: [.posixPermissions: 0o600]) else { throw DirectFilesFailure.unavailable }
                            defer { try? FileManager.default.removeItem(at: temporary) }
                            let input = try FileHandle(forReadingFrom: source), output = try FileHandle(forWritingTo: temporary)
                            defer { try? input.close(); try? output.close() }
                            while true {
                                try lease.check()
                                let bytes = try input.read(upToCount: DirectFilesPolicy.chunkSize) ?? Data()
                                if bytes.isEmpty { break }
                                try output.write(contentsOf: bytes)
                            }
                            try output.synchronize(); try output.close(); try lease.check()
                            if FileManager.default.fileExists(atPath: url.path) { _ = try FileManager.default.replaceItemAt(url, withItemAt: temporary, backupItemName: nil, options: [.usingNewMetadataOnly]) }
                            else { try FileManager.default.moveItem(at: temporary, to: url) }
                        }
                    }
                    if let error { throw error }; try outcome.get()
                }.result
                guard self.lease === lease, DirectAppLockV1.shared.canAccess else { completion(.failure(CancellationError())); return }
                self.lease = nil
                completion(result)
            }
        }
    }
}
#endif
#endif
