import CompanionMacApp
import CompanionMacApplicationPlatform
import CompanionMacUI
import SwiftUI

@main
@MainActor
struct MacCompanionApplication: App {
    // Retains exact login-role identities without registering either role.
    private let loginRoles = MacCompanionLoginRoleComposition()
    // Construction retains the real dashboard product without starting XPC.
    @State private var dashboard = MacCompanionDashboardApplicationV1()

    var body: some Scene {
        MenuBarExtra(
            "Mac Companion",
            systemImage: "macbook.and.iphone"
        ) {
            MacCompanionDashboardRoot(application: dashboard)
        }
        .menuBarExtraStyle(.window)
    }
}

private struct MacCompanionDashboardRoot: View {
    let application: MacCompanionDashboardApplicationV1

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
        Task { @MainActor in
            _ = await application.retryStatus()
        }
    }

    private var source: MacAgentDashboardSourceV0 { application.source }
}
