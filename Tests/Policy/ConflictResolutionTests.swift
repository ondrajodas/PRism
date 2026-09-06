import Foundation
import Testing

@testable import PRism

/// Jak se z účtu session a z toho, co řekl `git`, skládá výpis v okně (#467).
///
/// **Je to `Policy`, takže výčtem a bez mockování** — a zrovna tady na tom záleží: rozhodnutí „co
/// je účet session a co doklad z `gitu`“ je celý smysl toho výpisu.
@Suite("Výsledek slévání konfliktů")
struct ConflictResolutionTests {
    // MARK: - Účet session proti seznamu z gitu

    /// **Rozsah a pořadí drží `git`, popisky session.** Kdyby výpis vznikal z odpovědi modelu,
    /// mohl by o kolidujícím souboru mlčet — a ten by se pak čtl jako vyřešený.
    @Test("Pořadí a rozsah výpisu drží git, ne session")
    func gitDecidesWhichFilesAreListed() {
        let rows = Policy.resolvedFiles(
            conflicted: ["a.php", "b.php", "c.php"],
            claimed: [
                ResolvedConflictFile(path: "c.php", action: .tookBoth),
                ResolvedConflictFile(path: "a.php", action: .manual),
                // Soubor, který **nekolidoval** — session si ho vymyslela. Do výpisu nepatří.
                ResolvedConflictFile(path: "vymysleny.php", action: .manual),
            ]
        )

        #expect(rows.map(\.path) == ["a.php", "b.php", "c.php"])
        #expect(rows.map(\.action) == [.manual, .unchanged, .tookBoth])
    }

    /// **Soubor, o kterém session mlčí, je `unchanged`, ne chybějící řádek.** Chybějící řádek by se
    /// čtl jako „tenhle soubor nekolidoval“.
    @Test("Soubor, o kterém session mlčí, je beze změny")
    func silenceMeansUnchanged() {
        let rows = Policy.resolvedFiles(conflicted: ["a.php"], claimed: [])

        #expect(rows == [ResolvedConflictFile(path: "a.php", action: .unchanged)])
    }

    /// **Měření přebíjí tvrzení.** Soubor, ve kterém `git` pořád vidí konflikt, je `unresolved`,
    /// i kdyby session tvrdila „ruční slití“ — to je zrovna ten druh textu, který tvrdí víc, než
    /// data unesou.
    @Test("Značky v souboru přebijí, co o něm session tvrdí")
    func measurementBeatsTheClaim() {
        let rows = Policy.resolvedFiles(
            conflicted: ["a.php", "b.php"],
            claimed: [
                ResolvedConflictFile(path: "a.php", action: .manual),
                ResolvedConflictFile(path: "b.php", action: .tookBoth),
            ],
            unresolvedPaths: ["b.php"]
        )

        #expect(rows.map(\.action) == [.manual, .unresolved])
        #expect(rows.last?.action.isResolved == false)
    }

    @Test("Popisky jsou ty z návrhu")
    func labelsMatchTheDesign() {
        #expect(ResolvedConflictFile.Action.tookBoth.czechLabel == "vzala obojí")
        #expect(ResolvedConflictFile.Action.manual.czechLabel == "ruční slití")
        #expect(ResolvedConflictFile.Action.unchanged.czechLabel == "beze změny")
        #expect(ResolvedConflictFile.Action.unresolved.czechLabel == "nevyřešeno")
        // **Dvě různé otázky, ne jedna.** `beze změny` se dá commitnout (`isResolved`), ale
        // session na ten soubor **nesáhla** (`isTouched`) — a `✓` u něj by tvrdilo, že za to slití
        // někdo ručí. Návrh tam kreslí `—`.
        #expect(ResolvedConflictFile.Action.unchanged.isResolved)
        #expect(!ResolvedConflictFile.Action.unchanged.isTouched)
        #expect(!ResolvedConflictFile.Action.unresolved.isResolved)
        #expect(!ResolvedConflictFile.Action.unresolved.isTouched)
        #expect(ResolvedConflictFile.Action.tookBoth.isTouched)
        #expect(ResolvedConflictFile.Action.manual.isTouched)
    }

    // MARK: - Diff v potvrzení

    /// **Strop je podmínka, ne úklid**: pod diffem stojí výstraha o lease a neomezený výpis by ji
    /// odrolil pod hranu.
    @Test("Diff má strop a zbytek se počítá")
    func capsTheDiffAndCountsTheRest() {
        let diff = (1...60).map { "+ radek \($0)" }.joined(separator: "\n")

        let lines = Policy.conflictDiffLines(diff)

        #expect(lines.shown.count == Policy.conflictDiffLineLimit)
        #expect(lines.hidden == 60 - Policy.conflictDiffLineLimit)
        #expect(lines.shown.first?.text == "+ radek 1")
        // Identita je **index**, ne text: řádky diffu se legitimně opakují (prázdné, `}`).
        #expect(lines.shown.map(\.id) == Array(0..<Policy.conflictDiffLineLimit))
    }

    /// **Diff, který se vejde celý, nesmí hlásit „a další 1 řádek“.** `git diff` končí `\n`, takže
    /// bez odečtení posledního prázdného řádku by to tvrdil vždycky.
    @Test("Koncový nový řádek se nepočítá")
    func trailingNewlineIsNotALine() {
        let lines = Policy.conflictDiffLines("+ a\n- b\n")

        #expect(lines.shown.count == 2)
        #expect(lines.hidden == 0)
    }

    /// **Hlavička se od přidaného řádku musí odlišit**, jinak by `+++ b/soubor` svítilo zeleně
    /// jako přidaný kód a `--- a/soubor` červeně jako smazaný.
    @Test("Hlavička diffu není přidaný ani smazaný řádek")
    func headerIsNotAnAddedLine() {
        let diff = """
            diff --git a/a.php b/a.php
            index 111..222 100644
            --- a/a.php
            +++ b/a.php
            @@ -1,3 +1,3 @@
             kontext
            -stare
            +nove
            """

        let kinds = Policy.conflictDiffLines(diff).shown.map(\.kind)

        #expect(kinds == [.header, .header, .header, .header, .hunk, .context, .removed, .added])
    }

    @Test("Prázdný diff nevydá žádný řádek")
    func emptyDiffHasNoLines() {
        #expect(Policy.conflictDiffLines("").shown.isEmpty)
        #expect(Policy.conflictDiffLines("").hidden == 0)
    }

    // MARK: - Věty

    @Test("Nadpis sheetu počítá vyřešené konflikty")
    func sheetTitleCountsResolvedConflicts() {
        #expect(Policy.conflictSheetTitle(base: "main", resolved: 1) == "Srovnáno s main — 1 konflikt vyřešen")
        #expect(Policy.conflictSheetTitle(base: "main", resolved: 2) == "Srovnáno s main — 2 konflikty vyřešeny")
        #expect(Policy.conflictSheetTitle(base: "main", resolved: 5) == "Srovnáno s main — 5 konfliktů vyřešeno")
        // Nula = nebylo co řešit, tak se o tom nemluví.
        #expect(Policy.conflictSheetTitle(base: "main", resolved: 0) == "Srovnáno s main")
        // **Prázdný základ se nesází jako mezera** — nadpis potvrzení nevratné akce nemá o sobě
        // říkat, že mu něco chybí.
        #expect(Policy.conflictSheetTitle(base: "", resolved: 2) == "Srovnáno se základem — 2 konflikty vyřešeny")
    }

    /// **Kolo i počet souborů ve větě**, protože desetiminutové ticho nad „Slévám konflikty“ je
    /// k nerozeznání od zaseknutého okna.
    @Test("Věta o běžícím slévání nese kolo i počet souborů")
    func activitySentenceCarriesRoundAndCount() {
        let sentence = Policy.conflictActivity(round: 2, files: ["a.php", "b.php"])

        #expect(sentence == "Slévám konflikty ve 2 souborech (kolo 2 z 3).")
    }

    @Test("Řádek o kroku session rozlišuje čtení a psaní")
    func toolActivityNamesWritesSeparately() {
        let worktree = URL(filePath: "/cache/x")
        func line(_ name: String, _ detail: String) -> String {
            Policy.writingToolActivity(
                of: ToolAttempt(name: name, detail: detail, id: "1"),
                inside: worktree
            )
        }

        #expect(line("Write", "/cache/x/a.php") == "přepisuje a.php")
        #expect(line("Edit", "/cache/x/a.php") == "upravuje a.php")
        #expect(line("Read", "/cache/x/a.php") == "čte a.php")
        #expect(line("Neznamy", "/cache/x/a.php") == "pracuje…")
    }

    /// **Věta o zápisu mimo strom musí říct i to, co z toho plyne** — jinak vypadá jako spadlá
    /// session, a přitom je to jediný stav, ve kterém aplikace odmítla přijmout hotovou práci.
    @Test("Věta o zápisu mimo strom říká, že se výsledek nepřijal")
    func writesOutsideSentenceExplainsTheConsequence() {
        let sentence = Policy.writesOutsideWorktree(["/tmp/a", "/tmp/b", "/tmp/c"])

        #expect(sentence.contains("/tmp/a, /tmp/b"))
        #expect(sentence.contains("a 1 další"))
        #expect(sentence.contains("nepřijal"))
        #expect(sentence.contains("terminálu"))
    }

    // MARK: - Součet útraty za kola

    /// **`nil` je „nevíme“, ne nula.** Kolo, které cenu nenahlásilo, se nesmí započítat jako
    /// zdarma — je to tatáž úvaha, kvůli které jsou ta pole volitelná.
    @Test("Součet útraty sčítá jen to, co víme")
    func sumsOnlyKnownUsage() {
        #expect(RunUsage.summed(nil, nil) == nil)
        #expect(RunUsage.summed(RunUsage(cost: 1), nil) == RunUsage(cost: 1))
        #expect(RunUsage.summed(nil, RunUsage(cost: 2)) == RunUsage(cost: 2))
        #expect(
            RunUsage.summed(RunUsage(cost: 1, turns: 3), RunUsage(cost: 2, turns: 4))
                == RunUsage(cost: 3, turns: 7)
        )
        // Jedna známá a jedna neznámá složka: známá **zůstane**, ne že se zahodí kvůli druhé.
        #expect(
            RunUsage.summed(RunUsage(cost: 1), RunUsage(turns: 2)) == RunUsage(cost: 1, turns: 2)
        )
    }

    /// Strop kol je proti **účtu**, ne proti zacyklení — každé kolo je vlastní session.
    @Test("Kol je nejvýš tři")
    func roundsAreCapped() {
        #expect(Policy.maxConflictRounds == 3)
    }
}
