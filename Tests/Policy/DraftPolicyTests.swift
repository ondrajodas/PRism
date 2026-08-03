import Foundation
import Testing

@testable import PRism

/// Komentovatelnost řádku a zastarání draftu — čisté funkce, nic se nemockuje.
@Suite("Policy — draft")
struct DraftPolicyTests {
    private let pr = PRIdentifier("cli/cli#42")!

    /// Diff s jedním souborem a hunkem na nových řádcích 25–27: 25 kontext, 26 přidaný
    /// (starý 26 odebraný), 27 kontext. Před hunkem i za ním jsou řádky, které v diffu
    /// **nejsou**.
    private func diff() throws -> Diff {
        DiffParser.parse("""
            diff --git a/Cart.php b/Cart.php
            --- a/Cart.php
            +++ b/Cart.php
            @@ -25,3 +25,3 @@
             kontext
            -staré
            +nové
             další
            """)
    }

    private func file() throws -> FileDiff {
        try #require(try diff().files.first)
    }

    private func line(_ kind: DiffLine.Kind, old: Int?, new: Int?, text: String) -> DiffLine {
        DiffLine(kind: kind, oldNumber: old, newNumber: new, text: text)
    }

    // MARK: - Komentovatelnost

    @Test("Přidaný řádek se komentuje na pravé straně")
    func commentsAnAddedLineOnTheRight() throws {
        let file = try file()
        let added = try #require(file.hunks.first?.lines.first { $0.kind == .added })

        #expect(Policy.commentableSide(of: added, in: file) == .right)
    }

    /// Ověřeno na živém API u #62: komentář na kontextovém řádku hunku projde.
    @Test("Kontextový řádek hunku se komentuje na pravé straně")
    func commentsAContextLineOnTheRight() throws {
        let file = try file()
        let context = try #require(file.hunks.first?.lines.first { $0.kind == .context })

        #expect(Policy.commentableSide(of: context, in: file) == .right)
    }

    /// Odebraný řádek v novém souboru neexistuje a jeho číslo je ze starého — bez `left` by
    /// komentář odešel na jiný řádek.
    @Test("Odebraný řádek se komentuje na levé straně")
    func commentsARemovedLineOnTheLeft() throws {
        let file = try file()
        let removed = try #require(file.hunks.first?.lines.first { $0.kind == .removed })

        #expect(Policy.commentableSide(of: removed, in: file) == .left)
        #expect(removed.newNumber == nil)
    }

    /// `\ No newline at end of file` není obsah souboru.
    @Test("Meta řádek se komentovat nedá")
    func refusesAMetaLine() throws {
        let file = try file()
        let meta = line(.meta, old: nil, new: nil, text: "\\ No newline at end of file")

        #expect(Policy.commentableSide(of: meta, in: file) == nil)
        #expect(!Policy.isCommentable(meta, in: file))
    }

    /// GitHub takový komentář odmítne (`422 Line could not be resolved`) a **s ním celé
    /// review** — ověřeno u #62. Nesmí se to tedy nabídnout.
    @Test("Řádek mimo hunky se komentovat nedá")
    func refusesALineOutsideHunks() throws {
        let file = try file()
        let outside = line(.context, old: 5, new: 5, text: "výplň mimo hunk")

        #expect(Policy.commentableSide(of: outside, in: file) == nil)
    }

    /// **Rozbalený kontext (#47) komentovat nejde** — jsou to řádky dotažené ze souboru,
    /// které v diffu nejsou. `DiffRow` je skládá jako obyčejný kontext s oběma čísly, takže
    /// se to musí poznat příslušností k hunku, ne z `DiffLine` samotného.
    @Test("Rozbalený kontext se komentovat nedá")
    func refusesRevealedContext() throws {
        let file = try file()
        let content = (1...40).map { "// řádek \($0)" }
        var revealed = RevealedLines()
        revealed.reveal(20...24)

        let rows = DiffRow.rows(of: file, revealed: revealed, content: content)
        let revealedLines = rows.compactMap { row -> DiffLine? in
            guard case .line(_, let line) = row else { return nil }
            // Řádky hunku mají čísla 25–27; cokoli nižšího přišlo z rozbalení.
            guard let number = line.newNumber, number < 25 else { return nil }
            return line
        }

        #expect(!revealedLines.isEmpty, "rozbalení nedodalo žádný řádek")
        for line in revealedLines {
            #expect(
                Policy.commentableSide(of: line, in: file) == nil,
                "rozbalený řádek \(line.newNumber ?? -1) se nabízí ke komentáři"
            )
        }
    }

    /// Řádky hunku komentovatelné **zůstanou**, i když je kolem nich rozbalený kontext.
    ///
    /// Rozbalení se tu musí opravdu udělat, ne jen zmínit v názvu: bez `DiffRow.rows`
    /// s `revealed`/`content` by test prošel, i kdyby rozbalení hunkové řádky rozbilo.
    @Test("Rozbalení nezkazí komentovatelnost řádků hunku")
    func keepsHunkLinesCommentableAfterRevealing() throws {
        let file = try file()
        let content = (1...40).map { "// řádek \($0)" }
        var revealed = RevealedLines()
        revealed.reveal(20...24)

        let rows = DiffRow.rows(of: file, revealed: revealed, content: content)
        let hunkLines = rows.compactMap { row -> DiffLine? in
            guard case .line(_, let line) = row else { return nil }
            // Řádky hunku jsou 25–27 na nové straně, plus odebraný, který nové číslo nemá.
            guard line.kind != .meta else { return nil }
            guard line.newNumber.map({ $0 >= 25 }) ?? true else { return nil }
            return line
        }

        #expect(hunkLines.count == 4, "hunk má tři nové řádky a jeden odebraný")
        for line in hunkLines {
            #expect(
                Policy.isCommentable(line, in: file),
                "řádek hunku (\(line.kind)) po rozbalení přestal být komentovatelný"
            )
        }
    }

    @Test("Soubor bez hunků nemá co komentovat")
    func refusesEverythingWithoutHunks() {
        let diff = DiffParser.parse("""
            diff --git a/logo.png b/logo.png
            Binary files a/logo.png and b/logo.png differ
            """)
        guard let binary = diff.files.first else { return }

        #expect(Policy.commentableSide(
            of: line(.added, old: nil, new: 1, text: "cokoli"),
            in: binary
        ) == nil)
    }

    // MARK: - Kotvy

    /// Kotva je číslo **a** strana. U odebraného řádku musí přijít staré číslo — nové
    /// neexistuje, takže by komentář odešel jinam, nebo vůbec.
    @Test("Kotva odebraného řádku nese staré číslo a levou stranu")
    func anchorsARemovedLineOnTheOldNumber() throws {
        let file = try file()
        let removed = try #require(file.hunks.first?.lines.first { $0.kind == .removed })

        let anchor = try #require(Policy.commentAnchor(of: removed, in: file))

        #expect(anchor.side == .left)
        #expect(anchor.line == removed.oldNumber)
    }

    @Test("Kotva přidaného řádku nese nové číslo a pravou stranu")
    func anchorsAnAddedLineOnTheNewNumber() throws {
        let file = try file()
        let added = try #require(file.hunks.first?.lines.first { $0.kind == .added })

        let anchor = try #require(Policy.commentAnchor(of: added, in: file))

        #expect(anchor.side == .right)
        #expect(anchor.line == added.newNumber)
    }

    /// Mapa je jen zrychlení, takže musí dávat **totéž**, co dotaz po jednom. Kdyby se
    /// rozešly, nabízela by se tlačítka na řádcích, které GitHub odmítne — a odmítne s nimi
    /// celé review.
    @Test("Mapa kotev odpovídá dotazu po jednom řádku")
    func theAnchorMapAgreesWithSingleLookups() throws {
        let file = try file()
        let anchors = Policy.commentAnchors(in: file)

        for hunk in file.hunks {
            for line in hunk.lines {
                #expect(anchors[line] == Policy.commentAnchor(of: line, in: file))
            }
        }
        #expect(anchors.count == 4, "hunk má tři řádky s číslem plus odebraný")
    }

    /// Rozbalený kontext (#47) v mapě být nesmí — je to řádek, který v diffu není.
    @Test("Mapa kotev neobsahuje rozbalený kontext")
    func theAnchorMapSkipsRevealedContext() throws {
        let file = try file()
        let anchors = Policy.commentAnchors(in: file)

        #expect(anchors[line(.context, old: 5, new: 5, text: "výplň mimo hunk")] == nil)
    }

    // MARK: - Kam převzatý nález patří

    @Test("Nález na řádku v hunku jde jako řádkový komentář")
    func adoptsAFindingInsideAHunkAsALineComment() throws {
        let diff = try diff()
        let finding = makeFinding(file: "Cart.php", line: 26)

        #expect(
            Policy.draftTarget(for: finding, in: diff)
                == .line(path: "Cart.php", anchor: DraftAnchor(line: 26, side: .right))
        )
    }

    /// Řádkový komentář mimo hunk GitHub odmítne (`422`) a s ním celé review, takže se to
    /// nesmí ani zkusit — jde do těla jako odkaz na kód.
    @Test("Nález mimo hunky jde do těla review")
    func sendsAFindingOutsideHunksToTheBody() throws {
        let diff = try diff()
        let finding = makeFinding(file: "Cart.php", line: 120)

        #expect(Policy.draftTarget(for: finding, in: diff) == .body(path: "Cart.php", line: 120))
    }

    @Test("Nález bez řádku jde do těla jako odkaz na soubor")
    func sendsAFindingWithoutALineToTheBody() throws {
        let diff = try diff()
        let finding = makeFinding(file: "Cart.php", line: nil)

        #expect(Policy.draftTarget(for: finding, in: diff) == .body(path: "Cart.php", line: nil))
    }

    /// Nález bez souboru odkaz nemá kam udělat, takže jde do těla jako holý text.
    @Test("Nález bez souboru jde do těla bez odkazu")
    func sendsAFindingWithoutAFileToTheBodyWithoutALink() throws {
        #expect(
            Policy.draftTarget(for: makeFinding(file: nil, line: nil), in: try diff())
                == .body(path: nil, line: nil)
        )
    }

    /// Reviewer umí nahlásit přejmenovaný soubor pod **starou** cestou, kdežto komentář
    /// i permalink míří na hlavu PR. Bez překladu by komentář odešel na cestu, která tam
    /// není — `422 Path could not be resolved`.
    @Test("Nález pod starou cestou se přeloží na tu dnešní")
    func translatesTheOldPathOfARenamedFile() throws {
        let diff = DiffParser.parse("""
            diff --git a/Old.php b/New.php
            similarity index 90%
            rename from Old.php
            rename to New.php
            --- a/Old.php
            +++ b/New.php
            @@ -1,2 +1,2 @@
             kontext
            -staré
            +nové
            """)
        let finding = makeFinding(file: "Old.php", line: 2)

        #expect(
            Policy.draftTarget(for: finding, in: diff)
                == .line(path: "New.php", anchor: DraftAnchor(line: 2, side: .right))
        )
    }

    /// Bez diffu se nedá poznat, co je uvnitř hunku — a hádat znamená riskovat odmítnutí
    /// celého review.
    @Test("Bez načteného diffu jde nález do těla")
    func sendsEverythingToTheBodyWithoutADiff() {
        #expect(
            Policy.draftTarget(for: makeFinding(file: "Cart.php", line: 26), in: nil)
                == .body(path: "Cart.php", line: 26)
        )
    }

    // MARK: - Text převzatého nálezu

    @Test("Převzatý text je to, co napsal reviewer")
    func prefillsWithTheReviewerText() {
        let finding = makeFinding(summary: "total() ignoruje množství")

        #expect(Policy.adoptedText(of: finding) == "total() ignoruje množství")
    }

    /// „Kdy to praskne“ je v review komentáři to nejcennější a smazat odstavec je jedno gesto.
    @Test("Scénář selhání jde do textu jako druhý odstavec")
    func appendsTheFailureScenario() {
        let finding = makeFinding(
            summary: "total() ignoruje množství",
            failureScenario: "Košík se dvěma kusy vyjde na cenu jednoho."
        )

        #expect(Policy.adoptedText(of: finding) == """
            total() ignoruje množství

            Košík se dvěma kusy vyjde na cenu jednoho.
            """)
    }

    // MARK: - Odznak „už je v draftu“

    @Test("Převzatý nález se pozná podle kotvy a revieweera")
    func recognisesAnAdoptedFinding() throws {
        let diff = try diff()
        let finding = makeFinding(file: "Cart.php", line: 26, reviewer: "code-review")
        let target = Policy.draftTarget(for: finding, in: diff)
        let draft = ReviewDraft(
            pullRequest: pr,
            headSha: "abc",
            comments: [
                ReviewDraftComment(
                    path: "Cart.php",
                    line: 26,
                    side: .right,
                    body: "moje slova",
                    origin: .finding(reviewer: "code-review")
                ),
            ]
        )

        #expect(Policy.isAdopted(finding, target: target, in: draft, repo: pr.repo))
    }

    /// Dva reviewery na jednom řádku jsou běžné (odznak `2×`). Kdyby odznak koukal jen na
    /// kotvu, tvrdil by o nepřevzatém nálezu, že v draftu je — a ten by z odeslaného review
    /// tiše vypadl.
    @Test("Nález druhého revieweera na tomtéž řádku převzatý není")
    func doesNotConfuseTwoReviewersOnOneLine() throws {
        let diff = try diff()
        let mine = makeFinding(file: "Cart.php", line: 26, reviewer: "code-review")
        let other = makeFinding(file: "Cart.php", line: 26, reviewer: "oj-php-quality-check")
        let draft = ReviewDraft(
            pullRequest: pr,
            headSha: "abc",
            comments: [
                ReviewDraftComment(
                    path: "Cart.php",
                    line: 26,
                    side: .right,
                    body: "moje slova",
                    origin: .finding(reviewer: "code-review")
                ),
            ]
        )

        #expect(Policy.isAdopted(mine, target: Policy.draftTarget(for: mine, in: diff), in: draft, repo: pr.repo))
        #expect(!Policy.isAdopted(other, target: Policy.draftTarget(for: other, in: diff), in: draft, repo: pr.repo))
    }

    /// Vlastní komentář na tomtéž řádku není převzatý nález.
    @Test("Vlastní komentář na řádku nález za převzatý nevydává")
    func doesNotCountMyOwnCommentAsAdopted() throws {
        let diff = try diff()
        let finding = makeFinding(file: "Cart.php", line: 26)
        let draft = ReviewDraft(
            pullRequest: pr,
            headSha: "abc",
            comments: [
                ReviewDraftComment(path: "Cart.php", line: 26, side: .right, body: "moje", origin: .own),
            ]
        )

        #expect(!Policy.isAdopted(finding, target: Policy.draftTarget(for: finding, in: diff), in: draft, repo: pr.repo))
    }

    /// U položky v těle rozhoduje přítomnost odkazu: text si člověk přepíše, odkaz ne.
    @Test("Nález v těle se pozná podle odkazu")
    func recognisesAFindingAdoptedIntoTheBody() throws {
        let diff = try diff()
        let finding = makeFinding(file: "Cart.php", line: 120)
        let link = try #require(Policy.permalink(to: "Cart.php", line: 120, in: pr.repo, at: "abc"))
        let draft = ReviewDraft(pullRequest: pr, headSha: "abc", body: "\(link.absoluteString)\n\ntext")

        #expect(Policy.isAdopted(finding, target: Policy.draftTarget(for: finding, in: diff), in: draft, repo: pr.repo))
    }

    @Test("Bez draftu není převzatý nic")
    func nothingIsAdoptedWithoutADraft() throws {
        let finding = makeFinding(file: "Cart.php", line: 26)

        #expect(!Policy.isAdopted(
            finding,
            target: Policy.draftTarget(for: finding, in: try diff()),
            in: nil,
            repo: pr.repo
        ))
    }

    // MARK: - Permalink a tělo review

    @Test("Permalink míří na řádek v commitu")
    func buildsAPermalink() throws {
        let link = try #require(Policy.permalink(
            to: "App/Store/AppStore.swift",
            line: 42,
            in: RepoID(owner: "ondrajodas", name: "PRism"),
            at: "abc123"
        ))

        #expect(link.absoluteString
            == "https://github.com/ondrajodas/PRism/blob/abc123/App/Store/AppStore.swift#L42")
    }

    @Test("Permalink bez řádku ukazuje na soubor")
    func buildsAPermalinkWithoutALine() throws {
        let link = try #require(Policy.permalink(
            to: "Cart.php",
            line: nil,
            in: pr.repo,
            at: "abc123"
        ))

        #expect(link.absoluteString == "https://github.com/cli/cli/blob/abc123/Cart.php")
    }

    /// Neescapovaná mezera odkaz rozlomí a GitHub z něj úryvek kódu neudělá.
    @Test("Mezera v cestě se v permalinku zakóduje")
    func encodesSpacesInThePath() throws {
        let link = try #require(Policy.permalink(
            to: "src/My File.php",
            line: 3,
            in: pr.repo,
            at: "abc"
        ))

        #expect(link.absoluteString == "https://github.com/cli/cli/blob/abc/src/My%20File.php#L3")
    }

    /// Odkaz musí stát **sám na řádku** — s textem na téže řádce z něj GitHub úryvek kódu
    /// neudělá a zůstane holá URL.
    @Test("Položka těla má odkaz na vlastním řádku")
    func putsTheLinkOnItsOwnLine() throws {
        let link = try #require(Policy.permalink(to: "Cart.php", line: 7, in: pr.repo, at: "abc"))

        let item = Policy.bodyItem(text: "chybí kontrola", link: link)

        #expect(item == "\(link.absoluteString)\n\nchybí kontrola")
    }

    @Test("Položka bez odkazu je jen text")
    func fallsBackToPlainText() {
        #expect(Policy.bodyItem(text: "chybí testy", link: nil) == "chybí testy")
    }

    @Test("Přidání položky nezahodí, co je v těle")
    func keepsTheExistingBody() {
        #expect(Policy.appendingBodyItem("druhá", to: "první") == "první\n\ndruhá")
        #expect(Policy.appendingBodyItem("druhá", to: "první\n") == "první\n\ndruhá")
        #expect(Policy.appendingBodyItem("první", to: "") == "první")
    }

    // MARK: - Zastarání

    @Test("Draft proti hlavě PR zastaralý není")
    func isFreshAgainstTheHead() {
        let draft = ReviewDraft(pullRequest: pr, headSha: "abc", body: "tělo")

        #expect(!Policy.isStale(draft, head: "abc"))
    }

    @Test("Nový commit draft označí za zastaralý")
    func goesStaleOnANewCommit() {
        let draft = ReviewDraft(pullRequest: pr, headSha: "abc", body: "tělo")

        #expect(Policy.isStale(draft, head: "def"))
    }

    // MARK: - Odesílatelnost

    /// Odesílatelnost se testuje nad **sandboxovým** repem, protože `PublishScope` je
    /// součástí odpovědi: na `cli/cli` by nic nešlo odeslat bez ohledu na obsah draftu.
    /// Že to tak je, hlídá `blocksARepositoryOutsideTheSandbox` níž.
    private let sandbox = PRIdentifier("ondrajodas/prism-review-sandbox#7")!

    @Test("Draft s verdiktem a obsahem se odeslat dá")
    func sendsADraftWithAVerdict() {
        let draft = ReviewDraft(pullRequest: sandbox, headSha: "abc", body: "tělo", verdict: .approve)

        #expect(Policy.sendBlock(for: draft, head: "abc") == nil)
    }

    /// `event` je v API povinný a hádat ho za člověka znamená odeslat něco jiného, než chtěl.
    @Test("Bez vybraného verdiktu se odeslat nedá")
    func isNotSendableWithoutAVerdict() {
        let draft = ReviewDraft(pullRequest: sandbox, headSha: "abc", body: "tělo", verdict: nil)

        #expect(Policy.sendBlock(for: draft, head: "abc") == .noVerdict)
    }

    @Test("Úplně prázdný draft se odeslat nedá")
    func isNotSendableWhenEmpty() {
        let draft = ReviewDraft(pullRequest: sandbox, headSha: "abc")

        #expect(draft.isEmpty)
        #expect(Policy.sendBlock(for: draft, head: "abc") == .nothingToSend)
    }

    /// Draft, který se ještě nezaložil, není „prázdný jinak“ — je to tentýž důvod.
    @Test("Neexistující draft se odeslat nedá")
    func blocksAMissingDraft() {
        #expect(Policy.sendBlock(for: nil, head: "abc") == .nothingToSend)
    }

    /// Brána na sandbox je **první**, stejně jako v publisheru: na cizí repo se nemá ani
    /// nabízet tlačítko, natož sahat na síť.
    @Test("Repo mimo sandbox odeslání zablokuje ještě před obsahem draftu")
    func blocksARepositoryOutsideTheSandbox() {
        let draft = ReviewDraft(pullRequest: pr, headSha: "abc", body: "tělo", verdict: .approve)

        #expect(Policy.sendBlock(for: draft, head: "abc") == .outsideScope(pr.repo))
    }

    /// „Nevím, jaká je hlava“ **není** „zastaralé“ — dokud se detail načítá, nedá se říct
    /// ani jedno, a banner o zastaralém draftu by nad ním lhal.
    @Test("Neznámá hlava PR je vlastní důvod, ne zastarání")
    func blocksWhenTheHeadIsUnknown() {
        let draft = ReviewDraft(pullRequest: sandbox, headSha: "abc", body: "tělo", verdict: .approve)

        #expect(Policy.sendBlock(for: draft, head: nil) == .headUnknown(detail: nil))
    }

    /// **Hlásí se ten důvod, se kterým se dá něco udělat.** Vada na samotném draftu jde před
    /// čekáním na hlavu PR: „vyber verdikt“ se dá splnit hned, kdežto „zjišťuji, na kterém
    /// commitu PR stojí“ posílá čekat — a když se detail nepovede načíst, čekalo by se
    /// donekonečna nad draftem, kterému chybí verdikt. Nález Copilota z #112.
    @Test("Vada draftu se hlásí dřív než čekání na hlavu PR")
    func prefersTheReasonTheUserCanFix() {
        let withoutVerdict = ReviewDraft(pullRequest: sandbox, headSha: "abc", body: "tělo")
        let withBlankComment = ReviewDraft(
            pullRequest: sandbox,
            headSha: "abc",
            verdict: .comment,
            comments: [
                ReviewDraftComment(path: "a.php", line: 1, side: .right, body: " ", origin: .own),
            ]
        )

        #expect(Policy.sendBlock(for: withoutVerdict, head: nil) == .noVerdict)
        #expect(Policy.sendBlock(for: withBlankComment, head: nil) == .blankComment)
        // A totéž proti zastarání — dopsat komentář jde, přenést draft na nový commit (#69)
        // zatím ne.
        #expect(Policy.sendBlock(for: withBlankComment, head: "def") == .blankComment)
    }

    /// Schválení **bez prózy a bez komentářů je plnohodnotné review** — v datech z #63 to
    /// byla čtvrtina vzorku. Kdyby ho `isEmpty` bralo jako prázdné, nešlo by PR odklepnout
    /// bez toho, aby k tomu člověk něco napsal.
    @Test("Samotný verdikt bez prózy se odeslat dá")
    func sendsADraftWithNothingButAVerdict() {
        let draft = ReviewDraft(pullRequest: sandbox, headSha: "abc", verdict: .approve)

        #expect(!draft.isEmpty)
        #expect(Policy.sendBlock(for: draft, head: "abc") == nil)
    }

    /// Prázdný komentář vzniká běžně — kliknu na „komentovat“ a rozmyslím si to. GitHub
    /// takový payload odmítne, a protože je odeslání atomické, padne s ním celé review.
    @Test("Prázdný komentář zablokuje odeslání")
    func isNotSendableWithABlankComment() {
        let draft = ReviewDraft(
            pullRequest: sandbox,
            headSha: "abc",
            verdict: .comment,
            comments: [
                ReviewDraftComment(path: "a.php", line: 1, side: .right, body: "napsané", origin: .own),
                ReviewDraftComment(path: "a.php", line: 2, side: .right, body: "  \n ", origin: .own),
            ]
        )

        #expect(!draft.isEmpty)
        #expect(Policy.sendBlock(for: draft, head: "abc") == .blankComment)
    }

    /// Nový commit draft **nemaže**, jen blokuje odeslání.
    @Test("Zastaralý draft se odeslat nedá, ale zůstává")
    func isNotSendableWhenStale() {
        let draft = ReviewDraft(pullRequest: sandbox, headSha: "abc", body: "tělo", verdict: .approve)

        #expect(Policy.sendBlock(for: draft, head: "def") == .stale(draft: "abc", head: "def"))
        #expect(!draft.isEmpty)
    }

    /// Věta u každého důvodu musí něco říkat — hláška, ze které nevyplývá další krok, je jen
    /// zpráva o smůle, a prázdný text by v okně vypadal jako mlčky zakázané tlačítko.
    @Test("Každý důvod má vlastní větu")
    func everyBlockExplainsItself() {
        let blocks: [DraftSendBlock] = [
            .nothingToSend,
            .outsideScope(pr.repo),
            .headUnknown(detail: nil),
            .headUnknown(detail: "gh není přihlášený."),
            .noVerdict,
            .stale(draft: "abcdef1234", head: "9876fedcba"),
            .blankComment,
        ]

        #expect(Set(blocks.map(\.userDescription)).count == blocks.count)
        #expect(blocks.allSatisfy { !$0.userDescription.isEmpty })
        // Zkrácené sha, ne celé — v hlášce jde o to, že se liší, ne o čtyřicet znaků.
        #expect(DraftSendBlock.stale(draft: "abcdef1234", head: "9876fedcba").userDescription
            .contains("abcdef1"))
    }

    // MARK: - Prázdnost

    @Test("Draft je prázdný jen bez těla, verdiktu i komentářů")
    func recognisesAnEmptyDraft() {
        #expect(ReviewDraft(pullRequest: pr, headSha: "abc").isEmpty)
        #expect(!ReviewDraft(pullRequest: pr, headSha: "abc", body: "tělo").isEmpty)
        #expect(!ReviewDraft(pullRequest: pr, headSha: "abc", verdict: .comment).isEmpty)
        #expect(!ReviewDraft(
            pullRequest: pr,
            headSha: "abc",
            comments: [
                ReviewDraftComment(path: "a.php", line: 1, side: .right, body: "x", origin: .own),
            ]
        ).isEmpty)
    }
}
