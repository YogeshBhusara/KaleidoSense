//
//  KaleidoscopeScreen.swift
//  KaleidoSense
//
//  The main full-screen experience: the GPU kaleidoscope with an auto-hiding
//  glass control overlay. Single-tap toggles the controls, double-tap
//  randomizes the pattern. Honors Reduce Motion / Reduce Transparency.
//

import SwiftUI

struct KaleidoscopeScreen: View {
    @State private var viewModel = KaleidoscopeViewModel()
    @State private var hideTask: Task<Void, Never>?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            MetalKaleidoscopeView(viewModel: viewModel)
                .ignoresSafeArea()
                .accessibilityLabel("Live kaleidoscope. Tilt and rotate your iPhone to change the pattern.")
                .accessibilityAddTraits(.updatesFrequently)

            // Gesture layer: sits above the Metal view, below the controls.
            Color.clear
                .contentShape(Rectangle())
                .ignoresSafeArea()
                .onTapGesture(count: 2) {
                    viewModel.randomize()
                    revealControlsBriefly()
                }
                .onTapGesture(count: 1) {
                    toggleControls()
                }

            if viewModel.controlsVisible {
                ControlsOverlay(viewModel: viewModel) { scheduleAutoHide() }
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .preferredColorScheme(.dark)
        .animation(.easeInOut(duration: 0.28), value: viewModel.controlsVisible)
        .onAppear {
            viewModel.setAccessibility(reduceMotion: reduceMotion,
                                       reduceTransparency: reduceTransparency)
            viewModel.onAppear()
            scheduleAutoHide()
        }
        .onDisappear { viewModel.onDisappear() }
        .onChange(of: reduceMotion) { _, new in
            viewModel.setAccessibility(reduceMotion: new, reduceTransparency: reduceTransparency)
        }
        .onChange(of: reduceTransparency) { _, new in
            viewModel.setAccessibility(reduceMotion: reduceMotion, reduceTransparency: new)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:    viewModel.onAppear()
            case .background: viewModel.onDisappear()
            default: break
            }
        }
        .sheet(item: $viewModel.sharePayload) { payload in
            ShareSheet(items: payload.activityItems)
        }
        .alert("Something went wrong",
               isPresented: Binding(get: { viewModel.errorMessage != nil },
                                    set: { if !$0 { viewModel.errorMessage = nil } })) {
            Button("OK", role: .cancel) { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    // MARK: - Controls visibility

    private func toggleControls() {
        viewModel.controlsVisible.toggle()
        if viewModel.controlsVisible { scheduleAutoHide() } else { hideTask?.cancel() }
    }

    private func revealControlsBriefly() {
        if !viewModel.controlsVisible { viewModel.controlsVisible = true }
        scheduleAutoHide()
    }

    /// Hides the controls after a period of inactivity. Disabled while recording
    /// so the stop button stays reachable.
    private func scheduleAutoHide() {
        hideTask?.cancel()
        hideTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled, !viewModel.isRecording else { return }
            viewModel.controlsVisible = false
        }
    }
}

#Preview {
    KaleidoscopeScreen()
}
