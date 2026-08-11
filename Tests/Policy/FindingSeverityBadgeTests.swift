import Foundation
import Testing

@testable import PRism

/// Odznak závažnosti u nálezu (#150) — čistá funkce, takže se dá vyčerpat výčtem.
///
/// Nejcennější tvrzení téhle sady je to, že se `blokuje` **neztratí**: `vyřešeno` je tvrzení
/// modelu, kdežto `blokuje` je fakt o tom, co drží merge, a nález s `vyřešeno` se dál počítá
/// i dál blokuje. Kdyby ho odznak spolkl, řádek by tvrdil „hotovo“ — a rozbilo by se to potichu,
/// protože obojí vypadá na obrazovce správně, dokud si toho člověk nevšimne.
@Suite("Odznak závažnosti u nálezu")
struct FindingSeverityBadgeTests {
    private func status(_ verdict: RecheckStatus.Verdict) -> RecheckStatus {
        RecheckStatus(verdict: verdict, note: "opraveno v abc1234")
    }

    private func dismissal(_ reason: FindingDismissal.Reason = .invalid) -> FindingDismissal {
        FindingDismissal(reason: reason, dismissedAt: Date(timeIntervalSince1970: 1_700_000_000))
    }

    /// Tohle je ta věta, kvůli které sada existuje.
    @Test("Vyřešeno nesundá blokuje")
    func resolvedNeverSwallowsBlocking() {
        let badge = Policy.severityBadge(isBlocking: true, recheck: status(.resolved), dismissal: nil)

        #expect(badge == .resolved(status(.resolved), blocking: true))
        #expect(badge.showsBlocking)
        #expect(badge.strikesFindingText)
    }

    @Test("Vyřešený nález, který neblokuje, odznak dostane taky")
    func resolvedShowsWithoutBlocking() {
        let badge = Policy.severityBadge(isBlocking: false, recheck: status(.resolved), dismissal: nil)

        #expect(badge == .resolved(status(.resolved), blocking: false))
        #expect(!badge.showsBlocking)
        #expect(badge.strikesFindingText)
    }

    /// Přeškrtnutí a `vyřešeno` má **jedině** `resolved`. „Z kódu se to nedá poznat“ ani „pořád
    /// platí“ nejsou dobrá zpráva a závažnost se u nich nesmí pohnout.
    @Test("Pořád platí a nejasné závažnost nemění")
    func otherVerdictsLeaveSeverityAlone() {
        for verdict in [RecheckStatus.Verdict.stillApplies, .unclear] {
            let blocking = Policy.severityBadge(isBlocking: true, recheck: status(verdict), dismissal: nil)
            let plain = Policy.severityBadge(isBlocking: false, recheck: status(verdict), dismissal: nil)

            #expect(blocking == .blocking)
            #expect(plain == .none)
            #expect(!blocking.strikesFindingText)
            #expect(!plain.strikesFindingText)
        }
    }

    @Test("Bez kontroly zůstává závažnost, jak byla")
    func withoutARecheckNothingChanges() {
        #expect(Policy.severityBadge(isBlocking: true, recheck: nil, dismissal: nil) == .blocking)
        #expect(Policy.severityBadge(isBlocking: false, recheck: nil, dismissal: nil) == .none)
    }

    /// Odmítnutí je rozhodnutí **člověka** a přebíjí tvrzení modelu. A hlavně: odmítnutý nález se
    /// **nepřeškrtává** — celořádkové „nepočítá se“ nosí `DismissedRowStyle` a dva různé důsledky
    /// nesmí mít jeden obrázek.
    @Test("Odmítnutí přebíjí kontrolu a nepřeškrtává")
    func dismissalWinsOverTheRecheck() {
        for reason in FindingDismissal.Reason.allCases {
            let badge = Policy.severityBadge(
                isBlocking: true,
                recheck: status(.resolved),
                dismissal: dismissal(reason)
            )

            #expect(badge == .dismissed(reason))
            #expect(!badge.strikesFindingText)
            #expect(!badge.showsBlocking)
        }
    }

    // MARK: - Skupina nálezů na jednom místě

    private func group(
        _ findings: [Finding],
        rechecks: [FindingKey: RecheckStatus] = [:],
        dismissals: [FindingKey: FindingDismissal] = [:]
    ) -> FindingGroup {
        let groups = Policy.groups(of: findings, dismissals: dismissals, rechecks: rechecks)
        return groups[0]
    }

    @Test("Skupina s jediným vyřešeným nálezem")
    func aGroupWithOneResolvedFinding() {
        let finding = makeFinding(file: "App/Main.swift", line: 8)
        let badge = Policy.severityBadge(
            of: group([finding], rechecks: [Policy.key(of: finding): status(.resolved)])
        )

        #expect(badge == .resolved(status(.resolved), blocking: true))
    }

    /// Dva nálezy na jednom řádku a jen jeden opravený je zrovna ten případ, kdy by odznak za
    /// skupinu lhal — a přeškrtl by shrnutí nálezu, který pořád platí.
    @Test("Skupina mluví za všechny platné nálezy, ne za první")
    func aGroupSpeaksForEveryActiveFinding() {
        let resolved = makeFinding(file: "App/Main.swift", line: 8, summary: "první", reviewer: "a")
        let stays = makeFinding(file: "App/Main.swift", line: 8, summary: "druhý", reviewer: "b")
        let badge = Policy.severityBadge(of: group(
            [resolved, stays],
            rechecks: [
                Policy.key(of: resolved): status(.resolved),
                Policy.key(of: stays): status(.stillApplies),
            ]
        ))

        #expect(badge == .blocking)
        #expect(!badge.strikesFindingText)
    }

    /// Nález, na který kontrola neodpověděla, není vyřešený nález.
    @Test("Nezodpovězený nález vyřešeno zháší")
    func anUnansweredFindingKeepsTheGroupOpen() {
        let resolved = makeFinding(file: "App/Main.swift", line: 8, summary: "první", reviewer: "a")
        let silent = makeFinding(file: "App/Main.swift", line: 8, summary: "druhý", reviewer: "b")
        let badge = Policy.severityBadge(of: group(
            [resolved, silent],
            rechecks: [Policy.key(of: resolved): status(.resolved)]
        ))

        #expect(badge == .blocking)
    }

    /// Odmítnutý nález ve skupině se nepočítá — ani do závažnosti, ani do toho, komu kontrola
    /// odpověděla. Tatáž úvaha jako u proužku bubliny, který přestane křičet, když ten jeden
    /// blokující nález zamítnu.
    @Test("Odmítnutý nález ve skupině vyřešeno nebrání")
    func aDismissedSiblingDoesNotBlockResolved() {
        let resolved = makeFinding(file: "App/Main.swift", line: 8, summary: "první", reviewer: "a")
        let gone = makeFinding(file: "App/Main.swift", line: 8, summary: "druhý", reviewer: "b")
        let badge = Policy.severityBadge(of: group(
            [resolved, gone],
            rechecks: [Policy.key(of: resolved): status(.resolved)],
            dismissals: [Policy.key(of: gone): dismissal()]
        ))

        #expect(badge == .resolved(status(.resolved), blocking: true))
    }

    @Test("Skupina bez platného nálezu je odmítnutá")
    func aGroupWithoutActiveFindingsIsDismissed() {
        let finding = makeFinding(file: "App/Main.swift", line: 8)
        let badge = Policy.severityBadge(of: group(
            [finding],
            rechecks: [Policy.key(of: finding): status(.resolved)],
            dismissals: [Policy.key(of: finding): dismissal(.irrelevant)]
        ))

        #expect(badge == .dismissed(.irrelevant))
        #expect(!badge.strikesFindingText)
    }

    /// Blokující sada je parametr, ne konstanta: nález, který v ní není, `vyřešeno` dostane taky —
    /// jen bez `blokuje`.
    @Test("Blokující sada se u skupiny respektuje")
    func theBlockingCategoriesAreHonored() {
        let finding = makeFinding(file: "App/Main.swift", line: 8, category: "style")
        let badge = Policy.severityBadge(
            of: group([finding], rechecks: [Policy.key(of: finding): status(.resolved)]),
            categories: ["correctness"]
        )

        #expect(badge == .resolved(status(.resolved), blocking: false))
    }

    // MARK: - Cesta do okna

    /// Karta v panelu i řádek tabulky se ptají téže funkce. Kdyby si každý rozhodoval sám,
    /// rozešly by se — a jedna obrazovka by tvrdila `vyřešeno` a druhá `blokuje` o tomtéž nálezu.
    @Test("Karta a řádek tabulky vidí tentýž odznak")
    func theCardAndTheTableRowAgree() throws {
        let finding = makeFinding(file: "App/Main.swift", line: 8)
        let rechecks = [Policy.key(of: finding): status(.resolved)]
        let card = try #require(FindingRow.rows(of: [finding], rechecks: rechecks).first)
        let row = try #require(FindingTableRow.rows(of: [finding], sort: nil, rechecks: rechecks).first)

        #expect(card.severityBadge == .resolved(status(.resolved), blocking: true))
        #expect(row.severityBadge == card.severityBadge)
        // Výstraha na kartě se řídí odznakem, takže je to tatáž pravda, ne druhá podmínka.
        #expect(card.showsBlockingWarning)
    }

    @Test("Odmítnutý nález v tabulce zůstává odmítnutý, ne vyřešený")
    func aDismissedRowStaysDismissed() throws {
        let finding = makeFinding(file: "App/Main.swift", line: 8)
        let row = try #require(FindingTableRow.rows(
            of: [finding],
            sort: nil,
            dismissals: [Policy.key(of: finding): dismissal()],
            rechecks: [Policy.key(of: finding): status(.resolved)]
        ).first)

        #expect(row.severityBadge == .dismissed(.invalid))
        #expect(!row.severityBadge.strikesFindingText)
    }
}
