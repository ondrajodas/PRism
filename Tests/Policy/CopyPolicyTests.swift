import Foundation
import Testing

@testable import PRism

/// Skládání kódu z diffu pro schránku (#157).
///
/// Čistá funkce, takže vyčerpávajícím výčtem. To hlavní, co se tu dá pokazit potichu, jsou dvě
/// věci: **pořadí řádků** (rozsah se zvýrazňuje množinou, která pořadí nemá) a **která verze se
/// kopíruje** u rozsahu přes obě strany diffu.
@Suite("Kopírování kódu z diffu")
struct CopyPolicyTests {
    /// Soubor s hunkem, ve kterém je od každého druhu řádku něco: kontext, odebrané a přidané.
    ///
    /// Nové řádky 10–13, staré 10–12.
    private func file(path: String = "src/Cart.php") throws -> FileDiff {
        let diff = DiffParser.parse("""
            diff --git a/\(path) b/\(path)
            --- a/\(path)
            +++ b/\(path)
            @@ -10,3 +10,4 @@ class Cart
                 public function total(): int
            -        return $this->sum;
            +        return $this->sum + $this->tax;
            +    }
                 // konec
            """)
        return try #require(diff.files.first)
    }

    private func lines(of file: FileDiff) -> [DiffLine] {
        file.hunks.flatMap(\.lines)
    }

    private func comment(
        path: String = "src/Cart.php",
        from: DraftAnchor.Endpoint?,
        to: DraftAnchor.Endpoint
    ) -> ReviewDraftComment {
        ReviewDraftComment(
            path: path,
            anchor: DraftAnchor(line: to.line, side: to.side, start: from),
            body: "",
            origin: .own
        )
    }

    // MARK: - Kód, ne diff

    /// **Vedoucí `+`/`-` ani čísla řádků do schránky nepatří.** Text se vkládá do terminálu nebo
    /// do komentáře jako kód, kde by z nich byl syntaktický nesmysl.
    @Test("Ve schránce je kód bez znaků změny a bez čísel")
    func stripsTheDiffMarkup() throws {
        let file = try file()

        let text = Policy.code(of: lines(of: file))
        let copied = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        // Žádný řádek nezačíná znakem změny. **Ne `contains("+ ")`** — `$a + $b` je legitimní kód
        // a první verze tohohle testu na tom spadla; rozhoduje **začátek** řádku.
        #expect(!copied.contains { $0.hasPrefix("+") || $0.hasPrefix("-") })
        // Ani hlavička hunku, ani čísla řádků: kopíruje se obsah souboru, ne diff.
        #expect(!copied.contains { $0.hasPrefix("@@") })
        #expect(copied == [
            "    public function total(): int",
            "        return $this->sum;",
            "        return $this->sum + $this->tax;",
            "    }",
            "    // konec",
        ])
    }

    /// Poznámka `git`u není obsah souboru, takže se do schránky nedostane.
    @Test("Poznámka gitu se nekopíruje")
    func skipsGitNotes() {
        let text = Policy.code(of: [
            DiffLine(kind: .added, oldNumber: nil, newNumber: 1, text: "kód"),
            DiffLine(kind: .meta, oldNumber: nil, newNumber: nil, text: "No newline at end of file"),
        ])

        #expect(text == "kód")
    }

    // MARK: - Rozsah

    /// **Pořadí je to hlavní.** Rozsah se pro zvýraznění drží jako `Set`, který pořadí nemá —
    /// kdyby se z něj kopírovalo, přišel by kód do schránky přeházený a nikdo by to nepoznal,
    /// dokud by ho někam nevložil.
    @Test("Rozsah se kopíruje v pořadí, jak stojí v souboru")
    func keepsTheOrderOfTheRange() throws {
        let file = try file()
        let anchor = DraftAnchor(
            line: 13,
            side: .right,
            start: DraftAnchor.Endpoint(line: 10, side: .right)
        )

        let text = try #require(Policy.code(of: anchor, in: file))

        // Řádky jdou vzestupně podle nového čísla, tedy tak, jak stojí v souboru.
        let copied = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let expected = lines(of: file)
            .compactMap { line -> String? in
                guard line.kind != .removed, let number = line.newNumber, (10...13).contains(number)
                else { return nil }
                return line.text
            }
        #expect(copied == expected)
        #expect(copied.count == 4)
        // A opravdu vzestupně, ne jen se stejným obsahem: první řádek je ten s nejmenším číslem.
        #expect(copied.first == "    public function total(): int")
        #expect(copied.last == "    // konec")
    }

    /// Rozsah na **pravé** straně kopíruje novou verzi — odebraný řádek v ní neexistuje.
    @Test("Rozsah vpravo vynechá odebrané řádky")
    func skipsRemovedLinesOnTheRight() throws {
        let file = try file()
        let anchor = DraftAnchor(
            line: 12,
            side: .right,
            start: DraftAnchor.Endpoint(line: 10, side: .right)
        )

        let text = try #require(Policy.code(of: anchor, in: file))

        #expect(!text.contains("return $this->sum;"))
        #expect(text.contains("return $this->sum + $this->tax;"))
    }

    /// Rozsah čistě na **levé** straně naopak kopíruje ten starý kód: o něm je řeč, když někdo
    /// komentuje smazané řádky. Kdyby se i tady brala nová verze, zkopíroval by se kód, který
    /// s komentářem nesouvisí.
    @Test("Rozsah vlevo kopíruje odebrané řádky, ne přidané")
    func copiesRemovedLinesOnTheLeft() throws {
        let file = try file()
        let anchor = DraftAnchor(
            line: 11,
            side: .left,
            start: DraftAnchor.Endpoint(line: 10, side: .left)
        )

        let text = try #require(Policy.code(of: anchor, in: file))

        #expect(text.contains("return $this->sum;"))
        #expect(!text.contains("return $this->sum + $this->tax;"))
    }

    /// Rozsah **přes obě strany** (tažení přes odebrané i přidané řádky) dává **novou** verzi:
    /// o té je při review řeč a je to ta, která v souboru po mergi zůstane.
    @Test("Rozsah přes obě strany dává novou verzi")
    func prefersTheNewVersionForAMixedRange() throws {
        let file = try file()
        let anchor = DraftAnchor(
            line: 12,
            side: .right,
            start: DraftAnchor.Endpoint(line: 10, side: .left)
        )

        let text = try #require(Policy.code(of: anchor, in: file))

        #expect(!text.contains("return $this->sum;"))
        #expect(text.contains("return $this->sum + $this->tax;"))
    }

    /// Jednořádková kotva rozsah není, takže se z ní rozsah nekopíruje — `copyTargets` u ní
    /// nabídne jen samotný řádek.
    @Test("Kotva bez začátku rozsah nedá")
    func hasNoRangeWithoutAStart() throws {
        let file = try file()

        #expect(Policy.code(of: DraftAnchor(line: 12, side: .right), in: file) == nil)
    }

    @Test("Rozsah mimo diff nedá nic")
    func refusesARangeOutsideTheDiff() throws {
        let file = try file()
        let anchor = DraftAnchor(
            line: 900,
            side: .right,
            start: DraftAnchor.Endpoint(line: 890, side: .right)
        )

        #expect(Policy.code(of: anchor, in: file) == nil)
    }

    // MARK: - Hunk

    /// Kopíruje se **hunk**, ne „celý soubor“: mezi hunky chybí řádky, takže slepený soubor by
    /// tvrdil, že je kód souvislý, a to je zrovna to tiché zkreslení, kterému se aplikace vyhýbá.
    @Test("Hunk se kopíruje jako nová verze")
    func copiesTheHunkAsTheNewVersion() throws {
        let file = try file()
        let hunk = try #require(file.hunks.first)

        let text = Policy.code(of: hunk)

        #expect(text.contains("    public function total(): int"))
        #expect(text.contains("return $this->sum + $this->tax;"))
        #expect(!text.contains("return $this->sum;"))
        #expect(text.contains("    // konec"))
    }

    // MARK: - Hunk řádku

    /// Z kontextového menu řádku se otevírá **celý jeho hunk** jako text k vybírání (#157), takže
    /// se musí najít ten správný — u souboru s víc hunky by cizí hunk ukázal jiný kód.
    @Test("Řádek najde svůj hunk, ne první v souboru")
    func findsTheHunkOfTheLine() throws {
        let diff = DiffParser.parse(twoHunks)
        let file = try #require(diff.files.first)
        #expect(file.hunks.count == 2)
        let line = try #require(lines(of: file).first { $0.text == "přidané v druhém" })

        let hunk = try #require(Policy.hunk(containing: line, in: file))

        #expect(hunk.newStart == 50)
        #expect(Policy.code(of: hunk).contains("druhý hunk"))
        #expect(!Policy.code(of: hunk).contains("první hunk"))
    }

    @Test("Řádek z cizího souboru žádný hunk nenajde")
    func findsNoHunkForAForeignLine() throws {
        let file = try file()
        let foreign = DiffLine(kind: .added, oldNumber: nil, newNumber: 999, text: "tohle tam není")

        #expect(Policy.hunk(containing: foreign, in: file) == nil)
    }

    private var twoHunks: String {
        [
            "diff --git a/a.php b/a.php",
            "--- a/a.php",
            "+++ b/a.php",
            "@@ -1,2 +1,2 @@",
            " první hunk",
            "+přidané v prvním",
            "@@ -50,2 +50,2 @@",
            " druhý hunk",
            "+přidané v druhém",
        ].joined(separator: "\n")
    }

    // MARK: - Který rozsah řádek pokrývá

    @Test("Řádek uvnitř rozsahu svůj rozsah najde")
    func findsTheRangeCoveringTheLine() throws {
        let file = try file()
        let comments = [comment(from: DraftAnchor.Endpoint(line: 10, side: .right), to: DraftAnchor.Endpoint(line: 13, side: .right))]
        let line = try #require(lines(of: file).first { $0.newNumber == 12 })

        let anchor = try #require(Policy.range(covering: line, in: comments, of: file))

        #expect(anchor.line == 13)
        #expect(anchor.start?.line == 10)
    }

    @Test("Řádek mimo rozsah žádný nenajde")
    func findsNoRangeOutsideIt() throws {
        let file = try file()
        let comments = [comment(from: DraftAnchor.Endpoint(line: 10, side: .right), to: DraftAnchor.Endpoint(line: 11, side: .right))]
        let line = try #require(lines(of: file).first { $0.newNumber == 13 })

        #expect(Policy.range(covering: line, in: comments, of: file) == nil)
    }

    /// Jednořádkový komentář se za rozsah **nepočítá** — „kopírovat rozsah“ by u něj neřeklo nic
    /// navíc proti „kopírovat řádek“ a v menu by stály dvě položky, které dělají totéž.
    @Test("Jednořádkový komentář rozsah nedělá")
    func ignoresASingleLineComment() throws {
        let file = try file()
        let comments = [comment(from: nil, to: DraftAnchor.Endpoint(line: 12, side: .right))]
        let line = try #require(lines(of: file).first { $0.newNumber == 12 })

        #expect(Policy.range(covering: line, in: comments, of: file) == nil)
    }

    /// Komentář **jiného souboru** se nesmí připlést: čísla řádků se mezi soubory překrývají,
    /// takže bez filtru by menu nabídlo kód, který s tímhle souborem nemá nic společného.
    @Test("Rozsah z jiného souboru se nepřiplete")
    func ignoresRangesFromOtherFiles() throws {
        let file = try file()
        let comments = [comment(
            path: "src/Jinde.php",
            from: DraftAnchor.Endpoint(line: 10, side: .right),
            to: DraftAnchor.Endpoint(line: 13, side: .right)
        )]
        let line = try #require(lines(of: file).first { $0.newNumber == 12 })

        #expect(Policy.range(covering: line, in: comments, of: file) == nil)
    }

    // MARK: - Co nabídne menu

    @Test("Běžný řádek nabídne kopírování řádku")
    func offersTheLineOnAnOrdinaryRow() throws {
        let file = try file()
        let line = try #require(lines(of: file).first { $0.newNumber == 12 })

        let targets = Policy.copyTargets(for: line, in: file, comments: [])

        #expect(targets.count == 1)
        #expect(targets[0].title == "Kopírovat řádek")
        #expect(targets[0].text == line.text)
    }

    /// Menu **říká, kolik řádků** rozsah má: rozsah nemusí být celý vidět, takže je to rozdíl
    /// mezi „to je ono“ a „to je něco jiného“. České tvary přes `Plural.czech`, jako všude jinde.
    @Test("Řádek v rozsahu nabídne obojí a řekne kolik")
    func offersTheRangeWithItsSize() throws {
        let file = try file()
        let comments = [comment(from: DraftAnchor.Endpoint(line: 10, side: .right), to: DraftAnchor.Endpoint(line: 13, side: .right))]
        let line = try #require(lines(of: file).first { $0.newNumber == 12 })

        let targets = Policy.copyTargets(for: line, in: file, comments: comments)

        #expect(targets.count == 2)
        #expect(targets[0].id == "line")
        #expect(targets[1].id == "range")
        // Čtyři řádky: nové 10 a 13 jsou kontext, 11 a 12 přidané. Odebraný `return $this->sum;`
        // se nepočítá — v nové verzi není. (První verze testu čekala tři a spadla; přepočítáno
        // proti diffu, ne proti dojmu.)
        #expect(targets[1].title == "Kopírovat rozsah (4 řádky)")
    }

    /// Český tvar u jednoho řádku — `1 řádků` praští do očí a tvary se v okně rozlišují na víc
    /// místech, takže musí jít přes `Plural.czech` jako všude.
    @Test("Jednořádkový rozsah má tvar „1 řádek“")
    func usesTheSingularForm() throws {
        let file = try file()
        let comments = [comment(
            from: DraftAnchor.Endpoint(line: 13, side: .right),
            to: DraftAnchor.Endpoint(line: 13, side: .right)
        )]
        let line = try #require(lines(of: file).first { $0.newNumber == 13 })

        let targets = Policy.copyTargets(for: line, in: file, comments: comments)

        #expect(targets.last?.title == "Kopírovat rozsah (1 řádek)")
    }

    @Test("Pětiřádkový rozsah má správný český tvar")
    func usesCzechPluralForms() throws {
        let file = try file()
        let comments = [comment(from: DraftAnchor.Endpoint(line: 10, side: .left), to: DraftAnchor.Endpoint(line: 13, side: .right))]
        let line = try #require(lines(of: file).first { $0.newNumber == 12 })

        let targets = Policy.copyTargets(for: line, in: file, comments: comments)

        // Rozsah přes obě strany dá novou verzi. Začátek je **starý** řádek 10, tedy
        // `public function total()`, takže vyjdou tytéž čtyři řádky nové verze.
        #expect(targets.last?.title == "Kopírovat rozsah (4 řádky)")
    }

    /// Počet v popisku nad souborem s **`CRLF`** (#295). Do #295 se počítal
    /// `split(separator: "\n")` nad hotovým textem — a protože `"\r\n"` je ve Swiftu jeden
    /// `Character`, vyšel by nad rozsahem z takového souboru **„1 řádek“** bez ohledu na to,
    /// kolik jich tam je. Dvojí pojistka: parser `CR` sundá a počet jde přes `TextLines`.
    @Test("Rozsah v souboru s CRLF řekne správný počet")
    func countsTheRangeInACRLFFile() throws {
        let path = "src/App.cs"
        let diff = DiffParser.parse(
            "diff --git a/\(path) b/\(path)\r\n"
                + "--- a/\(path)\r\n"
                + "+++ b/\(path)\r\n"
                + "@@ -10,3 +10,4 @@ class App\r\n"
                + "     public int Total()\r\n"
                + "-        return sum;\r\n"
                + "+        return sum + tax;\r\n"
                + "+    }\r\n"
                + "     // konec\r\n"
        )
        let file = try #require(diff.files.first)
        let comments = [comment(
            path: path,
            from: DraftAnchor.Endpoint(line: 10, side: .right),
            to: DraftAnchor.Endpoint(line: 13, side: .right)
        )]
        let line = try #require(file.hunks.flatMap(\.lines).first { $0.newNumber == 12 })

        let targets = Policy.copyTargets(for: line, in: file, comments: comments)

        #expect(targets.last?.title == "Kopírovat rozsah (4 řádky)")
        // A do schránky jde kód **bez `CR`** — rozhodnutí #295, zapsané u `Policy.code(of:)`:
        // kopie nese `LF`, protože jde do terminálu nebo do komentáře jako kód.
        let text = try #require(targets.last?.text)
        #expect(!text.unicodeScalars.contains("\r"))
        #expect(TextLines.all(text).count == 4)
    }

    /// Nad poznámkou `git`u se menu **nekreslí vůbec** — není to obsah souboru, takže by
    /// „Kopírovat řádek“ dalo do schránky text, který v kódu není.
    @Test("Poznámka gitu nenabídne nic")
    func offersNothingOnAGitNote() throws {
        let file = try file()
        let note = DiffLine(kind: .meta, oldNumber: nil, newNumber: nil, text: "No newline at end of file")

        #expect(Policy.copyTargets(for: note, in: file, comments: []).isEmpty)
    }

    // MARK: - Kopírování nezakládá komentář

    /// **Nejcennější tvrzení téhle sady: kopírováním nevzniká komentář.** Dnešní tažení otevře
    /// editor, takže kdo chtěl jen kód, musel po sobě uklízet rozdělaný komentář. Skládání textu
    /// je čistá funkce nad diffem — nemá čím do draftu sáhnout — a menu je na pravém kliknutí,
    /// které nic nezakládá. Test to drží proti tomu, aby se to jednou „zjednodušilo“ tak, že by
    /// kopírování šlo přes stejnou cestu jako komentování.
    @Test("Kopírování se draftu ani nedotkne")
    func neverTouchesTheDraft() throws {
        let file = try file()
        let comments = [comment(from: DraftAnchor.Endpoint(line: 10, side: .right), to: DraftAnchor.Endpoint(line: 13, side: .right))]
        let line = try #require(lines(of: file).first { $0.newNumber == 12 })

        let targets = Policy.copyTargets(for: line, in: file, comments: comments)
        _ = targets.map(\.text)

        // Seznam komentářů je hodnotový typ a zůstal, jak byl — žádná položka nepřibyla.
        #expect(comments.count == 1)
        #expect(comments[0].body.isEmpty)
    }
}
