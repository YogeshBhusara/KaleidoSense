//
//  ProceduralAudioEngine.swift
//  KaleidoSense
//
//  Real-time procedural audio for the kaleidoscope. There are no audio files
//  and no loops — every sound is synthesized:
//
//    • Chimes      – inharmonic bell-like voices (3 partials) triggered by
//                    rotation and tilt changes.
//    • Crystal clicks – very short, bright voices with a noise transient,
//                    triggered by sharp accelerations / shakes.
//    • Soft rolling – a continuously filtered noise bed whose level follows
//                    overall motion energy (the "beads rolling" sound).
//
//  Concurrency: the AVAudioSourceNode render block runs on the real-time audio
//  thread (AURemoteIO). It must never touch MainActor state or Swift's
//  `OSAllocatedUnfairLock` (which can trip dispatch queue assertions there).
//  All shared DSP state is guarded by a plain `os_unfair_lock`, which is safe
//  for very short critical sections on both the main thread and the audio thread.
//

import AVFoundation
import os
import simd

// MARK: - Synthesizer (real-time safe, Sendable)

nonisolated final class Synthesizer: @unchecked Sendable {

    private struct Voice {
        var active = false
        var partialFreq = SIMD3<Float>(0, 0, 0)
        var partialPhase = SIMD3<Float>(0, 0, 0)
        var partialAmp = SIMD3<Float>(0, 0, 0)
        var env: Float = 0
        var envDecay: Float = 0.9999
        var noiseMix: Float = 0
        var pan: Float = 0.5
    }

    private struct State {
        var voices: [Voice]
        var rollLevel: Float = 0
        var rollSmoothed: Float = 0
        var noiseLP: Float = 0
        var masterGain: Float = 0
        var targetGain: Float = 0
        var rng: UInt64 = 0x2545F4914F6CDD1D
        var nextVoice: Int = 0
    }

    let sampleRate: Float
    private var state: State
    private var lock = os_unfair_lock_s()
    private let voiceCount = 24

    init(sampleRate: Float) {
        self.sampleRate = sampleRate
        self.state = State(voices: Array(repeating: Voice(), count: 24))
    }

    // MARK: Parameter updates (main thread)

    func setEnabled(_ enabled: Bool) {
        withLock { $0.targetGain = enabled ? 1 : 0 }
    }

    func setRollLevel(_ level: Float) {
        withLock { $0.rollLevel = level.clamped(to: 0...1) }
    }

    func triggerChime(frequency: Float, brightness: Float, decay: Float, gain: Float, pan: Float) {
        withLock { state in
            let i = state.nextVoice
            state.nextVoice = (state.nextVoice + 1) % voiceCount
            let f0 = frequency
            var v = Voice()
            v.active = true
            v.partialFreq = SIMD3(f0, f0 * 2.76, f0 * 5.40)
            v.partialPhase = .zero
            v.partialAmp = SIMD3(0.6, 0.3 * brightness, 0.18 * brightness) * gain
            v.env = 1
            v.envDecay = powf(0.001, 1.0 / max(decay * sampleRate, 1))
            v.pan = pan.clamped(to: 0...1)
            state.voices[i] = v
        }
    }

    func triggerClick(frequency: Float, gain: Float, pan: Float) {
        withLock { state in
            let i = state.nextVoice
            state.nextVoice = (state.nextVoice + 1) % voiceCount
            var v = Voice()
            v.active = true
            v.partialFreq = SIMD3(frequency, frequency * 3.1, frequency * 6.7)
            v.partialAmp = SIMD3(0.5, 0.35, 0.2) * gain
            v.env = 1
            v.envDecay = powf(0.001, 1.0 / max(0.06 * sampleRate, 1))
            v.noiseMix = 0.6
            v.pan = pan.clamped(to: 0...1)
            state.voices[i] = v
        }
    }

    // MARK: Render (real-time audio thread — must stay lock-only, no allocations)

    func render(left: UnsafeMutablePointer<Float>,
                right: UnsafeMutablePointer<Float>,
                frames: Int) {
        let twoPiOverSR = (2 * Float.pi) / sampleRate
        withLock { state in
            for n in 0..<frames {
                state.masterGain += (state.targetGain - state.masterGain) * 0.0008
                state.rollSmoothed += (state.rollLevel - state.rollSmoothed) * 0.0006

                var sampleL: Float = 0
                var sampleR: Float = 0

                let white = Self.whiteNoise(&state.rng)
                state.noiseLP += (white - state.noiseLP) * 0.05
                let roll = state.noiseLP * state.rollSmoothed * 0.25
                sampleL += roll
                sampleR += roll

                for vi in 0..<state.voices.count {
                    guard state.voices[vi].active else { continue }
                    var v = state.voices[vi]

                    var s = simd_dot(sin(v.partialPhase), v.partialAmp)
                    if v.noiseMix > 0 {
                        s += Self.whiteNoise(&state.rng) * v.noiseMix * v.env
                    }
                    s *= v.env

                    let panAngle = v.pan * (Float.pi / 2)
                    sampleL += s * cosf(panAngle)
                    sampleR += s * sinf(panAngle)

                    v.partialPhase += v.partialFreq * twoPiOverSR
                    v.partialPhase -= floor(v.partialPhase / (2 * Float.pi)) * (2 * Float.pi)
                    v.env *= v.envDecay
                    if v.env < 0.0002 { v.active = false }
                    state.voices[vi] = v
                }

                let g = state.masterGain * 0.5
                left[n] = tanhf(sampleL * g)
                right[n] = tanhf(sampleR * g)
            }
        }
    }

    // MARK: Lock helper

    private func withLock(_ body: (inout State) -> Void) {
        os_unfair_lock_lock(&lock)
        body(&state)
        os_unfair_lock_unlock(&lock)
    }

    private static func whiteNoise(_ rng: inout UInt64) -> Float {
        rng ^= rng << 13
        rng ^= rng >> 7
        rng ^= rng << 17
        let u = Float(rng >> 40) / Float(1 << 24)
        return u * 2 - 1
    }
}

// MARK: - Engine (main-actor orchestration)

@MainActor
final class ProceduralAudioEngine {

    private let engine = AVAudioEngine()
    private let synth: Synthesizer
    private var sourceNode: AVAudioSourceNode?
    private(set) var isRunning = false
    var isEnabled = false {
        didSet {
            guard oldValue != isEnabled else { return }
            synth.setEnabled(isEnabled && isRunning)
        }
    }

    private var prevRotation: Float = 0
    private var prevAccel: Float = 0
    private var chimeCooldown: Float = 0
    private var clickCooldown: Float = 0
    private let scale: [Float] = [0, 2, 3, 5, 7, 9, 10, 12]

    init() {
        // Default sample rate until the session is configured in `start()`.
        self.synth = Synthesizer(sampleRate: 48_000)
    }

    func start() {
        guard !isRunning else { return }

        configureSession()

        let sessionRate = AVAudioSession.sharedInstance().sampleRate
        let sr = sessionRate > 0 ? sessionRate : 48_000
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 2) else { return }

        // Build the render node in a nonisolated context. This is critical:
        // under `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, a closure created
        // inside this @MainActor method would be inferred @MainActor and Swift
        // would inject a `dispatch_assert_queue(main)` check. CoreAudio calls
        // the block on AURemoteIO::IOThread, so that assertion would crash with
        // "BUG IN CLIENT OF LIBDISPATCH". The factory keeps the block isolation-free.
        let node = Self.makeSourceNode(format: format, synth: synth)

        engine.stop()
        if let existing = sourceNode {
            engine.detach(existing)
            sourceNode = nil
        }

        sourceNode = node
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 1.0
        engine.prepare()

        do {
            try engine.start()
            isRunning = true
            synth.setEnabled(isEnabled)
        } catch {
            isRunning = false
        }
    }

    /// Creates the real-time render node outside of any actor isolation so the
    /// render block is callable on the audio I/O thread without a MainActor
    /// dispatch assertion. Only captures the `Sendable` synthesizer.
    nonisolated private static func makeSourceNode(format: AVAudioFormat,
                                                   synth: Synthesizer) -> AVAudioSourceNode {
        AVAudioSourceNode(format: format) { _, _, frameCount, ablPointer -> OSStatus in
            let abl = UnsafeMutableAudioBufferListPointer(ablPointer)
            let frames = Int(frameCount)
            guard abl.count >= 2,
                  let lPtr = abl[0].mData?.assumingMemoryBound(to: Float.self),
                  let rPtr = abl[1].mData?.assumingMemoryBound(to: Float.self) else {
                return noErr
            }
            synth.render(left: lPtr, right: rPtr, frames: frames)
            return noErr
        }
    }

    func stop() {
        guard isRunning else { return }
        synth.setEnabled(false)
        engine.stop()
        if let node = sourceNode {
            engine.detach(node)
            sourceNode = nil
        }
        isRunning = false
    }

    private func configureSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            // Audio is optional; visuals continue without it.
        }
    }

    func update(motion: MotionSample, profile: AudioProfile, dt: Float) {
        guard isRunning, isEnabled else { return }

        chimeCooldown = max(0, chimeCooldown - dt)
        clickCooldown = max(0, clickCooldown - dt)

        synth.setRollLevel(profile.rollLevel * motion.energy.clamped(to: 0...1))

        let pan = (motion.tilt.x * 0.5 + 0.5).clamped(to: 0...1)

        let rotDelta = motion.rotationSpeed - prevRotation
        prevRotation = motion.rotationSpeed
        if chimeCooldown == 0, motion.rotationSpeed > 0.6, rotDelta > 0.02 {
            let step = scale.randomElement() ?? 0
            let freq = profile.baseFrequency * powf(2, step / 12)
            let gain = (0.2 + motion.rotationSpeed * 0.2).clamped(to: 0...0.7)
            synth.triggerChime(frequency: freq, brightness: profile.brightness,
                               decay: profile.decay, gain: gain, pan: pan)
            chimeCooldown = 0.08 / max(profile.chimeDensity, 0.1)
        }

        let accelDelta = motion.accelerationMagnitude - prevAccel
        prevAccel = motion.accelerationMagnitude
        if clickCooldown == 0, accelDelta > 0.08 {
            let freq = profile.baseFrequency * Float.random(in: 1.5...3.0)
            let gain = (accelDelta * 2).clamped(to: 0.05...0.6)
            synth.triggerClick(frequency: freq, gain: gain, pan: pan)
            clickCooldown = 0.05
        }
    }

    func playFlourish(profile: AudioProfile) {
        guard isRunning, isEnabled else { return }
        for i in 0..<4 {
            let step = scale[(i * 2) % scale.count]
            let freq = profile.baseFrequency * powf(2, step / 12)
            synth.triggerChime(frequency: freq, brightness: profile.brightness,
                               decay: profile.decay, gain: 0.25,
                               pan: Float(i) / 3)
        }
    }
}
