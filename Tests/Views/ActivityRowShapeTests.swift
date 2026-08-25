import AppKit
import SwiftUI
import Testing

@testable import PRism

/// Úzký tvar řádku dění (#443) — ten, kterým se platí za to, že blok stojí v **pravém sloupci**
/// dashboardu, a ne přes celou šířku pod oběma sloupci.
///
/// Testuje se **obojí naráz, a jinými měřidly**, protože jedno bez druhého by prošlo i nad
/// rozbitou verzí:
///
/// - **výškou** to, že se řádek do 456 bodů vejde na jednu řádku (24 b) a že celý řádek ze sekce
///   by se tam nevešel. To je celý důvod, proč úzký tvar existuje;
/// - **přirozenou šířkou** to, co v něm **není**. Výška na tuhle otázku odpovědět neumí: úzký
///   řádek se nezalamuje, takže vrácený chip `bez banneru` ani sha by ji nezvedly ani o bod —
///   jen by ukously kus titulku. Přirozená šířka je proti tomu součet toho, co se doopravdy
///   kreslí, takže se v ní každý vrácený údaj projeví.
///
/// **Proč `fittingSize.width` je přirozená šířka i se `Spacer`em na konci**: `fittingSize` se ptá
/// nespecifikovaným návrhem a `Spacer(minLength: 0)` na něj odpoví nulou. Je to změřené — kdyby
/// odpovídal jinak, vyšly by všechny varianty stejně a spadlo by tvrzení, že se šířka s titulkem
/// **mění**; to je v téhle sadě schválně, jako protiváha k těm ostatním.
@MainActor
@Suite("Úzký řádek dění (#443)")
struct ActivityRowShapeTests {
    /// Pravý sloupec dashboardu — `1fr` z `1.45fr 1fr` v okně z návrhu, tedy 456 z 1134 bodů.
    private static let columnWidth = 456.0
    /// Strop jedné řádky. V návrhu má `.tl-line` `min-height: 24px`; pár bodů rezervy je na
    /// zaokrouhlení sazby, ne na druhé patro — to začíná někde nad 40.
    private static let oneLine = 28.0

    /// **Kvůli tomuhle úzký tvar je.** Pět položek ze sekce 31 návrhu doslova: v úzkém tvaru se
    /// každá vejde na jednu řádku, v plném ani jedna.
    @Test("V 456 bodech se úzký řádek vejde na jednu řádku, plný ne")
    func fitsASingleLineInTheColumn() {
        for event in Self.mockupEvents {
            let slim = height(of: event, at: .dashboard)
            let full = height(of: event, at: .section)

            #expect(slim <= Self.oneLine, "„\(event.headline)“ v úzkém tvaru \(slim) b")
            #expect(full > Self.oneLine, "„\(event.headline)“ v plném tvaru \(full) b — vešel by se")
        }
    }

    /// **Co se v úzkém tvaru nekreslí**, měřeno přirozenou šířkou: podrobnost, sha a chip
    /// `bez banneru` se z události berou, ale do řádku se nedostanou. V sekci se do něj dostanou
    /// všechny tři, takže tvrzení má i druhou stranu — jinak by prošla verze, která je nekreslí
    /// nikde.
    @Test("Úzký řádek nenese podrobnost, sha ani chip, plný ano")
    func dropsTheDetailTheShaAndTheChip() {
        let bare = Self.event()
        let loaded = Self.event(
            detail: "přišly 3 commity, hlava je teď",
            head: "9c1f0ab2d4e5f60718293a4b5c6d7e8f90a1b2c3",
            wasAnnounced: false
        )

        #expect(naturalWidth(of: loaded, at: .dashboard) == naturalWidth(of: bare, at: .dashboard))
        #expect(naturalWidth(of: loaded, at: .section) > naturalWidth(of: bare, at: .section))
    }

    /// Autor je v sekci součástí souřadnic (`keboola/vault#85 · odinuv`), v úzkém tvaru z nich
    /// zbývá jen `repo#číslo`.
    @Test("Úzký řádek nenese autora, plný ano")
    func dropsTheAuthor() {
        let anonymous = Self.event()
        let signed = Self.event(author: "odinuv")

        #expect(naturalWidth(of: signed, at: .dashboard) == naturalWidth(of: anonymous, at: .dashboard))
        #expect(naturalWidth(of: signed, at: .section) > naturalWidth(of: anonymous, at: .section))
    }

    /// Cíl (`→ Nálezy`, `→ Konverzace`) se v úzkém tvaru nekreslí, takže dvě události, které se
    /// liší jedině tím, kam vedou, jsou v něm stejně široké. Kliknutí na ně přitom vede pořád
    /// jinam — to je v `AppStoreFeedTests`, tohle je jen o kresbě.
    ///
    /// **Dvojice je vybraná podle délky popisku, ne podle druhu**: `fittingSize` vrací celé body,
    /// takže `→ Nálezy` proti `GitHub ↗` vyšlo v sekci **371 : 371** — dva různé popisky, které se
    /// liší o míň než bod. `→ Konverzace` je o pět znaků delší, takže se rozdíl projeví i po
    /// zaokrouhlení a druhá strana tvrzení něco měří.
    @Test("Úzký řádek nekreslí cíl")
    func dropsTheDestination() {
        let toFindings = Self.event(kind: .findings)
        let toConversation = Self.event(kind: .foreignActivity)

        #expect(Policy.destination(of: .findings) != Policy.destination(of: .foreignActivity))
        #expect(naturalWidth(of: toFindings, at: .dashboard) == naturalWidth(of: toConversation, at: .dashboard))
        #expect(naturalWidth(of: toFindings, at: .section) < naturalWidth(of: toConversation, at: .section))
    }

    /// Protiváha ke třem tvrzením výš: měřidlo **není** slepé. Titulek i souřadnice se do úzkého
    /// řádku kreslí, takže se v jeho šířce projeví — bez tohohle by sada procházela i nad řádkem,
    /// který nekreslí vůbec nic.
    @Test("Titulek a souřadnice se v úzkém tvaru projeví")
    func stillCarriesTheHeadlineAndTheSlug() {
        let short = Self.event(headline: "Čisté review")
        let long = Self.event(headline: "odinuv: opravdu to potřebuje ten mutex?")
        let elsewhere = Self.event(pullRequest: "keboola/app-project-restore#91")

        #expect(naturalWidth(of: long, at: .dashboard) > naturalWidth(of: short, at: .dashboard))
        #expect(naturalWidth(of: elsewhere, at: .dashboard) > naturalWidth(of: short, at: .dashboard))
    }

    // MARK: - měřidlo

    /// Výška řádku na dané šířce — tedy to, co si řádek v `VStack`u osy vezme.
    private func height(of event: ActivityEvent, at place: ActivityRowPlace) -> CGFloat {
        NSHostingView(rootView: row(event, at: place).frame(width: Self.columnWidth)).fittingSize.height
    }

    /// Přirozená šířka řádku — bez vnějšího rámce, tedy součet toho, co se v něm doopravdy kreslí.
    private func naturalWidth(of event: ActivityEvent, at place: ActivityRowPlace) -> CGFloat {
        NSHostingView(rootView: row(event, at: place)).fittingSize.width
    }

    /// Hodiny stojí a událost je **starší než dvě hodiny**, takže čas vyjde `.absolute` a je
    /// u všech porovnávaných variant stejně široký. S relativním časem (`před 2 min`) by šířka
    /// záležela na tom, kdy sada běží.
    private func row(_ event: ActivityEvent, at place: ActivityRowPlace) -> some View {
        ActivityRowView(event: event, now: Self.now, place: place, open: { _ in })
    }

    private static let now = Date(timeIntervalSince1970: 1_756_000_000)

    /// Událost, ze které se v jednotlivých tvrzeních mění vždycky **jedna** věc.
    private static func event(
        kind: ActivityEvent.Kind = .findings,
        pullRequest: String = "keboola/vault#85",
        headline: String = "3 nálezy · 1 blokuje",
        detail: String? = nil,
        head: String? = nil,
        wasAnnounced: Bool = true,
        author: String? = nil
    ) -> ActivityEvent {
        ActivityEvent(
            id: "\(kind)|\(pullRequest)|\(headline)",
            kind: kind,
            pullRequest: PRIdentifier(pullRequest)!,
            at: now.addingTimeInterval(-4 * 60 * 60),
            headline: headline,
            detail: detail,
            wasAnnounced: wasAnnounced,
            head: head,
            author: author
        )
    }

    /// Pět položek ze sekce 31 návrhu — včetně té nejdelší, na které se pozná, že se titulek
    /// **ořízne** a nezalomí.
    private static var mockupEvents: [ActivityEvent] {
        [
            event(
                kind: .staleFindings,
                headline: "Nálezy zastaraly",
                detail: "přišly 3 commity, hlava je teď",
                head: "9c1f0ab2d4e5f60718293a4b5c6d7e8f90a1b2c3"
            ),
            event(
                kind: .foreignActivity,
                pullRequest: "keboola/app-project-restore#91",
                headline: "odinuv: opravdu to potřebuje ten mutex?",
                detail: "a 1 review od Copilota"
            ),
            event(headline: "3 nálezy · 1 blokuje", detail: "php-review, security-review"),
            event(
                kind: .newPullRequest,
                headline: "Nový PR k review",
                detail: "chore: modernize dependencies (Symfony 8-ready)",
                author: "odinuv"
            ),
            event(
                kind: .clean,
                pullRequest: "keboola/job-queue-api#402",
                headline: "Čisté review",
                detail: "3 skilly · 1,04 $",
                wasAnnounced: false
            )
        ]
    }
}
