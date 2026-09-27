import SwiftUI

// The shared visual vocabulary: colour tokens, grid metrics, and the surface and
// press treatments every screen reuses. Keeping them here means a change lands
// everywhere at once instead of drifting per view.

// MARK: - Colour

extension UIColor {
    /// The app's single accent, resolved per appearance instead of stored as one
    /// fixed value. The light tone stays dark enough to carry text on white; the
    /// dark tone is lifted so it doesn't sink into a near-black canvas. Both are
    /// authored in Display P3 and both deepen under Increase Contrast.
    static let islamicGreen = UIColor { traits in
        switch (traits.userInterfaceStyle, traits.accessibilityContrast) {
        case (.dark, .high):
            return UIColor(displayP3Red: 0.44, green: 0.87, blue: 0.67, alpha: 1)
        case (.dark, _):
            return UIColor(displayP3Red: 0.28, green: 0.77, blue: 0.56, alpha: 1)
        case (_, .high):
            return UIColor(displayP3Red: 0.00, green: 0.31, blue: 0.22, alpha: 1)
        default:
            return UIColor(displayP3Red: 0.02, green: 0.45, blue: 0.33, alpha: 1)
        }
    }

    /// Reserved for the star rating — the one place a second hue earns its keep.
    static let goldAccent = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(displayP3Red: 0.98, green: 0.78, blue: 0.29, alpha: 1)
            : UIColor(displayP3Red: 0.72, green: 0.53, blue: 0.05, alpha: 1)
    }
}

extension Color {
    static let islamicGreen = Color(uiColor: .islamicGreen)
    static let goldAccent = Color(uiColor: .goldAccent)

    /// Canvas behind grouped content.
    static let appCanvas = Color(.systemGroupedBackground)
    /// Fill for a card sitting on `appCanvas`.
    static let appCard = Color(.secondarySystemGroupedBackground)
}

// MARK: - Metrics

/// The 8-point grid. Half-steps (4) only for tight pairings inside a component.
enum Metrics {
    static let gutter: CGFloat = 16
    static let section: CGFloat = 24
    static let card: CGFloat = 12
    static let cardRadius: CGFloat = 16
    static let controlRadius: CGFloat = 10
    /// Apple's minimum comfortable touch target.
    static let minTarget: CGFloat = 44
}

// MARK: - Surfaces

extension View {
    /// A content card: a fill that separates from the canvas on its own, with a
    /// continuous (squircle) corner. Deliberately no drop shadow — on a grouped
    /// canvas the fill contrast does the separating, and a shadow under a
    /// `systemBackground` card is invisible in dark mode anyway.
    func cardSurface(radius: CGFloat = Metrics.cardRadius) -> some View {
        background(Color.appCard, in: .rect(cornerRadius: radius, style: .continuous))
    }
}

// MARK: - Press feedback

/// Gives a tappable card the press response the system gives its own controls:
/// a small settle on touch-down that can be interrupted mid-flight. The scale is
/// dropped under Reduce Motion, leaving the dim as the feedback.
struct CardButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.975 : 1)
            .opacity(configuration.isPressed ? 0.72 : 1)
            .animation(.snappy(duration: 0.25, extraBounce: 0.1), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == CardButtonStyle {
    static var card: CardButtonStyle { CardButtonStyle() }
}

// MARK: - Shared components

/// A section title above a group of cards. Carries the header trait so VoiceOver
/// users can jump between sections with the rotor.
struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.title3.weight(.semibold))
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Marks a review that has slipped past its due date. Carries an icon and a word
/// as well as the colour, so the state survives colour-blindness and greyscale.
struct OverdueBadge: View {
    var body: some View {
        Label("Overdue", systemImage: "exclamationmark.circle.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.red)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.red.opacity(0.12), in: .capsule)
            .accessibilityLabel("Overdue")
    }
}

/// The star row used by ratings. Presented to VoiceOver as one value rather than
/// five separate images.
struct StarRatingView: View {
    let stars: Int
    var size: Font = .caption2

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<5, id: \.self) { index in
                Image(systemName: index < stars ? "star.fill" : "star")
                    .font(size)
                    .foregroundStyle(index < stars ? Color.goldAccent : Color(.tertiaryLabel))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(stars) out of 5 stars")
    }
}
