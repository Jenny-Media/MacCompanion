import AppKit
import CompanionAgent
import CompanionLifecycle
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
        MenuBarExtra {
            MacCompanionProductRoot(
                application: applicationDelegate.product,
                interactiveIndicator:
                    applicationDelegate.interactiveIndicator,
                updates: applicationDelegate.updates
            )
        } label: {
            Label(
                applicationDelegate.interactiveIndicator.isVisible
                    ? "Mac Companion Control Active"
                    : "Mac Companion",
                systemImage:
                    applicationDelegate.interactiveIndicator.isVisible
                        ? "record.circle.fill"
                        : "macbook.and.iphone"
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
    let interactiveIndicator: MacInteractiveActivityIndicatorV1
    let updates: MacCompanionSparkleAdapterV0

    private var launchTask: Task<Void, Never>?
    private var finishTask: Task<Void, Never>?

    override init() {
        let loginRoles = MacCompanionLoginRoleComposition()
        let setup = MacRemoteAccessSetupApplicationV1(
            agent: loginRoles.agent,
            menuApp: loginRoles.menuApp
        )
        let interactiveIndicator = MacInteractiveActivityIndicatorV1()
        let updates = MacCompanionSparkleAdapterV0()
        self.loginRoles = loginRoles
        self.interactiveIndicator = interactiveIndicator
        self.updates = updates
        product = MacCompanionProductApplicationV1(
            agentRegistration: loginRoles.agentRaw,
            setup: setup,
            dashboardFactory: {
                MacCompanionDashboardApplicationV1(
                    interactiveIndicator: interactiveIndicator
                )
            }
        )
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard launchTask == nil, finishTask == nil else { return }
        updates.start()
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
    let interactiveIndicator: MacInteractiveActivityIndicatorV1
    let updates: MacCompanionSparkleAdapterV0

    var body: some View {
        VStack(spacing: 0) {
            if interactiveIndicator.isVisible {
                interactiveActivity
                Divider()
            }
            routedContent
            Divider()
            MacCompanionUpdateFooter(adapter: updates)
        }
    }

    @ViewBuilder
    private var routedContent: some View {
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

    private var interactiveActivity: some View {
        HStack(spacing: 12) {
            Image(systemName: "record.circle.fill")
                .font(.title2)
                .foregroundStyle(.red)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(
                    interactiveIndicator.phase == .stopping
                        ? "Stopping Remote Control"
                        : "Remote Control Active"
                )
                .font(.headline)
                Text(
                    interactiveIndicator.deviceDisplayName
                        ?? "Approved device"
                )
                .font(.callout)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Stop", role: .destructive) {
                Task { @MainActor in
                    try? await interactiveIndicator.requestStop()
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(interactiveIndicator.phase != .active)
        }
        .padding(14)
        .background(.red.opacity(0.08))
        .accessibilityElement(children: .contain)
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

private struct MacCompanionUpdateFooter: View {
    @ObservedObject var adapter: MacCompanionSparkleAdapterV0

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(iconStyle)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if case .checking = adapter.phase {
                ProgressView()
                    .controlSize(.small)
            } else if showsCheckButton {
                Button("Check for Updates") {
                    adapter.probeForUpdates()
                }
                .controlSize(.small)
                .disabled(!adapter.canProbe)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .accessibilityElement(children: .contain)
    }

    private var showsCheckButton: Bool {
        switch adapter.phase {
        case .ready, .current, .updateAvailable, .failed:
            true
        case .notConfigured, .invalidConfiguration, .checking:
            false
        }
    }

    private var title: String {
        switch adapter.phase {
        case .notConfigured:
            "Updates not configured"
        case .invalidConfiguration:
            "Update configuration invalid"
        case let .ready(channel):
            "\(channelName(channel)) updates ready"
        case .checking:
            "Checking for updates…"
        case .current:
            "Mac Companion is up to date"
        case let .updateAvailable(_, displayVersion, _):
            "Version \(displayVersion) is available"
        case .failed:
            "Update check unavailable"
        }
    }

    private var detail: String {
        switch adapter.phase {
        case .notConfigured:
            "This development build has no release feed authority."
        case .invalidConfiguration:
            "The release channel, feed, or public key failed validation."
        case let .ready(channel), let .current(channel):
            "\(channelName(channel)) channel · Automatic checks are off"
        case let .checking(channel):
            "Reading the signed \(channelName(channel).lowercased()) feed"
        case let .updateAvailable(channel, _, build):
            "\(channelName(channel)) build \(build) · Installation remains locally gated"
        case let .failed(channel):
            "The \(channelName(channel).lowercased()) feed was not accepted."
        }
    }

    private var systemImage: String {
        switch adapter.phase {
        case .invalidConfiguration, .failed:
            "exclamationmark.triangle"
        case .updateAvailable:
            "arrow.down.circle"
        case .checking:
            "arrow.trianglehead.2.clockwise.rotate.90"
        case .notConfigured, .ready, .current:
            "checkmark.shield"
        }
    }

    private var iconStyle: AnyShapeStyle {
        switch adapter.phase {
        case .invalidConfiguration, .failed:
            AnyShapeStyle(.orange)
        case .updateAvailable:
            AnyShapeStyle(.blue)
        case .notConfigured, .ready, .checking, .current:
            AnyShapeStyle(.secondary)
        }
    }

    private func channelName(_ channel: MacUpdateChannelV0) -> String {
        switch channel {
        case .beta: "Beta"
        case .stable: "Stable"
        }
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
