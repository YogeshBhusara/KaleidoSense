//
//  MotionManager.swift
//  KaleidoSense
//
//  Wraps CoreMotion using a *pull* model: device motion updates are started
//  without a handler and the renderer samples `CMMotionManager.deviceMotion`
//  once per frame via `sample(dt:)`. This keeps everything on the main thread
//  (where the Metal draw loop already runs), avoids cross-actor hops, and lets
//  us apply frame-rate-correct exponential smoothing in one place.
//
//  When device motion is unavailable (e.g. the Simulator), a gentle synthetic
//  idle sample is produced so the experience still looks alive.
//

import CoreMotion
import QuartzCore
import simd

@MainActor
final class MotionManager {

    private let manager = CMMotionManager()
    private let sensitivityProvider: () -> Float

    // Smoothing state (persisted across frames).
    private var smoothedGravity = SIMD2<Float>(0, -1)
    private var smoothedTilt = SIMD2<Float>.zero
    private var smoothedRotationSpeed: Float = 0
    private var smoothedAccel: Float = 0
    private var smoothedYawRate: Float = 0
    private var smoothedUserAccel = SIMD2<Float>.zero
    private var accumulatedYaw: Float = 0

    private(set) var isActive = false

    /// - Parameter sensitivity: closure returning the current user sensitivity
    ///   (0...1) so motion response can be tuned live from the UI.
    init(sensitivity: @escaping () -> Float) {
        self.sensitivityProvider = sensitivity
    }

    var isDeviceMotionAvailable: Bool { manager.isDeviceMotionAvailable }

    func start() {
        guard manager.isDeviceMotionAvailable, !isActive else { return }
        // 120 Hz target; CoreMotion clamps to the hardware maximum.
        manager.deviceMotionUpdateInterval = 1.0 / 120.0
        manager.startDeviceMotionUpdates(using: .xArbitraryZVertical)
        isActive = true
    }

    func stop() {
        guard isActive else { return }
        manager.stopDeviceMotionUpdates()
        isActive = false
    }

    /// Produces a smoothed sample for the current frame.
    func sample(dt: Float) -> MotionSample {
        let sensitivity = sensitivityProvider().clamped(to: 0...1)
        // More sensitivity -> shorter half-life -> snappier response.
        let halfLife = Float(0.18 - 0.12 * sensitivity)
        let k = Float.smoothingFactor(halfLife: max(halfLife, 0.03), dt: dt)

        guard let dm = manager.deviceMotion else {
            return synthSample(dt: dt, sensitivity: sensitivity, k: k)
        }

        let g = dm.gravity
        let rr = dm.rotationRate
        let ua = dm.userAcceleration
        let att = dm.attitude

        let rawGravity = SIMD2<Float>(Float(g.x), Float(g.y))
        let rawTilt = SIMD2<Float>(Float(att.roll), Float(att.pitch))
        let rawRotSpeed = Float(sqrt(rr.x * rr.x + rr.y * rr.y + rr.z * rr.z))
        let rawAccel = Float(sqrt(ua.x * ua.x + ua.y * ua.y + ua.z * ua.z))

        let rawUserAccel = SIMD2<Float>(Float(ua.x), Float(ua.y))
        let rawYawRate = Float(rr.z)

        smoothedGravity += (rawGravity - smoothedGravity) * k
        smoothedTilt += (rawTilt - smoothedTilt) * k
        smoothedRotationSpeed += (rawRotSpeed - smoothedRotationSpeed) * k
        smoothedAccel += (rawAccel - smoothedAccel) * k
        smoothedYawRate += (rawYawRate - smoothedYawRate) * k
        smoothedUserAccel += (rawUserAccel - smoothedUserAccel) * k

        // Integrate yaw rate (scaled by sensitivity) for a continuous spin.
        accumulatedYaw += Float(rr.z) * dt * (0.5 + sensitivity)

        return assemble(att: SIMD3(Float(att.roll), Float(att.pitch), Float(att.yaw)),
                        sensitivity: sensitivity)
    }

    // MARK: - Helpers

    private func assemble(att: SIMD3<Float>, sensitivity: Float) -> MotionSample {
        let energy = (smoothedRotationSpeed * 0.35 + smoothedAccel * 1.2).clamped(to: 0...1)
        let gain = 0.6 + sensitivity * 0.8
        return MotionSample(
            roll: att.x,
            pitch: att.y,
            yaw: att.z,
            gravity2D: smoothedGravity.normalizedSafe,
            tilt: smoothedTilt * gain,
            rotationZ: accumulatedYaw,
            rotationSpeed: smoothedRotationSpeed,
            yawRate: smoothedYawRate,
            userAccel: smoothedUserAccel,
            accelerationMagnitude: smoothedAccel,
            energy: energy
        )
    }

    /// Slow synthetic drift used when no real sensors are present.
    private func synthSample(dt: Float, sensitivity: Float, k: Float) -> MotionSample {
        let t = Float(CACurrentMediaTime())
        let g = SIMD2<Float>(sin(t * 0.3) * 0.4, -1 + cos(t * 0.21) * 0.1).normalizedSafe
        smoothedGravity += (g - smoothedGravity) * k
        accumulatedYaw += dt * 0.15
        let tilt = SIMD2<Float>(sin(t * 0.4) * 0.2, cos(t * 0.33) * 0.2)
        smoothedTilt += (tilt - smoothedTilt) * k
        return MotionSample(
            roll: tilt.x, pitch: tilt.y, yaw: accumulatedYaw,
            gravity2D: smoothedGravity,
            tilt: smoothedTilt,
            rotationZ: accumulatedYaw,
            rotationSpeed: 0.05,
            yawRate: 0.15,
            userAccel: SIMD2<Float>(sin(t * 0.7) * 0.05, cos(t * 0.5) * 0.05),
            accelerationMagnitude: 0.02,
            energy: 0.08
        )
    }
}
