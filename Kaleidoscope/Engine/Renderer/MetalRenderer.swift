//
//  MetalRenderer.swift
//  KaleidoSense
//
//  MTKView delegate that drives the kaleidoscope. Each frame it pulls the
//  current `Uniforms` and folded particle buffer from its frame source, copies
//  them into a triple-buffered pool (so the CPU never writes a buffer the GPU is
//  still reading), encodes the single full-screen pass, and presents.
//
//  It also exposes:
//    • `snapshot(size:)` – renders one frame off-screen at an arbitrary
//      resolution for high-resolution photo export.
//    • `captureHandler` – invoked with the drawable texture each frame while
//      recording, feeding the video pipeline.
//

import MetalKit
import simd
import os

/// Supplies per-frame render data. Implemented by the view model.
@MainActor
protocol KaleidoscopeFrameSource: AnyObject {
    /// Steps simulation by `dt` and returns the data for this frame.
    func makeFrame(dt: Float, drawableSize: SIMD2<Float>) -> (uniforms: Uniforms, particles: [GPUParticle])
    /// Reports the measured frame duration for instrumentation.
    func frameCompleted(duration: CFTimeInterval)
}

@MainActor
final class MetalRenderer: NSObject, MTKViewDelegate {

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLRenderPipelineState

    // Triple buffering.
    private static let maxInFlight = 3
    private let inFlight = DispatchSemaphore(value: maxInFlight)
    private var uniformBuffers: [MTLBuffer] = []
    private var particleBuffers: [MTLBuffer] = []
    private var frameIndex = 0

    private weak var frameSource: KaleidoscopeFrameSource?
    private var lastTimestamp: CFTimeInterval = 0

    // Cached last frame data for off-screen snapshotting.
    private var lastUniforms = Uniforms()
    private var lastParticles: [GPUParticle] = []

    /// Called with the just-rendered drawable texture while recording.
    var captureHandler: ((MTLTexture) -> Void)?

    init?(metalView: MTKView, frameSource: KaleidoscopeFrameSource) {
        guard let device = metalView.device ?? MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary(),
              let vertexFn = library.makeFunction(name: "vertex_main"),
              let fragmentFn = library.makeFunction(name: "fragment_main") else {
            return nil
        }
        self.device = device
        self.commandQueue = queue
        self.frameSource = frameSource

        let desc = MTLRenderPipelineDescriptor()
        desc.label = "KaleidoscopePipeline"
        desc.vertexFunction = vertexFn
        desc.fragmentFunction = fragmentFn
        desc.colorAttachments[0].pixelFormat = metalView.colorPixelFormat
        do {
            pipelineState = try device.makeRenderPipelineState(descriptor: desc)
        } catch {
            return nil
        }

        super.init()

        let uniformStride = MemoryLayout<Uniforms>.stride
        let particleStride = MemoryLayout<GPUParticle>.stride * Int(KS_MAX_PARTICLES)
        for i in 0..<Self.maxInFlight {
            guard let ub = device.makeBuffer(length: uniformStride, options: .storageModeShared),
                  let pb = device.makeBuffer(length: particleStride, options: .storageModeShared) else {
                return nil
            }
            ub.label = "Uniforms \(i)"
            pb.label = "Particles \(i)"
            uniformBuffers.append(ub)
            particleBuffers.append(pb)
        }
    }

    // MARK: - MTKViewDelegate (called on the main thread)

    nonisolated func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // Nothing to do; the shader reads resolution from uniforms each frame.
    }

    nonisolated func draw(in view: MTKView) {
        MainActor.assumeIsolated {
            self.renderFrame(in: view)
        }
    }

    private func renderFrame(in view: MTKView) {
        guard let frameSource,
              let drawable = view.currentDrawable,
              let passDescriptor = view.currentRenderPassDescriptor else {
            return
        }

        // Frame timing.
        let now = CACurrentMediaTime()
        let dt: Float
        if lastTimestamp > 0 {
            dt = Float(now - lastTimestamp)
        } else {
            dt = 1.0 / 60.0
        }
        lastTimestamp = now

        let size = SIMD2<Float>(Float(view.drawableSize.width), Float(view.drawableSize.height))
        let (uniforms, particles) = frameSource.makeFrame(dt: dt, drawableSize: size)
        lastUniforms = uniforms
        lastParticles = particles

        inFlight.wait()
        frameIndex = (frameIndex + 1) % Self.maxInFlight
        let ub = uniformBuffers[frameIndex]
        let pb = particleBuffers[frameIndex]
        write(uniforms: uniforms, particles: particles, into: ub, pb)

        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            inFlight.signal()
            return
        }

        let semaphore = inFlight
        commandBuffer.addCompletedHandler { [weak self] _ in
            semaphore.signal()
            let frameDuration = CACurrentMediaTime() - now
            Task { @MainActor in self?.frameSource?.frameCompleted(duration: frameDuration) }
        }

        if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor) {
            encoder.setRenderPipelineState(pipelineState)
            encoder.setFragmentBuffer(ub, offset: 0, index: Int(KSBufferIndexUniforms.rawValue))
            encoder.setFragmentBuffer(pb, offset: 0, index: Int(KSBufferIndexParticles.rawValue))
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            encoder.endEncoding()
        }

        // Feed the recorder before presenting.
        if let captureHandler { captureHandler(drawable.texture) }

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    private func write(uniforms: Uniforms, particles: [GPUParticle],
                       into uniformBuffer: MTLBuffer, _ particleBuffer: MTLBuffer) {
        var u = uniforms
        memcpy(uniformBuffer.contents(), &u, MemoryLayout<Uniforms>.stride)
        if !particles.isEmpty {
            particles.withUnsafeBytes { raw in
                memcpy(particleBuffer.contents(), raw.baseAddress!, raw.count)
            }
        }
    }

    // MARK: - High-resolution off-screen snapshot

    /// Renders the most recent frame into an off-screen texture and returns a
    /// CGImage suitable for export. `size` is in pixels.
    func snapshot(size: CGSize) -> CGImage? {
        let width = max(Int(size.width), 1)
        let height = max(Int(size.height), 1)

        let texDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        texDesc.usage = [.renderTarget, .shaderRead]
        texDesc.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: texDesc) else { return nil }

        var uniforms = lastUniforms
        uniforms.resolution = SIMD2<Float>(Float(width), Float(height))

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)

        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else {
            return nil
        }

        let uStride = MemoryLayout<Uniforms>.stride
        let pStride = MemoryLayout<GPUParticle>.stride * max(lastParticles.count, 1)
        guard let ub = device.makeBuffer(bytes: &uniforms, length: uStride, options: .storageModeShared),
              let pb = device.makeBuffer(length: pStride, options: .storageModeShared) else {
            encoder.endEncoding()
            return nil
        }
        if !lastParticles.isEmpty {
            lastParticles.withUnsafeBytes { memcpy(pb.contents(), $0.baseAddress!, $0.count) }
        }

        encoder.setRenderPipelineState(pipelineState)
        encoder.setFragmentBuffer(ub, offset: 0, index: Int(KSBufferIndexUniforms.rawValue))
        encoder.setFragmentBuffer(pb, offset: 0, index: Int(KSBufferIndexParticles.rawValue))
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        return Self.makeCGImage(from: texture)
    }

    private static func makeCGImage(from texture: MTLTexture) -> CGImage? {
        let width = texture.width
        let height = texture.height
        let rowBytes = width * 4
        var data = [UInt8](repeating: 0, count: rowBytes * height)
        texture.getBytes(&data, bytesPerRow: rowBytes,
                         from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        // Texture is BGRA; use the matching byte order so colors are correct.
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue
                                      | CGBitmapInfo.byteOrder32Little.rawValue)
        guard let provider = CGDataProvider(data: Data(data) as CFData) else { return nil }
        return CGImage(width: width, height: height,
                       bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: rowBytes,
                       space: colorSpace, bitmapInfo: bitmapInfo,
                       provider: provider, decode: nil, shouldInterpolate: false,
                       intent: .defaultIntent)
    }
}
