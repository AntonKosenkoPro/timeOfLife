import SwiftUI
import WidgetKit

/// Entry point of the Live Activities widget extension (live-activities
/// change). Without this bundle the system finds no `ActivityConfiguration`
/// for `TimerActivityAttributes`: request/end still succeed, so the activity
/// goes live, but every face renders as an empty black surface.
@main
struct LifioLiveActivitiesBundle: WidgetBundle {
    var body: some Widget {
        TimerLiveActivityWidget()
    }
}
