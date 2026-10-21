import DeviceActivity
import Foundation

/// Runs at midnight, when the daily schedule starts, and locks the chosen apps if the new day
/// has reviews due. The app does the rest: it unlocks them when the last review is logged and
/// locks them again if one is undone.
final class LockMonitorExtension: DeviceActivityMonitor {
    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        guard activity == .dailyLock else { return }
        ShieldController.sync()
    }
}
