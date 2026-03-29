// Theme.swift — Design tokens. No magic numbers elsewhere.
import SwiftUI

@MainActor
enum Theme {
    // Colors
    static let cardFill = Color.white.opacity(0.08)
    static let cardBorder = Color.white.opacity(0.15)
    static let cardShadow = Color.black.opacity(0.12)

    // Geometry
    static let cardCornerRadius: CGFloat = 16
    static let cardShadowRadius: CGFloat = 8
    static let cardShadowY: CGFloat = 4
    static let gridSpacing: CGFloat = 12
    static let gridMinWidth: CGFloat = 900   // threshold for 2-col layout

    // Animation
    static let springAnimation = Animation.spring(response: 0.4, dampingFraction: 0.8)
    static let cardTransition = AnyTransition.scale(scale: 0.95).combined(with: .opacity)

    // Typography uses system SF Pro via .headline / .caption modifiers
}
