import AppKit
import Foundation
import SwiftUI
import Testing

@testable import PRism

/// Šířka `Přehledu` (#291): **nic se nesmí nakreslit mimo tab.**
///
/// Vzniklo z regrese, kterou přinesla #279: sazba Markdownu přešla z pružného `frame(maxWidth:
/// .infinity)` na `filling()`, tedy na **konkrétní šířku z prostředí** — a `OverviewView`
/// tu šířku nezúžil o svá odsazení, takže popis dostal celou šířku tabu a karta kolem něj vyšla
/// o 58 bodů širší. Vpravo pak chyběla hrana a `Otevřít na GitHubu` bylo odříznuté.
///
/// **Jak se to měří, drží `OverflowProbe`** — jedno místo pro tuhle suitu i pro taby bez panelu
/// (#294), včetně toho, proč se čtou pixely a proč se obsah bere bez `ScrollView`u.
///
/// **Pásmo šířek, ne jedna** (poučení z #236): chyba tohohle druhu je konstantní přesah, ale text
/// se v každé šířce zalomí jinak, takže jediná šířka umí projít náhodou.
@MainActor
@Suite("Šířka Přehledu (#291)")
struct OverviewWidthTests {
    /// Šířky, ve kterých `Přehled` doopravdy stojí. Spodní kraj je 128 bodů, a není to teoretické
    /// číslo: okno má podlahu 700, rail bere 52 a panel nálezů se dá vytáhnout na 520. `Přehled`
    /// panel má i po #294, takže to pásmo platí dál.
    private let widths: [CGFloat] = [128, 200, 320, 420, 560, 720, 900, 1180]

    @Test("Popis PR nepřeteče mimo tab v žádné šířce")
    func markdownDescriptionStaysInside() throws {
        for width in widths {
            let overflow = try overflow(width: width, description: Self.description, label: "popis")
            #expect(overflow == 0, "šířka \(Int(width)): přeteklo \(overflow) bodů vpravo")
        }
    }

    /// Prázdné a nedoručené stavy `Přehledu` (`Načítám popis…` proti `Autor k PR nic nenapsal.`)
    /// zůstávají rozlišené — a ani jeden z nich nesmí přetéct. Jsou to jiné podstromy než sazba,
    /// takže se měří zvlášť.
    @Test("Nenačtený i prázdný popis zůstanou uvnitř")
    func placeholderStatesStayInside() throws {
        for width in widths {
            for description in [nil, ""] as [String?] {
                let label = description == nil ? "nenacteny" : "prazdny"
                let overflow = try overflow(width: width, description: description, label: label)
                #expect(overflow == 0, "šířka \(Int(width)), \(label) popis: přeteklo \(overflow) bodů")
            }
        }
    }

    /// Banner „od minule“ a dlaždice s fakty jsou v `Přehledu` sourozenci karty s popisem, takže
    /// se roztáhnou na její šířku. Přetéct proto umí i tehdy, když si o šířku samy neříkají.
    @Test("Banner a dlaždice nepřetečou ani nad širokým popisem")
    func siblingsStayInside() throws {
        for width in widths {
            let overflow = try overflow(
                width: width,
                description: Self.description,
                facts: Self.facts,
                changes: Self.changes,
                movedHead: "9c1de0212ab",
                label: "vse"
            )
            #expect(overflow == 0, "šířka \(Int(width)): přeteklo \(overflow) bodů vpravo")
        }
    }

    /// Řada pod odrážkami — odznak `nálezy zastaraly` a dvě tlačítka (#284).
    ///
    /// Je to nejužší místo `Přehledu`: tři prvky vedle sebe mají dohromady přes 300 bodů, kdežto
    /// tab začíná na 128.
    ///
    /// **Tvrdí to jen to, co změří: nic se nenakreslilo mimo tab.** Že se řada v úzkém tabu
    /// *zlomí do sloupce* místo aby se popisky zkrátily na `Pust…`, tenhle test **nechytá** —
    /// ověřeno vložením regrese, s pevnou řadou zůstal zelený, protože zkrácený popisek nepřeteče.
    /// Na to je `SinceLastVisitActionsTests`, který počítá šířky. Obojí je potřeba: přetečení je
    /// jiná chyba než zkrácení a `NSScrollView` z něj navíc na renderu udělá skoro opravený
    /// stav (to je celá #291).
    @Test("Odznak a obě tlačítka se vejdou do každé šířky")
    func sinceLastVisitActionsStayInside() throws {
        for width in widths {
            let overflow = try overflow(
                width: width,
                description: Self.description,
                facts: Self.facts,
                changes: Self.changes,
                isStale: true,
                hasStaleFindings: true,
                movedHead: "9c1de0212ab",
                offersAdded: true,
                label: "akce"
            )
            #expect(overflow == 0, "šířka \(Int(width)): přeteklo \(overflow) bodů vpravo")
        }
    }

    // MARK: - Měření

    private func overflow(
        width: CGFloat,
        description: String?,
        facts: PullRequestFacts = PullRequestFacts(tiles: []),
        changes: VisitChanges = .none,
        isStale: Bool = false,
        hasStaleFindings: Bool = false,
        movedHead: String? = nil,
        offersAdded: Bool = false,
        label: String
    ) throws -> Int {
        let probe = OverflowProbe(width: width, name: "prehled-\(label)-\(Int(width))")
        return try probe.overflow(of: OverviewView(
            description: description,
            facts: facts,
            changes: changes,
            lastVisit: Date(timeIntervalSince1970: 1_754_000_000),
            isStale: isStale,
            hasStaleFindings: hasStaleFindings,
            movedHead: movedHead,
            rerun: isStale ? {} : nil,
            showAdded: offersAdded ? {} : nil,
            pullRequest: Self.pullRequest
        ).content)
    }

    private static let pullRequest = PullRequestSummary(
        id: PRIdentifier(repo: RepoID(owner: "cli", name: "cli"), number: 14013),
        title: "Route autolink requests through api.Client",
        author: "williammartin",
        url: URL(string: "https://github.com/cli/cli/pull/14013")!,
        updatedAt: Date(timeIntervalSince1970: 1_754_000_000),
        state: .open
    )

    /// Popis, ve kterém je od každého bloku aspoň jeden — nadpisy, próza, seznam, citace, výstraha
    /// i blok kódu. `filling()` je v každém z nich zvlášť, takže jeden odstavec by změřil jeden.
    private static let description = """
        ## Popis

        Odstavec s **tučným**, `inline kódem` a [odkazem](https://github.com), dost dlouhý na to,
        aby se v úzkém tabu zalomil na několik řádků a nešel vyřešit zkrácením.

        - první odrážka
        - [x] hotová položka
          - zanořená položka, taky dost dlouhá na zalomení v úzkém tabu

        1. číslovaná
        2. a druhá

        > citace od kolegy
        > ## nadpis v citaci

        > [!NOTE]
        > Poznámka od bota, opět dost dlouhá na to, aby se v úzkém tabu zalomila.

        ```swift
        let x = 1
        ```
        """

    private static let facts = PullRequestFacts(
        tiles: [
            .init(caption: "Commity", value: "12", note: "3 nové"),
            .init(caption: "Soubory", value: "8", note: "2 s nálezem"),
            .init(caption: "Hlava", value: "abc1234", isMonospaced: true),
            .init(caption: "Nálezy proti", value: "def5678", isMonospaced: true, isStale: true),
        ]
    )

    /// Banner „od minule“ potřebuje aspoň jednu položku, aby se vůbec nakreslil. Force push je na to
    /// nejhustší řádek — nese i větu o tom, která sha na větvi už není.
    private static let changes = VisitChanges(
        commits: [],
        forcePushes: [
            TimelineEvent(
                id: "1",
                kind: .forcePushed(before: "4f2ac9188cd", after: "9c1de0212ab"),
                actor: EventActor(login: "odinuv", avatarURL: nil, isBot: false),
                at: Date(timeIntervalSince1970: 1_753_900_000)
            )
        ],
        events: [],
        reviews: [],
        comments: []
    )
}
