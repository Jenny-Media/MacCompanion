import AppIntents
import SwiftUI

struct RemoteSessionActivityActionsView: View {
    let resumeURL: URL
    let activityID: String
    var compact = false

    var body: some View {
        HStack(spacing: compact ? 8 : 12) {
            Link(destination: resumeURL) {
                Label("Resume", systemImage: "arrow.up.forward.app")
                    .lineLimit(1).minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, minHeight: compact ? 28 : 32)
            }
            .buttonStyle(.bordered).tint(.blue)
            Button(intent: EndRemoteSessionIntent(activityID: activityID)) {
                Label(compact ? "End" : "End Session", systemImage: "xmark.circle")
                    .lineLimit(1).minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, minHeight: compact ? 28 : 32)
            }
            .buttonStyle(.bordered).tint(.red)
            .accessibilityLabel("End Session")
        }
        .font(.subheadline.weight(.semibold))
        .controlSize(compact ? .small : .regular)
        .buttonBorderShape(.capsule)
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
                Image(systemName: "desktopcomputer")
                    .font(.body).foregroundStyle(.blue)
                    .accessibilityHidden(true)
                Text(attributes.macName)
                    .font(.headline).lineLimit(2).truncationMode(.tail)
                    .accessibilityLabel(attributes.macName)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(isStale ? "Paused" : phase.title)
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1).fixedSize(horizontal: true, vertical: false)
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
                Image(systemName: "desktopcomputer").font(.title2).foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 4) {
                    Text(attributes.macName).font(.headline).lineLimit(1)
                    Text(isStale ? "Paused · Tap to resume" : phase.title)
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            RemoteSessionActivityActionsView(resumeURL: attributes.resumeURL, activityID: activityID)
        }
        .padding(16)
    }
}
