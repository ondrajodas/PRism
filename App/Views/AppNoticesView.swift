import SwiftUI

/// Hlášky ve stavovém řádku: co je špatně a co se kvůli tomu neděje.
///
/// **Levá strana `StatusBarView`, ne vlastní pruh** (#31). Do #72 to byl `safeAreaInset`
/// uvnitř bočního panelu a mělo to dvě chyby, které spolu souvisely: obsah okna vycházel
/// o výšku tohohle pruhu **vyšší než okno** a spodní hrana ho v obou sloupcích odřízla
/// (změřeno přes accessibility: okno 874 pt, obsah 904), a tatáž mašinerie
/// (`invalidateSafeAreaInsets` uvnitř `updateConstraints` split view) stojí v crash reportu
/// z 2026-08-03. Pak z toho byl vlastní pruh přes celé okno a od #31 je součástí stavového
/// řádku — dva pruhy na tytéž hlášky by znamenaly, že se jeden z nich přestane plnit.
///
/// **Když není co říct, nekreslí se vůbec** — pruh drží stavový řádek a puntíky v něm, takže
/// prázdné hlášky nemají co vyhradit. Pozadí ani odsazení si proto nedělá samo.
struct AppNoticesView: View {
    let store: AppStore

    var body: some View {
        if hasNotices {
            VStack(alignment: .leading, spacing: 4) {
                // Rozbitá konfigurace nesmí projít tiše — jinak uživatel hledá, proč mu
                // nastavení nefunguje, a aplikace mezitím běží na výchozích hodnotách.
                if let failure = store.configurationFailure {
                    notice(failure, icon: "exclamationmark.triangle")
                }
                // Pozastavený automat se **musí** ukázat. Bez toho vypadá jako rozbitý: PR
                // přibývají, nic se nespouští a proč se nedá zjistit odnikud.
                // Nula v konfiguraci znamená **vypnuto**, ne vyčerpáno. „Vyčerpaný limit (0)“
                // by tvrdil, že se něco spotřebovalo, a poslal by hledat, co.
                if store.isAutomaticStopped {
                    notice(automaticPausedText, icon: "pause.circle")
                }
                // Rozbitý soubor s nálezy znamená, že se nějaké ztratily — a ztracený nález
                // se nesmí tvářit jako „review neběželo“.
                if store.unreadableReviewFiles > 0 {
                    notice(
                        "\(store.unreadableReviewFiles) uložených nálezů se nepodařilo přečíst.",
                        icon: "exclamationmark.triangle"
                    )
                }
                // A o důvod víc u rozdělaného review: nález se dá dostat zpátky dalším během,
                // ručně psaný text ne.
                if store.unreadableDraftFiles > 0 {
                    notice(
                        "\(store.unreadableDraftFiles) rozdělaných review se nepodařilo přečíst.",
                        icon: "exclamationmark.triangle"
                    )
                }
                // Neuložené review se nesmí tvářit jako uložené — po restartu by bylo pryč.
                if let failure = store.draftFailure {
                    notice(failure, icon: "exclamationmark.triangle")
                }
            }
        }
    }

    private var automaticPausedText: String {
        let limit = store.configuration.global.autoRunsPerDay
        return limit > 0
            ? "Automatické review pozastavené — vyčerpaný denní limit (\(limit)). Ručně jde dál."
            : "Automatické review je vypnuté (denní limit 0). Ručně jde dál."
    }

    private var hasNotices: Bool {
        store.configurationFailure != nil
            || store.isAutomaticStopped
            || store.unreadableReviewFiles > 0
            || store.unreadableDraftFiles > 0
            || store.draftFailure != nil
    }

    private func notice(_ text: String, icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(.caption)
            .foregroundStyle(.orange)
            .fixedSize(horizontal: false, vertical: true)
    }
}
