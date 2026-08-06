import SwiftUI

/// Identita hlavního okna. Titulek je zároveň to, čím ho `WindowCentering` pozná mezi
/// `NSApp.windows` — proto konstanta a **žádný druhý literál `"PRism"`**: drží to pravidlo
/// „jeden název všude“ z `CLAUDE.md`.
enum MainWindow {
    static let title = "PRism"
}

@main
struct PRismApp: App {
    /// Žije nad scénami, ne v okně: `Settings` je **vlastní scéna** a ke store uvnitř
    /// hlavního okna by se nedostala.
    @State private var preflight = PreflightModel()
    /// Kvůli `applicationShouldTerminate` — jinak se aplikace ukončí i uprostřed review
    /// a nálezy, které reviewer nahlásil, se ztratí.
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup(MainWindow.title) {
            RootView(model: preflight)
                // Až tady, ne v initu delegáta: store vzniká teprve po preflightu. Čte se
                // při každém dotazu, takže na pořadí nezáleží.
                // `?? 0` není tichý default: bez store neprošel preflight, a než projde,
                // se nemá co spustit. Předává se **uzávěr, ne číslo** — dialog se ptá
                // v okamžiku zavírání, ne v okamžiku, kdy se okno objevilo.
                .onAppear { delegate.runningReviews = { preflight.store?.runningReviews ?? 0 } }
        }
        .defaultSize(width: 1100, height: 700)
        // **Bez tohohle nešlo okno zmenšit na výšku.** Výchozí `.automatic` u `WindowGroup`
        // odvozuje minimum okna z toho, co si obsah přeje — a `List` v bočním panelu si přeje
        // celou výšku svých řádků, takže při dvanácti PR vyšlo minimum vyšší než obrazovka
        // a spodní hranou okna nešlo hýbat. Ověřeno tím, že po skrytí bočního panelu se okno
        // zmenšit dalo.
        //
        // `.contentMinSize` bere **minimum** obsahu, ne jeho přání, a strop nechává otevřený.
        // Vlastní podlaha je proto na `RootView`, ať se okno nedá stáhnout do nesmyslu.
        .windowResizability(.contentMinSize)
        // Položka v menu aplikace, hned pod „O aplikaci PRism“ — tam se „co je nového“
        // hledá. `Window` scéna sama žádnou položku nepřidá, takže bez tohohle by se okno
        // dalo otevřít jedině po aktualizaci, a to je ta menší polovina zadání #127.
        .commands {
            CommandGroup(after: .appInfo) {
                ReleaseNotesMenuItem()
            }
        }

        Settings {
            SettingsScene(preflight: preflight)
        }

        // `Window`, ne `WindowGroup`: novinky jsou jedno okno nad jedněmi daty, takže druhá
        // kopie by jen dovolila mít otevřené dvě různé verze téhož seznamu.
        Window(ReleaseNotesWindow.title, id: ReleaseNotesWindow.id) {
            ReleaseNotesScene(preflight: preflight)
        }
        .defaultSize(width: 900, height: 620)
        .windowResizability(.contentMinSize)
    }
}
