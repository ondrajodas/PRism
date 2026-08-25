import AppKit
import Foundation
import SwiftUI
import Testing

@testable import PRism

/// Labely a reviewery v panelu — **rozměr, ne pravidlo** (#392).
///
/// Pravidlo zalomení testuje `LabelChipsTests` nad umělými šířkami; tady se měří **skutečným
/// písmem** a **přes pásmo šířek**, ve kterých panel doopravdy stojí (240 až 520). Je to schválně
/// rozdělené: kdyby to bylo v jednom testu, nešlo by po jeho spadnutí poznat, jestli se rozbilo
/// rozhodování, nebo sazba.
///
/// **Pásmo, ne jedna šířka**: chipy se v každé zalomí jinak, takže jediná šířka umí projít náhodou —
/// a rozejde se to zrovna v pásmu. Přesně tak vypadala past, na kterou se přišlo měřením zákresu:
/// chip 230 bodů v řádku širokém 214.
@MainActor
@Suite("Šířka labelů a reviewerů v panelu (#392)")
struct PanelMetadataWidthTests {
    /// Šířky panelu z návrhu: podlaha, výchozí, mezi tím a strop.
    private let panelWidths: [Double] = [240, 260, 300, 360, 420, 520]

    /// Šířka, která v bloku zbývá na chipy. **Z produkční funkce**, ne z vlastní aritmetiky:
    /// odsazení je jedno a měření se s kresbou nesmí rozejít (pravidlo #236, nález Copilota).
    private func contentWidth(_ panel: Double) -> Double {
        PanelMetadataView.contentWidth(inPanelOf: panel)
    }

    /// Skutečné labely z `cli/cli` (fixture `repo-labels.json`) plus dvě dlouhá jména — ta jsou to,
    /// co se do panelu nemá kam vejít.
    private static let labels: [PullRequestLabel] = [
        PullRequestLabel(name: "enhancement", color: "a2eeef"),
        PullRequestLabel(name: "needs-design-review", color: "d4c5f9"),
        PullRequestLabel(name: "needs-design-review-and-product-signoff", color: "d4c5f9"),
        PullRequestLabel(name: "dependencies", color: "0366d6"),
        PullRequestLabel(name: "bug", color: "d73a4a"),
        PullRequestLabel(name: "go", color: "16e2e2"),
    ]

    private func metrics() -> Policy.LabelChipMetrics {
        LabelChipStyle.metrics(addTitle: "+ label")
    }

    /// **Ta změřená past ze zákresu**: chip se počítá **i s rámem a odsazením**, takže nesmí přerůst
    /// řádek. Bez `box-sizing: border-box` vyšel v zákresu 230 bodů v řádku širokém 214, tedy tři
    /// body za pravým okrajem panelu.
    @Test("Žádný chip nepřeroste šířku řádku v žádné šířce panelu")
    func noChipOutgrowsTheRow() {
        let metrics = metrics()
        for panel in panelWidths {
            let width = contentWidth(panel)
            let layout = Policy.labelChips(Self.labels, width: width, metrics: metrics, canAdd: true)

            for row in layout.rows {
                let total = row.reduce(0.0) { $0 + Self.width(of: $1, metrics: metrics) }
                    + Double(max(0, row.count - 1)) * metrics.spacing
                #expect(total <= width + 0.5, "panel \(Int(panel)): řádek má \(total) v \(width)")
            }
        }
    }

    /// Strop **dvou řádků labelů** platí v celém pásmu — třetí řádek ukusuje místo nálezům.
    @Test("Labely se nikde nerozlezou na tři řádky")
    func neverThreeLabelRows() {
        let metrics = metrics()
        for panel in panelWidths {
            let layout = Policy.labelChips(
                Self.labels,
                width: contentWidth(panel),
                metrics: metrics,
                canAdd: true
            )

            #expect(layout.labelRows <= 2, "panel \(Int(panel)): \(layout.labelRows) řádků labelů")
        }
    }

    /// `+N` je tam **právě tehdy**, když se něco nevešlo — ani jednou navíc, ani jednou méně.
    @Test("+N se kreslí právě tehdy, když se něco nevešlo")
    func theMoreBadgeMatchesTheHiddenCount() {
        let metrics = metrics()
        for panel in panelWidths {
            let layout = Policy.labelChips(
                Self.labels,
                width: contentWidth(panel),
                metrics: metrics,
                canAdd: true
            )
            let hasMore = layout.rows.flatMap { $0 }.contains { if case .more = $0 { true } else { false } }

            #expect(hasMore == (layout.hidden > 0), "panel \(Int(panel)): +N a počet se rozešly")
        }
    }

    /// **`+ label` neustoupí nikdy** — v žádné šířce pásma nesmí zmizet.
    @Test("+ label je v každé šířce")
    func theActionIsAlwaysThere() {
        let metrics = metrics()
        for panel in panelWidths {
            let layout = Policy.labelChips(
                Self.labels,
                width: contentWidth(panel),
                metrics: metrics,
                canAdd: true
            )

            #expect(layout.rows.flatMap { $0 }.contains(.add), "panel \(Int(panel)): + label zmizel")
        }
    }

    /// **Ořez nechá místo na `+N`** — a mez je právě šířka řádku minus mezera a `+N`, tedy ta
    /// hodnota, ze které v zákresu vyšlo 180 bodů. Není to konstanta k opsání: měří se **na tom, na
    /// čem se kreslí**, takže se s doladěním písma posune sama.
    @Test("Ořezaný chip nechá vedle sebe místo na +N")
    func theTrimLeavesRoomForTheMoreBadge() {
        let metrics = metrics()
        for panel in panelWidths {
            let width = contentWidth(panel)
            let layout = Policy.labelChips(Self.labels, width: width, metrics: metrics, canAdd: true)
            guard layout.hidden > 0 else { continue }
            let reserve = metrics.moreWidth(layout.hidden) + metrics.spacing

            for row in layout.rows {
                for chip in row {
                    if case .label(_, let maxWidth) = chip, let maxWidth {
                        #expect(maxWidth <= width - reserve + 0.5, "panel \(Int(panel)): ořez nechal na +N málo")
                        #expect(maxWidth > 0)
                    }
                }
            }
        }
    }

    /// **`chce změny` se neořezává nikdy** — u reviewerů ustupuje jméno, ne odpověď: kvůli odpovědi
    /// se na sekci kouká. Změřeno na **podlaze 240**, tedy tam, kde je místa nejmíň: 16 na iniciálu,
    /// dvě mezery po 7 a `chce změny` celé — na jméno musí zbýt aspoň jeden znak.
    @Test("Nejdelší odpověď se vejde i na podlaze 240 bodů")
    func theLongestAnswerFitsOnTheFloor() {
        let width = contentWidth(240)
        let answer = ReviewerAnswer.allCases
            .map { TextWidth.of($0.czechLabel, font: .systemFont(ofSize: 11)) }
            .max() ?? 0
        // Iniciála 16, dvě mezery po 7 (za iniciálou a před odpovědí).
        let fixed = 16.0 + 2 * 7.0
        let forName = width - fixed - Double(answer)

        #expect(Double(answer) < width, "odpověď je sama širší než panel")
        #expect(forName > TextWidth.of("a…", font: .systemFont(ofSize: 12)),
                "na jméno nezbylo místo ani na jeden znak s výpustkou")
    }

    /// A druhá polovina téhož tvrzení: **`chce změny` je z těch tří nejdelší**, takže když se vejde
    /// ona, vejdou se i ostatní dvě. Bez toho by test výš mohl měřit tu nejkratší.
    @Test("Chce změny je nejdelší z tří odpovědí")
    func theBlockingAnswerIsTheLongest() {
        let widths = ReviewerAnswer.allCases.map {
            ($0, TextWidth.of($0.czechLabel, font: .systemFont(ofSize: 11)))
        }
        let longest = widths.max { $0.1 < $1.1 }?.0

        #expect(longest == .changesRequested)
    }

    /// **Spočítaná šířka musí souhlasit s nakreslenou** — pravidlo #236: kdo si říká o velikost,
    /// musí ji měřit na tom, na čem kreslí.
    ///
    /// Tohle je jediné tvrzení, které chytá `box-sizing`: kdyby `chipWidth` počítala jen text
    /// (`content-box`), vyšla by menší než nakreslený chip, `Policy` by na řádek nasázela o chip víc
    /// a `HStack` by pak jména ořezal — a to i tam, kde by se celá vešla. Ostatní tvrzení v téhle
    /// suitě to nechytí, protože si berou tutéž (rozbitou) míru.
    ///
    /// Ověřeno vloženou regresí: s `frameWidth == 0` tenhle test spadne.
    @Test("Spočítaná šířka chipu souhlasí s nakreslenou")
    func theComputedWidthMatchesTheDrawnOne() throws {
        for label in Self.labels {
            let drawn = try Self.drawnWidth(of: LabelChipView(label: label, maxWidth: nil))
            let computed = LabelChipStyle.chipWidth(label)

            #expect(abs(drawn - computed) <= 1, "\(label.name): kreslí se \(drawn), počítá se \(computed)")
        }
    }

    @Test("Spočítaná šířka +N a + label souhlasí s nakreslenou")
    func theComputedBadgeWidthsMatch() throws {
        for count in [2, 12] {
            let drawn = try Self.drawnWidth(of: LabelMoreChipView(count: count))
            #expect(abs(drawn - LabelChipStyle.moreWidth(count)) <= 1, "+\(count): kreslí se \(drawn)")
        }
        for title in ["+ label", "+ reviewer"] {
            let drawn = try Self.drawnWidth(of: AddChipLabel(title: title))
            #expect(abs(drawn - LabelChipStyle.actionWidth(title)) <= 1, "\(title): kreslí se \(drawn)")
        }
    }

    /// Ideální šířka tak, jak ji nakreslí SwiftUI — `ImageRenderer` bez rámce dá přesně ji.
    @MainActor private static func drawnWidth(of view: some View) throws -> Double {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        return try #require(renderer.nsImage).size.width
    }

    /// **Blok nepřeteče v žádné šířce panelu** — ani s dlouhými jmény labelů, ani s dlouhým loginem.
    ///
    /// Měří se pixely, ne rámečky (`OverflowProbe`): `frame(width:)` je tvrdý rámec, takže dítě,
    /// které se do něj nevejde, přeteče vizuálně, aniž by se rodičova velikost změnila.
    @Test("Blok labelů a reviewerů nikde nepřeteče")
    func theBlockNeverOverflows() throws {
        for panel in panelWidths {
            let probe = OverflowProbe(
                width: panel,
                height: 420,
                name: "panel-metadata-\(Int(panel))"
            )
            let overflow = try probe.overflow(of: Self.view(panelWidth: panel))
            #expect(overflow == 0, "panel \(Int(panel)): blok přetekl o \(overflow) bodů")
        }
    }

    /// **Akce, po které se nic nestane, tam být nesmí.** Dokud snímek nedorazil, nemá `+ label`
    /// z čeho složit sadu (posílá se celá), takže se kreslí **zakázaný** — a jeho vysvětlení mluví
    /// o načítání, ne o bráně. Kdyby zůstal aktivní, klik v nabídce by tiše neudělal nic.
    @Test("Bez načteného snímku je + label zakázaný")
    func theAddActionWaitsForTheSnapshot() throws {
        let width = contentWidth(300)
        let loading = PanelMetadataView(
            state: .loading,
            editing: .allowed,
            repo: Self.repo,
            contentWidth: width
        )
        let loaded = PanelMetadataView(
            state: .loaded(PullRequestMetadata(), updatedAt: Date(timeIntervalSince1970: 100)),
            editing: .allowed,
            repo: Self.repo,
            contentWidth: width
        )

        // Dva různé obrázky: zakázaný chip se kreslí ztlumeně, povolený plně.
        #expect(try Self.pixels(of: loading) != Self.pixels(of: loaded))
    }

    /// Surové bajty bitmapy, ne `tiffRepresentation` — ta se mezi dvěma rendery liší i u shodného
    /// obrázku, takže by porovnání vycházelo různě vždycky (viz `PanelHeadNoticeTests`).
    @MainActor private static func pixels(of view: some View) throws -> Data {
        let renderer = ImageRenderer(content: view.frame(width: 300, height: 200))
        renderer.scale = 1
        let image = try #require(renderer.nsImage)
        let bitmap = try #require(image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
        let bytes = try #require(bitmap.bitmapData)
        return Data(bytes: bytes, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
    }

    /// Součet šířky jednoho prvku v řádku — tatáž tabulka, jakou používá `Policy` uvnitř.
    private static func width(of chip: Policy.LabelChip, metrics: Policy.LabelChipMetrics) -> Double {
        switch chip {
        case .label(let label, let maxWidth): min(metrics.chipWidth(label), maxWidth ?? .infinity)
        case .more(let count): metrics.moreWidth(count)
        case .add: metrics.addWidth
        }
    }

    /// Blok tak, jak ho skládá panel: **vlastní PR s povolenou branou**, tedy s oběma akcemi — to je
    /// ta nejplnější podoba, a co se vejde tam, vejde se i na cizí PR.
    @MainActor private static func view(panelWidth: Double) -> PanelMetadataView {
        PanelMetadataView(
            state: .loaded(
                PullRequestMetadata(
                    labels: labels,
                    reviewers: [
                        // Nejdelší kombinace: blokující odpověď a login, který se do panelu nevejde.
                        RequestedReviewer(login: "katerina-prochazkova-mala", answer: .changesRequested),
                        RequestedReviewer(login: "babakks", answer: .approved),
                        RequestedReviewer(login: "sergiou87", answer: .waiting),
                    ],
                    // Tým s dlouhým slugem: druhý druh řádku, který se má do panelu vejít.
                    teams: ["ajda-swimlane-platform-architecture"]
                ),
                updatedAt: Date(timeIntervalSince1970: 100)
            ),
            editing: .allowed,
            repo: repo,
            contentWidth: PanelMetadataView.contentWidth(inPanelOf: panelWidth),
            known: labels,
            candidates: [.person("odinuv"), .team("ajda-swimlane")]
        )
    }

    /// Kam by šel nový label (#413). V těchhle tvrzeních se nekreslí — panel ho jen předává nabídce.
    private static let repo = RepoID(owner: "keboola", name: "vault")
}
