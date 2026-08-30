import Foundation
import Testing

@testable import PRism

/// Hranice cache — **dva verdikty, které se nesmí zaměnit** (#452, doměřeno u #479).
///
/// `CacheFile` je jediné místo, kde tvrdá podmínka č. 3 bydlí, a nabízí **dvě** odpovědi:
/// `isInsideCache` pro **mazání** (jen `contains`, tedy rozbalený **rodič**) a `refusal` pro
/// **čtení a zápis** (k tomu odkaz na samotném souboru). Do #479 nebyl na ten rozdíl přímý test —
/// stálo to nález Copilota na PR #481, kde zápis důvěry do `~/.claude.json` bral verdikt pro mazání
/// a symbolický odkaz uvnitř cache mířící ven by jím **prošel**.
@Suite("Hranice cache — verdikt pro mazání a verdikt pro zápis (#452, #479)")
struct CacheFileVerdictTests {
    private func scratch() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "prism-verdict-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// **Odkaz na samotné složce oba verdikty rozliší** — a je to celý důvod, proč jsou dva.
    ///
    /// `contains` rozbaluje **rodiče**, takže odkaz, který leží uvnitř cache a míří ven, jím projde:
    /// rodič je pořád v cache. Kdo přes takovou cestu **čte nebo píše**, sáhne ale na cíl — a u
    /// zápisu důvěry to platí dvakrát, protože klíč do konfigurace skládá `realpath`, který
    /// poslední komponentu rozvine.
    @Test("Odkaz uvnitř cache mířící ven projde mazacím verdiktem, zápisovým ne")
    func asymbolicLinkInsideTheCachePassesOnlyTheDeletionVerdict() throws {
        let root = try scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let outside = try scratch()
        defer { try? FileManager.default.removeItem(at: outside) }
        let layout = CacheLayout(root: root)
        let link = root.appending(path: "worktrees-link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)

        #expect(CacheFile.isInsideCache(link, in: layout), "mazací verdikt odkaz odmítat nemá")
        #expect(CacheFile.refusal(for: link, in: layout) == .symbolicLink)
    }

    /// Složka mimo cache neprojde ani jedním — tam se ty dva verdikty neliší.
    @Test("Složka mimo cache neprojde ani jedním verdiktem")
    func adirectoryOutsideTheCacheFailsBoth() throws {
        let root = try scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let layout = CacheLayout(root: root)
        let outside = URL(filePath: "/Users/o/Projects/PRism")

        #expect(!CacheFile.isInsideCache(outside, in: layout))
        #expect(CacheFile.refusal(for: outside, in: layout) == .outsideCache)
    }

    /// **Zápis důvěry si bere ten přísnější**, a tvrdí se to nad zdrojákem: v harnessu se to
    /// ověřit nedá, protože `AppStore` si `CacheLayout.applicationSupport` bere staticky, takže
    /// odkaz by musel vzniknout ve **skutečné** cache aplikace. Je to tentýž postup jako
    /// u `GlobalAppearanceTests` a `FontMetricTests` — o kontrole, kterou nejde vyvolat, se dá
    /// aspoň tvrdit, že v kódu stojí.
    @Test("Zápis důvěry bere verdikt pro zápis, ne pro mazání")
    func theTrustWriteTakesTheWriteVerdict() throws {
        let source = try String(
            contentsOf: URL(filePath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appending(path: "App/Store/AppStore+TerminalDrawer.swift"),
            encoding: .utf8
        )
        let code = TextLines.content(source)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")

        #expect(code.contains("CacheFile.refusal(for: workspace, in: layout) == nil"))
        #expect(!code.contains("CacheFile.isInsideCache"), "zápis vzal verdikt pro mazání")
    }
}
