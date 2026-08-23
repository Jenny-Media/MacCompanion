#if os(iOS)
import CompanionStudy
import Foundation
import SwiftUI
import UniformTypeIdentifiers

public struct ClientStage3StudyReportSummaryV1: Equatable, Sendable {
    public let studyCode: String
    public let cohortPhase: Stage3StudyCohortPhaseV1
    public let appVersion: String
    public let buildNumber: String
    public let completedJobCount: Int
    public let operationalEventCount: Int
    public let safetyReviewCompleted: Bool

    public init(report: Stage3StudyReportV1) {
        studyCode = report.studyCode
        cohortPhase = report.cohortPhase
        appVersion = report.build.appVersion
        buildNumber = report.build.buildNumber
        completedJobCount = report.jobs.count { $0.isCompletedRealJob }
        operationalEventCount = report.operationalEvents.count
        safetyReviewCompleted = report.safetyReviewCompleted
    }
}

public enum ClientStage3StudyReportStateV1: Equatable, Sendable {
    case loading
    case absent
    case ready(ClientStage3StudyReportSummaryV1)
    case preview(Stage3StudyExportPreviewV1)
    case failed
}

public struct ClientStage3StudyJSONDocumentV1: FileDocument {
    public static var readableContentTypes: [UTType] { [.json] }

    private let data: Data

    public init(data: Data) {
        self.data = data
    }

    public init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              data.count <= Stage3StudyReportV1.maximumEncodedBytes else {
            throw CocoaError(.fileReadCorruptFile)
        }
        _ = try Stage3StudyReportCodecV1.decode(data)
        self.data = data
    }

    public func fileWrapper(
        configuration: WriteConfiguration
    ) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

@available(iOS 17.0, *)
@MainActor
public final class ClientStage3StudyReportModelV1: ObservableObject {
    @Published public private(set) var state:
        ClientStage3StudyReportStateV1 = .loading
    @Published public var isExporting = false
    @Published public private(set) var activeSessionDayIndex: Int?
    public private(set) var exportDocument:
        ClientStage3StudyJSONDocumentV1?
    public private(set) var exportFilename = "mac-companion-study"

    private let owner: Stage3StudyLocalReportOwnerV1
    private let capture: Stage3StudyLocalCaptureV1

    public init(
        owner: Stage3StudyLocalReportOwnerV1,
        capture: Stage3StudyLocalCaptureV1
    ) {
        self.owner = owner
        self.capture = capture
    }

    public func load() async {
        do {
            activeSessionDayIndex = await capture.currentSessionDayIndex()
            if let report = try await owner.currentReport() {
                state = .ready(ClientStage3StudyReportSummaryV1(
                    report: report
                ))
            } else {
                state = .absent
            }
        } catch {
            state = .failed
        }
    }

    public func enrollDogfood(
        studyCode: String,
        macOSMajorVersion: Int,
        workaround: Stage3StudyWorkaroundV1,
        adaptiveJobApplicable: Bool
    ) async {
        do {
            guard let appVersion = Bundle.main.object(
                forInfoDictionaryKey: "CFBundleShortVersionString"
            ) as? String,
            let buildNumber = Bundle.main.object(
                forInfoDictionaryKey: "CFBundleVersion"
            ) as? String else {
                state = .failed
                return
            }
            let build = try Stage3StudyBuildV1(
                appVersion: appVersion,
                buildNumber: buildNumber,
                iOSMajorVersion: ProcessInfo.processInfo
                    .operatingSystemVersion.majorVersion,
                macOSMajorVersion: macOSMajorVersion
            )
            let report = try await capture.enroll(
                Stage3StudyLocalEnrollmentV1(
                    cohortPhase: .dogfood,
                    studyCode: studyCode,
                    build: build,
                    workaround: workaround,
                    adaptiveJobApplicable: adaptiveJobApplicable
                )
            )
            state = .ready(ClientStage3StudyReportSummaryV1(
                report: report
            ))
        } catch {
            state = .failed
        }
    }

    public func beginSession(dayIndex: Int) async {
        do {
            try await capture.beginSession(dayIndex: dayIndex)
            activeSessionDayIndex = dayIndex
        } catch {
            state = .failed
        }
    }

    public func endSession() async {
        await capture.endSession()
        activeSessionDayIndex = nil
    }

    public func preparePreview() async {
        do {
            state = .preview(try await owner.prepareExportPreview())
        } catch let error as Stage3StudyLocalStoreErrorV1
            where error == .noReport {
            state = .absent
        } catch {
            state = .failed
        }
    }

    public func beginExplicitExport() async {
        guard case let .preview(preview) = state else {
            state = .failed
            return
        }
        do {
            let payload = try await owner.exportAfterExplicitRequest(
                previewToken: preview.token
            )
            exportDocument = ClientStage3StudyJSONDocumentV1(
                data: payload.data
            )
            exportFilename = payload.suggestedFilename
            isExporting = true
        } catch {
            state = .failed
        }
    }

    public func completeExport() {
        isExporting = false
        exportDocument = nil
    }

    public func cancelPreview() async {
        await load()
    }

    public func deleteAfterExplicitRequest(studyCode: String) async {
        do {
            _ = try await owner.deleteAfterExplicitRequest(
                studyCode: studyCode
            )
            await capture.endSession()
            activeSessionDayIndex = nil
            state = .absent
            exportDocument = nil
            isExporting = false
        } catch {
            state = .failed
        }
    }
}

@available(iOS 17.0, *)
public struct ClientStage3StudyReportViewV1: View {
    @StateObject private var model: ClientStage3StudyReportModelV1
    private let captureFailed: Bool
    @State private var deleteCode: String?
    @State private var enrollmentCode = ""
    @State private var macOSMajorVersion = 26
    @State private var workaround = Stage3StudyWorkaroundV1.returnOrDefer
    @State private var adaptiveJobApplicable = false
    @State private var understoodLocalStudy = false
    @State private var selectedDayIndex = 0
    @Environment(\.dismiss) private var dismiss

    public init(
        owner: Stage3StudyLocalReportOwnerV1,
        capture: Stage3StudyLocalCaptureV1,
        captureFailed: Bool = false
    ) {
        self.captureFailed = captureFailed
        _model = StateObject(wrappedValue:
            ClientStage3StudyReportModelV1(
                owner: owner,
                capture: capture
            ))
    }

    public var body: some View {
        content
            .navigationTitle("Study Report")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await model.load() }
            .confirmationDialog(
                "Delete this local study report?",
                isPresented: Binding(
                    get: { deleteCode != nil },
                    set: { if !$0 { deleteCode = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete Report", role: .destructive) {
                    guard let deleteCode else { return }
                    self.deleteCode = nil
                    Task {
                        await model.deleteAfterExplicitRequest(
                            studyCode: deleteCode
                        )
                    }
                }
                Button("Cancel", role: .cancel) { deleteCode = nil }
            } message: {
                Text(
                    "This removes the only product-generated copy on this device. Export is never automatic."
                )
            }
            .fileExporter(
                isPresented: $model.isExporting,
                document: model.exportDocument,
                contentType: .json,
                defaultFilename: model.exportFilename
            ) { _ in
                model.completeExport()
            }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            ProgressView("Loading local report…")
        case .absent:
            enrollmentForm
        case let .ready(summary):
            summaryForm(summary)
        case let .preview(preview):
            previewView(preview)
        case .failed:
            ContentUnavailableView {
                Label(
                    "Report unavailable",
                    systemImage: "exclamationmark.triangle"
                )
            } description: {
                Text(
                    "Mac Companion did not export or delete anything. Close this screen and try again."
                )
            }
        }
    }

    private func summaryForm(
        _ summary: ClientStage3StudyReportSummaryV1
    ) -> some View {
        Form {
            if captureFailed {
                Section {
                    Label(
                        "A study fact could not be saved. Product operation continued, but do not export this report until the study is reviewed.",
                        systemImage: "exclamationmark.triangle"
                    )
                    .foregroundStyle(.red)
                }
            }
            Section("Local Report") {
                LabeledContent("Study code", value: summary.studyCode)
                LabeledContent(
                    "Cohort",
                    value: summary.cohortPhase.rawValue.capitalized
                )
                LabeledContent(
                    "Candidate",
                    value: "\(summary.appVersion) (\(summary.buildNumber))"
                )
                LabeledContent(
                    "Completed jobs",
                    value: String(summary.completedJobCount)
                )
                LabeledContent(
                    "Operational facts",
                    value: String(summary.operationalEventCount)
                )
                LabeledContent(
                    "Safety review",
                    value: summary.safetyReviewCompleted
                        ? "Complete" : "Incomplete"
                )
            }
            Section {
                sessionControls
                Button("Preview Exact Report", systemImage: "doc.text.magnifyingglass") {
                    Task { await model.preparePreview() }
                }
                Button("Delete Local Report", role: .destructive) {
                    deleteCode = summary.studyCode
                }
            } footer: {
                Text(
                    "Nothing is uploaded. Preview is required before an explicit export, and you choose the destination."
                )
            }
        }
    }

    private var enrollmentForm: some View {
        Form {
            Section("Local Dogfood") {
                TextField("16-character study code", text: $enrollmentCode)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .font(.body.monospaced())
                Stepper(
                    "Mac OS major version: \(macOSMajorVersion)",
                    value: $macOSMajorVersion,
                    in: 26...99
                )
                Picker("Usual workaround", selection: $workaround) {
                    ForEach(Stage3StudyWorkaroundV1.allCases, id: \.self) {
                        Text($0.studyDisplayName).tag($0)
                    }
                }
                Toggle(
                    "An adaptive app, window, or focused-region job applies",
                    isOn: $adaptiveJobApplicable
                )
            }
            Section("Before Enrolling") {
                Text(
                    "Enrollment creates one local, content-free report. It does not upload analytics, screen content, input, addresses, device identity, or diagnostic logs. You may use Mac Companion without enrolling and may delete the report at any time."
                )
                Toggle(
                    "I understand this local dogfood report",
                    isOn: $understoodLocalStudy
                )
            }
            Section {
                Button("Enroll in Local Dogfood") {
                    Task {
                        await model.enrollDogfood(
                            studyCode: normalizedEnrollmentCode,
                            macOSMajorVersion: macOSMajorVersion,
                            workaround: workaround,
                            adaptiveJobApplicable: adaptiveJobApplicable
                        )
                    }
                }
                .disabled(
                    !understoodLocalStudy || !isEnrollmentCodeValid
                )
            } footer: {
                Text(
                    "Calibration and confirmatory enrollment remain unavailable until the external participant disclosure and retention policy are approved."
                )
            }
        }
    }

    @ViewBuilder
    private var sessionControls: some View {
        if let activeDayIndex = model.activeSessionDayIndex {
            LabeledContent(
                "Study session",
                value: "Day \(activeDayIndex + 1) active"
            )
            Button("End Study Session", systemImage: "stop.circle") {
                Task { await model.endSession() }
            }
        } else {
            Picker("Study day", selection: $selectedDayIndex) {
                ForEach(0..<14, id: \.self) { dayIndex in
                    Text("Day \(dayIndex + 1)").tag(dayIndex)
                }
            }
            Button("Begin Study Session", systemImage: "record.circle") {
                Task { await model.beginSession(dayIndex: selectedDayIndex) }
            }
        }
    }

    private var normalizedEnrollmentCode: String {
        enrollmentCode.trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
    }

    private var isEnrollmentCodeValid: Bool {
        let bytes = normalizedEnrollmentCode.utf8
        return bytes.count == 16 && bytes.allSatisfy { byte in
            (UInt8(ascii: "A")...UInt8(ascii: "Z")).contains(byte)
                || (UInt8(ascii: "2")...UInt8(ascii: "7")).contains(byte)
        }
    }

    private func previewView(
        _ preview: Stage3StudyExportPreviewV1
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(
                "Review the exact product-generated JSON. It excludes screen, input, address, identity, and diagnostic-log content."
            )
            .font(.callout)
            .foregroundStyle(.secondary)

            ScrollView([.horizontal, .vertical]) {
                Text(preview.jsonUTF8)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(8)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))

            Text("\(preview.byteCount) bytes")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Button("Back") {
                    Task { await model.cancelPreview() }
                }
                Spacer()
                Button("Export…", systemImage: "square.and.arrow.up") {
                    Task { await model.beginExplicitExport() }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }
}

private extension Stage3StudyWorkaroundV1 {
    var studyDisplayName: String {
        switch self {
        case .returnOrDefer: "Return to the Mac or defer"
        case .screenSharingOrRemoteDesktop: "Screen sharing or remote desktop"
        case .sshScriptShortcutOrUtility: "SSH, script, Shortcut, or utility"
        case .keepPrimaryMacNearby: "Keep the primary Mac nearby"
        case .noWorkableAlternative: "No workable alternative"
        }
    }
}
#endif
