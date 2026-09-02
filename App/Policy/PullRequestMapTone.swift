import Foundation

/// Co v pásu mapy PR znamená který tón (#501).
///
/// **Existuje proto, aby barvu vydávalo jedno místo pro kresbu i pro legendu.** V zákresu měla
/// legenda barvy dosazené inline (`style="background: var(--crit)"`), tedy druhé místo, které při
/// změně škály nikdo neprojde — a rozejití by nebylo na obrázku vidět, protože obojí je *ta samá
/// barva, jen jinde*. V okně je to táž past: `PullRequestMapView.fill(of:)` kreslí segment
/// i vzorek v legendě, a tenhle výčet je to, na co se ptá.
///
/// **Sedm tónů, ale výplň jsou jen čtyři.** `read` je **krytí** nad výplní (`Policy.mapReadOpacity`),
/// `thread` je svislá čárka a `current` je značka souboru pod výřezem — tři různé kanály, které
/// v legendě stojí vedle barev, protože člověk na obrazovce vidí sedm věcí, ne čtyři. Že se
/// `mapFill(of:)` na ty tři nikdy nezeptá, tvrdí test.
enum PullRequestMapTone: Hashable, Sendable, CaseIterable {
    /// Blokující nález v souboru.
    case blocking
    /// Nález, který neblokuje.
    case findings
    /// Soubor bez nálezu.
    case clean
    /// Nový soubor — tón `ok`, protože na novém souboru není co rozbít.
    case new
    /// Značka `Prošlo` (#500) — tlumení, ne barva.
    case read
    /// Zakotvené vlákno — svislá čárka akcentem.
    case thread
    /// Soubor pod výřezem.
    case current
}

/// Jedna položka legendy pásu (#501).
struct PullRequestMapLegendItem: Hashable, Sendable, Identifiable {
    let tone: PullRequestMapTone
    let label: String

    var id: PullRequestMapTone { tone }
}

/// Jedna řádka vzorků v legendě (#501). **Identita je pořadí**, ne obsah: řádky se legitimně
/// opakují tvarem a je jich pevný počet.
struct PullRequestMapLegendRow: Hashable, Sendable, Identifiable {
    let index: Int
    let items: [PullRequestMapLegendItem]

    var id: Int { index }
}

extension Policy {
    /// Krytí prošlého segmentu. **Jedno místo**: čte ho kresba i vzorek `prošlo` v legendě, a dvě
    /// konstanty by znamenaly, že legenda ukazuje jiný odstín, než jaký je v pásu.
    static let mapReadOpacity = 0.35

    /// Nadpis legendy — v popoveru nad vzorky.
    static let mapLegendTitle = "Co který tón v pásu znamená"

    /// Legenda pásu, **v tom pořadí, v jakém stojí v zákresu**: napřed tři tóny závažnosti, pak
    /// druh souboru a stav značky, nakonec dva kanály, které barvu nenesou.
    ///
    /// Je to `Policy`, protože je to rozhodnutí nad daty (co pás kóduje a jak se to jmenuje), ne
    /// kresba — a protože se tím dá vyčerpávajícím výčtem otestovat, že v legendě **nechybí
    /// tón**, který pás umí nakreslit. Barvu vydává `PullRequestMapView.fill(of:)`.
    static func mapLegend() -> [PullRequestMapLegendItem] {
        [
            PullRequestMapLegendItem(tone: .blocking, label: "blokuje"),
            PullRequestMapLegendItem(tone: .findings, label: "nález"),
            PullRequestMapLegendItem(tone: .new, label: "nový soubor"),
            PullRequestMapLegendItem(tone: .clean, label: "bez nálezu"),
            PullRequestMapLegendItem(tone: .read, label: "prošlo"),
            PullRequestMapLegendItem(tone: .thread, label: "vlákno"),
            PullRequestMapLegendItem(tone: .current, label: "čtu"),
        ]
    }

    /// Legenda po řádkách — zákres ji má jako box o 330 bodech, ve kterém se vzorky **zalomí po
    /// dvou**. Zalomení rozhoduje `Policy`, ne view: je to dělení seznamu, tedy věc, která se dá
    /// vyčerpat výčtem, a v `Grid`u by z toho byl `enumerated()` s tuplem.
    ///
    /// Poslední řádka smí být kratší (významů je sedm), ale **prázdná nikdy** — jinak by v legendě
    /// zbyla mezera po tónu, který se zapomněl pojmenovat.
    static func mapLegendRows(perRow: Int = 2) -> [PullRequestMapLegendRow] {
        let items = mapLegend()
        guard perRow > 0 else { return [PullRequestMapLegendRow(index: 0, items: items)] }
        return stride(from: 0, to: items.count, by: perRow).enumerated().map { order, start in
            PullRequestMapLegendRow(
                index: order,
                items: Array(items[start..<min(start + perRow, items.count)])
            )
        }
    }

    /// Který tón nese **výplň** segmentu.
    ///
    /// **Nejhorší nález přebíjí druh souboru**: nový soubor s blokujícím nálezem je červený, ne
    /// zelený — pás se čte podle závažnosti. Tlumení prošlého se tady **nerozhoduje**, protože to
    /// není výplň, ale krytí nad ní; jinak by `changed` (práce, která se vrátila) musel být pátý
    /// tón výplně.
    static func mapFill(of segment: PullRequestMapSegment) -> PullRequestMapTone {
        switch segment.marker {
        case .blocking: .blocking
        case .findings: .findings
        case nil: segment.isNew ? .new : .clean
        }
    }
}
