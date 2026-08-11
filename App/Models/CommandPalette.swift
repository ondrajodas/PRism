import Foundation

/// Command palette ⌘K (#184) — jmenný prostor pro to, co se v ní ukazuje.
///
/// Není to typ k instanciování, jen střecha nad tvary: `Item` je jeden řádek, `Section` je
/// skupina řádků, `Target` je to, co se stane po `↵`, a `Jump` je žádost o odscrollování,
/// kterou vyřídí detail PR. **Pravidla** (co na dotaz sedne a v jakém pořadí) bydlí v `Policy`
/// — viz `App/Policy/CommandPaletteSearch.swift`.
///
/// **Jmenný prostor, ne prefix v každém názvu**: `Palette` v tomhle repu už znamená barvy okna
/// (`App/Views/Palette.swift`), takže `PaletteItem` by se čtl jako barevný token.
///
/// **Odsud nic neodchází.** Ve výčtu `Action` není nic, co by sahalo na jedinou cestu ven
/// (`App/Publish/`, tvrdá podmínka č. 1), a paleta si nikdy nic nedotahuje — hledá se v tom, co
/// store už v paměti má.
enum CommandPalette {}

extension CommandPalette {
    /// Skupina výsledků.
    ///
    /// **Pořadí případů je pořadí skupin v okně** a je to tvrzení o tom, k čemu tohle okno je:
    /// nálezy první, protože jsou jediná věc, kterou tahle aplikace má a prohlížeč ne. Kdo
    /// pořadí přehodí, mění návrh, ne kreslení.
    enum Group: Hashable, Sendable, CaseIterable {
        case findings
        case files
        case pullRequests
        case actions

        /// Nadpis skupiny, jak ho má návrh (#184).
        var title: String {
            switch self {
            case .findings: "Nálezy"
            case .files: "Soubory v otevřeném PR"
            case .pullRequests: "Pull requesty"
            case .actions: "Akce"
            }
        }
    }

    /// Co se stane po `↵`.
    ///
    /// Payload, ne kreslení — vykonává ho `AppStore.reveal(_:)`. Navigace i akce jsou schválně
    /// v jednom výčtu: paleta je jedno pole na všechno, takže „skoč sem“ a „udělej tohle“ chodí
    /// tou samou cestou.
    enum Target: Hashable, Sendable {
        /// Skok na nález v diffu. `file == nil` je nález bez místa v kódu — v diffu se nemá
        /// kam skočit, takže se otevře tab `Nálezy`, kde je vidět celý.
        case finding(PRIdentifier, file: String?, line: Int?)
        /// Skok na soubor diffu otevřeného PR.
        case file(PRIdentifier, path: String)
        /// Otevření PR jako záložky.
        case pullRequest(PRIdentifier)
        case action(Action)
    }

    /// Akce, které paleta umí vykonat — „akce, ne jen navigace“ ze zadání #184.
    ///
    /// Výčet je krátký schválně a **nic v něm neodesílá na GitHub**: `startReview` pouští
    /// headless session (reviewer je read-only, tvrdá podmínka č. 2), zbytek přepíná to, co je
    /// v okně vidět.
    enum Action: Hashable, Sendable {
        case runReview(PRIdentifier)
        case cancelReview(PRIdentifier)
        /// Přepnutí pohledu na diff — hodnota je ten pohled, který má **nastat**.
        case setDiffLayout(DiffLayout)
        /// Složení nebo rozložení panelu s mým review; hodnota je stav, který má nastat.
        case setReviewPanel(expanded: Bool)
        /// Sekce railu, tedy obsah domácí záložky.
        case openSection(RailSection)
        case refresh
        /// Nastavení. Vykoná ho **okno**, ne store — viz `Effect`.
        case openSettings
    }

    /// Co po vykonání zbývá na okno. `nil` z `AppStore.reveal(_:)` znamená „hotovo ve storu“.
    ///
    /// Existuje kvůli jediné akci: okno nastavení je **vlastní scéna**, otevřít ji umí jedině
    /// view (`openSettings` z environmentu). Store to tedy nemůže udělat sám a nemá si to ani
    /// pamatovat — jen to řekne volajícímu.
    enum Effect: Hashable, Sendable {
        case openSettings
    }

    /// Značka na začátku řádku. Symbol a barvu sází view (`CommandPaletteRowView`), tady je
    /// jen to, **co** ten řádek je — model o `Palette` ani o SF Symbols nic neví.
    enum Mark: Hashable, Sendable {
        case blockingFinding
        case finding
        case pullRequest(PullRequestState)
        case file
        /// Akce si symbol nese, protože každá dělá něco jiného a jeden společný by neřekl nic.
        case action(symbol: String)
    }

    /// Jeden řádek palety.
    struct Item: Identifiable, Hashable, Sendable {
        /// Identita pro `ForEach`. Skládá ji ten, kdo katalog staví (`AppStore+Palette`), a musí
        /// být **jednoznačná v celém katalogu** — dva řádky se stejným `id` by SwiftUI slil.
        let id: String
        let group: Group
        /// Hlavní text. Jen v něm se zvýrazňuje shoda, viz `Hit.highlight`.
        let title: String
        /// Souřadnice pod titulkem — `vault#85 · SecretClient.php:81`, `+18 −6`, `connection#21663`.
        let subtitle: String?
        let mark: Mark
        /// Zkratka, kterou má řádek nakreslenou. **Jen skutečná** — popiska klávesy, která nic
        /// nedělá, je lež o tom, co okno umí (tatáž zásada jako u akcí na dashboardu).
        let shortcut: String?
        /// Kam vede `⌘↵`. `nil` = na GitHubu to nikde není (akce), takže `⌘↵` neudělá nic.
        let url: URL?
        /// Co se prohledává **kromě** titulku a podtitulku: celá cesta souboru, `owner/repo`,
        /// jméno revieweera, synonyma u akcí. Do titulku by se to nevešlo a bez toho by se
        /// nálezy nedaly najít podle repa.
        let keywords: [String]
        let target: Target

        init(
            id: String,
            group: Group,
            title: String,
            subtitle: String? = nil,
            mark: Mark,
            shortcut: String? = nil,
            url: URL? = nil,
            keywords: [String] = [],
            target: Target
        ) {
            self.id = id
            self.group = group
            self.title = title
            self.subtitle = subtitle
            self.mark = mark
            self.shortcut = shortcut
            self.url = url
            self.keywords = keywords
            self.target = target
        }
    }

    /// Řádek, který na dotaz sedl — i s tím, kde se to v titulku potkalo.
    struct Hit: Identifiable, Hashable, Sendable {
        let item: Item
        /// Rozsah v `item.title` ke zvýraznění. `nil` = potkalo se to jinde (podtitulek nebo
        /// klíčové slovo), takže v titulku není co zvýraznit — zvýraznit něco jiného by bylo
        /// tvrzení, že se to potkalo tam.
        let highlight: Range<String.Index>?

        var id: String { item.id }
    }

    /// Skupina výsledků, jak se kreslí.
    struct Section: Identifiable, Hashable, Sendable {
        let group: Group
        let hits: [Hit]

        var id: Group { group }
    }

    /// Žádost o skok do diffu, kterou vyřídí detail PR (#184).
    ///
    /// **Ve store, ne ve view:** rozhodnutí „skoč sem“ padá v paletě nad celým oknem, kdežto
    /// odscrollovat umí jedině detail PR — má kotvy řádků a `ScrollViewProxy`. Nese vlastní
    /// `id`, aby se dal tentýž skok vyžádat dvakrát: `task(id:)` se na shodné hodnotě podruhé
    /// nespustí, takže bez něj by druhé `↵` na tomtéž nálezu neudělalo nic.
    struct Jump: Identifiable, Hashable, Sendable {
        /// Nález se po skoku **zvýrazní**, soubor ne: zvýraznění patří k bublině nálezu, takže
        /// nad souborem by ukazovalo na místo, kde žádný nález není.
        enum Kind: Hashable, Sendable {
            case finding
            case file
        }

        let id = UUID()
        let pullRequest: PRIdentifier
        let file: String
        /// `nil` = nález bez čísla řádku; kotva pak padne na hlavičku souboru.
        let line: Int?
        let kind: Kind
    }
}
