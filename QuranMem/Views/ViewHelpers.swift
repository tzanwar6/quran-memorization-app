import SwiftUI

extension PerformanceRating {
    var color: Color {
        switch self {
        case .perfect: return .green
        case .veryGood: return .blue
        case .good: return .yellow
        case .poor: return .orange
        case .veryPoor: return .red
        }
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
