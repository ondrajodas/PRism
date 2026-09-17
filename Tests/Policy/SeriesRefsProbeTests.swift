import Foundation
import Testing

@testable import PRism

/// Na větve kterých PR se tik zeptá (#513) a jak se to skládá s dotazem na hlavy (#420).
///
/// **Nejcennější tvrzení jsou o počtu dotazů**: na klidný tik se neptáme vůbec, na pohnutý jednou —
/// a obě rozhlídky jdou **jedním** seznamem, protože se ptají na týž uzel téhož dotazu. Kdyby se to
/// rozpadlo na dva dotazy, vypadala by aplikace stejně a platilo by se dvakrát.
@Suite("Policy — dotaz na větve pro sérii (#513)")
struct SeriesRefsProbeTests {
    private let mine: Set<String> = ["ondrajodas"]
    private let moment = Date(timeIntervalSince1970: 1_700_000_000)

    private func summary(
        _ text: String,
        author: String = "odinuv",
        state: PullRequestState = .open,
        updatedAt: Date? = nil
    ) -> PullRequestSummary {
        let id = PRIdentifier(text)!
        return PullRequestSummary(
            id: id,
            title: "titulek",
            author: author,
            url: URL(string: "https://github.com/\(id.repo)/pull/\(id.number)")!,
            updatedAt: updatedAt ?? moment,
            state: state
        )
    }

    private func probe(
        _ summaries: [PullRequestSummary],
        probed: [PRIdentifier: Date] = [:],
        limit: Int = Policy.staleHeadProbeLimit
    ) -> [PRIdentifier] {
        Policy.seriesRefsProbe(
            of: summaries,
            mine: mine,
            probedAt: { probed[$0] },
            limit: limit
        )
    }
}

// MARK: - Koho se zeptat

extension SeriesRefsProbeTests {
    /// PR, na který se aplikace **nikdy neptala**, je přesně to, na co se ptáme — i když se od
    /// startu nic nestalo. Bez toho by se série po restartu nedozvěděla vůbec nic.
    @Test("PR bez razítka se zeptá i bez posunu updatedAt")
    func asksAboutUnprobedPullRequests() {
        #expect(probe([summary("cli/cli#1")]) == [PRIdentifier("cli/cli#1")!])
    }

    /// Jakmile razítko sedí a `updatedAt` se nepohnul, **neptáme se**: base větev se bez posunu
    /// `updatedAt` změnit nemá čím. Tohle je ta polovina, na které stojí „na klidný tik nula“.
    ///
    /// **Platí to i tehdy, když odpověď větve nenesla** — a je to rozhodnutí, ne díra: PR, u kterého
    /// by se „nevíme“ počítalo za důvod k dotazu, by se ptal každou minutu donekonečna.
    @Test("Klidný tik se na nic neptá")
    func staysQuiet() {
        let pr = PRIdentifier("cli/cli#1")!

        #expect(probe([summary("cli/cli#1")], probed: [pr: moment]).isEmpty)
    }

    /// Posunuté `updatedAt` znamená zeptat se znovu — právě tak se pozná, že po mergi spodního PR
    /// přepnul GitHub base toho horního na `main` a série se rozpadla.
    @Test("Posunuté updatedAt se zeptá znovu")
    func asksAgainAfterAChange() {
        let pr = PRIdentifier("cli/cli#1")!
        let summaries = [summary("cli/cli#1", updatedAt: moment.addingTimeInterval(60))]

        #expect(probe(summaries, probed: [pr: moment]) == [pr])
    }

    /// **Vlastní PR se sem neptají**: jejich větve dotahuje každý tik rozhlídka po slévatelnosti
    /// (#572), takže by to bylo druhé volání za tutéž hodnotu.
    @Test("Vlastní PR se neptá")
    func skipsOwnPullRequests() {
        #expect(probe([summary("cli/cli#1", author: "ondrajodas")]).isEmpty)
    }

    /// Zavřené a mergnuté PR v sérii nejsou (`Policy.series`), takže by dotaz na ně byl dotaz za
    /// odpověď, kterou nikdo nepřečte.
    @Test("Zavřené a mergnuté se neptáme")
    func skipsClosedPullRequests() {
        #expect(probe([summary("cli/cli#1", state: .merged), summary("cli/cli#2", state: .closed)]).isEmpty)
    }

    /// Rozpracovaný PR se ptá — v sérii být může.
    @Test("Draft se zeptá")
    func asksAboutDrafts() {
        #expect(probe([summary("cli/cli#1", state: .draft)]) == [PRIdentifier("cli/cli#1")!])
    }

    /// Strop ohraničuje **velikost dokumentu**, ne počet volání: co se nevejde, se zeptá příští tik.
    @Test("Strop uřízne zbytek")
    func stopsAtTheLimit() {
        let summaries = (1...5).map { summary("cli/cli#\($0)") }

        #expect(probe(summaries, limit: 2).count == 2)
    }
}

// MARK: - Jeden dotaz ze dvou rozhlídek

extension SeriesRefsProbeTests {
    /// **Dvě rozhlídky, jeden seznam.** Ptají se na týž uzel téhož dotazu, takže se spojí — a PR,
    /// který je v obou, je v dotazu jednou.
    @Test("Sjednocení nemá duplicity a drží pořadí")
    func mergesBothProbes() {
        let a = PRIdentifier("cli/cli#1")!
        let b = PRIdentifier("cli/cli#2")!
        let c = PRIdentifier("cli/cli#3")!

        #expect(Policy.headProbe(stale: [a, b], refs: [b, c]) == [a, b, c])
    }

    /// **Zastaralé nálezy jdou první.** Když se do dokumentu obojí nevejde, ustoupí rozhlídka po
    /// větvích: série se dozví za minutu, kdežto zastaralé nálezy jsou ta událost, po které je
    /// práce k zahození.
    @Test("Strop ukrojí větve, ne zastaralé nálezy")
    func prefersStaleHeads() {
        let stale = [PRIdentifier("cli/cli#1")!, PRIdentifier("cli/cli#2")!]
        let refs = [PRIdentifier("cli/cli#3")!]

        #expect(Policy.headProbe(stale: stale, refs: refs, limit: 2) == stale)
    }

    /// Prázdno z obou rozhlídek znamená **žádný dotaz** — a to je ten klidný tik.
    @Test("Dvě prázdné rozhlídky nedají dotaz")
    func asksNothingWhenBothAreEmpty() {
        #expect(Policy.headProbe(stale: [], refs: []).isEmpty)
    }
}
