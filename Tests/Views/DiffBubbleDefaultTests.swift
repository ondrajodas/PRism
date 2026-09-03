import AppKit
import SwiftUI
import Testing

@testable import PRism

/// **Výchozí stav diffu jsou bubliny pod řádky, okraj je za přepínačem** (#548).
///
/// #503 postavilo nálezy do okraje vpravo a udělalo z toho výchozí stav. Z provozu vyšlo, že se
/// ta kolona platí **300 body natrvalo** — i v souborech bez nálezu, tedy skoro pořád —, takže se
/// výchozí hodnota přepínače `Nálezy pod řádky` otočila zpátky na zapnuto. Okraj v kódu zůstává.
///
/// ## Co se měří a proč zrovna to
///
/// Kolony diffu jsou SwiftUI, takže se z hostovaného okna nedají přečíst jako rámečky; přečíst se
/// dá **plocha obsahu** (`NSScrollView`, viz `NSView.diffContentArea()`) a **výška jejího
/// dokumentu**. Obojí se v těch dvou stavech liší o řád víc než rezerva na posuvník:
///
/// - **šířka** — okraj je 300 b, takže se kolona kódu o ně zkrátí;
/// - **výška dokumentu** — bublina stojí v toku pod svým řádkem, karta v okraji ne, takže je
///   obsah s bublinami vyšší.
///
/// **Výchozí hodnota se tvrdí výčtem tří stavů klíče**, ne jedním tvrzením: nic uloženo,
/// uloženo `true` (bubliny) a uloženo `false` (okraj). Výchozí stav se musí chovat **stejně jako
/// zapnutý přepínač** a zároveň **jinak než okraj** — bez té druhé poloviny by měřidlo vydalo
/// tutéž hodnotu pro „funguje“ i „nefunguje“ (#478). Ptá se to **přes pásmo šířek** (#236)
/// a v obou pohledech, protože u jedné šířky test projde: v okně 700 (štěrbina 610) `Pod sebou`
/// dokonce s okrajem vyjde kolona **širší**, protože automatika zahodí i strom.
@MainActor
@Suite("Výchozí stav diffu jsou bubliny pod řádky (#548)", .serialized)
struct DiffBubbleDefaultTests {
    /// Šířky **štěrbiny diffu** — okno bez railu (52) a bez složeného proužku panelu (38), tedy
    /// okna 700 (podlaha `RootView`u), 1100, 1303 a 1512 (šířka displeje). Tatáž řada jako
    /// u #546, aby se čísla z obou sad dala porovnat.
    nonisolated static let slots: [Double] = [610, 1010, 1213, 1422]
    /// Štěrbina, na které se ptají tvrzení, která na šířce nezávisí (panel, přepnutí tam a zpět).
    /// **1 213 je schválně ta, ve které se okraj vejde v obou pohledech** — na podlaze okna by
    /// tvrzení o okraji mluvilo o stavu, ve kterém se okraj nekreslí.
    private static let referenceSlot = 1_213.0
    private static let height = 700.0

    /// Klíč přepínače `Nálezy pod řádky`. **Nepřejmenovává se** (#548): otáčí se výchozí hodnota,
    /// ne význam uložené — `true` pořád znamená bubliny.
    private static let key = "showInlineFindingBubbles"

    /// Co v `UserDefaults` leží, než se scéna postaví.
    enum Stored: CustomStringConvertible {
        /// Nic — platí výchozí hodnota z `@AppStorage`, tedy to, o čem tahle sada je.
        case unset
        /// Přepínač zapnutý rukou.
        case bubbles
        /// Přepínač vypnutý rukou, tedy okraj s kartami.
        case margin

        var description: String {
            switch self {
            case .unset: "nic uloženo"
            case .bubbles: "uloženo zapnuto"
            case .margin: "uloženo vypnuto"
            }
        }

        /// Kreslí se v tomhle stavu okraj? Odpověď, proti které se počítá očekávaná kolona —
        /// a u `unset` je to **tvrzení**, ne opis kódu.
        var hasMargin: Bool { self == .margin }
    }

    /// Rezerva na posuvník. `NSScrollView` s legacy posuvníky hlásí v nescrollované ose šířku
    /// obsahu **plus pás posuvníku**; bere se z AppKitu, ne jako konstanta (tentýž důvod jako
    /// u #422 a #546). **Vadu to nezakrývá**: mezi oběma stavy je rozdíl 300 b, tedy o řád víc.
    private static var scrollerReserve: Double {
        Double(NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy))
    }

    // MARK: - Výchozí hodnota

    @Test(
        "Výchozí stav je bublinový: chová se jako zapnutý přepínač a jako okraj ne",
        arguments: slots, [DiffLayout.split, .unified]
    )
    func theDefaultDrawsBubbles(slot: Double, layout: DiffLayout) async throws {
        var readings: [Stored: Reading] = [:]
        for stored in [Stored.unset, .bubbles, .margin] {
            let scene = try Scene.make(slot: slot, layout: layout, stored: stored)
            defer { scene.close() }
            // **Druhá polovina tvrzení je nad scénou**: bez karty by okraj nebyl ani ve stavu
            // `margin` a všechna tři čtení by vyšla stejně — zelený test o ničem (#478).
            #expect(scene.cardCount > 0, """
                Materiál scény nemá ani jednu kartu do okraje, takže se tvrzení níž neopírají \
                o nic (štěrbina \(slot), \(layout)).
                """)
            let reading = try await scene.measure()
            readings[stored] = reading

            // Kolona kódu, jak ji spočítá `Policy` **pro ten stav, o kterém tvrzení mluví**.
            // U `unset` je `hasMargin: false` to samotné tvrzení: kdyby výchozí hodnota byla
            // vypnuto, byla by plocha o 300 b užší a tohle spadne.
            let expected = try #require(Self.column(slot: slot, layout: layout, margin: stored.hasMargin))
            #expect(
                abs(reading.area - expected) <= Self.scrollerReserve + 0.5,
                """
                \(stored): plocha obsahu je \(reading.area) b, kolona podle `Policy` \(expected) b \
                (štěrbina \(slot), \(layout)). Rozdíl je nad rezervou na posuvník \
                (\(Self.scrollerReserve)) — okraj se kreslí jinak, než na kolik se spoléhá šířka.
                """
            )
        }

        let unset = try #require(readings[.unset])
        let bubbles = try #require(readings[.bubbles])
        let margin = try #require(readings[.margin])

        #expect(
            abs(unset.area - bubbles.area) <= 0.5 && abs(unset.height - bubbles.height) <= 1,
            """
            Výchozí stav se nechová jako zapnutý přepínač: \(unset) proti \(bubbles) \
            (štěrbina \(slot), \(layout)).
            """
        )
        // Že se ty dva stavy liší, je ta polovina, která z tvrzení výš dělá tvrzení.
        #expect(
            abs(unset.area - margin.area) > Self.scrollerReserve + 0.5,
            """
            Výchozí stav a okraj vyšly na stejné šířce (\(unset.area) proti \(margin.area), \
            štěrbina \(slot), \(layout)) — měřidlo ty dva stavy nerozliší, takže tvrzení výš \
            neplatí ani jedno.
            """
        )
    }

    /// **Kolona kódu je s bublinami o 300 b širší než s okrajem — tam, kde se okraj kreslí.**
    ///
    /// Na podlaze okna to neplatí a je to správně: v `Pod sebou` při štěrbině 610 automatika okraj
    /// zahodí **a k tomu složí strom**, takže s okrajem vyjde kolona naopak širší. Rozhoduje tedy
    /// `columns.margin`, ne šířka okna — a aspoň jedna šířka z pásma musí okraj doopravdy
    /// nakreslit, jinak tvrzení nic neváží (#478).
    @Test("Šířka kolony: bubliny mají o okraj víc, kde se okraj vejde")
    func theCodeColumnIsWiderByTheMargin() throws {
        var drawn = 0
        for slot in Self.slots {
            for layout in [DiffLayout.split, .unified] {
                let withMargin = Policy.diffSideColumns(layout: layout, hasMargin: true, available: slot)
                let withBubbles = Policy.diffSideColumns(layout: layout, hasMargin: false, available: slot)
                let marginColumn = try #require(Policy.diffCodeColumnWidth(available: slot, columns: withMargin))
                let bubbleColumn = try #require(Policy.diffCodeColumnWidth(available: slot, columns: withBubbles))
                guard withMargin.margin else {
                    // **Okraj se nevejde**, takže ho automatika zahodí **a k tomu složí strom** —
                    // a s okrajem vyjde kolona naopak širší. Je to jediný takový bod v pásmu
                    // (610 v `Pod sebou`) a pin je na něm schválně: tvrzení níž se váže na
                    // `columns.margin`, ne na šířku okna.
                    #expect(
                        bubbleColumn <= marginColumn,
                        """
                        Štěrbina \(slot) \(layout): okraj se nekreslí, a přesto vyšla kolona \
                        s bublinami (\(bubbleColumn) b) širší než ta s okrajem (\(marginColumn) b) \
                        — pak už automatika neustupuje tak, jak je popsané.
                        """
                    )
                    continue
                }
                drawn += 1
                #expect(
                    withMargin.tree == withBubbles.tree,
                    "Štěrbina \(slot) \(layout): strom se liší, rozdíl kolon pak není jen okraj"
                )
                #expect(
                    bubbleColumn - marginColumn == Policy.marginColumnWidth(shown: true),
                    """
                    Štěrbina \(slot) \(layout): s bublinami \(bubbleColumn) b, s okrajem \
                    \(marginColumn) b — rozdíl \(bubbleColumn - marginColumn) b místo \
                    \(Policy.marginColumnWidth(shown: true)).
                    """
                )
            }
        }
        #expect(drawn > 0, "V žádné šířce z pásma se okraj nekreslí — tvrzení výš neváží nic.")
    }

    // MARK: - Panel vpravo

    /// **S bublinami se panel neskládá** — je to ten stav, do kterého se #548 vrací.
    ///
    /// Skládání panelu je od #503 podmíněné okrajem (`Policy.diffSideColumns`), takže s výchozími
    /// bublinami má o panelu rozhodovat jedině pohled: `Pod sebou` rozložený, `Vedle sebe` složené
    /// (#188, beze změny). Druhá polovina tvrzení je nad tímtéž oknem s okrajem — tam se panel
    /// složit **musí**, jinak by věta „s bublinami se neskládá“ neměla protějšek.
    @Test("Panel se s bublinami neskládá, s okrajem ano", arguments: [DiffLayout.split, .unified])
    func thePanelStaysExpandedWithBubbles(layout: DiffLayout) async throws {
        let bubbles = try Scene.make(slot: Self.referenceSlot, layout: layout, stored: .unset)
        defer { bubbles.close() }
        _ = try await bubbles.measure()
        await waitUntil("automatika sloupců rozhodne o panelu") { bubbles.panel.applied }
        #expect(
            bubbles.panel.expanded == (layout != .split),
            """
            \(layout): panel je \(bubbles.panel.expanded ? "rozložený" : "složený"), ačkoli \
            s bublinami má rozhodovat jedině pohled (#188).
            """
        )

        let margin = try Scene.make(slot: Self.referenceSlot, layout: layout, stored: .margin)
        defer { margin.close() }
        _ = try await margin.measure()
        await waitUntil("automatika sloupců rozhodne o panelu s okrajem") { margin.panel.applied }
        #expect(
            margin.panel.expanded == false,
            "\(layout): okraj panel nesložil — pak tvrzení výš nemá s čím kontrastovat."
        )
    }

    // MARK: - Přepnutí tam a zpět

    /// **Přepnutí tam a zpět vrátí obojí do výchozího stavu** — šířku kolony i panel.
    ///
    /// Výchozí hodnota se dá otočit a přesto to nechat rozbité: `task(id: columns)` v `DiffView`
    /// má stráž na **totéž** rozhodnutí (`appliedColumns`), takže kdyby identitou byly vstupy
    /// místo výsledku, zůstal by po jednom přepnutí panel složený a kolona úzká. Proto se to měří
    /// třikrát na **jedné** scéně, ne třemi scénami.
    ///
    /// A s kolonou se přepíná i ukazatel `N znaků na stranu` (#546): počítá se z předané kolony,
    /// takže musí sedět na tu **změřenou** v každé fázi zvlášť.
    @Test("Zapnout okraj a vypnout ho vrátí kolonu i panel", arguments: [DiffLayout.split, .unified])
    func togglingThereAndBackRestoresTheDefault(layout: DiffLayout) async throws {
        let scene = try Scene.make(slot: Self.referenceSlot, layout: layout, stored: .unset)
        defer { scene.close() }

        let first = try await scene.measure()
        await waitUntil("panel se dorozhodne") { scene.panel.applied }
        try Self.expectColumn(first, slot: Self.referenceSlot, margin: false, layout: layout, phase: "výchozí")
        #expect(scene.panel.expanded == (layout != .split), "výchozí: panel rozhodl okraj, ne pohled")

        scene.store(.margin)
        let switched = try await scene.measure(changedFrom: first)
        try Self.expectColumn(switched, slot: Self.referenceSlot, margin: true, layout: layout, phase: "s okrajem")
        #expect(scene.panel.expanded == false, "s okrajem: panel se nesložil")

        scene.store(.bubbles)
        let back = try await scene.measure(changedFrom: switched)
        try Self.expectColumn(back, slot: Self.referenceSlot, margin: false, layout: layout, phase: "zpátky na bubliny")
        #expect(
            abs(back.area - first.area) <= 0.5,
            "Zpátky na bublinách je kolona \(back.area) b, na začátku byla \(first.area) b."
        )
        #expect(
            scene.panel.expanded == (layout != .split),
            """
            \(layout): po přepnutí zpět zůstal panel \(scene.panel.expanded ? "rozložený" : "složený") \
            — rozhodnutí o kolonách se neuplatnilo podruhé.
            """
        )
    }

    // MARK: - Bublina zabírá místo, karta v okraji ne

    /// **Nálezy jsou ve výchozím stavu doopravdy v toku pod řádky**, ne jen „okraj se nekreslí“.
    ///
    /// Šířka o tom neřekne nic: bez okraje vyjde kolona stejně široká, ať nálezy jsou, nebo nejsou.
    /// Řekne to **výška dokumentu** — bublina stojí pod svým řádkem, takže obsah naroste. Měří se
    /// na téže štěrbině a v témže pohledu, takže se kolona nemění a zalomení řádků s ní.
    @Test("Bubliny ve výchozím stavu zabírají svislé místo", arguments: [DiffLayout.split, .unified])
    func theBubblesTakeVerticalSpace(layout: DiffLayout) async throws {
        let withFindings = try Scene.make(slot: Self.referenceSlot, layout: layout, stored: .unset)
        defer { withFindings.close() }
        let clean = try Scene.make(
            slot: Self.referenceSlot, layout: layout, stored: .unset, hasFindings: false
        )
        defer { clean.close() }

        let loaded = try await withFindings.measure()
        let empty = try await clean.measure()
        #expect(
            abs(loaded.area - empty.area) <= 0.5,
            "Kolona se s nálezy změnila (\(loaded.area) proti \(empty.area)) — pak se výška srovnává na jiné šířce."
        )
        // **Čtyřicet bodů je podlaha, ne naměřená hodnota** — je to méně než jedna sbalená
        // bublina, takže se pod ni nedá dostat jinak než tím, že bubliny v toku nestojí vůbec.
        #expect(
            loaded.height > empty.height + 40,
            """
            \(layout): obsah s nálezy je \(loaded.height) pt, bez nálezů \(empty.height) pt. \
            Bubliny tedy v toku nestojí — nálezy jsou schované, ne pod řádky.
            """
        )
    }

    // MARK: - Pomůcky

    private static func column(slot: Double, layout: DiffLayout, margin: Bool) -> Double? {
        let columns = Policy.diffSideColumns(layout: layout, hasMargin: margin, available: slot)
        return Policy.diffCodeColumnWidth(available: slot, columns: columns)
    }

    /// Změřená plocha proti koloně z `Policy` — a k tomu ukazatel `N znaků na stranu`, který se
    /// z té kolony skládá. Kontroluje se v každé fázi zvlášť, protože zrovna on se u #546 jednou
    /// rozešel s tím, co je na obrazovce.
    private static func expectColumn(
        _ reading: Reading,
        slot: Double,
        margin: Bool,
        layout: DiffLayout,
        phase: String,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        let expected = try #require(
            column(slot: slot, layout: layout, margin: margin),
            sourceLocation: sourceLocation
        )
        #expect(
            abs(reading.area - expected) <= scrollerReserve + 0.5,
            "\(phase) (\(layout)): plocha \(reading.area) b proti koloně \(expected) b",
            sourceLocation: sourceLocation
        )
        let characterWidth = TestWait.settledFontMetric(
            .characterWidth,
            of: .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        )
        let gutter = DiffLineView.contentInset(for: layout)
        let gauge = Policy.charactersPerSide(
            contentWidth: expected,
            characterWidth: characterWidth,
            layout: layout,
            gutter: gutter
        )
        let fromTheWindow = Policy.charactersPerSide(
            contentWidth: reading.area,
            characterWidth: characterWidth,
            layout: layout,
            gutter: gutter
        )
        // Rezerva na posuvník je pár bodů, tedy nejvýš jeden znak na stranu; víc znamená, že
        // ukazatel slibuje sloupce, které v okně nejsou.
        #expect(
            abs(gauge - fromTheWindow) <= 1,
            """
            \(phase) (\(layout)): ukazatel hlásí \(gauge) znaků z předané kolony, ale ze změřené \
            plochy vychází \(fromTheWindow).
            """,
            sourceLocation: sourceLocation
        )
        #expect(gauge > 0, "\(phase) (\(layout)): ukazatel nemá co hlásit", sourceLocation: sourceLocation)
    }

    /// Co se ze scény čte. Dvě čísla, protože ani jedno samo o sobě ty dva stavy nerozliší:
    /// šířka mluví o koloně, výška o tom, že bubliny stojí v toku.
    struct Reading: Equatable, CustomStringConvertible {
        let area: Double
        let height: Double

        var description: String {
            String(format: "kolona %.1f b, obsah %.0f pt", area, height)
        }
    }

    /// Kam `DiffView` hlásí složení panelu. Třída, aby se dalo přečíst po přepnutí, aniž by se
    /// scéna stavěla znovu.
    @MainActor @Observable final class PanelBox {
        var expanded = true
        /// Rozhodla už automatika sloupců? Bez toho by tvrzení o panelu mohlo přečíst výchozí
        /// `true` dřív, než `task(id:)` doběhne — tedy zelený test o nastavené hodnotě.
        var applied = false
    }

    // MARK: - Scéna

    @MainActor
    struct Scene {
        let window: NSWindow
        let hosting: NSHostingView<AnyView>
        /// **Drží se, i když z něj nikdo nečte** (#411): scéna čte `@AppStorage`, a jakmile
        /// poslední reference zmizí, `ScratchDefaults` po sobě doménu uklidí — tedy dřív, než se
        /// okno změří.
        let defaults: ScratchDefaults
        let panel: PanelBox
        let slot: Double
        let layout: DiffLayout
        /// Kolik karet by do okraje šlo — spočítané **tou funkcí, kterou se skládá okraj**, takže
        /// se scéna nemůže rozejít s tím, o čem tvrzení mluví.
        let cardCount: Int

        static func make(
            slot: Double,
            layout: DiffLayout,
            stored: Stored,
            hasFindings: Bool = true
        ) throws -> Scene {
            let defaults = try ScratchDefaults("diffBubbleDefault")
            Self.write(stored, to: defaults)
            let diff = DiffParser.parse(try Fixture.text("gh/pr-diff-ordinary.diff"))
            let findings = hasFindings ? Self.findings(in: diff) : []
            let panel = PanelBox()
            let hosting = NSHostingView(
                rootView: AnyView(
                    DiffBubbleDefaultProbe(
                        diff: diff,
                        findings: findings,
                        layout: layout,
                        panel: panel
                    )
                    // **Takhle to dělá detail PR** (#220): šířku tabu změří jednou a pošle ji dolů
                    // prostředím i rámcem.
                    .availableWidth(slot)
                    .frame(width: slot, height: height, alignment: .topLeading)
                    .defaultAppStorage(defaults.store)
                )
            )
            hosting.frame = NSRect(x: 0, y: 0, width: slot, height: height)
            let window = NSWindow(
                contentRect: hosting.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.contentView = hosting
            window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
            window.orderFrontUnanimated()
            return Scene(
                window: window,
                hosting: hosting,
                defaults: defaults,
                panel: panel,
                slot: slot,
                layout: layout,
                cardCount: Self.cards(of: findings, in: diff).count
            )
        }

        func close() {
            window.orderOut(nil)
        }

        /// Přepni přepínač **za živa**, tedy tou cestou, jakou ho přepíná člověk v liště:
        /// `@AppStorage` sleduje doménu, takže se změna propíše do už postavené scény.
        func store(_ stored: Stored) {
            Self.write(stored, to: defaults)
        }

        /// Jediné místo, které tím klíčem hýbe — `make` i `store` jdou tudy. **Ve vlastní doméně**
        /// (`ScratchDefaults`, #411): do `UserDefaults.standard` se z testů nesahá.
        private static func write(_ stored: Stored, to defaults: ScratchDefaults) {
            switch stored {
            case .unset: defaults.store.removeObject(forKey: DiffBubbleDefaultTests.key)
            case .bubbles: defaults.store.set(true, forKey: DiffBubbleDefaultTests.key)
            case .margin: defaults.store.set(false, forKey: DiffBubbleDefaultTests.key)
            }
        }

        /// Změřená plocha obsahu — po **ustálení**, ne po pevném okamžiku (#269).
        ///
        /// - Parameter changedFrom: čtení, které tady po přepnutí být **nemá**. Bez toho by se
        ///   měření po přepnutí mohlo trefit do stavu před ním a vyšlo by zeleně omylem.
        func measure(
            changedFrom previous: Reading? = nil,
            sourceLocation: SourceLocation = #_sourceLocation
        ) async throws -> Reading {
            await letItSettle(differingFrom: previous, sourceLocation: sourceLocation)
            let scroller = try #require(
                hosting.diffContentArea(),
                "V okně není plocha obsahu diffu — tvrzení by bylo o prázdnu.",
                sourceLocation: sourceLocation
            )
            let document = try #require(
                scroller.documentView,
                "Plocha obsahu diffu nemá dokument — v okně není co měřit.",
                sourceLocation: sourceLocation
            )
            return Reading(area: Double(scroller.frame.width), height: Double(document.frame.height))
        }

        /// Nechá scénu doskládat: čeká, dokud se dvě po sobě přečtená čísla přestanou měnit — a po
        /// přepnutí navíc dokud se **odliší** od předchozího čtení.
        private func letItSettle(
            differingFrom previous: Reading?,
            sourceLocation: SourceLocation
        ) async {
            let limit = ContinuousClock.now.advanced(by: TestWait.deadline)
            var quiet = 0
            var last: Reading?
            while ContinuousClock.now < limit, quiet < 3 {
                // **Obojí, a v tomhle pořadí.** Odmlka pustí `MainActor`, takže se dostane ke
                // slovu `task(id:)` v `DiffView` (ten rozhoduje o kolonách i o panelu) i přepsaná
                // hodnota `@AppStorage`; pumpování smyčky pak nechá AppKit a SwiftUI doopravdy
                // rozvrhnout. Samotná odmlka rozvržení nevyvolá, samotné pumpování zase
                // vyhladoví aktor (#296; přesně na to naráží sonda okraje u #503).
                await TestWait.pause()
                pump()
                let current = read()
                let stable = current == last && current != nil
                let moved = previous == nil || current != previous
                quiet = stable && moved ? quiet + 1 : 0
                last = current
            }
            // **Nedočkání se hlásí, nepolyká**: měřit polorozloženou scénu znamená buď náhodně
            // zelený běh, nebo pád o pár kroků dál, ze kterého se příčina nepozná.
            if quiet < 3 {
                Issue.record(
                    """
                    Nedočkalo se: plocha obsahu se do \(TestWait.deadline) neustálila \
                    (naposled \(last.map(\.description) ?? "nic"), štěrbina \(slot), \(layout)\
                    \(previous.map { ", čekalo se na změnu proti \($0)" } ?? "")).
                    """,
                    sourceLocation: sourceLocation
                )
            }
        }

        /// Jedno kolo smyčky. **Musí to být synchronní funkce**: `RunLoop.current.run(until:)`
        /// je z asynchronního kontextu nedostupné (toolchain to odmítne přeložit), a přitom je to
        /// ta jediná cesta, jak v hostovaném okně vynutit rozvržení. Volá se tedy odsud, mezi
        /// dvěma odmlkami, které aktor zase pustí.
        private func pump() {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
            hosting.layoutSubtreeIfNeeded()
        }

        private func read() -> Reading? {
            guard let scroller = hosting.diffContentArea(), let document = scroller.documentView
            else { return nil }
            return Reading(area: Double(scroller.frame.width), height: Double(document.frame.height))
        }

        // MARK: - Materiál

        /// Nálezy s kotvou v diffu — z nich se skládá okraj (#503), tedy ta užší kolona kódu.
        ///
        /// Řádek se hledá **v samotném diffu**, ne opisuje z fixture: vymyšlené číslo by kotvu
        /// minulo, karta by nevznikla a všechna tři čtení by vyšla stejně.
        static func findings(in diff: Diff) -> [FindingGroup] {
            diff.files.prefix(3).compactMap { file in
                guard let line = file.hunks
                    .flatMap(\.lines)
                    .compactMap({ Policy.number(of: $0, on: .right) })
                    .last
                else { return nil }
                return FindingGroup(
                    file: file.displayPath,
                    line: line,
                    findings: [makeFinding(
                        file: file.displayPath,
                        line: line,
                        summary: """
                        Návratová hodnota se zahazuje, takže selhání vypadá jako prázdno — \
                        a v UI se to nedá odlišit od „nic tu nebylo“.
                        """
                    )]
                )
            }
        }

        /// Karty do okraje **tou funkcí, kterou je skládá `DiffView`**.
        static func cards(of findings: [FindingGroup], in diff: Diff) -> [DiffMarginCard] {
            Policy.marginCards(
                of: findings,
                in: diff.files.map { DiffMarginSource(file: $0, revealed: RevealedLines(), isFolded: false) }
            )
        }
    }
}

/// Scéna: skutečný `DiffView`, jen s panelem odloženým do třídy, aby se dal přečíst z testu.
struct DiffBubbleDefaultProbe: View {
    let diff: Diff
    let findings: [FindingGroup]
    let layout: DiffLayout
    let panel: DiffBubbleDefaultTests.PanelBox

    var body: some View {
        // **Hodnota se čte v těle, ne uvnitř closure bindingu** (tentýž důvod jako u `JumpProbe`):
        // čtení observable vlastnosti v closure se do závislostí těla nezapíše.
        let expanded = panel.expanded
        return DiffView(
            diff: diff,
            subject: "prism/prism#548",
            scrollTarget: .constant(nil),
            expansion: DiffExpansionActions(
                state: { _ in FileExpansion() },
                reveal: { _, _ in },
                collapse: nil
            ),
            folding: DiffFoldingActions(
                isFolded: { _ in false },
                toggle: { _ in },
                foldAll: { _ in },
                unfoldAll: {}
            ),
            findings: findings,
            layout: .constant(layout),
            panelExpanded: Binding(
                get: { expanded },
                set: { value in
                    panel.expanded = value
                    panel.applied = true
                }
            )
        )
    }
}
