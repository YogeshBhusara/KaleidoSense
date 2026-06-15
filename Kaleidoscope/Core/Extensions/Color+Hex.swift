//
//  Color+Hex.swift
//  KaleidoSense
//
//  Bridges between SwiftUI `Color`, hex strings, and the `SIMD4<Float>` RGBA
//  representation consumed by the Metal shader.
//

import SwiftUI
import simd

extension SIMD4 where Scalar == Float {
    /// Creates an RGBA vector from a hex string such as `"#FF8800"` or `"FF8800AA"`.
    init(hex: String, alpha: Float = 1) {
        var hexString = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if hexString.hasPrefix("#") { hexString.removeFirst() }

        var value: UInt64 = 0
        Scanner(string: hexString).scanHexInt64(&value)

        let r, g, b, a: Float
        if hexString.count == 8 {
            r = Float((value >> 24) & 0xFF) / 255
            g = Float((value >> 16) & 0xFF) / 255
            b = Float((value >> 8) & 0xFF) / 255
            a = Float(value & 0xFF) / 255
        } else {
            r = Float((value >> 16) & 0xFF) / 255
            g = Float((value >> 8) & 0xFF) / 255
            b = Float(value & 0xFF) / 255
            a = alpha
        }
        self.init(r, g, b, a)
    }

    var color: Color {
        Color(.sRGB, red: Double(x), green: Double(y), blue: Double(z), opacity: Double(w))
    }
}
