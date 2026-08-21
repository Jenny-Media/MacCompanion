import CompanionMacApp
import CompanionMacUI
import SwiftUI

@main
struct MacCompanionApplication: App {
    var body: some Scene {
        MenuBarExtra(
            "Mac Companion",
            systemImage: "macbook.and.iphone"
        ) {
            MacCompanionDashboardRoot()
        }
        .menuBarExtraStyle(.window)
    }
}

private struct MacCompanionDashboardRoot: View {
    @State private var source: MacAgentDashboardSourceV0 = .unavailable

    var body: some View {
        dashboard
    }

    @ViewBuilder
    private var dashboard: some View {
        if let view = try? MacAgentDashboardViewV0(
            source: source,
            perform: perform
        ) {
            view
        } else {
            ContentUnavailableView(
                "Mac Companion unavailable",
                systemImage: "exclamationmark.triangle",
                description: Text("The local dashboard state was invalid.")
            )
            .frame(width: 520, height: 520)
        }
    }

    private func perform(_ action: MacAgentDashboardActionV0) {
        guard action == .retryStatus else { return }
        source = .loading
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            source = .unavailable
        }
    }
}
