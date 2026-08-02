import SwiftUI

@main
struct PRismApp: App {
    /// Žije nad scénami, ne v okně: `Settings` je **vlastní scéna** a ke store uvnitř
    /// hlavního okna by se nedostala.
    @State private var preflight = PreflightModel()

    var body: some Scene {
        WindowGroup("PRism") {
            RootView(model: preflight)
        }
        .defaultSize(width: 1100, height: 700)

        Settings {
            SettingsScene(preflight: preflight)
        }
    }
}
