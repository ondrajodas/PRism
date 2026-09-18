import Foundation
import Testing

@testable import PRism

/// Zadání pro osmou session (#521) — **vyčerpávajícím výčtem**, protože je to čistá funkce
/// a jediné místo, kde se rozhoduje, co session o pull requestu ví.
///
/// **Nejcennější tvrzení téhle sady je negativní**: ve vstupu **není cesta k repozitáři**. Session
/// nemá jediný nástroj, takže cesta do cache by v zadání byla údaj, který nikomu neslouží a v textu
/// odesílaném na GitHub se umí objevit — a rozbilo by se to potichu, protože by nic nespadlo.
@Suite("Policy — zadání pro tělo review (#521)")
struct ReviewBodyInputTests {
    private func plan(
        adopt: [Finding] = [],
        contested: [FindingKey: AutoDraftDoubt] = [:]
    ) -> AutoDraftPlan {
        AutoDraftPlan(adopt: adopt, contested: contested)
    }

    private func sample(_ id: String, _ body: String, at seconds: Double = 1) -> ReviewVoiceSample {
        ReviewVoiceSample(id: id, at: Date(timeIntervalSince1970: seconds), body: body)
    }

    // MARK: - Co v zadání není

    /// **Negativní test, a je to ten, na kterém tahle session stojí.** Typ `ReviewBodyRequest`
    /// cestu ani nemá kam napsat, ale materiál se skládá z nálezů — a ty cestu k **souboru**
    /// nesou. Tvrdí se tedy, že v zadání není nic, co ukazuje na disk: ani cache aplikace, ani
    /// pracovní strom, ani absolutní cesta.
    @Test("Ve vstupu není cesta k repozitáři ani do cache")
    func neverCarriesARepositoryPath() {
        let material = Policy.reviewBodyInput(
            plan: plan(adopt: [makeFinding(file: "src/Vault/SecretClient.php", line: 81)]),
            voice: [sample("r1", String(repeating: "ó", count: 60))]
        )

        #expect(!material.text.contains("Application Support"))
        #expect(!material.text.contains("/Users/"))
        #expect(!material.text.contains("worktree"))
        // Cesta **uvnitř** repozitáře v zadání být má — je to totéž, co stojí v panelu
        // u komentáře, a bez ní by odstavec nemohl jmenovat soubor.
        #expect(material.text.contains("src/Vault/SecretClient.php:81"))
    }

    /// **Verdikt se do zadání nedává** (rozhodnutí #521): prompt zakazuje verdikt psát, takže
    /// přiložit ho k materiálu by znamenalo pozvat model k obejití pravidla.
    @Test("Ve vstupu není verdikt")
    func neverCarriesAVerdict() {
        let material = Policy.reviewBodyInput(plan: plan(adopt: [makeFinding()]), voice: [])

        #expect(!material.text.contains("APPROVE"))
        #expect(!material.text.contains("REQUEST_CHANGES"))
        #expect(!material.text.lowercased().contains("verdikt"))
    }

    // MARK: - Převzaté nálezy

    @Test("Převzatý nález nese reviewera, text, kategorii i místo")
    func describesAdoptedFindings() {
        let material = Policy.reviewBodyInput(
            plan: plan(adopt: [
                makeFinding(
                    file: "Cart.php",
                    line: 26,
                    category: "security",
                    summary: "Token se loguje v plain textu",
                    reviewer: "security-review"
                )
            ]),
            voice: []
        )

        #expect(material.text.contains("Převzaté nálezy (1)"))
        #expect(material.text.contains("security-review: Token se loguje v plain textu"))
        #expect(material.text.contains("kategorie security"))
        #expect(material.text.contains("soubor Cart.php:26"))
        // `blokuje` **slovem, ne číslem**: poučení z #516, kde `blokuje 2` vydalo v briefu větu
        // o dvou reviewerech. Nejednoznačný vstup si model domyslí, a domyslí si ho špatně.
        #expect(material.text.contains("blokuje"))
    }

    /// Nález bez souboru (`chybí testy`) je legitimní — a věta o něm nesmí předstírat místo.
    @Test("Nález bez souboru žádné místo nepředstírá")
    func handlesFindingsWithoutAFile() {
        let material = Policy.reviewBodyInput(
            plan: plan(adopt: [makeFinding(category: nil, summary: "Chybí testy")]),
            voice: []
        )

        #expect(material.text.contains("code-review: Chybí testy"))
        #expect(!material.text.contains("soubor"))
    }

    // MARK: - Sporné nálezy

    /// **Sporné jdou do zadání, i když z nich v draftu není ani komentář** — je to ta věta, na
    /// které celá skupina #520–#521 stojí. Tělo review je první místo, kde se sporný nález dá
    /// zamluvit, takže o něm session vědět **musí**.
    @Test("Sporné nálezy jsou v zadání i s důvodem")
    func carriesContestedFindings() {
        let material = Policy.reviewBodyInput(
            plan: plan(contested: [
                Policy.key(of: makeFinding(file: "a.php", line: 1)): .plausible,
                Policy.key(of: makeFinding(file: "b.php", line: 2)): .noVerdict,
            ]),
            voice: []
        )

        #expect(material.text.contains("Sporné nálezy (2)"))
        #expect(material.text.contains("PLAUSIBLE"))
        #expect(material.text.contains("bez verdiktu"))
    }

    /// **Pořadí je naše, ne slovníkovo.** Nesetříděný výpis by se mezi dvěma běhy nad týmiž nálezy
    /// přeskládal, takže by se zadání měnilo bez důvodu a nedalo by se testovat výčtem.
    @Test("Sporné se vypisují setříděně")
    func sortsContestedReasons() {
        let doubts: [FindingKey: AutoDraftDoubt] = [
            Policy.key(of: makeFinding(file: "a.php", line: 1)): .plausible,
            Policy.key(of: makeFinding(file: "b.php", line: 2)): .noVerdict,
            Policy.key(of: makeFinding(file: "c.php", line: 3)): .disagreement(reviewers: ["a", "b"]),
        ]

        let first = Policy.reviewBodyInput(plan: plan(contested: doubts), voice: []).text
        let second = Policy.reviewBodyInput(plan: plan(contested: doubts), voice: []).text

        #expect(first == second)
        let reasons = first.components(separatedBy: "nález s důvodem ").dropFirst().map {
            String($0.prefix(while: { !$0.isNewline }))
        }
        #expect(reasons == reasons.sorted())
    }

    /// **„Sporné nejsou žádné“ se říká výslovně.** Prázdný oddíl by model přečetl jako místo, do
    /// kterého si něco může domyslet — a věta o sporných nálezech nad review, ve kterém žádné
    /// nejsou, je zrovna ten „text, který tvrdí víc, než data unesou“.
    @Test("Bez sporných to zadání říká rovnou")
    func saysWhenThereAreNoContested() {
        let material = Policy.reviewBodyInput(plan: plan(adopt: [makeFinding()]), voice: [])

        #expect(material.text.contains("Sporné nálezy (0)"))
        #expect(material.text.contains("o sporných nepiš vůbec"))
    }

    // MARK: - Hlas

    @Test("Ukázky hlasu jdou do zadání celé a od nejnovější")
    func carriesTheVoice() {
        let material = Policy.reviewBodyInput(
            plan: plan(adopt: [makeFinding()]),
            voice: [sample("r2", "Novější tělo review."), sample("r1", "Starší tělo review.")]
        )

        #expect(material.samples == 2)
        #expect(material.text.contains("Ukázky mých starších těl review (2)"))
        let newer = try! #require(material.text.range(of: "Novější tělo review."))
        let older = try! #require(material.text.range(of: "Starší tělo review."))
        #expect(newer.lowerBound < older.lowerBound)
    }

    /// **Nový uživatel: neutrálně, a zadání to řekne.** Bez téhle větve by session dostala oddíl
    /// bez ukázek a napodobovala by hlas, který nikde nemá — tedy vymyslela by si ho.
    @Test("Bez ukázek se v zadání stojí, že se píše neutrálně")
    func fallsBackToNeutral() {
        let material = Policy.reviewBodyInput(plan: plan(adopt: [makeFinding()]), voice: [])

        #expect(material.samples == 0)
        #expect(material.text.contains("žádné. Piš neutrálně"))
    }

    // MARK: - Sběr vzorků

    /// Filtr stojí na třech věcech a tohle je ta první: **cizí prózou se hlas napodobit nedá.**
    @Test("Do vzorků jde jen moje odeslané review s textem")
    func collectsOnlyMySubmittedReviews() {
        let mine = String(repeating: "á", count: 60)
        let conversation = Conversation(
            viewer: "octocat",
            reviews: ConversationPage(
                items: [
                    SubmittedReview(id: "1", author: "octocat", state: .commented, body: mine, submittedAt: Date(timeIntervalSince1970: 10)),
                    // Cizí — vypadne.
                    SubmittedReview(id: "2", author: "hubot", state: .approved, body: mine, submittedAt: Date(timeIntervalSince1970: 20)),
                    // Moje, ale rozdělané (`pending`) — ještě se může celé změnit.
                    SubmittedReview(id: "3", author: "octocat", state: .pending, body: mine, submittedAt: nil),
                    // Moje, ale krátké: `LGTM` se jako vzor nad třemi nálezy odeslat nedá.
                    SubmittedReview(id: "4", author: "octocat", state: .approved, body: "LGTM", submittedAt: Date(timeIntervalSince1970: 30)),
                ],
                total: 4,
                hasNextPage: false
            ),
            threads: ConversationPage(items: [], total: 0, hasNextPage: false),
            comments: ConversationPage(items: [], total: 0, hasNextPage: false)
        )

        #expect(Policy.reviewVoiceSamples(in: conversation).map(\.id) == ["1"])
    }

    /// **Deduplikuje se podle `id`, ne podle textu**, a novější zápis přebíjí starší: tělo review
    /// se dá na GitHubu editovat, takže vzorek z doby před opravou je text, který už nikde nestojí.
    @Test("Slití drží nejnovějších deset a přepisuje podle id")
    func mergesAndCaps() {
        let stored = (1...10).map { sample("r\($0)", "tělo \($0)", at: Double($0)) }
        let merged = Policy.mergedReviewVoice(
            stored,
            adding: [sample("r1", "opravené tělo", at: 1), sample("r11", "nové tělo", at: 11)]
        )

        #expect(merged.count == Policy.reviewVoiceLimit)
        #expect(merged.first?.id == "r11")
        // `r1` je nejstarší, takže vypadl — a `r2` je teď ten nejstarší, který zůstal.
        #expect(merged.last?.id == "r2")
        #expect(!merged.contains { $0.body == "opravené tělo" })
    }

    /// Dvě review odeslaná v tomtéž okamžiku (dávka) musí vyjít pokaždé stejně — jinak by se
    /// desítka po každém načtení přeskládala a zadání by se měnilo bez důvodu.
    @Test("Shodný okamžik rozhodne id, takže je pořadí stabilní")
    func ordersStablyOnTies() {
        let samples = [sample("a", "první", at: 5), sample("b", "druhý", at: 5)]

        #expect(Policy.mergedReviewVoice([], adding: samples).map(\.id) == ["b", "a"])
        #expect(Policy.mergedReviewVoice(samples.reversed(), adding: []).map(\.id) == ["b", "a"])
    }
}
