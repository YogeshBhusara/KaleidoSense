//
//  HapticsManager.swift
//  KaleidoSense
//
//  Thin wrapper around CoreHaptics providing a few premium, restrained haptic
//  gestures: subtle ticks when motion crosses thresholds, a richer swell when
//  the pattern changes dramatically, and a crisp tap for the randomize action.
//
//  All calls are no-ops on devices without a haptic engine, so callers never
//  need to branch.
//

import CoreHaptics
import QuartzCore
import UIKit

@MainActor
final class HapticsManager {

    private var engine: CHHapticEngine?
    private(set) var isSupported = CHHapticEngine.capabilitiesForHardware().supportsHaptics
    var isEnabled = true

    private var thresholdCooldown: TimeInterval = 0
    private var lastEventTime: TimeInterval = 0

    func prepare() {
        guard isSupported, engine == nil else { return }
        do {
            let engine = try CHHapticEngine()
            engine.isAutoShutdownEnabled = true
            // These handlers are invoked by CoreHaptics on arbitrary threads.
            // Mark them @Sendable + nonisolated so the MainActor default
            // isolation does not inject a main-queue assertion that would crash
            // when the system calls them off the main thread.
            engine.resetHandler = { [weak engine] in
                nonisolated(unsafe) let e = engine
                try? e?.start()
            }
            engine.stoppedHandler = { _ in }
            try engine.start()
            self.engine = engine
        } catch {
            self.engine = nil
        }
    }

    func stop() {
        engine?.stop()
        engine = nil
    }

    // MARK: - Gestures

    /// A very subtle tick used when motion crosses an intensity threshold.
    /// Rate-limited so rapid movement doesn't produce a buzz.
    func motionTick(intensity: Float) {
        let now = CACurrentMediaTime()
        guard now - thresholdCooldown > 0.09 else { return }
        thresholdCooldown = now
        playTransient(intensity: intensity.clamped(to: 0.1...0.5), sharpness: 0.3)
    }

    /// A crisp confirmation tap (e.g. randomize).
    func tap() {
        playTransient(intensity: 0.8, sharpness: 0.7)
    }

    /// A short two-stage swell used when a large pattern change happens
    /// (e.g. switching modes or symmetry).
    func patternChange() {
        guard isEnabled, isSupported, let engine else {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            return
        }
        do {
            let events = [
                CHHapticEvent(eventType: .hapticTransient, parameters: [
                    .init(parameterID: .hapticIntensity, value: 0.5),
                    .init(parameterID: .hapticSharpness, value: 0.4)
                ], relativeTime: 0),
                CHHapticEvent(eventType: .hapticContinuous, parameters: [
                    .init(parameterID: .hapticIntensity, value: 0.35),
                    .init(parameterID: .hapticSharpness, value: 0.2)
                ], relativeTime: 0.04, duration: 0.18)
            ]
            let pattern = try CHHapticPattern(events: events, parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: 0)
        } catch {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        }
    }

    // MARK: - Primitive

    private func playTransient(intensity: Float, sharpness: Float) {
        guard isEnabled else { return }
        guard isSupported, let engine else {
            // Graceful fallback on non-CoreHaptics hardware.
            UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: CGFloat(intensity))
            return
        }
        do {
            let event = CHHapticEvent(eventType: .hapticTransient, parameters: [
                .init(parameterID: .hapticIntensity, value: intensity),
                .init(parameterID: .hapticSharpness, value: sharpness)
            ], relativeTime: 0)
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: 0)
        } catch {
            // Ignore transient failures.
        }
    }
}
