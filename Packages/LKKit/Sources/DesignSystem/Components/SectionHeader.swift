import SwiftUI

/// The capitalised line above a group of rows ("YOUR SQUAD", "TODAY"), with optional quiet
/// detail on the right ("3 of 4 locked in").
public struct LKSectionHeader: View {
    private let title: String
    private let detail: String?

    public init(_ title: String, detail: String? = nil) {
        self.title = title
        self.detail = detail
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: LKSpacing.s) {
            Text(title)
                .lkType(.label)
                .foregroundStyle(LKColor.textSecondary)
                .lineLimit(1)
            Spacer(minLength: 0)
            if let detail {
                Text(detail)
                    .font(LKFont.caption)
                    .foregroundStyle(LKColor.textSecondary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}
