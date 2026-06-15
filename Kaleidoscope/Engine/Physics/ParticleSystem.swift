//
//  ParticleSystem.swift
//  KaleidoSense
//
//  A lightweight 2D particle physics simulation that models the loose glass
//  fragments tumbling inside a kaleidoscope's object chamber.
//
//  The chamber is a disc of radius `chamberRadius`. Each frame the simulation:
//    • applies device-gravity as a constant acceleration,
//    • adds shake-driven jitter from the device's user acceleration,
//    • integrates motion semi-implicitly,
//    • damps velocity with friction,
//    • resolves collisions with the circular wall (with restitution),
//    • performs cheap O(n²) fragment-fragment separation so they don't fully
//      overlap (n is small, ≤ KS_MAX_PARTICLES, so this stays well within budget).
//
//  Folding into the symmetry wedge happens in `gpuParticles(segments:)`, keeping
//  the physics in a simple full-disc space.
//

import simd

final class ParticleSystem {

    private(set) var particles: [Particle] = []

    /// Radius of the circular object chamber in pattern space.
    let chamberRadius: Float = 1.05

    private var config: PhysicsConfig
    private var palette: ColorPalette
    private var particleConfig: ParticleConfig

    /// Scratch buffer reused every frame to avoid per-frame allocations.
    private var gpuScratch: [GPUParticle]

    init(mode: KaleidoscopeMode) {
        self.config = mode.physicsConfig
        self.palette = mode.palette
        self.particleConfig = mode.particleConfig
        self.gpuScratch = Array(repeating: GPUParticle(), count: Int(KS_MAX_PARTICLES))
        reseed(mode: mode)
    }

    // MARK: - Configuration

    /// Replaces the whole population to match a new mode.
    func reseed(mode: KaleidoscopeMode) {
        config = mode.physicsConfig
        palette = mode.palette
        particleConfig = mode.particleConfig

        let count = min(particleConfig.count, Int(KS_MAX_PARTICLES))
        particles = (0..<count).map { _ in makeParticle() }
    }

    /// Re-randomizes positions, velocities and colors without changing the mode.
    func randomize() {
        for i in particles.indices {
            particles[i] = makeParticle()
        }
    }

    private func makeParticle() -> Particle {
        // Rejection-free disc sampling using sqrt for uniform area distribution.
        let r = sqrt(Float.random(in: 0...1)) * chamberRadius * 0.92
        let theta = Float.random(in: 0...(2 * .pi))
        let pos = SIMD2<Float>(cos(theta), sin(theta)) * r
        let radius = Float.random(in: particleConfig.minRadius...particleConfig.maxRadius)
        var color = palette.randomFragmentColor()
        color.w = particleConfig.alpha
        return Particle(
            position: pos,
            velocity: SIMD2<Float>(.random(in: -0.3...0.3), .random(in: -0.3...0.3)),
            color: color,
            radius: radius,
            rotation: .random(in: 0...(2 * .pi)),
            angularVelocity: .random(in: -particleConfig.spin...particleConfig.spin),
            refraction: particleConfig.refraction * Float.random(in: 0.6...1.0),
            mass: max(radius * radius, 0.0008),
            seed: .random(in: 0...1)
        )
    }

    // MARK: - Simulation

    /// Advances the simulation by `dt` seconds.
    /// - Parameters:
    ///   - gravity: 2D gravity direction derived from the device attitude.
    ///   - shove: smoothed user acceleration in the screen plane — a direct push.
    ///   - swirl: signed yaw rate — spins the whole bed of fragments.
    ///   - shake: magnitude of user acceleration, drives random jitter.
    ///   - activity: 0...1 amount of device movement. Forces are scaled by this
    ///     so a perfectly steady phone applies no force and the fragments settle
    ///     to a complete stop (like real beads at rest); any movement makes them
    ///     tumble again.
    func update(dt: Float, gravity: SIMD2<Float>, shove: SIMD2<Float>,
                swirl: Float, shake: Float, activity: Float) {
        guard dt > 0 else { return }
        let clampedDt = min(dt, 1.0 / 30.0)   // guard against hitches

        let act = activity.clamped(to: 0...1)

        // Gravity only pulls while the device is in motion, so holding the phone
        // still — even at a tilt — leaves the fragments where they are.
        let gravAccel = gravity * config.gravityScale * 9.0 * act
        // Direct shove from user acceleration (in g) — the strongest, most
        // immediate "I moved the phone" response.
        let shoveAccel = shove * 48.0
        // Friction: gentle while moving so shards actually flow, ramping up to
        // near-stiction only as the device approaches stillness.
        let idleFriction: Float = 0.985
        let blend = 1 - Self.smoothstep(0.0, 0.18, act)   // 1 when idle, 0 when active
        let curFriction = (config.friction + (idleFriction - config.friction) * blend)
            .clamped(to: 0...0.999)
        let frictionFactor = powf(1 - curFriction, clampedDt)
        let jitterAmt = config.jitter * shake * 2.5

        for i in particles.indices {
            var p = particles[i]

            // Acceleration: gravity + direct shove + swirl (tangential) + jitter.
            var a = gravAccel + shoveAccel
            // Swirl: a tangential force proportional to yaw rate and radius.
            let tangent = SIMD2<Float>(-p.position.y, p.position.x)
            a += tangent * (swirl * 12.0)
            if jitterAmt > 0 {
                a += SIMD2<Float>(.random(in: -1...1), .random(in: -1...1)) * jitterAmt
            }
            p.velocity += a * clampedDt
            p.velocity *= frictionFactor
            // Spin responds to yaw and is damped (previously it never decayed,
            // which kept shards rotating even when the phone was held still).
            p.angularVelocity += swirl * 5.0 * clampedDt
            p.angularVelocity *= frictionFactor

            // Braking zone: once the device is barely moving, aggressively bleed
            // off any remaining momentum so the shards come to rest quickly
            // instead of coasting — the hallmark of holding a real kaleidoscope
            // still.
            if act < 0.12 {
                let brake = powf(0.02, clampedDt)   // ~98% damping per second
                p.velocity *= brake
                p.angularVelocity *= brake
            }

            // Clamp speed for stability.
            let speed = p.velocity.length
            if speed > config.maxSpeed {
                p.velocity *= config.maxSpeed / speed
            }

            // Below a small threshold while nearly idle, snap fully to rest so
            // the pattern is perfectly frozen rather than creeping.
            if act < 0.06 {
                if speed < 0.06 { p.velocity = .zero }
                if abs(p.angularVelocity) < 0.06 { p.angularVelocity = 0 }
            }

            // Integrate position and spin.
            p.position += p.velocity * clampedDt
            p.rotation += p.angularVelocity * clampedDt

            // Circular wall collision with restitution.
            let dist = p.position.length
            let limit = chamberRadius - p.radius * 0.5
            if dist > limit, dist > .ulpOfOne {
                let n = p.position / dist
                p.position = n * limit
                let vn = simd_dot(p.velocity, n)
                if vn > 0 {
                    p.velocity -= n * (vn * (1 + config.restitution))
                    p.angularVelocity += (Float.random(in: -1...1)) * vn * 0.5
                }
            }

            particles[i] = p
        }

        resolveOverlaps()
    }

    /// Cheap pairwise separation so fragments push each other apart, giving the
    /// "packed beads" feeling. O(n²) but n is tiny.
    private func resolveOverlaps() {
        let count = particles.count
        guard count > 1 else { return }
        for i in 0..<(count - 1) {
            for j in (i + 1)..<count {
                var a = particles[i]
                var b = particles[j]
                let delta = b.position - a.position
                let dist = delta.length
                let minDist = (a.radius + b.radius) * 0.6
                guard dist > .ulpOfOne && dist < minDist else { continue }

                let n = delta / dist
                let overlap = (minDist - dist) * 0.5
                a.position -= n * overlap
                b.position += n * overlap

                // Exchange a fraction of velocity along the normal (elastic-ish).
                let relVel = simd_dot(b.velocity - a.velocity, n)
                if relVel < 0 {
                    let impulse = n * relVel * config.restitution
                    a.velocity += impulse
                    b.velocity -= impulse
                }
                particles[i] = a
                particles[j] = b
            }
        }
    }

    // MARK: - GPU hand-off

    /// Folds each fragment into the base symmetry wedge and returns the buffer
    /// the shader consumes. Reuses an internal scratch array.
    func gpuParticles(segments: Float) -> [GPUParticle] {
        let count = min(particles.count, Int(KS_MAX_PARTICLES))
        let seg = (2 * Float.pi) / max(segments, 1)
        for i in 0..<count {
            let p = particles[i]
            gpuScratch[i] = GPUParticle(
                position: Self.fold(p.position, seg: seg),
                color: p.color,
                radius: p.radius,
                rotation: p.rotation,
                refraction: p.refraction,
                seed: p.seed
            )
        }
        return Array(gpuScratch[0..<count])
    }

    /// Scalar smoothstep matching the GLSL/Metal semantics.
    private static func smoothstep(_ edge0: Float, _ edge1: Float, _ x: Float) -> Float {
        let t = ((x - edge0) / (edge1 - edge0)).clamped(to: 0...1)
        return t * t * (3 - 2 * t)
    }

    /// Mirrors a point into the base wedge so it lines up with the GPU fold.
    private static func fold(_ p: SIMD2<Float>, seg: Float) -> SIMD2<Float> {
        let r = p.length
        var a = atan2f(p.y, p.x)
        a -= seg * floorf(a / seg)
        a = abs(a - seg * 0.5)
        return SIMD2<Float>(cos(a), sin(a)) * r
    }
}
