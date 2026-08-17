import Foundation
import Testing

@testable import PRism

/// Uložení zadání pro reviewera (#120).
///
/// Nejcennější tvrzení jsou dvě a obojí je o tom, **kam se nesahá**: soubor leží vedle pracovního
/// stromu (ne v něm, jinak by ho reviewer viděl v `git diff` jako součást změny) a nikdy mimo
/// cache aplikace.
@Suite("ReviewIntentStore (#120)")
struct ReviewIntentStoreTests {
    private let workspace: TemporaryDirectory
    private let layout: CacheLayout
    private let store: ReviewIntentStore
    private let pr = PRIdentifier(repo: RepoID(owner: "cli", name: "cli"), number: 42)
    private let headSha = "aaaa1111"

    init() throws {
        workspace = try TemporaryDirectory()
        layout = CacheLayout(root: workspace.url)
        store = ReviewIntentStore(layout: layout)
    }

    /// **Vedle stromu, ne v něm** — tohle je celý důvod, proč soubor bydlí tam, kde bydlí.
    /// Uvnitř stromu by ho `git status` i `git diff` vypsaly jako změnu k posouzení.
    @Test("Soubor leží vedle pracovního stromu, ne uvnitř")
    func sitsNextToTheWorktreeAndNotInsideIt() throws {
        let file = try #require(try store.save("# zadání\n", for: pr, at: headSha))

        let worktree = layout.worktree(for: pr, at: headSha)
        #expect(file.deletingLastPathComponent() == worktree.deletingLastPathComponent())
        #expect(!file.path(percentEncoded: false).hasPrefix(worktree.path(percentEncoded: false) + "/"))
        #expect(file.lastPathComponent == "42-aaaa1111.md")
        #expect(try String(contentsOf: file, encoding: .utf8) == "# zadání\n")
    }

    /// Složka pod souborem nemusí existovat — zadání se ukládá i tehdy, když strom ještě
    /// nevznikl (v testech) nebo se mezitím uklidil.
    @Test("Chybějící složka se založí")
    func createsTheParentDirectory() throws {
        #expect(!FileManager.default.fileExists(atPath: layout.worktrees(of: pr.repo).path(percentEncoded: false)))

        let file = try store.save("x", for: pr, at: headSha)

        #expect(FileManager.default.fileExists(atPath: try #require(file).path(percentEncoded: false)))
    }

    /// `nil` znamená „nebylo co uložit“, ne „ulož prázdno“. Prázdný soubor by reviewera poslal
    /// čtením za nic a věta v promptu by na něj přesto ukazovala.
    @Test("Bez obsahu se nic nezakládá")
    func writesNothingWithoutABrief() throws {
        #expect(try store.save(nil, for: pr, at: headSha) == nil)
        #expect(!FileManager.default.fileExists(atPath: layout.intentFile(for: pr, at: headSha).path(percentEncoded: false)))
    }

    /// Druhý běh nad tímtéž commitem přepíše, ne přidá — a to i tehdy, když je nový obsah kratší.
    /// Zbytek starého zadání v souboru by byl nález o něčem, co v PR není.
    @Test("Nový zápis starý přepíše celý")
    func overwritesTheWholeFile() throws {
        try store.save("dlouhé původní zadání", for: pr, at: headSha)

        let file = try #require(try store.save("krátké", for: pr, at: headSha))

        #expect(try String(contentsOf: file, encoding: .utf8) == "krátké")
    }

    /// **Tvrdá podmínka č. 3**: aplikace pracuje výhradně ve své cache. Symlink v cestě umí zápis
    /// poslat mimo ni — a hlídá to tatáž kontrola, jaká už v repu je (`CacheEviction.insideCache`
    /// nad `CacheLayout.contains`), ne vlastní kopie.
    @Test("Zápis přes symlink ven z cache neprojde")
    func refusesToWriteOutsideTheCache() throws {
        let outside = try TemporaryDirectory()
        // `worktrees/cli/cli` je odkaz na složku mimo cache; zápis přes něj by skončil v ní.
        let repoRoot = layout.worktrees(of: pr.repo)
        try FileManager.default.createDirectory(
            at: repoRoot.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(at: repoRoot, withDestinationURL: outside.url)

        #expect(throws: CheckoutError.self) {
            try store.save("# zadání", for: pr, at: headSha)
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: outside.url.path(percentEncoded: false)).isEmpty)
    }

    /// Odkaz **na samotném souboru** `contains` nezachytí (rozbaluje symlinky na obou stranách),
    /// takže se musí odmítnout výslovně — tatáž kontrola, jakou u čtení mají `ReviewStore`
    /// i `ReviewDraftStore` (#106). Nález Copilota na #352.
    ///
    /// Změřeno, že na zápisu dnes nestojí nic: `write(to:options: .atomic)` odkaz **nahradí**
    /// souborem a cíl nechá být (bez `.atomic` by ho přepsal). Bezpečnost tedy visela na příznaku
    /// u zápisu, ne na vyjmenované kontrole — a to je slabší záruka.
    @Test("Zápis na místo, kde leží odkaz, neprojde")
    func refusesToWriteThroughASymbolicLinkFile() throws {
        let outside = try TemporaryDirectory()
        let victim = outside.url.appending(path: "mimo-cache.md")
        try Data("PŮVODNÍ".utf8).write(to: victim)
        try FileManager.default.createDirectory(
            at: layout.worktrees(of: pr.repo),
            withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(
            at: layout.intentFile(for: pr, at: headSha),
            withDestinationURL: victim
        )

        #expect(throws: CheckoutError.self) {
            try store.save("# zadání", for: pr, at: headSha)
        }
        #expect(try String(contentsOf: victim, encoding: .utf8) == "PŮVODNÍ")
    }

    // MARK: - Existující soubor pro `Zkopírovat příkaz`

    @Test("Bez uloženého zadání se cesta nevrátí")
    func reportsNoFileBeforeAnythingWasSaved() {
        #expect(store.existingFile(for: pr, at: headSha) == nil)
    }

    @Test("Uložené zadání se najde")
    func findsASavedFile() throws {
        let saved = try store.save("# zadání", for: pr, at: headSha)

        #expect(store.existingFile(for: pr, at: headSha) == saved)
    }

    /// Zadání je klíčované `(PR, headSha)`, takže po novém commitu **neplatí**. Vrátit ho i pro
    /// jinou hlavu by znamenalo příkaz, který posílá reviewera na zadání proti jinému kódu — je to
    /// tatáž hranice, jakou hlídá klíčování nálezů.
    @Test("Zadání jiného commitu se nevydá")
    func doesNotServeTheIntentOfAnotherHead() throws {
        try store.save("# zadání", for: pr, at: headSha)

        #expect(store.existingFile(for: pr, at: "cccc3333") == nil)
    }

    /// A ani zadání jiného PR — čísla PR se mezi repozitáři opakují a `421-` není `42-`.
    @Test("Zadání jiného PR se nevydá")
    func doesNotServeTheIntentOfAnotherPullRequest() throws {
        try store.save("# zadání", for: pr, at: headSha)

        let other = PRIdentifier(repo: pr.repo, number: 421)
        #expect(store.existingFile(for: other, at: headSha) == nil)
    }

    /// **Nejcennější tvrzení téhle sady.** Vrácená cesta jde do promptu a reviewer ji otevře
    /// `Read`em, takže odkaz by session poslal čtením **mimo cache aplikace** — a to je tvrdá
    /// podmínka č. 3. Nález Copilota na #352.
    @Test("Odkaz místo zadání se jako zadání nevydá")
    func neverServesASymbolicLink() throws {
        let outside = try TemporaryDirectory()
        let secret = outside.url.appending(path: "cizi-soubor.md")
        try Data("cizí obsah".utf8).write(to: secret)
        try FileManager.default.createDirectory(
            at: layout.worktrees(of: pr.repo),
            withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(
            at: layout.intentFile(for: pr, at: headSha),
            withDestinationURL: secret
        )

        #expect(store.existingFile(for: pr, at: headSha) == nil)
    }
}
