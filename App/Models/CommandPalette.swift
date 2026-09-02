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
    ///
    /// **Vlastní PR mají vlastní skupinu, ne odznak v cizí** (#336), a je to kvůli stropu:
    /// `Policy.paletteGroupLimit` platí **na skupinu**, takže ve společné skupině by při dvaceti
    /// cizích PR to moje nemuselo vyjít vůbec. Odznak u řádku ten problém neřeší, jen ho schová.
    /// Stojí **za** cizími: cizí PR jsou to, na co se čeká.
    enum Group: Hashable, Sendable, CaseIterable {
        case link
        case findings
        case files
        case pullRequests
        case myPullRequests
        case actions

        /// Nadpis skupiny, jak ho má návrh (#184, sekce 09 od #336 a od #531).
        var title: String {
            switch self {
            // **První, a je to výjimka z pravidla nad výčtem** (#531): nálezy jsou první proto,
            // že jsou to nejcennější data v okně, kdežto odkaz je první proto, že se v tu chvíli
            // **na nic jiného neptám** — vložená adresa PR není hledání, je to příkaz. Skupina se
            // navíc objeví jedině tehdy, když dotaz je adresa; nad běžným hledáním tam není.
            case .link: "Odkaz"
            case .findings: "Nálezy"
            case .files: "Soubory v otevřeném PR"
            // **Ne jen „Pull requesty“** (#336): se dvěma skupinami musí první říct, čeho se
            // týká, jinak vypadá `Moje PR` jako řádky, které do té první nepatří omylem.
            case .pullRequests: "Pull requesty k review"
            case .myPullRequests: "Moje PR"
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
        /// Vložený odkaz na PR (#531). **Vlastní značka, ne `pullRequest(_:)`**: o stavu toho PR
        /// se v tu chvíli neví nic — dotáhne se, až se záložka otevře —, takže by se musel
        /// vymyslet, a `otevřený` u zavřeného PR je lež v tom nejtišším možném místě.
        case link
        /// Akce si symbol nese, protože každá dělá něco jiného a jeden společný by neřekl nic.
        case action(symbol: String)
    }

    /// Jeden řádek palety.
    struct Item: Identifiable, Hashable, Sendable {
        /// Identita pro `ForEach`. Skládá ji ten, kdo katalog staví (`AppStore+Palette`), a musí
        /// být **jednoznačná v celém katalogu** — dva řádky se stejným `id` by SwiftUI slil.
        let id: String
        let group: Group
        /// Hlavní text.
        let title: String
        /// Souřadnice pod titulkem — `vault#85 · SecretClient.php:81`, `+18 −6`,
        /// `connection#21663 · sykora-ji`. Hledá se v něm stejně jako v titulku (jen za nižší
        /// váhu) a shoda se v něm **zvýrazňuje**: bydlí tady repo a autor, takže bez zvýraznění
        /// by u dotazu na jméno nebylo z řádku poznat, proč vyšel.
        let subtitle: String?
        let mark: Mark
        /// Zkratka, kterou má řádek nakreslenou. **Jen skutečná** — popiska klávesy, která nic
        /// nedělá, je lež o tom, co okno umí (tatáž zásada jako u akcí na dashboardu).
        let shortcut: String?
        /// Kam vede `⌘↵`. `nil` = na GitHubu to nikde není (akce), takže `⌘↵` neudělá nic.
        let url: URL?
        /// Co se prohledává **kromě** titulku a podtitulku: celá cesta souboru, `owner/repo`,
        /// jméno revieweera, synonyma u akcí. Nikde se to nekreslí, takže shoda v klíčovém slově
        /// se nedá zvýraznit — proto váží nejmíň a patří sem jen to, co je **nadmnožinou** něčeho
        /// viditelného (celá cesta vs. jméno souboru, `owner/repo` vs. `repo#85`) nebo synonymum
        /// titulku. Co má samo rozhodovat o tom, jestli řádek vyjde, patří do podtitulku.
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

    /// Řádek, který na dotaz sedl — i s tím, kde se to potkalo.
    ///
    /// Dva rozsahy, ne jeden: zvýrazňuje se **v tom textu, ve kterém se to doopravdy potkalo**.
    /// Zvýraznit v titulku shodu z podtitulku by bylo tvrzení, že se to potkalo tam, a nezvýraznit
    /// ji vůbec by z řádku udělalo výsledek, u kterého není poznat, proč vyšel.
    struct Hit: Identifiable, Hashable, Sendable {
        let item: Item
        /// Rozsah v `item.title`. `nil` = v titulku se nepotkalo nic.
        let titleHighlight: Range<String.Index>?
        /// Rozsah v `item.subtitle`. `nil` = v podtitulku se nepotkalo nic (nebo tam žádný není).
        let subtitleHighlight: Range<String.Index>?

        var id: String { item.id }

        init(
            item: Item,
            titleHighlight: Range<String.Index>? = nil,
            subtitleHighlight: Range<String.Index>? = nil
        ) {
            self.item = item
            self.titleHighlight = titleHighlight
            self.subtitleHighlight = subtitleHighlight
        }
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
