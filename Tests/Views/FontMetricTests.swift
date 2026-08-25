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
        let source = try code(at: "App/Views/FontMetric.swift")
        #expect(!source.contains("NSAttributedString"), "měřidlo sází text")
    }

    // MARK: - Kde metrika smí bydlet

    /// **V `App/` se metrika písma čte na jednom místě**, a tvrdí se to nad zdrojáky — za běhu se
    /// „kolikrát je to v repu zapsané“ zjistit nedá. Tatáž konstrukce jako `GlobalAppearanceTests`
    /// a `SingleWayOutTests`, včetně zahazování řádkových komentářů: o metrice se v komentářích
    /// mluví na půltuctu míst a právě ta vysvětlení to pravidlo drží pochopitelné.
    ///
    /// Do #407 to bylo **pět míst**: `LogTailTextView`, `SelectableCodeView`, `DiffToolbar`
    /// a v `DiffTextView` dvakrát — z toho jednou jako dvojice `defaultLineHeight` / obalový rámec
    /// podle toho, jak daleko bylo view v sestavování, tedy **dvě čísla na jednu výšku řádku**.
    @Test("Metriku písma čte v App jediný soubor")
    func onlyOneFileInTheAppReadsFontMetrics() throws {
        let offenders = try appSources()
            .filter { $0.path != "App/Views/FontMetric.swift" }
            .filter { source in Self.rawMetricReads.contains { source.code.contains($0) } }
            .map(\.path)

        #expect(offenders.isEmpty, "vlastní čtení metriky písma: \(offenders.joined(separator: ", "))")
    }

    /// A **sady, které na té třídě padaly, si metriku nečtou samy.** Je to inkluzivní výčet
    /// schválně: `FontMetricTests` a `FontMetricProbe` metriku čtou surově, protože se právě na
    /// cesty ptají, a v `Tests/` leží i sady, které si ji zatím čtou samy (`PillTypesettingTests`,
    /// `CodeTextSheetSizingTests`) — o těch je řeč v `docs/testovani.md`, a plošný zákaz by musel
    /// mít v seznamu výjimek dva soubory, které se na tuhle třídu jen zatím nedostaly.
    @Test("Sady, které na tom padaly, metriku nečtou samy")
    func theSuitesThatFellTakeTheMetricFromOnePlace() throws {
        let places = [
            "Tests/Views/CommitPanelRoomTests.swift",
            "Tests/Views/LogTailHeightTests.swift",
            "Tests/Views/DesignPillTests.swift",
            "Tests/Views/LogTailScrollerReserveTests.swift",
            "Tests/Views/CheckLogRoomProbe.swift",
        ]
        for path in places {
            let code = try code(at: path)
            let own = Self.rawMetricReads.filter { code.contains($0) }
            #expect(own.isEmpty, "\(path) si čte metriku sám: \(own.joined(separator: ", "))")
            #expect(code.contains("FontMetric.shared"), "\(path) nebere metriku z `FontMetric`")
        }
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
        /// Jen kód — řádkové komentáře jsou pryč, protože o metrice se v nich mluví.
        let code: String
    }

    private static let repository = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    private func code(at path: String) throws -> String {
        let text = try String(contentsOf: Self.repository.appending(path: path), encoding: .utf8)
        return Self.stripped(text)
    }

    private static func stripped(_ text: String) -> String {
        // `TextLines`, ne `split(separator: "\n")` — pravidlo repa platí i v testech.
        TextLines.content(text)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    private func appSources() throws -> [Source] {
        let root = Self.repository.appending(path: "App")
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else {
            throw SourceError.unreadable(root.path)
        }
        var files: [Source] = []
        for case let url as URL in walker where url.pathExtension == "swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            let path = "App/" + url.path.replacingOccurrences(of: root.path + "/", with: "")
            files.append(Source(path: path, code: Self.stripped(text)))
        }
        guard !files.isEmpty else { throw SourceError.unreadable(root.path) }
        return files
    }

    private enum SourceError: Error {
        case unreadable(String)
    }
}
