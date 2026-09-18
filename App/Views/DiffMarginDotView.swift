import SwiftUI

/// Značka nálezu na hraně okraje (#505) — puntík v barvě druhu, který se kliknutím rozbalí
/// do karty.
///
/// **Jeden typ pro dvě situace**, protože je to jedno pravidlo: *karta, která se nekreslí jako
/// karta, se kreslí jako značka* (`Policy.marginDots`). Složená hrana (`DiffMarginRailView`)
/// nekreslí jako kartu žádnou, rozložená kolona (`DiffMarginView`) nekreslí ty mimo nasazený pás
/// (#469) — a do #505 z nich nebyla na obrazovce ani stopa, což je nález, o kterém se nikdo
/// nedozví.
///
/// **Karta v popoveru je tatáž `FindingBubbleView` jako v okraji**, i se šířkou kolony: odznaky,
/// shoda dvou reviewerů, stav z kontroly (#150), odmítnutí (#113) i řada `Převzít · Neplatí ·
/// Nepatří sem` (#283) se ve složeném stavu nesmí chovat jinak než v rozloženém. Druhá kresba
/// téhož by znamenala, že jedna podoba okraje nabízí akci, kterou druhá nemá.
///
/// **Popover, ne vlastní vrstva nad plochou.** Pravidlo z #483 (co přesahuje rodiče, ořízne každý
/// ořezávající předek) tady platí dvojnásob: hrana je 28 bodů široká a `.clipped()`, takže by
/// karta o 300 bodech neměla kudy ven. Popover je vlastní okno, takže ho neořízne nic; že bere
/// fokus, je u kliknutí správně — u našeptávače emotikonů to byl důvod, proč se zamítl, protože
/// tam se přitom píše.
struct DiffMarginDotView: View {
    let card: DiffMarginCard
    /// Stojí na téhle kartě kurzor procházení nálezů (#187, `⌥↓`)? Dostane rámeček — bez něj by
    /// na složené hraně nebylo poznat, o kterém puntíku lišta mluví.
    var isCurrent = false
    var blockingCategories: Set<String> = Policy.defaultBlockingCategories
    var findingActions: FindingActions?
    var draft = FileDraftActions()

    @State private var isOpen = false

    var body: some View {
        Button { isOpen = true } label: {
            Circle()
                .fill(card.severity.stripe)
                .frame(width: Self.dot, height: Self.dot)
                .padding(Self.ring)
                // Rámeček kurzoru **kolem** puntíku, ne místo něj: barva druhu musí zůstat vidět.
                .overlay {
                    if isCurrent {
                        RoundedRectangle(cornerRadius: 5)
                            .strokeBorder(Palette.ink3, lineWidth: 1)
                    }
                }
                // Klikací je celá plocha značky, ne sedmibodový puntík — trefit se do sedmi bodů
                // je zbytečná práce, tatáž úvaha jako u pruhu se značkou v bublině.
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        // Karta se otevírá **doleva**, tedy nad kód: okraj stojí u pravé hrany okna, takže napravo
        // od něj místo není.
        .popover(isPresented: $isOpen, arrowEdge: .leading) {
            FindingBubbleView(
                group: card.group,
                blockingCategories: blockingCategories,
                draft: draft,
                actions: findingActions,
                // Rozbalená a bez pruhu na sbalení — přesně jako karta v okraji: v popoveru
                // nestojí v cestě kódu, takže sbalit ji není proč.
                disclosure: .expanded,
                toggle: nil,
                placement: .margin
            )
            // **Šířka kolony, ne pružná**: karta se v ní zalamuje stejně jako v rozloženém okraji,
            // takže se text mezi oběma podobami nepřesází.
            .frame(width: Policy.marginColumnWidth(form: .cards))
            .padding(.vertical, 10)
        }
        .help(Policy.marginDotHint(of: card))
        .accessibilityLabel(Policy.marginDotHint(of: card))
    }

    /// Průměr puntíku — tentýž, jaký má značka v bublině (`FindingBubbleView.mark`), takže se obě
    /// podoby nálezu potkávají na jedné velikosti.
    static let dot = 7.0
    /// Vzduch kolem puntíku, do kterého se vejde rámeček kurzoru procházení.
    static let ring = 4.0
    /// Celá plocha značky — z ní se počítá odstrkování na hraně i šířka hrany samotné.
    static var size: Double { dot + 2 * ring }
}
