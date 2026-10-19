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
                RemoteSessionActivityCompactSymbol(attributes: context.attributes)
            } minimal: {
                RemoteSessionActivityCompactSymbol(attributes: context.attributes)
            }
            .widgetURL(context.attributes.resumeURL)
            .keylineTint(.blue)
        }
    }
}
