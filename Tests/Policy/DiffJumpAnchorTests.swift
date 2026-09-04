import Testing

@testable import PRism

/// Kam se v diffu skáče a kolik místa nad cílem zůstane (#152) — čisté funkce, vyčerpávající výčet.
///
/// **Poloha v okně se tvrdí jinde** (`DiffJumpPlacementTests` nad hostovaným `DiffView`em); tady jde
/// o **vzorec**, protože ten je to, co u #152 chybělo: podíl výšky se počítal z výřezu a poloha
/// řádku v bloku do něj nevstupovala vůbec.
@Suite("Kam skočí cíl v diffu (#152)")
struct DiffJumpAnchorTests {
    /// Výška výřezu, na které se to měřilo v okně (okno 800 pt minus lišta).
    private static let viewport = 762.0
    /// Výška řádku diffu na tomhle stroji — z měření sondy, ne z písma: test má být nezávislý na
    /// metrice, jinak by tvrdil něco o `NSFont`u.
    private static let rowHeight = 16.0

    // MARK: - Kolik místa nad cílem

    @Test("Bez výšky výřezu se odstup nepočítá")
    func withoutAViewportThereIsNoOffset() {
        #expect(Policy.jumpOffset(of: .bubble, viewport: 0) == nil)
        #expect(Policy.jumpOffset(of: .searchHit, viewport: 0) == nil)
        #expect(Policy.jumpAnchorY(
            of: .searchHit,
            viewport: 0,
            metrics: Policy.jumpMetrics(of: DiffJumpSpot(id: "x"), rowHeight: 16)
        ) == nil)
    }

    /// **Výskyt hledání chce víc místa nad sebou než nález** — nález si kontext nese v bublině pod
    /// řádkem, kdežto u výskytu je kontext ten kód okolo.
    @Test("Výskyt hledání dostane třetinu shora, nález hlavičku a tři řádky")
    func theSearchHitGetsAThirdTheFindingThreeRows() {
        #expect(Policy.jumpOffset(of: .bubble, viewport: Self.viewport) == Policy.bubbleContextAbove)
        #expect(Policy.jumpOffset(of: .searchHit, viewport: Self.viewport) == Self.viewport / 3)
        #expect(
            Policy.jumpOffset(of: .searchHit, viewport: Self.viewport)!
                > Policy.jumpOffset(of: .bubble, viewport: Self.viewport)!
        )
    }

    /// V nízkém okně je „třetina shora“ i „devadesát bodů“ nesplnitelné — **strop je půlka výřezu**,
    /// tedy střed, a platí pro oba druhy cíle stejně.
    @Test("V nízkém okně je stropem střed", arguments: [DiffJumpTarget.bubble, .searchHit])
    func inALowWindowTheCeilingIsTheMiddle(target: DiffJumpTarget) {
        #expect(Policy.jumpOffset(of: target, viewport: 100) == 50)
        #expect(Policy.jumpOffset(of: target, viewport: 40) == 20)
    }

    /// Pod třetinou výřezu se u výskytu drží **podlaha** z nálezu: méně místa než hlavička a tři
    /// řádky nemá smysl, protože ukotvená hlavička souboru vršek překrývá.
    @Test("Odstup u výskytu neklesne pod odstup nálezu")
    func theSearchOffsetNeverDropsBelowTheFindingOne() {
        for viewport in stride(from: 200.0, through: 900.0, by: 50.0) {
            let bubble = Policy.jumpOffset(of: .bubble, viewport: viewport)!
            let hit = Policy.jumpOffset(of: .searchHit, viewport: viewport)!
            #expect(hit >= bubble, "výřez \(viewport): výskyt \(hit) < nález \(bubble)")
        }
    }

    // MARK: - Hlavička souboru (#506)

    /// **Klik na soubor sedne hlavičkou na hranu výřezu** — a je to jediný druh cíle, u kterého
    /// vzorec z #152 nic nepočítá.
    ///
    /// Cílem je totiž **celá sekce souboru**, tedy přímo to, co má být vidět, ne řádek uvnitř
    /// bloku. Podíl je proto nula **bez ohledu na výřez i na výšku sekce**, a ta nezávislost je
    /// podmínka, ne úspora: sekce je vysoká tisíce bodů, takže by z ní podíl 0,12 (co by vyšlo
    /// s odstupem `bubbleContextAbove`) udělal skok o stovky bodů **do** souboru.
    @Test("Hlavička souboru přistane na hraně, ať je sekce jak vysoká chce")
    func theFileHeaderLandsOnTheEdge() throws {
        #expect(Policy.jumpOffset(of: .fileHeader, viewport: Self.viewport) == 0)
        // Nula i v nízkém okně, kde je u ostatních cílů stropem střed.
        #expect(Policy.jumpOffset(of: .fileHeader, viewport: 100) == 0)
        for height in [16.0, 200, Self.viewport, 3_000, 40_000] {
            for viewport in [0.0, 100, Self.viewport] {
                let y = try #require(Policy.jumpAnchorY(
                    of: .fileHeader,
                    viewport: viewport,
                    metrics: DiffJumpMetrics(above: 0, height: height)
                ))
                #expect(y == 0, "sekce \(height) b ve výřezu \(viewport): podíl \(y)")
            }
        }
    }

    /// **A bez změřeného výřezu se nesahá po středu** — u ostatních cílů je `nil` odpověď „nevím,
    /// vezmi si střed“, u hlavičky by z toho byl skok do půlky souboru.
    @Test("Hlavička souboru nepotřebuje změřený výřez")
    func theFileHeaderNeedsNoViewport() {
        #expect(Policy.jumpAnchorY(
            of: .fileHeader,
            viewport: 0,
            metrics: DiffJumpMetrics(above: 0, height: 3_000)
        ) == 0)
        // Protějšek: u výskytu hledání `nil` být **musí**, jinak by se z něj tohle tvrzení stalo
        // slepým (tatáž hodnota pro obojí, #478).
        #expect(Policy.jumpAnchorY(
            of: .searchHit,
            viewport: 0,
            metrics: DiffJumpMetrics(above: 0, height: 3_000)
        ) == nil)
    }

    /// **Druh cíle se pozná z cíle, ne z toho, kdo ho nastavil** (#506) — bez toho by sloupec
    /// s itinerářem, který stojí mimo `DiffView`, druh předat nemohl.
    @Test("Kotva na `file.id` je hlavička, kotva na řádek ne")
    func theTargetIdentityDecidesTheKind() {
        let files = [Self.file("src/A.php"), Self.file("src/A.php.bak")]
        for requested in [DiffJumpTarget.bubble, .searchHit] {
            for file in files {
                #expect(
                    Policy.jumpTarget(of: file.id, files: files, requested: requested) == .fileHeader
                )
                // Řádek téhož souboru **hlavička není** — a `src/A.php` je prefixem
                // `src/A.php.bak`, takže se tady zároveň tvrdí, že se porovnává celé `id`.
                #expect(
                    Policy.jumpTarget(of: "\(file.id)|h0l0", files: files, requested: requested)
                        == requested
                )
            }
            // Soubor, který v diffu není (přišel commit, který ho smazal): druh se nemění.
            #expect(
                Policy.jumpTarget(of: "src/Gone.php", files: files, requested: requested) == requested
            )
        }
    }

    private static func file(_ path: String) -> FileDiff {
        FileDiff(
            oldPath: path,
            newPath: path,
            change: .modified,
            isBinary: false,
            hunks: [],
            blobs: nil
        )
    }

    // MARK: - Podíl výšky

    /// **Tohle je celá oprava #152, vyjádřená invariantem:** podíl je správný právě tehdy, když
    /// z něj vyjde **cílový řádek** v požadované výšce. Vzorec `scrollTo(anchor:)`:
    ///
    /// ```
    /// poloha řádku = a × (výřez − výška bloku) + řádky nad cílem × výška řádku
    /// ```
    @Test("Podíl posadí cílový řádek do požadované výšky, ať je v bloku kdekoli")
    func theAnchorPutsTheRowWhereTheOffsetSays() throws {
        for rows in [1, 2, 20, 47, DiffBlock.maxLines] {
            for above in 0..<rows {
                let spot = DiffJumpSpot(id: "x", above: above, rows: rows)
                let y = try #require(Policy.jumpAnchorY(
                    of: .searchHit,
                    viewport: Self.viewport,
                    metrics: Policy.jumpMetrics(of: spot, rowHeight: Self.rowHeight)
                ))
                let wanted = try #require(Policy.jumpOffset(of: .searchHit, viewport: Self.viewport))
                let block = Double(rows) * Self.rowHeight + Policy.blockInset
                let landed = y * (Self.viewport - block) + Double(above) * Self.rowHeight
                #expect(
                    abs(landed - wanted) < 0.001,
                    "blok \(rows) řádků, \(above) nad cílem: řádek přistane na \(landed), čekáno \(wanted)"
                )
            }
        }
    }

    /// **Podíl mimo `0…1` je správná odpověď, ne chyba** — u bloku vyššího než výřez se cíl jinak
    /// umístit nedá a `scrollTo` extrapolaci zvládne (změřeno, viz `jumpAnchorY`). Kdyby se sem
    /// vrátilo ořezání, tenhle test spadne první.
    @Test("U bloku vyššího než výřez podíl z rozsahu vyjde")
    func theAnchorLeavesTheUnitRangeForATallBlock() throws {
        let tall = DiffJumpSpot(id: "x", above: 0, rows: DiffBlock.maxLines)
        let y = try #require(Policy.jumpAnchorY(
            of: .searchHit,
            viewport: Self.viewport,
            metrics: Policy.jumpMetrics(of: tall, rowHeight: Self.rowHeight)
        ))
        // Blok je vyšší než výřez (964 > 762) a cíl je jeho první řádek, takže horní hrana bloku
        // musí skončit **pod** hranou výřezu — a to je záporný podíl.
        #expect(y < 0, "podíl \(y) je ořezaný, cíl skončí nad hranou výřezu")
    }

    /// Cíl, který blok není (hlavička souboru, bublina, expander), je „blok o jednom řádku“ — a to
    /// je jediná hodnota, se kterou vzorec nepočítá s cizí výškou.
    @Test("Cíl mimo blok se posadí jako jednořádkový")
    func aTargetOutsideABlockBehavesLikeOneRow() throws {
        let alone = try #require(Policy.jumpAnchorY(
            of: .bubble,
            viewport: Self.viewport,
            metrics: Policy.jumpMetrics(of: DiffJumpSpot(id: "x"), rowHeight: Self.rowHeight)
        ))
        let explicit = try #require(Policy.jumpAnchorY(
            of: .bubble,
            viewport: Self.viewport,
            metrics: Policy.jumpMetrics(of: DiffJumpSpot(id: "x", above: 0, rows: 1), rowHeight: Self.rowHeight)
        ))
        #expect(alone == explicit)
        #expect(alone > 0 && alone < 1, "u malého cíle má podíl zůstat v rozsahu")
    }

    /// Blok přesně tak vysoký jako výřez: podíl s ním nehýbe (`a × 0`), takže **není co počítat**.
    /// Nula je jediná poctivá odpověď a hlavně se nesmí vydat `inf`.
    @Test("Blok stejně vysoký jako výřez vydá nulu, ne nekonečno")
    func aBlockAsTallAsTheViewportYieldsZero() throws {
        let rows = 10
        let height = 20.0
        let viewport = Double(rows) * height + Policy.blockInset
        let y = try #require(Policy.jumpAnchorY(
            of: .bubble,
            viewport: viewport,
            metrics: Policy.jumpMetrics(of: DiffJumpSpot(id: "x", above: 3, rows: rows), rowHeight: height)
        ))
        #expect(y == 0)
        #expect(y.isFinite)
    }
}

/// Vodorovné odhalení výskytu (#152, druhé kolo proklikání) — čisté funkce, vyčerpávající výčet.
///
/// Ve split pohledu se **nezalamuje**, takže výskyt na dlouhém řádku leží za pravou hranou sloupce
/// a pruh přitom hlásí `4 z 17`. Tady se tvrdí **kdy** se posouvá a **kam**; že se ten posun
/// v okně doopravdy provede, měří `DiffJumpPlacementTests`.
@Suite("Odhalení výskytu do šířky (#152)")
struct DiffSearchRevealTests {
    private static let visible = 100.0...600.0
    private static let margin = Policy.searchRevealMargin

    /// **Nejcennější tvrzení je to negativní**: výskyt, který je vidět, sloupcem nehýbe. Vodorovnou
    /// polohu si člověk nastavil sám a přerovnat ji bez důvodu je tentýž poskok, jaký se u svislé
    /// osy zamítal.
    @Test("Výskyt, který je vidět i s rezervou, sloupcem nehýbe")
    func aVisibleMatchDoesNotMoveTheColumn() {
        #expect(Policy.horizontalReveal(match: 300...340, visible: Self.visible) == nil)
        // Přesně na hranici rezervy: pořád se nehýbe.
        #expect(Policy.horizontalReveal(
            match: (100 + Self.margin)...(600 - Self.margin),
            visible: Self.visible
        ) == nil)
    }

    /// Na hraně výřezu se **posune**, i když je technicky „vidět": bez rezervy není poznat, že
    /// výskyt pokračuje dál.
    @Test("Výskyt na hraně se posune, aby kolem sebe měl místo")
    func aMatchOnTheEdgeGetsMargin() throws {
        let left = try #require(Policy.horizontalReveal(match: 105...140, visible: Self.visible))
        #expect(left == 105 - Self.margin)
        let right = try #require(Policy.horizontalReveal(match: 560...595, visible: Self.visible))
        // Posun je levá hrana výřezu, takže se výskyt i s rezervou vejde do jeho pravé části.
        #expect(right == 595 + Self.margin - 500)
    }

    @Test("Výskyt vlevo od výřezu se přitáhne na začátek")
    func aMatchToTheLeftIsPulledBack() throws {
        let x = try #require(Policy.horizontalReveal(match: 40...80, visible: Self.visible))
        #expect(x == 40 - Self.margin)
    }

    /// **Posun nikdy nejde za začátek dokumentu**: výskyt na prvním znaku by jinak vyžadoval
    /// zápornou hodnotu a plocha by ji stejně ořízla — jen by se o tom nedalo psát test.
    @Test("Posun se nedostane před začátek řádku")
    func theOffsetNeverGoesBeforeTheStart() throws {
        let x = try #require(Policy.horizontalReveal(match: 0...30, visible: 200...700))
        #expect(x == 0)
    }

    /// Výskyt delší než výřez: vyhrává jeho **začátek**, protože se čte zleva.
    @Test("U výskytu delšího než výřez vyhrává jeho začátek")
    func aMatchWiderThanTheViewportShowsItsStart() throws {
        let x = try #require(Policy.horizontalReveal(match: 800...1600, visible: Self.visible))
        #expect(x == 800 - Self.margin)
    }

    /// Nulová šířka výřezu (sloupec se ještě nerozvrhl) — **není co odhalovat**, a hlavně se nesmí
    /// vydat nesmyslný posun.
    @Test("Bez rozvrženého sloupce se neposouvá")
    func withoutALaidOutColumnNothingMoves() {
        #expect(Policy.horizontalReveal(match: 100...200, visible: 0...0) == nil)
    }
}
