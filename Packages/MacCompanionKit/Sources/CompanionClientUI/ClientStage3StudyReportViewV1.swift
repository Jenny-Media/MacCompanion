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

    public func recordPhysicalReturn(
        _ reason: Stage3StudyPhysicalReturnReasonV1
    ) async -> Bool {
        do {
            let report = try await capture.recordPhysicalReturn(reason)
            state = .ready(ClientStage3StudyReportSummaryV1(report: report))
            return true
        } catch {
            state = .failed
            return false
        }
    }

    public func completeFinalReview(
        comprehension: Stage3StudyComprehensionV1,
        safetyIncidents: Set<Stage3StudySafetyIncidentV1>,
        recoveryConfusions: Set<Stage3StudyRecoveryConfusionV1>
    ) async -> Bool {
        do {
            let report = try await capture.completeReview(
                comprehension: comprehension,
                safetyIncidents: Array(safetyIncidents),
                recoveryConfusions: Array(recoveryConfusions)
            )
            activeSessionDayIndex = nil
            state = .ready(ClientStage3StudyReportSummaryV1(report: report))
            return true
        } catch {
            state = .failed
            return false
        }
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
    @State private var showingPhysicalReturn = false
    @State private var physicalReturnInFlight = false
    @State private var physicalReturnReason =
        Stage3StudyPhysicalReturnReasonV1.permission
    @State private var showingFinalReview = false
    @State private var finalReviewInFlight = false
    @State private var distinguishesPairedAndConnected = false
    @State private var distinguishesViewingAndControlling = false
    @State private var understandsApprovalRequired = false
    @State private var understandsSeparateGrants = false
    @State private var safetyIncidents: Set<Stage3StudySafetyIncidentV1> = []
    @State private var recoveryConfusions:
        Set<Stage3StudyRecoveryConfusionV1> = []
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
            .sheet(isPresented: $showingPhysicalReturn) {
                physicalReturnSheet
                    .interactiveDismissDisabled(physicalReturnInFlight)
            }
            .sheet(isPresented: $showingFinalReview) {
                finalReviewSheet
                    .interactiveDismissDisabled(finalReviewInFlight)
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
                if summary.safetyReviewCompleted {
                    Label(
                        "Final review complete; this report is locked",
                        systemImage: "lock.fill"
                    )
                } else {
                    sessionControls
                    if model.activeSessionDayIndex != nil {
                        Button(
                            "Record a Physical Return",
                            systemImage: "figure.walk.arrival"
                        ) {
                            showingPhysicalReturn = true
                        }
                        Button(
                            "Complete Final Review and Lock Report",
                            systemImage: "checkmark.shield"
                        ) {
                            showingFinalReview = true
                        }
                    }
                }
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

    private var physicalReturnSheet: some View {
        NavigationStack {
            Form {
                Section("Why physical access was required") {
                    Picker("Reason", selection: $physicalReturnReason) {
                        ForEach(
                            Stage3StudyPhysicalReturnReasonV1.allCases,
                            id: \.self
                        ) { reason in
                            Text(reason.studyDisplayName).tag(reason)
                        }
                    }
                    .pickerStyle(.inline)
                }
                Section {
                    Button("Add Physical Return", systemImage: "plus.circle") {
                        guard !physicalReturnInFlight else { return }
                        physicalReturnInFlight = true
                        Task {
                            if await model.recordPhysicalReturn(
                                physicalReturnReason
                            ) {
                                showingPhysicalReturn = false
                            }
                            physicalReturnInFlight = false
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(physicalReturnInFlight)
                } footer: {
                    Text(
                        "Record only when the remote job actually required "
                            + "returning to the Mac. The report stores this "
                            + "closed reason and the active study day only."
                    )
                }
            }
            .navigationTitle("Physical Return")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showingPhysicalReturn = false }
                        .disabled(physicalReturnInFlight)
                }
            }
        }
    }

    private var finalReviewSheet: some View {
        ClientStage3StudyFinalReviewViewV1(
            distinguishesPairedAndConnected:
                $distinguishesPairedAndConnected,
            distinguishesViewingAndControlling:
                $distinguishesViewingAndControlling,
            understandsApprovalRequired: $understandsApprovalRequired,
            understandsSeparateGrants: $understandsSeparateGrants,
            safetyIncidents: $safetyIncidents,
            recoveryConfusions: $recoveryConfusions,
            inFlight: finalReviewInFlight,
            onCancel: { showingFinalReview = false },
            onComplete: {
                guard !finalReviewInFlight else { return }
                finalReviewInFlight = true
                let comprehension = Stage3StudyComprehensionV1(
                    distinguishesPairedAndConnected:
                        distinguishesPairedAndConnected,
                    distinguishesViewingAndControlling:
                        distinguishesViewingAndControlling,
                    understandsApprovalRequired:
                        understandsApprovalRequired,
                    understandsSeparateGrants: understandsSeparateGrants
                )
                Task {
                    if await model.completeFinalReview(
                        comprehension: comprehension,
                        safetyIncidents: safetyIncidents,
                        recoveryConfusions: recoveryConfusions
                    ) {
                        showingFinalReview = false
                    }
                    finalReviewInFlight = false
                }
            }
        )
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

@available(iOS 17.0, *)
private struct ClientStage3StudyFinalReviewViewV1: View {
    @Binding var distinguishesPairedAndConnected: Bool
    @Binding var distinguishesViewingAndControlling: Bool
    @Binding var understandsApprovalRequired: Bool
    @Binding var understandsSeparateGrants: Bool
    @Binding var safetyIncidents: Set<Stage3StudySafetyIncidentV1>
    @Binding var recoveryConfusions: Set<Stage3StudyRecoveryConfusionV1>
    let inFlight: Bool
    let onCancel: () -> Void
    let onComplete: () -> Void
    @State private var reviewedSafety = false
    @State private var reviewedRecovery = false
    @State private var understandsLock = false
    @State private var confirmingCompletion = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Understanding check") {
                    Toggle(
                        "Paired and connected are different states",
                        isOn: $distinguishesPairedAndConnected
                    )
                    Toggle(
                        "Viewing and controlling are different states",
                        isOn: $distinguishesViewingAndControlling
                    )
                    Toggle(
                        "An action can require separate approval",
                        isOn: $understandsApprovalRequired
                    )
                    Toggle(
                        "Pairing, Act, and Control grants are separate",
                        isOn: $understandsSeparateGrants
                    )
                }
                Section("Confirmed safety incidents") {
                    ForEach(
                        Stage3StudySafetyIncidentV1.allCases,
                        id: \.self
                    ) { incident in
                        Toggle(
                            incident.studyDisplayName,
                            isOn: selection(
                                incident,
                                in: $safetyIncidents
                            )
                        )
                    }
                    Toggle(
                        "I reviewed the full session for safety incidents",
                        isOn: $reviewedSafety
                    )
                }
                Section("Confirmed recovery confusion") {
                    ForEach(
                        Stage3StudyRecoveryConfusionV1.allCases,
                        id: \.self
                    ) { confusion in
                        Toggle(
                            confusion.studyDisplayName,
                            isOn: selection(
                                confusion,
                                in: $recoveryConfusions
                            )
                        )
                    }
                    Toggle(
                        "I reviewed the full session for misleading recovery state",
                        isOn: $reviewedRecovery
                    )
                }
                Section {
                    Toggle(
                        "I understand completion ends the session and permanently locks this report",
                        isOn: $understandsLock
                    )
                    Button(
                        "Complete Review and Lock Report",
                        systemImage: "lock.fill"
                    ) {
                        confirmingCompletion = true
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(
                        inFlight
                            || !reviewedSafety
                            || !reviewedRecovery
                            || !understandsLock
                    )
                } footer: {
                    Text(
                        "Leave incident or confusion items off only when the "
                            + "review confirmed none occurred. Understanding "
                            + "answers may remain false and will be scored as "
                            + "incorrect rather than omitted."
                    )
                }
            }
            .navigationTitle("Final Study Review")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                        .disabled(inFlight)
                }
            }
            .confirmationDialog(
                "Lock this report permanently?",
                isPresented: $confirmingCompletion,
                titleVisibility: .visible
            ) {
                Button(
                    "Complete and Lock",
                    role: .destructive,
                    action: onComplete
                )
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(
                    "The active study session will end. No later product or "
                        + "review facts can be added to this local report."
                )
            }
        }
    }

    private func selection<Value: Hashable>(
        _ value: Value,
        in values: Binding<Set<Value>>
    ) -> Binding<Bool> {
        Binding(
            get: { values.wrappedValue.contains(value) },
            set: { selected in
                if selected {
                    values.wrappedValue.insert(value)
                } else {
                    values.wrappedValue.remove(value)
                }
            }
        )
    }
}

private extension Stage3StudyPhysicalReturnReasonV1 {
    var studyDisplayName: String {
        switch self {
        case .permission: "Permission"
        case .pairing: "Pairing"
        case .network: "Network"
        case .lock: "Locked Mac"
        case .sleep: "Sleeping Mac"
        case .dialog: "Unexpected dialog"
        case .input: "Input problem"
        case .unclearState: "Unclear product state"
        case .other: "Other"
        }
    }
}

private extension Stage3StudySafetyIncidentV1 {
    var studyDisplayName: String {
        switch self {
        case .staleAuthorityInput: "Input after authority became stale"
        case .unintendedSurfaceOrFieldInput: "Input reached the wrong surface or field"
        case .behindLockContentDisclosure: "Content was visible behind lock"
        case .unauthorizedCapabilityElevation: "Capability exceeded its grant"
        case .localStopOrRevocationFailure: "Local Stop or revocation failed"
        }
    }
}

private extension Stage3StudyRecoveryConfusionV1 {
    var studyDisplayName: String {
        switch self {
        case .unreachablePresentedAsLive: "Unreachable appeared live"
        case .stalePresentedAsFresh: "Stale status appeared fresh"
        case .lockedPresentedAsUnlocked: "Locked appeared unlocked"
        case .sleepingPresentedAsReachable: "Sleeping appeared reachable"
        case .outcomeUnknownPresentedAsCompleted: "Unknown action outcome appeared complete"
        }
    }
}
#endif
