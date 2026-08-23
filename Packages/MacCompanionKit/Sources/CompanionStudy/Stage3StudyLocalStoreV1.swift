import Darwin
import Foundation

public enum Stage3StudyLocalStoreFaultPointV1:
    String,
    CaseIterable,
    Hashable,
    Sendable
{
    case afterTemporaryWrite
    case afterTemporarySync
    case beforeRename
    case afterRenameBeforeDirectorySync
    case afterDeleteBeforeDirectorySync
}

public enum Stage3StudyLocalStoreErrorV1: Error, Equatable, Sendable {
    case unsafeStorage
    case quotaExceeded
    case revisionConflict
    case noReport
    case stalePreview
    case invalidExportRequest
    case ioFailure
    case injectedFault(Stage3StudyLocalStoreFaultPointV1)
}

public enum Stage3StudyLocalCommitResultV1: Equatable, Sendable {
    case inserted
    case replaced
    case alreadyPresentExactReport
}

public enum Stage3StudyLocalDeleteResultV1: Equatable, Sendable {
    case deleted
    case alreadyAbsent
}

public protocol Stage3StudyReportPersistenceV1: Sendable {
    func currentReport() async throws -> Stage3StudyReportV1?

    func replaceAtomically(
        _ report: Stage3StudyReportV1,
        expectedCurrent: Stage3StudyReportV1?
    ) async throws -> Stage3StudyLocalCommitResultV1

    func deleteAtomically(
        expectedCurrent: Stage3StudyReportV1
    ) async throws -> Stage3StudyLocalDeleteResultV1
}

/// Stores exactly one canonical study report in an app-owned Application
/// Support subdirectory. The app composition remains responsible for choosing
/// a protected container and proving its Data Protection behavior.
public actor AtomicFileStage3StudyReportStoreV1:
    Stage3StudyReportPersistenceV1
{
    public static let reportFilename = "stage3-study-report.json"
    public static let maximumRecordBytes =
        Stage3StudyReportV1.maximumEncodedBytes + 1

    private let directory: URL
    private let reportURL: URL
    private let injectedFaults: Set<Stage3StudyLocalStoreFaultPointV1>
    private let fileManager: FileManager
    private let lockDescriptor: Int32

    public init(
        directory: URL,
        injectedFaults: Set<Stage3StudyLocalStoreFaultPointV1> = [],
        fileManager: FileManager = .default
    ) throws {
        guard directory.isFileURL else {
            throw Stage3StudyLocalStoreErrorV1.unsafeStorage
        }
        self.directory = directory.standardizedFileURL
        reportURL = self.directory.appendingPathComponent(
            Self.reportFilename,
            isDirectory: false
        )
        self.injectedFaults = injectedFaults
        self.fileManager = fileManager
        try Self.prepareDirectory(self.directory, fileManager: fileManager)

        let lockURL = self.directory.appendingPathComponent(
            ".lock",
            isDirectory: false
        )
        let descriptor = open(
            lockURL.path,
            O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW,
            0o600
        )
        guard descriptor >= 0, fchmod(descriptor, 0o600) == 0 else {
            if descriptor >= 0 { close(descriptor) }
            throw Stage3StudyLocalStoreErrorV1.ioFailure
        }
        lockDescriptor = descriptor
        do {
            try Self.withExclusiveLock(descriptor: descriptor) {
                try Self.recoverPendingFiles(
                    in: self.directory,
                    fileManager: fileManager
                )
                try Self.validateVisibleEntries(
                    in: self.directory,
                    reportURL: self.reportURL,
                    fileManager: fileManager
                )
            }
        } catch {
            close(descriptor)
            throw error
        }
    }

    deinit {
        close(lockDescriptor)
    }

    public func currentReport() async throws -> Stage3StudyReportV1? {
        try withExclusiveLock {
            try recoverAndValidate()
            return try loadReport()
        }
    }

    public func replaceAtomically(
        _ report: Stage3StudyReportV1,
        expectedCurrent: Stage3StudyReportV1?
    ) async throws -> Stage3StudyLocalCommitResultV1 {
        try withExclusiveLock {
            try recoverAndValidate()
            let current = try loadReport()
            if current == report { return .alreadyPresentExactReport }
            guard current == expectedCurrent else {
                throw Stage3StudyLocalStoreErrorV1.revisionConflict
            }
            if let current,
               current.studyCode != report.studyCode {
                throw Stage3StudyLocalStoreErrorV1.revisionConflict
            }

            let data = try Stage3StudyReportCodecV1.encode(report)
            guard data.count <= Self.maximumRecordBytes else {
                throw Stage3StudyLocalStoreErrorV1.quotaExceeded
            }
            let temporary = directory.appendingPathComponent(
                ".pending-\(UUID().uuidString.lowercased())",
                isDirectory: false
            )
            do {
                try data.write(to: temporary, options: .withoutOverwriting)
                try fileManager.setAttributes(
                    [.posixPermissions: 0o600],
                    ofItemAtPath: temporary.path
                )
                try inject(.afterTemporaryWrite)
                try Self.synchronizeFile(temporary)
                try inject(.afterTemporarySync)
                try inject(.beforeRename)
                guard Darwin.rename(temporary.path, reportURL.path) == 0 else {
                    throw Stage3StudyLocalStoreErrorV1.ioFailure
                }
                try inject(.afterRenameBeforeDirectorySync)
                try Self.synchronizeDirectory(directory)
                return current == nil ? .inserted : .replaced
            } catch {
                if fileManager.fileExists(atPath: temporary.path) {
                    try? fileManager.removeItem(at: temporary)
                }
                throw error
            }
        }
    }

    public func deleteAtomically(
        expectedCurrent: Stage3StudyReportV1
    ) async throws -> Stage3StudyLocalDeleteResultV1 {
        try withExclusiveLock {
            try recoverAndValidate()
            guard let current = try loadReport() else {
                return .alreadyAbsent
            }
            guard current == expectedCurrent else {
                throw Stage3StudyLocalStoreErrorV1.revisionConflict
            }
            guard Darwin.unlink(reportURL.path) == 0 else {
                throw Stage3StudyLocalStoreErrorV1.ioFailure
            }
            try inject(.afterDeleteBeforeDirectorySync)
            try Self.synchronizeDirectory(directory)
            return .deleted
        }
    }

    private func recoverAndValidate() throws {
        try Self.recoverPendingFiles(
            in: directory,
            fileManager: fileManager
        )
        try Self.validateVisibleEntries(
            in: directory,
            reportURL: reportURL,
            fileManager: fileManager
        )
    }

    private func loadReport() throws -> Stage3StudyReportV1? {
        guard fileManager.fileExists(atPath: reportURL.path) else {
            return nil
        }
        let values = try reportURL.resourceValues(forKeys: [
            .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey,
        ])
        guard values.isRegularFile == true,
              values.isSymbolicLink != true,
              let size = values.fileSize,
              (1...Self.maximumRecordBytes).contains(size),
              try Self.hasPrivatePermissions(
                reportURL,
                fileManager: fileManager
              ) else {
            throw Stage3StudyLocalStoreErrorV1.unsafeStorage
        }
        do {
            let data = try Data(contentsOf: reportURL, options: .mappedIfSafe)
            return try Stage3StudyReportCodecV1.decode(data)
        } catch let error as Stage3StudyLocalStoreErrorV1 {
            throw error
        } catch {
            throw Stage3StudyLocalStoreErrorV1.unsafeStorage
        }
    }

    private func inject(_ point: Stage3StudyLocalStoreFaultPointV1) throws {
        if injectedFaults.contains(point) {
            throw Stage3StudyLocalStoreErrorV1.injectedFault(point)
        }
    }

    private func withExclusiveLock<T>(_ body: () throws -> T) throws -> T {
        try Self.withExclusiveLock(descriptor: lockDescriptor, body)
    }

    private static func withExclusiveLock<T>(
        descriptor: Int32,
        _ body: () throws -> T
    ) throws -> T {
        guard flock(descriptor, LOCK_EX) == 0 else {
            throw Stage3StudyLocalStoreErrorV1.ioFailure
        }
        defer { _ = flock(descriptor, LOCK_UN) }
        return try body()
    }

    private static func prepareDirectory(
        _ directory: URL,
        fileManager: FileManager
    ) throws {
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(
            atPath: directory.path,
            isDirectory: &isDirectory
        ) {
            let values = try directory.resourceValues(forKeys: [
                .isDirectoryKey, .isSymbolicLinkKey,
            ])
            guard isDirectory.boolValue,
                  values.isDirectory == true,
                  values.isSymbolicLink != true else {
                throw Stage3StudyLocalStoreErrorV1.unsafeStorage
            }
        } else {
            do {
                try fileManager.createDirectory(
                    at: directory,
                    withIntermediateDirectories: true,
                    attributes: [.posixPermissions: 0o700]
                )
            } catch {
                throw Stage3StudyLocalStoreErrorV1.ioFailure
            }
        }
        do {
            try fileManager.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: directory.path
            )
        } catch {
            throw Stage3StudyLocalStoreErrorV1.ioFailure
        }
    }

    private static func recoverPendingFiles(
        in directory: URL,
        fileManager: FileManager
    ) throws {
        let entries: [URL]
        do {
            entries = try fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [
                    .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey,
                ],
                options: []
            )
        } catch {
            throw Stage3StudyLocalStoreErrorV1.ioFailure
        }
        var removed = false
        for entry in entries where entry.lastPathComponent.hasPrefix(
            ".pending-"
        ) {
            let suffix = String(
                entry.lastPathComponent.dropFirst(".pending-".count)
            )
            let values = try entry.resourceValues(forKeys: [
                .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey,
            ])
            guard suffix == suffix.lowercased(),
                  let identifier = UUID(uuidString: suffix),
                  identifier.uuidString.lowercased() == suffix,
                  values.isRegularFile == true,
                  values.isSymbolicLink != true,
                  let size = values.fileSize,
                  size <= maximumRecordBytes else {
                throw Stage3StudyLocalStoreErrorV1.unsafeStorage
            }
            do {
                try fileManager.removeItem(at: entry)
                removed = true
            } catch {
                throw Stage3StudyLocalStoreErrorV1.ioFailure
            }
        }
        if removed { try synchronizeDirectory(directory) }
    }

    private static func validateVisibleEntries(
        in directory: URL,
        reportURL: URL,
        fileManager: FileManager
    ) throws {
        let entries: [URL]
        do {
            entries = try fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [
                    .isRegularFileKey, .isSymbolicLinkKey,
                ],
                options: []
            )
        } catch {
            throw Stage3StudyLocalStoreErrorV1.ioFailure
        }
        for entry in entries {
            if entry.lastPathComponent == ".lock" {
                guard try hasPrivateRegularFile(
                    entry,
                    fileManager: fileManager
                ) else {
                    throw Stage3StudyLocalStoreErrorV1.unsafeStorage
                }
                continue
            }
            guard entry.standardizedFileURL == reportURL,
                  try hasPrivateRegularFile(
                    entry,
                    fileManager: fileManager
                  ) else {
                throw Stage3StudyLocalStoreErrorV1.unsafeStorage
            }
        }
    }

    private static func hasPrivateRegularFile(
        _ url: URL,
        fileManager: FileManager
    ) throws -> Bool {
        let values = try url.resourceValues(forKeys: [
            .isRegularFileKey, .isSymbolicLinkKey,
        ])
        let hasPrivatePermissions = try hasPrivatePermissions(
            url,
            fileManager: fileManager
        )
        return values.isRegularFile == true
            && values.isSymbolicLink != true
            && hasPrivatePermissions
    }

    private static func hasPrivatePermissions(
        _ url: URL,
        fileManager: FileManager
    ) throws -> Bool {
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        guard let permissions = attributes[.posixPermissions] as? NSNumber
        else { return false }
        return permissions.intValue & 0o077 == 0
    }

    private static func synchronizeFile(_ url: URL) throws {
        let descriptor = open(url.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        guard descriptor >= 0 else {
            throw Stage3StudyLocalStoreErrorV1.ioFailure
        }
        defer { close(descriptor) }
        guard fsync(descriptor) == 0 else {
            throw Stage3StudyLocalStoreErrorV1.ioFailure
        }
    }

    private static func synchronizeDirectory(_ url: URL) throws {
        let descriptor = open(url.path, O_RDONLY | O_CLOEXEC | O_DIRECTORY)
        guard descriptor >= 0 else {
            throw Stage3StudyLocalStoreErrorV1.ioFailure
        }
        defer { close(descriptor) }
        guard fsync(descriptor) == 0 else {
            throw Stage3StudyLocalStoreErrorV1.ioFailure
        }
    }
}

public struct Stage3StudyExportPreviewV1: Equatable, Sendable {
    public let token: UUID
    public let studyCode: String
    public let suggestedFilename: String
    public let byteCount: Int
    public let jsonUTF8: String
}

public struct Stage3StudyExportPayloadV1: Equatable, Sendable {
    public let suggestedFilename: String
    public let contentType: String
    public let data: Data
}

/// Coordinates local save, preview, delete, and explicit export. Preparing a
/// preview never produces an export payload. A payload requires a matching
/// one-use preview token and is refused if the durable report changed.
public actor Stage3StudyLocalReportOwnerV1 {
    private struct PreparedPreview: Sendable {
        let token: UUID
        let report: Stage3StudyReportV1
        let data: Data
        let filename: String
    }

    private let persistence: any Stage3StudyReportPersistenceV1
    private var preparedPreview: PreparedPreview?

    public init(persistence: any Stage3StudyReportPersistenceV1) {
        self.persistence = persistence
    }

    public func currentReport() async throws -> Stage3StudyReportV1? {
        try await persistence.currentReport()
    }

    @discardableResult
    public func save(
        _ report: Stage3StudyReportV1
    ) async throws -> Stage3StudyLocalCommitResultV1 {
        let current = try await persistence.currentReport()
        if let current,
           current.studyCode != report.studyCode {
            throw Stage3StudyLocalStoreErrorV1.revisionConflict
        }
        let result = try await persistence.replaceAtomically(
            report,
            expectedCurrent: current
        )
        preparedPreview = nil
        return result
    }

    public func prepareExportPreview() async throws
        -> Stage3StudyExportPreviewV1 {
        guard let report = try await persistence.currentReport() else {
            throw Stage3StudyLocalStoreErrorV1.noReport
        }
        let data = try Stage3StudyReportCodecV1.encode(report)
        let filename = "mac-companion-study-\(report.studyCode).json"
        let prepared = PreparedPreview(
            token: UUID(),
            report: report,
            data: data,
            filename: filename
        )
        preparedPreview = prepared
        return Stage3StudyExportPreviewV1(
            token: prepared.token,
            studyCode: report.studyCode,
            suggestedFilename: filename,
            byteCount: data.count,
            jsonUTF8: String(decoding: data, as: UTF8.self)
        )
    }

    public func exportAfterExplicitRequest(
        previewToken: UUID
    ) async throws -> Stage3StudyExportPayloadV1 {
        guard let prepared = preparedPreview,
              prepared.token == previewToken else {
            throw Stage3StudyLocalStoreErrorV1.invalidExportRequest
        }
        preparedPreview = nil
        guard try await persistence.currentReport() == prepared.report else {
            throw Stage3StudyLocalStoreErrorV1.stalePreview
        }
        return Stage3StudyExportPayloadV1(
            suggestedFilename: prepared.filename,
            contentType: "application/json",
            data: prepared.data
        )
    }

    @discardableResult
    public func deleteAfterExplicitRequest(
        studyCode: String
    ) async throws -> Stage3StudyLocalDeleteResultV1 {
        guard let current = try await persistence.currentReport() else {
            preparedPreview = nil
            return .alreadyAbsent
        }
        guard current.studyCode == studyCode else {
            throw Stage3StudyLocalStoreErrorV1.invalidExportRequest
        }
        let result = try await persistence.deleteAtomically(
            expectedCurrent: current
        )
        preparedPreview = nil
        return result
    }
}
