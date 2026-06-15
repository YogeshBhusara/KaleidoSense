//
//  KaleidoscopeMode.swift
//  KaleidoSense
//
//  A mode bundles together everything that gives a preset its character:
//  palette, particle look, physics feel, post-processing effects, the default
//  symmetry, and the procedural-audio profile.
//

import SwiftUI
import simd

// MARK: - Sub-configs

/// Controls how individual glass fragments are spawned and animated.
struct ParticleConfig: Sendable {
    var count: Int
    var minRadius: Float
    var maxRadius: Float
    var refraction: Float          // 0...1 shimmer strength
    var spin: Float                // base angular velocity magnitude
    var alpha: Float               // fragment opacity
}

/// Lightweight particle-physics tuning for the chamber.
struct PhysicsConfig: Sendable {
    var gravityScale: Float        // how strongly device gravity pulls fragments
    var friction: Float            // velocity damping per second (0...1)
    var restitution: Float         // wall bounce energy retention (0...1)
    var jitter: Float              // brownian-ish energy from shaking
    var maxSpeed: Float
}

/// Post-processing effect intensities passed straight to the shader.
struct EffectConfig: Sendable {
    var bloom: Float
    var chromaticAberration: Float
    var lensDistortion: Float
    var glow: Float
    var refraction: Float
    var vignette: Float
}

/// High-level character of the procedural audio for a mode.
struct AudioProfile: Sendable {
    var baseFrequency: Float       // root of the chime scale (Hz)
    var brightness: Float          // 0...1 high-partial content
    var chimeDensity: Float        // events per unit of motion
    var rollLevel: Float           // background rolling/noise bed level
    var decay: Float               // chime envelope decay (seconds)
}

// MARK: - Mode

enum KaleidoscopeMode: Int, CaseIterable, Identifiable, Sendable {
    case classic = 0
    case crystalDreams
    case cosmicGalaxy
    case neonPrism
    case liquidGlass
    case mandala

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .classic:       return "Classic"
        case .crystalDreams: return "Crystal Dreams"
        case .cosmicGalaxy:  return "Cosmic Galaxy"
        case .neonPrism:     return "Neon Prism"
        case .liquidGlass:   return "Liquid Glass"
        case .mandala:       return "Mandala"
        }
    }

    var symbol: String {
        switch self {
        case .classic:       return "circle.hexagongrid.fill"
        case .crystalDreams: return "snowflake"
        case .cosmicGalaxy:  return "sparkles"
        case .neonPrism:     return "triangle.fill"
        case .liquidGlass:   return "drop.fill"
        case .mandala:       return "asterisk"
        }
    }

    var palette: ColorPalette {
        switch self {
        case .classic:       return .aurora
        case .crystalDreams: return .crystal
        case .cosmicGalaxy:  return .cosmos
        case .neonPrism:     return .neon
        case .liquidGlass:   return .liquid
        case .mandala:       return .ember
        }
    }

    var defaultSymmetry: SymmetryMode {
        switch self {
        case .classic:       return .six
        case .crystalDreams: return .twelve
        case .cosmicGalaxy:  return .eight
        case .neonPrism:     return .eight
        case .liquidGlass:   return .six
        case .mandala:       return .sixteen
        }
    }

    var particleConfig: ParticleConfig {
        switch self {
        case .classic:
            return .init(count: 40, minRadius: 0.05, maxRadius: 0.16, refraction: 0.6, spin: 0.4, alpha: 0.92)
        case .crystalDreams:
            return .init(count: 48, minRadius: 0.04, maxRadius: 0.13, refraction: 0.95, spin: 0.25, alpha: 0.85)
        case .cosmicGalaxy:
            return .init(count: 56, minRadius: 0.02, maxRadius: 0.10, refraction: 0.7, spin: 0.6, alpha: 0.95)
        case .neonPrism:
            return .init(count: 36, minRadius: 0.05, maxRadius: 0.15, refraction: 0.5, spin: 0.5, alpha: 1.0)
        case .liquidGlass:
            return .init(count: 30, minRadius: 0.08, maxRadius: 0.22, refraction: 0.9, spin: 0.15, alpha: 0.7)
        case .mandala:
            return .init(count: 52, minRadius: 0.03, maxRadius: 0.12, refraction: 0.65, spin: 0.35, alpha: 0.95)
        }
    }

    var physicsConfig: PhysicsConfig {
        switch self {
        case .classic:
            return .init(gravityScale: 1.0, friction: 0.6, restitution: 0.55, jitter: 1.0, maxSpeed: 2.2)
        case .crystalDreams:
            return .init(gravityScale: 0.5, friction: 0.8, restitution: 0.4, jitter: 0.6, maxSpeed: 1.6)
        case .cosmicGalaxy:
            return .init(gravityScale: 0.25, friction: 0.35, restitution: 0.7, jitter: 1.3, maxSpeed: 2.6)
        case .neonPrism:
            return .init(gravityScale: 1.2, friction: 0.5, restitution: 0.8, jitter: 1.1, maxSpeed: 2.8)
        case .liquidGlass:
            return .init(gravityScale: 0.8, friction: 0.92, restitution: 0.25, jitter: 0.4, maxSpeed: 1.2)
        case .mandala:
            return .init(gravityScale: 0.15, friction: 0.7, restitution: 0.5, jitter: 0.7, maxSpeed: 1.8)
        }
    }

    var effectConfig: EffectConfig {
        switch self {
        case .classic:
            return .init(bloom: 0.7, chromaticAberration: 0.5, lensDistortion: 0.5, glow: 0.5, refraction: 1.0, vignette: 0.6)
        case .crystalDreams:
            return .init(bloom: 0.9, chromaticAberration: 0.7, lensDistortion: 0.35, glow: 0.7, refraction: 1.3, vignette: 0.5)
        case .cosmicGalaxy:
            return .init(bloom: 1.1, chromaticAberration: 0.6, lensDistortion: 0.6, glow: 0.9, refraction: 1.1, vignette: 0.75)
        case .neonPrism:
            return .init(bloom: 1.0, chromaticAberration: 0.9, lensDistortion: 0.4, glow: 1.0, refraction: 0.9, vignette: 0.55)
        case .liquidGlass:
            return .init(bloom: 0.6, chromaticAberration: 0.45, lensDistortion: 0.7, glow: 0.5, refraction: 1.4, vignette: 0.5)
        case .mandala:
            return .init(bloom: 0.8, chromaticAberration: 0.4, lensDistortion: 0.3, glow: 0.7, refraction: 1.0, vignette: 0.65)
        }
    }

    var audioProfile: AudioProfile {
        switch self {
        case .classic:
            return .init(baseFrequency: 523.25, brightness: 0.6, chimeDensity: 1.0, rollLevel: 0.5, decay: 0.9)
        case .crystalDreams:
            return .init(baseFrequency: 783.99, brightness: 0.9, chimeDensity: 1.2, rollLevel: 0.3, decay: 1.4)
        case .cosmicGalaxy:
            return .init(baseFrequency: 392.00, brightness: 0.7, chimeDensity: 0.8, rollLevel: 0.6, decay: 1.8)
        case .neonPrism:
            return .init(baseFrequency: 659.25, brightness: 1.0, chimeDensity: 1.4, rollLevel: 0.4, decay: 0.6)
        case .liquidGlass:
            return .init(baseFrequency: 329.63, brightness: 0.4, chimeDensity: 0.6, rollLevel: 0.7, decay: 2.0)
        case .mandala:
            return .init(baseFrequency: 440.00, brightness: 0.65, chimeDensity: 1.0, rollLevel: 0.45, decay: 1.2)
        }
    }
}
