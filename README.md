# 📖 QuranMem - Quran Memorization Tracker

<div align="center">

**A beautiful iOS app to help you memorize the Quran using proven spaced repetition techniques**

[![Swift](https://img.shields.io/badge/Swift-5.9-orange.svg)](https://swift.org)
[![iOS](https://img.shields.io/badge/iOS-18.5%2B-blue.svg)](https://www.apple.com/ios/)
[![SwiftUI](https://img.shields.io/badge/SwiftUI-green.svg)](https://developer.apple.com/xcode/swiftui/)
[![License](https://img.shields.io/badge/License-MIT-purple.svg)](LICENSE)

</div>

---

## 🌟 Overview

QuranMem is a native iOS application designed to help Muslims memorize and retain the Holy Quran through scientifically-proven spaced repetition learning. Create personalized schedules, track your progress, and stay consistent with smart notifications.

> *"Indeed, it is We who sent down the Quran and indeed, We will be its guardian."* - Surah Al-Hijr (15:9)

## ✨ Features

### 📅 Smart Scheduling
- Create custom memorization schedules for any Surah
- Choose from multiple review frequencies (daily, weekly, bi-weekly, monthly, bi-monthly)
- Schedule full Surahs or specific page ranges
- Activate/deactivate schedules as needed
- Reviews adapt to your performance: a Poor rating brings a review back after about half its interval, and Very Poor makes it due tomorrow (can be turned off)
- Choose how overdue reviews are rescheduled: keep their original rhythm (e.g. the same weekday) or restart the interval from the day you complete them

### 📊 Progress Tracking
- Visual analytics with beautiful charts
- Track your current and longest streak
- Monitor average performance ratings
- View detailed session history grouped by date
- Edit or delete past sessions
- See last 7 days activity at a glance

### 🔔 Smart Notifications
- Reminders at your preferred time that list what's due, including overdue reviews
- No reminder on days with nothing due
- Badge count for pending reviews

### 🎯 Session Management
- Rate your performance after each session (1-5 stars)
- Add notes to track insights or difficulties
- Undo a session saved by mistake, right from the Home screen
- Automatic streak calculations
- Real-time statistics updates

### 🏠 Dashboard Overview
- Quick view of today's due tasks
- Current streak and total sessions
- Recent session history
- Fast access to complete tasks

## 📱 Screenshots

<!-- Add screenshots here -->
*Coming soon: Screenshots of Home, Schedules, Progress, and Settings screens*

## 🚀 Getting Started

### Prerequisites

- Xcode 16.4 or later (the project uses the iOS 18.5 SDK)
- iOS 18.5+ device or simulator

### Installation

1. **Clone the repository**
   ```bash
   git clone https://github.com/tzanwar6/quran-memorization-app.git
   cd quran-memorization-app
   ```

2. **Open in Xcode**
   ```bash
   open QuranMem.xcodeproj
   ```

3. **Configure Signing**
   - Select the project in Xcode
   - Go to "Signing & Capabilities"
   - Select your development team
   - Update bundle identifier if needed

4. **Build and Run**
   - Select your target device/simulator
   - Press `Cmd + R` to build and run

5. **Run the Tests**
   - Press `Cmd + U`, or from the command line:
   ```bash
   xcodebuild test -project QuranMem.xcodeproj -scheme QuranMem -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:QuranMemTests
   ```

### First Launch

On first launch, the app will:
- Request notification permissions (optional)
- Initialize the database with all 114 Surahs
- Display the Home screen ready for you to create schedules

## 🏗️ Architecture

### Tech Stack

- **Language**: Swift 5.9
- **UI Framework**: SwiftUI
- **Architecture**: MVVM (Model-View-ViewModel)
- **Persistence**: Core Data
- **Notifications**: UserNotifications framework
- **Charts**: Swift Charts
- **Tests**: Swift Testing

### Project Structure

```
QuranMem/
├── Models/              # Data models and Core Data entities
├── Views/               # SwiftUI views
├── ViewModels/          # Business logic and state management
├── Services/            # DataStore, ReviewEngine, ReminderPlanner, NotificationManager
├── Data/                # surahs.json with all 114 Surahs
└── Assets.xcassets/     # Images and color assets
```

### Key Components

- **DataStore**: Centralized data access layer with CRUD operations
- **ReviewEngine**: Due-date rules (frequency, rating adjustments, overdue handling) and streak calculations
- **ReminderPlanner**: Works out which days get a reminder and what it says
- **NotificationManager**: Reminder preferences, permissions, and scheduling
- **ViewModels**: State management and business logic for each screen

## 💾 Data Models

### Core Entities

- **Surah**: Complete data for all 114 Surahs (name, verses, pages)
- **Schedule**: Memorization schedules with frequency and date tracking
- **Session**: Completed memorization sessions with ratings and notes
- **Stats**: Aggregated statistics (streaks, totals, averages)

## 🎨 Design Philosophy

- **Islamic Aesthetic**: Green and gold color scheme reflecting Islamic heritage
- **Native iOS**: Follows Apple's Human Interface Guidelines
- **Accessibility**: VoiceOver support and Dynamic Type
- **Smooth Animations**: Native SwiftUI transitions and animations

## 📖 Detailed Documentation

For comprehensive technical documentation, including:
- Core Data setup instructions
- Architecture deep-dive
- Customization guide
- Troubleshooting tips
- Deployment instructions

See the [Technical README](QuranMem/README.md)

## 🤝 Contributing

Contributions are welcome! Whether it's:
- 🐛 Bug reports
- 💡 Feature requests
- 📝 Documentation improvements
- 🔧 Code contributions

Please feel free to open an issue or submit a pull request.

## 🗺️ Roadmap

- [ ] iCloud sync across devices
- [ ] iPad optimization with split views
- [ ] Home screen widgets
- [ ] Export/import data functionality
- [ ] Juz-based scheduling
- [ ] Audio recitation integration
- [ ] Social features (share progress)

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- Quran data sourced from reliable Islamic databases
- Spaced repetition algorithm based on proven learning science
- Built with ❤️ for the Muslim community

## 🤲 Du'a

```
بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ

May Allah accept your efforts in memorizing His Book
and make it a light for you in this life and the Hereafter.

اللَّهُمَّ انْفَعْنَا بِمَا عَلَّمْتَنَا
وَعَلِّمْنَا مَا يَنْفَعُنَا
وَزِدْنَا عِلْمًا

(O Allah, benefit us with what You have taught us,
teach us what will benefit us,
and increase us in knowledge)
```

---

<div align="center">

**Made with 💚 for the Ummah**

If this project helps you in your Quran memorization journey, please consider starring ⭐ the repository!

</div>
