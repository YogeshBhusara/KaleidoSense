//
//  SymmetryMode.swift
//  KaleidoSense
//
//  The selectable mirror-symmetry counts. The raw value is the number of
//  segments fed directly to the GPU fold.
//

import Foundation

enum SymmetryMode: Int, CaseIterable, Identifiable, Sendable {
    case six = 6
    case eight = 8
    case twelve = 12
    case sixteen = 16

    var id: Int { rawValue }

    /// Number of dihedral segments passed to the shader.
    var segments: Float { Float(rawValue) }

    var title: String { "\(rawValue)" }

    var accessibilityLabel: String { "\(rawValue) segment symmetry" }

    var next: SymmetryMode {
        let all = SymmetryMode.allCases
        let idx = all.firstIndex(of: self) ?? 0
        return all[(idx + 1) % all.count]
    }
}
