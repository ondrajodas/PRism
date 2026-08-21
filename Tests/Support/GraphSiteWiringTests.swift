import Foundation
import Testing

@testable import PRism

/// **Vyjmenované místo, které nikdo nezapojil, je nula, která lže** (#361).
///
/// `GraphSite` je výčet míst, ze kterých se v hořícím kole ptáme grafu. Kdyby některé z nich
/// v `App/` nikdo nevolal, v záznamu by u té sekundy prostě nebylo — a to se nedá odlišit od
/// „tímhle místem kolo neprochází“, což je zrovna ta věta, kterou se u #361 hledá příčina. Test
/// proto tvrdí, že **každý** případ výčtu má v aplikaci volání.
///
/// Čte se zdroják, ne chování: „odkud se ptáme“ je vlastnost struktury kódu a za běhu se na to
/// zeptat nedá — v hořícím kole se nedostaneme k tomu, abychom to zjišťovali. Je to tatáž
/// konstrukce jako u `SingleWayOutTests`, včetně zahazování komentářů (`grep -vE ':[0-9]+: *//'`):
/// o hácích se v dokumentaci mluví, a vysvětlení nemá test zakazovat.
@Suite("Zapojení míst v grafu (#361)")
struct GraphSiteWiringTests {
    private static let sources = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appending(path: "App")

    @Test("Každé vyjmenované místo má v aplikaci volání")
    func everySiteIsWired() throws {
        let code = try appCode()
        for site in GraphSite.allCases {
            #expect(
                code.contains("RenderDiagnostics.inGraph(.\(site))"),
                "místo \(site) (\(site.rawValue)) není v App/ nikde zapojené"
            )
        }
    }

    /// **Identita líných seznamů jde přes hák.** Tři seznamy, ve kterých se kolo z #361 chytlo:
    /// soubory a řádky diffu a osa konverzace. Kdyby se `ForEach` vrátil na `\.id`, diagnostika by
    /// v kole osy konverzace neviděla **nic** — tam je dotaz na identitu jediná přítomnost
    /// aplikace.
    @Test("Líné seznamy čtou identitu přes diagnosedID")
    func lazyListsUseDiagnosedIdentity() throws {
        let code = try appCode()
        #expect(code.contains("ForEach(diff.files, id: \\.diagnosedID)"))
        #expect(code.contains("ForEach(rows, id: \\.diagnosedID)"))
        #expect(code.contains("id: \\.diagnosedID\n        ) { row in"))
    }

    /// Kód aplikace bez řádkových komentářů, slitý do jednoho textu.
    private func appCode() throws -> String {
        let root = Self.sources
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else {
            throw WiringError.unreadable(root.path)
        }
        var parts: [String] = []
        for case let url as URL in walker where url.pathExtension == "swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            // `TextLines`, ne `split(separator: "\n")` — pravidlo repa platí i v testech.
            parts.append(
                TextLines.content(text)
                    .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
                    .joined(separator: "\n")
            )
        }
        guard !parts.isEmpty else { throw WiringError.unreadable(root.path) }
        return parts.joined(separator: "\n")
    }

    private enum WiringError: Error {
        case unreadable(String)
    }
}
