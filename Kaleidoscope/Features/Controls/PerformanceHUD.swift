//
//  PerformanceHUD.swift
//  KaleidoSense
//
//  Minimal on-screen instrumentation: smoothed FPS, mean frame time and the
//  worst frame in the last window. Useful while profiling on-device.
//

import SwiftUI

struct PerformanceHUD: View {
    let monitor: PerformanceMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(String(format: "%.0f FPS", monitor.fps))
                .foregroundStyle(color(for: monitor.fps))
            Text(String(format: "%.2f ms", monitor.frameTimeMS))
            Text(String(format: "max %.2f ms", monitor.worstFrameMS))
                .foregroundStyle(Theme.onGlassDim)
        }
        .font(.system(size: 11, weight: .semibold, design: .monospaced))
        .foregroundStyle(Theme.onGlass)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.black.opacity(0.45))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Performance \(Int(monitor.fps)) frames per second"))
    }

    private func color(for fps: Double) -> Color {
        switch fps {
        case 100...: return .green
        case 55...:  return .yellow
        default:     return .red
        }
    }
}
