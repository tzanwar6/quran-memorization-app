import FamilyControls
import Foundation

// Shared with the Screen Time extensions, so nothing here may depend on app-only code.

/// The promise not to loosen the lock. While it stands the settings are fixed, except during one
/// half hour a week that the user chose when making the promise.
struct LockCommitment: Equatable {
    var since: Date
    /// When the weekly change window opens: a `Calendar` weekday (1 is Sunday), an hour and a minute.
    var windowWeekday: Int
    var windowHour: Int
    var windowMinute: Int
}

/// Everything the lock decision depends on, as one value.
struct SharedLockState: Equatable {
    var isEnabled = false
    /// The next due date of every active schedule. A passage is due once its date is today or earlier.
    var dueDates: [Date] = []
    /// Nil while the lock can still be changed freely.
    var commitment: LockCommitment?
}

/// Keeps the lock's state in the App Group, where the Screen Time extensions can read it.
/// They can't open Core Data: they run with only a few megabytes of memory.
///
/// Each value has its own key. The app and the extensions write different values, and a single
/// blob would let one side overwrite the other's change.
struct LockStore {
    static let appGroup = "group.com.tahaanwar.QuranMem"

    private enum Key {
        static let prefix = "revisionLock."
        static let isEnabled = "revisionLock.isEnabled"
        static let dueDates = "revisionLock.dueDates"
        static let selection = "revisionLock.selection"
        static let permanentSince = "revisionLock.permanentSince"
        static let windowWeekday = "revisionLock.windowWeekday"
        static let windowHour = "revisionLock.windowHour"
        static let windowMinute = "revisionLock.windowMinute"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = UserDefaults(suiteName: LockStore.appGroup) ?? .standard) {
        self.defaults = defaults
    }

    var isEnabled: Bool {
        get { defaults.bool(forKey: Key.isEnabled) }
        nonmutating set { defaults.set(newValue, forKey: Key.isEnabled) }
    }

    var dueDates: [Date] {
        get { defaults.array(forKey: Key.dueDates) as? [Date] ?? [] }
        nonmutating set { defaults.set(newValue, forKey: Key.dueDates) }
    }

    /// The apps, categories and websites the user chose to lock.
    var selection: FamilyActivitySelection {
        get {
            guard let data = defaults.data(forKey: Key.selection),
                  let selection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) else {
                return FamilyActivitySelection()
            }
            return selection
        }
        nonmutating set { defaults.set(try? JSONEncoder().encode(newValue), forKey: Key.selection) }
    }

    var commitment: LockCommitment? {
        get {
            // A commitment without a window could never be changed, so it doesn't count as one.
            guard let since = defaults.object(forKey: Key.permanentSince) as? Date,
                  let weekday = defaults.object(forKey: Key.windowWeekday) as? Int else { return nil }
            return LockCommitment(
                since: since,
                windowWeekday: weekday,
                windowHour: defaults.integer(forKey: Key.windowHour),
                windowMinute: defaults.integer(forKey: Key.windowMinute)
            )
        }
        nonmutating set {
            defaults.set(newValue?.since, forKey: Key.permanentSince)
            defaults.set(newValue?.windowWeekday, forKey: Key.windowWeekday)
            defaults.set(newValue?.windowHour, forKey: Key.windowHour)
            defaults.set(newValue?.windowMinute, forKey: Key.windowMinute)
        }
    }

    var state: SharedLockState {
        SharedLockState(
            isEnabled: isEnabled,
            dueDates: dueDates,
            commitment: commitment
        )
    }

    /// Builds without the App Group entitlement kept these values in the app's own preferences,
    /// where the extensions can't read them. Copies them into the App Group the first time.
    static func moveIntoAppGroup(fileManager: FileManager = .default) {
        // Without the entitlement the suite below is that same old file, so there's nothing to move.
        guard fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroup) != nil,
              let shared = UserDefaults(suiteName: appGroup),
              let library = fileManager.urls(for: .libraryDirectory, in: .userDomainMask).first else { return }
        let oldFile = library.appending(path: "Preferences/\(appGroup).plist")
        guard let data = try? Data(contentsOf: oldFile),
              let old = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return }
        // Anything already in the App Group was written since, so it wins.
        let isFresh = !shared.dictionaryRepresentation().keys.contains { $0.hasPrefix(Key.prefix) }
        if isFresh {
            for (key, value) in old where key.hasPrefix(Key.prefix) {
                shared.set(value, forKey: key)
            }
        }
        try? fileManager.removeItem(at: oldFile)
    }
}

/// The notification the shield posts, because a shield's buttons can't open QuranMem themselves.
enum LockNotification {
    static let identifier = "revision-lock-open"
}
