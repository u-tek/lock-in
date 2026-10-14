import DesignSystem
import SwiftUI
import UIKit

/// What a Home Screen widget sits on: the system background with a wash of one colour from the
/// top, the way Apple's own widgets carry their app's colour. The widget extension hands it to
/// `containerBackground(for: .widget)`, so the system removes it in the tinted and clear Home
/// Screen styles and on StandBy; the app's snapshots draw it behind the same views.
public struct WidgetSurface: View {
    private let accent: Color

    public init(accent: Color) {
        self.accent = accent
    }

    public var body: some View {
        ZStack {
            Color(uiColor: .systemBackground)
            LinearGradient(
                colors: [accent.opacity(0.2), accent.opacity(0.04)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}
