#if os(iOS)
import CompanionInteractiveWire
import SwiftUI

@available(iOS 17.0, *)
struct ClientSharedDisplayPickerV0: View {
    let catalog: InteractiveDisplayCatalogResponseBodyV1?
    let requestInFlight: Bool
    let pendingDisplayID: UUID?
    let statusMessage: String?
    let onSelect: (UUID) -> Void
    let onRefresh: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    if let catalog {
                        ClientSharedDisplayTopologyV0(
                            catalog: catalog,
                            disabled: requestInFlight || pendingDisplayID != nil,
                            onSelect: onSelect
                        )
                        .frame(height: 220)

                        VStack(spacing: 0) {
                            ForEach(catalog.displays.sorted { $0.ordinal < $1.ordinal }) { display in
                                displayRow(display, catalog: catalog)
                                if display.ordinal != catalog.displays.map(\.ordinal).max() {
                                    Divider().padding(.leading, 48)
                                }
                            }
                        }
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 16))

                        Text("Tap a display to share it.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else if requestInFlight {
                        ProgressView("Loading displays…")
                            .frame(maxWidth: .infinity, minHeight: 220)
                            .accessibilityIdentifier("Shared Displays Loading")
                    } else {
                        ContentUnavailableView(
                            "Displays unavailable",
                            systemImage: "display.trianglebadge.exclamationmark",
                            description: Text("Refresh to load your Mac’s displays.")
                        )
                    }

                    if requestInFlight, catalog != nil {
                        ProgressView(statusMessage ?? "Refreshing displays…")
                            .accessibilityIdentifier("Shared Displays Updating")
                    } else if let statusMessage {
                        Label(statusMessage, systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("Shared Displays Status")
                    }
                }
                .padding(16)
                .frame(maxWidth: 600)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("Choose Display")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done", action: onCancel)
                        .disabled(pendingDisplayID != nil)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Refresh Displays", systemImage: "arrow.clockwise", action: onRefresh)
                        .labelStyle(.iconOnly)
                        .accessibilityIdentifier("Refresh Shared Displays")
                        .disabled(requestInFlight || pendingDisplayID != nil)
                }
            }
        }
    }

    private func displayRow(_ display: InteractiveDisplayCandidateV1,
                            catalog: InteractiveDisplayCatalogResponseBodyV1) -> some View {
        let selected = display.displayID == catalog.selectedDisplayID
        let pending = display.id == pendingDisplayID
        return Button {
            if !selected { onSelect(display.id) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "display")
                    .font(.title3)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 4) {
                    Text(display.isMain ? "Main Display" : "Display \(display.ordinal)")
                        .font(.body.weight(.medium))
                    Text("\(display.pixelWidth) × \(display.pixelHeight)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if pending { ProgressView().controlSize(.small) }
                else if selected { Image(systemName: "checkmark.circle.fill") }
            }
            .foregroundStyle(selected ? Color.accentColor : Color.primary)
            .padding(14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(requestInFlight || pendingDisplayID != nil)
        .accessibilityIdentifier("Shared Display \(display.ordinal)")
        .accessibilityValue(pending ? "Switching" : selected ? "Showing" : "Available")
    }
}

@available(iOS 17.0, *)
private struct ClientSharedDisplayTopologyV0: View {
    let catalog: InteractiveDisplayCatalogResponseBodyV1
    let disabled: Bool
    let onSelect: (UUID) -> Void

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                if let layout = ClientSharedDisplayTopologyGeometryV0(
                    displays: catalog.displays, canvasSize: proxy.size
                ) {
                    ForEach(catalog.displays) { display in
                        if let frame = layout.framesByDisplayID[display.id] {
                            let selected = display.displayID == catalog.selectedDisplayID
                            Button {
                                if !selected { onSelect(display.id) }
                            } label: {
                                VStack(spacing: 6) {
                                    Image(systemName: "display")
                                    Text("\(display.ordinal)")
                                        .fontWeight(.semibold)
                                }
                                .font(.callout)
                                .minimumScaleFactor(0.6)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .foregroundStyle(selected ? Color.accentColor : Color.primary)
                                .background(selected ? Color.accentColor.opacity(0.18) : Color(uiColor: .secondarySystemBackground),
                                            in: RoundedRectangle(cornerRadius: 10))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 10)
                                        .strokeBorder(selected ? Color.accentColor : Color.secondary.opacity(0.4), lineWidth: selected ? 2 : 1)
                                }
                                .clipped()
                            }
                            .buttonStyle(.plain)
                            .frame(width: frame.width, height: frame.height)
                            .position(x: frame.midX, y: frame.midY)
                            .disabled(disabled)
                            .accessibilityIdentifier("Display Map Tile \(display.ordinal)")
                            .accessibilityLabel("Display \(display.ordinal)")
                            .accessibilityValue(selected ? "Showing" : "Available")
                        }
                    }
                }
            }
            // Offset does not enlarge a ZStack's intrinsic bounds. Give the
            // diagram its actual canvas before positioning display centers.
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
            .clipped()
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("Display Layout")
        }
    }
}
#endif
