import Foundation
import Testing

@testable import PRism

/// Materiál a prompt rozhovoru (#452).
///
/// Co se tady hlídá především, je **že žádná sekce nezmizí mlčky**. Materiál je jediné, co
/// session o PR ví mimo kód — a chybějící sekce je mezera, kterou si model doplní domněnkou,
/// kdežto věta „nálezy nejsou“ je informace.
@Suite("Materiál a prompt rozhovoru (#452)")
struct AskPromptTests {
    private static let pr = PRIdentifier(repo: RepoID("keboola/vault")!, number: 85)

    private static func finding(
        summary: String = "zámek je kolem celého fetch",
        file: String? = "src/SecretClient.php",
        line: Int? = 80,
        category: String? = "correctness",
        scenario: String? = nil
    ) -> Finding {
        Finding(
            reported: ReportedFinding(
                file: file,
                line: line,
                category: category,
                verdict: .confirmed,
                shortSummary: nil,
                summary: summary,
                failureScenario: scenario
            ),
            reviewer: "php-review",
            headSha: "abc123"
        )
    }

    // MARK: - Materiál

    /// Prázdný materiál dá **celý soubor**, ne nic: sekce jsou odpovědi i tehdy, když jsou
    /// prázdné.
    @Test("Sekce jsou v souboru vždycky, i když je v nich prázdno")
    func everySectionIsAlwaysThere() {
        let brief = Policy.askBrief(of: Self.pr, material: AskMaterial())

        for heading in [
            "## Pull request", "## Description", "## What PRism's reviewers reported",
            "## GitHub conversation", "## CI checks",
        ] {
            #expect(brief.contains(heading), "chybí sekce \(heading)")
        }
        #expect(brief.contains(AskMaterialText.noDescription))
        #expect(brief.contains(AskMaterialText.noFindings))
        #expect(brief.contains(AskMaterialText.noConversation))
        #expect(brief.contains(AskMaterialText.noChecks))
        // Preambule říká, že je to materiál, ne pokyn — obsah je cizí text.
        #expect(brief.contains(AskMaterialText.preamble))
        #expect(brief.hasSuffix("\n"))
    }

    /// **Prázdný popis a nedotažený popis se nedají odlišit**, a věta to říká — tatáž úvaha
    /// jako u zadání pro reviewera (#120).
    @Test("Chybějící popis dostane větu, která netvrdí, čí je to chyba")
    func missingDescriptionIsHonest() {
        let brief = Policy.askBrief(of: Self.pr, material: AskMaterial(description: "   "))

        #expect(brief.contains(AskMaterialText.noDescription))
    }

    /// Blokující nález se pozná **v textu**, ne pořadím: session z pořadí nic nepozná.
    @Test("U blokujícího nálezu stojí, že blokuje")
    func blockingFindingsSayThat() {
        let brief = Policy.askBrief(
            of: Self.pr,
            material: AskMaterial(
                findings: [Self.finding(), Self.finding(summary: "styl", category: "style")],
                blockingCategories: ["correctness"]
            )
        )

        #expect(brief.contains("[correctness, blocking, by php-review, src/SecretClient.php:80]"))
        #expect(brief.contains("[style, by php-review, src/SecretClient.php:80]"))
    }

    /// Nález se sráží na řádek (`singleLine`) — víceřádkové shrnutí by v odrážkovém seznamu
    /// rozbilo, kde jeden nález končí a druhý začíná.
    @Test("Nález je jeden řádek, i když ho reviewer napsal na tři")
    func findingsAreOneLine() {
        let brief = Policy.askBrief(
            of: Self.pr,
            material: AskMaterial(findings: [Self.finding(summary: "první\ndruhý\r\ntřetí")])
        )

        #expect(brief.contains("první druhý třetí"))
    }

    /// **Zkrácená konverzace se přiznává.** Session, která z neúplné diskuze usoudí, že se nikdo
    /// neozval, odpoví přesvědčivě a špatně.
    @Test("Zkrácená konverzace to v materiálu říká")
    func truncatedConversationSaysSo() {
        let conversation = Conversation(
            viewer: "ondra",
            reviews: ConversationPage(items: [], total: 0, hasNextPage: false),
            threads: ConversationPage(items: [], total: 0, hasNextPage: false),
            comments: ConversationPage(
                items: [
                    ThreadComment(
                        id: "c1",
                        author: "kolega",
                        body: "tohle mi nesedí",
                        createdAt: Date(timeIntervalSince1970: 0),
                        url: URL(string: "https://github.com/x")!,
                        replyToID: nil
                    ),
                ],
                total: 40,
                hasNextPage: true
            )
        )
        let brief = Policy.askBrief(of: Self.pr, material: AskMaterial(conversation: conversation))

        #expect(brief.contains(AskMaterialText.truncatedConversation))
        #expect(brief.contains("- kolega: tohle mi nesedí"))
    }

    /// Načtená, ale prázdná konverzace se od nenačtené liší — jinak by „nikdo nic nenapsal“
    /// platilo i po výpadku sítě.
    @Test("Prázdná načtená konverzace není totéž co nenačtená")
    func emptyIsNotUnloaded() {
        let empty = Conversation(
            viewer: "ondra",
            reviews: ConversationPage(items: [], total: 0, hasNextPage: false),
            threads: ConversationPage(items: [], total: 0, hasNextPage: false),
            comments: ConversationPage(items: [], total: 0, hasNextPage: false)
        )
        let brief = Policy.askBrief(of: Self.pr, material: AskMaterial(conversation: empty))

        #expect(brief.contains(AskMaterialText.emptyConversation))
        #expect(!brief.contains(AskMaterialText.noConversation))
    }

    /// **Diff v materiálu není, a je to schválně**: session stojí v pracovním stromě a má
    /// `Bash(git:*)`, takže si ho přečte `git diff base...HEAD`.
    @Test("Materiál neobsahuje diff, jen commit, proti kterému se diffuje")
    func theDiffIsNotInTheFile() {
        let brief = Policy.askBrief(of: Self.pr, material: AskMaterial(baseSha: "def456"))

        #expect(brief.contains("- Base commit: def456"))
        #expect(!brief.contains("@@"))
        #expect(!brief.contains("diff --git"))
    }

    // MARK: - Prompt

    /// **Cesta k materiálu je v promptu vždycky**, i u navazující otázky — a je to oprava první
    /// podoby #452, kde byla jen v té první. Pruh `ví o tomhle PR:` se počítá **živě**, takže by
    /// nad navazující otázkou tvrdil `3 nálezy` o session, která o nich neslyšela.
    ///
    /// Liší se **úvodní věta**: navazující otázka říká, že je soubor čerstvý, ne že ho session
    /// vidí poprvé. `nil` znamená, že se materiál **nepodařilo uložit** — prompt pak na žádný
    /// soubor neukazuje (#120).
    @Test("Cesta k materiálu je v obou otázkách, liší se úvodní věta")
    func contextGoesIntoEveryQuestion() {
        let file = URL(filePath: "/cache/worktrees/o/r/85-ask.md")
        let first = Policy.askPrompt(question: "proč?", contextFile: file, baseSha: "def456")
        let next = Policy.askPrompt(
            question: "a co timeout?",
            contextFile: file,
            baseSha: "def456",
            isFollowUp: true
        )

        #expect(first.contains(file.path))
        #expect(first.contains("git diff def456...HEAD"))
        #expect(!first.contains("have been refreshed"))

        #expect(next.contains(file.path))
        #expect(next.contains("have been refreshed"))
        #expect(next.contains("git diff def456...HEAD"))

        // Bez souboru se na žádný neodkazuje ani jedna podoba.
        for isFollowUp in [false, true] {
            let without = Policy.askPrompt(
                question: "x",
                contextFile: nil,
                baseSha: "def456",
                isFollowUp: isFollowUp
            )
            #expect(!without.contains("85-ask.md"))
        }
    }

    /// **Kontrakt session je v promptu vždycky**, i u navazující otázky: model si po deseti kolech
    /// nemá pamatovat, že nesmí zapisovat. Držet to doopravdy je práce `--disallowedTools`; tahle
    /// věta je pojistka, ne brána.
    @Test("Zákaz zápisu a odesílání je v promptu i u navazující otázky")
    func theContractIsAlwaysThere() {
        for contextFile in [URL(filePath: "/x/85-ask.md"), nil] {
            let prompt = Policy.askPrompt(question: "proč?", contextFile: contextFile, baseSha: "a")
            #expect(prompt.contains("Read only."))
            #expect(prompt.contains("no `gh` commands"))
            #expect(prompt.contains("The question is: proč?"))
        }
    }

    /// Prompt si říká o **tvar odkazu**, podle kterého se pak hledají místa v kódu
    /// (`Policy.askReferences`). Dvě formulace téhož by se rozešly a kapsle pod bublinou by
    /// přestaly vznikat.
    @Test("Prompt si říká o tvar path:line, který okno umí přečíst")
    func promptAsksForTheReferenceShape() {
        let prompt = Policy.askPrompt(question: "x", contextFile: nil, baseSha: "a")

        #expect(prompt.contains("path/to/file.swift:80"))
        #expect(Policy.askReferences(in: "je to v path/to/file.swift:80")
            == [AskReference(file: "path/to/file.swift", line: 80)])
    }
}
