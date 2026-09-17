import Foundation
import Testing

@testable import PRism

/// Karta `Odpověď na tvoje review` (#523) — kresba nad reportem z #522.
///
/// Čtyři věci se tady rozbijí potichu a každá má vlastní test:
///
/// - **návrh verdiktu** — `Schválit` přes nezodpovězený bod je nejdražší chyba, kterou karta umí;
/// - **předepsané tělo** — věta, která tvrdí víc, než kolik se doopravdy opravilo;
/// - **tři podoby `bez odpovědi`** — `nejde říct` se nesmí slít s `beze změny` ani s mlčením
///   kontroly (#522);
/// - **kdy se karta nekreslí vůbec** — na vlastním PR a nad nenačtenou konverzací.
@Suite("Policy — karta druhého kola")
struct ReviewReplyCardTests {
    // MARK: - Stavba dat

    private func comment(_ id: String, line: Int? = 81, path: String = "src/Cart.swift") -> SentComment {
        SentComment(threadID: id, path: path, line: line, body: "prázdný fallback")
    }

    private func entry(
        _ id: String,
        _ state: Policy.ReviewReplyState,
        line: Int? = 81,
        reply: ThreadComment? = nil
    ) -> Policy.ReviewReplyEntry {
        Policy.ReviewReplyEntry(comment: comment(id, line: line), state: state, reply: reply)
    }

    private func reply(_ author: String, _ body: String) -> ThreadComment {
        ThreadComment(
            id: "r",
            author: author,
            body: body,
            createdAt: Date(timeIntervalSince1970: 1_000_000),
            url: URL(string: "https://github.com/cli/cli/pull/42#discussion_r1")!
        )
    }

    private func tally(
        _ entries: [Policy.ReviewReplyEntry],
        missingThreads: Int = 0,
        isTruncated: Bool = false,
        verdicts: Policy.ReviewReplyVerdicts? = Policy.ReviewReplyVerdicts(
            againstHeadSha: "9c1de0212ab",
            outcome: .finished,
            finishedAt: Date(timeIntervalSince1970: 2_000_000)
        )
    ) -> Policy.ReviewReplyTally {
        Policy.ReviewReplyTally(
            entries: entries,
            fixed: entries.count { if case .fixed = $0.state { return true } else { return false } },
            answered: entries.count { $0.state == .answered },
            unanswered: entries.count {
                if case .unanswered = $0.state { return true } else { return false }
            },
            missingThreads: missingThreads,
            isTruncated: isTruncated,
            verdicts: verdicts
        )
    }

    // MARK: - Návrh verdiktu — vyčerpávající výčet

    /// Zadání #523 chce výčet `vše / část / nic opraveno × odpovězeno`. Devět kombinací nad třemi
    /// vlákny, u každé vypsaný návrh — tabulka je tady kvůli tomu, aby při změně pravidla bylo
    /// vidět, které buňky se hnuly.
    ///
    /// **Jediné, co o návrhu rozhoduje, je `bez odpovědi`.** Poměr `opraveno` ku `odpovězeno` do
    /// něj nemluví: obojí je vyřízený bod.
    @Test(
        "Návrh verdiktu: schvaluje se jedině tehdy, když nic nezbývá",
        arguments: [
            // opraveno, odpovězeno, bez odpovědi → návrh
            (3, 0, 0, Policy.ReviewReplyProposal.approve),
            (0, 3, 0, .approve),
            (2, 1, 0, .approve),
            (2, 0, 1, .comment(.unanswered(1))),
            (0, 2, 1, .comment(.unanswered(1))),
            (1, 1, 1, .comment(.unanswered(1))),
            (0, 0, 3, .comment(.unanswered(3))),
            (1, 0, 2, .comment(.unanswered(2))),
            (0, 1, 2, .comment(.unanswered(2)))
        ]
    )
    func proposalAcrossTheGrid(
        fixed: Int,
        answered: Int,
        unanswered: Int,
        expected: Policy.ReviewReplyProposal
    ) {
        var entries: [Policy.ReviewReplyEntry] = []
        for index in 0..<fixed { entries.append(entry("f\(index)", .fixed(in: "9c1de02"))) }
        for index in 0..<answered {
            entries.append(entry("a\(index)", .answered, reply: reply("sykora-ji", "hotovo")))
        }
        for index in 0..<unanswered { entries.append(entry("u\(index)", .unanswered(.unchanged))) }
        #expect(Policy.replyProposal(tally(entries)) == expected)
    }

    /// **Useknutá stránka vláken schválení bere taky.** Nezodpovězený bod není, ale o části PR se
    /// neví nic — a `Schválit` by tvrdilo víc, než data unesou. Je to tentýž směr opatrnosti jako
    /// u zahozeného nálezu v `suggestedVerdict`.
    @Test("Useknutá stránka vláken bere schválení, i když nic nezbývá")
    func truncatedThreadsBlockApproval() {
        let entries = [entry("1", .fixed(in: "9c1de02"))]
        #expect(Policy.replyProposal(tally(entries, isTruncated: true))
            == .comment(.incompleteThreads))
        #expect(Policy.replyProposal(tally(entries, missingThreads: 4))
            == .comment(.incompleteThreads))
        // A **zbývající bod je konkrétnější než useknutá stránka**: dá se otevřít a vyřídit.
        #expect(Policy.replyProposal(tally(
            entries + [entry("2", .unanswered(.unclear))],
            isTruncated: true
        )) == .comment(.unanswered(1)))
    }

    // MARK: - Předepsané tělo

    /// Věta se skládá z **obou** čísel. `všech 5 opraveno` nad čtyřmi opravami a jednou odpovědí
    /// by bylo tvrzení navíc — přesně ta třída, které se celé #522 vyhýbá.
    @Test("Předepsané tělo netvrdí víc, než kolik se opravilo")
    func approvalBodyCountsBoth() {
        let fixedOnly = tally((0..<5).map { entry("f\($0)", .fixed(in: "9c1de02")) })
        #expect(Policy.replyApprovalBody(fixedOnly) == "Díky, všech 5 opraveno.")

        let one = tally([entry("f", .fixed(in: "9c1de02"))])
        #expect(Policy.replyApprovalBody(one) == "Díky, opraveno.")

        let answeredOnly = tally([
            entry("a", .answered, reply: reply("sykora-ji", "necháme na AJDA-570"))
        ])
        #expect(Policy.replyApprovalBody(answeredOnly) == "Díky za odpovědi.")

        let mixed = tally([
            entry("f1", .fixed(in: "9c1de02")),
            entry("f2", .fixed(in: "9c1de02")),
            entry("a", .answered, reply: reply("sykora-ji", "necháme na AJDA-570"))
        ])
        #expect(Policy.replyApprovalBody(mixed) == "Díky — 2 body opraveno, na zbytek jsi odpověděl.")
    }

    /// **Nejcennější tvrzení téhle sady: `Schválit i tak` nepředepisuje nic.** Poděkovat za bod,
    /// který zůstal bez odpovědi, znamená položit člověku do úst větu, která není pravda.
    @Test("Přes nezodpovězený bod se tělo nepředepisuje")
    func noBodyOverAnUnansweredPoint() {
        let remaining = tally([
            entry("f", .fixed(in: "9c1de02")),
            entry("u", .unanswered(.unchanged))
        ])
        #expect(Policy.replyApprovalBody(remaining) == nil)
        #expect(Policy.replyApproveLabel(Policy.replyProposal(remaining)) == "Schválit i tak")
    }

    /// Rozepsaná věta má přednost — jinak by klik na `Schválit` smazal text, který se nedá pustit
    /// znovu. Bílé místo se za rozepsanou větu nepovažuje.
    @Test("Předpis nepřepíše rozepsané tělo")
    func prescriptionKeepsWhatIsWritten() {
        #expect(Policy.prescribedBody(existing: "Moje věta", prescribed: "Díky, opraveno.")
            == "Moje věta")
        #expect(Policy.prescribedBody(existing: "", prescribed: "Díky, opraveno.")
            == "Díky, opraveno.")
        #expect(Policy.prescribedBody(existing: "  \n ", prescribed: "Díky, opraveno.")
            == "Díky, opraveno.")
        // Bez předpisu se nemaže ani prázdno: `nil` znamená „nic nepředepisuju“.
        #expect(Policy.prescribedBody(existing: "Moje věta", prescribed: nil) == "Moje věta")
    }

    // MARK: - Řádky

    /// **Tři podoby `bez odpovědi`, ne jedna** (#522) — a ani jedna neznamená „ignoroval mě“.
    @Test("Tři pochybnosti se v kresbě neslijí")
    func threeDoubtsStayApart() {
        let notes = [
            Policy.replyNote(of: entry("1", .unanswered(.unchanged))),
            Policy.replyNote(of: entry("2", .unanswered(.unclear))),
            Policy.replyNote(of: entry("3", .unanswered(.unknown)))
        ]
        #expect(Set(notes).count == 3)
        #expect(notes[0] == "bez odpovědi · řádek beze změny")
        #expect(notes[1] == "bez odpovědi · z kódu to nejde říct")
        #expect(notes[2] == "bez odpovědi · kontrola se k tomu nevyjádřila")
    }

    /// `opraveno v <sha>` nese **sedm znaků hlavy**, ne celou — a odpověď nese autora i větu,
    /// protože právě kvůli ní se do vlákna jde zpátky.
    @Test("Opravený a zodpovězený řádek řeknou čím")
    func fixedAndAnsweredNotes() {
        #expect(Policy.replyNote(of: entry("1", .fixed(in: "9c1de0212ab")))
            == "opraveno v 9c1de02")
        #expect(Policy.replyNote(of: entry(
            "2",
            .answered,
            reply: reply("sykora-ji", "necháme na AJDA-570")
        )) == "odpověděl sykora-ji: „necháme na AJDA-570“")
        // Prázdné tělo (odpověď jen s obrázkem) nechá **samotného autora**: visící dvojtečka
        // vypadá jako uříznutý text.
        #expect(Policy.replyNote(of: entry("3", .answered, reply: reply("sykora-ji", "  ")))
            == "odpověděl sykora-ji")
    }

    /// Vlákno bez kotvy (zastaralé) se pozná podle **jména souboru** — prázdné místo by z řádku
    /// udělalo větu bez podmětu.
    @Test("Bez čísla řádku zbývá jméno souboru")
    func placeFallsBackToTheFileName() {
        #expect(Policy.replyPlace(of: comment("1", line: 60)) == "ř. 60")
        #expect(Policy.replyPlace(of: comment("2", line: nil)) == "Cart.swift")
        // Číslo řádku je **adresa, ne množství**: oddělovač tisíců by z něj udělal dvě čísla.
        #expect(Policy.replyPlace(of: comment("3", line: 1234)) == "ř. 1234")
    }

    // MARK: - Celá karta

    /// **Na vlastním PR se karta nekreslí vůbec** — schválení vlastního PR GitHub odmítne, takže
    /// by spodní půlka karty nabízela něco, co nejde.
    @Test("Na vlastním PR karta není")
    func noCardOnMyOwnPullRequest() {
        let report = Policy.ReviewReplyReport.current(tally([entry("1", .fixed(in: "9c1de02"))]))
        #expect(Policy.replyCard(report, ownership: .mine, reviewedAt: nil) == nil)
        #expect(Policy.replyCard(report, ownership: .theirs, reviewedAt: nil) != nil)
    }

    /// Nenačtená konverzace a „žádné vlákno tam nemám“ jsou dvě různé věty a **ani jedna kartu
    /// nevydá**: prázdná karta by tvrdila to druhé i tam, kde platí to první.
    @Test("Bez dat karta není")
    func noCardWithoutData() {
        #expect(Policy.replyCard(.unknown, ownership: .theirs, reviewedAt: nil) == nil)
        #expect(Policy.replyCard(.current(tally([])), ownership: .theirs, reviewedAt: nil) == nil)
    }

    /// Pořadí je z návrhu (Z3): hotové věci nahoře, dole to, na co se musí kliknout. A **sbalí se
    /// jedině opravené** — `odpovězeno` nese větu kolegy a `bez odpovědi` je důvod, proč se na
    /// kartu kouká.
    @Test("Řádky se řadí a sčítá se jedině přebytek opravených")
    func rowsAreOrderedAndOnlyFixedIsFolded() {
        let entries = (0..<7).map { entry("f\($0)", .fixed(in: "9c1de02")) }
            + [entry("a", .answered, reply: reply("sykora-ji", "necháme na AJDA-570"))]
            + [entry("u", .unanswered(.unchanged))]
        let card = try! #require(Policy.replyCard(
            .current(tally(entries)),
            ownership: .theirs,
            reviewedAt: nil
        ))
        #expect(card.foldedFixed == 2)
        #expect(card.rows.count == 7)
        #expect(card.rows.map(\.mark) == [.fixed, .fixed, .fixed, .fixed, .fixed, .answered, .unanswered])
        // `Otevřít zbývající` míří na vlákno bez odpovědi, i když leželo v datech poslední.
        #expect(card.openRemaining?.threadID == "u")
        #expect(card.openRemaining?.label == "Otevřít zbývající (ř. 81)")
    }

    /// Titulek nese datum **mého posledního odeslaného review**; bez něj zůstane holý, protože
    /// `z —` vypadá jako chyba.
    @Test("Titulek bez data nevymýšlí datum")
    func titleWithoutADate() {
        #expect(Policy.replyCardTitle(reviewedAt: nil) == "Odpověď na tvoje review")
        #expect(Policy.replyCardTitle(reviewedAt: Date(timeIntervalSince1970: 1_000_000))
            .hasPrefix("Odpověď na tvoje review z "))
    }

    /// Jen **odeslané** review datuje kartu: `submittedAt == nil` je rozepsané review, které
    /// kolega nikdy neviděl.
    @Test("Datum bere nejnovější odeslané moje review")
    func reviewDateIgnoresPendingAndForeign() {
        let mine = SubmittedReview(
            id: "1",
            author: "ondrajodas",
            state: .commented,
            body: "",
            submittedAt: Date(timeIntervalSince1970: 1_000)
        )
        let newerPending = SubmittedReview(
            id: "2",
            author: "ondrajodas",
            state: .pending,
            body: "",
            submittedAt: nil
        )
        let foreign = SubmittedReview(
            id: "3",
            author: "sykora-ji",
            state: .approved,
            body: "",
            submittedAt: Date(timeIntervalSince1970: 9_000)
        )
        let conversation = Conversation(
            viewer: "ondrajodas",
            reviews: ConversationPage(items: [mine, newerPending, foreign], total: 3, hasNextPage: false),
            threads: ConversationPage(items: [], total: 0, hasNextPage: false),
            comments: ConversationPage(items: [], total: 0, hasNextPage: false)
        )
        #expect(Policy.lastOwnReviewDate(in: conversation) == Date(timeIntervalSince1970: 1_000))
        #expect(Policy.lastOwnReviewDate(in: nil) == nil)
    }

    // MARK: - Co karta neví

    /// **Chybějící data se přiznají.** Useknutá stránka vláken, chybějící kontrola a kontrola,
    /// která nedoběhla, jsou tři různé věty — a karta o nich musí mluvit, ne mlčet.
    @Test("Karta přizná, o čem neví")
    func caveatsAreSpelledOut() {
        let entries = [entry("1", .fixed(in: "9c1de02"))]
        #expect(Policy.replyCaveats(tally(entries)).isEmpty)
        #expect(Policy.replyCaveats(tally(entries, missingThreads: 4))
            == [.incompleteThreads(missing: 4)])
        #expect(Policy.replyCaveats(tally(entries, isTruncated: true))
            == [.incompleteThreads(missing: 0)])
        #expect(Policy.replyCaveats(tally(entries, verdicts: nil)) == [.noCheck])
        #expect(Policy.replyCaveats(tally(entries, verdicts: Policy.ReviewReplyVerdicts(
            againstHeadSha: "9c1de02",
            outcome: .timedOut,
            finishedAt: Date(timeIntervalSince1970: 2_000_000)
        ))) == [.checkDidNotFinish])
        // Věty se nesmí slít: každá pojmenovává jinou mezeru.
        let sentences = [
            Policy.ReviewReplyCaveat.incompleteThreads(missing: 4),
            .incompleteThreads(missing: 0),
            .noCheck,
            .checkDidNotFinish
        ].map(Policy.replyCaveatSentence)
        #expect(Set(sentences).count == 4)
    }

    /// Pruh nad tlačítky **vypisuje, proč se neschvaluje** — bez toho by `Komentář` vypadal jako
    /// náhodná volba.
    @Test("Pruh s návrhem řekne i proč")
    func proposalLabelSaysWhy() {
        #expect(Policy.replyProposalLabel(.approve) == "návrh: Schválit")
        #expect(Policy.replyProposalLabel(.comment(.unanswered(1)))
            == "návrh: Komentář · 1 bez odpovědi")
        #expect(Policy.replyProposalLabel(.comment(.incompleteThreads))
            == "návrh: Komentář · o všech vláknech nevíme")
    }
}
