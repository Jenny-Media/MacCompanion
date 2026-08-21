#if os(iOS)
import CompanionWire
import SwiftUI

@available(iOS 17.0, *)
public struct ClientAuditHistoryViewV1: View {
    private let projection: ClientAuditHistoryProjectionV1
    private let onLoadOlder: () -> Void

    public init(
        page: AuditListResponseBodyV1,
        onLoadOlder: @escaping () -> Void
    ) {
        self.init(
            projection: ClientAuditHistoryProjectionV1(page: page),
            onLoadOlder: onLoadOlder
        )
    }

    public init(
        projection: ClientAuditHistoryProjectionV1,
        onLoadOlder: @escaping () -> Void
    ) {
        self.projection = projection
        self.onLoadOlder = onLoadOlder
    }

    public var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
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
                                : "Activity from this device will appear here."
                        )
                    )
                } else {
                    ForEach(projection.rows) { row in
                        rowCard(row)
                    }
                }

                if projection.canLoadOlder {
                    Button("Load Older Activity", action: onLoadOlder)
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(20)
        }
        .navigationTitle("Activity")
    }

    private var gapCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("History is incomplete", systemImage: "exclamationmark.triangle")
                .font(.headline)
            ForEach(projection.gaps.messages, id: \.self) { message in
                Text(message)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }

    private func rowCard(_ row: ClientAuditRowProjectionV1) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: row.systemImage)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(row.title)
                    .font(.headline)
                Text(row.scopeLabel)
                    .font(.subheadline)
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
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }
}
#endif
