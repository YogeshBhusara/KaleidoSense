//
//  GlassCard.swift
//  KaleidoSense
//
//  Reusable glassmorphism container. Uses a thin material with a dual-edge
//  highlight to evoke cut crystal. Respects Reduce Transparency by falling
//  back to a solid, high-contrast surface.
//

import SwiftUI

struct GlassCard<Content: View>: View {
    var cornerRadius: CGFloat = Theme.corner
    @ViewBuilder var content: Content

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(reduceTransparency
                          ? AnyShapeStyle(Color.black.opacity(0.88))
                          : AnyShapeStyle(.ultraThinMaterial))
                    .environment(\.colorScheme, .dark)
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.55), .white.opacity(0.08), .white.opacity(0.22)],
                            startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 0.8)
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius - 1, style: .continuous)
                    .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
                    .padding(1)
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(color: Theme.panelShadow, radius: 22, x: 0, y: 12)
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
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(isActive ? Theme.accent : tint)
                .frame(width: 54, height: 54)
                .background {
                    Circle().fill(reduceTransparency ? AnyShapeStyle(Color.black.opacity(0.88))
                                                      : AnyShapeStyle(.ultraThinMaterial))
                        .environment(\.colorScheme, .dark)
                }
                .overlay {
                    Circle().strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(isActive ? 0.7 : 0.45), .white.opacity(0.08)],
                            startPoint: .top, endPoint: .bottom),
                        lineWidth: 0.8)
                }
                .shadow(color: isActive ? Theme.accent.opacity(0.35) : Theme.panelShadow,
                        radius: isActive ? 12 : 10, y: 5)
        }
        .buttonStyle(.plain)
    }
}
