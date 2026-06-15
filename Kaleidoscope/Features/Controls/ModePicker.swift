//
//  ModePicker.swift
//  KaleidoSense
//
//  Horizontal carousel of premium mode chips.
//

import SwiftUI

struct ModePicker: View {
    @Bindable var viewModel: KaleidoscopeViewModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(KaleidoscopeMode.allCases) { mode in
                    chip(for: mode)
                }
            }
            .padding(.horizontal, 4)
        }
        .scrollClipDisabled()
    }

    private func chip(for mode: KaleidoscopeMode) -> some View {
        let isSelected = viewModel.mode == mode
        return Button {
            withAnimation(.snappy(duration: 0.25)) { viewModel.selectMode(mode) }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: mode.symbol)
                    .font(.system(size: 13, weight: .bold))
                Text(mode.title)
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(isSelected ? .black : Theme.onGlass)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background {
                Capsule().fill(isSelected
                               ? AnyShapeStyle(LinearGradient(colors: mode.palette.swatch,
                                                              startPoint: .leading, endPoint: .trailing))
                               : AnyShapeStyle(.ultraThinMaterial))
                    .environment(\.colorScheme, .dark)
            }
            .overlay {
                Capsule().strokeBorder(.white.opacity(isSelected ? 0.0 : 0.18), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(mode.title))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
