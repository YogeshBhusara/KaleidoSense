//
//  MotionSample.swift
//  KaleidoSense
//
//  An immutable, smoothed snapshot of device motion for a single frame.
//

import simd

struct MotionSample: Sendable {
    /// Attitude in radians.
    var roll: Float
    var pitch: Float
    var yaw: Float

    /// Gravity projected into the 2D pattern plane (drives "which way is down").
    var gravity2D: SIMD2<Float>

    /// Small roll/pitch offset used for parallax translation of the pattern.
    var tilt: SIMD2<Float>

    /// Accumulated yaw rotation used to spin the kaleidoscope (radians).
    var rotationZ: Float

    /// Instantaneous rotation-rate magnitude (rad/s), smoothed.
    var rotationSpeed: Float

    /// Signed yaw rate (rad/s, smoothed) — drives the swirl of the fragments.
    var yawRate: Float

    /// Smoothed user acceleration in the screen plane (g) — a direct "shove".
    var userAccel: SIMD2<Float>

    /// Instantaneous user-acceleration magnitude (g), smoothed.
    var accelerationMagnitude: Float

    /// Combined, normalized 0...1 "how much is happening" value.
    var energy: Float

    static let neutral = MotionSample(
        roll: 0, pitch: 0, yaw: 0,
        gravity2D: SIMD2(0, -1),
        tilt: .zero,
        rotationZ: 0,
        rotationSpeed: 0,
        yawRate: 0,
        userAccel: .zero,
        accelerationMagnitude: 0,
        energy: 0
    )
}
