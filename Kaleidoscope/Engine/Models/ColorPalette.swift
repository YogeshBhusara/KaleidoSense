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
        background: SIMD4(hex: "#05060E"),
        a: SIMD4(hex: "#36E2C2"),
        b: SIMD4(hex: "#5B8CFF"),
        c: SIMD4(hex: "#C66BFF"),
        fragmentColors: [
            SIMD4(hex: "#36E2C2"), SIMD4(hex: "#5B8CFF"),
            SIMD4(hex: "#C66BFF"), SIMD4(hex: "#7CF7E6"),
            SIMD4(hex: "#9B7BFF")
        ]
    )

    static let crystal = ColorPalette(
        id: "crystal",
        name: "Crystal",
        background: SIMD4(hex: "#070A12"),
        a: SIMD4(hex: "#Bfe9ff"),
        b: SIMD4(hex: "#7FD3FF"),
        c: SIMD4(hex: "#E8F6FF"),
        fragmentColors: [
            SIMD4(hex: "#E8F6FF"), SIMD4(hex: "#9FE0FF"),
            SIMD4(hex: "#C7B9FF"), SIMD4(hex: "#FFFFFF"),
            SIMD4(hex: "#7FD3FF")
        ]
    )

    static let cosmos = ColorPalette(
        id: "cosmos",
        name: "Cosmos",
        background: SIMD4(hex: "#02030A"),
        a: SIMD4(hex: "#3A2C8F"),
        b: SIMD4(hex: "#E85CC0"),
        c: SIMD4(hex: "#FFD36E"),
        fragmentColors: [
            SIMD4(hex: "#FFD36E"), SIMD4(hex: "#E85CC0"),
            SIMD4(hex: "#7A5CFF"), SIMD4(hex: "#FF8A5C"),
            SIMD4(hex: "#FFFFFF")
        ]
    )

    static let neon = ColorPalette(
        id: "neon",
        name: "Neon",
        background: SIMD4(hex: "#02040A"),
        a: SIMD4(hex: "#00FFD1"),
        b: SIMD4(hex: "#FF2EC4"),
        c: SIMD4(hex: "#3DDBFF"),
        fragmentColors: [
            SIMD4(hex: "#00FFD1"), SIMD4(hex: "#FF2EC4"),
            SIMD4(hex: "#3DDBFF"), SIMD4(hex: "#B6FF3D"),
            SIMD4(hex: "#FF6B3D")
        ]
    )

    static let liquid = ColorPalette(
        id: "liquid",
        name: "Liquid Glass",
        background: SIMD4(hex: "#0A0E14"),
        a: SIMD4(hex: "#9FB4C9"),
        b: SIMD4(hex: "#C9D6E3"),
        c: SIMD4(hex: "#76E0D0"),
        fragmentColors: [
            SIMD4(hex: "#C9D6E3"), SIMD4(hex: "#9FB4C9"),
            SIMD4(hex: "#76E0D0"), SIMD4(hex: "#E3EAF2"),
            SIMD4(hex: "#A7C7E7")
        ]
    )

    static let ember = ColorPalette(
        id: "ember",
        name: "Ember",
        background: SIMD4(hex: "#0C0603"),
        a: SIMD4(hex: "#FF7A18"),
        b: SIMD4(hex: "#FFB347"),
        c: SIMD4(hex: "#FF3D6E"),
        fragmentColors: [
            SIMD4(hex: "#FF7A18"), SIMD4(hex: "#FFB347"),
            SIMD4(hex: "#FF3D6E"), SIMD4(hex: "#FFD98A"),
            SIMD4(hex: "#C9442E")
        ]
    )

    static let all: [ColorPalette] = [aurora, crystal, cosmos, neon, liquid, ember]
}
