import Foundation
import Testing

@testable import PRism

/// Jedno odeslání od kliknutí po odpověď GitHubu. Proti `FakeReviewPublisher`, takže se
/// **nic neodesílá** — a právě to je tady to hlavní: testy tvrdí i to, kdy se nezavolá nic.
@Suite("ReviewSubmission")
@MainActor
struct ReviewSubmissionTests {
    private let pr = PRIdentifier("ondrajodas/prism-review-sandbox#7")!

    private func summary() -> PullRequestSummary {
        PullRequestSummary(
            id: pr,
            title: "titulek",
            author: "autor",
            url: URL(string: "https://github.com/ondrajodas/prism-review-sandbox/pull/7")!,
            updatedAt: Date(timeIntervalSince1970: 100),
            state: .open
        )
    }

    private func draft(verdict: ReviewDraft.Verdict? = .approve) -> ReviewDraft {
        ReviewDraft(
            pullRequest: pr,
            headSha: "aaaa1111",
            body: "vypadá to dobře",
            verdict: verdict,
            comments: [
                ReviewDraftComment(path: "Cart.php", anchor: DraftAnchor(line: 26, side: .right), body: "tady", origin: .own),
            ]
        )
    }

    private func review() -> SubmittedReview {
        SubmittedReview(
            id: "1",
            author: "ondrajodas",
            state: .approved,
            body: "vypadá to dobře",
            submittedAt: Date(timeIntervalSince1970: 200)
        )
    }

    /// Závora, kterou test drží odeslání rozběhnuté. Čeká se **odmlkami, ne `Task.yield()`**.
    ///
    /// Točení přes `yield()` je jinde v testech tohohle repa běžné, ale tady by běželo
    /// **na `MainActoru`** (`ReviewSubmission` je `@MainActor`) a **bez horní hranice** —
    /// dokud závoru někdo nepustí. Swift Testing pouští suity paralelně, takže takový hot
    /// spin ubírá čas všem ostatním: `SubprocessStreamerTests` na něm začaly padat, protože
    /// zrušený proces se nestihl zabít dřív, než mu doběhl `sleep 1`. Millisekundová odmlka
    /// vlákno pustí a vlastnost, kvůli které se `yield()` používá, zůstává — test, který se
    /// nedočká, uvízne, což je srozumitelnější než náhodné padání.
    private final class AsyncGate: @unchecked Sendable {
        private let lock = NSLock()
        private var isOpen = false

        func open() { lock.withLock { isOpen = true } }

        func wait() async {
            while !lock.withLock({ isOpen }) { try? await Task.sleep(for: .milliseconds(1)) }
        }
    }

    /// Kolikrát se zavolal úklid po úspěchu. Ne boolean: dvojí smazání draftu by se
    /// v aplikaci neprojevilo (je idempotentní), ale znamenalo by dvě odeslání.
    private final class Cleanups: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        var value: Int { lock.withLock { count } }
        func record() { lock.withLock { count += 1 } }
    }

    private func submission(
        _ publisher: FakeReviewPublisher,
        draft: ReviewDraft? = nil,
        suggestion: ReviewVerdict? = nil,
        cleanups: Cleanups = Cleanups(),
        anchors: [DraftAnchorCheck] = [],
        needsTransfer: Bool = false,
        transferred: ReviewDraft? = nil
    ) -> ReviewSubmission {
        ReviewSubmission(
            pullRequest: summary(),
            draft: draft ?? self.draft(),
            suggestion: suggestion,
            anchors: anchors,
            needsTransfer: needsTransfer,
            publisher: { publisher },
            afterSuccess: { cleanups.record() },
            applyTransfer: { _ in transferred }
        )
    }

    // MARK: - Kontrola proti novému commitu (#69)

    /// **To hlavní:** dokud se draft nepřenesl, nesmí se dát odeslat. Pre-flight publisheru by ho
    /// odmítl (jiná hlava), ale na tu chybu se nemá jít naběhnout z okna.
    @Test("V kontrole se odeslat nedá")
    func refusesToSendWhileChecking() async {
        let publisher = FakeReviewPublisher(always: .success(review()))
        let submission = submission(publisher, needsTransfer: true)

        #expect(submission.state == .checking)
        #expect(!submission.canSend)
        await submission.send()

        #expect(publisher.submitted.isEmpty, "nic se nesmí odeslat")
        #expect(submission.state == .checking)
    }

    /// Zastaralý draft **bez řádkových komentářů** je zastaralý taky — kontrola se z prázdných
    /// kotev odvodit nedá, takže o ní rozhoduje vlastní příznak.
    @Test("Prázdné kotvy z kontroly nedělají hotový stav")
    func staysCheckingWithoutAnchors() {
        let submission = submission(FakeReviewPublisher(always: .success(review())), needsTransfer: true)

        #expect(submission.anchors.isEmpty)
        #expect(submission.state == .checking)
    }

    /// Po přenesení se ukáže **nový** snímek: co je v potvrzení vidět, to se odešle.
    @Test("Přenesení nahradí snímek a odemkne odeslání")
    func transfersAndUnlocksSending() async {
        let publisher = FakeReviewPublisher(always: .success(review()))
        let new = ReviewDraft(
            pullRequest: pr,
            headSha: "bbbb2222",
            body: "vypadá to dobře",
            verdict: .approve,
            comments: []
        )
        let submission = submission(publisher, needsTransfer: true, transferred: new)

        submission.transfer(choices: [:])

        #expect(submission.state == .ready)
        #expect(submission.draft == new)
        #expect(submission.anchors.isEmpty)

        await submission.send()
        #expect(publisher.submitted == [new], "odešle se přenesený draft, ne ten původní")
    }

    /// Když přenesení nevyjde (draft nebo diff zmizely pod rukama), okno **zůstane v kontrole** —
    /// tvářit se jako hotové by znamenalo odeslat proti starému commitu.
    @Test("Nepovedené přenesení nechá okno v kontrole")
    func staysCheckingWhenTheTransferFails() {
        let submission = submission(
            FakeReviewPublisher(always: .success(review())),
            needsTransfer: true,
            transferred: nil
        )

        submission.transfer(choices: [:])

        #expect(submission.state == .checking)
        #expect(!submission.canSend)
    }

    /// Přenést se dá jen z kontroly: druhé zavolání by přepsalo snímek, který už člověk potvrdil.
    @Test("Přenesení mimo kontrolu nic nedělá")
    func ignoresATransferOutsideChecking() {
        let original = draft()
        let submission = submission(
            FakeReviewPublisher(always: .success(review())),
            draft: original,
            transferred: ReviewDraft(pullRequest: pr, headSha: "cccc3333", verdict: .approve)
        )

        submission.transfer(choices: [:])

        #expect(submission.state == .ready)
        #expect(submission.draft == original)
    }

    /// Draft se drží v proměnné, ne se vyrábí dvakrát: `ReviewDraftComment` si generuje
    /// `UUID`, takže dvě volání továrničky nikdy nedají shodné hodnoty.
    @Test("Odeslání pošle přesně to, co je v snímku draftu")
    func sendsTheSnapshot() async {
        let publisher = FakeReviewPublisher(always: .success(review()))
        let cleanups = Cleanups()
        let draft = draft()
        let submission = submission(publisher, draft: draft, cleanups: cleanups)

        await submission.send()

        #expect(publisher.submitted == [draft])
        #expect(submission.state == .sent(review()))
        #expect(cleanups.value == 1)
    }

    /// Draft se maže **až po potvrzené odpovědi**. Selhání ho nechává netknutý, aby se dalo
    /// zkusit znovu bez psaní nanovo — a úklid, který by se pustil i po chybě, by rozdělané
    /// review zahodil kvůli výpadku sítě.
    @Test("Selhání nespustí úklid a nechá se zkusit znovu")
    func keepsTheDraftAfterAFailure() async {
        let publisher = FakeReviewPublisher([
            .failure(PublishError.pendingReviewExists),
            .success(review()),
        ])
        let cleanups = Cleanups()
        let submission = submission(publisher, cleanups: cleanups)

        await submission.send()

        #expect(submission.state == .failed(.pendingReviewExists))
        #expect(cleanups.value == 0)
        #expect(submission.canSend)

        await submission.send()

        #expect(submission.state == .sent(review()))
        #expect(cleanups.value == 1)
    }

    /// Sheet se po odeslání zavírá sám — že review odešlo, je za ním vidět líp (draft je
    /// pryč, v `Přehledu` přibylo moje review). **Výjimka je odpověď, jejímuž stavu
    /// nerozumíme:** tam je jediná zpráva ta, že se to má zkontrolovat na GitHubu, a jinde
    /// v okně se člověk k ní nedostane, protože review tam vypadá jako každé jiné.
    @Test("Sheet se zavírá sám, ale ne u odpovědi, které nerozumíme")
    func closesItselfOnlyWhenThereIsNothingToAdd() async {
        let understood = submission(FakeReviewPublisher(always: .success(review())))
        #expect(!understood.closesItself, "před odesláním není co zavírat")

        await understood.send()
        #expect(understood.closesItself)

        let unknown = SubmittedReview(
            id: "2",
            author: "ondrajodas",
            state: nil,
            body: "",
            submittedAt: nil
        )
        let puzzling = submission(FakeReviewPublisher(always: .success(unknown)))

        await puzzling.send()

        #expect(puzzling.state == .sent(unknown))
        #expect(!puzzling.closesItself)
    }

    /// Selhání sheet nezavírá — chyba i věta o tom, že draft zůstal, se čtou právě tam.
    @Test("Selhání sheet nechá otevřený")
    func staysOpenAfterAFailure() async {
        let submission = submission(FakeReviewPublisher(always: .failure(PublishError.timedOut)))

        await submission.send()

        #expect(!submission.closesItself)
    }

    /// Po úspěchu je hotovo. Druhé odeslání by nebylo opravou toho prvního, ale **druhým
    /// review** — a to už na PR leží jako samostatný záznam.
    @Test("Po úspěchu se znovu odeslat nedá")
    func refusesToSendTwice() async {
        let publisher = FakeReviewPublisher(always: .success(review()))
        let submission = submission(publisher)

        await submission.send()
        await submission.send()

        #expect(publisher.submitted.count == 1)
        #expect(!submission.canSend)
    }

    /// **Zrušení není „nic se nestalo“.** Zrušit jde jedině *během* volání, takže POST mohl
    /// doběhnout — vrátit stav na začátek a nechat aktivní tlačítko by byla pozvánka poslat
    /// approve podruhé. Dnes to nikdo nevyvolá (task odeslání se neruší), ale tvar se drží,
    /// aby se to nedalo spolknout, až rušit půjde.
    @Test("Zrušení se nevydává za to, že se nic nestalo")
    func treatsCancellationAsAnUnknownOutcome() async {
        let publisher = FakeReviewPublisher(always: .failure(CancellationError()))
        let cleanups = Cleanups()
        let submission = submission(publisher, cleanups: cleanups)

        await submission.send()

        #expect(submission.state == .failed(.interrupted))
        #expect(!submission.canSend)
        #expect(cleanups.value == 0)
    }

    /// **To hlavní na téhle třídě chyb:** po selhání, po kterém review na PR **může ležet**,
    /// se nesmí nabízet odeslání znovu. `malformedResponse` vzniká při **nulovém** exit kódu,
    /// tedy poté, co POST prošel; `timedOut` znamená, že jsme `gh` zabili sami po třiceti
    /// vteřinách. Druhý pokus by z toho udělal dvě review a po něm by se draft smazal.
    @Test("Po chybě, u které review mohlo dojít, se znovu odeslat nedá")
    func refusesToRetryWhenTheReviewMayExist() async {
        for error in [PublishError.malformedResponse("nesmysl"), .timedOut, .unknown("kdo ví")] {
            let publisher = FakeReviewPublisher(always: .failure(error))
            let submission = submission(publisher)

            await submission.send()

            #expect(submission.state == .failed(error))
            #expect(!submission.canSend, "\(error) nabídlo odeslat znovu")
        }
    }

    /// Naopak u chyby, kterou GitHub **odmítl** (nebo se k němu vůbec nedostala), je jisté, že
    /// review nevzniklo — tam by zakázané tlačítko nutilo psát review znovu bez důvodu.
    @Test("Po odmítnutí se odeslat znovu dá")
    func allowsRetryAfterARejection() async {
        for error in [PublishError.lineOutsideDiff("422"), .notAuthenticated, .pendingReviewExists] {
            let publisher = FakeReviewPublisher(always: .failure(error))
            let submission = submission(publisher)

            await submission.send()

            #expect(submission.canSend, "\(error) nešlo zkusit znovu")
        }
    }

    /// Dvojklik nesmí poslat dvě review — a drží to **jen** na tom, že se `.sending` nastaví
    /// dřív než první `await` v `send()`.
    ///
    /// Obě volání se proto pouští **naráz**, ne s čekáním na to, až první poběží: `Task`
    /// z tlačítka se spouští asynchronně, takže se dvě kliknutí stihnou zařadit dřív, než se
    /// první rozběhne, a zachrání to až serializace na `MainActoru`. Test, který na první
    /// odeslání počká, tenhle závod zavře a přesunutí toho jednoho řádku by mu prošlo —
    /// ověřeno tím, že s takovým testem zelená zůstala.
    @Test("Dvojklik pošle jedno review, ne dvě")
    func refusesASecondSendFromADoubleClick() async {
        let publisher = FakeReviewPublisher(always: .success(review()))
        let submission = submission(publisher)

        async let first: Void = submission.send()
        async let second: Void = submission.send()
        _ = await (first, second)

        #expect(publisher.submitted.count == 1)
    }

    /// Za běhu je tlačítko zakázané — na tom stojí, že se dvojklik nemá o co opřít ani
    /// tehdy, když druhé kliknutí přijde až po chvíli.
    @Test("Během odesílání se odeslat znovu nedá")
    func refusesToSendWhileSending() async {
        let publisher = FakeReviewPublisher(always: .success(review()))
        let submission = submission(publisher)
        let release = AsyncGate()
        publisher.hold { await release.wait() }

        async let first: Void = submission.send()
        while publisher.submitted.isEmpty { try? await Task.sleep(for: .milliseconds(1)) }

        #expect(submission.state == .sending)
        #expect(!submission.canSend)
        await submission.send()
        #expect(publisher.submitted.count == 1)

        release.open()
        await first
    }

    /// Chyba, která není `PublishError`, se nesmí ztratit — z okna má být poznat, že se to
    /// nepovedlo, i když netušíme proč.
    @Test("Cizí chyba skončí jako neznámé selhání")
    func wrapsAnUnknownError() async {
        struct Boom: Error {}
        let publisher = FakeReviewPublisher(always: .failure(Boom()))
        let submission = submission(publisher)

        await submission.send()

        guard case .failed(.unknown) = submission.state else {
            Issue.record("Čekal jsem neznámé selhání, přišlo \(submission.state)")
            return
        }
    }

    /// Návrh z nálezů verdikt **nepředvyplňuje**, ale rozchod s ním se v potvrzení hlásí:
    /// schválit PR, u kterého reviewer hlásí blokující nález, je nejdražší záměna, jakou
    /// tohle okno umí.
    @Test("Rozchod s návrhem z nálezů se pozná")
    func spotsAContradictionWithTheSuggestion() {
        let publisher = FakeReviewPublisher(always: .success(review()))

        #expect(submission(publisher, draft: draft(verdict: .approve), suggestion: .requestChanges)
            .contradictsSuggestion)
        #expect(submission(publisher, draft: draft(verdict: .requestChanges), suggestion: .approve)
            .contradictsSuggestion)
        #expect(!submission(publisher, draft: draft(verdict: .approve), suggestion: .approve)
            .contradictsSuggestion)
        // Bez návrhu není s čím se rozcházet, a `jen komentář` neodporuje ničemu — je to
        // vědomé „nerozhoduju“, ne opak schválení.
        #expect(!submission(publisher, draft: draft(verdict: .approve), suggestion: nil)
            .contradictsSuggestion)
        #expect(!submission(publisher, draft: draft(verdict: .comment), suggestion: .requestChanges)
            .contradictsSuggestion)
    }
}
