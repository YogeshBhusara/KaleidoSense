//
//  SymmetryPicker.swift
//  KaleidoSense
//
//  Segmented selector for the mirror-symmetry count.
//

import SwiftUI

struct SymmetryPicker: View {
    @Bindable var viewModel: KaleidoscopeViewModel

    var body: some View {
        HStack(spacing: 6) {
            ForEach(SymmetryMode.allCases) { mode in
                let isSelected = viewModel.symmetry == mode
                Button {
                    withAnimation(.snappy(duration: 0.2)) { viewModel.selectSymmetry(mode) }
                } label: {
                    Text(mode.title)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                        .foregroundStyle(isSelected ? .black : Theme.onGlass)
                        .background {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(isSelected ? AnyShapeStyle(Theme.accent)
                                                 : AnyShapeStyle(Color.white.opacity(0.08)))
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(.white.opacity(isSelected ? 0.4 : 0.12), lineWidth: 0.8)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(mode.accessibilityLabel))
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            }
        }
    }
}
