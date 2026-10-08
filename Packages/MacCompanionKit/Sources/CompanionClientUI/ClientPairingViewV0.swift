#if os(iOS)
import CompanionPresentation
import SwiftUI

@available(iOS 17.0, *)
public struct ClientPairingViewV0: View {
    private let surface: ClientPairingSurfaceV0
    private let onScan: () -> Void
    private let onAcceptPreview: () -> Void
    private let onCancel: () -> Void
    private let onRetry: () -> Void
    private let onDone: () -> Void
    private let onPastePairingCode: ((String) -> Void)?
    @State private var enteringCode = false
    @State private var pairingCode = ""

    public init(
        presentation: PairingClientPresentation,
        onScan: @escaping () -> Void,
        onAcceptPreview: @escaping () -> Void,
        onCancel: @escaping () -> Void,
        onRetry: @escaping () -> Void,
        onDone: @escaping () -> Void,
        onPastePairingCode: ((String) -> Void)? = nil
    ) {
        surface = ClientPairingSurfaceV0(presentation: presentation)
        self.onScan = onScan
        self.onAcceptPreview = onAcceptPreview
        self.onCancel = onCancel
        self.onRetry = onRetry
        self.onDone = onDone
        self.onPastePairingCode = onPastePairingCode
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Image(systemName: "macbook.and.iphone")
                    .font(.system(size: 52, weight: .semibold))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                content
            }
            .frame(maxWidth: 520)
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Connect to Mac")
        .sheet(isPresented: $enteringCode, onDismiss: { pairingCode = "" }) {
            NavigationStack {
                Form {
                    Text("Paste or enter the complete pairing code from your Mac.")
                        .foregroundStyle(.secondary)
                    TextEditor(text: $pairingCode)
                        .frame(minHeight: 160)
                        .accessibilityLabel("Pairing Code")
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                .navigationTitle("Enter Pairing Code")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { pairingCode = ""; enteringCode = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Use Code") {
                            let value = pairingCode
                            pairingCode = ""
                            enteringCode = false
                            onPastePairingCode?(value)
                        }
                        .disabled(pairingCode.isEmpty)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch surface {
        case .scan:
            heading(
                "Scan the code on your Mac",
                detail: "Mac Companion on your Mac creates a temporary pairing code."
            )
            Button("Scan Pairing Code", systemImage: "qrcode.viewfinder") {
                onScan()
            }
            .buttonStyle(.borderedProminent)
            if onPastePairingCode != nil {
                Button("Enter Pairing Code", systemImage: "text.cursor") {
                    pairingCode = ""
                    enteringCode = true
                }
                .buttonStyle(.bordered)
            }

        case let .preview(preview):
            heading(
                "Ready to verify this Mac",
                detail: "The pairing code provides the expected fingerprint. Connect securely to verify it against the Mac’s live identity."
            )
            fingerprint(preview.fingerprint, verified: false)
            Label(
                "\(preview.routeCandidateCount) private route candidates",
                systemImage: "network"
            )
            actionRow(
                primaryTitle: "Connect Securely",
                primarySystemImage: "lock.shield",
                primary: onAcceptPreview,
                secondary: onCancel
            )

        case let .securing(progress):
            ProgressView()
                .controlSize(.large)
                .accessibilityLabel(securityProgressTitle(progress))
            heading(
                securityProgressTitle(progress),
                detail: "Keep this screen open while Mac Companion verifies the connection."
            )
            Button("Cancel", role: .cancel, action: onCancel)

        case let .compareOnMac(authentication):
            heading(
                "Compare this code on your Mac",
                detail: "Continue only when the same code appears in Mac Companion on the Mac."
            )
            Text(authentication.authenticationString)
                .font(.system(.largeTitle, design: .monospaced).weight(.bold))
                .textSelection(.enabled)
                .accessibilityLabel("Authentication code")
                .accessibilityValue(authentication.authenticationString)
            Button("Cancel", role: .cancel, action: onCancel)

        case let .recovering(authentication):
            ProgressView()
                .controlSize(.large)
                .accessibilityLabel("Recovering secure pairing")
            heading(
                "Finishing secure pairing…",
                detail: "The Mac saved your approval. Mac Companion is reconnecting with the same verified keys; no new code or approval is needed."
            )
            Text(authentication.authenticationString)
                .font(.system(.title2, design: .monospaced).weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityLabel("Previously verified authentication code")
                .accessibilityValue(authentication.authenticationString)
            Button("Cancel", role: .cancel, action: onCancel)

        case .saving:
            ProgressView("Saving this Mac securely…")
                .controlSize(.large)

        case let .paired(host):
            ContentUnavailableView {
                Label("Mac Connected", systemImage: "checkmark.circle.fill")
            } description: {
                Text("The verified Mac identity is saved on this device.")
            } actions: {
                Button("Continue", action: onDone)
                    .buttonStyle(.borderedProminent)
            }
            fingerprint(host.fingerprint, verified: true)

        case let .failed(failure):
            ContentUnavailableView {
                Label("Couldn’t Connect", systemImage: "exclamationmark.triangle")
            } description: {
                Text(pairingFailureDetail(failure))
            } actions: {
                Button("Try Again", action: onRetry)
                    .buttonStyle(.borderedProminent)
                Button("Cancel", role: .cancel, action: onCancel)
            }
        }
    }

    private func heading(_ title: String, detail: String) -> some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
            Text(detail)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private func fingerprint(
        _ value: String,
        verified: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(
                verified
                    ? "Verified Mac fingerprint"
                    : "Fingerprint from pairing code",
                systemImage: verified ? "checkmark.shield" : "qrcode"
            )
            .font(.headline)
            Text(
                verified
                    ? "Verified against the Mac’s live TLS identity."
                    : "Verification is pending until the secure connection succeeds."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 14))
    }

    private func actionRow(
        primaryTitle: String,
        primarySystemImage: String,
        primary: @escaping () -> Void,
        secondary: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 12) {
            Button(primaryTitle, systemImage: primarySystemImage, action: primary)
                .buttonStyle(.borderedProminent)
            Button("Cancel", role: .cancel, action: secondary)
        }
    }

    private func securityProgressTitle(
        _ progress: PairingSecurityProgress
    ) -> String {
        switch progress {
        case .connecting: "Connecting securely…"
        case .pinnedTLSVerified: "Mac identity verified"
        case .verifyingTranscript: "Verifying pairing…"
        }
    }

    private func pairingFailureDetail(
        _ failure: PairingClientPresentationFailure
    ) -> String {
        switch failure {
        case .invalidOrExpiredCode: "The pairing code is invalid or expired. Create a new code on your Mac."
        case .connectionFailed: "The private connection could not be established."
        case .identityVerificationFailed: "The Mac identity did not match the pairing code."
        case .hostRejected: "The Mac declined this pairing request."
        case .clientStorageUnavailable: "This device could not save the verified Mac identity."
        case .unknown: "The pairing attempt ended without a verified connection."
        }
    }
}

@available(iOS 17.0, *)
private struct ClientPairingViewV0Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            ClientPairingViewV0(
                presentation: PairingClientPresentation(),
                onScan: {},
                onAcceptPreview: {},
                onCancel: {},
                onRetry: {},
                onDone: {}
            )
        }
        .previewDisplayName("Pairing scan")
    }
}
#endif
