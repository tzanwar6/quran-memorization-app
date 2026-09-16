# QuranMem - Native iOS Swift Implementation

Complete Swift codebase for QuranMem - a Quran memorization tracker for iOS.

## 📦 What's Included

This directory contains **all the Swift code** you need to create a native iOS app:

### Core Files (2 files)
- `QuranMemApp.swift` - Main app entry point with tab navigation
- `Persistence.swift` - Core Data stack and initialization

### Models (3 files)
- `Models/Surah.swift` - Surah data structure
- `Models/Types.swift` - Enums (Frequency, PerformanceRating) and helper types
- `Models/CoreDataModels.swift` - Core Data entity extensions

### Services (4 files)
- `Services/DataStore.swift` - Core Data wrapper with all CRUD operations
- `Services/ReviewEngine.swift` - Due-date rules (frequency, rating adjustments, overdue handling) and streak calculations
- `Services/ReminderPlanner.swift` - Decides which days get a reminder and what it says
- `Services/NotificationManager.swift` - Reminder preferences, permissions and scheduling

### ViewModels (4 files)
- `ViewModels/HomeViewModel.swift` - Today's tasks, calendar and undo
- `ViewModels/SchedulesViewModel.swift` - Schedule management
- `ViewModels/ProgressViewModel.swift` - Analytics, history and session edits
- `ViewModels/SettingsViewModel.swift` - App settings

### Views (8 files)
- `Views/HomeView.swift` - Today's tasks, two-week calendar and undo banner
- `Views/SchedulesView.swift` - Schedule list and management
- `Views/ProgressTabView.swift` - Charts and session history
- `Views/SessionEditView.swift` - Edit or delete a past session
- `Views/SettingsView.swift` - Appearance, reminders, scheduling and data management
- `Views/SurahSelectionView.swift` - Modal for creating schedules
- `Views/MemorizationSessionView.swift` - Session completion modal
- `Views/ViewHelpers.swift` - Shared error alert and rating colors

### Data (1 file)
- `Data/surahs.json` - Complete data for all 114 Surahs

### Documentation (2 files)
- `CORE_DATA_SETUP.md` - Step-by-step Core Data configuration
- This README

### Tests
- `QuranMemTests/QuranMemTests.swift` - Unit tests (Swift Testing) for scheduling, streaks, reminders, DataStore and surah data

## 🚀 Quick Start

### Prerequisites
- Mac with Xcode 16.4 or later (the project targets iOS 18.5)

### Setup Steps

1. Open `QuranMem.xcodeproj` in Xcode
2. Select your development team under "Signing & Capabilities" if you want to run on a device
3. Select an iPhone simulator or your device
4. Press Cmd+R to build and run
5. The app loads all 114 Surahs into Core Data on first launch

The Core Data model, `surahs.json` and the notification permission description are already set up in the project. `CORE_DATA_SETUP.md` documents the entity definitions.

## 📱 App Features

### Home Screen
- Today's due and overdue tasks
- Two-week calendar of upcoming reviews (weeks start on the region's first weekday)
- Complete memorization sessions with performance ratings
- Undo a just-completed session, which also restores the schedule's due date

### Schedules Screen
- View all active and inactive schedules
- Create new schedules by selecting Surahs
- Choose frequency (daily, weekly, biweekly, monthly, bimonthly)
- Option for full Surah or specific page ranges
- Edit frequency or set the next due date manually
- Toggle schedules active/inactive
- Delete schedules with swipe action (their sessions are deleted too)

### Progress Screen
- Overview stats (current/longest streak, total sessions, avg rating)
- Last 7 days activity chart
- Performance breakdown by rating
- Complete session history grouped by date
- Tap a session to edit its rating and notes, or delete it

### Settings Screen
- Appearance (system, light, dark)
- Toggle reminders on/off and choose the reminder time
- Adjust for Performance: Poor ratings bring reviews back after about half the interval, Very Poor the next day
- Overdue Reviews: keep the original rhythm, or restart the interval from the completion day
- Reset all data option
- App version and build info

## 🏗 Architecture

### Pattern: MVVM (Model-View-ViewModel)

```
Views (SwiftUI)
    ↓
ViewModels (@ObservableObject)
    ↓
Services (DataStore, ReviewEngine, NotificationManager)
    ↓
Core Data (Local database)
```

### Data Flow

1. **Views** display UI and handle user interactions
2. **ViewModels** manage state and business logic
3. **Services** provide data access and algorithms
4. **Core Data** persists all data locally

### Key Components

**DataStore** - Centralized data access layer
- CRUD operations for all entities
- Automatic stats updates
- Next due date calculations

**ReviewEngine** - Spaced repetition logic
- Calculate next due dates based on frequency, rating and overdue policy
- Recalculate due dates when a schedule's frequency changes
- Compute current and longest streaks
- Date-based scheduling

**NotificationManager** - iOS notifications
- Request permissions
- Save reminder preferences
- Schedule a reminder for each of the next 30 days that has reviews due
- Update app badge count
- Handle notification interactions

## 💾 Data Models

### Surah (114 total)
- Arabic name, English name, transliteration
- Verse count
- Page range (start/end)
- Revelation type (Meccan/Medinan)

### Schedule
- Links to Surah
- Frequency (daily to bi-monthly)
- Full Surah or page range
- Next due date
- Active/inactive status

### Session
- Links to Schedule
- Performance rating (1-5 stars)
- Completion timestamp
- Optional notes

### Stats
- Current and longest streaks
- Total sessions completed
- Average performance rating
- Last session date

## 🎨 Design

### Color Scheme
- **Islamic Green**: `#047857` - Primary brand color
- **Gold Accent**: `#D4A517` - Highlights and ratings
- Islamic-themed, clean, professional

### UI Components
- Native iOS design language
- SwiftUI standard components
- Smooth animations and transitions
- Accessibility-friendly

## 🔔 Notifications

### Reminders
- Sent at a customizable time (default 12 PM)
- List the reviews due that day, e.g. "3 reviews due: Al-Mulk, Yasin and 1 more. 1 overdue."
- Skipped on days with nothing due
- Badge count shows pending tasks
- Can be enabled/disabled in Settings

### Implementation
Uses the `UserNotifications` framework:
- Permission request on first launch
- `ReminderPlanner` builds one non-repeating reminder per day with reviews due, for the next 30 days
- `NotificationManager` rebuilds the plan whenever schedules or sessions are saved and when the app comes to the foreground

## 📊 Charts & Analytics

- Swift Charts bar chart for the last 7 days of activity
- Performance breakdown by rating

## 🧪 Testing

### Unit Tests

Run with Cmd+U in Xcode, or:
```bash
xcodebuild test -project QuranMem.xcodeproj -scheme QuranMem -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:QuranMemTests
```

They cover due-date rules, rating adjustments, overdue policies, streaks, reminder planning, DataStore operations (using an in-memory store) and the surah data.

### Manual Testing Checklist

**Schedule Management**
- [ ] Create schedule for full Surah
- [ ] Create schedule for page range
- [ ] Edit schedule frequency
- [ ] Toggle schedule active/inactive
- [ ] Delete schedule

**Session Tracking**
- [ ] Complete session with each rating (1-5)
- [ ] Undo a session from the Home screen
- [ ] Edit and delete a session from History
- [ ] Add notes to session
- [ ] Verify stats update correctly
- [ ] Check streak calculations

**Notifications**
- [ ] Grant notification permission
- [ ] Set custom reminder time
- [ ] Verify the reminder lists what's due
- [ ] Check badge count updates

**Data Persistence**
- [ ] Create data
- [ ] Force quit app
- [ ] Reopen app
- [ ] Verify data persists

## 🐛 Troubleshooting

### Build Errors

**"No such module 'CoreData'"**
- Solution: Clean build folder (Cmd+Shift+K), rebuild

**"Cannot find 'SurahEntity' in scope"**
- Solution: Verify Core Data model is configured correctly
- Codegen must be set to "Class Definition"

### Runtime Issues

**App crashes on launch**
- Check Console for error messages
- Verify `surahs.json` is in bundle resources
- Ensure Core Data model matches entity definitions

**Data not loading**
- Check `surahs.json` is properly formatted
- Verify file is added to app target
- Check Persistence initialization code

**Notifications not working**
- Request permission in Settings tab
- Check device Settings → Notifications → QuranMem
- Test on physical device (simulator has limitations)

### Reset Development Database

To start fresh:
1. Delete app from simulator/device
2. Clean build folder (Cmd+Shift+K)
3. Run app again

## 📝 Customization

### Changing Colors

Edit in `QuranMemApp.swift`:
```swift
extension Color {
    static let islamicGreen = Color(red: 0.02, green: 0.47, blue: 0.34)
    static let islamicDark = Color(red: 0.02, green: 0.37, blue: 0.27)
    static let goldAccent = Color(red: 0.85, green: 0.65, blue: 0.13)
}
```

### Adding Custom Frequencies

1. Edit `Frequency` enum in `Models/Types.swift`
2. Add case and display name
3. Update `ReviewEngine.calculateNextDueDate()` logic

### Modifying Notification Time

Default is 12:00 PM. Users can change it in Settings, or change the default in `NotificationManager.swift`:
```swift
defaults.register(defaults: [
    Self.remindersEnabledKey: true,
    Self.reminderHourKey: 12,  // Change this
    Self.reminderMinuteKey: 0
])
```

## 🚢 Deployment to Personal iPhone

### Prerequisites
- Apple ID (free account works)
- iPhone with USB cable
- Mac with Xcode

### Steps

1. **Connect iPhone** to Mac via USB
2. **Trust Computer** on iPhone when prompted
3. **Select Device** in Xcode toolbar
4. **Configure Signing**:
   - Select project in navigator
   - Go to "Signing & Capabilities"
   - Check "Automatically manage signing"
   - Select your Apple ID team
   - Change bundle identifier if needed (e.g., `com.yourname.quranmem`)

5. **Build and Run** (Cmd+R)
6. **Trust Developer** on iPhone:
   - Go to Settings → General → VPN & Device Management
   - Tap your Apple ID
   - Tap "Trust"

7. **App Installed!** Find QuranMem on your home screen

### Note
Free Apple ID apps expire after 7 days and need to be re-installed. For permanent installation, you need a paid Apple Developer account ($99/year).

## 📚 Code Structure

```
QuranMem/
├── QuranMemApp.swift           # App entry, tab bar setup
├── Persistence.swift            # Core Data initialization
├── Models/
│   ├── Surah.swift             # Surah data model
│   ├── Types.swift             # Enums and helper types
│   └── CoreDataModels.swift    # Entity extensions
├── Services/
│   ├── DataStore.swift         # Data access layer
│   ├── ReviewEngine.swift      # Scheduling and streak logic
│   ├── ReminderPlanner.swift   # Reminder content and timing
│   └── NotificationManager.swift
├── ViewModels/
│   ├── HomeViewModel.swift
│   ├── SchedulesViewModel.swift
│   ├── ProgressViewModel.swift
│   └── SettingsViewModel.swift
├── Views/
│   ├── HomeView.swift
│   ├── SchedulesView.swift
│   ├── ProgressTabView.swift
│   ├── SessionEditView.swift
│   ├── SettingsView.swift
│   ├── SurahSelectionView.swift
│   ├── MemorizationSessionView.swift
│   └── ViewHelpers.swift
└── Data/
    └── surahs.json             # 114 Surahs data
```

## 🎯 Future Enhancements

Ideas for extending the app:
- [ ] iCloud sync across devices
- [ ] Export data to CSV/JSON
- [ ] Home screen widgets
- [ ] iPad optimization
- [ ] Custom notification sounds
- [ ] Share progress with friends
- [ ] Import/export schedules
- [ ] Juz-based scheduling
- [ ] Audio recitation integration

## 🤲 Islamic Prayer

```
بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ

May Allah accept your efforts in memorizing His Book
and make it a light for you in this life and the Hereafter.

اللَّهُمَّ انْفَعْنَا بِمَا عَلَّمْتَنَا
وَعَلِّمْنَا مَا يَنْفَعُنَا
وَزِدْنَا عِلْمًا

بارك الله فيك
```

## 📧 Support

This is a complete, self-contained iOS app. All code is provided and ready to use.

**If you encounter issues:**
1. Check this README and `CORE_DATA_SETUP.md`
2. Review the troubleshooting section
3. Run the unit tests to check the scheduling logic

May Allah make your memorization journey successful! 🤲
