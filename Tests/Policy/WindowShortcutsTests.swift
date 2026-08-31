import Foundation
import Testing

@testable import PRism

/// Katalog klávesových zkratek hlavního okna (#441).
///
/// Nejcennější tvrzení je tady **to, které říká, že se něco nestalo**: žádná dvě tlačítka v okně
/// nemají tutéž kombinaci. Kolize se totiž neprojeví chybou ani pádem — vyhraje ta zkratka, která
/// se zaregistrovala později, a ta druhá prostě „nefunguje“ (#151, #184). Bez katalogu se na to
/// nešlo zeptat jinak než grepem přes čtyři soubory.
///
/// Druhé v pořadí je tvrzení o **české klávesnici**. `keyboardShortcut` páruje na znak, takže `⌃1`
/// na české mapě nezabere vůbec — pod tou klávesou je `+`. Že sekce railu mají obě varianty, se
/// v harnessu jinak ověřit nedá: testovací host nedostane aktivaci (změřeno u #392), takže nemá key
/// okno a stisk nemá kam sednout. Testuje se proto katalog; **na klávesnici to zkouší člověk**.
@Suite("Zkratky hlavního okna (#441)")
struct WindowShortcutsTests {
    // MARK: - Kolize

    /// **Tvrzení o tom, co se nesmí stát.** Dvě tlačítka s jednou kombinací znamenají, že jedna
    /// z akcí je nedostupná — a pozná se to jedině tím, že si toho někdo všimne při používání.
    @Test("Žádné dvě tlačítka v okně nemají tutéž kombinaci")
    func noTwoButtonsShareACombination() {
        var seen: [WindowShortcut.Combination: String] = [:]
        for shortcut in Policy.windowShortcuts {
            for combination in shortcut.combinations {
                #expect(
                    seen[combination] == nil,
                    "\(combination.display) chce „\(shortcut.title)“ i „\(seen[combination] ?? "")“"
                )
                seen[combination] = shortcut.title
            }
        }
    }

    /// Počet je **vyjmenovaný, ne „aspoň tolik“** — stejně jako u `SingleWayOutTests`. Nová zkratka
    /// v okně je rozhodnutí, ne přírůstek: má projít úvahou, jestli se s něčím nesrazí a jestli se
    /// nakreslí tam, kde se na ni přijde.
    @Test("Katalog má právě jednadvacet akcí")
    func catalogHasExactlyTwentyOneActions() {
        #expect(Policy.windowShortcutActions.count == 21)
        #expect(Policy.windowShortcuts.count == 21)
    }

    /// Kombinace, které patří systému nebo scéně nastavení, si okno **nesmí vzít**. `⌘W` je zrovna
    /// důvod, proč se záložka zavírá `⌃W`.
    @Test("Systémové kombinace zůstávají volné")
    func systemCombinationsStayFree() {
        let reserved: [WindowShortcut.Combination] = [
            .init(key: .character("w"), modifiers: .command),
            .init(key: .character("q"), modifiers: .command),
            .init(key: .character("m"), modifiers: .command),
            .init(key: .character("h"), modifiers: .command),
            .init(key: .character(","), modifiers: .command),
        ]
        let taken = Set(Policy.windowShortcuts.flatMap(\.combinations))
        for combination in reserved {
            #expect(!taken.contains(combination), "okno si vzalo \(combination.display)")
        }
    }

    // MARK: - Česká klávesnice

    /// Sekce railu má **dvě** kombinace: číslici a znak, který je na téže klávese v české mapě.
    /// Výčet je vyčerpávající přes `RailSection`, takže šestá sekce bez zkratky spadne tady.
    @Test("Každá sekce railu má číslici i českou variantu")
    func railSectionsCarryBothKeyboards() {
        // Znaky pod `1`–`5` na české mapě. Vypsané zvlášť schválně: je to jediné místo, kde je
        // z testu vidět, proč ty druhé kombinace vůbec jsou.
        let czech: [Character: Character] = ["1": "+", "2": "ě", "3": "š", "4": "č", "5": "ř"]

        for section in RailSection.allCases {
            let shortcut = Policy.windowShortcut(.openSection(section))
            #expect(shortcut.combinations.count == 2, "\(section.title) nemá obě varianty")
            guard case .character(let digit) = shortcut.primary.key else {
                Issue.record("\(section.title) nemá pod primární kombinací číslici")
                continue
            }
            #expect(czech[digit] != nil, "\(digit) není klávesa z číselné řady 1–5")
            guard case .character(let letter) = shortcut.alternates.first?.key else {
                Issue.record("\(section.title) nemá českou variantu")
                continue
            }
            #expect(letter == czech[digit])
        }
    }

    /// Alternativa musí mít **stejné modifikátory** jako primární kombinace: je to tentýž hmat na
    /// jiné mapě, ne druhá zkratka. `⌥ě` místo `⌃ě` by znamenalo, že si člověk pamatuje dvě věci.
    @Test("Alternativa se od primární liší jen klávesou")
    func alternatesKeepTheSameModifiers() {
        for shortcut in Policy.windowShortcuts {
            for alternate in shortcut.alternates where alternate.key != shortcut.primary.key {
                #expect(alternate.modifiers == shortcut.primary.modifiers, "\(shortcut.title)")
            }
        }
    }

    /// Číslice zůstává pod stejnou sekcí jako pořadí v railu — `⌃3` má otevřít **třetí** ikonu
    /// shora. Kdyby se to rozešlo, zkratka by fungovala a otevírala něco jiného, než na co se
    /// kouká prst.
    @Test("Číslice sedí na pořadí sekce v railu")
    func digitsFollowRailOrder() {
        for (index, section) in RailSection.allCases.enumerated() {
            let expected = Character("\(index + 1)")
            #expect(Policy.windowShortcut(.openSection(section)).primary.key == .character(expected))
        }
    }

    // MARK: - Zakázané stavy

    /// `⌃W` na domácí záložce **nesmí zavřít nic**. Zavřít poslední otevřené review, na které se
    /// člověk ani nedíval, je horší než zkratka, po které se nestane nic.
    @Test("⌃W zavírá jen otevřený pull request, na domácí záložce nic")
    func closableTabIsOnlyAnOpenPullRequest() {
        let pr = PRIdentifier("keboola/vault#85")!

        #expect(Policy.closableTab(in: .home) == nil)
        #expect(Policy.closableTab(in: .pullRequest(pr)) == pr)
    }

    /// `⌘R` čte **tutéž** podmínku jako tlačítko `⟳` (#442). Dvě kopie by se rozešly potichu:
    /// povolená zkratka nad zakázaným tlačítkem vypadá jako nefunkční tlačítko.
    @Test("⌘R je povolené právě tehdy, když bere klik i tlačítko obnovení")
    func refreshShortcutFollowsTheButton() {
        for isRefreshing in [true, false] {
            let control = Policy.refreshControl(isRefreshing: isRefreshing)
            #expect(control.isEnabled == !isRefreshing)
        }
    }

    /// Modifikátory u `.cancelAction` by se **zahodily potichu** — `Combination.keyboardShortcut`
    /// vrací pojmenovanou roli, ne klávesu s maskou. Katalog je proto psát nesmí.
    @Test("⎋ se v katalogu píše bez modifikátorů")
    func cancelActionCarriesNoModifiers() {
        for shortcut in Policy.windowShortcuts {
            for combination in shortcut.combinations where combination.key == .cancelAction {
                #expect(combination.modifiers.isEmpty, "\(shortcut.title)")
            }
        }
    }

    /// Akce, které visí na **viditelném** tlačítku, nesmí mít alternativu: `View.windowShortcut(_:)`
    /// bere jen primární kombinaci, takže by se ta druhá nikde nezaregistrovala.
    @Test("Akce na viditelném tlačítku nemají alternativu")
    func visibleButtonActionsHaveNoAlternates() {
        for action in [WindowShortcut.Action.fileTree, .runAllReviews, .openDraft] {
            #expect(Policy.windowShortcut(action).alternates.isEmpty)
        }
    }

    // MARK: - Co se kreslí

    /// `⌃⏎` je **druhá klávesa**, ne náhrada — `⌘⏎` musí zůstat, protože je zavedené (#151)
    /// a kreslí se v nápovědě.
    @Test("Potvrzení odeslání zůstává na ⌘⏎ a přibylo ⌃⏎")
    func submissionKeepsCommandReturnAndGainsControlReturn() {
        let shortcut = Policy.windowShortcut(.openSubmission)

        #expect(shortcut.primary == .init(key: .return, modifiers: .command))
        #expect(shortcut.alternates == [.init(key: .return, modifiers: .control)])
        #expect(shortcut.display == "⌘⏎")
    }

    /// Glyfy v pořadí z **návrhu** (`⌘⇧P`, `⌘⌥S` v `docs/navrh.html`), ne v pořadí menu macOS
    /// (`⌃⌥⇧⌘`). Bez pevného pořadí by v jednom okně stálo `⌘⇧P` a `⇧⌘P`.
    @Test("Popiska se skládá v pořadí ⌘⌃⌥⇧")
    func modifierGlyphsFollowTheDesign() {
        let all: ShortcutModifiers = [.shift, .option, .control, .command]

        #expect(all.glyphs == "⌘⌃⌥⇧")
        #expect(ShortcutModifiers().glyphs.isEmpty)
    }

    /// Vyčerpávající výčet toho, co se v okně a v paletě kreslí. Je to jediné místo, kde je vidět
    /// celá mapa kláves pohromadě.
    @Test("Kreslené zkratky jsou ty skutečné")
    func drawnShortcutsMatchTheKeys() {
        let expected: [(WindowShortcut.Action, String)] = [
            (.palette, "⌘K"),
            (.nextTab, "⌃Tab"),
            (.previousTab, "⌃⇧Tab"),
            (.closeTab, "⌃W"),
            (.refresh, "⌘R"),
            (.openSection(.overview), "⌃1"),
            (.openSection(.queue), "⌃2"),
            (.openSection(.mine), "⌃3"),
            (.openSection(.drafts), "⌃4"),
            (.openSection(.activity), "⌃5"),
            (.nextFinding, "⌥↓"),
            (.previousFinding, "⌥↑"),
            (.reviewPanel, "⌘2"),
            (.backFromCommit, "esc"),
            (.openSubmission, "⌘⏎"),
            (.agentPrompt, "⌘⇧P"),
            (.cancelReview, "⌘."),
            (.toggleTerminal, "⌃`"),
            (.fileTree, "⌘1"),
            (.runAllReviews, "⌘⇧R"),
            (.openDraft, "⌘⇧D"),
        ]

        for (action, display) in expected {
            #expect(Policy.windowShortcut(action).display == display)
        }
        #expect(expected.count == Policy.windowShortcutActions.count)
    }

    /// **Kapsli sází monospace systémové písmo a dva glyfy v něm nejsou** — `⇥` (U+21E5)
    /// a `⎋` (U+238B). Změřeno `CTFontGetGlyphsForCharacters` nad
    /// `.AppleSystemUIFontMonospaced-Regular`: `⌘`, `⌃`, `⌥`, `⇧`, `⏎`, `↑` a `↓` v něm **jsou**,
    /// ty dva ne. Text s nimi by se propadl do náhradního písma, tedy do jiné šířky i kresby než
    /// zbytek kapsle — proto se `Tab` a `esc` píšou slovem, jak je aplikace psala i před #441.
    ///
    /// Tvrdí se to nad **výčtem**, ne měřením písma za běhu: `NSFont` v testovacím hostu pod
    /// zátěží vydá přechodně nepoužitelnou metriku (#407), takže sáhnout si sem na písmo znamená
    /// koupit si falešně červený `main`. Měření je v `docs/testovani.md` i s postupem, jak ho
    /// zopakovat.
    @Test("Kreslená zkratka nesahá po glyfu, který písmo kapsle nemá")
    func drawnShortcutsStayInsideTheMonospacedFont() {
        let drawable: Set<Character> = ["⌘", "⌃", "⌥", "⇧", "⏎", "↑", "↓"]

        for shortcut in Policy.windowShortcuts {
            for character in shortcut.display where !character.isASCII {
                #expect(drawable.contains(character), "\(shortcut.display) sahá po \(character)")
            }
        }
    }

    @Test("Nápověda tlačítka má zkratku v závorce")
    func helpCarriesTheShortcutInBrackets() {
        #expect(Policy.shortcutHelp("Obnovit seznam", .refresh) == "Obnovit seznam (⌘R)")
        #expect(Policy.refreshControl(isRefreshing: false).help == "Obnovit seznam (⌘R)")
        // Za běhu dotazu se zkratka **nekreslí**: je zakázaná a tlačítko říká proč.
        #expect(!Policy.refreshControl(isRefreshing: true).help.contains("⌘R"))
    }

    // MARK: - Paleta ⌘K

    /// Paleta kreslí u akce vždycky tu **skutečnou** zkratku. Řádky `refresh`, `openSection(_:)`
    /// a `cancelReview(_:)` v ní byly od #184 bez ní — což do #441 platilo, protože zkratku
    /// neměly.
    @Test("Paleta kreslí u akcí zkratku z katalogu")
    func paletteDrawsCatalogShortcuts() {
        let pr = PRIdentifier("keboola/vault#85")!
        let items = Policy.paletteActions(open: pr, isReviewing: true, section: .queue)
        let shortcuts = Dictionary(
            uniqueKeysWithValues: items.map { ($0.id, $0.shortcut) }
        )

        #expect(shortcuts["action:refresh"] == "⌘R")
        #expect(shortcuts["action:cancel-review"] == "⌘.")
        #expect(shortcuts["action:review-panel"] == "⌘2")
        for (index, section) in RailSection.allCases.enumerated() {
            #expect(shortcuts["action:section-\(section.rawValue)"] == "⌃\(index + 1)")
        }
    }

    /// **Nakreslená zkratka, kterou nikdo neregistruje, je lež o tom, co okno umí.** Jediná
    /// výjimka je `⌘,` — to registruje scéna `Settings`, ne okno.
    @Test("V paletě není nakreslená zkratka mimo katalog")
    func paletteNeverDrawsAnUnknownShortcut() {
        let pr = PRIdentifier("keboola/vault#85")!
        let known = Set(Policy.windowShortcuts.map(\.display)).union(["⌘,"])

        for open in [pr, nil] {
            for item in Policy.paletteActions(open: open, isReviewing: open != nil) {
                guard let shortcut = item.shortcut else { continue }
                #expect(known.contains(shortcut), "\(item.title) kreslí \(shortcut)")
            }
        }
    }

    // MARK: - Stráž nad zdrojáky

    /// Kombinace se v aplikaci píše **na jednom místě** — v katalogu. Ostatní soubory ji dostávají
    /// přes `WindowShortcutButtons` nebo `View.windowShortcut(_:)`.
    ///
    /// Výčet výjimek je **jmenovitý, ne rozsah**: jsou to sheety, vlastní scény, uvítací brána
    /// a překryv palety — tedy věci, které si klávesu berou samy a s oknem se nepotkají. Nový
    /// soubor v tomhle seznamu je rozhodnutí, ne přírůstek.
    ///
    /// Čte se zdroják, protože „odkud se zkratka registruje“ je vlastnost struktury kódu, na kterou
    /// se za běhu zeptat nedá. Komentáře se zahazují stejně jako v grepech z `CLAUDE.md`.
    @Test("Kombinace kláves se píše jen v katalogu a v jeho překladu")
    func keyCombinationsLiveInTheCatalogOnly() throws {
        let allowed: Set<String> = [
            // Překlad katalogu do SwiftUI — jediné místo, kde se `keyboardShortcut` píše nad
            // kombinací z `Policy`.
            "Views/WindowShortcutButtons.swift",
            // Vlastní okna a sheety: `⎋` a `⏎` si berou samy, s oknem se nepotkají.
            "Views/PreflightGateView.swift",
            "Views/RawSessionSheet.swift",
            "Views/AgentPromptSheet.swift",
            "Views/CodeTextSheet.swift",
            "Views/ReviewSubmissionSheet.swift",
            // Potvrzení merge (#465): `⎋` na `Zrušit`, jako u potvrzení review. Tlačítko, které
            // merguje, zkratku **nemá** — poslední klik před nevratnou věcí je klik.
            "Views/MergeSheet.swift",
            // Potvrzení přetlačení větve (#466): totéž a ze stejného důvodu. `⎋` na `Zrušit`,
            // `Přetlačit větev` **bez klávesy** — `Enter` nesmí přepsat historii větve.
            "Views/BranchPushSheet.swift",
            "Views/Settings/SettingsView.swift",
            "Views/Settings/SettingsScene.swift",
            "Views/ReleaseNotes/ReleaseNotesScene.swift",
            // Paleta ⌘K je překryv, který existuje jen otevřený — a zkratky okna, které by se
            // s ní srazily, jsou nad ní zakázané (#184).
            "Views/CommandPaletteView.swift",
            // Composer v tabu `Zeptat se` (#452): `⌘⏎` odesílá otázku a zkratka **okna** je nad
            // tím tabem zakázaná (`Policy.claimsReturnShortcut`), takže se sem klávesa propadne.
            // Je to tentýž vzorec jako u palety o řádek výš — jen se místo překryvu rozhoduje
            // podle toho, který tab je na obrazovce.
            "Views/AskComposer.swift",
        ]

        let found = Set(try sources().filter { $0.code.contains("keyboardShortcut(") }.map(\.path))

        #expect(found == allowed)
    }

    /// Kombinace se **nekreslí literálem** — druhá půlka téže stráže.
    ///
    /// Tuhle třídu našel u #441 až Copilot: tooltip panelu se převedl na katalog, ale kapsle
    /// vedle něj kreslila `⌘2` pořád natvrdo. `keyboardShortcut(` to nechytá, protože kapsle
    /// žádnou zkratku neregistruje — jenom o ní **tvrdí**, a rozejít se s klávesou umí potichu.
    ///
    /// Hledá se `⌘` a `⌥` v řetězcovém literálu, protože ty dva glyfy v aplikaci neznamenají nic
    /// jiného než zkratku. `⌃` a `⇧` ne: první je v `AgentPromptPickList` **šipka rozbalení**
    /// a druhý stojí v próze o `⇧ kliku` v diffu.
    ///
    /// Výčet je **jmenovitý** a každý řádek má svůj důvod — tatáž konstrukce jako `SingleWayOutTests`.
    @Test("Kombinace kláves se nekreslí literálem")
    func drawnCombinationsComeFromTheCatalog() throws {
        let allowed: Set<String> = [
            // Katalog sám — tady ty glyfy vznikají.
            "Policy/WindowShortcuts.swift",
            // `⌘,` registruje scéna `Settings`, ne okno, takže v katalogu kolizí nemá co dělat.
            "Policy/CommandPaletteSearch.swift",
            "Publish/PublishError.swift",
            "Views/ContentView.swift",
            // Paleta ⌘K je překryv, který existuje jen otevřený — `⌘↵` je její vlastní klávesa.
            "Views/CommandPaletteView.swift",
            // `⌥↵` u zakládání labelu (#413) sedí na **poli** v popoveru, ne na okně.
            "Views/LabelPickerView.swift",
            // `⌘⏎` u composeru v tabu `Zeptat se` (#452) — kapsle vedle tlačítka, které tu
            // klávesu doopravdy registruje o pár řádků výš v tomtéž souboru. Kreslí se literálem
            // schválně: kombinace **není** v katalogu okna, protože ji tam registruje tab, ne
            // okno; do katalogu patří jedině to, co se může srazit napříč obrazovkami.
            "Views/AskComposer.swift",
        ]

        var found: Set<String> = []
        for source in try sources() {
            for line in TextLines.content(source.code)
            where line.range(of: "\"[^\"]*[⌘⌥][^\"]*\"", options: .regularExpression) != nil {
                found.insert(source.path)
            }
        }

        #expect(found == allowed)
    }

    // MARK: - Čtení zdrojáků

    private struct Source {
        let path: String
        /// Jen kód — řádky, které začínají `//`, jsou pryč.
        let code: String
    }

    private static let root = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appending(path: "App")

    private func sources() throws -> [Source] {
        let root = Self.root
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else {
            throw SourceUnreadable(path: root.path)
        }
        var files: [Source] = []
        for case let url as URL in walker where url.pathExtension == "swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            files.append(
                Source(
                    path: url.path.replacingOccurrences(of: root.path + "/", with: ""),
                    // `TextLines`, ne `split(separator: "\n")` — pravidlo repa platí i v testech.
                    code: TextLines.content(text)
                        .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
                        .joined(separator: "\n")
                )
            )
        }
        guard !files.isEmpty else { throw SourceUnreadable(path: root.path) }
        return files
    }

    private struct SourceUnreadable: Error { let path: String }
}
