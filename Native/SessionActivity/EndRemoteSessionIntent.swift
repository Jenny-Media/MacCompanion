import ActivityKit
import AppIntents
import Foundation

struct EndRemoteSessionIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "End Session"
    static let isDiscoverable = false
    static var supportedModes: IntentModes { .background }

    @Parameter(title: "Session Activity") var activityID: String

    init() {}
    init(activityID: String) { self.activityID = activityID }

    @MainActor func perform() async throws -> some IntentResult {
        await RemoteSessionActivityActions.end(activityID: activityID)
        return .result()
    }
}

enum RemoteSessionActivityActions {
    static let endRequested = Notification.Name("media.jenny.maccompanion.session-activity.end")

    @MainActor static func end(activityID: String) async {
        guard !activityID.isEmpty, activityID.utf8.count <= 256 else { return }
        // LiveActivityIntent executes in the app process. The existing viewer
        // consumes only its own activity ID; an orphan has no connection to stop.
        NotificationCenter.default.post(name: endRequested, object: activityID)
        await dismissActivity(activityID)
    }
    nonisolated private static func dismissActivity(_ activityID: String) async {
        if let activity = Activity<RemoteSessionActivityAttributes>.activities.first(where: { $0.id == activityID }) {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}
