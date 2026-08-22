import AppKit
import CompanionAgent
import CompanionMacApp
import CompanionMacApplicationPlatform
import CompanionMacUI
import SwiftUI

@main
@MainActor
struct MacCompanionApplication: App {
    @NSApplicationDelegateAdaptor(
        MacCompanionApplicationDelegate.self
    ) private var applicationDelegate

    var body: some Scene {
        MenuBarExtra(
            "Mac Companion",
            systemImage: "macbook.and.iphone"
        ) {
            MacCompanionProductRoot(
                application: applicationDelegate.product
            )
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
private final class MacCompanionApplicationDelegate:
    NSObject,
    NSApplicationDelegate
{
    let loginRoles: MacCompanionLoginRoleComposition
    let product: MacCompanionProductApplicationV1

    private var launchTask: Task<Void, Never>?
    private var finishTask: Task<Void, Never>?

    override init() {
        let loginRoles = MacCompanionLoginRoleComposition()
        let setup = MacRemoteAccessSetupApplicationV1(
            agent: loginRoles.agent,
            menuApp: loginRoles.menuApp
        )
        self.loginRoles = loginRoles
        product = MacCompanionProductApplicationV1(
            agentRegistration: loginRoles.agentRaw,
            setup: setup
        )
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard launchTask == nil, finishTask == nil else { return }
        let product = self.product
        launchTask = Task { @MainActor in await product.start() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        beginBestEffortFinish()
    }

    private func beginBestEffortFinish() {
        guard finishTask == nil else { return }
        let launchTask = self.launchTask
        let product = self.product
        launchTask?.cancel()
        finishTask = Task { @MainActor in
            if let launchTask { await launchTask.value }
            await product.finish()
        }
    }

    isolated deinit {
        launchTask?.cancel()
        guard finishTask == nil else { return }
        let product = self.product
        Task { await product.finish() }
    }
}

private struct MacCompanionProductRoot: View {
    let application: MacCompanionProductApplicationV1

    var body: some View {
        switch application.route {
        case .checking:
            ProgressView("Checking Mac Companion…")
                .frame(width: 520, height: 320)
        case .setup:
            MacCompanionRemoteAccessSetupView(application: application)
        case .dashboard:
            if let dashboard = application.dashboard {
                MacCompanionDashboardRoot(application: dashboard)
            } else {
                unavailable
            }
        case .requiresLoginItemApproval:
            ContentUnavailableView(
                "Login item approval required",
                systemImage: "person.badge.key",
                description: Text(
                    "Allow Mac Companion in System Settings > General > Login Items, then try again."
                )
            )
            .overlay(alignment: .bottom) { retryButton.padding(24) }
            .frame(width: 520, height: 360)
        case .unavailable:
            unavailable
        }
    }

    private var unavailable: some View {
        ContentUnavailableView(
            "Mac Companion unavailable",
            systemImage: "exclamationmark.triangle",
            description: Text(
                "The signed Mac Agent could not be verified as ready. No remote access was granted."
            )
        )
        .overlay(alignment: .bottom) { retryButton.padding(24) }
        .frame(width: 520, height: 360)
    }

    private var retryButton: some View {
        Button("Check Again") {
            Task { @MainActor in await application.retryRoute() }
        }
        .buttonStyle(.borderedProminent)
    }
}

private struct MacCompanionRemoteAccessSetupView: View {
    let application: MacCompanionProductApplicationV1

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label(title, systemImage: systemImage)
                .font(.title2.weight(.semibold))
            Text(detail)
                .foregroundStyle(.secondary)

            if case .awaitingConsent = application.setup.state {
                consentFacts
            }

            Spacer(minLength: 8)
            actions
        }
        .padding(24)
        .frame(width: 520, height: 430)
    }

    private var title: String {
        switch application.setup.state {
        case .idle, .declined:
            "Set up Mac Companion"
        case .awaitingConsent:
            "Allow remote access services?"
        case .registeringAgent, .connecting, .readingOffer:
            "Preparing the Mac Agent"
        case .enabling, .convergingMenu, .enabled:
            "Enabling Mac Companion"
        case .failed(.menuRegistrationPending):
            "Finish login item setup"
        case .failed:
            "Setup could not finish"
        case .outcomeUnknown:
            "Check the Agent state"
        }
    }

    private var detail: String {
        switch application.setup.state {
        case .idle, .declined:
            "Mac Companion is currently off for this macOS account. Setup starts only after you choose Enable."
        case .registeringAgent, .connecting, .readingOffer:
            "Registering and authenticating the per-user Agent. This does not grant a remote capability."
        case .awaitingConsent:
            "Review the fixed product boundary below. This confirmation enables the Agent, not access to your screen, keyboard, mouse, or actions."
        case .enabling, .convergingMenu, .enabled:
            "Waiting for durable Agent confirmation and a fresh authenticated readiness check."
        case .failed(.agentRegistration(.requiresApproval)),
                .failed(.menuRegistrationPending(.requiresApproval)):
            "macOS requires approval in System Settings > General > Login Items. No readiness or remote capability was granted."
        case .failed(.agentCleanup):
            "The setup-only login item could not be removed. Review Login Items before trying again."
        case .failed:
            "The attempt failed closed before readiness. You can retry without granting Observe, Act, or Control."
        case .outcomeUnknown:
            "The enable command may have reached durable storage, so Mac Companion kept the Agent registered and will reconcile instead of guessing."
        }
    }

    private var systemImage: String {
        switch application.setup.state {
        case .idle, .declined: "power"
        case .awaitingConsent: "hand.raised.fill"
        case .registeringAgent, .connecting, .readingOffer,
                .enabling, .convergingMenu, .enabled:
            "clock.arrow.circlepath"
        case .failed, .outcomeUnknown: "exclamationmark.triangle"
        }
    }

    private var consentFacts: some View {
        VStack(alignment: .leading, spacing: 10) {
            setupFact(
                "Per-user Agent",
                "Runs only for this logged-in macOS account and can be disabled from Mac Companion or Login Items."
            )
            setupFact(
                "No vendor relay",
                "Connections use your local network or a private route you configure."
            )
            setupFact(
                "Separate permissions",
                "Observe, approved actions, screen viewing, mouse, and keyboard remain independently granted."
            )
            setupFact(
                "Your Mac stays authoritative",
                "Pairing, grants, permission checks, revocation, and the visible stop control remain on this Mac."
            )
        }
        .padding(14)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var actions: some View {
        switch application.setup.state {
        case .idle, .declined,
                .failed(.agentRegistration),
                .failed(.transportUnavailable),
                .failed(.invalidOffer),
                .failed(.consentExpired):
            Button("Enable Mac Companion") {
                Task { @MainActor in try? await application.setup.begin() }
            }
            .buttonStyle(.borderedProminent)
        case .awaitingConsent:
            HStack {
                Button("Not Now", role: .cancel) {
                    Task {
                        @MainActor in try? await application.setup.decline()
                    }
                }
                Spacer()
                Button("Enable Mac Companion") {
                    Task {
                        @MainActor in try? await application.setup.confirm()
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        case .failed(.menuRegistrationPending):
            Button("Finish Setup") {
                Task {
                    @MainActor in
                    try? await application.setup.retryMenuConvergence()
                }
            }
            .buttonStyle(.borderedProminent)
        case .outcomeUnknown:
            Button("Check Agent State") {
                Task { @MainActor in await application.retryRoute() }
            }
            .buttonStyle(.borderedProminent)
        case .failed(.agentCleanup):
            Button("Check Again") {
                Task { @MainActor in await application.retryRoute() }
            }
        case .registeringAgent, .connecting, .readingOffer, .enabling,
                .convergingMenu, .enabled:
            ProgressView()
        }
    }

    private func setupFact(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.headline)
            Text(detail).font(.callout).foregroundStyle(.secondary)
        }
    }
}

private struct MacCompanionDashboardRoot: View {
    let application: MacCompanionDashboardApplicationV1

    var body: some View {
        VStack(spacing: 0) {
            dashboard
            Divider()
            HStack {
                Spacer()
                Button("Pair New Device") {
                    Task { @MainActor in
                        await application.beginPairing()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(pairingSheetPresented)
            }
            .padding(16)
        }
        .sheet(isPresented: pairingSheetBinding) {
            pairingSheet
        }
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

    @ViewBuilder
    private var pairingSheet: some View {
        if let review = try? MacPairingReviewViewV0(
            presentation: application.pairingReview,
            onDraftChanged: { value in
                Task { @MainActor in
                    await application.updatePairingDeviceName(value)
                }
            },
            perform: { action in
                Task { @MainActor in
                    let mapped: MacCompanionPairingReviewActionV1 =
                        switch action {
                        case .approve: .approve
                        case .decline: .decline
                        case .retryDecision: .retryDecision
                        }
                    await application.performPairingReviewAction(mapped)
                }
            }
        ) {
            review
        } else if let pairing = try? MacPairingSessionViewV0(
            presentation: application.pairingSession,
            perform: { action in
                Task { @MainActor in
                    let mapped: MacCompanionPairingActionV1 = switch action {
                    case .retryCreation: .retryCreation
                    case .dismissPairing: .dismissPairing
                    case .retryDismissal: .retryDismissal
                    }
                    await application.performPairingAction(mapped)
                }
            }
        ) {
            pairing
        } else {
            ProgressView("Updating pairing state…")
                .padding(32)
        }
    }

    private var pairingSheetBinding: Binding<Bool> {
        Binding(
            get: { pairingSheetPresented },
            set: { _ in }
        )
    }

    private var pairingSheetPresented: Bool {
        switch application.pairingReview.phase {
        case .idle:
            break
        case .reviewing, .deciding, .decisionFailed:
            return true
        }
        switch application.pairingSession.phase {
        case .idle:
            return false
        case .creating, .creationFailed, .presenting, .dismissing,
                .dismissalFailed:
            return true
        }
    }

    private var source: MacAgentDashboardSourceV0 { application.source }
}
