import Foundation
import Testing

@testable import PRism

/// Co je vidět po rozkliknutí commitu (#317) — vyčerpávající výčet nad čistými funkcemi.
@Suite("Diff commitu — stav tabu")
struct CommitDiffTabStateTests {
    private static let repo = RepoID(owner: "keboola", name: "job-queue")

    private func commit(_ sha: String, message: String = "feat: něco", merge: Bool = false) -> PullRequestCommit {
        PullRequestCommit(
            sha: sha,
            message: message,
            authorName: "Odin Uv",
            authorLogin: "odinuv",
            avatarURL: nil,
            committedAt: Date(timeIntervalSince1970: 1_754_000_000),
            isMerge: merge
        )
    }

    private var diff: Diff {
        DiffParser.parse("""
            diff --git a/Cart.php b/Cart.php
            --- a/Cart.php
            +++ b/Cart.php
            @@ -1,3 +1,4 @@
             <?php
            -$a = 1;
            +$a = 2;
            +$b = 3;
            """)
    }

    // MARK: - Který commit je otevřený

    @Test("Bez žádosti se kreslí seznam")
    func drawsTheListWithoutARequest() {
        #expect(Policy.openCommit(nil, in: [commit("aaa")]) == nil)
    }

    @Test("Otevřený commit se hledá podle sha")
    func findsTheOpenCommitBySha() {
        let list = [commit("aaa"), commit("bbb")]
        #expect(Policy.openCommit("bbb", in: list)?.sha == "bbb")
    }

    /// Force push umí commit z PR odstranit. Kreslit dál jeho hlavičku by znamenalo obrazovku,
    /// ze které se nedá poznat, že už neplatí — tab proto spadne zpátky na seznam.
    @Test("Commit, který ze seznamu zmizel, se nekreslí")
    func fallsBackToTheListWhenTheCommitIsGone() {
        #expect(Policy.openCommit("bbb", in: [commit("aaa")]) == nil)
    }

    // MARK: - Stav diffu

    @Test("Bez staženého diffu se čeká")
    func waitsWithoutAStoredDiff() {
        #expect(Policy.commitDiffTab(nil, of: commit("aaa")) == .loading)
    }

    /// V okně se drží nejvýš jeden diff commitu na PR, takže hned po kliknutí na jiný commit tam
    /// ještě leží ten předchozí. Nakreslit ho pod novou hlavičkou by byl diff, který k ní nepatří.
    @Test("Diff jiného commitu se nekreslí, čeká se")
    func ignoresADiffOfAnotherCommit() {
        let stored = CommitDiff(sha: "aaa", content: .loaded(diff))
        #expect(Policy.commitDiffTab(stored, of: commit("bbb")) == .loading)
    }

    @Test("Načtený diff se ukáže")
    func showsTheLoadedDiff() {
        let stored = CommitDiff(sha: "aaa", content: .loaded(diff))
        #expect(Policy.commitDiffTab(stored, of: commit("aaa")) == .diff(diff))
    }

    @Test("Selhání si nechá text od gh")
    func keepsTheFailureText() {
        let stored = CommitDiff(sha: "aaa", content: .failed("HTTP 404"))
        #expect(Policy.commitDiffTab(stored, of: commit("aaa")) == .failed("HTTP 404"))
    }

    // MARK: - Prázdný diff

    /// Prázdno **není porucha ani načítání** — měřeno na `keboola/job-queue#727`, kde tři commity
    /// z `git commit --allow-empty` vracejí nula bajtů.
    @Test("Prázdný diff obyčejného commitu má vlastní větu")
    func explainsAnEmptyOrdinaryCommit() throws {
        let stored = CommitDiff(sha: "aaa", content: .loaded(DiffParser.parse("")))
        guard case .nothing(let empty) = Policy.commitDiffTab(stored, of: commit("aaa")) else {
            Issue.record("Prázdný diff má být vysvětlený, ne porucha")
            return
        }
        #expect(empty.message.contains("allow-empty"))
        #expect(!empty.title.contains("Sloučení"))
    }

    @Test("Prázdný diff sloučení má jinou větu než prázdný commit")
    func explainsAnEmptyMergeDifferently() throws {
        let stored = CommitDiff(sha: "aaa", content: .loaded(DiffParser.parse("")))
        guard case .nothing(let merge) = Policy.commitDiffTab(stored, of: commit("aaa", merge: true)),
              case .nothing(let ordinary) = Policy.commitDiffTab(stored, of: commit("aaa"))
        else {
            Issue.record("Obě podoby prázdna mají mít větu")
            return
        }
        #expect(merge != ordinary)
        #expect(merge.message.contains("prvnímu rodiči"))
    }

    /// Ani jedna z těch vět nesmí znít jako porucha: prázdný diff je platná odpověď a věta je
    /// jediné, z čeho se to pozná.
    @Test("Věty o prázdnu říkají, že to není porucha", arguments: [true, false])
    func saysItIsNotAFailure(isMerge: Bool) {
        #expect(Policy.emptyCommitDiff(isMerge: isMerge).message.contains("Není to porucha"))
    }

    // MARK: - Čísla a adresy

    @Test("Počty se počítají ze staženého diffu")
    func countsComeFromTheDiff() {
        let facts = Policy.commitDiffFacts(of: diff)
        #expect(facts.files == "1 soubor")
        #expect(facts.additions == 2)
        #expect(facts.deletions == 1)
    }

    /// České skloňování je tentýž rozdíl jako u seznamu (#316) — `1 soubor` nemá znít jako chyba.
    @Test("Počet souborů se skloňuje", arguments: [(1, "1 soubor"), (3, "3 soubory"), (7, "7 souborů")])
    func inflectsTheFileCount(count: Int, expected: String) {
        let files = (1...max(count, 1)).map { index in
            """
            diff --git a/F\(index).php b/F\(index).php
            --- a/F\(index).php
            +++ b/F\(index).php
            @@ -1 +1 @@
            -a
            +b
            """
        }
        #expect(Policy.commitDiffFacts(of: DiffParser.parse(files.joined(separator: "\n"))).files == expected)
    }

    @Test("Pozice se počítá v pořadí, ve kterém je seznam nakreslený")
    func countsThePositionInTheDrawnOrder() {
        let list = [commit("aaa"), commit("bbb"), commit("ccc")]
        #expect(Policy.commitPosition(of: "bbb", in: list) == "2 ze 3")
        #expect(Policy.commitPosition(of: "aaa", in: list) == "1 ze 3")
    }

    @Test("Pozice commitu mimo seznam se netvrdí")
    func hasNoPositionOutsideTheList() {
        #expect(Policy.commitPosition(of: "zzz", in: [commit("aaa")]) == nil)
    }

    @Test("Adresa commitu míří na jeho stránku na GitHubu")
    func buildsTheCommitURL() {
        #expect(
            Policy.commitURL(of: "5e2b1aa", in: Self.repo)?.absoluteString
                == "https://github.com/keboola/job-queue/commit/5e2b1aa"
        )
    }

    // MARK: - Tělo zprávy a jeho sbalování

    /// Titulek hlavičky **je** první řádka, takže tělo je všechno pod ní — jinak by hlavička
    /// tvrdila totéž dvakrát.
    @Test("Tělo zprávy je všechno pod první řádkou")
    func takesEverythingBelowTheFirstLine() {
        let message = "feat: cache secrets\n\nKaždý požadavek si sáhne do Vaultu za každým klíčem."
        #expect(Policy.commitMessageBody(of: commit("aaa", message: message))
            == "Každý požadavek si sáhne do Vaultu za každým klíčem.")
    }

    /// Většina commitů má jednořádkovou zprávu. Prázdné tělo je signál pro hlavičku, že nemá
    /// kreslit **ani přepínač** — sbalovat prázdno nemá co říct.
    @Test(
        "Jednořádková zpráva nemá tělo",
        arguments: ["feat: něco", "feat: něco\n", "feat: něco\n\n  \n", "feat: něco\r\n", "feat: něco\r"]
    )
    func hasNoBodyForASingleLineMessage(message: String) {
        #expect(Policy.commitMessageBody(of: commit("aaa", message: message)).isEmpty)
    }

    /// Rozbalený stav počet neuvádí: text je vidět, takže by číslo bylo šum vedle toho, o čem
    /// mluví. **Sbalený ho uvádí**, protože je to jediné, co o schovaném textu něco říká.
    @Test("Počet řádků je jen ve sbaleném popisku")
    func countsLinesOnlyWhenCollapsed() {
        let body = "první\ndruhá\ntřetí"
        #expect(Policy.commitMessageToggle(body, expanded: true) == "Tělo zprávy")
        #expect(Policy.commitMessageToggle(body, expanded: false) == "Tělo zprávy · 3 řádky")
    }

    /// Prázdný řádek mezi odstavci se počítá: v hlavičce zabírá místo jako každý jiný, a počet
    /// odpovídá na otázku „kolik toho schovávám“.
    @Test("Prázdné řádky mezi odstavci se počítají")
    func countsBlankLinesBetweenParagraphs() {
        #expect(Policy.commitMessageToggle("první\n\ntřetí", expanded: false) == "Tělo zprávy · 3 řádky")
    }

    @Test(
        "Počet řádků se skloňuje",
        arguments: [(1, "1 řádek"), (2, "2 řádky"), (5, "5 řádků")]
    )
    func inflectsTheLineCount(count: Int, expected: String) {
        let body = (1...count).map { "řádka \($0)" }.joined(separator: "\n")
        #expect(Policy.commitMessageToggle(body, expanded: false) == "Tělo zprávy · \(expected)")
    }

    // MARK: - Zakončení řádků ve zprávě (#339)

    /// **Tohle je ta chyba z #339.** Do opravy se řádky počítaly `split(separator: "\n")`, a `"\r\n"`
    /// je ve Swiftu **jeden `Character`** — takže se na `CRLF` nerozdělilo vůbec a v hlavičce stálo
    /// `Tělo zprávy · 1 řádek` bez ohledu na délku zprávy. Popisek tvrdil přesný opak toho, kvůli
    /// čemu tam je: má odpovědět, jestli se vyplatí text rozbalit.
    ///
    /// Fixture je **skutečná odpověď** `gh api …/pulls/6293/commits` na veřejném
    /// `git-for-windows/git`, kde commit `415ab35` má míchaná zakončení (titulek `LF`, tělo `CRLF`);
    /// ručně psaný literál by nesl `LF` toho, kdo ho napsal, a test by zezelenal nad rozbitým
    /// počítáním. Proč nestojí v `.gitattributes`, je u `GhCommitTests.keepsCRLFInTheMessage()`.
    @Test("Tělo s CRLF má skutečný počet řádků, ne jeden")
    func countsLinesInACRLFBody() throws {
        let body = Policy.commitMessageBody(of: try CommitFixture.crlfCommit())

        #expect(body.contains("\r\n"), "fixture přišla o CRLF — viz GhCommitTests")
        #expect(Policy.commitMessageToggle(body, expanded: false) == "Tělo zprávy · 3 řádky")
    }

    /// **Odpověď na „nezměnilo se něco na `LF` vstupech?“** Tatáž zpráva s `LF` musí dát tentýž
    /// popisek — jinak by oprava `CRLF` byla směna, ne oprava.
    @Test("Tělo s CRLF dá stejný popisek jako totéž tělo s LF")
    func countsCRLFSameAsLF() throws {
        let commit = try CommitFixture.crlfCommit()
        let body = Policy.commitMessageBody(of: commit)
        let lf = body.replacingOccurrences(of: "\r\n", with: "\n")

        #expect(lf != body, "předpoklad testu: tělo z fixture má CRLF")
        #expect(
            Policy.commitMessageToggle(body, expanded: false)
                == Policy.commitMessageToggle(lf, expanded: false)
        )
    }

    /// Zakončení si vybírá cizí repo, ne my — `LF`, `CRLF`, samotné `CR` i míchaná zakončení
    /// v jedné zprávě musí dát **stejný** počet.
    @Test(
        "Počet řádků nezávisí na tom, jaké zakončení cizí repo používá",
        arguments: [
            "první\ndruhá\ntřetí",
            "první\r\ndruhá\r\ntřetí",
            "první\rdruhá\rtřetí",
            "první\r\ndruhá\ntřetí",
        ]
    )
    func countsLinesRegardlessOfTheTerminator(body: String) {
        #expect(Policy.commitMessageToggle(body, expanded: false) == "Tělo zprávy · 3 řádky")
    }

    /// Titulek a tělo jsou **dvě půlky jednoho rozdělení**, takže musí mít tentýž pojem „konec
    /// řádky“ (#339). `U+2028` je pro `git` **obsah**, ne konec řádku — kdyby se na něm dělilo
    /// (`isNewline`), usekl by titulek a jeho zbytek by se v hlavičce objevil ještě jako první řádka
    /// těla, tedy tentýž text dvakrát. `lineLimit` v obou pohledech (1 v seznamu, 2 v hlavičce)
    /// znamená, že delší titulek sazbu nerozhodí.
    @Test("Unicode oddělovač titulek neusekne ani ho nepřelije do těla")
    func keepsUnicodeSeparatorsInsideTheSubject() {
        let separated = commit("aaa", message: "feat: cache\u{2028}secrets\n\nKaždý požadavek sáhne do Vaultu.")

        #expect(separated.subject == "feat: cache\u{2028}secrets")
        let body = Policy.commitMessageBody(of: separated)
        #expect(body == "Každý požadavek sáhne do Vaultu.")
        #expect(Policy.commitMessageToggle(body, expanded: false) == "Tělo zprávy · 1 řádek")
    }

    /// Druhá strana téhož rozhodnutí: `U+2028` v **těle** se nesmí spočítat jako řádek, protože
    /// řádek v hlavičce zabírá místo teprve tehdy, když ho `git` za řádek považuje.
    @Test("Unicode oddělovač v těle se za řádek nepočítá")
    func doesNotCountUnicodeSeparatorsAsLines() {
        #expect(Policy.commitMessageToggle("pořád\u{2028}jedna\u{2029}řádka", expanded: false)
            == "Tělo zprávy · 1 řádek")
    }
}
