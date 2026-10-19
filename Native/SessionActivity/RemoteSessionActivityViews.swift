import AppIntents
import SwiftUI

/// Compact and minimal presentations identify the return shortcut, not socket health.
/// Only expanded and Lock Screen content depend on phase and status freshness.
struct RemoteSessionActivityCompactSymbol: View {
    let attributes: RemoteSessionActivityAttributes

    var body: some View {
        Image(systemName: attributes.symbol)
            .accessibilityLabel("Return to \(attributes.macName)")
    }
}

struct RemoteSessionActivityActionsView: View {
    let resumeURL: URL
    let activityID: String
    var compact = false

    var body: some View {
        HStack(spacing: compact ? 8 : 12) {
            Link(destination: resumeURL) {
                actionLabel("Open", systemImage: "arrow.up.forward.app")
            }
            .buttonStyle(.bordered).tint(.blue)
            .accessibilityLabel("Open")
            Button(intent: EndRemoteSessionIntent(activityID: activityID)) {
                actionLabel("Disconnect", systemImage: "xmark.circle")
            }
            .buttonStyle(.bordered).tint(.red)
            .accessibilityLabel("Disconnect")
        }
        .font(.subheadline.weight(.semibold))
        .controlSize(compact ? .small : .regular)
        .buttonBorderShape(.capsule)
    }
    private func actionLabel(_ title: LocalizedStringKey, systemImage: String) -> some View {
        Group {
            // Preserve readable action names in the narrow expanded island.
            if compact { Text(title) }
            else { Label(title, systemImage: systemImage) }
        }.lineLimit(1).minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, minHeight: compact ? 28 : 32)
    }
}

/// The expanded island's bottom region spans the available width below the camera.
/// Keep text here rather than squeezing the phase beside the camera cutout.
struct RemoteSessionExpandedContent: View {
    let attributes: RemoteSessionActivityAttributes
    let phase: RemoteSessionActivityAttributes.Phase
    let isStale: Bool
    let activityID: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: attributes.symbol)
                    .font(.body).foregroundStyle(.blue)
                    .accessibilityHidden(true)
                Text(attributes.macName)
                    .font(.headline).lineLimit(2).truncationMode(.tail)
                    .accessibilityLabel(attributes.macName)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(isStale ? "Needs checking" : phase.title)
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1).fixedSize(horizontal: true, vertical: false)
            }
            if attributes.kind == .terminal {
                Text("Terminal")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            RemoteSessionActivityActionsView(resumeURL: attributes.resumeURL,
                activityID: activityID, compact: true)
        }
        // Keep every expanded element below the camera and inset from the curved mask.
        .padding(.top, 8)
        .padding(.horizontal, 4)
        .padding(.bottom, 4)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }
}

struct RemoteSessionActivityCard: View {
    let attributes: RemoteSessionActivityAttributes
    let phase: RemoteSessionActivityAttributes.Phase
    let isStale: Bool
    let activityID: String
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: attributes.symbol).font(.title2).foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 4) {
                    Text(attributes.macName).font(.headline).lineLimit(1)
                    Text(isStale ? "Open to check connection" : phase.title)
                        .font(.subheadline).foregroundStyle(.secondary)
                    if attributes.kind == .terminal {
                        Text("Terminal")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            RemoteSessionActivityActionsView(resumeURL: attributes.resumeURL, activityID: activityID)
        }
        .padding(16)
    }
}
