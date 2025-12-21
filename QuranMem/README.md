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

### Services (3 files)
- `Services/DataStore.swift` - Core Data wrapper with all CRUD operations
- `Services/ReviewEngine.swift` - Spaced repetition algorithm and streak calculations
- `Services/NotificationManager.swift` - iOS notification handling

### ViewModels (4 files)
- `ViewModels/HomeViewModel.swift` - Today's tasks and stats
- `ViewModels/SchedulesViewModel.swift` - Schedule management
- `ViewModels/ProgressViewModel.swift` - Analytics and history
- `ViewModels/SettingsViewModel.swift` - App settings

### Views (6 files)
- `Views/HomeView.swift` - Dashboard with tasks and stats
- `Views/SchedulesView.swift` - Schedule list and management
- `Views/ProgressView.swift` - Charts and session history
- `Views/SettingsView.swift` - Notification settings and data management
- `Views/SurahSelectionView.swift` - Modal for creating schedules
- `Views/MemorizationSessionView.swift` - Session completion modal

### Data (1 file)
- `Data/surahs.json` - Complete data for all 114 Surahs

### Documentation (2 files)
- `CORE_DATA_SETUP.md` - Step-by-step Core Data configuration
- This README

**Total: 21 files ready to use!**

## 🚀 Quick Start

### Prerequisites
- Mac with macOS 12+
- Xcode 14+ installed
- Basic familiarity with Xcode

### Setup Steps

#### 1. Create New Xcode Project

```
File → New → Project
Choose: iOS → App
Name: QuranMem
Interface: SwiftUI
Language: Swift
Storage: Core Data ✅ (IMPORTANT: Check this box!)
```

#### 2. Add All Swift Files

**Option A: Drag and Drop**
1. Open Finder and navigate to this `swift-ios` directory
2. Select all `.swift` files
3. Drag them into your Xcode project navigator
4. Check "Copy items if needed"
5. Ensure they're added to your target

**Option B: Manual Import**
1. Right-click your project in Xcode
2. Choose "Add Files to QuranMem..."
3. Navigate to `swift-ios` directory
4. Select all `.swift` files
5. Check "Copy items if needed"

#### 3. Add Surahs JSON Data

1. Drag `Data/surahs.json` into your Xcode project
2. Make sure it's added to your app target
3. Verify it appears in "Copy Bundle Resources" build phase

#### 4. Configure Core Data Model

Follow the detailed instructions in `CORE_DATA_SETUP.md`:
- Open `QuranMem.xcdatamodeld`
- Create 4 entities: SurahEntity, ScheduleEntity, SessionEntity, StatsEntity
- Configure all attributes as specified
- Set proper types and optional settings

#### 5. Update Info.plist

Add notification permission description:
```xml
<key>NSUserNotificationsUsageDescription</key>
<string>QuranMem needs notification permission to remind you about your daily memorization tasks.</string>
```

#### 6. Build and Run

1. Select iPhone simulator or your device
2. Press Cmd+R to build and run
3. App will initialize with 114 Surahs on first launch

## 📱 App Features

### Home Screen
- Today's due tasks
- Quick stats (streak, sessions, avg rating)
- Recent session history
- Complete memorization sessions with performance ratings

### Schedules Screen
- View all active and inactive schedules
- Create new schedules by selecting Surahs
- Choose frequency (daily, weekly, biweekly, monthly, bimonthly)
- Option for full Surah or specific page ranges
- Toggle schedules active/inactive
- Delete schedules with swipe action

### Progress Screen
- Overview stats (current/longest streak, total sessions, avg rating)
- Last 7 days activity chart
- Performance breakdown by rating
- Complete session history grouped by date
- Detailed session cards with ratings and notes

### Settings Screen
- Toggle daily reminders on/off
- Configure notification time
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
- Calculate next due dates based on frequency
- Compute current and longest streaks
- Date-based scheduling

**NotificationManager** - iOS notifications
- Request permissions
- Schedule daily reminders
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

### Daily Reminders
- Scheduled at customizable time (default 12 PM)
- Alerts for due memorization tasks
- Badge count shows pending tasks
- Can be enabled/disabled in Settings

### Implementation
Uses `UserNotifications` framework:
- Permission request on first launch
- Repeating daily trigger
- Rich notifications with task details

## 📊 Charts & Analytics

### iOS 16+ (Swift Charts)
- Native Charts framework
- Bar charts for weekly activity
- Performance breakdown visualization

### iOS 15 and below (Fallback)
- Simple bar chart using SwiftUI shapes
- Compatible with older iOS versions

## 🧪 Testing

### Manual Testing Checklist

**Schedule Management**
- [ ] Create schedule for full Surah
- [ ] Create schedule for page range
- [ ] Edit schedule frequency
- [ ] Toggle schedule active/inactive
- [ ] Delete schedule

**Session Tracking**
- [ ] Complete session with each rating (1-5)
- [ ] Add notes to session
- [ ] Verify stats update correctly
- [ ] Check streak calculations

**Notifications**
- [ ] Grant notification permission
- [ ] Set custom reminder time
- [ ] Verify daily notification appears
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

Default is 12:00 PM. Users can change in Settings, or modify default in `SettingsViewModel.swift`:
```swift
components.hour = 12  // Change this
components.minute = 0
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
swift-ios/
├── QuranMemApp.swift           # App entry, tab bar setup
├── Persistence.swift            # Core Data initialization
├── Models/
│   ├── Surah.swift             # Surah data model
│   ├── Types.swift             # Enums and helper types
│   └── CoreDataModels.swift    # Entity extensions
├── Services/
│   ├── DataStore.swift         # Data access layer
│   ├── ReviewEngine.swift      # Business logic
│   └── NotificationManager.swift
├── ViewModels/
│   ├── HomeViewModel.swift
│   ├── SchedulesViewModel.swift
│   ├── ProgressViewModel.swift
│   └── SettingsViewModel.swift
├── Views/
│   ├── HomeView.swift
│   ├── SchedulesView.swift
│   ├── ProgressView.swift
│   ├── SettingsView.swift
│   ├── SurahSelectionView.swift
│   └── MemorizationSessionView.swift
└── Data/
    └── surahs.json             # 114 Surahs data
```

## 🎯 Future Enhancements

Ideas for extending the app:
- [ ] iCloud sync across devices
- [ ] Export data to CSV/JSON
- [ ] Home screen widgets
- [ ] Dark mode support
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
3. Verify all files are properly added to your Xcode project
4. Ensure Core Data model matches specifications

---

**Ready to begin?** Start with Step 1 above and you'll have a working app in minutes!

May Allah make your memorization journey successful! 🤲
