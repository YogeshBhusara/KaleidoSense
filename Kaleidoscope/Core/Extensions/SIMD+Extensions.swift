//
//  SIMD+Extensions.swift
//  KaleidoSense
//
//  Small vector helpers used across the physics and rendering layers. These are
//  pure value-type utilities, so they are explicitly `nonisolated` to remain
//  callable from the real-time audio thread under the project's MainActor
//  default isolation.
//

import simd
import CoreGraphics

extension SIMD2 where Scalar == Float {
    nonisolated var length: Float { simd_length(self) }
    nonisolated var lengthSquared: Float { simd_length_squared(self) }

    /// Returns a unit-length copy, or zero when the vector has no length.
    nonisolated var normalizedSafe: SIMD2<Float> {
        let len = length
        return len > .ulpOfOne ? self / len : .zero
    }

    /// Rotates the vector around the origin by `radians`.
    nonisolated func rotated(by radians: Float) -> SIMD2<Float> {
        let c = cosf(radians)
        let s = sinf(radians)
        return SIMD2<Float>(c * x - s * y, s * x + c * y)
    }
}

extension Float {
    /// Frame-rate independent exponential smoothing factor.
    /// `halfLife` is the time in seconds for the value to move halfway.
    nonisolated static func smoothingFactor(halfLife: Float, dt: Float) -> Float {
        guard halfLife > 0 else { return 1 }
        return 1 - powf(2, -dt / halfLife)
    }

    nonisolated func clamped(to range: ClosedRange<Float>) -> Float {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
