import Foundation
import Testing

@testable import PRism

/// **Itinerář stojí vedle všech tabů, ne uvnitř `Změněných souborů`** (#506, druhé kolo) — a co to
/// ostatním tabům ubere.
///
/// Připomínka z proklikání zněla takhle: *„když se z něj překliknu na kontroly, tak to celý zmizí,
/// a pak musím zdlouhavě se překlikávat zpátky.“* Sloupec je průvodce review, a průvodce, který
/// mizí právě tehdy, když podle něj člověk někam odešel, není průvodce.
///
/// ## Co se tady dá tvrdit a co ne
///
/// **Že je sloupec v každém tabu, se tvrdí nad zdrojáky, ne nad kresbou** — a je to rozhodnutí,
/// ne obcházení: kolony jsou SwiftUI a v hostovaném okně se z accessibility tree přečíst nedají
/// (změřeno u #546, `DiffCodeColumnWidthTests`). Tvrzení „sloupec nezávisí na tabu“ je přitom
/// **strukturální**: staví se **před** `switch tab` a v žádné jeho větvi nestojí, takže se do něj
/// podmínka na tab nedá propašovat, aniž by tahle stráž spadla. Jak sloupec vedle `Kontrol`
/// a `Konverzace` **vypadá**, ukazují rendery (viz `docs/testovani.md`).
///
/// **Kolik to ubere, se počítá produkční funkcí** — `Policy.treeColumnWidth` a `widthWithItinerary`,
/// ne odečítáním v testu.
@Suite("Itinerář vedle všech tabů (#506)")
struct ItineraryEveryTabTests {
    /// Plocha tabu na výchozím okně: 1100 minus rail 52 — tatáž hodnota, ze které počítá zákres,
    /// `ItineraryColumnRoomTests` a `CommitPanelRoomTests`.
    private let tabWidth = 1_047.0

    // MARK: - Kolik to ubere ostatním tabům

    /// **Cena je jedno číslo pro všech osm tabů**: 260 bodů rozložený, 34 složený.
    ///
    /// Že je to jedno číslo, není zjednodušení — je to podmínka. Sloupec s šířkou závislou na tabu
    /// by okno přeskládal při každém přepnutí záložky, tedy zrovna při tom pohybu, kvůli kterému
    /// #506/2 vzniklo.
    ///
    /// **Naměřeno na výchozím okně** (štěrbina 1 047 b): rozložený sloupec nechá tabu **787 b**
    /// (75 %), složený **1 013 b** (97 %). Ostatní taby jsou řádky a próza, takže se ta ztráta
    /// projeví zúžením, ne ořezáním — jediný tab, u kterého se dá spočítat, o co člověk přišel,
    /// je diff, a ten je změřený ve znacích v `ItineraryColumnRoomTests`.
    @Test("Sloupec ubere každému tabu 260 bodů, složený 34")
    func theColumnCostsTheSameInEveryTab() {
        let expanded = Policy.treeColumnWidth(expanded: true)
        let collapsed = Policy.treeColumnWidth(expanded: false)
        #expect(expanded == 260)
        #expect(collapsed == 34)
        #expect(tabWidth - expanded == 787)
        #expect(tabWidth - collapsed == 1_013)
        // Do #506/2 platily tuhle cenu jen `Změněné soubory`; od #506/2 ji platí všech osm.
        #expect(PullRequestTab.allCases.count == 8)
    }

    /// **Společná šířka se dopočítá přesně, ne odhadem** (`Policy.widthWithItinerary`).
    ///
    /// Rozhodnutí o kolonách se musí ptát na šířku, o kterou se sloupec, kód a okraj **dělí** —
    /// jinak by se sloupec skládal podle toho, co po něm zbylo, tedy sám podle sebe. Počítá ji
    /// ten, kdo sloupec kreslí (detail PR), a podává ji prostředím (`sideColumnsWidth`); tvrzení
    /// níž je o tom, že z obou stavů sloupce vyjde **tatáž** společná šířka, takže se rozhodnutí
    /// nerozkmitá.
    @Test("Ze štěrbiny bez sloupce vyjde zpátky společná šířka")
    func theSharedWidthRoundTrips() {
        for shared in [620.0, 700, 1_047, 1_422, 3_388] {
            for expanded in [true, false] {
                let slot = shared - Policy.treeColumnWidth(expanded: expanded)
                #expect(
                    Policy.widthWithItinerary(slot: slot, expanded: expanded) == shared,
                    "společná \(shared), rozložený \(expanded): štěrbina \(slot)"
                )
            }
        }
    }

    /// **Nezměřená štěrbina je `nil`, ne 260.** V prvním průchodu dá `GeometryReader` nulu, a bez
    /// téhle podmínky by z ní vyšla společná šířka 260 — tedy „složit všechno“ — a vzápětí by se
    /// to rozložilo zpátky. `DiffView` pak spadne na svou vlastní štěrbinu a `diffSideColumns`
    /// na `nil` odpovídá jako do #503: rozhoduje jen pohled.
    @Test("Nulová štěrbina znamená nezměřeno, ne úzké okno")
    func anUnmeasuredSlotIsNil() {
        #expect(Policy.widthWithItinerary(slot: 0, expanded: true) == nil)
        #expect(Policy.widthWithItinerary(slot: -10, expanded: false) == nil)
        let unmeasured = Policy.diffSideColumns(layout: .unified, hasMargin: false, available: nil)
        #expect(unmeasured.tree)
        // **A nula je totéž co `nil`, ne nejužší okno** (#506/3). `DiffView` spadne na vlastní
        // štěrbinu (`sharedWidth ?? slotWidth`) a ta v prvním průchodu **nulu propustí** — z ní by
        // vyšlo „složit všechno“, a od #506 se to rozhodnutí ukládá do volby člověka, takže by to
        // nebyl problém jednoho snímku.
        for zero in [0.0, -1] {
            let columns = Policy.diffSideColumns(layout: .unified, hasMargin: false, available: zero)
            #expect(columns.tree, """
                Šířka \(zero) sloupec složila, tedy se vzala jako úzké okno — má se brát jako \
                „nikdo to nezměřil“.
                """)
        }
    }

    // MARK: - Stráž nad zdrojáky

    /// **Sloupec se staví před `switch tab` a v žádné jeho větvi nestojí.**
    ///
    /// Tohle je to tvrzení, které se rozbije potichu: vrátit sloupec do jedné větve `switch`e je
    /// jednořádková úprava, aplikace po ní běží a vada se pozná jedině tím, že si člověk klikne na
    /// `Kontroly`. Hledá se nad **kódem bez mezer** (`Source.condensed`, #490/#550), protože ve
    /// Swiftu je mezera uvnitř volání volná.
    @Test("Levý sloupec stojí mimo switch nad taby")
    func theColumnIsBuiltOutsideTheTabSwitch() throws {
        // **Hledá se uvnitř `content`**, ne v celém souboru: `switch tab` je i v `badge(in:)`
        // (odznak u záložky), a ten stojí o sto řádků výš — porovnávat s ním by neznamenalo nic.
        let content = try Self.detailContent()
        let column = try #require(content.range(of: "itineraryColumn"))
        let tabSwitch = try #require(content.range(of: "switchtab{"))
        #expect(
            column.lowerBound < tabSwitch.lowerBound,
            "`itineraryColumn` stojí až za `switch tab` — pak je sloupec součástí obsahu tabu."
        )
        // A v žádné větvi `switch`e: kdyby se sloupec kreslil `case`em, byl by pod ním.
        for tab in ["case.filesChanged:", "case.overview:", "case.checks:", "case.conversation:",
                    "case.commits:", "case.findings:", "case.progress:", "case.ask:"] {
            let branch = try #require(content.range(of: tab))
            let line = content[branch.upperBound...].prefix(60)
            #expect(
                !line.contains("itineraryColumn"),
                "Větev \(tab) staví sloupec sama — pak není v každém tabu týž."
            )
        }
    }

    /// **A `DiffView` sloupec nekreslí vůbec.** Zůstal mu jen okraj s kartami; kdyby se sloupec
    /// vrátil dovnitř, stál by v tabu `Commity` dvakrát (jednou z detailu, jednou z diffu commitu)
    /// a kolona kódu by se počítala o 260 bodů vedle.
    @Test("Sloupec s itinerářem kreslí jedno místo")
    func onlyOnePlaceDrawsTheColumn() throws {
        let views = try Self.sources(under: "App/Views")
        let drawing = views.filter {
            $0.condensed.contains("ItineraryColumnView(") || $0.condensed.contains("ItineraryRailView(")
        }
        #expect(
            drawing.map(\.path) == ["PullRequestDetailView.swift"],
            "Sloupec staví \(drawing.map(\.path)) — má ho stavět jedině detail PR."
        )
        let diff = try #require(views.first { $0.path == "DiffView.swift" })
        #expect(!diff.condensed.contains("ReviewItineraryView("))
        #expect(!diff.condensed.contains("ItineraryColumnView("))
        #expect(!diff.condensed.contains("ItineraryRailView("))
        // **A společnou šířku si `DiffView` nedopočítává** — dostane ji prostředím. Přičtení
        // `treeColumnWidth` uvnitř diffu by v okně sedělo, ale v hostu **bez** sloupce vedle sebe
        // by rozhodnutí měnilo svůj vlastní vstup, a to umí kmitat (rozložený sloupec kolonu
        // složí, složený ji rozloží).
        #expect(!diff.condensed.contains("Policy.widthWithItinerary"))
        #expect(diff.condensed.contains("sharedWidth??slotWidth"))
    }

    /// **Složený proužek počet nekreslí, dokud ho nikdo nezná.** `0 souborů` by tvrdilo „tenhle
    /// pull request nic nemění“ o PR, u kterého se to zatím neví — a od #506/2 je to případ, který
    /// nastat umí: sloupec stojí i v tabech, kde se diff nenačítá, takže se proužek kreslí nad
    /// nenačteným diffem. Je to tatáž hranice, na které mlčí `Policy.fileStopDetail`.
    @Test("Nad nenačteným diffem je počet na proužku nil, ne nula")
    func theRailStaysSilentWithoutADiff() throws {
        #expect(Policy.fileStopDetail(read: 0, of: 0) == nil)
        let source = try Self.detailSource()
        #expect(
            source.condensed.contains("ItineraryRailView(files:loadedDiff?.files.count)"),
            "Proužek dostává počet jinak než z nepovinného diffu — nad nenačteným pak vyjde nula."
        )
    }

    /// **Uložený stav sloupce čte jediný uzel** (#506, třetí kolo).
    ///
    /// Do třetího kola visel `@AppStorage("diffTreeExpanded")` na `PullRequestDetailView` **i** na
    /// `DiffView`. Dva uzly nad jedním klíčem nejsou samy o sobě vada (je to uložená předvolba),
    /// ale byly to dvě místa, která o jedné hodnotě **rozhodují** — a rozešla se potichu: diff při
    /// každém vzniku uplatnil rozhodnutí #188 na stav, který kreslí detail, a přepsal tím `⌘1`.
    /// Od té doby chodí stav i stráž do diffu **parametrem** (`DiffColumnActions`).
    @Test("Uložený stav sloupce čte jediný uzel")
    func oneNodeOwnsTheStoredColumnState() throws {
        let key = "@AppStorage(\"diffTreeExpanded\")"
        let owners = try Self.sources(under: "App").filter { $0.condensed.contains(key) }
        #expect(
            owners.map(\.path) == ["Views/PullRequestDetailView.swift"],
            """
            Klíč `diffTreeExpanded` čte \(owners.map(\.path)) — má ho číst jedině ten, kdo sloupec \
            kreslí. Druhý uzel nad tím klíčem je cesta, kterou se volba člověka přepíše.
            """
        )
    }

    /// **A do stavu sloupce se píše ze čtyř vyjmenovaných míst.**
    ///
    /// Tři jsou z kliknutí — `⌘1` (`columnShortcut`), `collapse` z hlavičky sloupce a proužek,
    /// kterým se otevře zpátky — a čtvrté je binding pro automatiku. Pátý zapisovatel se pozná
    /// jedině tím, že se sloupec „někdy“ zavře, takže je to přesně ten druh tvrzení, který se
    /// rozbije potichu.
    @Test("Do stavu sloupce píšou vyjmenovaná místa")
    func onlyTheNamedPlacesWriteTheColumnState() throws {
        let detail = try Self.detailSource()
        #expect(detail.condensed.ranges(of: "isColumnExpanded.toggle()").count == 1, "`⌘1` má být jedno.")
        // Ve složených závorkách, tedy **zápis z closury** — samotné `isColumnExpanded=true` je
        // v souboru dvakrát a to druhé je výchozí hodnota `@AppStorage`, ne zápis.
        #expect(detail.condensed.ranges(of: "{isColumnExpanded=true}").count == 1, "Proužek má být jeden.")
        #expect(detail.condensed.ranges(of: "{isColumnExpanded=false}").count == 1, "`collapse` má být jeden.")
        // Binding pro automatiku — **jeden**, a jde do `DiffView`u pull requestu. Diff commitu ho
        // dostat nesmí: kreslí se v tabu `Commity`, kde sloupec stojí taky, a přepsal by ho.
        #expect(
            detail.condensed.ranges(of: "expanded:$isColumnExpanded").count == 1,
            "Binding pro automatiku má být jeden — druhý znamená druhý `DiffView`, který stav mění."
        )
        let commit = try #require(Self.sources(under: "App/Views").first { $0.path == "CommitDiffView.swift" })
        #expect(
            !commit.condensed.contains("columnActions"),
            "Diff commitu dostal `columnActions` — pak sloupcem hýbe i tab, ve kterém není o čem."
        )
    }

    // MARK: - Klik na soubor

    /// **Klik na soubor ve sloupci jde tou hotovou cestou, kterou skáče mapa PR** (#501) — a to je
    /// celá oprava druhé připomínky z proklikání (*„když kliknu na soubor tak se nic nestane“*).
    ///
    /// Do #506/2 měl sloupec vlastní skok (`withAnimation { proxy.scrollTo(file.id, anchor: .top) }`)
    /// a ten byl vadný na dvou místech, obojí vyjmenované u #152: **animovaný jediný průchod**
    /// (druhý posun ho utne, takže skok skončí dva až třináct bodů od místa, kde začal) a **žádný
    /// druhý průchod s přeměřenými rozměry**. Odsud vede jediná cesta: `jump(toFile:)` → kotva
    /// z `DiffRow.anchor` → `scroll(to:)`, tedy `scrollTarget` a `task(id:)` v `DiffView` se dvěma
    /// průchody a bez animace.
    ///
    /// Tvrdí se to nad zdrojáky, protože ten skok je `@State` detailu: co se stalo, se v harnessu
    /// nedá přečíst. **Co změřit jde**, je kam cíl přistane (`DiffJumpAnchorTests`) a že kotva na
    /// soubor je `file.id` (`DiffRowTests`).
    @Test("Sloupec skáče na soubor cestou mapy PR, ne vlastní")
    func theFileClickGoesThroughTheProvenPath() throws {
        let source = try Self.detailSource()
        #expect(
            source.condensed.contains("jump:{jump(toFile:$0.displayPath)}"),
            "Sloupec neskáče přes `jump(toFile:)` — pak má vlastní skok a #152 se ho netýká."
        )
        // `scroll(to:)` je to místo, kde se **napřed přepne tab**: klik na soubor z `Kontrol` má
        // skončit v `Změněných souborech`, ne nastavit cíl do tabu, ve kterém diff není.
        #expect(source.condensed.contains("store.setDetailTab(.filesChanged,for:pullRequest.id)"))
        #expect(source.condensed.contains("scrollTarget=anchor"))
        // A sloupec **nemá vlastní `scrollTo`**: kdyby ho měl, obešel by dva průchody z #152.
        #expect(!source.condensed.contains("proxy.scrollTo"))
    }

    /// **Sbalený soubor se rozbalí dřív, než se nastaví cíl** — jinak by se ukázala jen jeho
    /// hlavička (a od #500 je sbalený každý prošlý soubor, takže je to běžný stav, ne výjimka).
    ///
    /// Rozbaluje `anchor(inFile:line:)`, tedy tatáž funkce jako u skoku z nálezu a z palety;
    /// pořadí je podmínka, ne detail — `scrollTo` na id, které v seznamu ještě není, tiše nic
    /// neudělá.
    @Test("Kotva na soubor rozbalí sbalený soubor")
    func theAnchorUnfoldsAFoldedFile() throws {
        let source = try Self.detailSource()
        let anchor = try #require(source.condensed.range(of: "funcanchor(inFilepath:String,line:Int?)"))
        let body = source.condensed[anchor.upperBound...].prefix(600)
        let unfold = try #require(body.range(of: "store.unfold("))
        let returns = try #require(body.range(of: "returnanchor"))
        #expect(
            unfold.lowerBound < returns.lowerBound,
            """
            `anchor(inFile:line:)` vrací kotvu dřív, než soubor rozbalí — skok pak míří na id, \
            které v seznamu ještě není.
            """
        )
    }

    // MARK: - Čtení zdrojáků

    /// Kód **bez řádkových komentářů a bez mezer** — o sloupci se v komentářích píše, a vysvětlení
    /// nemá být porušením pravidla, které vysvětluje.
    private struct Source {
        let path: String
        let condensed: String
    }

    /// Tělo `content` v detailu PR — od jeho hlavičky po `terminalDrawer`, tedy ta jedna
    /// vlastnost, ve které se o rozvržení záložky rozhoduje.
    private static func detailContent() throws -> Substring {
        let source = try detailSource()
        guard let start = source.condensed.range(of: "privatevarcontent:someView{"),
              let end = source.condensed.range(of: "privatevarterminalDrawer")
        else { throw SourceError.unreadable("content v PullRequestDetailView.swift") }
        return source.condensed[start.upperBound..<end.lowerBound]
    }

    private static func detailSource() throws -> Source {
        let views = try sources(under: "App/Views")
        guard let detail = views.first(where: { $0.path == "PullRequestDetailView.swift" }) else {
            throw SourceError.unreadable("PullRequestDetailView.swift")
        }
        return detail
    }

    private static func sources(under folder: String) throws -> [Source] {
        let root = repository.appending(path: folder)
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else {
            throw SourceError.unreadable(root.path)
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
                    path: url.path.replacingOccurrences(of: root.path + "/", with: ""),
                    condensed: code.filter { !$0.isWhitespace }
                )
            )
        }
        guard !files.isEmpty else { throw SourceError.unreadable(root.path) }
        return files
    }

    /// Kořen repa z cesty tohohle souboru — `Tests/Views/…`, tedy tři úrovně nad.
    private static let repository = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    private enum SourceError: Error {
        case unreadable(String)
    }
}
