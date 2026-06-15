//
//  ControlsOverlay.swift
//  KaleidoSense
//
//  Auto-hiding glass control surface layered over the kaleidoscope. Split into
//  a lightweight top bar (title + performance HUD) and a bottom control panel
//  (mode / symmetry / palette pickers, sensitivity, toggles) plus a floating
//  action row (shuffle, capture, record).
//

import SwiftUI

struct ControlsOverlay: View {
    @Bindable var viewModel: KaleidoscopeViewModel
    var onInteraction: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Spacer(minLength: 0)
            actionRow
            bottomPanel
        }
        .padding(.horizontal, Theme.spacing)
        .padding(.bottom, 6)
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("KaleidoSense")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.onGlassDim)
                Text(viewModel.mode.title)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.onGlass)
            }
            Spacer()
            if viewModel.showPerformanceHUD {
                PerformanceHUD(monitor: viewModel.performance)
            }
        }
        .padding(.top, 6)
    }

    // MARK: Floating action row

    private var actionRow: some View {
        HStack(spacing: 18) {
            GlassIconButton(systemName: "shuffle") {
                onInteraction()
                viewModel.randomize()
            }
            .accessibilityLabel("Randomize pattern")

            GlassIconButton(systemName: "camera.fill") {
                onInteraction()
                Task { await viewModel.capturePhoto() }
            }
            .accessibilityLabel("Capture photo")

            GlassIconButton(systemName: viewModel.isRecording ? "stop.circle.fill" : "record.circle",
                            isActive: viewModel.isRecording,
                            tint: viewModel.isRecording ? .red : Theme.onGlass) {
                onInteraction()
                viewModel.toggleRecording()
            }
            .accessibilityLabel(viewModel.isRecording ? "Stop recording" : "Record video")
        }
        .padding(.bottom, 14)
    }

    // MARK: Bottom panel

    private var bottomPanel: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 16) {
                ModePicker(viewModel: viewModel)

                labeled("Symmetry") { SymmetryPicker(viewModel: viewModel) }
                labeled("Palette") { PalettePicker(viewModel: viewModel) }

                labeled("Motion Sensitivity") {
                    HStack(spacing: 12) {
                        Image(systemName: "tortoise.fill").foregroundStyle(Theme.onGlassDim)
                        Slider(value: $viewModel.motionSensitivity, in: 0...1)
                            .tint(Theme.accent)
                            .accessibilityLabel("Motion sensitivity")
                        Image(systemName: "hare.fill").foregroundStyle(Theme.onGlassDim)
                    }
                }

                togglesRow
            }
            .padding(Theme.panelPadding)
        }
    }

    private var togglesRow: some View {
        HStack(spacing: 10) {
            toggleChip(title: "Audio", systemName: "speaker.wave.2.fill",
                       isOn: viewModel.audioEnabled) {
                viewModel.setAudioEnabled(!viewModel.audioEnabled)
            }
            toggleChip(title: "Haptics", systemName: "iphone.radiowaves.left.and.right",
                       isOn: viewModel.hapticsEnabled) {
                viewModel.setHapticsEnabled(!viewModel.hapticsEnabled)
            }
            toggleChip(title: "60fps", systemName: "battery.75percent",
                       isOn: viewModel.prefersBatterySaver) {
                viewModel.prefersBatterySaver.toggle()
            }
            toggleChip(title: "Stats", systemName: "speedometer",
                       isOn: viewModel.showPerformanceHUD) {
                viewModel.showPerformanceHUD.toggle()
            }
        }
    }

    private func toggleChip(title: String, systemName: String, isOn: Bool,
                            action: @escaping () -> Void) -> some View {
        Button {
            onInteraction()
            action()
        } label: {
            VStack(spacing: 5) {
                Image(systemName: systemName)
                    .font(.system(size: 16, weight: .semibold))
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(isOn ? Theme.accent : Theme.onGlassDim)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isOn ? Color.white.opacity(0.12) : Color.white.opacity(0.05))
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(title))
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }

    private func labeled<Content: View>(_ title: String,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Theme.onGlassDim)
                .tracking(0.8)
            content()
        }
    }
}
