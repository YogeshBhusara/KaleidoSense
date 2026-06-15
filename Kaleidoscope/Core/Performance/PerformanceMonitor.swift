//
//  PerformanceMonitor.swift
//  KaleidoSense
//
//  Lightweight frame-time instrumentation. The renderer reports each frame's
//  duration; this aggregates a smoothed FPS and a worst-case frame time and
//  publishes them a few times per second for an optional on-screen HUD.
//
//  Profiling recommendations (see README) build on these numbers.
//

import Foundation
import Observation
import QuartzCore

@MainActor
@Observable
final class PerformanceMonitor {

    /// Smoothed frames-per-second.
    private(set) var fps: Double = 0
    /// Smoothed frame time in milliseconds.
    private(set) var frameTimeMS: Double = 0
    /// Worst frame time seen in the current publish window (ms).
    private(set) var worstFrameMS: Double = 0

    @ObservationIgnored private var emaFrameTime: Double = 1.0 / 60.0
    @ObservationIgnored private var windowWorst: Double = 0
    @ObservationIgnored private var lastPublish: CFTimeInterval = 0

    /// Reports a completed frame. `duration` is in seconds.
    func record(frameDuration duration: CFTimeInterval) {
        guard duration > 0, duration < 1 else { return }
        // Exponential moving average for a stable readout.
        emaFrameTime += (duration - emaFrameTime) * 0.1
        windowWorst = max(windowWorst, duration)

        let now = CACurrentMediaTime()
        if now - lastPublish >= 0.25 {
            lastPublish = now
            fps = emaFrameTime > 0 ? 1.0 / emaFrameTime : 0
            frameTimeMS = emaFrameTime * 1000
            worstFrameMS = windowWorst * 1000
            windowWorst = 0
        }
    }
}
