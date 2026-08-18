import Foundation
import Testing

@testable import PRism

/// Kolik stojí hlídání cizí aktivity (#335) — tedy to podstatné rozhodnutí celého issue.
///
/// Tik pollingu je jeden search dotaz; plná konverzace pro všechna vlastní PR by z něj udělala
/// `1 + N`. Sada tvrdí všechny tři pojistky naráz: **předfiltr podle `updatedAt`** (na klidný den
/// nula dotazů), **vlastní interval** a **strop na jednu rozhlídku**. Všechny tři jsou tvrzení
/// o tom, co se **nestane** — a to je ten druh chyby, který se pozná až na účtu za API.
@Suite("Policy.activitySweep — cena hlídání vlastních PR (#335)")
struct ActivitySweepTests {
    private let mine: Set<String> = ["ondrajodas"]
    private let now = Date(timeIntervalSince1970: 10_000)

    private func summary(
        _ identifier: String,
        author: String = "ondrajodas",
        updated seconds: TimeInterval = 5000
    ) -> PullRequestSummary {
        let id = PRIdentifier(identifier)!
        return PullRequestSummary(
            id: id,
            title: "titulek",
            author: author,
            url: URL(string: "https://github.com/\(id.repo)/pull/\(id.number)")!,
            updatedAt: Date(timeIntervalSince1970: seconds),
            state: .open
        )
    }

    private func sweep(
        _ pullRequests: [PullRequestSummary],
        loaded: [PRIdentifier: Date] = [:],
        now: Date? = nil,
        lastSweep: Date? = nil,
        limit: Int = Policy.activitySweepLimit
    ) -> [PRIdentifier] {
        Policy.activitySweep(
            of: pullRequests,
            mine: mine,
            loadedAt: { loaded[$0] },
            now: now ?? self.now,
            lastSweep: lastSweep,
            limit: limit
        )
    }

    /// **Tvrzení, že se nic nestalo**: cizí PR se na diskuzi neptá. Na cizím PR je moje práce
    /// spustit review, ne hlídat diskuzi — a kdyby se ptal, byl by z toho `1 + N` dotazů nad celou
    /// frontou, tedy třináct místo dvou.
    @Test("Cizí PR se neptá")
    func doesNotAskAboutOtherPeoplesPullRequests() {
        let list = [summary("keboola/vault#85", author: "odinuv"), summary("cli/cli#1", author: "kolega")]

        #expect(sweep(list).isEmpty)
    }

    /// **Tvrzení, že se nic nestalo**: dokud se `updatedAt` nepohnul, konverzace v paměti platí
    /// a nikdo se neptá. To je ten předfiltr, kvůli kterému je klidný den zadarmo.
    @Test("Beze změny updatedAt se neptá nikdo")
    func staysQuietWhileNothingChanged() {
        let pr = summary("ondrajodas/PRism#324", updated: 5000)

        #expect(sweep([pr], loaded: [pr.id: Date(timeIntervalSince1970: 5000)]).isEmpty)
    }

    @Test("Posunutý updatedAt se zeptá")
    func asksWhenUpdatedAtMoved() {
        let pr = summary("ondrajodas/PRism#324", updated: 6000)

        #expect(sweep([pr], loaded: [pr.id: Date(timeIntervalSince1970: 5000)]) == [pr.id])
        // A PR, o kterém konverzaci nemáme vůbec (nebo se nepovedla načíst), taky — selhaná
        // rozhlídka se tím zkusí znovu při té příští.
        #expect(sweep([pr]) == [pr.id])
    }

    @Test("Do intervalu se druhá rozhlídka nevejde")
    func honoursItsOwnInterval() {
        let pr = summary("ondrajodas/PRism#324")
        let justNow = now.addingTimeInterval(-60)

        #expect(sweep([pr], lastSweep: justNow).isEmpty)
        #expect(sweep([pr], lastSweep: now.addingTimeInterval(-Policy.activitySweepInterval)) == [pr.id])
    }

    /// Klidná chvíle okno **nespotřebuje**: razítko posouvá až rozhlídka, která se doopravdy ptala
    /// (viz `AppStore.refreshOwnActivity`). Kdyby ho posouval i průchod, který nic nenašel, čekalo
    /// by se pět minut zrovna na komentář, který přišel vteřinu po tiku.
    @Test("Prázdný průchod je zdarma a okno nespotřebuje")
    func anEmptyPassCostsNothing() {
        let pr = summary("ondrajodas/PRism#324", updated: 5000)
        let loaded = [pr.id: Date(timeIntervalSince1970: 5000)]

        #expect(sweep([pr], loaded: loaded, lastSweep: nil).isEmpty)
        // Vteřinu po něm už se změna zeptá, protože se razítko nikam neposunulo.
        #expect(sweep([pr], loaded: [:], lastSweep: nil) == [pr.id])
    }

    /// Strop je tu kvůli **bouři**: kdyby se naráz pohnulo šest PR, jeden průchod dotáhne tři
    /// a zbytek dojde na příští. Nejvyšší cena je tím shora omezená.
    @Test("Strop uřízne to nejstarší, ne náhodné")
    func capsOnePassAtTheLimit() {
        // Seznam je řazený `Policy.sorted`, tedy od naposledy změněného — strop tedy nechává to,
        // co se změnilo naposled, a čekat nechá to nejstarší.
        let list = (1...6).map { summary("ondrajodas/PRism#\($0)", updated: 6000 - Double($0)) }

        let asked = sweep(list)

        #expect(asked.count == Policy.activitySweepLimit)
        #expect(asked == list.prefix(Policy.activitySweepLimit).map(\.id))
    }

    /// Prázdná množina loginů znamená „nikdo nejsem“ (#330), takže se nemá ptát nikdo — jinak by se
    /// při selhaném `gh api user` tahala konverzace celé fronty.
    @Test("Bez loginu se neptá nikdo")
    func staysQuietWithoutAViewer() {
        let list = [summary("ondrajodas/PRism#324")]

        #expect(Policy.activitySweep(
            of: list,
            mine: [],
            loadedAt: { _ in nil },
            now: now,
            lastSweep: nil
        ).isEmpty)
    }

    /// Interval i strop jsou **konstanty v `Policy`**, ne klíče v konfiguraci: je to pojistka proti
    /// ceně, ne předvolba. Test to drží jako záznam čísla, se kterým se počítalo.
    @Test("Cena jednoho tiku je shora omezená")
    func theCostPerTickIsBounded() {
        #expect(Policy.activitySweepInterval == 300)
        #expect(Policy.activitySweepLimit == 3)
        // Tři dotazy za pět minut, tedy 0,6 na minutový tik — proti `1 + N` každou minutu.
        #expect(Double(Policy.activitySweepLimit) / (Policy.activitySweepInterval / 60) < 1)
    }
}
