import Testing

@testable import PRism

/// **Kdo v liště nad diffem ustupuje, v jakém pořadí a na co** (#593) — čistá funkce, takže
/// vyčerpaná výčtem.
///
/// Do #593 se to nedalo tvrdit vůbec: ustupoval jediný prvek, a to tím, že jako jediný zapomněl
/// `fixedSize()`. Tady je to rozhodnutí, ne shoda okolností — a většina tvrzení níž je
/// **negativní**: že se procházení nálezů nesrazí, že se vlevo nic neusekne a že žádný prvek
/// nespadne pod mez, pod kterou by zmizel.
@Suite("Pořadí ustupování v liště diffu (#593)")
struct DiffToolbarLadderTests {
    // MARK: - Tři kategorie

    /// **Co se skládá na ikonu, co se zkracuje a co zůstane celé** — celý výčet, ne vzorek.
    @Test("Každý prvek má svou sraženou podobu")
    func floorOfEveryItem() {
        #expect(Policy.diffToolbarFloor(.navigation) == .full)
        #expect(Policy.diffToolbarFloor(.unreadable) == .short)
        #expect(Policy.diffToolbarFloor(.missingThreads) == .short)
        #expect(Policy.diffToolbarFloor(.width) == .short)
        #expect(Policy.diffToolbarFloor(.layout) == .icon)
        #expect(Policy.diffToolbarFloor(.annotate) == .icon)
        #expect(Policy.diffToolbarFloor(.search) == .icon)
        #expect(Policy.diffToolbarFloor(.fold) == .icon)
    }

    /// Vlevo stojí to, čím se diff obsluhuje — a **jedině to se nikdy neusekává**.
    @Test("Vlevo je pohled a procházení, zbytek vpravo")
    func sideOfEveryItem() {
        let leading = Policy.DiffToolbarItem.allCases.filter { Policy.diffToolbarSide($0) == .leading }
        #expect(leading == [.layout, .navigation])
    }

    // MARK: - Pořadí

    /// Pořadí je **věta o návrhu**: akce ustupují dřív než informace a věta dřív než číslo.
    @Test("Pořadí ustupování je vyjmenované, ne odvozené od pořadí kresby")
    func ladderOrder() {
        #expect(Policy.diffToolbarLadder == [
            .annotate, .search, .fold, .width, .missingThreads, .unreadable, .layout,
        ])
    }

    /// **Procházení nálezů v pořadí není** (#187, #219) — je to jediná věc v liště, která se
    /// používá při každém review.
    @Test("Procházení nálezů v pořadí ustupování není")
    func navigationNeverConcedes() {
        #expect(!Policy.diffToolbarLadder.contains(.navigation))
    }

    /// **Přepínač pohledu je až poslední**: popisky segmentů jsou celý důvod, proč to není
    /// `Picker(.segmented)`.
    @Test("Přepínač pohledu ustupuje jako poslední, popis změn jako první")
    func ladderEnds() {
        #expect(Policy.diffToolbarLadder.first == .annotate)
        #expect(Policy.diffToolbarLadder.last == .layout)
    }

    /// Dva výčty se nesmí rozejít: co má sraženou podobu, musí být v pořadí — a naopak. Kdyby
    /// v pořadí stál prvek s podobou `full`, tvářilo by se ustoupení, které nic neuspoří.
    @Test("Pořadí a sražené podoby se nerozcházejí")
    func ladderMatchesFloors() {
        let concedable = Policy.DiffToolbarItem.allCases.filter { Policy.diffToolbarFloor($0) != .full }
        #expect(Set(Policy.diffToolbarLadder) == Set(concedable))
        #expect(Policy.diffToolbarLadder.count == concedable.count)
    }

    // MARK: - Rozdělení místa

    private func measure(
        _ item: Policy.DiffToolbarItem,
        _ full: Double,
        _ floor: Double
    ) -> Policy.DiffToolbarMeasure {
        Policy.DiffToolbarMeasure(item, full: full, floor: floor)
    }

    /// Změřená plná výbava z #593 (`docs/testovani.md`, *Kolik si který prvek lišty bere*).
    private var fullKit: [Policy.DiffToolbarMeasure] {
        [
            measure(.layout, 200, 69),
            measure(.navigation, 234, 234),
            measure(.width, 127, 73),
            measure(.annotate, 95, 13),
            measure(.search, 82, 13),
            measure(.fold, 94, 51),
        ]
    }

    @Test("Když se to vejde celé, nesráží se nic")
    func nothingConcedesWhenItFits() {
        let room = Policy.diffToolbarRoom(available: 2_000, measures: fullKit)

        #expect(room.conceded.isEmpty)
        #expect(room.truncated.isEmpty)
        #expect(room.width(of: .annotate) == 95)
    }

    /// **Přestane se, jak to stačí** — ne „srazit všechno, co srazit jde“.
    @Test("Sráží se po jednom a jen dokud se to nevejde")
    func concedesOnlyAsFarAsNeeded() {
        // Plná výbava si říká o 832; ubrat 82 na popisu změn stačí.
        let room = Policy.diffToolbarRoom(available: 760, measures: fullKit)

        #expect(room.conceded == [.annotate])
        #expect(room.width(of: .search) == 82)
        #expect(room.width(of: .layout) == 200)
    }

    /// Štěrbina podlahového okna: 572 − 28 odsazení − 63 mezer.
    @Test("V podlahovém okně ustoupí pět prvků a šestý zůstane celý")
    func concedesFiveAtTheFloor() {
        let room = Policy.diffToolbarRoom(available: 481, measures: fullKit)

        #expect(room.conceded == [.annotate, .search, .fold, .width, .layout])
        #expect(room.truncated.isEmpty)
        // Procházení nálezů zůstalo celé, a to je ta podstata: ustoupilo všechno ostatní.
        #expect(room.width(of: .navigation) == 234)
        #expect(room.slack == 28)
    }

    /// Prvek, který se srazit neumí, **nespotřebuje krok** — jinak by pořadí utíkalo do prázdna.
    @Test("Prvek bez sražené podoby se přeskočí, nespotřebuje krok")
    func itemWithoutFloorIsSkipped() {
        let measures = [
            measure(.annotate, 95, 95),  // sražená podoba se nekreslí (třeba ji nikdo nedal)
            measure(.search, 82, 13),
            measure(.navigation, 234, 234),
        ]
        let room = Policy.diffToolbarRoom(available: 350, measures: measures)

        #expect(room.conceded == [.search])
        #expect(room.width(of: .annotate) == 95)
    }

    /// I když je tísně tolik, že ustoupilo všechno, **procházení zůstává celé**.
    @Test("Procházení nálezů zůstane celé i v největší tísni")
    func navigationKeepsItsWidth() {
        let room = Policy.diffToolbarRoom(available: 100, measures: fullKit)

        #expect(room.width(of: .navigation) == 234)
        #expect(!room.conceded.contains(.navigation))
        #expect(!room.truncated.contains(.navigation))
    }

    /// **Vlevo se neusekává nic** — ani přepínač pohledu, který se srazit umí.
    @Test("Useknout se dá jedině to, co stojí vpravo")
    func onlyTrailingItemsAreTruncated() {
        let room = Policy.diffToolbarRoom(available: 100, measures: fullKit)

        #expect(room.width(of: .layout) == 69)
        #expect(!room.truncated.contains(.layout))
        #expect(room.truncated.allSatisfy { Policy.diffToolbarSide($0) == .trailing })
    }

    /// Lišta se všemi osmi prvky (obě vzácná varování naráz) v podlahovém okně — **jediný stav,
    /// ve kterém se ustoupením nevejde**, takže se z ní ubírá.
    private var extremeKit: [Policy.DiffToolbarMeasure] {
        fullKit + [measure(.unreadable, 210, 63), measure(.missingThreads, 324, 68)]
    }

    /// **Nic nezmizí.** Prvek scvrknutý na nulu je prvek, který se ztratil — a prvek, ze kterého
    /// se ubralo, se pozná: stojí v `truncated` a je užší než svá sražená podoba.
    @Test("Ani v nejhorším případě nespadne prvek pod svou mez")
    func nothingFallsBelowTheFloor() {
        let room = Policy.diffToolbarRoom(available: 300, measures: extremeKit)

        #expect(room.widths.count == extremeKit.count)
        for measure in extremeKit {
            let width = room.width(of: measure.item)
            #expect(width > 0)
            if room.truncated.contains(measure.item) {
                #expect(width >= Policy.diffToolbarItemFloor)
                #expect(width < measure.floor)
            } else {
                #expect(width == measure.full || width == measure.floor)
            }
        }
    }

    /// Ubírá se **nejširšímu**, ne prvnímu v pořadí kresby: jinak by o tom, kdo přišel o body,
    /// rozhodovalo, v jakém pořadí se prvky do lišty přidávaly.
    @Test("Useknutí bere z nejširšího prvku, ne z prvního")
    func truncationTakesFromTheWidest() {
        let measures = [
            measure(.navigation, 100, 100),
            measure(.width, 200, 200),
            measure(.search, 40, 40),
        ]
        let room = Policy.diffToolbarRoom(available: 300, measures: measures)

        #expect(room.width(of: .width) == 160)
        #expect(room.width(of: .search) == 40)
        #expect(room.truncated == [.width])
    }

    /// Na pořadí v seznamu měr to nezávisí — jinak by dvě stejné lišty vyšly různě. Měří se to
    /// na tom stavu, kde se **ubírá**: tam by se pořadí projevilo.
    @Test("Na pořadí v seznamu měr výsledek nezávisí")
    func resultDoesNotDependOnOrder() {
        let forward = Policy.diffToolbarRoom(available: 400, measures: extremeKit)
        let backward = Policy.diffToolbarRoom(available: 400, measures: extremeKit.reversed())

        #expect(forward == backward)
        #expect(!forward.truncated.isEmpty)
    }

    /// Zbytek nesmí být záporný: „vejde se to o −40 bodů“ není údaj.
    @Test("Zbylé místo nikdy není záporné")
    func slackIsNeverNegative() {
        #expect(Policy.diffToolbarRoom(available: 10, measures: fullKit).slack == 0)
    }
}
