import Foundation
import Testing

@testable import PRism

/// **Všechny čtyři sady povolení na jednom místě** (zadání #467).
///
/// Do #467 se každá sada tvrdila u svého příkazu (`ClaudeCommandTests`, `IntentTextCommandTests`,
/// `AskCommandTests`) a čtvrtá k nim přibyla. Čtyři sady znamenají **čtyři místa, kde se dá tvrdá
/// podmínka č. 2 porušit**, a rozeseté po čtyřech souborech se z nich nedá přečíst, čím se od sebe
/// liší — a právě rozdíly jsou to, co se u nich hlídá.
///
/// **Tvrdí se literálem, ne proti konstantě**, jako u #345 a #452: `#expect(x == Command.tools)`
/// by neznamenalo nic, protože po rozšíření konstanty by prošlo dál. Cena je, že se test musí
/// změnit vědomě — a to je celý smysl.
@Suite("Sady povolení všech session")
struct SessionToolSetsTests {
    /// Strom, na který se omezuje zápis u čtvrté session. Pevná cesta, ne z `CacheLayout`:
    /// tvrzení je o **tvaru** pravidla, ne o tom, kde ta cache dneska je.
    private let worktree = URL(filePath: "/cache/PRism/repos/o-r/42-sync")

    // MARK: - Čtyři sady, čtyři literály

    /// **1. Reviewer** (tvrdá podmínka č. 2): čte kód, hlásí nálezy, načte skill. Žádný `Write`
    /// ani `Edit`, u `Bash` jen `git`.
    @Test("Reviewer čte a hlásí, nepíše")
    func reviewerToolSet() {
        #expect(ClaudeCommand.allowedTools == "Read,Grep,Glob,Bash(git:*),ReportFindings,Skill")
    }

    /// **2. Dotažení textu issue** (#345): `ToolSearch` a jeden čtecí MCP nástroj z konfigurace.
    /// `ToolSearch` v ní být **musí** — bez něj se MCP nástroj nedá zavolat.
    @Test("Dotažení textu issue má ToolSearch a jeden MCP nástroj")
    func intentTextToolSet() {
        let allowed = Self.value(
            of: "--allowedTools",
            in: IntentTextCommand.arguments(prompt: "x", tool: "mcp__linear__get_issue")
        )

        #expect(allowed == "ToolSearch,mcp__linear__get_issue")
    }

    /// **3. Rozhovor nad PR** (#452): užší než reviewer — bez `ReportFindings` (nemá co hlásit)
    /// a bez `Skill` (skill načtený za běhu si umí říct o odeslání na GitHub).
    @Test("Rozhovor nad PR jen čte")
    func askToolSet() {
        #expect(AskCommand.allowedTools == "Read,Grep,Glob,Bash(git:*)")
    }

    /// **4. Slévání konfliktů** (#467) — **jediná, která smí psát**, a přesto ta nejužší v jedné
    /// věci: **`Bash` v ní není vůbec**.
    ///
    /// **Jeden literál, tři meze** — a všechny tři jsou v něm vidět naráz, proto se tvrdí celý
    /// řetězec a ne jeho části:
    ///
    /// - `Write` a `Edit` **s vypsaným rozsahem**, ne holým jménem. Holé `Write` píše kamkoli
    ///   (změřeno, `docs/claude-cli.md`), takže by prompt byl jediná „brána“ — a prompt brána není.
    /// - **Žádný `Bash`**, tedy ani `Bash(git:*)`: commituje aplikace, ne session, a bez `Bash`u
    ///   je to vlastnost sady, ne délka seznamu zákazů.
    /// - Rozsah je **ten strom, ve kterém rebase uvázl**, se `//` pro absolutní cestu.
    @Test("Slévání konfliktů píše, ale jen ve svém stromě")
    func conflictToolSet() {
        #expect(
            ConflictCommand.allowedTools(in: worktree)
                == "Read,Grep,Glob,Write(///cache/PRism/repos/o-r/42-sync/**),"
                    + "Edit(///cache/PRism/repos/o-r/42-sync/**)"
        )
    }

    /// **5. Agent na vlastním PR** (#510) — **druhá session, která smí psát**, a **první, kterou
    /// aplikace pouští bez kliknutí**.
    ///
    /// **Sada se tím nemění ani o položku, a tohle je to tvrzení.** Je to doslova týž řetězec jako
    /// u slévání konfliktů, protože otázka „kam smí zapisující session psát“ má mít **jednu**
    /// odpověď; nové na #510 je **spouštěč**, ne povolení. Kdyby si agent skládal sadu sám, byl by
    /// v aplikaci druhý `Write(//…)` — a ten by se s prvním rozešel potichu.
    ///
    /// Tvrdí se **oba směry**: literál (aby se rozšíření sady muselo napsat sem) i rovnost se
    /// čtvrtou sadou (aby se ty dvě nedaly rozejít).
    @Test("Agent na vlastním PR má tutéž sadu jako slévání konfliktů")
    func agentFixToolSet() {
        #expect(
            AgentFixCommand.allowedTools(in: worktree)
                == "Read,Grep,Glob,Write(///cache/PRism/repos/o-r/42-sync/**),"
                    + "Edit(///cache/PRism/repos/o-r/42-sync/**)"
        )
        #expect(AgentFixCommand.allowedTools(in: worktree) == ConflictCommand.allowedTools(in: worktree))
        // **`Bash` v ní není vůbec**, tedy ani `Bash(git:*)`: commituje aplikace, ne session.
        #expect(!AgentFixCommand.allowedTools(in: worktree).contains("Bash"))
    }

    /// **6. Anotace hunků** (#524) — **sedmá session, ale žádná nová sada**.
    ///
    /// Do zadání #524 měla mít vlastní sadu s nástrojem `ReportAnnotations`. Nástroj odpadl
    /// (odpovídá se posledním sdělením, viz `AnnotationSchema`) a s ním důvod pro vlastní sadu:
    /// zbyla by z ní **druhá konstanta s týmž obsahem**, tedy druhé místo, kde se dá tvrdá
    /// podmínka č. 2 porušit. Anotace se od rozhovoru liší **promptem a parserem**, ne právy.
    ///
    /// Tvrdí se **oba směry**, jako u páté session: literál (aby se rozšíření muselo napsat sem)
    /// i rovnost s rozhovorem (aby se ty dvě nedaly rozejít).
    @Test("Anotace hunků běží s toutéž sadou jako rozhovor nad PR")
    func annotateToolSet() {
        let allowed = Self.value(of: "--allowedTools", in: AnnotateCommand.arguments(prompt: "x"))

        #expect(allowed == "Read,Grep,Glob,Bash(git:*)")
        #expect(allowed == AskCommand.allowedTools)
        // **`ReportFindings` v ní není**: anotace není nález a nemá se kam zapsat, ani kdyby chtěla.
        #expect(allowed?.contains("ReportFindings") != true)
        // A `ReportAnnotations` v ní taky ne — nástroj, který aplikace nespouští, by v povoleních
        // znamenal, že se na něj session bude marně ptát.
        #expect(allowed?.contains("ReportAnnotations") != true)
    }

    // MARK: - Co platí pro všechny čtyři

    /// **Jedna sada zákazů, ne čtyři.** Druhá by byla druhé místo, kde se dá tvrdá podmínka č. 2
    /// porušit — a tvrdí se **literálem**, protože právě `git push` je to, co #466 povolilo
    /// **aplikaci** a session ne.
    @Test("Zákazy jsou jedna konstanta a jsou v ní gh i git push")
    func sharedDisallowedTools() {
        #expect(ClaudeCommand.disallowedTools == "Bash(gh:*),Bash(git push:*)")

        for arguments in Self.everyArgumentList(worktree: worktree) {
            #expect(Self.value(of: "--disallowedTools", in: arguments) == "Bash(gh:*),Bash(git push:*)")
        }
    }

    /// **Žádná session nemá `gh`.** Ani v povoleních, ani obchodem přes `Bash`: `Bash(gh:*)` je
    /// v zákazech, ale sada má říkat, co session smí — takže se `gh` nesmí objevit ani tam.
    @Test("gh není v povoleních žádné session")
    func noSessionMayUseGh() {
        for arguments in Self.everyArgumentList(worktree: worktree) {
            let allowed = Self.value(of: "--allowedTools", in: arguments) ?? ""
            #expect(!allowed.contains("gh"), "gh je v povoleních: \(allowed)")
        }
    }

    /// **Psát smí jedna jediná, a jedině s rozsahem.**
    ///
    /// Je to to tvrzení, které se rozbije potichu: kdyby `Write` přibyl reviewerovi, rozhovoru nebo
    /// dotažení textu issue, nic by nepadlo a nikdo by si toho nevšiml. A kdyby se u čtvrté session
    /// rozsah vytratil, session by uměla psát do uživatelova klonu.
    @Test("Write a Edit má jen slévání konfliktů, a s rozsahem")
    func onlyTheConflictSessionWrites() {
        let readOnly = [
            ClaudeCommand.allowedTools,
            AskCommand.allowedTools,
            Self.value(
                of: "--allowedTools",
                in: IntentTextCommand.arguments(prompt: "x", tool: "mcp__linear__get_issue")
            ) ?? "",
        ]
        for allowed in readOnly {
            #expect(!allowed.contains("Write"), "Write v read-only sadě: \(allowed)")
            #expect(!allowed.contains("Edit"), "Edit v read-only sadě: \(allowed)")
        }

        let writing = ConflictCommand.allowedTools(in: worktree)
        // **Holé jméno se nesmí objevit ani jako položka seznamu** — `Write` bez závorky by
        // znamenalo povolení bez rozsahu, tedy zápis kamkoli.
        let items = writing.split(separator: ",").map(String.init)
        #expect(!items.contains("Write"))
        #expect(!items.contains("Edit"))
        #expect(writing.contains("Write(//"))
        #expect(writing.contains("Edit(//"))
    }

    /// **`Bash` má jen ta session, která ho k něčemu potřebuje, a nikdy holý.**
    ///
    /// Reviewer a rozhovor potřebují `git diff`; slévání konfliktů `Bash` **nemá vůbec** (commituje
    /// aplikace) a dotažení textu issue taky ne (mluví s MCP nástrojem).
    @Test("Bash je jedině scoped na git, a jen u dvou session")
    func bashOnlyWhereItIsNeeded() {
        for allowed in [ClaudeCommand.allowedTools, AskCommand.allowedTools] {
            let items = allowed.split(separator: ",").map(String.init)
            #expect(items.contains("Bash(git:*)"))
            #expect(!items.contains("Bash"), "holý Bash v sadě: \(allowed)")
        }

        #expect(!ConflictCommand.allowedTools(in: worktree).contains("Bash"))
        #expect(
            Self.value(
                of: "--allowedTools",
                in: IntentTextCommand.arguments(prompt: "x", tool: "mcp__linear__get_issue")
            )?.contains("Bash") != true
        )
    }

    /// Argumenty všech čtyř session — **na jednom místě**, aby se tvrzení „platí pro všechny“
    /// nedalo napsat jen o třech z nich.
    private static func everyArgumentList(worktree: URL) -> [[String]] {
        [
            ClaudeCommand.arguments(prompt: "x"),
            IntentTextCommand.arguments(prompt: "x", tool: "mcp__linear__get_issue"),
            AskCommand.arguments(prompt: "x", resuming: nil),
            ConflictCommand.arguments(prompt: "x", worktree: worktree),
            // Pátá session (#510). Bere argumenty od té čtvrté, ale ve výčtu být **musí**: kdyby
            // si je někdy začala skládat sama, mají o tom tvrzení „platí pro všechny“ vědět.
            AgentFixCommand.arguments(prompt: "x", worktree: worktree),
            // Anotace hunků (#524). Skládá si argumenty sama a **povolení si půjčuje od rozhovoru**
            // — tvrzení „platí pro všechny“ ji tedy musí vidět, aby se tou půjčkou nedalo obejít.
            AnnotateCommand.arguments(prompt: "x"),
        ]
    }

    private static func value(of flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else {
            return nil
        }
        return arguments[index + 1]
    }
}
