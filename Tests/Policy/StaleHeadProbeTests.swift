import Foundation
import Testing

@testable import PRism

/// Na hlavy kterých PR se tik zeptá (#420) a co z odpovědi plyne.
///
/// Nejcennější tvrzení jsou tady ta o tom, co se **nestane**: na klidný tik se neptáme vůbec,
/// na vlastní PR nikdy (jinak by z dění byl obchvat #332) a na PR bez uložených nálezů taky ne —
/// není co zastarat. Všechna tři se rozbijí potichu: zůstane po nich dotaz každou minutu.
@Suite("Policy — dotaz na hlavy (#420)")
struct StaleHeadProbeTests {
    private let mine: Set<String> = ["ondrajodas"]
    private let moment = Date(timeIntervalSince1970: 1_700_000_000)

    private func summary(
        _ text: String,
        author: String = "odinuv",
        updatedAt: Date? = nil
    ) -> PullRequestSummary {
        let id = PRIdentifier(text)!
        return PullRequestSummary(
            id: id,
            title: "titulek",
            author: author,
            url: URL(string: "https://github.com/\(id.repo)/pull/\(id.number)")!,
            updatedAt: updatedAt ?? moment,
            state: .open
        )
    }

    private func probe(
        _ summaries: [PullRequestSummary],
        withFindings findings: Set<PRIdentifier> = [],
        probed: [PRIdentifier: Date] = [:],
        limit: Int = Policy.staleHeadProbeLimit
    ) -> [PRIdentifier] {
        Policy.staleHeadProbe(
            of: summaries,
            mine: mine,
            hasFindings: { findings.contains($0) },
            probedAt: { probed[$0] },
            limit: limit
        )
    }
}

// MARK: - Koho se zeptat

extension StaleHeadProbeTests {
    /// PR, na kterém leží nálezy a od minula se pohnul, je přesně to, na co se ptáme.
    @Test("PR s nálezy, na kterém se něco stalo, se zeptá")
    func asksAboutAMovedPullRequest() {
        let pr = PRIdentifier("cli/cli#1")!

        #expect(probe([summary("cli/cli#1")], withFindings: [pr]) == [pr])
    }

    /// **Bez nálezů není co zastarat.** Čisté review i nedotčené PR do dotazu nepatří — a je to
    /// zároveň ten předfiltr, který z fronty vybere hrstku.
    @Test("PR bez uložených nálezů se neptá")
    func skipsAPullRequestWithoutFindings() {
        #expect(probe([summary("cli/cli#1")]).isEmpty)
    }

    /// **Brána #332, ne úspora.** O zastaralých nálezech na vlastním PR se nehlásí
    /// (`Policy.isReported`), takže dotaz na ně je dotaz na řádek, který nikdy nevznikne.
    @Test("Vlastní PR se neptá nikdy")
    func skipsOwnPullRequests() {
        let pr = PRIdentifier("cli/cli#1")!
        let summaries = [summary("cli/cli#1", author: "ondrajodas")]

        #expect(probe(summaries, withFindings: [pr]).isEmpty)
        #expect(Policy.isReported(.staleFindings, on: .mine) == false)
    }

    /// **Klidný tik se neptá vůbec** — a to je celá odpověď na „co to přidá na tik“. `updatedAt`
    /// se nepohnul, takže se hlava nemá čím změnit.
    @Test("Nepohnuté updatedAt se neptá")
    func staysQuietOnACalmTick() {
        let pr = PRIdentifier("cli/cli#1")!

        #expect(probe([summary("cli/cli#1")], withFindings: [pr], probed: [pr: moment]).isEmpty)
    }

    /// Posunuté `updatedAt` je jediný signál, který ze searche o pohybu na PR je — takže se ptáme.
    @Test("Posunuté updatedAt se zeptá znovu")
    func asksAgainAfterAnUpdate() {
        let pr = PRIdentifier("cli/cli#1")!
        let later = moment.addingTimeInterval(600)

        let asked = probe(
            [summary("cli/cli#1", updatedAt: later)],
            withFindings: [pr],
            probed: [pr: moment]
        )

        #expect(asked == [pr])
    }

    /// Razítka jsou v paměti, takže po startu chybí všechna — a to je schválně ta chvíle, kdy se
    /// má dohnat, co se stalo, když aplikace neběžela. **Jedním dotazem**, ne jedním na PR.
    @Test("Po startu se zeptá na všechny, které nálezy mají")
    func catchesUpAfterALaunch() {
        let first = PRIdentifier("cli/cli#1")!
        let second = PRIdentifier("vercel/next.js#2")!

        let asked = probe(
            [summary("cli/cli#1"), summary("vercel/next.js#2"), summary("cli/cli#3")],
            withFindings: [first, second]
        )

        #expect(asked == [first, second])
    }
}

// MARK: - Strop

extension StaleHeadProbeTests {
    /// Strop ohraničuje **velikost dokumentu**, ne počet volání: co se nevejde, dojde na příští
    /// tik, protože razítko dostane jedině to, na co se ptalo.
    @Test("Strop uřízne konec seznamu, ne jeho začátek")
    func cutsTheOldestEnd() {
        let summaries = (1...25).map { summary("cli/cli#\($0)") }
        let findings = Set(summaries.map(\.id))

        let asked = probe(summaries, withFindings: findings, limit: 20)

        #expect(asked.count == 20)
        // Pořadí je ze vstupu (`Policy.sorted`, tedy od naposledy změněného), takže se uříznou ta
        // nejstarší — a ta snesou čekat minutu.
        #expect(asked.first == PRIdentifier("cli/cli#1"))
        #expect(asked.last == PRIdentifier("cli/cli#20"))
    }

    /// Strop je konstanta, ne klíč v konfiguraci — a hodnota je z měření (24 aliasů stojí pořád
    /// jeden bod z 5000/h).
    @Test("Strop je dvacet")
    func namesTheLimit() {
        #expect(Policy.staleHeadProbeLimit == 20)
    }
}

// MARK: - Co z odpovědi plyne

extension StaleHeadProbeTests {
    private func record(headSha: String, findings: Int) -> ReviewRecord {
        ReviewRecord(
            pullRequest: PRIdentifier("cli/cli#1")!,
            headSha: headSha,
            runs: [
                makeStoredRun(
                    findings: (0..<findings).map { makeReported(file: "Cart.swift", line: $0 + 1) },
                    headSha: headSha
                )
            ]
        )
    }

    @Test("Rozešlá sha je rozchod s nálezy")
    func reportsTheMismatch() {
        let stale = Policy.staleFindings(of: record(headSha: "4f2ac91", findings: 2), head: "9c1de02")

        #expect(stale?.head == "9c1de02")
        #expect(stale?.findingsHead == "4f2ac91")
        #expect(stale?.hasFindings == true)
    }

    /// Čisté review proti staršímu commitu **je** rozchod — jen se u něj nesmí tvrdit, že něco
    /// zastaralo. Rozhoduje `hasFindings`, ne existence rozchodu.
    @Test("Čisté review dá rozchod bez nálezů")
    func separatesTheCleanRun() {
        let stale = Policy.staleFindings(of: record(headSha: "4f2ac91", findings: 0), head: "9c1de02")

        #expect(stale != nil)
        #expect(stale?.hasFindings == false)
    }

    @Test("Shodná sha není rozchod")
    func staysQuietWhenTheyMatch() {
        #expect(Policy.staleFindings(of: record(headSha: "9c1de02", findings: 3), head: "9c1de02") == nil)
    }

    @Test("Bez záznamu review není co zastarat")
    func staysQuietWithoutARecord() {
        #expect(Policy.staleFindings(of: nil, head: "9c1de02") == nil)
    }

    /// **„Nevím“ se nesmí kreslit jako „zastaralo“.** Chybějící hlava je odpověď GitHubu u PR, na
    /// který nevidíme — a nad ní se nesmí nic tvrdit.
    @Test("Bez dnešní hlavy se rozchod netvrdí")
    func staysQuietWithoutAHead() {
        #expect(Policy.staleFindings(of: record(headSha: "4f2ac91", findings: 2), head: nil) == nil)
    }
}
