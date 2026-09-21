//
//  KaleidoscopeViewModel.swift
//  KaleidoSense
//
//  The single orchestrator (MVVM). It owns the engine subsystems, advances the
//  simulation each frame on behalf of the renderer, maps motion onto audio and
//  haptics, and exposes observable state for the SwiftUI controls.
//
//  Per-frame simulation data (particles, motion) is deliberately kept out of the
//  observable surface so the controls don't re-render 120 times a second.
//

import SwiftUI
import Observation
import simd

@MainActor
@Observable
final class KaleidoscopeViewModel: KaleidoscopeFrameSource {

    // MARK: - Observable UI state

    var mode: KaleidoscopeMode = .classic
    var symmetry: SymmetryMode = .six
    var palette: ColorPalette = KaleidoscopeMode.classic.palette
    var motionSensitivity: Double = 0.5
    var audioEnabled: Bool = false
    var hapticsEnabled: Bool = true
    var controlsVisible: Bool = true
    var showPerformanceHUD: Bool = false
    var prefersBatterySaver: Bool = false
    var isRecording: Bool = false
    var sharePayload: SharePayload?
    var errorMessage: String?

    let performance = PerformanceMonitor()

    var maxFrameRate: Int { prefersBatterySaver ? 60 : 120 }

    // MARK: - Accessibility (pushed from the environment by the view)

    @ObservationIgnored var reduceMotion = false
    @ObservationIgnored var reduceTransparency = false

    // MARK: - Engine subsystems (not observed)

    @ObservationIgnored private lazy var particleSystem = ParticleSystem(mode: mode)
    @ObservationIgnored private lazy var motionManager = MotionManager(
        sensitivity: { [weak self] in Float(self?.motionSensitivity ?? 0.5) })
    @ObservationIgnored private let audio = ProceduralAudioEngine()
    @ObservationIgnored private let haptics = HapticsManager()
    @ObservationIgnored private weak var renderer: MetalRenderer?
    @ObservationIgnored private let videoRecorder = VideoRecorder()

    // MARK: - Frame state

    @ObservationIgnored private var startTime: CFTimeInterval = CACurrentMediaTime()
    @ObservationIgnored private var patternRotation: Float = 0
    @ObservationIgnored private var prevEnergy: Float = 0
    @ObservationIgnored private var lastDrawableSize = SIMD2<Float>(1170, 2532)

    /// 0...1 smoothed device-movement amount. Drives whether the pattern is
    /// alive (moving) or frozen (steady).
    @ObservationIgnored private var smoothedActivity: Float = 0
    /// Animation clock that only advances while the device is moving, so all
    /// time-based shader effects (light orbit, sweep, shimmer, breathing) stop
    /// when the phone is held steady.
    @ObservationIgnored private var animationPhase: Float = 0

    // MARK: - Lifecycle

    func onAppear() {
        startTime = CACurrentMediaTime()
        motionManager.start()
        haptics.prepare()
        haptics.isEnabled = hapticsEnabled
        if audioEnabled {
            audio.start()
            audio.isEnabled = true
        }
    }

    func onDisappear() {
        motionManager.stop()
        audio.stop()
        haptics.stop()
    }

    func attach(renderer: MetalRenderer) {
        self.renderer = renderer
    }

    // MARK: - KaleidoscopeFrameSource

    func makeFrame(dt: Float, drawableSize: SIMD2<Float>) -> (uniforms: Uniforms, particles: [GPUParticle]) {
        lastDrawableSize = drawableSize
        let motion = motionManager.sample(dt: dt)

        // Movement signal with a small deadzone so sensor noise reads as "still".
        // Uses the dynamic parts of motion (rotation rate + user acceleration),
        // not static gravity, so a steady-but-tilted phone counts as steady.
        let deadzone: Float = 0.025
        let rawActivity = ((motion.rotationSpeed * 0.9 + motion.accelerationMagnitude * 2.2) - deadzone)
            .clamped(to: 0...1)
        // Asymmetric smoothing: rise instantly when movement starts, fall quickly
        // when it stops so the fragments settle almost immediately — like real
        // beads coming to rest the moment you hold the kaleidoscope still.
        let rising = rawActivity > smoothedActivity
        let k = Float.smoothingFactor(halfLife: rising ? 0.03 : 0.09, dt: dt)
        smoothedActivity += (rawActivity - smoothedActivity) * k
        if smoothedActivity < 0.01 { smoothedActivity = 0 }     // true rest

        // Time-based effects only advance while moving → frozen when steady.
        if !reduceMotion {
            animationPhase += dt * smoothedActivity
            patternRotation += dt * smoothedActivity * 0.4
        }

        // Physics. Gravity points "down" in screen space; we flip Y so tilting
        // the phone makes fragments flow toward the low edge naturally. The
        // shove (user acceleration) and swirl (yaw rate) give a direct,
        // immediate response to moving the phone.
        // Physics is driven directly by the user's deliberate phone movement, so
        // it stays active even when "Reduce Motion" is on (that setting only
        // suppresses the autonomous drift / light animation above).
        let gravity = SIMD2<Float>(motion.gravity2D.x, -motion.gravity2D.y)
        let shove = SIMD2<Float>(motion.userAccel.x, -motion.userAccel.y)
        particleSystem.update(dt: dt, gravity: gravity,
                              shove: shove,
                              swirl: motion.yawRate,
                              shake: motion.accelerationMagnitude,
                              activity: smoothedActivity)

        // Audio + haptics react to motion.
        audio.update(motion: motion, profile: mode.audioProfile, dt: dt)
        updateHaptics(energy: motion.energy)

        let particles = particleSystem.gpuParticles(segments: symmetry.segments)
        let uniforms = makeUniforms(motion: motion, drawableSize: drawableSize,
                                    particleCount: particles.count)
        return (uniforms, particles)
    }

    func frameCompleted(duration: CFTimeInterval) {
        performance.record(frameDuration: duration)
    }

    // MARK: - Uniform assembly

    private func makeUniforms(motion: MotionSample, drawableSize: SIMD2<Float>,
                              particleCount: Int) -> Uniforms {
        let fx = mode.effectConfig
        // Drive all shader-side animation from the motion-gated clock so the
        // light orbit, sweep and shimmer freeze when the phone is steady.
        let time = animationPhase
        let breathing = reduceMotion ? 0.88 : (0.88 + sin(time * 0.55) * 0.025)

        var u = Uniforms()
        u.paletteA = palette.a
        u.paletteB = palette.b
        u.paletteC = palette.c
        u.background = palette.background
        u.resolution = drawableSize
        u.tilt = motion.tilt
        u.time = time
        u.segments = symmetry.segments
        u.rotationZ = reduceMotion ? 0 : motion.rotationZ * 0.4
        u.motionEnergy = smoothedActivity
        u.zoom = breathing
        u.patternRotation = patternRotation
        u.particleCount = Int32(particleCount)
        u.mode = Int32(mode.rawValue)
        u.bloom = fx.bloom
        u.chromaticAberration = fx.chromaticAberration
        u.lensDistortion = fx.lensDistortion
        u.glow = fx.glow
        u.refraction = fx.refraction
        u.reduceMotion = reduceMotion ? 1 : 0
        u.reduceTransparency = reduceTransparency ? 1 : 0
        u.vignette = fx.vignette
        return u
    }

    private func updateHaptics(energy: Float) {
        defer { prevEnergy = energy }
        guard hapticsEnabled else { return }
        // Fire a subtle tick when energy rises through a threshold.
        if energy > 0.45, prevEnergy <= 0.45 {
            haptics.motionTick(intensity: 0.25 + energy * 0.25)
        }
    }

    // MARK: - User intents

    func selectMode(_ newMode: KaleidoscopeMode) {
        guard newMode != mode else { return }
        mode = newMode
        symmetry = newMode.defaultSymmetry
        palette = newMode.palette
        particleSystem.reseed(mode: newMode)
        if hapticsEnabled { haptics.patternChange() }
        if audioEnabled { audio.playFlourish(profile: newMode.audioProfile) }
    }

    func selectSymmetry(_ newSymmetry: SymmetryMode) {
        guard newSymmetry != symmetry else { return }
        symmetry = newSymmetry
        if hapticsEnabled { haptics.patternChange() }
    }

    func cycleSymmetry() { selectSymmetry(symmetry.next) }

    func selectPalette(_ newPalette: ColorPalette) {
        palette = newPalette
        particleSystem.reseed(mode: mode)
        if hapticsEnabled { haptics.tap() }
    }

    func randomize() {
        particleSystem.randomize()
        if hapticsEnabled { haptics.tap() }
        if audioEnabled { audio.playFlourish(profile: mode.audioProfile) }
    }

    func setAudioEnabled(_ enabled: Bool) {
        audioEnabled = enabled
        if enabled {
            audio.start()
            audio.isEnabled = true
        } else {
            audio.isEnabled = false
        }
    }

    func setHapticsEnabled(_ enabled: Bool) {
        hapticsEnabled = enabled
        haptics.isEnabled = enabled
    }

    func setAccessibility(reduceMotion: Bool, reduceTransparency: Bool) {
        self.reduceMotion = reduceMotion
        self.reduceTransparency = reduceTransparency
    }

    // MARK: - Capture & recording

    /// High-resolution still capture saved to Photos and offered for sharing.
    func capturePhoto() async {
        guard let renderer else { return }
        let size = snapshotSize()
        guard let cgImage = renderer.snapshot(size: size) else {
            errorMessage = ExportError.saveFailed.localizedDescription
            return
        }
        if hapticsEnabled { haptics.tap() }
        do {
            try await ImageExporter.saveToPhotos(cgImage)
            sharePayload = .image(ImageExporter.uiImage(from: cgImage))
        } catch {
            errorMessage = error.localizedDescription
            sharePayload = .image(ImageExporter.uiImage(from: cgImage))
        }
    }

    func toggleRecording() {
        if isRecording {
            Task { await stopRecording() }
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        guard let renderer, !isRecording else { return }
        let size = recordingSize()
        do {
            try videoRecorder.start(size: size, fps: 30) { [weak renderer] in
                renderer?.snapshot(size: size)
            }
            isRecording = true
            if hapticsEnabled { haptics.tap() }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func stopRecording() async {
        guard isRecording else { return }
        isRecording = false
        guard let url = await videoRecorder.stop() else { return }
        do {
            try await VideoRecorder.saveToPhotos(url)
            sharePayload = .video(url)
        } catch {
            errorMessage = error.localizedDescription
            sharePayload = .video(url)
        }
    }

    // MARK: - Sizing helpers

    private func snapshotSize() -> CGSize {
        // Render at up to 2x the drawable for a crisp export, capped to 4096.
        let scale: Float = 2
        var w = lastDrawableSize.x * scale
        var h = lastDrawableSize.y * scale
        let maxDim: Float = 4096
        let m = max(w, h)
        if m > maxDim { w *= maxDim / m; h *= maxDim / m }
        return CGSize(width: Int(w), height: Int(h))
    }

    private func recordingSize() -> CGSize {
        // 1080p-class while keeping the screen aspect ratio; even dimensions.
        let aspect = lastDrawableSize.x / max(lastDrawableSize.y, 1)
        let height: Float = 1280
        let width = (height * aspect).rounded()
        func even(_ v: Float) -> Int { let i = Int(v); return i % 2 == 0 ? i : i + 1 }
        return CGSize(width: even(width), height: even(height))
    }
}

// MARK: - Share payload

enum SharePayload: Identifiable {
    case image(UIImage)
    case video(URL)

    var id: String {
        switch self {
        case .image: return "image"
        case .video(let url): return url.absoluteString
        }
    }

    var activityItems: [Any] {
        switch self {
        case .image(let image): return [image]
        case .video(let url):   return [url]
        }
    }
}
