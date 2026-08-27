import Foundation
import Testing

@testable import PRism

/// Jediná cesta ven (tvrdá podmínka č. 1) jako **test, ne grep v hlavě** (#333).
///
/// `CLAUDE.md` říká, že `grep ReviewPublishing App/` má vypsat sedm souborů a pět volajících. Dokud
/// to byl jen grep, platilo to jen tehdy, když si na něj někdo vzpomněl — a zrovna u téhle
/// podmínky se porušení nepozná jinak než tím, že něco odešlo. Nejcennější test je ten, který
/// tvrdí, že se něco **nestalo**.
///
/// **Čísla v tvrzeních se u #392, #413 a #465 zvedla, tvrzení samotná ne** (u #392 z pěti souborů
/// a čtyř metod, u #413 ze šesti metod na sedm, u #465 ze šesti souborů na sedm a ze sedmi metod
/// na osm). Pravidlo se rozšířilo vědomě — labely a vyžádání
/// reviewera na **vlastním** PR, pak založení labelu, pak merge; důvody jsou u `ReviewPublishing` —,
/// takže se přepsal ten výčet, ne jeho podoba: pořád je to **jmenovitý**
/// seznam souborů a **jmenovitý** seznam metod, ne rozsah ani „aspoň tolik“. Rozvolnit tvrzení na
/// nerovnost by z testu udělalo dekoraci: přibyla by devátá cesta ven a nikdo by se o ní nedozvěděl.
///
/// **Počet souborů se u #413 nezvedl, u #465 ano, a v obou případech je to samo tvrzení.** Založení
/// labelu je sedmá **metoda**, ne pátý volající — přibylo do `MetadataSubmission`, protože je to
/// tatáž věc z pohledu podmínky (metadata vlastního PR, tatáž brána, tytéž dvě sekce panelu).
/// Merge je proti tomu **pátý volající** (`MergeSubmission`), a je to jediné místo, kde se od
/// #392 liší: má **potvrzovací obrazovku a životnost** — objekt vzniká kliknutím, drží snímek toho,
/// co se potvrzuje, a zaniká zavřením sheetu. Je to tvarem `ReviewSubmission`, ne
/// `MetadataSubmission`.
///
/// **A `merge` z výčtu zakázaných zmizel, což je ta nejpodstatnější změna v tomhle souboru.** Do
/// #465 tady stálo jmenovitě, že merge je porušení podmínky. Změnilo se to vědomě, ne obejitím:
/// mergnout vlastní PR, když je zeleno, je poslední věc, kvůli které se od hotového review
/// odskakuje do prohlížeče. **V zákazu zůstává** approve mimo review, zavření PR, milník
/// a `deleteLabel` — a je jmenovitě vypsaný níž, aby se z testu dalo přečíst, co se smí a co ne.
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

    /// **Sedm souborů, ani o jeden víc.** Protokol, jeho implementace a pět volajících — víc míst
    /// znamená víc toho, co aplikace umí odeslat, a to má být vidět na jednom místě.
    ///
    /// Všechny leží v `Publish/`, a to je druhá polovina tvrzení: nový volající **mimo** tuhle
    /// složku by znamenal, že cesta ven vede odjinud než z jednoho místa.
    @Test("ReviewPublishing zná sedm souborů")
    func namesEveryWayOut() throws {
        let using = try swiftFiles()
            .filter { $0.code.contains("ReviewPublishing") }
            .map(\.path)
            .sorted()

        #expect(using == [
            "Publish/CommentSubmission.swift",
            "Publish/GhReviewPublisher.swift",
            "Publish/MergeSubmission.swift",
            "Publish/MetadataSubmission.swift",
            "Publish/ReviewPublishing.swift",
            "Publish/ReviewSubmission.swift",
            "Publish/ThreadSubmission.swift",
        ])
        #expect(using.allSatisfy { $0.hasPrefix("Publish/") })
    }

    /// Protokol má **osm vyjmenovaných metod** (do #392 čtyři, do #413 šest, do #465 sedm). Approve
    /// mimo review, **zavření PR**, **milník** ani **smazání labelu** mezi ně nepatří — a kdyby
    /// přibyla devátá, má o tom být řeč v review, ne až na GitHubu.
    @Test("Protokol má osm metod")
    func hasEightMethods() throws {
        guard let file = try swiftFiles().first(where: { $0.path == "Publish/ReviewPublishing.swift" }) else {
            Issue.record("soubor s protokolem se nenašel")
            return
        }
        let methods = TextLines.content(file.code)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("func ") }

        #expect(methods.count == 8)
        for name in [
            "func submit", "func reply", "func setResolved", "func comment",
            "func setLabels", "func requestReviewers", "func createLabel", "func merge",
        ] {
            #expect(methods.contains { $0.hasPrefix(name) })
        }
        // **Co v zákazu zůstalo.** Vyjmenované jmenovitě, ne jen počtem: devátá metoda by počet
        // shodila, ale přejmenovaná pátá ne — a `close` nebo `approve` v tomhle protokolu je
        // porušení podmínky, ne rozšíření.
        //
        // **`merge` z tohohle výčtu u #465 zmizel** a je to vědomá změna pravidla, ne díra: přibyl
        // jako osmá **metoda** výš, se svým potvrzením a s hlavou v payloadu. Že tady zůstává
        // `close`, není nedodělek — zavřít cizí ani vlastní PR odsud nejde a nepůjde, protože to
        // není práce, která se dělá **při review**.
        //
        // **`deleteLabel` je v tom výčtu od #413**, a je to ta jediná věc, kterou nová metoda
        // nesmí přitáhnout: založený label se dá **přidat i odebrat z PR**, ale smazat ho
        // z repozitáře se odsud nebude dát nikdy — zmizel by ze všech issues, na kterých leží.
        for forbidden in [
            "func close", "func approve", "func setMilestone", "func deleteLabel",
        ] {
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

    /// **Surová session (#327) je čtení, a nic než čtení.** Sheet ukazuje soubor, který si `claude`
    /// vede na disku — takže ani jeden z jeho souborů nesmí publisher volat, skládat payload, sahat
    /// na API ani spouštět podproces. Je to tatáž konstrukce jako u zadání pro agenta a ze stejného
    /// důvodu: nová obrazovka nad daty běhu je zrovna to místo, kde by druhá cesta ven vznikla, aniž
    /// by o ní kdo mluvil.
    ///
    /// **A nesmí do souboru ani zapisovat.** Transcript je cizí soubor mimo cache (leží pod
    /// `~/.claude/projects`), takže by zápis do něj porušil i tvrdou podmínku č. 3 — `Ukázat
    /// v Finderu` je to nejvíc, co se s ním odsud dělá.
    @Test("Surová session umí jen číst")
    func keepsTheRawSessionReadOnly() throws {
        let files = try swiftFiles().filter {
            $0.path.contains("RawSession") || $0.path.contains("RawTranscript")
                || $0.path.contains("Transcript")
        }

        // Deset souborů: model, `Policy`, přepis a čtení v `Review`, cesta k souboru, store
        // a čtyři ve `Views`. Počet je v tvrzení schválně — nový soubor téhle vrstvy má projít
        // týmiž zákazy.
        #expect(files.count == 10)
        for file in files {
            #expect(!file.code.contains("ReviewPublishing"), "\(file.path) volá publisher")
            #expect(!file.code.contains("PublishRequest"), "\(file.path) skládá payload")
            #expect(!file.code.contains("GhReviewPublisher"), "\(file.path) zná implementaci")
            #expect(!file.code.contains("api.github.com"), "\(file.path) sahá na API")
            #expect(!file.code.contains("Process("), "\(file.path) spouští podproces")
            #expect(!file.code.contains(".write(to:"), "\(file.path) zapisuje do souboru")
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
