import Foundation
import Testing

@testable import PRism

/// Přenesení rozdělaného review na nový commit (#69). Čisté funkce, nic se nemockuje.
///
/// To hlavní není, že se kotva přenese, ale **že se nepřenese tiše**: rozhoduje text řádku, ne
/// jeho číslo, a když se text nenajde, musí z toho vyjít stav, který si žádá rozhodnutí — ne
/// kotva, která sedne na cizí kód.
@Suite("Policy — přenesení draftu")
struct DraftTransferTests {
    private let pr = PRIdentifier("cli/cli#42")!
    private let repo = RepoID(owner: "cli", name: "cli")

    // MARK: - Pomocníci

    /// Původní diff: hunk na nových řádcích 10–13.
    private func oldDiff() -> Diff {
        DiffParser.parse("""
            diff --git a/Cart.php b/Cart.php
            --- a/Cart.php
            +++ b/Cart.php
            @@ -10,4 +10,4 @@
             před
            -staré
            +$total = $this->sum();
             za
            """)
    }

    /// Nový diff, ve kterém se komentovaný řádek **posunul o dva dolů** (přibyly dva řádky nad).
    private func shiftedDiff() -> Diff {
        DiffParser.parse("""
            diff --git a/Cart.php b/Cart.php
            --- a/Cart.php
            +++ b/Cart.php
            @@ -10,4 +10,6 @@
             před
            +$this->assertItems();
            +
            -staré
            +$total = $this->sum();
             za
            """)
    }

    /// Nový diff, ve kterém komentovaný řádek **není** — přepsal se.
    private func rewrittenDiff() -> Diff {
        DiffParser.parse("""
            diff --git a/Cart.php b/Cart.php
            --- a/Cart.php
            +++ b/Cart.php
            @@ -10,4 +10,4 @@
             před
            -staré
            +$total = array_sum($this->prices());
             za
            """)
    }

    private func comment(
        line: Int = 11,
        side: DiffSide = .right,
        start: DraftAnchor.Endpoint? = nil,
        snapshot: DraftSnapshot = DraftSnapshot(anchored: "$total = $this->sum();"),
        body: String = "tady se ignoruje množství",
        path: String = "Cart.php"
    ) -> ReviewDraftComment {
        ReviewDraftComment(
            path: path,
            anchor: DraftAnchor(line: line, side: side, start: start),
            snapshot: snapshot,
            body: body,
            origin: .own
        )
    }

    private func draft(_ comments: [ReviewDraftComment], body: String = "") -> ReviewDraft {
        ReviewDraft(pullRequest: pr, headSha: "aaaa1111", body: body, verdict: .comment, comments: comments)
    }

    // MARK: - Snímek kódu

    /// Snímek se bere z diffu, ne od volajícího — jedno místo, které ví, že vlevo je staré číslo.
    @Test("Snímek nese text řádku pod kotvou")
    func takesTheSnapshotFromTheDiff() throws {
        let file = try #require(oldDiff().files.first)

        let single = Policy.snapshot(of: DraftAnchor(line: 11, side: .right), in: file)
        #expect(single.anchored == "$total = $this->sum();")
        #expect(single.start == nil)

        let range = Policy.snapshot(
            of: DraftAnchor(line: 12, side: .right, start: DraftAnchor.Endpoint(line: 10, side: .right)),
            in: file
        )
        #expect(range.start == "před")
        #expect(range.anchored == "za")
    }

    @Test("Odebraný řádek se snímá ze staré strany")
    func takesTheSnapshotFromTheLeftSide() throws {
        let file = try #require(oldDiff().files.first)

        #expect(Policy.snapshot(of: DraftAnchor(line: 11, side: .left), in: file).anchored == "staré")
    }

    // MARK: - Stav kotvy

    @Test("Nezměněný řádek sedí")
    func reportsAnUnchangedAnchorAsFitting() {
        #expect(Policy.anchorState(of: comment(), in: oldDiff()) == .fits)
    }

    /// Rozhoduje **text**, ne číslo: nový commit čísla posouvá, takže „stejné číslo“ o kódu nic
    /// neříká. Bez tohohle by komentář sedl na cizí řádek a nikdo by to nepoznal.
    @Test("Posunutý řádek se najde na novém čísle")
    func findsAMovedAnchor() throws {
        let state = Policy.anchorState(of: comment(), in: shiftedDiff())

        guard case .moved(let anchor) = state else {
            Issue.record("čekal jsem posun, přišlo \(state)")
            return
        }
        #expect(anchor.line == 13)
        #expect(anchor.side == .right)
    }

    @Test("Přepsaný řádek se ztratí")
    func reportsARewrittenAnchorAsLost() {
        #expect(Policy.anchorState(of: comment(), in: rewrittenDiff()) == .lost)
    }

    @Test("Komentář v souboru, který v novém diffu není, se ztratí")
    func reportsACommentOutsideTheDiffAsLost() {
        #expect(Policy.anchorState(of: comment(path: "Jinde.php"), in: oldDiff()) == .lost)
    }

    /// Draft z doby před #69 snímek nemá. Tvrdit „sedí“ by byl tichý přenos — a tvrdit „ztraceno“
    /// by zahodilo kotvu, která nejspíš platí. Proto vlastní stav.
    @Test("Bez snímku vyjde nejistota, ne shoda")
    func reportsAMissingSnapshotAsUncertain() {
        let older = comment(snapshot: DraftSnapshot())

        #expect(Policy.anchorState(of: older, in: oldDiff()) == .uncertain)
    }

    @Test("Bez snímku a bez řádku v diffu je to ztráta")
    func reportsAMissingSnapshotOutsideTheDiffAsLost() {
        let older = comment(line: 900, snapshot: DraftSnapshot())

        #expect(Policy.anchorState(of: older, in: oldDiff()) == .lost)
    }

    /// Změna odsazení je pořád tentýž řádek — přeanchorovat ho jinam by bylo horší než ho nechat.
    @Test("Změna odsazení kotvu neztratí")
    func ignoresIndentation() {
        let indented = comment(snapshot: DraftSnapshot(anchored: "        $total = $this->sum();"))

        #expect(Policy.anchorState(of: indented, in: oldDiff()) == .fits)
    }

    /// U rozsahu musí sednout **oba** konce: přeanchorovat jen jeden by z rozsahu udělalo něco
    /// jiného, než co člověk označil.
    @Test("Rozsah, kterému zmizel jeden konec, se ztratí")
    func losesARangeWithOneEndGone() {
        let range = comment(
            line: 11,
            start: DraftAnchor.Endpoint(line: 10, side: .right),
            snapshot: DraftSnapshot(anchored: "$total = $this->sum();", start: "před")
        )

        #expect(Policy.anchorState(of: range, in: rewrittenDiff()) == .lost)
    }

    @Test("Rozsah, kterému sedí oba konce, se posune celý")
    func movesAWholeRange() throws {
        let range = comment(
            line: 11,
            start: DraftAnchor.Endpoint(line: 10, side: .right),
            snapshot: DraftSnapshot(anchored: "$total = $this->sum();", start: "před")
        )

        let state = Policy.anchorState(of: range, in: shiftedDiff())

        guard case .moved(let anchor) = state else {
            Issue.record("čekal jsem posun, přišlo \(state)")
            return
        }
        #expect(anchor.start?.line == 10)
        #expect(anchor.line == 13)
    }

    // MARK: - Výchozí volby

    /// Ztracený komentář míří do **těla**, ne do koše: text je ručně psaná práce a odkaz na kód se
    /// z něj udělat dá, takže smazání musí být rozhodnutí člověka.
    @Test("Výchozí volby drží text")
    func defaultsKeepTheText() {
        #expect(Policy.defaultChoice(for: .fits) == .keep)
        #expect(Policy.defaultChoice(for: .moved(DraftAnchor(line: 1, side: .right))) == .keep)
        #expect(Policy.defaultChoice(for: .uncertain) == .keep)
        #expect(Policy.defaultChoice(for: .lost) == .body)
    }

    // MARK: - Přenesení

    @Test("Přenesení nastaví nový commit")
    func setsTheNewHead() {
        let transferred = Policy.transferring(draft([comment()]), to: oldDiff(), head: "bbbb2222", in: repo)

        #expect(transferred.headSha == "bbbb2222")
    }

    @Test("Posunutá kotva se přenese na nový řádek")
    func movesTheAnchor() throws {
        let one = comment()

        let transferred = Policy.transferring(draft([one]), to: shiftedDiff(), head: "bbbb2222", in: repo)

        let moved = try #require(transferred.comments.first)
        #expect(moved.line == 13)
        // Identita zůstává, ať se editor nezahodí a bublina nepřeskočí jako nová.
        #expect(moved.id == one.id)
        #expect(moved.body == "tady se ignoruje množství")
        // A snímek taky: kotva se posunula proto, že se ten text našel jinde.
        #expect(moved.anchoredText == one.anchoredText)
    }

    /// Ztracená kotva se **neřeší tiše**: výchozí je přepis do těla, takže text zůstane i s odkazem
    /// na kód — a odkaz míří na **nový** commit, protože proti němu se tělo odešle.
    @Test("Ztracený komentář se přepíše do těla s odkazem na nový commit")
    func rewritesALostCommentIntoTheBody() {
        let transferred = Policy.transferring(draft([comment()]), to: rewrittenDiff(), head: "bbbb2222", in: repo)

        #expect(transferred.comments.isEmpty)
        #expect(transferred.body.contains("tady se ignoruje množství"))
        #expect(transferred.body.contains("bbbb2222"), "odkaz míří na nový commit")
        #expect(transferred.body.contains("Cart.php"))
    }

    @Test("Vyjmutí komentář zahodí i s textem")
    func dropsADeletedComment() throws {
        let one = comment()
        let transferred = Policy.transferring(
            draft([one]),
            to: oldDiff(),
            head: "bbbb2222",
            in: repo,
            choices: [one.id: .delete]
        )

        #expect(transferred.comments.isEmpty)
        #expect(transferred.body.isEmpty)
    }

    @Test("Rozhodnutí přebije výchozí volbu")
    func honoursAnExplicitChoice() throws {
        let one = comment()

        // Ztracený komentář by šel do těla; člověk si vybere kotvu nechat.
        let kept = Policy.transferring(
            draft([one]),
            to: rewrittenDiff(),
            head: "bbbb2222",
            in: repo,
            choices: [one.id: .keep]
        )
        #expect(kept.comments.count == 1)
        #expect(kept.body.isEmpty)

        // A naopak: sedící komentář jde do těla, když si o to člověk řekne.
        let moved = Policy.transferring(
            draft([one]),
            to: oldDiff(),
            head: "bbbb2222",
            in: repo,
            choices: [one.id: .body]
        )
        #expect(moved.comments.isEmpty)
        #expect(moved.body.contains("tady se ignoruje množství"))
    }

    /// Tělo review se přenesením **neztrácí** — přepsané komentáře se za něj přidávají.
    @Test("Rozepsané tělo zůstane")
    func keepsTheExistingBody() {
        let transferred = Policy.transferring(
            draft([comment()], body: "celkem dobré"),
            to: rewrittenDiff(),
            head: "bbbb2222",
            in: repo
        )

        #expect(transferred.body.hasPrefix("celkem dobré"))
        #expect(transferred.body.contains("tady se ignoruje množství"))
    }

    @Test("Verdikt přenesení nemění")
    func keepsTheVerdict() {
        #expect(Policy.transferring(draft([comment()]), to: oldDiff(), head: "bbbb2222", in: repo).verdict == .comment)
    }
}
