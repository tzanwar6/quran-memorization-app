import SwiftUI

extension PerformanceRating {
    /// A five-step scale from red through to green. Authored per appearance so a
    /// rating keeps roughly the same perceived weight on both canvases — the
    /// mid-scale yellow in particular is too pale to read against white at its
    /// system value. Nothing relies on these alone: every use pairs the colour
    /// with the star count or the rating's name.
    var color: Color {
        Color(uiColor: UIColor { traits in
            let isDark = traits.userInterfaceStyle == .dark
            switch self {
            case .perfect:
                return isDark ? UIColor(displayP3Red: 0.19, green: 0.82, blue: 0.35, alpha: 1)
                              : UIColor(displayP3Red: 0.09, green: 0.60, blue: 0.25, alpha: 1)
            case .veryGood:
                return isDark ? UIColor(displayP3Red: 0.39, green: 0.82, blue: 1.00, alpha: 1)
                              : UIColor(displayP3Red: 0.00, green: 0.48, blue: 0.75, alpha: 1)
            case .good:
                return isDark ? UIColor(displayP3Red: 1.00, green: 0.84, blue: 0.04, alpha: 1)
                              : UIColor(displayP3Red: 0.72, green: 0.53, blue: 0.00, alpha: 1)
            case .poor:
                return isDark ? UIColor(displayP3Red: 1.00, green: 0.62, blue: 0.04, alpha: 1)
                              : UIColor(displayP3Red: 0.80, green: 0.42, blue: 0.00, alpha: 1)
            case .veryPoor:
                return isDark ? UIColor(displayP3Red: 1.00, green: 0.27, blue: 0.23, alpha: 1)
                              : UIColor(displayP3Red: 0.80, green: 0.13, blue: 0.09, alpha: 1)
            }
        })
    }
}

extension View {
    /// Shows `message` in an alert while it's non-nil and clears it when dismissed.
    func errorAlert(_ message: Binding<String?>, title: String = "Something Went Wrong") -> some View {
        alert(
            title,
            isPresented: Binding(
                get: { message.wrappedValue != nil },
                set: { if !$0 { message.wrappedValue = nil } }
            )
        ) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(message.wrappedValue ?? "")
        }
    }
}
