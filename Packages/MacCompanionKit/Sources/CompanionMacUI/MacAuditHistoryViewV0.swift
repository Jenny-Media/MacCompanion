#if os(macOS)
import CompanionIPC
import SwiftUI

@available(macOS 14.0, *)
public struct MacAuditHistoryViewV0: View {
    private let projection: MacAuditHistoryProjectionV0
    private let onLoadOlder: () -> Void

    public init(
        page: LocalAuditPageResponseV0,
        locallyConfirmedDeviceNames: [UUID: String],
        onLoadOlder: @escaping () -> Void
    ) {
        projection = MacAuditHistoryProjectionV0(
            page: page,
            locallyConfirmedDeviceNames: locallyConfirmedDeviceNames
        )
        self.onLoadOlder = onLoadOlder
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Activity history", systemImage: "clock.arrow.circlepath")
                .font(.title2.weight(.semibold))

            if projection.gaps.historyIsIncomplete {
                gapCard
            }

            if projection.rows.isEmpty {
                ContentUnavailableView(
                    projection.gaps.historyIsIncomplete
                        ? "No Retained Activity"
                        : "No Activity Yet",
                    systemImage: "clock.arrow.circlepath",
                    description: Text(
                        projection.gaps.historyIsIncomplete
                            ? "Older or unretained activity may not appear here."
                            : "Paired-device and local security activity will appear here."
                    )
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(projection.rows) { row in
                    rowView(row)
                }
                .listStyle(.inset)
            }

            if projection.canLoadOlder {
                Button("Load Older Activity", action: onLoadOlder)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .padding(18)
        .frame(minWidth: 540, idealWidth: 680, minHeight: 460)
    }

    private var gapCard: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label("History is incomplete", systemImage: "exclamationmark.triangle")
                .font(.headline)
            ForEach(projection.gaps.messages, id: \.self) { message in
                Text(message)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
    }

    private func rowView(_ row: MacAuditRowProjectionV0) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: row.systemImage)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(row.title)
                    .font(.headline)
                Text(row.deviceLabel.map {
                    "\($0) • \(row.actorLabel)"
                } ?? row.actorLabel)
                    .foregroundStyle(.secondary)
                ForEach(row.details, id: \.self) { detail in
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Text(row.observedAt, style: .date)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Text(row.observedAt, style: .time)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}
#endif
