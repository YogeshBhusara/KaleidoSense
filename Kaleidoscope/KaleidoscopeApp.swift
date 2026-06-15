//
//  KaleidoscopeApp.swift
//  KaleidoSense
//
//  App entry point. A single immersive scene hosts the kaleidoscope.
//

import SwiftUI

@main
struct KaleidoscopeApp: App {
    var body: some Scene {
        WindowGroup {
            KaleidoscopeScreen()
                .preferredColorScheme(.dark)
        }
    }
}
