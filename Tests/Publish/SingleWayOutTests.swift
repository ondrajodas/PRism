import Foundation
import Testing

@testable import PRism

/// Jediná cesta ven (tvrdá podmínka č. 1) jako **test, ne grep v hlavě** (#333).
///
/// `CLAUDE.md` říká, že `grep ReviewPublishing App/` má vypsat šest souborů a čtyři volající. Dokud
/// to byl jen grep, platilo to jen tehdy, když si na něj někdo vzpomněl — a zrovna u téhle
/// podmínky se porušení nepozná jinak než tím, že něco odešlo. Nejcennější test je ten, který
/// tvrdí, že se něco **nestalo**.
///
/// **Čísla v tvrzeních se u #392 zvedla, tvrzení samotná ne** (do té doby pět souborů a čtyři
/// metody). Pravidlo se rozšířilo vědomě — labely a vyžádání reviewera na **vlastním** PR, důvod je
/// u `ReviewPublishing` —, takže se přepsal ten výčet, ne jeho podoba: pořád je to **jmenovitý**
/// seznam souborů a **jmenovitý** seznam metod, ne rozsah ani „aspoň tolik“. Rozvolnit tvrzení na
/// nerovnost by z testu udělalo dekoraci: přibyla by sedmá cesta ven a nikdo by se o ní nedozvěděl.
///
/// Čte se **zdroják, ne chování**: „odkud se dá odeslat“ je vlastnost struktury kódu, na kterou se
/// za běhu zeptat nedá. Cesta ke zdrojákům se odvozuje z `#filePath`, jako u `Fixture`.
///
/// **Komentáře se zahazují**, stejně jako u grepů v `CLAUDE.md` (`grep -vE ':[0-9]+: *//'`):
/// o publisheru se v dokumentaci mluví na dalších čtyřech místech (`ReviewVerdict`,
/// `AppStore+Submission`, `AppStore+Conversation`, `CommitDiffView`) a právě ta vysvětlení jsou to,
/// co podmínku drží pochopitelnou. Test by je jinak zakazoval.
@Suite("Jediná cesta ven")
struct SingleWayOutTests {
    private static let sources = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appending(path: "App")

    private struct Source {
        let path: String
        /// Celý soubor, včetně komentářů.
        let text: String
        /// Jen kód — řádky, které začínají `//`, jsou pryč.
        let code: String
    }

    /// Všechny zdrojáky aplikace i s cestou relativní ke `App/`.
    private func swiftFiles() throws -> [Source] {
        let root = Self.sources
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else {
            throw SourceError.unreadable(root.path)
        }
        var files: [Source] = []
        for case let url as URL in walker where url.pathExtension == "swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            files.append(
                Source(
                    path: url.path.replacingOccurrences(of: root.path + "/", with: ""),
                    text: text,
                    // `TextLines`, ne `split(separator: "\n")` — pravidlo repa platí i v testech.
                    code: TextLines.content(text)
                        .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
                        .joined(separator: "\n")
                )
            )
        }
        guard !files.isEmpty else { throw SourceError.unreadable(root.path) }
        return files
    }

    private enum SourceError: Error {
        case unreadable(String)
    }

    /// **Šest souborů, ani o jeden víc.** Protokol, jeho implementace a čtyři volající — víc míst
    /// znamená víc toho, co aplikace umí odeslat, a to má být vidět na jednom místě.
    ///
    /// Všechny leží v `Publish/`, a to je druhá polovina tvrzení: nový volající **mimo** tuhle
    /// složku by znamenal, že cesta ven vede odjinud než z jednoho místa.
    @Test("ReviewPublishing zná šest souborů")
    func namesEveryWayOut() throws {
        let using = try swiftFiles()
            .filter { $0.code.contains("ReviewPublishing") }
            .map(\.path)
            .sorted()

        #expect(using == [
            "Publish/CommentSubmission.swift",
            "Publish/GhReviewPublisher.swift",
            "Publish/MetadataSubmission.swift",
            "Publish/ReviewPublishing.swift",
            "Publish/ReviewSubmission.swift",
            "Publish/ThreadSubmission.swift",
        ])
        #expect(using.allSatisfy { $0.hasPrefix("Publish/") })
    }

    /// Protokol má **šest vyjmenovaných metod** (do #392 čtyři). Approve mimo review, **merge**,
    /// **zavření PR** ani **milník** mezi ně nepatří — a kdyby přibyla sedmá, má o tom být řeč
    /// v review, ne až na GitHubu.
    @Test("Protokol má šest metod")
    func hasSixMethods() throws {
        guard let file = try swiftFiles().first(where: { $0.path == "Publish/ReviewPublishing.swift" }) else {
            Issue.record("soubor s protokolem se nenašel")
            return
        }
        let methods = TextLines.content(file.code)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("func ") }

        #expect(methods.count == 6)
        for name in [
            "func submit", "func reply", "func setResolved", "func comment",
            "func setLabels", "func requestReviewers",
        ] {
            #expect(methods.contains { $0.hasPrefix(name) })
        }
        // **Co v zákazu zůstalo.** Vyjmenované jmenovitě, ne jen počtem: sedmá metoda by počet
        // shodila, ale přejmenovaná pátá ne — a `merge` nebo `close` v tomhle protokolu je
        // porušení podmínky, ne rozšíření.
        for forbidden in ["func merge", "func close", "func approve", "func setMilestone"] {
            #expect(!methods.contains { $0.hasPrefix(forbidden) }, "\(forbidden) je cesta ven, kterou podmínka nepřipouští")
        }
    }

    /// **Zadání pro agenta (#333) cestu ven nemá.** Prompt končí ve schránce nebo v souboru, který
    /// si vybere člověk — takže ani jeden z jeho souborů nesmí publisher volat, skládat payload,
    /// sahat na API ani spouštět podproces. Kdyby se to změnilo, byla by to druhá cesta ven, a tu
    /// podmínka nepřipouští.
    @Test("Zadání pro agenta neumí nic odeslat")
    func keepsTheAgentPromptOffline() throws {
        let files = try swiftFiles().filter { $0.path.contains("AgentPrompt") }

        // Dvanáct souborů: sedm v `Policy`, jeden ve `Store`, čtyři ve `Views` — a `ReviewPanel`,
        // který je kreslí, tady schválně není (počítá se jen to, co má „AgentPrompt“ ve jméně).
        // Počet je v tvrzení schválně: nový soubor téhle vrstvy má projít týmiž zákazy. Od #377
        // k nim patří i výběr po položkách (`AgentPromptExclusion`, `AgentPromptPick`,
        // `AgentPromptDiffSummary`, `AgentPromptPickList`) — výběr rozhoduje o **obsahu** textu,
        // takže je to zrovna vrstva, u které se nesmí objevit cesta ven.
        #expect(files.count == 12)
        for file in files {
            #expect(!file.code.contains("ReviewPublishing"), "\(file.path) volá publisher")
            #expect(!file.code.contains("PublishRequest"), "\(file.path) skládá payload")
            #expect(!file.code.contains("GhReviewPublisher"), "\(file.path) zná implementaci")
            #expect(!file.code.contains("api.github.com"), "\(file.path) sahá na API")
            #expect(!file.code.contains("Process("), "\(file.path) spouští podproces")
        }
    }

    /// Uložení do souboru je **jediné místo mimo úložiště, které zapisuje** — a smí to jen proto,
    /// že cestu vybírá člověk v systémovém dialogu (`NSSavePanel`). Kdyby si cestu složil kód sám,
    /// byl by to zápis mimo cache (tvrdá podmínka č. 3).
    @Test("Do souboru se zapisuje jen tam, kam ukáže člověk")
    func writesOnlyWhereTheUserPoints() throws {
        let files = try swiftFiles()
        let writers = files.filter { $0.code.contains(".write(to:") }.map(\.path).sorted()
        // Úložiště (`Store`, `Config`, `Checkout`, `Review`, `Publish`) zapisují do cache a mají —
        // tohle tvrzení je o vrstvách, které si soubor vybírat nemají.
        let outside = writers.filter { path in
            ["Support/", "Views/", "Policy/", "Models/", "Diff/"].contains { path.hasPrefix($0) }
        }

        #expect(outside == ["Support/TextFileExport.swift"])
        #expect(files.first { $0.path == "Support/TextFileExport.swift" }?.code.contains("NSSavePanel") == true)
    }
}
