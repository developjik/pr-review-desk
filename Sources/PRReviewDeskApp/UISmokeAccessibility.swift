import SwiftUI

struct UISmokeAccessibilityControl: Equatable, Hashable, Sendable {
    let identifier: String
    let state: String?

    var reportToken: String {
        if let state, !state.isEmpty {
            return "\(identifier)[\(state)]"
        }

        return identifier
    }
}

struct UISmokeAccessibilityControlPreferenceKey: PreferenceKey {
    static let defaultValue: [UISmokeAccessibilityControl] = []

    static func reduce(
        value: inout [UISmokeAccessibilityControl],
        nextValue: () -> [UISmokeAccessibilityControl]
    ) {
        value.append(contentsOf: nextValue())
    }
}

extension View {
    func smokeAccessibilityIdentifier(_ identifier: String, state: String? = nil) -> some View {
        modifier(UISmokeAccessibilityIdentifierModifier(identifier: identifier, state: state))
    }
}

private struct UISmokeAccessibilityIdentifierModifier: ViewModifier {
    let identifier: String
    let state: String?

    func body(content: Content) -> some View {
        content
            .accessibilityIdentifier(identifier)
            .background(
                Color.clear.preference(
                    key: UISmokeAccessibilityControlPreferenceKey.self,
                    value: [UISmokeAccessibilityControl(identifier: identifier, state: state)]
                )
            )
    }
}
