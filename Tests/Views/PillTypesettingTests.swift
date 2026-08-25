import AppKit
import SwiftUI
import Testing

@testable import PRism

/// Rozměry a čitelnost kapslí po sjednocení sazby (#404).
///
/// `DesignPillTests` tvrdí, **kdo** kapsli bere a jakou má metriku. Tady se měří to, co se tou
/// změnou pohnulo v okně a co se z konstant nepozná:
///
/// - **šířka** — mono je širší, a dvě z těch pěti míst mají místo **spočítané**, ne pružné:
///   sloupec závažnosti v tabulce nálezů (92 bodů) a řádek fronty, kde odznak stojí vedle titulku
///   PR. `3 nálezy · 1 blokuje` roste o 40 bodů, `timeout · 2 · 1 blokuje` o 48;
/// - **výška** — mono 10,5 má řádek 12 bodů proti 13 u `.caption2`, ale odsazení jde z 1 na 2,
///   takže kapsle je o bod **vyšší** (15 → 16). V bublině nálezu je to ta věc, která rozhoduje
///   o výšce celého pruhu se značkou (#236);
/// - **kontrast** — a měří se **z bitmapy**, ne z tokenu. Kontrast tokenu netvrdí nic o kresbě
///   (#393): `DiffPaletteTests` roky měřily `Palette.ink`, který se do textu vůbec nenasazoval.
///   U `já` je to zrovna ta nová věc — do #404 odznak barvu textu neměl a dědil ji z okolí.
@Suite("Sazba kapslí (#404)")
@MainActor
struct PillTypesettingTests {
    /// Výška kapsle a řádek, který na jejím místě stál do #404 — **přečtené jednou za test** (#367).
    /// Metrika písma je stav procesu, takže se v jednom testu nesmí čítat dvakrát.
    private let pillHeight = NSLayoutManager().defaultLineHeight(for: DesignPill.font)
        + 2 * DesignPill.verticalPadding
    private let caption2Line = NSLayoutManager().defaultLineHeight(for: .preferredFont(forTextStyle: .caption2))

    // MARK: - Šířka: co má místo spočítané

    /// **Kapsle v tabulce nálezů se musí vejít do svého sloupce.** Sloupce jsou spočítané
    /// (`Policy.findingTableLayout`, #220), takže kapsle, která přeteče, nic neposune — jen se
    /// nakreslí přes sousední sloupec.
    ///
    /// Nejdelší popisek v tom sloupci je `irelevantní`. Měří se **hostovaná** kapsle, ne jen
    /// `TextWidth.pill`, protože o rozměru rozhoduje `designPill`, ne měřidlo.
    @Test("Kapsle v tabulce nálezů se vejde do svého sloupce")
    func theTablePillFitsItsColumn() {
        // Nejužší tab bez panelu (okno 700 − rail 52), tedy stav, ve kterém sloupec `reviewer`
        // odpadá — šířky ostatních sloupců jsou přitom konstanty, takže platí i pro širší okno.
        let layout = Policy.findingTableLayout(availableWidth: 648)
        let severityLabels = FindingDismissal.Reason.allCases.map(\.label)
            + [FindingSeverityBadge.resolvedLabel, "blokuje"]

        for label in severityLabels {
            let width = fittingSize(of: label).width
            #expect(width <= layout.severity, "„\(label)“ má \(width) bodů, sloupec \(layout.severity)")
        }
        // A sloupec revieweera, ve kterém stojí odznak shody. Dvouciferná shoda je teoretická,
        // ale je to řetězec z `\(row.agreement)×`, takže se dvěma znaky počítá i měření.
        let reviewer = Policy.findingTableLayout(availableWidth: 1400).reviewer
        for label in ["2×", "12×"] {
            let width = fittingSize(of: label).width
            #expect(width <= (reviewer ?? 0), "„\(label)“ má \(width) bodů, sloupec \(reviewer ?? 0)")
        }
    }

    /// **Odznak stavu v úzkém řádku fronty neustoupí ani o bod.** Mono je u nejdelšího stavu
    /// o 48 bodů širší (`timeout · 2 · 1 blokuje`, 116 → 164), a v řádku vedle něj stojí titulek
    /// PR, který je taky pružný — takže bez `fixedSize` se o to místo dělí a odznak se zkrátí na
    /// `3 nález…`.
    ///
    /// Měří se **v tom řádku, ne kapsle samotná**, a to `onGeometryChange` uvnitř hostovaného
    /// okna: `fittingSize` na tuhle otázku neodpoví, protože rámec nasazený zvenčí je tvrdý
    /// a hostující view pak hlásí tu šířku, kterou jsme mu dali.
    ///
    /// **Ověřeno vloženou regresí, a ta vyloučila i první podobu tohohle testu**: `lineLimit(1)`
    /// sám o sobě zalomení opravdu zabrání, takže test, který měřil jen **výšku**, procházel
    /// i s odebraným `fixedSize()`. Zkrácení je jiná vada než zalomení a měří se šířkou —
    /// s odebraným `fixedSize()` se dva nejdelší stavy srazily o **20 a 33 bodů**.
    @Test("Odznak stavu fronty v úzkém řádku neustoupí")
    func theQueueBadgeNeverGivesWay() throws {
        // Nejužší tab (okno 700 − rail 52) a v něm jen půlka, ať se titulek s odznakem o místo
        // doopravdy pere.
        let row = 320.0
        for state in Self.queueStates {
            let label = ReviewStateAppearance.label(of: state.state, blocking: state.blocking)
            let natural = fittingSize(of: badge(state))
            #expect(
                abs(natural.height - pillHeight) <= 1,
                "„\(label)“ má výšku \(natural.height), kapsle \(pillHeight)"
            )

            let inRow = try width(of: state, inRowOf: row)
            #expect(
                abs(inRow - natural.width) <= 1,
                "„\(label)“ se v \(row) bodech srazil z \(natural.width) na \(inRow)"
            )
        }
    }

    /// Cena mono u odznaku fronty, **zapsaná jako měření**: nejdelší stav roste o 48 bodů.
    /// Kdyby se sazba omylem zvedla na 12 nebo 13, spadne to tady — ne až na tom, že se v úzkém
    /// okně ztratí titulek PR.
    @Test("Mono u odznaku fronty nestojí víc než padesát bodů")
    func keepsTheCostOfMonoBoundedInTheQueue() {
        for state in Self.queueStates {
            let label = ReviewStateAppearance.label(of: state.state, blocking: state.blocking)
            let before = TextWidth.of(label, font: .preferredFont(forTextStyle: .caption1)) + 12
            let after = fittingSize(of: badge(state)).width
            #expect(after > before, "„\(label)“: mono má být širší, jinak měřidlo měří jeden font dvakrát")
            #expect(after - before <= 50, "„\(label)“ vyrostl o \(after - before) bodů")
        }
    }

    // MARK: - Výška: pruh se značkou v bublině

    /// **Kapsle je v pruhu se značkou to nejvyšší** — a proto o výšce pruhu rozhoduje ona, ne text
    /// vedle ní. Je to ten důvod, proč se u #404 musela výška projít renderem: `caption2` má řádek
    /// 13 bodů, kapsle 16.
    @Test("Výšku pruhu se značkou rozhoduje kapsle, ne text vedle ní")
    func theMarkHeightComesFromThePill() {
        #expect(pillHeight > caption2Line, "kapsle \(pillHeight), próza vedle ní \(caption2Line)")
    }

    /// **Bublina nálezu vyroste o kapsli, ne o víc.** Měří se dvě bubliny nad týmiž daty — jedna
    /// s odznakem `blokuje`, druhá bez něj —, takže rozdíl výšek je přesně to, co kapsle přidala.
    ///
    /// Tvrzení je, že přidá **nulu**: kapsle je 16 bodů a pruh má svislé odsazení 6, tedy
    /// 28 bodů, což je zároveň výška pruhu bez ní (próza 13 + odsazení… ne — 13 + 12 = 25). Číslo
    /// se proto nevymýšlí, měří se a hlídá se **strop**: kapsle smí pruh zvednout nejvýš o ten
    /// jeden bod, který ji dělí od prózy. Víc by znamenalo, že se do bubliny dostala jiná sazba.
    @Test("Kapsle zvedne bublinu nejvýš o bod")
    func theBubbleGrowsByAtMostOnePoint() {
        let width = 720.0
        let withPill = fittingSize(of: bubble(blocking: true).frame(width: width)).height
        let withoutPill = fittingSize(of: bubble(blocking: false).frame(width: width)).height

        #expect(withPill >= withoutPill, "bublina s kapslí je nižší (\(withPill)) než bez ní (\(withoutPill))")
        #expect(
            withPill - withoutPill <= pillHeight - caption2Line,
            "kapsle zvedla bublinu o \(withPill - withoutPill), smí nejvýš o \(pillHeight - caption2Line)"
        )
    }

    // MARK: - Kontrast: měřeno z bitmapy

    /// **Text kapsle musí být na svém podkladu čitelný, a měří se to na nakresleném.**
    ///
    /// Bere se nejsytější pixel uvnitř kapsle (tedy ten, ve kterém glyf pokryl plochu nejvíc)
    /// a porovná se s podkladem kapsle **z téže bitmapy**. Tokeny by na tuhle otázku
    /// neodpověděly: `Palette.ink` u `já` se do #404 nenasazoval vůbec, a bitmapa je navíc
    /// v profilu displeje, takže se hodnoty z palety a z kresby nerovnají (u #366 vyšel `crit`
    /// v bitmapě 0,799/0,292/0,272 proti 0,812/0,133/0,180).
    ///
    /// **Práh je u každé kapsle vlastní a je to naměřená hodnota**, ne kulaté číslo.
    ///
    /// **Od #432 bere celá škála tokeny.** Do té doby čtyři z těch kapslí kreslily **systémovou**
    /// škálu (`.green`, `.red` z `badgeColor(of:)` a z `ReviewStateAppearance`) a ve světlém režimu
    /// byly pod třemi — `vyřešeno` mělo **1,63**. #404 na tom nic neměnilo (měnilo sazbu) a nechalo
    /// to tady zapsané k vyřízení zvlášť; #432 ten převod udělalo a tahle sada teď hlídá výsledek.
    ///
    /// Naměřeno (světlý / tmavý), kresba v profilu displeje převedená do sRGB. Sloupec **před** je
    /// hodnota se systémovou barvou, **po** s tokenem — u kapslí, které se u #432 neměnily, je to
    /// jedno číslo:
    ///
    /// | kapsle | odstín | světlý před → po | tmavý před → po |
    /// |---|---|---|---|
    /// | fronta, `3 nálezy · 1 blokuje` | `.red` → `Palette.crit` | **2,70 → 3,77** | 4,48 → 4,55 |
    /// | fronta, `3 nálezy` | `.orange` → `Palette.find` | **1,85 → 3,36** | 5,94 → 5,75 |
    /// | fronta, `čisté` | `.green` → `Palette.ok` | **1,80 → 3,44** | 6,26 → 5,55 |
    /// | bublina, `blokuje` | `Palette.crit` | 3,65 | 4,16 |
    /// | tabulka, `irelevantní` | `Palette.ink2` na `raised` | 4,08 | 6,47 |
    /// | vlákno, `vyřešeno` | `.green` → `Palette.ok` | **1,63 → 3,05** | 4,73 → 4,19 |
    /// | vlákno, `zastaralé` | `Palette.ink2` na `line` | 3,66 | 5,26 |
    /// | vlákno, `+12` | `Palette.stale` | 2,91 | 4,56 |
    /// | konverzace, `já` | `Palette.ink` na akcentu | 12,27 | 8,40 |
    /// | konverzace, `schválil` | `.green` → `Palette.ok` | **1,70 → 3,19** | 5,26 → 4,67 |
    /// | konverzace, `vyžádal změny` | `.red` → `Palette.crit` | **2,52 → 3,49** | 3,84 → 3,90 |
    ///
    /// **V tmavém režimu je to u tří z nich výměna dolů** (6,26 → 5,55 u `čisté` je největší), a je
    /// to vědomé: tmavá větev palety je tmavší než systémová škála, takže se platí rezervou tam,
    /// kde jí bylo dost, za čitelnost tam, kde nebyla vůbec. Nejnižší hodnota po převodu je
    /// **3,05** proti **1,63** před ním.
    ///
    /// Prahy leží kus pod těmi hodnotami, ať sada spadne na zhoršení, ne na zaokrouhlení; tatáž
    /// kázeň jako v `MintTokenTests`.
    @Test("Kontrast kapsle se proti naměřenému nezhorší")
    func keepsThePillContrastWhereItWasMeasured() throws {
        for (mode, name) in [(NSAppearance.Name.aqua, "světlý"), (.darkAqua, "tmavý")] {
            let appearance = try #require(NSAppearance(named: mode))
            for sample in Self.samples {
                let drawn = try drawn(sample, in: appearance)
                let value = contrast(drawn.tint, drawn.plate)
                #expect(value >= sample.floor, "\(name), \(sample.name): kontrast \(value), práh \(sample.floor)")
            }
        }
    }

    /// **`já` je ta kapsle, které #404 barvu textu doopravdy přidalo** — do té doby ji dědila
    /// z okolí —, takže právě u ní má měření co říct: **12,27** ve světlém a **8,40** v tmavém.
    ///
    /// Tvrdí se to zvlášť a s vysokým prahem, protože kdyby se `Palette.ink` jednou vyměnil za
    /// `ink2` nebo `ink3`, hodnota spadne pod polovinu a společný práh z tabulky výš by to nechytil.
    @Test("Odznak já je na akcentovém washi čitelný v obou režimech")
    func theMineBadgeReadsOnTheAccentWash() throws {
        let sample = try #require(Self.samples.first { $0.label == "já" })
        for (mode, name) in [(NSAppearance.Name.aqua, "světlý"), (.darkAqua, "tmavý")] {
            let appearance = try #require(NSAppearance(named: mode))
            let drawn = try drawn(sample, in: appearance)
            let value = contrast(drawn.tint, drawn.plate)
            #expect(value >= 8.0, "\(name): `já` má kontrast \(value)")
        }
    }

    /// **A ta barva se do textu doopravdy dostane.** Nejsytější pixel v kapsli musí být blíž
    /// nasazenému odstínu než podkladu — kdyby se `foregroundStyle` vynechalo, text by měl barvu
    /// zděděnou z okolí a tohle tvrzení padne, kdežto kontrast výš by mohl projít.
    ///
    /// Odstín se **kreslí týmž harnessem** (plocha vedle kapsle), ne čte z `Palette`: viz #366.
    @Test("Nasazený odstín se dostane do textu kapsle")
    func theTintReachesTheText() throws {
        for (mode, name) in [(NSAppearance.Name.aqua, "světlý"), (.darkAqua, "tmavý")] {
            let appearance = try #require(NSAppearance(named: mode))
            for sample in Self.samples {
                let drawn = try drawn(sample, in: appearance)
                let toTint = distance(drawn.text, drawn.tint)
                let toPlate = distance(drawn.text, drawn.plate)
                #expect(
                    toTint < toPlate,
                    "\(name), \(sample.name): text je blíž podkladu (\(toPlate)) než odstínu (\(toTint))"
                )
            }
        }
    }

    // MARK: - Scény

    private struct QueueState {
        let state: ReviewState
        var blocking = 0
    }

    /// Stavy, které v řádku fronty stojí — **i ty nejdelší**, protože o šířku se pere jen ten
    /// nejdelší popisek. `timeout · 2 · 1 blokuje` je z nich nejdelší (164 bodů mono).
    private static let queueStates: [QueueState] = [
        QueueState(state: .notStarted),
        QueueState(state: .queued),
        QueueState(state: .cloning),
        QueueState(state: .checkoutFailed(detail: "boom")),
        QueueState(state: .running(finished: 2, total: 3)),
        QueueState(state: .clean),
        QueueState(state: .completed(findings: 3)),
        QueueState(state: .completed(findings: 3), blocking: 1),
        QueueState(state: .dismissed(findings: 3)),
        QueueState(state: .failed(detail: "boom")),
        QueueState(state: .timedOut(findings: 2), blocking: 1),
        QueueState(state: .interrupted(findings: 2), blocking: 1),
        QueueState(state: .stale),
    ] + InconclusiveReason.allCases.map { QueueState(state: .inconclusive(reason: $0)) }

    private func badge(_ state: QueueState) -> some View {
        ReviewStateBadge(state: state.state, blocking: state.blocking)
    }

    /// Kam si řádek zapíše šířku, kterou odznaku doopravdy nechal.
    ///
    /// Reference mimo observable stav, jako v `LayoutCallbackProbe`: `@State` by graf špinil sám
    /// a měřidlo by měřilo sebe.
    @MainActor private final class Reported {
        var width: CGFloat?
    }

    /// Šířka odznaku **v řádku fronty**, ne samotného. Řádek je zkrácená podoba `PullRequestRow`:
    /// pružný titulek s `lineLimit(1)`, mezera a odznak — tedy zrovna ta trojice, ve které se
    /// o místo pere.
    private func width(of state: QueueState, inRowOf width: CGFloat) throws -> CGFloat {
        let reported = Reported()
        let row = HStack(spacing: 6) {
            Text(verbatim: "feat: přepsat frontu tak, aby se do řádku nevešla ani náhodou")
                .font(.body)
                .lineLimit(1)
            Spacer(minLength: 8)
            badge(state)
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { reported.width = $0 }
        }
        .frame(width: width)

        let hosting = NSHostingView(rootView: row)
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: 40)
        let window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        hosting.layoutSubtreeIfNeeded()

        return try #require(reported.width, "řádek nenahlásil šířku odznaku — měřidlo nic neměří")
    }

    /// Bublina nad jedním nálezem. `blocking: false` je tatáž bublina bez kapsle — kategorie
    /// `style` v základní blokující sadě není, takže odznak nedostane.
    private func bubble(blocking: Bool) -> some View {
        let finding = Finding(
            reported: ReportedFinding(
                file: "src/Vault/Encryptor.php",
                line: 41,
                // `style` v `Policy.defaultBlockingCategories` není, takže tatáž bublina odznak
                // nedostane — a rozdíl výšek je pak přesně to, co kapsle přidala.
                category: blocking ? "correctness" : "style",
                verdict: .confirmed,
                shortSummary: nil,
                summary: "Klíč se loguje v plaintextu.",
                failureScenario: "V logu skončí šifrovací klíč."
            ),
            reviewer: "code-review:code-review",
            headSha: "0123456789abcdef0123456789abcdef01234567"
        )
        return FindingBubbleView(
            group: FindingGroup(file: finding.file, line: finding.line, findings: [finding]),
            indent: 0,
            toggle: {}
        )
    }

    /// Jedna kapsle z jednoho z těch pěti míst — i s podkladem, na kterém v okně doopravdy leží.
    private struct Sample {
        let name: String
        let label: String
        let tint: Color
        let wash: Color
        /// Plocha pod kapslí: `raised` v hlavičce vlákna, `chrome` v bublině nálezu a v kartě
        /// konverzace, `surface` v řádku fronty.
        let plate: Color
        /// Práh kontrastu — naměřená hodnota z tabulky u `keepsThePillContrastWhereItWasMeasured`,
        /// zaokrouhlená dolů. Platí pro **oba** režimy, takže je z toho horšího.
        let floor: Double
    }

    private static let samples: [Sample] = [
        Sample(
            name: "fronta / blokující stav",
            label: "3 nálezy · 1 blokuje",
            tint: Palette.crit,
            wash: Palette.crit.opacity(0.15),
            plate: Palette.surface,
            floor: 3.7
        ),
        // Nálezy bez blokujícího a čistý běh **přibyly u #432**: oranžová byla z celé škály na tom
        // nejhůř (1,85) a v tabulce chyběla, protože #404 měřilo jen ty kapsle, které se sázely.
        Sample(
            name: "fronta / nálezy",
            label: "3 nálezy",
            tint: Palette.find,
            wash: Palette.find.opacity(0.15),
            plate: Palette.surface,
            floor: 3.3
        ),
        Sample(
            name: "fronta / čisté",
            label: "čisté",
            tint: Palette.ok,
            wash: Palette.ok.opacity(0.15),
            plate: Palette.surface,
            floor: 3.4
        ),
        Sample(
            name: "bublina / blokuje",
            label: "blokuje",
            tint: Palette.crit,
            wash: Palette.crit.opacity(0.15),
            plate: Palette.chrome,
            floor: 3.4
        ),
        Sample(
            name: "tabulka / odmítnutý",
            label: "irelevantní",
            tint: Palette.ink2,
            wash: Palette.raised,
            plate: Palette.chrome,
            floor: 3.9
        ),
        Sample(
            name: "vlákno / vyřešeno",
            label: "vyřešeno",
            tint: Palette.ok,
            wash: Palette.ok.opacity(0.18),
            plate: Palette.raised,
            floor: 3.0
        ),
        Sample(
            name: "vlákno / zastaralé",
            label: "zastaralé",
            tint: Palette.ink2,
            wash: Palette.line,
            plate: Palette.raised,
            floor: 3.4
        ),
        Sample(
            name: "vlákno / nevešlo se",
            label: "+12",
            tint: Palette.stale,
            wash: Palette.stale.opacity(0.18),
            plate: Palette.raised,
            floor: 2.7
        ),
        Sample(
            name: "konverzace / já",
            label: "já",
            tint: Palette.ink,
            wash: Palette.accent.opacity(0.18),
            plate: Palette.raised,
            floor: 8.0
        ),
        // Verdikty v kartě konverzace (`badgeColor(of:)`) brala do #432 systémová škála; od #432
        // jsou to tokeny jako všude jinde. `dismissed` mezi vzorky **není**: má `.secondary`, tedy
        // poloprůhlednou barvu, u které by naměřený kontrast popisoval stav před stejně jako po.
        Sample(
            name: "konverzace / schválil",
            label: "schválil",
            tint: Palette.ok,
            wash: Palette.ok.opacity(0.18),
            plate: Palette.chrome,
            floor: 3.1
        ),
        Sample(
            name: "konverzace / vyžádal změny",
            label: "vyžádal změny",
            tint: Palette.crit,
            wash: Palette.crit.opacity(0.18),
            plate: Palette.chrome,
            floor: 3.4
        ),
    ]

    // MARK: - Měřidlo

    private func fittingSize(of label: String) -> CGSize {
        fittingSize(of: Text(verbatim: label).designPill(tint: Palette.ink2, background: Palette.raised))
    }

    private func fittingSize(of view: some View) -> CGSize {
        NSHostingView(rootView: view).fittingSize
    }

    /// Barva přečtená v sRGB. Neúspěch převodu se **nezamlčuje fallbackem** — hlídá ho vlastní
    /// tvrzení (`isConverted`), aby se zelená sada nedala splnit měřením v cizím prostoru; tatáž
    /// konstrukce jako v `MintTokenTests`.
    private struct Measured {
        let color: NSColor
        let isConverted: Bool

        init(_ color: NSColor) {
            let converted = color.usingColorSpace(.sRGB)
            self.color = converted ?? color
            isConverted = converted != nil
        }

        private func channel(_ value: Double) -> Double {
            value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }

        var luminance: Double {
            0.2126 * channel(color.redComponent) + 0.7152 * channel(color.greenComponent)
                + 0.0722 * channel(color.blueComponent)
        }

        /// Vzdálenost v sRGB — na „je text blíž odstínu, nebo podkladu“ stačí, protože se
        /// porovnávají **dvě vzdálenosti v témže prostoru**, ne absolutní hodnota.
        func distance(to other: Measured) -> Double {
            let dr = color.redComponent - other.color.redComponent
            let dg = color.greenComponent - other.color.greenComponent
            let db = color.blueComponent - other.color.blueComponent
            return (dr * dr + dg * dg + db * db).squareRoot()
        }
    }

    private func contrast(_ first: Measured, _ second: Measured) -> Double {
        let (a, b) = (first.luminance, second.luminance)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    private func distance(_ first: Measured, _ second: Measured) -> Double {
        first.distance(to: second)
    }

    /// Kapsle a k ní referenční odstín — **obojí z bitmapy**, ne z `Palette`.
    ///
    /// Podklad se bere z **té samé kapsle**: je to nejčastější barva ve středním pásu, tedy wash
    /// složený nad plátem přesně tak, jak se nakreslil. Odečítat ho z polohy by znamenalo tvrdit,
    /// kde v bitmapě co leží — a to je předpoklad, který se rozbije při první změně odsazení.
    /// Odstín má **vlastní kresbu v témže vzhledu**: plocha vyplněná tímtéž tokenem (#366).
    private func drawn(
        _ sample: Sample,
        in appearance: NSAppearance
    ) throws -> (text: Measured, tint: Measured, plate: Measured) {
        let pill = Text(verbatim: sample.label)
            .designPill(tint: sample.tint, background: sample.wash)
            .background(sample.plate)
        let rep = try bitmap(of: pill, size: fittingSize(of: pill), in: appearance)
        let band = try pixels(in: rep)
        let plate = try #require(modal(of: band), "v kapsli se nenašel ani jeden pixel — sonda nekreslí")
        let text = try #require(
            band.max(by: { $0.distance(to: plate) < $1.distance(to: plate) }),
            "v kapsli se nenašel ani jeden pixel — sonda nekreslí"
        )

        let swatch = Rectangle().fill(sample.tint).frame(width: Self.swatch, height: Self.swatch)
        let swatchRep = try bitmap(of: swatch, size: CGSize(width: Self.swatch, height: Self.swatch), in: appearance)
        let tint = Measured(try #require(
            swatchRep.colorAt(x: Int(Self.swatch) / 2, y: Int(Self.swatch) / 2),
            "plocha s odstínem se nenakreslila"
        ))

        // Kdyby se převod nepovedl, počítal by se kontrast v cizím prostoru — a vyšel by z jiných
        // čísel, než jaká jsou v bitmapě.
        #expect(
            plate.isConverted && tint.isConverted && text.isConverted,
            "\(sample.name): barvu nelze převést do sRGB"
        )
        return (text, tint, plate)
    }

    /// Scéna nakreslená ve **vynuceném vzhledu na vlastním okně**, ne na `NSApp` (#367): globální
    /// vzhled je jedna hodnota na celý proces a hostitel testů si ji sám přepisuje.
    private func bitmap(
        of scene: some View,
        size: CGSize,
        in appearance: NSAppearance
    ) throws -> NSBitmapImageRep {
        let hosting = NSHostingView(rootView: scene)
        hosting.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.appearance = appearance
        window.contentView = hosting
        // Mimo obrazovku, ať měření nikomu neskočí před oči — v paralelním běhu stojí vedle sebe
        // víc instancí.
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        window.orderFront(nil)
        defer { window.orderOut(nil) }

        let rep = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        return rep
    }

    /// Pixely ze **středního pásu** kapsle, ne z celé: u zaoblených konců prosvítá plát, takže by
    /// „nejdál od podkladu“ mohl vyjít pixel, ve kterém žádný text není.
    private func pixels(in rep: NSBitmapImageRep) throws -> [Measured] {
        let rows = (rep.pixelsHigh * 3 / 8)...(rep.pixelsHigh * 5 / 8)
        let columns = (rep.pixelsWide / 5)...(rep.pixelsWide * 4 / 5)
        var found: [Measured] = []
        for y in rows {
            for x in columns where rep.colorAt(x: x, y: y) != nil {
                found.append(Measured(try #require(rep.colorAt(x: x, y: y))))
            }
        }
        return found
    }

    /// Nejčastější barva v pásu — tedy wash, protože glyfy pokrývají jen jeho menšinu.
    ///
    /// Klíčem je barva zaokrouhlená na 256 úrovní, ať se antialiasované odchylky o zlomek
    /// procenta nepočítají jako různé podklady.
    private func modal(of pixels: [Measured]) -> Measured? {
        var counts: [String: (count: Int, color: Measured)] = [:]
        for pixel in pixels {
            let key = [pixel.color.redComponent, pixel.color.greenComponent, pixel.color.blueComponent]
                .map { String(Int(($0 * 255).rounded())) }
                .joined(separator: ",")
            counts[key] = ((counts[key]?.count ?? 0) + 1, pixel)
        }
        return counts.values.max { $0.count < $1.count }?.color
    }

    /// Šířka referenční plochy. Dost na to, aby se z ní dal vzít pixel z prostředka a nezachytil
    /// se okraj.
    private static let swatch: CGFloat = 12
}
