import Foundation

/// Command palette ⌘K (#184) — jmenný prostor pro to, co se v ní ukazuje.
///
/// Není to typ k instanciování, jen střecha nad tvary: `Item` je jeden řádek, `Section` je
/// skupina řádků, `Target` je to, co se stane po `↵`, `Level` je úroveň, ve které paleta stojí
/// (#533), `Stage` to, co se v ní kreslí okolo výsledků, a `Jump` je žádost o odscrollování,
/// kterou vyřídí detail PR. **Pravidla** (co na dotaz sedne, v jakém pořadí a co říká patka)
/// bydlí v `Policy` — viz `App/Policy/CommandPaletteSearch.swift`
/// a `App/Policy/CommandPaletteLevel.swift`.
///
/// **Jmenný prostor, ne prefix v každém názvu**: `Palette` v tomhle repu už znamená barvy okna
/// (`App/Views/Palette.swift`), takže `PaletteItem` by se čtl jako barevný token.
///
/// **Odsud nic neodchází.** Ve výčtu `Action` není nic, co by sahalo na jedinou cestu ven
/// (`App/Publish/`, tvrdá podmínka č. 1).
///
/// **A dotahuje se jediná věc, na jediný pokyn** (#533): otevřené PR repa, do kterého jsem
/// vstoupil `↵`. Psaní v poli **nedotahuje nic** — ani v první úrovni (hledá se v tom, co store
/// má v paměti, a repozitáře leží v cache na disku), ani v druhé (filtruje se dotažený seznam).
/// Je na to test, který po každém úhozu i po každém cíli počítá volání gateway.
enum CommandPalette {}

extension CommandPalette {
    /// Ve které úrovni paleta je (#533).
    ///
    /// **Dvě úrovně, ne dvě palety.** Enter na repu nechá kartu, pole i klávesy na místě a změní
    /// jedině to, v čem se hledá — proto je to stav palety, ne druhý překryv. V poli po tom zůstane
    /// chip s repem, takže je z obrazovky vidět, kde člověk je.
    ///
    /// **Ve store, ne v `@State` karty**, na rozdíl od dotazu a kurzoru: druhá úroveň si nechává
    /// dotažený seznam PR, a ten by se s každým překreslením karty tahal znovu. Zavřením palety se
    /// úroveň **vrací na `top`** — ⌘K je „začínám hledat“, takže se nikdo nemá vracet do repa,
    /// o kterém před minutou zapomněl.
    enum Level: Hashable, Sendable {
        case top
        /// Otevřené pull requesty jednoho repa.
        case repository(RepoID)

        /// Repo, ve kterém paleta stojí. `nil` = první úroveň.
        var repository: RepoID? {
            switch self {
            case .top: nil
            case .repository(let repo): repo
            }
        }
    }

    /// Otevřené pull requesty repa, do kterého paleta vstoupila (#533).
    ///
    /// **Tři stavy, ne pole a `Bool`**: „tahá se“, „je tu tohle“ a „nepovedlo se“ jsou tři různé
    /// věci na obrazovce a prázdné pole by je slilo do jedné — repo bez otevřených PR by vypadalo
    /// stejně jako repo, na které `gh` neodpověděl. Je to tentýž důvod, kvůli kterému `ReviewState`
    /// rozlišuje chybové stavy.
    enum RepositoryPullRequests: Hashable, Sendable {
        case loading
        /// Dotažené **otevřené** PR v pořadí, ve kterém přišly z gateway.
        case loaded([PullRequestSummary])
        /// Věta z `gh`. Prázdno by tvrdilo „repo nemá otevřené PR“, což je něco jiného.
        case failed(String)
    }

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
    ///
    /// **Skupina `Repozitáře` je poslední** (#533, návrh pozn. 59), a je to tatáž úvaha jako
    /// u nálezů, jen z druhé strany: je to **nabídka, kam jít**, ne odpověď na to, co je v okně.
    /// Kdo píše `vault`, hledá nejčastěji něco, co v okně už je.
    ///
    /// **Otevřené PR repa jsou taky skupina, i když je v druhé úrovni sama** (#533). Nadpis nad
    /// nimi říká, kolik jich je a jak jsou řazené, takže bez skupiny by ta věta neměla kde být —
    /// a strop se na ni schválně nevztahuje, viz `Policy.paletteRepositoryResults`.
    enum Group: Hashable, Sendable, CaseIterable {
        case link
        case findings
        case files
        case pullRequests
        case myPullRequests
        case actions
        case repositories
        case repositoryPullRequests

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
            // **Ne „Repozitáře mých organizací“**: které to jsou, dopisuje nadpis za tečkou
            // (`Section.detail`), a to jmenovitě — jedno slovo `organizací` by za sebe muselo
            // ručit, aniž by řeklo, kterých.
            case .repositories: "Repozitáře"
            // **„Otevřené“ je součást tvrzení, ne zkrášlení** (#533): dotahují se jedině otevřené
            // PR, takže `Pull requesty` by nad tím seznamem tvrdilo, že jsou v repu všechny.
            case .repositoryPullRequests: "Otevřené pull requesty"
            }
        }
    }

    /// Odznak u řádku pull requestu v druhé úrovni (#533) — `ve frontě`, nebo `moje`.
    ///
    /// **Skládá se z toho, co store už má**, ne z dalšího dotazu (návrh pozn. 60): „ve frontě“
    /// znamená „je v seznamu ze zdrojů“ a „moje“ rozhoduje `Policy.ownership`. PR, o kterém store
    /// neví nic, odznak nedostane — a to je ta většina, protože druhá úroveň chodí do rep, která
    /// ve zdrojích nejsou.
    ///
    /// Text nese model (jako `PullRequestState.czechLabel`), barvu sází view: `Mark` říká, **co**
    /// ten řádek je, a tohle říká, **co se o něm ví**.
    enum Badge: Hashable, Sendable {
        /// PR je ve zdrojích, tedy ve frontě k review (#4).
        case inQueue
        case mine

        var czechLabel: String {
            switch self {
            case .inQueue: "ve frontě"
            case .mine: "moje"
            }
        }
    }

    /// Jedna položka patky palety — `↵ otevřít`.
    ///
    /// Existuje kvůli tomu, že se patka mění podle **úrovně** (#533): v druhé úrovni `esc` nezavírá,
    /// ale vrací o úroveň zpět, a to se musí dát otestovat výčtem. Rozhoduje `Policy.paletteStage`.
    ///
    /// **Podle úrovně, ne podle vybraného řádku** (návrh, s09link): klávesy jsou vlastnost karty,
    /// takže kdyby text patky závisel na tom, co je zrovna pod kurzorem, musel by se do něj dívat
    /// každý řádek — a patka by se měnila pod rukou při každé šipce.
    struct Hint: Hashable, Sendable, Identifiable {
        let key: String
        let what: String

        var id: String { key }
    }

    /// Co se napíše, když v paletě není vidět ani jeden řádek.
    ///
    /// **Dvě věty, ne jedna**, a druhá je ta cennější: `Na „x“ nic nesedí` říká, že se nenašlo,
    /// kdežto `note` říká **kde se hledalo** — a paleta nechodí na GitHub, takže bez toho by
    /// prázdný výsledek vypadal jako tvrzení, že takový pull request neexistuje.
    ///
    /// **`note` je optional**, protože jsou stavy, ve kterých se nehledalo vůbec: repo bez
    /// otevřených PR není prázdný **výsledek**, je to prázdné **repo**, a věta o tom, v čem se
    /// hledá, by tam byla vytáčka.
    struct EmptyState: Hashable, Sendable {
        let headline: String
        let note: String?
    }

    /// Věta nad seznamem, která říká, že se něco děje nebo nepovedlo (#533).
    ///
    /// **Vlastní typ, ne `String?`**: puntík načítání a červená věta o selhání jsou dvě různé
    /// kresby, a jeden řetězec by z nich udělal jednu.
    enum Notice: Hashable, Sendable {
        case loading(String)
        case failed(String)
    }

    /// Jak paleta vypadá v téhle úrovni (#533) — všechno, co **nezávisí na dotazu**.
    ///
    /// Skládá to `Policy.paletteStage(level:repository:)`, takže se dá projít výčtem. Ve view
    /// nesmí zůstat žádné `if` nad úrovní — jinak by se rozhodnutí „co říká patka“ dalo přečíst
    /// jedině z kresby.
    ///
    /// **Prázdný stav v tom není**, protože závisí na dotazu: skládá ho
    /// `Policy.paletteEmpty(at:query:)` tam, kde je dotaz po ruce (tedy ve view, jako výsledky).
    struct Stage: Hashable, Sendable {
        let level: Level
        /// Chip s repem v poli. `nil` = první úroveň, tedy pole bez chipu.
        let chip: String?
        /// Výzva v prázdném poli.
        let prompt: String
        let hints: [Hint]
        /// `nil` = nic se netahá a nic se nepokazilo.
        let notice: Notice?
        /// Vrací `esc` a `⌫` o úroveň zpět? `false` = `esc` zavírá paletu.
        let goesBack: Bool
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
        /// Vstup do druhé úrovně palety (#533) — otevřené PR toho repa.
        ///
        /// **Cíl jako každý jiný, ne zvláštní cesta:** `↵` v paletě má jednu trasu
        /// (`AppStore.reveal(_:)`), takže i „přepni úroveň“ chodí tudy. Jediné, čím se liší, je
        /// že po něm **paleta zůstane otevřená** — rozhoduje `Policy.paletteClosesAfter(_:)`.
        case repository(RepoID)
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
        /// Repozitář z organizací v nastavení (#533). **Vlastní značka, ne `pullRequest(_:)`**:
        /// řádek nemluví o pull requestu, ale o místu, kam se dá vejít — a stav, který by značka
        /// PR chtěla, u repa neexistuje.
        case repository
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
        /// Odznak za podtitulkem (#533) — `ve frontě` / `moje`. `nil` = o řádku se nic takového
        /// neví, což je většina řádků palety.
        ///
        /// **Vlastní pole, ne slovo v podtitulku**: kreslí se jako kapsle s barvou, takže by se
        /// v řetězci nedalo odlišit od autora vedle sebe — a hledání by v něm shodu zvýrazňovalo.
        let badge: Badge?
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
            badge: Badge? = nil,
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
            self.badge = badge
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
        /// Co se dopíše do nadpisu za tečkou — `keboola, ondrajodas` u repozitářů, `7 · řazeno
        /// podle poslední změny` u otevřených PR repa (#533). `nil` = nadpis je jen jméno skupiny.
        ///
        /// **Skládá to `Policy`, ne view**: je to tvrzení o tom, kde se hledalo a jak je to
        /// seřazené, tedy rozhodnutí — ne kosmetika nadpisu.
        let detail: String?

        var id: Group { group }

        init(group: Group, hits: [Hit], detail: String? = nil) {
            self.group = group
            self.hits = hits
            self.detail = detail
        }
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
