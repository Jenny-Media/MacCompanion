#if (os(iOS) || os(macOS)) && MACCOMPANION_VNC_DEVELOPMENT
import Foundation

struct DirectFilesEntry: Identifiable, Equatable, Sendable {
    enum Kind: Sendable { case folder, file, other }
    var id: String { name }
    let name: String
    let kind: Kind
    let size: UInt64?
    var symbol: String { kind == .folder ? "folder.fill" : kind == .file ? "doc" : "link" }
}
struct DirectFilesDirectory: Sendable {
    let path: String
    let entries: [DirectFilesEntry]
}
struct DirectFilesAttributes: Sendable {
    let kind: DirectFilesEntry.Kind
    let size: UInt64?
}
enum DirectFilesFailure: LocalizedError {
    case invalidName, invalidPath, notRegular, tooManyFiles, changedFile, unsupportedReplace, interrupted, unavailable, timedOut, pendingTransfers
    var errorDescription: String? {
        switch self {
        case .invalidName: "Use a filename without slashes or control characters, up to 255 UTF-8 bytes."
        case .invalidPath: "This folder path is unavailable. Return to Home and try again."
        case .notRegular: "Choose individual files. Folder transfers, links and special files are not supported yet."
        case .tooManyFiles: "Choose up to 32 files at a time."
        case .changedFile: "The file changed during transfer. Review it and retry."
        case .unsupportedReplace: "This server cannot safely replace files. Choose Keep Both instead."
        case .interrupted: "Transfer interrupted. Review the result before retrying."
        case .unavailable: "The Files connection is unavailable. Reconnect to continue."
        case .timedOut: "The Mac stopped responding. Reconnect and retry when it is reachable."
        case .pendingTransfers: "Save your downloads, retry unfinished files, or discard pending transfers before starting another transfer."
        }
    }
}
enum DirectFilesExitIntent { case disconnect, close }
enum DirectFilesPolicy {
    static let chunkSize = 32_768
    static let maximumBatch = 32
    static func validName(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".." && name.utf8.count <= 255 && !name.contains("/") &&
        !name.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
    }
    static func validPath(_ path: String) -> Bool {
        path.hasPrefix("/") && path.utf8.count <= 4096 && !path.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
    }
    static func child(_ name: String, of path: String) throws -> String {
        guard validName(name) else { throw DirectFilesFailure.invalidName }
        let result = (path == "/" ? "" : path) + "/" + name
        guard validPath(result) else { throw DirectFilesFailure.invalidPath }
        return result
    }
    static func parent(_ path: String) -> String { (path as NSString).deletingLastPathComponent.isEmpty ? "/" : (path as NSString).deletingLastPathComponent }
    static func duplicateName(_ name: String, number: Int) -> String {
        let url = URL(fileURLWithPath: name), ext = url.pathExtension
        let stem = ext.isEmpty ? name : url.deletingPathExtension().lastPathComponent
        return stem + " (\(number))" + (ext.isEmpty ? "" : "." + ext)
    }
}
#endif
