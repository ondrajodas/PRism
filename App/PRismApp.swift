import SwiftUI

@main
struct PRismApp: App {
    /// Žije nad scénami, ne v okně: `Settings` je **vlastní scéna** a ke store uvnitř
    /// hlavního okna by se nedostala.
    @State private var preflight = PreflightModel()
    /// Kvůli `applicationShouldTerminate` — jinak se aplikace ukončí i uprostřed review
    /// a nálezy, které reviewer nahlásil, se ztratí.
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup("PRism") {
            RootView(model: preflight)
                // Až tady, ne v initu delegáta: store vzniká teprve po preflightu. Čte se
                // při každém dotazu, takže na pořadí nezáleží.
                // `?? 0` není tichý default: bez store neprošel preflight, a než projde,
                // se nemá co spustit. Předává se **uzávěr, ne číslo** — dialog se ptá
                // v okamžiku zavírání, ne v okamžiku, kdy se okno objevilo.
                .onAppear { delegate.runningReviews = { preflight.store?.runningReviews ?? 0 } }
        }
        .defaultSize(width: 1100, height: 700)

        Settings {
            SettingsScene(preflight: preflight)
        }
    }
}
