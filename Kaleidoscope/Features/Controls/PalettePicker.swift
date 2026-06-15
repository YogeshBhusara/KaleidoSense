//
//  PalettePicker.swift
//  KaleidoSense
//
//  Row of color-palette swatches.
//

import SwiftUI

struct PalettePicker: View {
    @Bindable var viewModel: KaleidoscopeViewModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(ColorPalette.all) { palette in
                    let isSelected = viewModel.palette == palette
                    Button {
                        withAnimation(.snappy(duration: 0.2)) { viewModel.selectPalette(palette) }
                    } label: {
                        swatch(palette)
                            .overlay {
                                Circle().strokeBorder(.white.opacity(isSelected ? 0.95 : 0.2),
                                                      lineWidth: isSelected ? 2.5 : 1)
                            }
                            .scaleEffect(isSelected ? 1.08 : 1.0)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("\(palette.name) palette"))
                    .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 4)
        }
        .scrollClipDisabled()
    }

    private func swatch(_ palette: ColorPalette) -> some View {
        Circle()
            .fill(AngularGradient(colors: palette.swatch + [palette.swatch[0]],
                                  center: .center))
            .frame(width: 38, height: 38)
    }
}
