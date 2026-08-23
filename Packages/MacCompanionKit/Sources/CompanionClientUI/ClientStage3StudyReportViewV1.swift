#if os(iOS)
import CompanionStudy
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
    public private(set) var exportDocument:
        ClientStage3StudyJSONDocumentV1?
    public private(set) var exportFilename = "mac-companion-study"

    private let owner: Stage3StudyLocalReportOwnerV1

    public init(owner: Stage3StudyLocalReportOwnerV1) {
        self.owner = owner
    }

    public func load() async {
        do {
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
    @State private var deleteCode: String?
    @Environment(\.dismiss) private var dismiss

    public init(owner: Stage3StudyLocalReportOwnerV1) {
        _model = StateObject(wrappedValue:
            ClientStage3StudyReportModelV1(owner: owner))
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
            ContentUnavailableView {
                Label("No study report", systemImage: "doc.badge.ellipsis")
            } description: {
                Text(
                    "Mac Companion has no local Stage 3 report to preview or export. The app remains usable without one."
                )
            }
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
#endif
