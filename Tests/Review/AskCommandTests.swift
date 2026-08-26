import Foundation
import Testing

@testable import PRism

/// Rozhovor nad PR — argumenty session a doklad o tom, co si přečetla (#452).
///
/// **Obě konstanty sady se tvrdí literálem**, jako u dotažení textu issue (#345). Porovnat
/// povolení proti `AskCommand.allowedTools` by neznamenalo nic: kdyby se konstanta rozšířila
/// o `Write`, test by ji poslušně přečetl a prošel. Tvrdá podmínka č. 2 se dá porušit jedině
/// změnou toho řetězce, takže tady musí stát doslova.
@Suite("Rozhovor nad PR — session (#452)")
struct AskCommandTests {
    // MARK: - Argumenty

    /// **Tvrdá podmínka č. 2, třetí vyjmenovaná session.** Sada je **užší než reviewerova**:
    /// bez `ReportFindings` (nemá co hlásit) a bez `Skill` (skill načtený za běhu si umí říct
    /// o odeslání na GitHub).
    @Test("Povolení jsou čtyři čtecí nástroje a zákazy jsou tytéž jako u revieweera")
    func keepsTheSessionReadOnly() {
        let arguments = AskCommand.arguments(prompt: "cokoli", resuming: nil)

        // Literálem, ne konstantou: kdyby se konstanta změnila, má o tom být řeč tady.
        #expect(value(of: "--allowedTools", in: arguments) == "Read,Grep,Glob,Bash(git:*)")
        #expect(value(of: "--disallowedTools", in: arguments) == "Bash(gh:*),Bash(git push:*)")
        // A že je to **tatáž konstanta** jako u revieweera — druhá sada zákazů by znamenala druhé
        // místo, kde se ta podmínka dá porušit.
        #expect(value(of: "--disallowedTools", in: arguments) == ClaudeCommand.disallowedTools)
    }

    /// Co v povoleních **není** — jmenovitě, ne jen počtem: přejmenovaná položka by počet
    /// nezměnila.
    @Test("V povoleních není zápis, ReportFindings ani Skill")
    func forbidsWritingTools() {
        let allowed = value(of: "--allowedTools", in: AskCommand.arguments(prompt: "x", resuming: nil))

        for forbidden in ["Write", "Edit", "NotebookEdit", "ReportFindings", "Skill", "WebFetch"] {
            #expect(allowed?.contains(forbidden) != true, "\(forbidden) je v povoleních rozhovoru")
        }
        // `Bash` je povolený **jen se vzorem** — holý `Bash` by pustil cokoli.
        #expect(allowed?.contains("Bash(git:*)") == true)
        #expect(allowed?.split(separator: ",").contains("Bash") != true)
    }

    /// **Užší než reviewerova, a je to vidět z porovnání**: rozdílem jsou právě ty dvě položky.
    /// Kdyby se sada rozhovoru někdy „srovnala“ s reviewerovou, tenhle test spadne dřív, než se
    /// na to přijde v okně.
    @Test("Sada rozhovoru je vlastní podmnožina reviewerovy")
    func isNarrowerThanTheReviewers() {
        let ask = Set(AskCommand.allowedTools.split(separator: ","))
        let reviewer = Set(ClaudeCommand.allowedTools.split(separator: ","))

        #expect(ask.isSubset(of: reviewer))
        #expect(reviewer.subtracting(ask) == ["ReportFindings", "Skill"])
    }

    @Test("Session jede streamem, aby se dalo číst, co dělá")
    func runsAsAStream() {
        let arguments = AskCommand.arguments(prompt: "x", resuming: nil)

        #expect(value(of: "--output-format", in: arguments) == "stream-json")
        #expect(arguments.contains("--verbose"))
        #expect(arguments.first == "-p")
        #expect(arguments.dropFirst().first == "x")
    }

    /// **`--resume` drží rozhovor pohromadě.** Bez id se nepředává vůbec — a prázdné id je totéž
    /// co žádné, protože `claude --resume ""` by hledal session podle prázdného jména.
    @Test("Navázání se posílá jen s neprázdným id")
    func resumesOnlyWithAnIdentifier() {
        #expect(!AskCommand.arguments(prompt: "x", resuming: nil).contains("--resume"))
        #expect(!AskCommand.arguments(prompt: "x", resuming: "").contains("--resume"))

        let resumed = AskCommand.arguments(prompt: "x", resuming: "abc-123")
        #expect(value(of: "--resume", in: resumed) == "abc-123")
    }

    /// Model se **bere z konfigurace**, na rozdíl od překladu nálezů a dotažení textu issue:
    /// odpovědí je úvaha nad cizím kódem, ne mechanický převod.
    @Test("Model se předá, když je v konfiguraci — jinak si vybere claude")
    func passesTheConfiguredModel() {
        #expect(!AskCommand.arguments(prompt: "x", resuming: nil, model: nil).contains("--model"))
        #expect(!AskCommand.arguments(prompt: "x", resuming: nil, model: "").contains("--model"))
        #expect(
            value(of: "--model", in: AskCommand.arguments(prompt: "x", resuming: nil, model: "opus"))
                == "opus"
        )
    }

    // MARK: - Co si přečetl

    /// Doklad je z **provedených** kroků, ne z těch, o které si session řekla.
    ///
    /// Odmítnutý ani spadlý `Read` nic nepřečetl — a řádek „přečetl X“ nad odpovědí je doklad,
    /// takže tvrdit tam něco, co se nestalo, je přesně ten text, který tvrdí víc, než data unesou.
    @Test("Do dokladu jde jen Read, který prošel")
    func countsOnlyPassedReads() {
        let worktree = URL(filePath: "/cache/worktrees/o/r/42-abc")
        let tools = [
            ToolAttempt(name: "Read", detail: "\(worktree.path)/App/A.swift", outcome: .init(kind: .passed)),
            ToolAttempt(name: "Read", detail: "\(worktree.path)/App/B.swift", outcome: .init(kind: .denied)),
            ToolAttempt(name: "Read", detail: "\(worktree.path)/App/C.swift", outcome: .init(kind: .failed)),
            // Ještě běží — o tom, jestli prošel, se zatím neví.
            ToolAttempt(name: "Read", detail: "\(worktree.path)/App/D.swift", outcome: nil),
            ToolAttempt(name: "Grep", detail: "mutex", outcome: .init(kind: .passed)),
        ]

        #expect(AskCommand.readFiles(from: tools, worktree: worktree) == ["App/A.swift"])
    }

    /// Cesta se zkracuje o pracovní strom — jinak by na řádku stálo sedmdesát znaků cache před
    /// jménem souboru. A duplicity se zahazují, protože session si týž soubor otevře i třikrát.
    @Test("Cesty jsou zkrácené a bez duplicit, v pořadí prvního otevření")
    func shortensAndDeduplicates() {
        let worktree = URL(filePath: "/cache/worktrees/o/r/42-abc")
        let tools = ["App/B.swift", "App/A.swift", "App/B.swift"].map {
            ToolAttempt(name: "Read", detail: "\(worktree.path)/\($0)", outcome: .init(kind: .passed))
        }

        #expect(AskCommand.readFiles(from: tools, worktree: worktree) == ["App/B.swift", "App/A.swift"])
    }

    /// Limit odpovědi je **vlastní číslo**, ne limit review z konfigurace: tady čeká člověk
    /// u okna na jednu odpověď.
    @Test("Odpověď má pětiminutový strop")
    func hasItsOwnTimeout() {
        #expect(AskCommand.timeout == .seconds(300))
    }

    private func value(of flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }
}
