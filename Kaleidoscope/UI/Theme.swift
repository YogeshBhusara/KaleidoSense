//
//  Theme.swift
//  KaleidoSense
//
//  Shared design tokens for the visionOS-inspired glass UI.
//

import SwiftUI

enum Theme {
    static let corner: CGFloat = 26
    static let controlCorner: CGFloat = 18
    static let spacing: CGFloat = 14
    static let panelPadding: CGFloat = 16

    static let accent = Color(.sRGB, red: 0.55, green: 0.86, blue: 1.0)
    static let onGlass = Color.white.opacity(0.95)
    static let onGlassDim = Color.white.opacity(0.62)

    static let panelShadow = Color.black.opacity(0.55)
}
