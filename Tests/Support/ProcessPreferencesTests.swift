import Foundation
import Testing

@testable import PRism

/// **Doména `UserDefaults` procesu není naše, takže se do ní nepíše ani nečte** (#411).
///
/// Do #411 měl testovací host bundle ID **hlavní instance**: slotová přípona vznikala teprve
/// v `bin/run.sh`, takže `xcodebuild test` běžel jako `com.ondrajodas.prism` a všechno, co
/// v testu prošlo `@AppStorage` nebo `UserDefaults.standard`, **zapisovalo do nastavení, které
/// uživatel doopravdy používá**. Naměřené to je od #327, kdy tam po regresním experimentu zůstala
/// uložená velikost sheetu — a prosakovalo to i naopak, protože test pak čte, co si v aplikaci
/// nastavil člověk.
///
/// **Řeší to `PRISM_SLOT` v projektu, ne vrstva v kódu**, a tenhle soubor je ta kontrola.
/// Rozhodnutí i zamítnuté cesty jsou v `docs/testovani.md`, sekce *Globální stav procesu se
/// v testech neměří*; podstatné pro čtení testů níž je jen tohle:
///
/// - výchozí hodnota `PRISM_SLOT` v `project.pbxproj` je `.testhost`, takže build, který si
///   identitu nevyžádal, **není aplikace** — `xcodebuild test` dá hostitele
///   `com.ondrajodas.prism.testhost`;
/// - `bin/run.sh` tu hodnotu předává **vždycky, i prázdnou**, takže hlavní instance zůstává
///   `com.ondrajodas.prism` a slot `com.ondrajodas.prism.<slot>`.
///
/// Zbývají dvě věci, které tím vyřešené **nejsou** a hlídají se tady: doména hostitele je pořád
/// jedna pro souběžné běhy tří slotů (takže se do ní nepíše z testů), a jméno vlastní suity musí
/// být unikátní na běh (`ScratchDefaults`).
///
/// Je to tatáž konstrukce jako `GlobalAppearanceTests`, `SingleWayOutTests` a `GraphSiteWiringTests`
/// — „kdo smí sáhnout na doménu procesu“ je vlastnost struktury kódu, na kterou se za běhu zeptat
/// nedá. Walker nad zdrojáky je proto i tady vlastní, stejně jako u těch tří.
@Suite("Předvolby procesu (#411)")
struct ProcessPreferencesTests {
    private static let repository = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    /// Tenhle soubor si musí sám sebe odečíst: hledané řetězce v něm stojí jako literály a `.standard`
    /// se z něj **čte schválně** — je to jediné místo, které tvrdí, že v ní nic z testů neleží.
    private static let guardFile = "Support/ProcessPreferencesTests.swift"

    // MARK: - Hostitel

    /// **Hostitel není aplikace.** Kdyby se tohle rozbilo (třeba smazáním `PRISM_SLOT` z projektu),
    /// vrátí se celá ta třída naráz — a potichu, protože zápis do nastavení uživatele nikde
    /// nespadne. Proto je to tvrzení jednou větou a nahoře.
    @Test("Testovací host neběží v doméně aplikace")
    func theHostIsNotTheApplication() {
        #expect(
            Bundle.main.bundleIdentifier != "com.ondrajodas.prism",
            """
            Testovací host má bundle ID hlavní instance, takže UserDefaults.standard je nastavení, \
            které uživatel používá. Zkontroluj výchozí PRISM_SLOT v project.pbxproj.
            """
        )
    }

    // MARK: - Vlastní suita

    @Test("Vlastní suita má jméno na jeden běh")
    func scratchDefaultsGetAFreshNameEveryTime() throws {
        let first = try ScratchDefaults("processPreferences")
        let second = try ScratchDefaults("processPreferences")
        defer {
            first.remove()
            second.remove()
        }

        #expect(first.name != second.name)
        #expect(first.name.hasPrefix("cz.prism.tests.processPreferences."))
        #expect(second.name.hasPrefix("cz.prism.tests.processPreferences."))
    }

    /// Zápis do vlastní suity **nesmí skončit v doméně procesu**. Klíč je jednorázový, takže
    /// se `.standard` čte na hodnotu, kterou tam nemá kdo mít — jinak by to bylo tvrzení
    /// o nastavení stroje.
    @Test("Zápis do vlastní suity nejde do domény procesu")
    func writingToTheScratchSuiteKeepsTheProcessDomainClean() throws {
        let scratch = try ScratchDefaults("processPreferences")
        defer { scratch.remove() }
        let key = "scratchProbe-\(UUID().uuidString)"

        scratch.store.set(1_180.0, forKey: key)

        #expect(scratch.store.double(forKey: key) == 1_180.0)
        #expect(UserDefaults.standard.object(forKey: key) == nil)
    }

    /// Úklid je **doména i soubor po ní**. `removePersistentDomain(forName:)` plist nechá —
    /// změřeno, viz `ScratchDefaults` — takže bez toho druhého kroku by se soubory
    /// v `~/Library/Preferences` hromadily.
    ///
    /// **Co tenhle test dokázat neumí**, a je to potřeba vědět: prázdný plist se vrací teprve
    /// **zánikem procesu**, takže tvrzení uvnitř běhu projde i nad úklidem, který na disku nic
    /// neuklidí (přesně tak to vypadalo v prvním plném běhu po #411 — zeleno a pět zbylých souborů
    /// po 42 B). Na to je jediná kontrola, a je za hranicí harnessu: po plném běhu nesmí
    /// `~/Library/Preferences` obsahovat žádný `cz.prism.tests.*`. Proč se z toho nedá udělat test,
    /// je v `docs/testovani.md` — souběžné běhy tří slotů mají svoje soubory rozdělané.
    @Test("Po vlastní suitě nezůstane doména ani plist")
    func scratchDefaultsLeaveNothingBehind() throws {
        let scratch = try ScratchDefaults("processPreferences")
        scratch.store.set(true, forKey: "scratchProbe")
        #expect(FileManager.default.fileExists(atPath: scratch.plist.path))

        scratch.remove()

        #expect(!FileManager.default.fileExists(atPath: scratch.plist.path))
        #expect(UserDefaults(suiteName: scratch.name)?.object(forKey: "scratchProbe") == nil)
    }

    // MARK: - Zdrojáky

    private struct Source {
        let path: String
        /// Jen kód — řádky, které začínají `//`, jsou pryč.
        let code: String
    }

    /// Zdrojáky pod složkou repa, s cestou relativní k ní.
    ///
    /// Čte se **v každém tvrzení znovu**, a je to tatáž volba jako u `GlobalAppearanceTests`: tři
    /// pravidla jsou tři různé červené, takže se nesbírají do jednoho testu kvůli jednomu průchodu
    /// stromem. Swift Testing pouští testy paralelně, takže se ty průchody stejně překrývají.
    private func sources(under folder: String, extension suffix: String = "swift") throws -> [Source] {
        let root = Self.repository.appending(path: folder)
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else {
            throw SourceError.unreadable(root.path)
        }
        var files: [Source] = []
        for case let url as URL in walker where url.pathExtension == suffix {
            let text = try String(contentsOf: url, encoding: .utf8)
            // `TextLines`, ne `split(separator: "\n")` — pravidlo repa platí i v testech.
            let lines = TextLines.content(text)
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            files.append(
                Source(path: url.path.replacingOccurrences(of: root.path + "/", with: ""), code: lines.joined(separator: "\n"))
            )
        }
        guard !files.isEmpty else { throw SourceError.unreadable(root.path) }
        return files
    }

    private enum SourceError: Error {
        case unreadable(String)
    }

    /// **Žádný test nepíše ani nečte doménu procesu.** Host má od #411 svoji, takže to už není
    /// nastavení uživatele — ale je to pořád **jedna doména pro souběžné běhy tří slotů**, tedy
    /// hodnota, kterou test nevlastní. Tvrzení postavené na ní vychází podle toho, kdo běžel vedle.
    ///
    /// Kdo potřebuje `UserDefaults`, vezme si `ScratchDefaults` — a tam, kde jde o `@AppStorage`,
    /// ho nasadí na to view, které se měří (`defaultAppStorage(_:)`).
    @Test("Žádný test nesahá na UserDefaults.standard")
    func keepsEveryTestOffTheProcessDomain() throws {
        for file in try sources(under: "Tests") where file.path != Self.guardFile {
            #expect(!file.code.contains("UserDefaults.standard"), "\(file.path) sahá na doménu procesu")
        }
    }

    /// **Pojmenovaná suita s literálem je globál stejně jako `.standard`**, jen se to projeví teprve
    /// pod souběžnou zátěží (změřeno u #420, viz `ScratchDefaults`). Jméno proto skládá
    /// `ScratchDefaults` z `UUID`, ne test.
    @Test("Vlastní suita se nepojmenovává literálem")
    func keepsSuiteNamesUnique() throws {
        for file in try sources(under: "Tests") where file.path != Self.guardFile {
            #expect(
                !file.code.contains("UserDefaults(suiteName: \""),
                "\(file.path) si pojmenoval suitu literálem — jméno musí být unikátní na běh, viz ScratchDefaults"
            )
        }
    }

    /// **Hlavní instanci nesmí test ani přečíst.** Nejde jen o zápis: `SlotCleanupTests` tvrdily
    /// „hlavní instance se nezměnila“ z otisku jejího plistu a nainstalovaného bundlu, a do obojího
    /// píše někdo jiný — do plistu **běžící aplikace** (naměřeno 6 296 → 6 343 B) a do
    /// `/Applications/PRism.app` každé `bin/run.sh` po mergi. Byl z toho **dvakrát falešně červený
    /// `main`**. Sada, která tvrdí něco o úklidu, si hlavní instanci **vyrábí** — vlastní slot
    /// s `UUID` a podstrčený `HOME` (`MainInstanceDecoy`).
    ///
    /// Hlídají se dva literály, každý celý: jméno domény (takže `com.ondrajodas.prism.testhost`
    /// ani `com.ondrajodas.prism.\(slot)` sem nespadají) a cesta k nainstalovanému bundlu.
    ///
    /// **Jméno plistu se nehlídá, a je to vědomé:** `com.ondrajodas.prism.plist` je zrovna to jméno,
    /// které si vyrobená hlavní instance musí dát, aby o něčem vypovídala — ban by tedy zakázal tu
    /// opravu, ne tu vadu. O tom, na který soubor se sahá, rozhoduje `HOME`, ne jméno.
    @Test("Hlavní instance se v testech nejmenuje")
    func keepsEveryTestOffTheMainInstance() throws {
        for file in try sources(under: "Tests") where file.path != Self.guardFile {
            #expect(
                !file.code.contains("\"com.ondrajodas.prism\""),
                "\(file.path) jmenuje doménu hlavní instance"
            )
            #expect(
                !file.code.contains("/Applications/PRism.app"),
                "\(file.path) sahá na nainstalovaný bundle hlavní instance"
            )
        }
    }

    // MARK: - Druhá polovina té izolace

    /// **`run.sh` předává `PRISM_SLOT` vždycky, i prázdný.** Bez toho by si hlavní instance vzala
    /// výchozí hodnotu z projektu (`.testhost`) — tedy jiné bundle ID —, a to znamená rázem
    /// prázdné nastavení, propadlá TCC povolení a druhý PRism v LaunchServices. Za běhu se na to
    /// zeptat nedá: je to vlastnost toho skriptu, ne aplikace.
    @Test("run.sh si identitu aplikace vyžádá výslovně")
    func theRunScriptStampsTheIdentity() throws {
        let script = try String(
            contentsOf: Self.repository.appending(path: "bin/run.sh"),
            encoding: .utf8
        )
        let lines = TextLines.content(script)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("#") }

        #expect(lines.contains { $0.contains("SLOT_ARGS=(PRISM_SLOT=") && $0.contains("PRISM_SLOT_LABEL=") })
        #expect(lines.contains { $0.contains("\"${SLOT_ARGS[@]}\"") })
    }

    // MARK: - Cache hostitele (#421)

    /// **Hostitel nepracuje v cache aplikace.** Tatáž třída jako doména `UserDefaults` výš, jen se
    /// na ni přišlo o deset issues později: `CacheLayout.applicationSupport` si kořen bere
    /// z `CFBundleName`, a ten se do #421 skládal z `PRISM_SLOT_LABEL`, který měl v projektu
    /// **prázdnou** výchozí hodnotu. `xcodebuild test` tedy pouštěl aplikaci nad
    /// `~/Library/Application Support/PRism` — tedy nad cache, kterou používá hlavní instance.
    ///
    /// Nebylo to teoretické. Testovací host je celá aplikace, takže při každém běhu testů
    /// **obnovil otevřené záložky** (#527), dotáhl si k nim detail i diff **skutečnými** dotazy na
    /// `gh` a vykreslil je ve svém okně — a protože `RenderDiagnostics.current` je jedna hodnota na
    /// proces, ty průchody tělem se přičetly k tomu, co měřila sonda #421. Naměřený rozdíl:
    /// `DiffView` 26 průchodů proti 14, `DiffRow.id` 9 701 proti 5 820, a čísla se mezi běhy hýbala,
    /// protože záviselo na tom, kdy dorazí odpověď ze sítě. Po opravě jsou opakovatelná do jedničky.
    /// K tomu psal do `tabs.json` a `sessions.json` hlavní instance, tedy do souborů, podle kterých
    /// se uklízejí osiřelé session (#351).
    ///
    /// Hlídá se to **dvakrát**, protože každé z těch tvrzení chytá jinou polovinu: za běhu, že
    /// hostitel má vlastní kořen, a nad `project.pbxproj`, že výchozí hodnota v projektu není
    /// prázdná — bez toho druhého by šlo pravidlo obejít tím, že `PRISM_SLOT_LABEL` z projektu
    /// zmizí a `Info.plist` z něj složí zase `PRism`.
    @Test("Testovací host nepracuje v cache aplikace")
    func theHostDoesNotShareTheApplicationCache() {
        let root = CacheLayout.applicationSupport.root.lastPathComponent
        #expect(
            root != "PRism",
            """
            Testovací host má kořen cache hlavní instance (\(root)), takže xcodebuild test pracuje \
            nad cache, kterou používá aplikace — obnoví její záložky, ptá se za ni gh a přepisuje \
            jí sessions.json. Zkontroluj výchozí PRISM_SLOT_LABEL v project.pbxproj.
            """
        )
    }

    @Test("Projekt dává buildu bez identity vlastní jméno")
    func theProjectStampsATesthostName() throws {
        let project = try String(
            contentsOf: Self.repository.appending(path: "PRism.xcodeproj/project.pbxproj"),
            encoding: .utf8
        )
        let labels = TextLines.content(project)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("PRISM_SLOT_LABEL = ") }

        #expect(!labels.isEmpty, "project.pbxproj nemá PRISM_SLOT_LABEL — cache hostitele je pak cache aplikace")
        for label in labels {
            #expect(
                label != "PRISM_SLOT_LABEL = \"\";",
                "PRISM_SLOT_LABEL má v projektu prázdnou výchozí hodnotu, takže CFBundleName vyjde PRism"
            )
        }
    }
}
