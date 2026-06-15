//
//  MetalKaleidoscopeView.swift
//  KaleidoSense
//
//  SwiftUI bridge that hosts an `MTKView` driven by `MetalRenderer`. The view
//  model is both the frame source and the owner of the renderer reference (so
//  it can trigger snapshots and recording).
//

import SwiftUI
import MetalKit

struct MetalKaleidoscopeView: UIViewRepresentable {
    let viewModel: KaleidoscopeViewModel

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView()
        view.device = MTLCreateSystemDefaultDevice()
        view.colorPixelFormat = .bgra8Unorm
        view.framebufferOnly = false               // allow reading drawable for recording
        view.preferredFramesPerSecond = 120        // ProMotion; clamped on 60Hz devices
        view.isPaused = false
        view.enableSetNeedsDisplay = false
        view.isOpaque = true
        view.backgroundColor = .black
        view.isMultipleTouchEnabled = false
        view.autoResizeDrawable = true

        if let renderer = MetalRenderer(metalView: view, frameSource: viewModel) {
            context.coordinator.renderer = renderer
            view.delegate = renderer
            viewModel.attach(renderer: renderer)
        }
        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        uiView.preferredFramesPerSecond = viewModel.maxFrameRate
    }

    @MainActor
    final class Coordinator {
        var renderer: MetalRenderer?
    }
}
