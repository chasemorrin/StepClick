import ActivityKit
import Foundation

/// Starts, updates and ends the Live Activity. App target only.
@MainActor
final class LiveActivityController {
    private var activity: Activity<MetronomeActivityAttributes>?

    var isActive: Bool {
        activity?.activityState == .active
    }

    /// Shows the activity (or refreshes it if one is already up).
    func start(state: MetronomeActivityAttributes.ContentState) {
        if let current = activity, current.activityState != .active {
            activity = nil   // the person swiped it away
        }
        if activity == nil {
            activity = Activity<MetronomeActivityAttributes>.activities
                .first(where: { $0.activityState == .active })
        }
        if activity != nil {
            update(state: state)
            return
        }

        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        do {
            activity = try Activity<MetronomeActivityAttributes>.request(
                attributes: MetronomeActivityAttributes(),
                content: ActivityContent(state: state, staleDate: nil),
                pushType: nil
            )
        } catch {
            // Starting one is only allowed while the app is on screen.
            print("StepClick: could not start Live Activity: \(error)")
        }
    }

    func update(state: MetronomeActivityAttributes.ContentState) {
        guard let activity else { return }
        Task {
            await activity.update(ActivityContent(state: state, staleDate: nil))
        }
    }

    func end() {
        guard let activity else { return }
        self.activity = nil
        Task {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}
