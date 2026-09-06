import AppKit
import SwiftUI
import Testing

@testable import PRism

/// Dráha v řádku seznamu (#509) — **co se dá tvrdit měřením a nad zdrojáky**.
///
/// Tři třídy tvrzení, a dvě z nich se dají pokazit **potichu**:
///
/// - **výška řádku se nemění.** Tečky mají osm bodů a řádek dvě řádky textu, takže se do nich
///   vejdou — ale kdyby ne, blok `Moje PR` by se posunul a nešlo by poznat, čím. Měří se
///   `fittingSize` mimo obrazovku, ne odhadem z konstant (tatáž konstrukce jako
///   `QueueMapStripTests`);
/// - **v nejužším okně zůstává řádek na jedné řádce** — i s mapou PR, tečkami, pilulkou
///   a `Prompt →` vedle sebe. Tohle je ta věc, kterou #509 do řádku doopravdy přidává, a jestli
///   se to nevejde, pozná se to jedině měřením;
/// - **na cizím řádku se nekreslí nic** — a **druhé mapování stavu na barvu v okně není**;
///   obojí se tvrdí adresně, ne obrázkem.
@Suite("Dráha v řádku seznamu (#509)")
@MainActor
struct OwnLoopRowRenderTests {
    // MARK: - Měřená výška a šířka

    @Test("Tečky ani pilulka výšku řádku nezvednou")
    func doesNotGrowTheRow() {
        #expect(height(of: row(loop: loop())) == height(of: row(loop: nil)))
    }

    @Test("V nejužším okně zůstává řádek s dráhou na jedné řádce")
    func fitsTheNarrowestWindow() {
        // 636 bodů je obsah nejužšího okna bez railu — tam se tečky tlučou o místo s titulkem,
        // mapou PR a `Prompt →`.
        let narrow = height(of: row(loop: loop()), width: 636)
        let wide = height(of: row(loop: loop()), width: 900)

        #expect(narrow == wide, "v 636 b vyšlo \(narrow), v 900 b \(wide)")
        #expect(narrow == height(of: row(loop: nil), width: 636))
    }

    /// I s **nejdelším** slovem, které dráha umí vydat. Pilulka nemá `fixedSize` schválně
    /// (ustupovat má ona, ne titulek), takže tohle je tvrzení o tom, že se do řádku vejde bez
    /// zalomení celého `HStack`u.
    @Test("Nejdelší slovo dráhy řádek nezalomí")
    func fitsTheLongestWord() {
        let longest = OwnLoopRow(
            dots: OwnLoop.Station.allCases.map { .init(station: $0, state: .idle) },
            word: "Zadání 128 k předání",
            tone: .running
        )

        #expect(height(of: row(loop: longest), width: 636) == height(of: row(loop: nil), width: 636))
    }

    /// Tečky si o velikost **říkají samy a pevně** (#375, #220): v řádku líného seznamu se
    /// nevyjednává. Šířka se **počítá z počtu stanic**, takže by se po ubrání šesté a sedmé
    /// stanice (#508, čtvrté kolo) nemusela hledat zapsaná v konstantě.
    @Test("Pruh teček má pevných 52 × 8 bodů")
    func hasAFixedSize() {
        let hosting = NSHostingView(rootView: OwnLoopDots(row: loop()))

        #expect(OwnLoopDots.width == 52)
        #expect(hosting.fittingSize == CGSize(width: OwnLoopDots.width, height: OwnLoopDots.dot))
    }

    // MARK: - Co řádek kreslí a co ne

    @Test("Cizí řádek tečky nekreslí, i když mu je někdo podstrčí")
    func foreignRowDrawsNoDots() {
        // Řádek dráhu **dostává**, takže se na vlastnictví ptá i on — jinak by stačilo jedno
        // zapomenuté `ownership == .mine` u volajícího a tečky by se objevily nad cizí větví.
        #expect(row(loop: loop(), ownership: .theirs).showsLoop == nil)
        #expect(row(loop: loop()).showsLoop != nil)
        #expect(row(loop: nil).showsLoop == nil)
        // Dráha bez stanic je díra v řádku, ne odpověď — tatáž kontrola jako u mapy PR (#502).
        #expect(row(loop: OwnLoopRow(dots: [], word: "hotovo", tone: .done)).showsLoop == nil)
    }

    /// Hrana řádku na vlastním PR nese **aktivní stanici**, ne stav mého review (#509). Právě
    /// tenhle případ je celý důvod: čisté review nad spadlým CI mělo do #509 zelenou hranu.
    @Test("Hrana vlastního řádku bere barvu ze stanice, cizího ze stavu review")
    func stripeFollowsTheActiveStation() {
        let failing = OwnLoopRow(
            dots: OwnLoop.Station.allCases.map { .init(station: $0, state: .done) },
            word: "CI 1 neprošel",
            tone: .failed
        )

        #expect(row(loop: failing, state: .clean).stripe == LanePhaseChip.tint(of: .failed))
        // Cizí řádek se nemění: tam je stav mého review celá odpověď.
        #expect(
            row(loop: failing, state: .clean, ownership: .theirs).stripe
                == ReviewStateAppearance.color(of: .clean)
        )
    }

    /// `Prompt →` je plné akcentové tlačítko **jen tam, kde je co předat** (#509). Bez toho by
    /// v bloku `Moje PR` svítil akcent na každém řádku a přestal ukazovat na cokoli.
    @Test("Akcent si `Prompt →` bere jedině s nepředanou prací")
    func promptIsAccentedOnlyWithPendingWork() {
        #expect(row(loop: loop(), pending: 6).promptIsPrimary)
        #expect(!row(loop: loop(), pending: 0).promptIsPrimary)
        // Na cizím řádku se `Prompt →` nekreslí vůbec, takže se na akcent nemá kdo ptát.
        #expect(!row(loop: nil, pending: 6, ownership: .theirs).promptIsPrimary)
    }

    // MARK: - Jedno mapování stavu na barvu

    /// **Tečka si barvu nesází sama.** Kdyby ano, rozešel by se odstín `hotovo` v řádku
    /// s odstínem `hotovo` v kapsli dráhy tak, že by si toho všiml jedině člověk, který vidí
    /// obojí naráz. Tvrdí se to nad zdrojáky, protože `Color` se v harnessu neporovnává.
    @Test("Barvu tečky vydává LanePhaseChip, ne OwnLoopDots")
    func onlyOnePlaceMapsStateToColour() throws {
        let dots = try Self.condensed(at: "Views/OwnLoopDots.swift")

        #expect(dots.contains("LanePhaseChip.dotFill("))
        #expect(dots.contains("LanePhaseChip.dotStroke("))
        // Žádný token palety naholo: kdyby si tečka sáhla na `Palette.ok`, byla by to druhá
        // odpověď na „jakou barvu má hotová stanice“.
        #expect(!dots.contains("Palette."), "OwnLoopDots si sahá na paletu přímo")
    }

    // MARK: - Stráž: kde se kreslí řádek, tam je i dráha

    /// **Řádek se kreslí na třech místech** (#512) a dráha musí být na všech (#509). Za běhu se
    /// to tvrdit nedá — `body` je neprůhledný typ —, takže se to čte ze zdrojáků, tak jako
    /// `PullRequestRowSnoozeWiringTests`.
    @Test("Každé kreslení řádku fronty mu předává dráhu")
    func everyRowSiteWiresTheLoop() throws {
        var offenders: [String] = []
        var sites = 0
        for source in try Self.sources() where source.path != Self.home {
            // **Čtou se argumenty toho volání, ne výskyty v souboru.** Prosté počítání
            // `loop:` (tak to dělá `PullRequestRowSnoozeWiringTests`) by tady vydalo nesmysl:
            // seznam si řádky předskládává do `ListRow`, takže v něm jméno `loop` stojí třikrát
            // a volání je jedno. Vyzvedne se proto text mezi závorkami každého `PullRequestRow(`.
            for arguments in source.constructions(of: "PullRequestRow(") {
                sites += 1
                // Pojistka proti rozvahám nad špatně vyzvednutým textem: kdyby se závorky
                // rozešly, tenhle argument by tam nebyl a stráž by zezelenala nad prázdnem.
                if !arguments.contains("pullRequest:") {
                    offenders.append("\(source.path): argumenty se nepodařilo přečíst")
                    continue
                }
                if !arguments.contains("loop:") { offenders.append("\(source.path)") }
            }
        }
        #expect(sites == 3, "míst, kde se kreslí řádek fronty, je \(sites)")
        #expect(
            offenders.isEmpty,
            """
            Řádek fronty se tu kreslí bez `loop:`, takže se v tom místě u vlastního PR nepozná, \
            kde ve smyčce stojí (#509). Předej `store.ownLoopRow(for:handoff:)`. \
            Nálezy: \(offenders.sorted().joined(separator: ", "))
            """
        )
    }

    /// Pojistka proti stráži, která zezelená tím, že přestane číst — a zároveň tvrzení o tom,
    /// **na kolika místech** se řádek kreslí (tři, #512).
    @Test("Stráž doopravdy čte zdrojáky a vyzvedává celé volání")
    func theGuardReallyReadsTheSources() throws {
        let sources = try Self.sources()
        #expect(sources.count > 100, "Čekaly se stovky zdrojáků, přišlo \(sources.count).")

        let places = sources
            .filter { $0.path != Self.home && !$0.constructions(of: "PullRequestRow(").isEmpty }
            .map(\.path)
            .sorted()
        #expect(
            places == [
                "Views/BoardView.swift",
                "Views/HomeView.swift",
                "Views/PullRequestListView.swift",
            ],
            "Místa, kde se kreslí řádek fronty, se změnila: \(places)"
        )

        // A vyzvednutí doopravdy vrací **argumenty jednoho volání**, ne zbytek souboru:
        // v seznamu je za tím voláním ještě `ListRow` s vlastním `loop:`, takže by prostý
        // sken do konce souboru vypadal stejně zeleně a netvrdil by nic.
        let list = try #require(sources.first { $0.path == "Views/PullRequestListView.swift" })
        let arguments = list.constructions(of: "PullRequestRow(")
        #expect(arguments.count == 1)
        #expect(arguments.first?.contains("snoozeAction:") == true)
        #expect(arguments.first?.contains("privatestructListRow") == false)
    }

    /// **`Policy.handoff` se na řádek počítá jednou, ne dvakrát** (#509) — a je to půlka téhle
    /// změny, ne úklid. Zdvojení by v seznamu nebylo konstanta jako u jednoho PR v hlavičce
    /// (#508), ale násobek počtu vlastních PR. Naměřená čísla jsou v `docs/testovani.md`.
    @Test("Dráha si v seznamu bere už spočítaný report předání")
    func theListReusesTheHandoffReport() throws {
        for path in ["Views/PullRequestListView.swift", "Views/HomeView.swift", "Views/BoardView.swift"] {
            let source = try Self.condensed(at: path)
            #expect(
                source.contains("ownLoopRow(for:") && source.contains("handoff:handoff)"),
                "\(path) si dráhu nebere z už spočítaného reportu"
            )
        }
        // A bezparametrová `ownLoop(for:)` (ta, která si report skládá sama) se ze seznamu
        // nevolá — je pro hlavičku otevřeného PR, kde je jeden.
        let callers = try Self.sources()
            .filter { $0.condensed.contains("ownLoop(for:") }
            .map(\.path)
            .sorted()
        #expect(
            callers == ["Store/AppStore+OwnLoop.swift", "Views/PullRequestDetailView.swift"],
            "dráhu si bez reportu skládá \(callers)"
        )
    }

    // MARK: - Pomůcky

    private func loop(
        _ states: [ReviewerLane.PhaseState] = [.done, .running, .idle, .idle, .idle],
        word: String = "Zadání 6 k předání",
        tone: ReviewerLane.PhaseState = .running
    ) -> OwnLoopRow {
        OwnLoopRow(
            dots: zip(OwnLoop.Station.allCases, states).map { .init(station: $0, state: $1) },
            word: word,
            tone: tone
        )
    }

    private func row(
        loop: OwnLoopRow?,
        state: ReviewState = .completed(findings: 3),
        pending: Int = 6,
        ownership: PullRequestOwnership = .mine
    ) -> PullRequestRow {
        PullRequestRow(
            pullRequest: PullRequestSummary(
                id: PRIdentifier("ondrajodas/PRism#499")!,
                title: "feat(diff): find in the diff with ⌘F",
                author: "ondrajodas",
                url: URL(string: "https://github.com/ondrajodas/PRism/pull/499")!,
                updatedAt: Date(timeIntervalSince1970: 1_000_000),
                state: .open
            ),
            reviewState: state,
            row: QueueRow(blocking: 0),
            ownership: ownership,
            openPrompt: {},
            pending: pending,
            loop: loop
        )
    }

    private func height(of row: PullRequestRow, width: Double = 900) -> Double {
        let hosting = NSHostingView(rootView: row.frame(width: width))
        return hosting.fittingSize.height
    }

    // MARK: - Čtení zdrojáků

    private static let app = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appending(path: "App")

    /// Soubor, ve kterém řádek **bydlí** — v něm je `#Preview`, tedy legitimní kreslení bez dráhy.
    private static let home = "Views/PullRequestRow.swift"

    private struct Source {
        let path: String
        /// Kód **bez řádkových komentářů a bez jediné mezery** (#490) — ve Swiftu je mezera
        /// uvnitř volání volná, takže `PullRequestRow (` je platný zápis téhož.
        let condensed: String

        func count(of needle: String) -> Int {
            condensed.components(separatedBy: needle).count - 1
        }

        /// Text mezi závorkami každého volání, které začíná `needle` (ta v sobě má otevírací
        /// závorku). Počítají se závorky, takže vnořené volání i uzávěr uvnitř argumentů volání
        /// neukončí.
        func constructions(of needle: String) -> [String] {
            var found: [String] = []
            var rest = Substring(condensed)
            while let start = rest.range(of: needle) {
                var depth = 1
                var index = start.upperBound
                while index < rest.endIndex, depth > 0 {
                    if rest[index] == "(" { depth += 1 }
                    if rest[index] == ")" { depth -= 1 }
                    index = rest.index(after: index)
                }
                // Nedovřená závorka je vada čtení, ne nález — vrací se prázdný text, který
                // v hlavní stráži spadne na pojistce `pullRequest:`.
                found.append(depth == 0 ? String(rest[start.upperBound..<index]) : "")
                rest = rest[index...]
            }
            return found
        }
    }

    private static func condensed(at path: String) throws -> String {
        let source = try sources().first { $0.path == path }
        guard let source else { throw SourceReadError.unreadable(path) }
        return source.condensed
    }

    private static func sources() throws -> [Source] {
        guard let walker = FileManager.default.enumerator(at: app, includingPropertiesForKeys: nil) else {
            throw SourceReadError.unreadable(app.path)
        }
        var files: [Source] = []
        for case let url as URL in walker where url.pathExtension == "swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            // `TextLines`, ne `split(separator: "\n")` — pravidlo repa platí i v testech.
            let code = TextLines.content(text)
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
                .joined(separator: "\n")
            files.append(
                Source(
                    path: url.path.replacingOccurrences(of: app.path + "/", with: ""),
                    condensed: code.filter { !$0.isWhitespace }
                )
            )
        }
        // Pojistka uvnitř čtení: kdyby složka přestala sedět, prošly by stráže nad prázdnem.
        guard !files.isEmpty else { throw SourceReadError.unreadable(app.path) }
        return files
    }

    private enum SourceReadError: Error {
        case unreadable(String)
    }
}
