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
                // A totéž u posouzeného nálezu (#113): neuložené odmítnutí se po restartu
                // vrátí a nebylo by z čeho poznat proč.
                if let failure = store.dismissalFailure {
                    notice(failure, icon: "exclamationmark.triangle")
                }
                // Reviewer, který nedostal zadání (#120), doběhne — a vypadá **úplně stejně**
                // jako ten, který ho dostal. Bez tohohle by se z okna nedalo poznat, proč
                // o zadání nemluví.
                if let failure = store.intentFailure {
                    notice(failure, icon: "exclamationmark.triangle")
                }
                // Rozhovor nad PR (#452): otázka i odpověď jsou **zaplacená** práce, takže
                // neuložený rozhovor, o kterém se mlčí, vypadá po restartu jako rozhovor, který
                // nikdy nebyl — a příští otázka za něj zaplatí kontext znovu. Totéž u materiálu,
                // který se nepodařilo uložit: odpověď bez něj vypadá v okně stejně jako s ním.
                if let failure = store.askFailure {
                    notice(failure, icon: "exclamationmark.triangle")
                }
                // Značky `Prošlo` (#500): neuložená značka se po restartu **ztratí**, a to se
                // pozná jedině tím, že se padesátisouborový diff prochází znovu. Nepřečtený
                // soubor je horší ještě o krok — v okně vypadá jako nezaškrtnutý diff, tedy
                // jako tvrzení „tohle jsi nečetl“ nad prací, která na disku je.
                if let failure = store.readMarkFailure {
                    notice(failure, icon: "exclamationmark.triangle")
                }
                // Neuložený vzhled okna (#278) taky ne: zápis selhal, takže se režim
                // **nepřepnul** — a klik do railu, po kterém se nic nestane, vypadá jako rozbitá
                // aplikace.
                if let failure = store.appearanceFailure {
                    notice(failure, icon: "exclamationmark.triangle")
                }
                // Notifikace, které nechodí (#88). Odmítnuté oprávnění aplikaci nepoloží, takže
                // bez tohohle je „nic mi nepřišlo“ k nerozeznání od „nic se nestalo“ — a spravit
                // se to dá jedině v Nastavení systému, kam aplikace nedosáhne. Vlastní ikona:
                // není to rozbitá aplikace, je to vypnutý zvonek.
                if let failure = store.notificationFailure {
                    notice(failure, icon: "bell.slash")
                }
                // Co se nepodařilo s terminálem. Je to tentýž případ jako notifikace: výsledek
                // téhle akce **není v okně vidět**, takže neúspěch vypadá k nerozeznání od toho,
                // že se nekliklo — u #453 proto, že se okno otevírá mimo aplikaci, a od #460
                // proto, že v zásuvce zůstalo všechno tak, jak bylo. Vlastní ikona, ne vykřičník:
                // není to rozbitá aplikace, je to terminál, který někdo musí uklidit (běžící
                // příkaz), nebo přístup, který se povoluje v Nastavení systému.
                if let failure = store.terminalFailure {
                    notice(failure, icon: "terminal")
                }
                // A co se nepodařilo s editorem (#530). Tentýž případ: editor se otevře **mimo
                // okno**, takže neúspěch vypadá k nerozeznání od toho, že se nekliklo. Vlastní
                // ikona, ne vykřičník — není to rozbitá aplikace, je to soubor, který v kopii
                // není, nebo editor, který na stroji chybí.
                if let failure = store.editorFailure {
                    notice(failure, icon: "arrow.up.forward.app")
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
            || store.dismissalFailure != nil
            || store.intentFailure != nil
            || store.appearanceFailure != nil
            || store.askFailure != nil
            || store.readMarkFailure != nil
            || store.notificationFailure != nil
            || store.terminalFailure != nil
            || store.editorFailure != nil
    }

    private func notice(_ text: String, icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(.caption)
            .foregroundStyle(Palette.find)
            .fixedSize(horizontal: false, vertical: true)
    }
}
