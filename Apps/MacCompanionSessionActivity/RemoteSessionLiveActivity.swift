import ActivityKit
import SwiftUI
import WidgetKit

@main
struct MacCompanionSessionWidgets: WidgetBundle {
    var body: some Widget { RemoteSessionLiveActivity() }
}

struct RemoteSessionLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RemoteSessionActivityAttributes.self) { context in
            RemoteSessionActivityCard(attributes: context.attributes, phase: context.state.phase,
                isStale: context.isStale, activityID: context.activityID)
            .foregroundStyle(.white)
            .activityBackgroundTint(.black.opacity(0.92))
            .activitySystemActionForegroundColor(.white)
            .widgetURL(context.attributes.resumeURL)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.bottom) {
                    RemoteSessionExpandedContent(attributes: context.attributes,
                        phase: context.state.phase, isStale: context.isStale,
                        activityID: context.activityID)
                }
            } compactLeading: {
                Text(context.attributes.macName).font(.caption.weight(.semibold))
                    .lineLimit(1).truncationMode(.tail).frame(maxWidth: 72)
                    .accessibilityLabel(context.attributes.macName)
            } compactTrailing: {
                phaseSymbol(context.state.phase, isStale: context.isStale)
            } minimal: {
                Image(systemName: "desktopcomputer").foregroundStyle(.blue)
            }
            .widgetURL(context.attributes.resumeURL)
            .keylineTint(.blue)
        }
    }

    private func phaseSymbol(_ phase: RemoteSessionActivityAttributes.Phase, isStale: Bool) -> some View {
        Image(systemName: isStale || phase == .paused ? "pause.fill" :
            phase == .reconnecting ? "arrow.triangle.2.circlepath" : "checkmark")
            .accessibilityLabel(isStale ? "Paused · Tap to resume" : phase.title)
    }
}
