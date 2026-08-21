#if os(macOS)
import CompanionPresentation
import SwiftUI

@available(macOS 14.0, *)
public struct MacInteractiveWarningViewV0: View {
    private let projection: MacInteractiveWarningProjectionV0
    private let onStop: () -> Void

    public init(
        presentation: LocalInteractiveWarningPresentation,
        onStop: @escaping () -> Void
    ) {
        projection = MacInteractiveWarningProjectionV0(presentation: presentation)
        self.onStop = onStop
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: statusSymbol)
                    .font(.title2)
                    .foregroundStyle(statusColor)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(statusTitle)
                        .font(.headline)
                    Text(projection.deviceDisplayName)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            Text(statusDetail)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 7) {
                ForEach(projection.effectLabels, id: \.self) { effect in
                    Label(effect, systemImage: "circle.fill")
                        .labelStyle(.titleAndIcon)
                }
            }
            .accessibilityElement(children: .contain)

            Button("Stop This Session", role: .destructive, action: onStop)
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(!projection.canStop)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(18)
        .frame(minWidth: 360, idealWidth: 420)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .contain)
    }

    private var statusTitle: String {
        switch projection.status {
        case .awaitingPhoneApproval: "Waiting for phone approval"
        case .starting: "Interactive Control is starting"
        case .active: "Interactive Control is active"
        case .paused: "Interactive Control is paused"
        case .ending: "Stopping Interactive Control"
        case .ended: "Interactive Control ended"
        }
    }

    private var statusDetail: String {
        switch projection.status {
        case .awaitingPhoneApproval:
            "No session starts until the request is approved on the phone."
        case .starting:
            "The approved session is preparing capture and input."
        case .active:
            "This device can use only the listed effects for this session."
        case .paused:
            "Capture or input is temporarily suspended."
        case .ending:
            "Remote authority and local capture/input are being removed."
        case .ended:
            "Remote authority and local capture/input have been removed."
        }
    }

    private var statusSymbol: String {
        switch projection.status {
        case .active: "record.circle.fill"
        case .awaitingPhoneApproval, .starting, .ending: "clock.arrow.circlepath"
        case .paused: "pause.circle.fill"
        case .ended: "checkmark.circle.fill"
        }
    }

    private var statusColor: Color {
        switch projection.status {
        case .active: .red
        case .paused, .awaitingPhoneApproval, .starting, .ending: .orange
        case .ended: .green
        }
    }
}
#endif
