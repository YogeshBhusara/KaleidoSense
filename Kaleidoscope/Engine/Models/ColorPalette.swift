//
//  ColorPalette.swift
//  KaleidoSense
//
//  A palette describes the chamber background and the tints used both for the
//  procedural stained-glass background and for spawning glass fragments.
//

import SwiftUI
import simd

struct ColorPalette: Identifiable, Sendable, Hashable {
    let id: String
    let name: String
    let background: SIMD4<Float>
    let a: SIMD4<Float>
    let b: SIMD4<Float>
    let c: SIMD4<Float>
    /// Discrete colors used to tint individual particles.
    let fragmentColors: [SIMD4<Float>]

    func randomFragmentColor() -> SIMD4<Float> {
        fragmentColors.randomElement() ?? a
    }

    var swatch: [Color] { [a.color, b.color, c.color] }

    static func == (lhs: ColorPalette, rhs: ColorPalette) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

extension ColorPalette {
    static let aurora = ColorPalette(
        id: "aurora",
        name: "Aurora",
        background: SIMD4(hex: "#04050C"),
        a: SIMD4(hex: "#1EE4C2"),
        b: SIMD4(hex: "#4E7CFF"),
        c: SIMD4(hex: "#D24BFF"),
        fragmentColors: [
            SIMD4(hex: "#1EE4C2"), SIMD4(hex: "#4E7CFF"),
            SIMD4(hex: "#D24BFF"), SIMD4(hex: "#FFE56A"),
            SIMD4(hex: "#FF4E8A"), SIMD4(hex: "#F4FBFF")
        ]
    )

    static let crystal = ColorPalette(
        id: "crystal",
        name: "Crystal",
        background: SIMD4(hex: "#05080F"),
        a: SIMD4(hex: "#D7F4FF"),
        b: SIMD4(hex: "#6ECFFF"),
        c: SIMD4(hex: "#FFFFFF"),
        fragmentColors: [
            SIMD4(hex: "#FFFFFF"), SIMD4(hex: "#B8ECFF"),
            SIMD4(hex: "#C9B8FF"), SIMD4(hex: "#7AD8FF"),
            SIMD4(hex: "#E8F7FF"), SIMD4(hex: "#F2D4FF")
        ]
    )

    static let cosmos = ColorPalette(
        id: "cosmos",
        name: "Cosmos",
        background: SIMD4(hex: "#02030A"),
        a: SIMD4(hex: "#5B3DFF"),
        b: SIMD4(hex: "#FF4CC4"),
        c: SIMD4(hex: "#FFD24A"),
        fragmentColors: [
            SIMD4(hex: "#FFD24A"), SIMD4(hex: "#FF4CC4"),
            SIMD4(hex: "#6A4CFF"), SIMD4(hex: "#FF7A4A"),
            SIMD4(hex: "#FFFFFF"), SIMD4(hex: "#3D9BFF")
        ]
    )

    static let neon = ColorPalette(
        id: "neon",
        name: "Neon",
        background: SIMD4(hex: "#010308"),
        a: SIMD4(hex: "#00FFD8"),
        b: SIMD4(hex: "#FF2EC8"),
        c: SIMD4(hex: "#2EE0FF"),
        fragmentColors: [
            SIMD4(hex: "#00FFD8"), SIMD4(hex: "#FF2EC8"),
            SIMD4(hex: "#2EE0FF"), SIMD4(hex: "#C6FF2E"),
            SIMD4(hex: "#FF6A2E"), SIMD4(hex: "#FFFFFF")
        ]
    )

    static let liquid = ColorPalette(
        id: "liquid",
        name: "Liquid Glass",
        background: SIMD4(hex: "#070B12"),
        a: SIMD4(hex: "#A8C4DA"),
        b: SIMD4(hex: "#E4EEF6"),
        c: SIMD4(hex: "#5FE6D4"),
        fragmentColors: [
            SIMD4(hex: "#E4EEF6"), SIMD4(hex: "#A8C4DA"),
            SIMD4(hex: "#5FE6D4"), SIMD4(hex: "#FFFFFF"),
            SIMD4(hex: "#7BB7E8"), SIMD4(hex: "#C9F4EC")
        ]
    )

    static let ember = ColorPalette(
        id: "ember",
        name: "Ember",
        background: SIMD4(hex: "#0A0402"),
        a: SIMD4(hex: "#FF6A12"),
        b: SIMD4(hex: "#FFC247"),
        c: SIMD4(hex: "#FF2E6A"),
        fragmentColors: [
            SIMD4(hex: "#FF6A12"), SIMD4(hex: "#FFC247"),
            SIMD4(hex: "#FF2E6A"), SIMD4(hex: "#FFE08A"),
            SIMD4(hex: "#FFFFFF"), SIMD4(hex: "#C12E1E")
        ]
    )

    static let all: [ColorPalette] = [aurora, crystal, cosmos, neon, liquid, ember]
}
