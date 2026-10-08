#if os(iOS)
import CompanionInteractiveShared
import CompanionInteractiveWire
import SwiftUI

@available(iOS 17.0, *)
public struct ClientSurfacePickerViewV0: View {
    @State private var searchText = ""
    @State private var applicationPath: [UUID] = []
    private let isBusy: Bool
    private let statusMessage: String?
    private let choices: [ClientSurfaceChoiceV0]
    private let windowsByApplication: [UUID: [ClientSurfaceChoiceV0]]
    private let onSelect: (ClientSurfaceChoiceV0) -> Void
    private let onRefresh: () -> Void
    private let onCancel: () -> Void

    public init(
        candidates: [InteractiveSurfaceTargetCandidateV0],
        isBusy: Bool = false,
        statusMessage: String? = nil,
        onSelect: @escaping (ClientSurfaceChoiceV0) -> Void,
        onRefresh: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.isBusy = isBusy
        self.statusMessage = statusMessage
        choices = ClientSurfaceChoiceProjectionV0.make(
            candidates: candidates
        )
        windowsByApplication = Dictionary(
            candidates.filter { $0.kind == .application }.map { candidate in
                let token = candidate.targetToken.rawValue
                return (token, ClientSurfaceChoiceProjectionV0.windows(
                    forApplication: token, candidates: candidates
                ))
            }, uniquingKeysWith: { first, _ in first }
        )
        self.onSelect = onSelect
        self.onRefresh = onRefresh
        self.onCancel = onCancel
    }

    public var body: some View {
        NavigationStack(path: $applicationPath) {
            List {
                transitionStatus
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
                            Text("Open a window on the Mac, then refresh.")
                        }
                        .listRowBackground(Color.clear)
                    } else if filteredChoices.isEmpty {
                        ContentUnavailableView.search(text: searchText)
                            .listRowBackground(Color.clear)
                    } else {
                        ForEach(filteredChoices) { choice in
                            pickerRow(choice)
                        }
                    }
                } header: {
                    Text("Applications and Windows")
                } footer: {
                    Text("Choose an app, then pick the window to show. You can also choose a window directly.")
                }
            }
            .navigationTitle("Choose Mac View")
            .navigationDestination(for: UUID.self) { token in
                applicationWindows(token)
            }
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
                    Button("Refresh", systemImage: "arrow.clockwise", action: refreshTargets)
                        .disabled(isBusy)
                }
            }
            .onChange(of: choices.map(\.id)) { _, _ in
                // Refresh replaces the one-use inventory tokens. Do not retain
                // a destination or window choice from the retired inventory.
                applicationPath.removeAll()
            }
        }
    }

    @ViewBuilder
    private func pickerRow(_ choice: ClientSurfaceChoiceV0) -> some View {
        if choice.kind == .application, let token = choice.targetToken {
            let windows = windowsByApplication[token] ?? []
            if windows.count == 1, let window = windows.first {
                choiceButton(choice, selection: window, detail: "Show this window")
            } else {
                NavigationLink(value: token) {
                    choiceLabel(choice, detail: "Choose a window")
                }
                .accessibilityIdentifier(choiceIdentifier(choice))
                .accessibilityHint("Choose which app window to show")
                .disabled(isBusy)
            }
        } else {
            choiceButton(choice)
        }
    }

    @ViewBuilder
    private func applicationWindows(_ token: UUID) -> some View {
        if let application = choices.first(where: {
            $0.kind == .application && $0.targetToken == token
        }) {
            List {
                transitionStatus
                Section("Choose a Window") {
                    let windows = windowsByApplication[token] ?? []
                    if windows.isEmpty {
                        Text("No windows available. Refresh to try again.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(windows) { choice in
                            choiceButton(choice)
                        }
                    }
                }
                Section {
                    choiceButton(application, title: "All App Windows",
                        detail: "On the selected display")
                } footer: {
                    Text("All windows keep their Mac positions. Space between them appears blank.")
                }
            }
            .navigationTitle(application.applicationName ?? "App Windows")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Refresh", systemImage: "arrow.clockwise", action: refreshTargets)
                        .disabled(isBusy)
                }
            }
        } else {
            ContentUnavailableView("Windows Refreshed", systemImage: "arrow.clockwise",
                description: Text("Go back to choose a current window."))
        }
    }

    @ViewBuilder
    private var transitionStatus: some View {
        if isBusy {
            Section {
                ProgressView(statusMessage ?? "Updating Mac View…")
                    .accessibilityIdentifier("Surface Picker Busy")
            }
        } else if let statusMessage {
            Section {
                Text(statusMessage).foregroundStyle(.secondary)
            }
        }
    }

    private func refreshTargets() {
        applicationPath.removeAll()
        onRefresh()
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
        _ choice: ClientSurfaceChoiceV0,
        selection: ClientSurfaceChoiceV0? = nil,
        title: String? = nil,
        detail: String? = nil
    ) -> some View {
        Button {
            onSelect(selection ?? choice)
        } label: {
            choiceLabel(choice, title: title, detail: detail)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(choiceIdentifier(choice))
        .disabled(isBusy || !choice.available)
        .accessibilityHint(
            choice.available
                ? "Switches the live Mac view"
                : "Refresh after the window becomes available"
        )
    }

    private func choiceIdentifier(_ choice: ClientSurfaceChoiceV0) -> String {
        "Surface \(choice.kind == .window ? "Window" : "Application") \(choice.targetToken?.uuidString ?? "Desktop")"
    }

    private func choiceLabel(_ choice: ClientSurfaceChoiceV0,
        title: String? = nil, detail: String? = nil) -> some View {
        HStack(spacing: 12) {
            Image(systemName: choiceSystemImage(choice))
                .frame(width: 28)
                .foregroundStyle(
                    choice.available
                        ? Color.accentColor
                        : Color.secondary
                )
            VStack(alignment: .leading, spacing: 3) {
                Text(title ?? choiceTitle(choice))
                if let detail = detail ?? choiceDetail(choice) {
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

    private func choiceTitle(_ choice: ClientSurfaceChoiceV0) -> String {
        switch choice.kind {
        case .desktop:
            "Desktop"
        case .application:
            choice.applicationName ?? "Application"
        case .window:
            choice.windowTitle ?? "\(choice.applicationName ?? "App") — Window \(choice.windowOrdinal ?? 0)"
        case .focusedRegion:
            "Smart Zoom"
        }
    }

    private func choiceDetail(_ choice: ClientSurfaceChoiceV0) -> String? {
        switch choice.kind {
        case .desktop:
            nil
        case .application:
            "All app windows on this display"
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
