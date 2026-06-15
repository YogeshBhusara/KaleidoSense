//
//  Particle.swift
//  KaleidoSense
//
//  CPU-side representation of a glass fragment. Physics runs on these and the
//  result is folded into `GPUParticle` values for the shader each frame.
//

import simd

struct Particle {
    var position: SIMD2<Float>     // disc-space position, |p| <= chamberRadius
    var velocity: SIMD2<Float>
    var color: SIMD4<Float>
    var radius: Float
    var rotation: Float
    var angularVelocity: Float
    var refraction: Float
    var mass: Float
    var seed: Float
}
