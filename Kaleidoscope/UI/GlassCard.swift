//
//  GlassCard.swift
//  KaleidoSense
//
//  Reusable glassmorphism container. Uses a thin material with a soft border
//  and highlight to evoke "liquid glass". Respects Reduce Transparency by
//  falling back to a solid, high-contrast surface.
//

import SwiftUI

struct GlassCard<Content: View>: View {
    var cornerRadius: CGFloat = Theme.corner
    @ViewBuilder var content: Content

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        content
            .background {
                if reduceTransparency {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color.black.opacity(0.85))
                } else {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .environment(\.colorScheme, .dark)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.35), .white.opacity(0.05)],
                            startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(color: Theme.panelShadow, radius: 18, x: 0, y: 10)
    }
}

/// A circular glass icon button used throughout the control overlay.
struct GlassIconButton: View {
    let systemName: String
    var isActive: Bool = false
    var tint: Color = Theme.onGlass
    let action: () -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(isActive ? Theme.accent : tint)
                .frame(width: 52, height: 52)
                .background {
                    Circle().fill(reduceTransparency ? AnyShapeStyle(Color.black.opacity(0.85))
                                                      : AnyShapeStyle(.ultraThinMaterial))
                        .environment(\.colorScheme, .dark)
                }
                .overlay {
                    Circle().strokeBorder(.white.opacity(isActive ? 0.5 : 0.18), lineWidth: 1)
                }
                .shadow(color: Theme.panelShadow, radius: 10, y: 5)
        }
        .buttonStyle(.plain)
    }
}
