#if os(iOS)
import CompanionInteractiveShared
import CompanionInteractiveWire
import SwiftUI

@available(iOS 17.0, *)
public struct ClientSurfacePickerViewV0: View {
    @State private var searchText = ""
    private let choices: [ClientSurfaceChoiceV0]
    private let onSelect: (ClientSurfaceChoiceV0) -> Void
    private let onRefresh: () -> Void
    private let onCancel: () -> Void

    public init(
        candidates: [InteractiveSurfaceTargetCandidateV0],
        onSelect: @escaping (ClientSurfaceChoiceV0) -> Void,
        onRefresh: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        choices = ClientSurfaceChoiceProjectionV0.make(
            candidates: candidates
        )
        self.onSelect = onSelect
        self.onRefresh = onRefresh
        self.onCancel = onCancel
    }

    public var body: some View {
        NavigationStack {
            List {
                Section {
                    choiceButton(.desktop)
                } footer: {
                    Text("Desktop always shows the selected Mac display.")
                }

                Section {
                    if choices.count == 1 {
                        ContentUnavailableView {
                            Label("No Targets Available", systemImage: "rectangle.stack.badge.minus")
                        } description: {
                            Text("Refresh to ask the Mac for a new privacy-limited list.")
                        }
                        .listRowBackground(Color.clear)
                    } else if filteredChoices.isEmpty {
                        ContentUnavailableView.search(text: searchText)
                            .listRowBackground(Color.clear)
                    } else {
                        ForEach(filteredChoices) { choice in
                            choiceButton(choice)
                        }
                    }
                } header: {
                    Text("Applications and Windows")
                } footer: {
                    Text("Window titles and document names never leave the Mac.")
                }
            }
            .navigationTitle("Choose Mac View")
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Find an app or window"
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel, action: onCancel)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Refresh", systemImage: "arrow.clockwise", action: onRefresh)
                }
            }
        }
    }

    private var filteredChoices: [ClientSurfaceChoiceV0] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return choices.dropFirst().filter { choice in
            query.isEmpty
                || choiceTitle(choice).localizedStandardContains(query)
                || (choiceDetail(choice)?.localizedStandardContains(query) ?? false)
        }
    }

    private func choiceButton(
        _ choice: ClientSurfaceChoiceV0
    ) -> some View {
        Button {
            onSelect(choice)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: choiceSystemImage(choice))
                    .frame(width: 28)
                    .foregroundStyle(
                        choice.available
                            ? Color.accentColor
                            : Color.secondary
                    )
                VStack(alignment: .leading, spacing: 3) {
                    Text(choiceTitle(choice))
                    if let detail = choiceDetail(choice) {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if !choice.available {
                    Text("Unavailable")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!choice.available)
        .accessibilityHint(
            choice.available
                ? "Switches the live Mac view"
                : "Refresh after the window becomes available"
        )
    }

    private func choiceTitle(_ choice: ClientSurfaceChoiceV0) -> String {
        switch choice.kind {
        case .desktop:
            "Desktop"
        case .application:
            choice.applicationName ?? "Application"
        case .window:
            "Window \(choice.windowOrdinal ?? 0)"
        case .focusedRegion:
            "Smart Zoom"
        }
    }

    private func choiceDetail(_ choice: ClientSurfaceChoiceV0) -> String? {
        switch choice.kind {
        case .desktop:
            nil
        case .application:
            "Application Focus"
        case .window:
            choice.applicationName
        case .focusedRegion:
            "Focused Region"
        }
    }

    private func choiceSystemImage(
        _ choice: ClientSurfaceChoiceV0
    ) -> String {
        switch choice.kind {
        case .desktop: "desktopcomputer"
        case .application: "app.window"
        case .window: "macwindow"
        case .focusedRegion: "viewfinder"
        }
    }
}
#endif
