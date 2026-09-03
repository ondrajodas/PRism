import AppKit
import Foundation
import Testing

@testable import PRism

/// **Metrika písma se měří jednou za proces a nula se nepamatuje** (#407).
///
/// Tohle je ta sada, která nahrazuje tři léčby na třech místech (#367, #348, #327). Testuje se na
/// **vlastní instanci** `FontMetric()`, ne na `shared`: sdílené měřidlo plní i suity, které běží
/// vedle, takže by se počty měření nedaly tvrdit — a vyprázdnit sdílené měřidlo uprostřed plného
/// běhu by znamenalo poslat ostatní sady měřit znovu, tedy zavést zpátky přesně to riziko, kvůli
/// kterému měřidlo vzniklo.
///
/// Tvrzení jsou čtyři druhy: **kolikrát se měří**, **co se stane, když měření nevyjde**, **jestli
/// jsou náhradní cesty použitelné**, a **kde v repu smí metrika bydlet**.
///
/// **Od #550 je ten druhý druh o jednu otázku bohatší**: nejen „co se stane“, ale **jak se to
/// pozná**. Měřidlo nepovedené měření vydávalo jako nulu, tedy k nerozeznání od rozměru nula —
/// odsud je to `nil` z `metric(_:of:)`, kdežto nulu dostane jedině kresba.
@Suite("Metrika písma z jednoho místa (#407)")
struct FontMetricTests {
    private let mono = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)

    // MARK: - Kolikrát se měří

    /// **Jedno měření bez opakování, i když si o hodnotu řekne osm vláken čtyři tisíce krát.**
    ///
    /// Tohle je celé zadání #407 v jednom tvrzení. Do #327 se měřilo při každém použití, od #367
    /// jednou za test (Swift Testing staví na každý test vlastní instanci suity, takže to bylo
    /// pořád N měření na proces) a #348 to opsalo do další sady. Vložená regrese, kterou to chytá:
    /// vyhodit zapamatování a měřit v `FontMetric.value(_:of:)` pokaždé — pak je měření 32 000.
    @Test("Metrika se měří jednou, ať se na ni ptá kdokoli")
    func measuresOncePerProcess() async {
        let metric = FontMetric()

        await withTaskGroup(of: Set<CGFloat>.self) { group in
            for _ in 0..<8 {
                group.addTask {
                    // Písmo se staví v každé úloze zvlášť: `NSFont` není `Sendable`, a je to
                    // i věrnější — v aplikaci si o metriku říká pět různých míst, každé se svým
                    // objektem písma.
                    let font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
                    var seen: Set<CGFloat> = []
                    for _ in 0..<4_000 { seen.insert(metric.characterWidth(of: font)) }
                    return seen
                }
            }
            var seen: Set<CGFloat> = []
            for await values in group { seen.formUnion(values) }
            // Jedna hodnota, ne „hodnoty, které se náhodou nerozešly“: kdyby se měřilo pokaždé,
            // tohle by na zdravém stroji prošlo — proto se k tomu tvrdí i počet měření níž.
            //
            // `Set<CGFloat>` tady na rozdíl od sondy vadit nemůže, i když se `NaN` nerovná sám sobě:
            // měřidlo `NaN` nikdy nevydá (zavírá to `Policy.usableFontMetric`), a kdyby vydalo, je to
            // právě „různé hodnoty“, tedy pád, který tenhle test má nahlásit.
            #expect(seen.count == 1, "32 000 čtení dalo \(seen.count) různých hodnot: \(seen.sorted())")
        }

        #expect(metric.tally == FontMetric.Tally(measurements: 1), "\(metric.tally)")
        #expect(metric.remembered == 1)
    }

    /// Tři druhy metriky jsou **tři klíče**, ne jeden: kdyby se slily, výška řádku by vyšla jako
    /// šířka znaku a bylo by to potichu (na mono 13 je to 16,0 proti 8,04).
    @Test("Druhy metriky se v klíči nemíchají")
    func keepsTheThreeKindsApart() {
        let metric = FontMetric()
        let width = metric.characterWidth(of: mono)
        let line = metric.lineHeight(of: mono)
        let box = metric.boundingHeight(of: mono)

        #expect(metric.tally.measurements == 3, "\(metric.tally)")
        #expect(width != line)
        #expect(line != box)
        #expect(width > 0 && line > 0 && box > 0)
    }

    /// **Mez je vidět a platí.** Cache bez vyjmenované meze je únik paměti s odkladem (#224), takže
    /// se při překročení zahodí celá — a hodnota, která v ní byla, se změří znovu.
    @Test("Přes svou mez se měřidlo nedostane")
    func staysWithinItsCapacity() {
        let metric = FontMetric(capacity: 4)
        for size in stride(from: 8.0, to: 14.0, by: 1.0) {
            _ = metric.characterWidth(of: .monospacedSystemFont(ofSize: size, weight: .regular))
        }

        #expect(metric.remembered <= metric.capacity, "zapamatováno \(metric.remembered), mez \(metric.capacity)")
        // Šest písem přes mez čtyř znamená, že se sada cestou zahodila — takže první z nich už
        // zapamatované není a měří se znovu.
        let before = metric.tally.measurements
        _ = metric.characterWidth(of: .monospacedSystemFont(ofSize: 8, weight: .regular))
        #expect(metric.tally.measurements == before + 1, "\(metric.tally)")
    }

    // MARK: - Když měření nevyjde

    /// **Když hlavní měření dá nulu, zaskočí čerstvé písmo — a je to změřené na skutečném písmu.**
    ///
    /// Písmo s **nulovou transformační maticí** je nejbližší dosažitelná podoba toho, co se v plném
    /// běhu naměřilo: `maximumAdvancement` u něj vyjde **0,0**. Druhá cesta (čerstvé písmo z téhož
    /// deskriptoru) vrátí **0,618** — tedy použitelné číslo tam, kde by jedno čtení dalo nulu.
    /// Přesně na tomhle celá oprava stojí: vadný je **objekt** písma, takže se zkusí jiný.
    ///
    /// Tvrdí se i **zamítnutá hodnota**: u #327 se z pádu nedalo poznat, jestli metrika vrátila nulu,
    /// nebo `NaN`, a to je zrovna ta informace, kvůli které `Tally` počty vůbec nese.
    @Test("Nulu z hlavního měření zachrání čerstvé písmo")
    func fallsBackWhenTheDirectReadIsZero() throws {
        let metric = FontMetric()
        let font = try #require(brokenFont(scaledBy: 0, size: 10), "vadné písmo se nepostavilo")

        try #require(FontMetric.Route.measured.read(.characterWidth, of: font) == 0, "písmo není vadné")
        #expect(metric.characterWidth(of: font) > 0, "náhradní cesta nic nevrátila")
        #expect(
            metric.tally
                == FontMetric.Tally(measurements: 1, retries: 0, fallbacks: 1, failures: 0, firstRejected: 0),
            "\(metric.tally)"
        )
        #expect(metric.remembered == 1)
    }

    /// **Když nepomůže žádná cesta, zkusí se celý řetěz znovu — a je to naměřená léčba, ne pojistka.**
    ///
    /// V osmém z deseti plných běhů pod zátěží vyšly u mono 13 **všechny tři cesty nulové** a totéž
    /// písmo dalo o zlomek sekundy později 8,036 (`měření 2, nepovedlo se 1×, zamítnuto 0.0`). Vada
    /// tedy netrvá, takže jediné, co pomůže, je zkusit to **později**.
    ///
    /// Tvrdí se to na písmu, které je vadné **natrvalo** (nekonečná matice): měřidlo na něm vyčerpá
    /// všechny pokusy, takže je z počtu opakování vidět, že se ten řetěz doopravdy prochází víc než
    /// jednou. A tvrdí se u toho i **cena**: pokusy stojí odmlku, ne nic.
    @Test("Nepovedené měření se zkusí znovu, ne jednou")
    func retriesTheWholeChain() throws {
        let metric = FontMetric()
        let broken = try #require(brokenFont(scaledBy: .infinity, size: 10), "vadné písmo se nepostavilo")

        let started = Date()
        #expect(metric.characterWidth(of: broken) == 0)
        let elapsed = Date().timeIntervalSince(started)

        #expect(metric.tally.retries == FontMetric.attempts - 1, "\(metric.tally)")
        #expect(
            elapsed >= Double(FontMetric.attempts - 1) * FontMetric.pauseBetweenAttempts,
            "měření trvalo \(elapsed) s, tedy se mezi pokusy nečekalo"
        )
    }

    /// **Nezdařené měření se nepamatuje** — jinak by z nuly byl stav procesu, a to je horší než
    /// vrátit ji jednou: `SelectableCodeView.characterWidth` i `DiffToolbar.characterWidth` jsou
    /// `static let`, tedy jedno měření navždycky.
    ///
    /// Písmo s **nekonečnou** maticí selže na všech třech cestách i po všech pokusech a vrací `NaN` —
    /// a je to zároveň ten důvod, proč `Policy.usableFontMetric(_:)` hlídá `isFinite`, ne jen
    /// kladnost: `NaN` je hodnota, kterou skutečné `NSFont` vydá, a `Int(NaN)` shodí proces.
    @Test("Nula se nezapamatuje a příště se měří znovu")
    func doesNotRememberAFailedMeasurement() throws {
        let metric = FontMetric()
        let broken = try #require(brokenFont(scaledBy: .infinity, size: 10), "vadné písmo se nepostavilo")

        #expect(metric.characterWidth(of: broken) == 0)
        #expect(metric.tally.measurements == 1, "\(metric.tally)")
        #expect(metric.tally.failures == 1, "\(metric.tally)")
        #expect(metric.tally.fallbacks == 0, "\(metric.tally)")
        // `NaN`, tedy ne nula — proto se v `Policy.usableFontMetric` hlídá `isFinite`.
        #expect(metric.tally.firstRejected?.isNaN == true, "zamítnuto \(String(describing: metric.tally.firstRejected))")
        #expect(metric.remembered == 0, "nula se zapamatovala")

        #expect(metric.characterWidth(of: broken) == 0)
        #expect(metric.tally.measurements == 2, "druhé volání neměřilo znovu: \(metric.tally)")
    }

    /// **Nepovedené měření se dá poznat od rozměru nula** (#550), a je to celý ten rozdíl, který do
    /// #550 chyběl: `CommitPanelRoomTests` padaly zprávou `šířka znaku: 0`, ze které nebylo poznat,
    /// jestli je písmo nulové, nebo jestli měřidlo v tu sekundu nic nemělo.
    ///
    /// Tvrdí se **obě strany naráz**, protože jedna bez druhé nic neznamená: `metric(_:of:)` vydá
    /// `nil` (nemám), kdežto `characterWidth(of:)` dál vydá **nulu**, protože z něj kreslí okno
    /// a to čekat nesmí. A tvrdí se u toho i to, že se **nula nezakryla**: `.some(0)` z měřidla
    /// vypadnout nemůže, protože o použitelnosti rozhoduje `Policy.usableFontMetric(_:)` — kdyby se
    /// tam nula jednou stala legitimní odpovědí, vydá se jako `.some(0)` a od `nil` se pozná.
    @Test("Chybějící metrika je nil, ne nula")
    func tellsAMissingMetricFromAZeroSize() throws {
        let metric = FontMetric()
        let broken = try #require(brokenFont(scaledBy: .infinity, size: 10), "vadné písmo se nepostavilo")

        #expect(metric.metric(.characterWidth, of: broken) == nil, "měřidlo vydalo hodnotu: \(metric.tally)")
        #expect(metric.characterWidth(of: broken) == 0, "kresba nedostala nulu: \(metric.tally)")

        // A na zdravém písmu je to `.some`, ne „něco kladného“ — jinak by tvrzení výš prošlo i nad
        // měřidlem, které vrací `nil` vždycky.
        let usable = try #require(metric.metric(.characterWidth, of: mono))
        #expect(usable > 0, "šířka znaku: \(usable), \(metric.tally)")
        #expect(Policy.usableFontMetric(CGFloat(0)) == nil, "nula je pořád nepoužitelná hodnota")
    }

    /// **A čekání se vzdává nahlas** (#550). `TestWait.settledFontMetric` vrací nulu i tehdy, když
    /// se metriky nedočká — jenže k té nule **zapíše nález**, takže test spadne na místě čekání
    /// a v hlášce stojí, že metrika není, ne že je rozměr nula. Kdyby se ten nález nezapisoval,
    /// vypadalo by nedočkání se přesně jako to, co #550 opravuje.
    ///
    /// Zkouší se na písmu, které je vadné **natrvalo** (nekonečná matice) a s nejkratším stropem —
    /// `withKnownIssue` ten nález spolkne, a **spadne, když žádný nepřijde**, takže je to tvrzení
    /// o zapsání, ne o návratové hodnotě.
    @Test("Nedočkaná metrika zapíše nález, ne jen nulu")
    func theWaitGivesUpLoudly() throws {
        let broken = try #require(brokenFont(scaledBy: .infinity, size: 10), "vadné písmo se nepostavilo")
        var value: CGFloat = -1

        withKnownIssue("metrika se neusadí, na to je tenhle test") {
            value = TestWait.settledFontMetric(.characterWidth, of: broken, within: .milliseconds(1))
        }

        #expect(value == 0, "nedočkané čekání vydalo \(value)")
    }

    /// Co se z naměřené hodnoty smí zapamatovat, rozhoduje `Policy.usableFontMetric(_:)` — čistá
    /// funkce, tedy vyčerpávajícím výčtem. **Nekonečno a `NaN` v něm nejsou navíc**: `Int(x)` na nich
    /// **shodí proces**, kdežto nulu zavře `guard` v `Policy.charactersPerSide`.
    @Test("Použitelná je jen kladná konečná hodnota")
    func acceptsOnlyFinitePositiveValues() {
        #expect(Policy.usableFontMetric(Double(8.0361328125)) == 8.0361328125)
        #expect(Policy.usableFontMetric(Double(0.0001)) == 0.0001)
        #expect(Policy.usableFontMetric(Double(0)) == nil)
        #expect(Policy.usableFontMetric(Double(-0.0)) == nil)
        #expect(Policy.usableFontMetric(Double(-8)) == nil)
        #expect(Policy.usableFontMetric(Double.nan) == nil)
        #expect(Policy.usableFontMetric(Double.infinity) == nil)
        #expect(Policy.usableFontMetric(-Double.infinity) == nil)
        #expect(Policy.usableFontMetric(Double.greatestFiniteMagnitude) == .greatestFiniteMagnitude)
        // A v tom typu, ve kterém pracuje měřidlo — převod mezi `CGFloat` a `Double` je zrovna to
        // druhé místo, kde se dá číslo pokazit.
        #expect(Policy.usableFontMetric(CGFloat(0)) == nil)
        #expect(Policy.usableFontMetric(CGFloat(8.0361328125)) == 8.0361328125)
    }

    // MARK: - Jsou náhradní cesty použitelné

    /// **Cesta, kterou nikdo nezkusil, je cesta, která nefunguje.** Náhradní měření se za normálního
    /// běhu nespustí nikdy, takže by se do repa dalo napsat cokoli a nikdo by si toho nevšiml, dokud
    /// by na tom jednou nezáleželo.
    ///
    /// Tvrdí se to, co se naměřilo, a u každého druhu jiná míra shody — je to zapsané měření, ne
    /// naděje:
    ///
    /// - **šířka znaku**: obalový rámec je **horní** mez (11,63 proti 8,04 na mono 13), tedy širší
    ///   znak a méně znaků na řádek — chyba na tu stranu, na kterou se chybovat má;
    /// - **výška řádku** na bod (16,0 proti 15,31 na mono 13; `defaultLineHeight` sumu zaokrouhluje);
    /// - **obalový rámec** jako **dolní** mez — inkoust přečnívá nad ascender i pod descender
    ///   (19,86 proti 15,31), a druhá cesta k němu nevede.
    @Test(
        "Náhradní cesta dá použitelné číslo",
        arguments: [NSFont.systemFontSize, 10.5, NSFont.smallSystemFontSize] as [CGFloat]
    )
    func theFallbackRouteAgreesEnough(size: CGFloat) throws {
        let font = NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        for kind in [FontMetric.Kind.characterWidth, .lineHeight, .boundingHeight] {
            let measured = try #require(FontMetric.Route.measured.read(kind, of: font))
            let derived = try #require(FontMetric.Route.derived.read(kind, of: font))
            let fresh = try #require(FontMetric.Route.fresh.read(kind, of: font))

            #expect(derived > 0, "\(kind) v \(size): náhradní cesta dala \(derived)")
            #expect(fresh == measured, "\(kind) v \(size): čerstvé písmo dalo \(fresh), ne \(measured)")
            switch kind {
            case .characterWidth: #expect(derived >= measured, "\(size): \(derived) proti \(measured)")
            case .lineHeight: #expect(abs(derived - measured) <= 1, "\(size): \(derived) proti \(measured)")
            case .boundingHeight: #expect(derived <= measured, "\(size): \(derived) proti \(measured)")
            }
        }
    }

    /// **Poslední cesta nesmí sázet text**, a je to tvrzení nad zdrojáky, protože jinak se to nedá
    /// hlídat: sazba písmem, u kterého selhalo přímé čtení metriky, položila při #407 **celý běh**
    /// (`NSInvalidArgumentException` z `TAttributes::ApplyFont` pod `NSAttributedString.size()`,
    /// 169 testů ze 3 979). Spadlý proces je horší než červený test, takže se náhradní měření ptá
    /// jedině na čísla, která má `NSFont` sám u sebe.
    @Test("Náhradní měření nesází text")
    func theFallbackNeverTypesets() throws {
        let source = try condensed(at: "App/Views/FontMetric.swift")
        #expect(!source.contains("NSAttributedString"), "měřidlo sází text")
    }

    // MARK: - Kde metrika smí bydlet

    /// **Metrika písma se v repu čte na jednom místě**, a tvrdí se to nad zdrojáky — za běhu se
    /// „kolikrát je to zapsané“ zjistit nedá. Tatáž konstrukce jako `GlobalAppearanceTests`
    /// a `SingleWayOutTests`, včetně zahazování řádkových komentářů: o metrice se v komentářích
    /// mluví na půltuctu míst a právě ta vysvětlení to pravidlo drží pochopitelné.
    ///
    /// Do #407 to bylo **pět míst v `App/`** — `LogTailTextView`, `SelectableCodeView`, `DiffToolbar`
    /// a v `DiffTextView` dvakrát, z toho jednou jako dvojice `defaultLineHeight` / obalový rámec
    /// podle toho, jak daleko bylo view v sestavování, tedy **dvě čísla na jednu výšku řádku** —
    /// a **pět v `Tests/`**.
    ///
    /// **Výjimky jsou dvě a obě metriku čtou proto, že se ptají na cesty**: tahle sada (porovnává je
    /// mezi sebou) a `FontMetricProbe` (vypisuje je vedle sebe). Jiná v seznamu být nemá — kdo měří
    /// rozměr, ptá se měřidla.
    @Test("Metriku písma čtou v repu jen měřidlo a to, co ho zkouší")
    func fontMetricsAreReadInOnePlace() throws {
        let allowed = [
            "App/Views/FontMetric.swift",
            "Tests/Views/FontMetricTests.swift",
            "Tests/Views/FontMetricProbe.swift",
        ]
        let offenders = try (sources(in: "App") + sources(in: "Tests"))
            .filter { !allowed.contains($0.path) }
            .filter { source in Self.rawMetricReads.contains { source.condensed.contains($0) } }
            .map(\.path)

        #expect(offenders.isEmpty, "vlastní čtení metriky písma: \(offenders.joined(separator: ", "))")
    }

    /// A **sady, které na té třídě padaly, si na metriku počkají** — tvrzení výš zakazuje surové
    /// čtení, tohle tvrdí, odkud si tedy metriku vzaly. Bez něj by šlo pravidlo splnit i tím, že se
    /// tvrzení o rozměru zahodí.
    ///
    /// **Od #550 je to `TestWait.settledFontMetric`, ne `FontMetric.shared`** a je to změna kvůli
    /// nule: měřidlo z pojmenovaných metod nepovedené měření vydává jako nulu (kreslí z nich okno
    /// a to čekat nesmí), takže sada, která z nuly skládá tvrzení, tvrdí něco o procesu, ne
    /// o aplikaci. Test čekat může — a `settledFontMetric` je jediné místo, kde se čeká.
    @Test("Sady, které na tom padaly, si na metriku počkají")
    func theSuitesThatFellWaitForTheMetric() throws {
        let places = [
            "Tests/Views/CommitPanelRoomTests.swift",
            "Tests/Views/LogTailHeightTests.swift",
            "Tests/Views/DesignPillTests.swift",
            "Tests/Views/LogTailScrollerReserveTests.swift",
            "Tests/Views/CheckLogRoomProbe.swift",
        ]
        for path in places {
            #expect(
                try condensed(at: path).contains("TestWait.settledFontMetric("),
                "\(path) si na metriku nepočká"
            )
        }
    }

    /// **A žádná jiná sada si o metriku neřekne přímo** (#550) — jinak by se ta nula vrátila do
    /// tvrzení tou cestou, kterou se do nich dostala poprvé: novou sadou, která o #407 ani #550
    /// nevěděla. Tvrzení výš jmenuje pět sad, tohle uzavírá zbytek `Tests/`, a to je ten rozdíl
    /// mezi opravou třídy a opravou výskytu.
    ///
    /// **Tři výjimky, každá s důvodem:** tahle sada (hledané řetězce v ní stojí jako literály
    /// a měří samo měřidlo), `FontMetricProbe` (porovnává cesty vedle sebe) a
    /// `CodeTextSheetSizingTests` — ta srovnává `static let` konstantu aplikace s tím, co měřidlo
    /// vydá **aplikaci**, takže se musí ptát touž nečekající cestou; s čekáním by tvrdila něco
    /// jiného, než co v konstantě leží.
    ///
    /// **`tally` v hlášce zakázaná není** — je to počet měření, ne rozměr, a je to zrovna to, co
    /// u #407 udělalo z „šířka znaku: 0“ příznak s příčinou.
    @Test("Metriku z měřidla si v testech nebere nikdo mimo helper čekání")
    func noSuiteReadsTheDeviceWithoutWaiting() throws {
        let allowed = [
            "Tests/Views/FontMetricTests.swift",
            "Tests/Views/FontMetricProbe.swift",
            "Tests/Views/CodeTextSheetSizingTests.swift",
        ]
        let reads = [
            "FontMetric.shared.characterWidth(",
            "FontMetric.shared.lineHeight(",
            "FontMetric.shared.boundingHeight(",
        ]
        let offenders = try sources(in: "Tests")
            .filter { !allowed.contains($0.path) }
            .filter { source in reads.contains { source.condensed.contains($0) } }
            .map(\.path)

        #expect(offenders.isEmpty, "metrika bez čekání: \(offenders.joined(separator: ", "))")
        // Pojistka, že stráž doopravdy hledá: v tomhle souboru ty vzory stojí, a musí sednout.
        let guardFile = try condensed(at: "Tests/Views/FontMetricTests.swift")
        #expect(reads.allSatisfy { guardFile.contains($0) }, "vzory nesedly ani na stráži samotné")
        #expect(!guardFile.contains(where: { $0.isWhitespace }), "v `condensed` zůstaly mezery")
    }

    /// Surová čtení metriky písma. `boundingRectForFont` je v tom výčtu taky, i když se na něm ta
    /// vada nenaměřila: kdo kreslí z nulového rámce, nakreslí nic, a druhé místo pro tutéž otázku
    /// je zrovna to, co #407 ruší.
    private static let rawMetricReads = [
        "maximumAdvancement",
        "defaultLineHeight",
        "boundingRectForFont",
    ]

    // MARK: - Měřidlo

    /// Písmo s vadnou transformační maticí. Aplikace žádné takové nestaví — je to jediný způsob, jak
    /// se k písmu s nepoužitelnou metrikou dostat úmyslně, a naměřené hodnoty jsou u tvrzení výš.
    private func brokenFont(scaledBy scale: CGFloat, size: CGFloat) -> NSFont? {
        let descriptor = mono.fontDescriptor.addingAttributes([
            .matrix: AffineTransform(scaleByX: scale, byY: scale),
        ])
        return NSFont(descriptor: descriptor, size: size)
    }

    private struct Source {
        let path: String

        /// Kód **bez jediné mezery a bez zalomení** (#490, sem u #550). Hledá se nad tímhle, protože
        /// ve Swiftu je mezera uvnitř volání volná: `FontMetric . shared` je platný zápis téhož,
        /// takže stráž nad surovým textem by ho pustila — tedy zezelenala by právě nad tou chybou,
        /// na kterou je. (U `rawMetricReads` je to uniformita, ne oprava: jeden identifikátor mezera
        /// rozdělit neumí.)
        ///
        /// **Uložený, ne počítaný** — čísla jsou u `UnanimatedWindowTests.Source.condensed`: tři
        /// vzory čtené z computed property znamenaly tři průchody přes 5,1 MB zdrojáků. Surový text
        /// se nedrží: nikdo ho tady nečte.
        let condensed: String

        /// `code` je kód **bez řádkových komentářů**, protože o metrice se v nich mluví.
        init(path: String, code: String) {
            self.path = path
            self.condensed = code.filter { !$0.isWhitespace }
        }
    }

    private static let repository = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    /// Kód jednoho souboru, bez řádkových komentářů a **bez mezer** — viz `Source.condensed` (#550).
    /// Nad surovým textem se v téhle sadě nehledá nic, takže se ani nevydává.
    private func condensed(at path: String) throws -> String {
        let text = try String(contentsOf: Self.repository.appending(path: path), encoding: .utf8)
        return Self.stripped(text).filter { !$0.isWhitespace }
    }

    private static func stripped(_ text: String) -> String {
        // `TextLines`, ne `split(separator: "\n")` — pravidlo repa platí i v testech.
        TextLines.content(text)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    /// Zdrojáky pod jednou složkou repa, bez řádkových komentářů. Prázdný výsledek je chyba, ne
    /// zelený test: guard, který nemá co čtou, tvrdí `isEmpty` na prázdnu.
    private func sources(in folder: String) throws -> [Source] {
        let root = Self.repository.appending(path: folder)
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else {
            throw SourceError.unreadable(root.path)
        }
        var files: [Source] = []
        for case let url as URL in walker where url.pathExtension == "swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            let path = folder + "/" + url.path.replacingOccurrences(of: root.path + "/", with: "")
            files.append(Source(path: path, code: Self.stripped(text)))
        }
        guard !files.isEmpty else { throw SourceError.unreadable(root.path) }
        return files
    }

    private enum SourceError: Error {
        case unreadable(String)
    }
}
