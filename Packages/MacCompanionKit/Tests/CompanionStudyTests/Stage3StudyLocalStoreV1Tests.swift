import CompanionStudy
import Foundation
import Testing

private func temporaryStudyDirectory() throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
        "maccompanion-study-tests-\(UUID().uuidString.lowercased())",
        isDirectory: true
    )
    try FileManager.default.createDirectory(
        at: root,
        withIntermediateDirectories: false
    )
    return root
}

@Test func localStudyStoreInsertsReplacesReopensAndDeletes() async throws {
    let directory = try temporaryStudyDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try AtomicFileStage3StudyReportStoreV1(
        directory: directory
    )
    let first = try studyReport(index: 200)
    let second = try studyReport(
        index: 200,
        desktopMilliseconds: 30,
        adaptiveMilliseconds: 70
    )

    #expect(try await store.currentReport() == nil)
    #expect(try await store.replaceAtomically(
        first,
        expectedCurrent: nil
    ) == .inserted)
    #expect(try await store.replaceAtomically(
        first,
        expectedCurrent: nil
    ) == .alreadyPresentExactReport)
    #expect(try await store.replaceAtomically(
        second,
        expectedCurrent: first
    ) == .replaced)

    let reopened = try AtomicFileStage3StudyReportStoreV1(
        directory: directory
    )
    #expect(try await reopened.currentReport() == second)
    let attributes = try FileManager.default.attributesOfItem(
        atPath: directory.appendingPathComponent(
            AtomicFileStage3StudyReportStoreV1.reportFilename
        ).path
    )
    #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    #expect(try await reopened.deleteAtomically(
        expectedCurrent: second
    ) == .deleted)
    #expect(try await store.currentReport() == nil)
    #expect(try await reopened.deleteAtomically(
        expectedCurrent: second
    ) == .alreadyAbsent)
}

@Test func localStudyStoreFencesStaleWritersAndDifferentStudies()
async throws {
    let directory = try temporaryStudyDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try AtomicFileStage3StudyReportStoreV1(
        directory: directory
    )
    let first = try studyReport(index: 201)
    let replacement = try studyReport(
        index: 201,
        desktopMilliseconds: 25,
        adaptiveMilliseconds: 75
    )
    let otherStudy = try studyReport(index: 202)
    _ = try await store.replaceAtomically(first, expectedCurrent: nil)
    _ = try await store.replaceAtomically(
        replacement,
        expectedCurrent: first
    )

    await #expect(throws: Stage3StudyLocalStoreErrorV1.revisionConflict) {
        try await store.replaceAtomically(first, expectedCurrent: first)
    }
    await #expect(throws: Stage3StudyLocalStoreErrorV1.revisionConflict) {
        try await store.replaceAtomically(
            otherStudy,
            expectedCurrent: replacement
        )
    }
}

@Test func localStudyStoreConvergesAcrossInjectedRenameAndDeleteFaults()
async throws {
    let directory = try temporaryStudyDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let first = try studyReport(index: 203)
    let replacement = try studyReport(
        index: 203,
        desktopMilliseconds: 10,
        adaptiveMilliseconds: 90
    )
    let clean = try AtomicFileStage3StudyReportStoreV1(
        directory: directory
    )
    _ = try await clean.replaceAtomically(first, expectedCurrent: nil)

    let beforeRename = try AtomicFileStage3StudyReportStoreV1(
        directory: directory,
        injectedFaults: [.beforeRename]
    )
    await #expect(
        throws: Stage3StudyLocalStoreErrorV1.injectedFault(.beforeRename)
    ) {
        try await beforeRename.replaceAtomically(
            replacement,
            expectedCurrent: first
        )
    }
    #expect(try await clean.currentReport() == first)

    let afterRename = try AtomicFileStage3StudyReportStoreV1(
        directory: directory,
        injectedFaults: [.afterRenameBeforeDirectorySync]
    )
    await #expect(
        throws: Stage3StudyLocalStoreErrorV1.injectedFault(
            .afterRenameBeforeDirectorySync
        )
    ) {
        try await afterRename.replaceAtomically(
            replacement,
            expectedCurrent: first
        )
    }
    #expect(try await clean.currentReport() == replacement)
    #expect(try await clean.replaceAtomically(
        replacement,
        expectedCurrent: first
    ) == .alreadyPresentExactReport)

    let deleteFault = try AtomicFileStage3StudyReportStoreV1(
        directory: directory,
        injectedFaults: [.afterDeleteBeforeDirectorySync]
    )
    await #expect(
        throws: Stage3StudyLocalStoreErrorV1.injectedFault(
            .afterDeleteBeforeDirectorySync
        )
    ) {
        try await deleteFault.deleteAtomically(
            expectedCurrent: replacement
        )
    }
    #expect(try await clean.currentReport() == nil)
    #expect(try await clean.deleteAtomically(
        expectedCurrent: replacement
    ) == .alreadyAbsent)
}

@Test func localStudyStoreRejectsUnexpectedAndSymlinkedMaterial()
async throws {
    let directory = try temporaryStudyDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    _ = try AtomicFileStage3StudyReportStoreV1(directory: directory)
    let unexpected = directory.appendingPathComponent("notes.txt")
    try Data("private".utf8).write(to: unexpected)
    #expect(throws: Stage3StudyLocalStoreErrorV1.unsafeStorage) {
        try AtomicFileStage3StudyReportStoreV1(directory: directory)
    }
    try FileManager.default.removeItem(at: unexpected)

    let outside = directory.deletingLastPathComponent().appendingPathComponent(
        "outside-\(UUID().uuidString.lowercased())"
    )
    try Data("outside".utf8).write(to: outside)
    defer { try? FileManager.default.removeItem(at: outside) }
    let reportURL = directory.appendingPathComponent(
        AtomicFileStage3StudyReportStoreV1.reportFilename
    )
    try FileManager.default.createSymbolicLink(
        at: reportURL,
        withDestinationURL: outside
    )
    #expect(throws: Stage3StudyLocalStoreErrorV1.unsafeStorage) {
        try AtomicFileStage3StudyReportStoreV1(directory: directory)
    }
}

@Test func localStudyOwnerRequiresFreshOneUsePreviewForExport()
async throws {
    let directory = try temporaryStudyDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try AtomicFileStage3StudyReportStoreV1(
        directory: directory
    )
    let owner = Stage3StudyLocalReportOwnerV1(persistence: store)
    let first = try studyReport(index: 204)
    let replacement = try studyReport(
        index: 204,
        desktopMilliseconds: 15,
        adaptiveMilliseconds: 85
    )
    #expect(try await owner.save(first) == .inserted)
    let preview = try await owner.prepareExportPreview()
    #expect(preview.studyCode == first.studyCode)
    #expect(preview.byteCount == Data(preview.jsonUTF8.utf8).count)
    #expect(!preview.jsonUTF8.contains("screenTitle"))

    let payload = try await owner.exportAfterExplicitRequest(
        previewToken: preview.token
    )
    #expect(payload.contentType == "application/json")
    #expect(try Stage3StudyReportCodecV1.decode(payload.data) == first)
    await #expect(
        throws: Stage3StudyLocalStoreErrorV1.invalidExportRequest
    ) {
        try await owner.exportAfterExplicitRequest(
            previewToken: preview.token
        )
    }

    let stalePreview = try await owner.prepareExportPreview()
    _ = try await store.replaceAtomically(
        replacement,
        expectedCurrent: first
    )
    await #expect(throws: Stage3StudyLocalStoreErrorV1.stalePreview) {
        try await owner.exportAfterExplicitRequest(
            previewToken: stalePreview.token
        )
    }
}

@Test func localStudyOwnerRequiresExactStudyCodeForExplicitDelete()
async throws {
    let directory = try temporaryStudyDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try AtomicFileStage3StudyReportStoreV1(
        directory: directory
    )
    let owner = Stage3StudyLocalReportOwnerV1(persistence: store)
    let report = try studyReport(index: 205)
    _ = try await owner.save(report)

    await #expect(
        throws: Stage3StudyLocalStoreErrorV1.invalidExportRequest
    ) {
        try await owner.deleteAfterExplicitRequest(studyCode: studyCode(206))
    }
    #expect(try await owner.currentReport() == report)
    #expect(try await owner.deleteAfterExplicitRequest(
        studyCode: report.studyCode
    ) == .deleted)
    await #expect(throws: Stage3StudyLocalStoreErrorV1.noReport) {
        try await owner.prepareExportPreview()
    }
}
