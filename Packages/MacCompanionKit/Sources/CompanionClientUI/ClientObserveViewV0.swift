#if os(iOS)
import SwiftUI

@available(iOS 17.0, *)
public struct ClientObserveViewV0: View {
    private let projection: ClientObserveWorkspaceProjectionV0
    private let isRefreshingStatus: Bool
    private let isLoadingActivity: Bool
    private let onRefreshStatus: () -> Void
    private let onLoadActivity: () -> Void
    private let onLoadOlderActivity: () -> Void

    public init(
        projection: ClientObserveWorkspaceProjectionV0,
        isRefreshingStatus: Bool = false,
        isLoadingActivity: Bool = false,
        onRefreshStatus: @escaping () -> Void,
        onLoadActivity: @escaping () -> Void,
        onLoadOlderActivity: @escaping () -> Void
    ) {
        self.projection = projection
        self.isRefreshingStatus = isRefreshingStatus
        self.isLoadingActivity = isLoadingActivity
        self.onRefreshStatus = onRefreshStatus
        self.onLoadActivity = onLoadActivity
        self.onLoadOlderActivity = onLoadOlderActivity
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Label(projection.macName, systemImage: "desktopcomputer")
                    .font(.title2.weight(.semibold))
                statusCard
                if let system = projection.status.system {
                    systemCard(system)
                }
                if let issue = projection.issue {
                    issueCard(issue)
                }
                activityCard
                Label(
                    "Observe reads status and scoped activity without starting or authorizing Remote Control.",
                    systemImage: "eye"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("Observe limitation")
            }
            .frame(maxWidth: 620, alignment: .leading)
            .padding(20)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Mac Status")
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(
                projection.status.title,
                systemImage: projection.status.systemImage
            )
            .font(.headline)
            Text(projection.status.detail)
                .foregroundStyle(.secondary)
            if let observedAt = projection.status.observedAt {
                HStack(spacing: 4) {
                    Text("Observed")
                    Text(observedAt, style: .date)
                    Text(observedAt, style: .time)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            if projection.status.canRefresh {
                Button(
                    isRefreshingStatus ? "Refreshing Status" : "Refresh Status",
                    systemImage: "arrow.clockwise",
                    action: onRefreshStatus
                )
                .buttonStyle(.bordered)
                .disabled(isRefreshingStatus)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("Observe status")
    }

    private func systemCard(
        _ system: ClientObserveSystemProjectionV0
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Mac Health")
                .font(.headline)
            LabeledContent("Session", value: system.hostState)
            LabeledContent("System", value: system.operatingSystem)
            LabeledContent(
                "CPU",
                value: percent(system.cpuUtilizationBasisPoints)
            )
            LabeledContent("Memory") {
                Text(system.memoryUsedBytes, format: .byteCount(style: .memory))
                Text("of")
                Text(system.memoryTotalBytes, format: .byteCount(style: .memory))
            }
            LabeledContent("Storage available") {
                Text(
                    system.storageAvailableBytes,
                    format: .byteCount(style: .file)
                )
            }
            LabeledContent("Power", value: system.power)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 16))
    }

    private func issueCard(_ issue: ClientObserveIssueProjectionV0)
        -> some View
    {
        VStack(alignment: .leading, spacing: 6) {
            Label(issue.title, systemImage: "exclamationmark.triangle")
                .font(.headline)
            Text(issue.detail)
                .foregroundStyle(.secondary)
            Text("Diagnostic: \(issue.diagnosticCode)")
                .font(.caption.monospaced())
                .foregroundStyle(.tertiary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private var activityCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Activity")
                .font(.headline)
            if let activity = projection.activity {
                if activity.gaps.historyIsIncomplete {
                    Label("History is incomplete", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
                Text(activity.rows.isEmpty
                    ? "No retained activity is available in this page."
                    : "\(activity.rows.count) scoped event\(activity.rows.count == 1 ? "" : "s") in the latest page.")
                    .foregroundStyle(.secondary)
                NavigationLink("View Activity") {
                    ClientAuditHistoryViewV1(
                        projection: activity,
                        onLoadOlder: onLoadOlderActivity
                    )
                }
            } else {
                Text("Load privacy-limited activity for this paired device.")
                    .foregroundStyle(.secondary)
                Button(
                    isLoadingActivity ? "Loading Activity" : "Load Activity",
                    systemImage: "clock.arrow.circlepath",
                    action: onLoadActivity
                )
                .buttonStyle(.bordered)
                .disabled(isLoadingActivity)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 16))
    }

    private func percent(_ basisPoints: UInt16) -> String {
        let whole = basisPoints / 100
        let fraction = basisPoints % 100
        return "\(whole).\(String(format: "%02d", fraction))%"
    }
}
#endif
