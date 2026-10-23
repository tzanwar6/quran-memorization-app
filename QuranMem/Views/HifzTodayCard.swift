import SwiftUI

/// Today's part of the memorization plan on Home: the new lesson and the recent review.
struct HifzTodayCard: View {
    let today: HifzToday
    let surahNames: ([Int]) -> String
    let onMemorize: ([HalfPage]) -> Void
    let onRecite: (HifzToday.RecentBlock) -> Void
    let onResume: () -> Void
    let onStartNext: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.card) {
            header

            if today.isPaused {
                row(
                    symbol: "pause.circle",
                    title: "Plan paused",
                    detail: "No lessons or recent review until you resume.",
                    action: ("Resume", false, onResume)
                )
            } else {
                lessonRow
                if let block = today.recentBlock {
                    Divider()
                    recentRow(block)
                }
            }

            if !today.isPaused, today.lesson != .finished, let finish = today.projectedFinish {
                Text("Done around \(finish.formatted(.dateTime.month(.abbreviated).day()))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(Metrics.gutter)
        .cardSurface()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            ViewThatFits(in: .horizontal) {
                HStack {
                    Text(today.plan.title)
                    Spacer(minLength: 8)
                    Text("\(today.memorizedCount) of \(today.totalCount) half pages")
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(today.plan.title)
                    Text("\(today.memorizedCount) of \(today.totalCount) half pages")
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)

            ProgressView(value: Double(today.memorizedCount), total: Double(max(1, today.totalCount)))
                .tint(.islamicGreen)
                .accessibilityLabel("\(today.plan.title) progress")
                .accessibilityValue("\(today.memorizedCount) of \(today.totalCount) half pages memorized")
        }
    }

    @ViewBuilder
    private var lessonRow: some View {
        switch today.lesson {
        case .due(let halves):
            row(
                symbol: "book.fill",
                title: "New lesson",
                detail: halves.portionDescription,
                caption: surahNames(halves.map(\.page)),
                action: ("Memorize", true, { onMemorize(halves) })
            )
            .accessibilityIdentifier("newLesson")
        case .done(let next, let nextDay):
            row(
                symbol: "checkmark.circle.fill",
                title: "Lesson memorized",
                detail: next.isEmpty ? "That was the last lesson." : "Next: \(next.portionDescription), \(Self.dayPhrase(nextDay))"
            )
        case .restDay(let next, let nextDay):
            row(
                symbol: "cup.and.saucer",
                title: "Rest day",
                detail: "Next lesson: \(next.portionDescription), \(Self.dayPhrase(nextDay))"
            )
        case .finished:
            row(
                symbol: "checkmark.seal.fill",
                title: "Every lesson memorized",
                detail: today.recentBlock == nil
                    ? "Your plan is complete."
                    : "Recent review goes on until each portion settles into revision.",
                action: ("Start Next Plan", false, onStartNext)
            )
        }
    }

    private func recentRow(_ block: HifzToday.RecentBlock) -> some View {
        Group {
            if today.recentReviewDoneToday {
                row(
                    symbol: "checkmark.circle.fill",
                    title: "Recent review done",
                    detail: "\(block.halves.pageRangeDescription) · \(Self.halves(block.halfCount))"
                )
            } else {
                row(
                    symbol: "arrow.triangle.2.circlepath",
                    title: "Recent review",
                    detail: block.halves.pageRangeDescription,
                    caption: Self.halves(block.halfCount),
                    action: ("Recite", false, { onRecite(block) })
                )
                .accessibilityIdentifier("recentReview")
            }
        }
    }

    private func row(
        symbol: String,
        title: String,
        detail: String,
        caption: String? = nil,
        action: (title: String, isProminent: Bool, perform: () -> Void)? = nil
    ) -> some View {
        HStack(alignment: .center, spacing: Metrics.card) {
            Image(systemName: symbol)
                .font(.body)
                .foregroundStyle(Color.islamicGreen)
                .frame(width: 36, height: 36)
                .background(Color.islamicGreen.opacity(0.12), in: .circle)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.subheadline)
                if let caption, !caption.isEmpty {
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)

            if let action {
                if action.isProminent {
                    Button(action.title, action: action.perform)
                        .buttonStyle(.borderedProminent)
                        .fontWeight(.semibold)
                } else {
                    Button(action.title, action: action.perform)
                        .buttonStyle(.bordered)
                        .tint(.islamicGreen)
                }
            }
        }
        .frame(minHeight: Metrics.minTarget)
    }

    static func halves(_ count: Int) -> String {
        count == 1 ? "1 half page" : "\(count) half pages"
    }

    /// "tomorrow", "on Sunday", or "on Oct 30".
    static func dayPhrase(_ date: Date?, now: Date = Date(), calendar: Calendar = .current) -> String {
        guard let date else { return "when you add a lesson day" }
        let today = calendar.startOfDay(for: now)
        let days = calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: date)).day ?? 0
        switch days {
        case ...0: return "today"
        case 1: return "tomorrow"
        case 2...6: return "on \(date.formatted(.dateTime.weekday(.wide)))"
        default: return "on \(date.formatted(.dateTime.month(.abbreviated).day()))"
        }
    }
}

/// Says what a graduation pass moved into revision.
struct MovedToRevisionBanner: View {
    let moved: MovedToRevision
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: Metrics.card) {
            Image(systemName: "arrow.right.circle.fill")
                .font(.title3)
                .foregroundStyle(Color.islamicGreen)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("Settled into revision")
                    .font(.subheadline.weight(.medium))
                Text(moved.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: Metrics.minTarget, height: Metrics.minTarget)
            }
            .accessibilityLabel("Dismiss")
            .padding(.vertical, -Metrics.card)
            .padding(.trailing, -Metrics.card)
        }
        .padding(Metrics.gutter)
        .cardSurface()
    }
}
