#if os(visionOS) && MACCOMPANION_VNC_DEVELOPMENT
import Foundation
import SwiftUI

@MainActor enum VisionDevelopmentQA {
    static let defaults: UserDefaults = {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--vision-qa-empty-library") {
            return UserDefaults(suiteName: "vision-qa-" + UUID().uuidString)!
        }
        #endif
        return .standard
    }()
    static func makeCloud() -> DirectCloudSyncV1 {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--vision-qa-empty-library") {
            return DirectCloudSyncV1(defaults: defaults,
                url: FileManager.default.temporaryDirectory.appending(path: "vision-qa-cloud-" + UUID().uuidString + ".json"),
                writerID: UUID())
        }
        #endif
        return .shared
    }
    static var compactLargeText: Bool {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains("--vision-qa-empty-library") && arguments.contains("--vision-qa-compact-large-text")
        #else
        return false
        #endif
    }
    static var sshPort: Int {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--vision-qa-empty-library"),
           let index = arguments.firstIndex(of: "--vision-qa-ssh-port"), index + 1 < arguments.count,
           let port = Int(arguments[index + 1]), (1...65535).contains(port) { return port }
        #endif
        return 22
    }
    static var libraryURL: URL? {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--vision-qa-empty-library") {
            let url = FileManager.default.temporaryDirectory.appending(path: "vision-qa-" + UUID().uuidString, directoryHint: .isDirectory)
                .appending(path: "direct-macs-v1.json")
            if ProcessInfo.processInfo.arguments.contains("--vision-qa-multiple-macs") {
                let library = DirectMacLibraryV1(url: url, removeLogin: { _ in })
                _ = library.save(id: nil, name: "Synthetic First Mac", addresses: ["127.0.0.1"])
                _ = library.save(id: nil, name: "Synthetic Second Mac", addresses: ["127.0.0.2"])
            }
            return url
        }
        #endif
        return nil
    }
}
struct VisionQALayout: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        if VisionDevelopmentQA.compactLargeText { content.dynamicTypeSize(.accessibility2) }
        else { content }
    }
}
#endif
