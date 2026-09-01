import Foundation
import Testing

@testable import PRism

/// Jak se volá session, která slévá konflikty (#467), a jak se čte její účet.
///
/// Sady povolení tvrdí **`SessionToolSetsTests`** — všechny čtyři na jednom místě, aby se z nich
/// dalo přečíst, čím se od sebe liší. Tady je zbytek kontraktu s CLI a rozbor odpovědi.
@Suite("Příkaz pro slévání konfliktů")
struct ConflictCommandTests {
    private let worktree = URL(filePath: "/cache/PRism/repos/o-r/42-sync")

    // MARK: - Tvar volání

    @Test("Prompt jde za -p, stream se čte průběžně")
    func passesThePromptAndStreams() {
        let arguments = ConflictCommand.arguments(prompt: "slij to", worktree: worktree)

        #expect(arguments.first == "-p")
        #expect(arguments.dropFirst().first == "slij to")
        #expect(value(of: "--output-format", in: arguments) == "stream-json")
        #expect(arguments.contains("--verbose"))
    }

    /// **`--resume` tu není, a je to rozhodnutí, ne opomenutí**: každé kolo je jiný commit a jiný
    /// konflikt, takže navázaný kontext by byl kontext o souborech, které se mezitím commitly.
    @Test("Kola nenavazují na sebe")
    func doesNotResumePreviousRounds() {
        #expect(!ConflictCommand.arguments(prompt: "x", worktree: worktree).contains("--resume"))
    }

    /// Model z konfigurace, jako u rozhovoru — slití cizího kódu je úvaha, ne mechanický převod.
    @Test("Model se posílá jen když je vybraný")
    func passesTheModelOnlyWhenChosen() {
        #expect(!ConflictCommand.arguments(prompt: "x", worktree: worktree, model: nil).contains("--model"))
        #expect(!ConflictCommand.arguments(prompt: "x", worktree: worktree, model: "").contains("--model"))
        #expect(
            value(
                of: "--model",
                in: ConflictCommand.arguments(prompt: "x", worktree: worktree, model: "opus")
            ) == "opus"
        )
    }

    /// **Rozsah je ten strom, který dostal request**, ne konstanta: dva pull requesty mají dva
    /// různé stromy a povolení psát do cizího by znamenalo, že session sáhne na rebase jiného PR.
    @Test("Rozsah zápisu je strom z requestu")
    func scopesWritesToTheGivenWorktree() {
        let other = URL(filePath: "/cache/PRism/repos/o-r/7-sync")

        #expect(ConflictCommand.allowedTools(in: worktree).contains("/42-sync/**"))
        #expect(!ConflictCommand.allowedTools(in: worktree).contains("/7-sync/**"))
        #expect(ConflictCommand.allowedTools(in: other).contains("/7-sync/**"))
    }

    @Test("Limit kola je deset minut")
    func timeoutIsTenMinutes() {
        #expect(ConflictCommand.timeout == .seconds(600))
    }

    // MARK: - Zápis mimo strom

    /// **Druhá vrstva té meze**, na které #467 stojí. Bránou je scoped `--allowedTools` (změřeno);
    /// tohle je čtení z toho, co session doopravdy zkoušela.
    @Test("Zápis mimo strom se najde, uvnitř ne")
    func findsWritesOutsideTheWorktree() {
        let tools = [
            attempt("Edit", "/cache/PRism/repos/o-r/42-sync/src/App.php"),
            attempt("Write", "/Users/ondra/Projects/vault/src/App.php"),
            attempt("Read", "/etc/hosts"),
        ]

        #expect(
            ConflictCommand.writesOutside(tools, worktree: worktree)
                == ["/Users/ondra/Projects/vault/src/App.php"]
        )
    }

    /// **Počítají se i odmítnuté pokusy**, a je to schválně: otázka není „povedlo se to“, ale
    /// „mířila session mimo strom“. Odmítnutý pokus je odpověď „brána drží“ — a pořád důvod
    /// nepokračovat bez člověka.
    @Test("Odmítnutý pokus se počítá taky")
    func countsDeniedAttempts() {
        let denied = ToolAttempt(
            name: "Write",
            detail: "/tmp/x.txt",
            id: "1",
            outcome: .init(kind: .denied)
        )

        #expect(ConflictCommand.writesOutside([denied], worktree: worktree) == ["/tmp/x.txt"])
    }

    /// **`..` se normalizuje**, jinak by kontrola vypadala jako kontrola a nebyla jí: cesta
    /// `<strom>/../jinam` má prefix stromu, ale míří ven.
    @Test("Cesta s .. se normalizuje před srovnáním")
    func normalizesDotDot() {
        let sneaky = attempt("Write", "/cache/PRism/repos/o-r/42-sync/../7-sync/x.php")

        #expect(
            ConflictCommand.writesOutside([sneaky], worktree: worktree)
                == ["/cache/PRism/repos/o-r/7-sync/x.php"]
        )
    }

    /// **Soubor se stejným prefixem, ale jiný strom, je „mimo“.** `42-sync-old` začíná na
    /// `42-sync` — bez lomítka v porovnání by prošel jako vnitřní.
    @Test("Sousední strom se stejným prefixem je mimo")
    func siblingWithTheSamePrefixIsOutside() {
        let sibling = attempt("Write", "/cache/PRism/repos/o-r/42-sync-old/x.php")

        #expect(ConflictCommand.writesOutside([sibling], worktree: worktree) == [sibling.detail])
    }

    /// Volání bez cesty **není pokus o zápis ven**: nedá se z něj tvrdit ani „mimo“, ani „uvnitř“,
    /// a vymyslet si cestu nesmíme. Je to vada streamu, ne prolomená brána.
    @Test("Zápis bez cesty se nepočítá")
    func ignoresAttemptsWithoutAPath() {
        #expect(ConflictCommand.writesOutside([attempt("Write", nil)], worktree: worktree).isEmpty)
    }

    @Test("Tentýž soubor se vypíše jednou")
    func deduplicatesPaths() {
        let twice = [attempt("Write", "/tmp/x"), attempt("Edit", "/tmp/x")]

        #expect(ConflictCommand.writesOutside(twice, worktree: worktree) == ["/tmp/x"])
    }

    // MARK: - Účet session

    @Test("Účet se přečte i s větou navíc a v code fence")
    func parsesTheAccountDefensively() {
        let text = """
            Hotovo, tady je výsledek:
            ```json
            {"files": [{"path": "a.php", "action": "both"},
                       {"path": "b.php", "action": "manual"}],
             "caveats": "U b.php si nejsem jistý pořadím."}
            ```
            """

        let parsed = ConflictCommand.parse(text)

        #expect(parsed.files == [
            ResolvedConflictFile(path: "a.php", action: .tookBoth),
            ResolvedConflictFile(path: "b.php", action: .manual),
        ])
        #expect(parsed.caveats == "U b.php si nejsem jistý pořadím.")
    }

    /// **Nepřečtený účet není zahozená práce**: rozhodnutí pokračovat drží `git`, ne tenhle rozbor.
    /// Prázdný výčet znamená „session o souborech neřekla nic“ a `Policy.resolvedFiles` je doplní.
    @Test("Nesmysl místo JSONu vydá prázdný účet, ne pád")
    func survivesGarbage() {
        #expect(ConflictCommand.parse("nevím, nešlo to").files.isEmpty)
        #expect(ConflictCommand.parse(nil).files.isEmpty)
        #expect(ConflictCommand.parse("{}").files.isEmpty)
        #expect(ConflictCommand.parse("{").caveats == nil)
    }

    /// **Neznámé slovo je `manual`, ne `unchanged`.** Session, která soubor sáhla a popsala to
    /// jinak, než jsme čekali, ho **změnila** — a `beze změny` by o něm tvrdilo opak.
    @Test("Neznámá akce se čte jako ruční slití")
    func unknownActionIsManual() {
        #expect(ConflictCommand.parse(#"{"files":[{"path":"a","action":"wat"}]}"#).files.first?.action == .manual)
        #expect(ConflictCommand.parse(#"{"files":[{"path":"a"}]}"#).files.first?.action == .manual)
        #expect(ConflictCommand.parse(#"{"files":[{"path":"a","action":"unchanged"}]}"#).files.first?.action == .unchanged)
        #expect(ConflictCommand.parse(#"{"files":[{"path":"a","action":"unresolved"}]}"#).files.first?.action == .unresolved)
    }

    /// **Cizí text se sráží na jeden řádek** — víceřádkové `caveats` by v panelu i v sheetu
    /// rozhodily řádkování (pravidlo o cizím textu).
    @Test("Caveats se srazí na řádek a prázdné zmizí")
    func squashesCaveats() {
        #expect(ConflictCommand.parse(#"{"caveats":"a\nb"}"#).caveats == "a b")
        #expect(ConflictCommand.parse(#"{"caveats":"   "}"#).caveats == nil)
    }

    @Test("Tentýž soubor v účtu se počítá jednou")
    func deduplicatesClaimedFiles() {
        let parsed = ConflictCommand.parse(
            #"{"files":[{"path":"a","action":"both"},{"path":"a","action":"unchanged"}]}"#
        )

        #expect(parsed.files == [ResolvedConflictFile(path: "a", action: .tookBoth)])
    }

    // MARK: - Prompt

    /// **Kolidující soubory musí být v promptu vypsané**: session nemá `Bash`, takže si je
    /// `git diff --diff-filter=U` zjistit nemůže.
    @Test("Prompt vypíše soubory, základ a zákazy")
    func promptNamesTheFilesAndTheRules() {
        let prompt = Policy.conflictPrompt(files: ["a.php", "b/c.php"], base: "master")

        #expect(prompt.contains("- a.php"))
        #expect(prompt.contains("- b/c.php"))
        #expect(prompt.contains("master"))
        #expect(prompt.contains("do not commit"))
        #expect(prompt.contains("unresolved"))
        // Že je `HEAD` při rebase **základ**, ne moje práce — model, který si to splete, zahodí
        // zrovna tu práci, o kterou jde.
        #expect(prompt.contains("<<<<<<< HEAD"))
    }

    private func attempt(_ name: String, _ path: String?) -> ToolAttempt {
        ToolAttempt(name: name, detail: path, id: "x", outcome: .init(kind: .passed))
    }

    private func value(of flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else {
            return nil
        }
        return arguments[index + 1]
    }
}
