import Foundation
import Testing

@testable import PRism

/// Slévání konfliktů proti **skutečnému `gitu`** (#467) — bez sítě, remote je `file://`.
///
/// Fake ověří, co si store nechá zapsat; tohle ověří, že tomu `git` rozumí a že z toho vypadne to,
/// co se čeká. Ta druhá půlka se namockovat nedá a **zrovna u téhle akce je to celý základ**: že
/// značka v souboru nese i **základ** (`zdiff3`), že `git diff HEAD` nad **nesloučenou** cestou
/// vydá obyčejný dvoustranný diff, a že `rebase --continue` doběhne bez editoru zprávy. Kdyby
/// kterákoli z těch tří věcí platila jinak, session by dostala nečitelný vstup, potvrzení by
/// vypisovalo nesmysl, nebo by rebase visel do timeoutu.
///
/// **Nic se nepushuje.** `RepoCheckout` je lokální modul (tvrdá podmínka č. 1) a `remote` je složka
/// na disku.
@Suite("Slévání konfliktů proti skutečnému gitu")
struct RealConflictStagingTests {
    /// Systémový `git`, ne `KnownPath.git`: tenhle test binárku skutečně spouští.
    private let git = URL(filePath: "/usr/bin/git")
    private let runner = SubprocessRunner()
    private let repo = RepoID(owner: "scratch", name: "sample")
    private let pr: PRIdentifier

    /// **Musí být uložená v suite**, ne lokální proměnná v testu — `TemporaryDirectory` se maže
    /// v `deinit` a umí složku smazat `gitu` pod rukama.
    private let workspace: TemporaryDirectory
    private let origin: URL
    private let layout: CacheLayout

    init() throws {
        workspace = try TemporaryDirectory()
        origin = workspace.url.appending(path: "origin")
        layout = CacheLayout(root: workspace.url.appending(path: "cache"))
        pr = PRIdentifier(repo: repo, number: 42)
    }

    private func checkout() -> GitRepoCheckout {
        GitRepoCheckout(
            git: git,
            gh: URL(filePath: "/usr/bin/false"),
            layout: layout,
            runner: runner,
            remote: { _ in self.origin.absoluteString }
        )
    }

    // MARK: - Rebase se dá nechat stát

    /// **`keepingConflict: true` nechá rebase rozdělaný** — a je to podmínka, ne volba pohodlí:
    /// v zahozeném rebase nejsou v souborech žádné značky, takže by session neměla co slévat.
    @Test("Se keepingConflict zůstane rebase rozdělaný v cache")
    func keepsTheConflictInTheWorktree() async throws {
        try await makeScratchRepository()
        let feature = try await makeConflictingBranch()
        let checkout = checkout()

        let outcome = try await checkout.rebase(pr, at: feature, onto: "main", keepingConflict: true)

        #expect(
            outcome == .conflicted(
                files: ["README.md"],
                aborted: false,
                worktree: layout.syncWorktree(for: pr)
            )
        )
        #expect(await checkout.syncWorktreeState(for: pr, at: feature, onto: "main") == .unfinishedRebase)
    }

    /// **Značka nese i základ**, protože se rebase spouští s `merge.conflictStyle=zdiff3`.
    ///
    /// Je to ta věc, kvůli které session nepotřebuje `Bash` — bez základu by nešlo poznat, která
    /// strana co změnila, a `git show :1:soubor` si session spustit nemůže. Kdyby `zdiff3` z volání
    /// vypadl, tohle tvrzení spadne; v souboru by pak byly jen dvě strany.
    @Test("Konfliktní značka nese obě strany i základ")
    func conflictMarkerCarriesTheAncestor() async throws {
        try await makeScratchRepository()
        let feature = try await makeConflictingBranch()

        _ = try await checkout().rebase(pr, at: feature, onto: "main", keepingConflict: true)

        let text = try String(
            contentsOf: layout.syncWorktree(for: pr).appending(path: "README.md"),
            encoding: .utf8
        )
        #expect(text.contains("<<<<<<< HEAD"))
        #expect(text.contains("|||||||"))
        #expect(text.contains(">>>>>>>"))
        // Základ je ten původní text, tedy to, co se dá porovnat s oběma stranami.
        #expect(text.contains("základ"))
        #expect(text.contains("cizí verze"))
        #expect(text.contains("moje verze"))
    }

    // MARK: - Zápis do indexu a diff

    /// **Celá cesta naostro**: slití, zápis do indexu, diff a dokončení rebase.
    ///
    /// Tři věci se tady dají pokazit potichu a všechny tři jsou tvrzené:
    ///
    /// - **diff je obyčejný dvoustranný**, ne kombinovaný — `git diff HEAD` nad nesloučenou cestou
    ///   se dá číst jako diff (změřeno; kdyby vydal `++`/`+ -`, výpis v potvrzení by byl nečitelný);
    /// - **diff mluví jen o kolidujících souborech** — `--cached` po zápisu by přibral celý
    ///   přehrávaný commit (změřeno: přibyl v něm soubor, který nekolidoval);
    /// - **`rebase --continue` doběhne** a nezasekne se na editoru commit message.
    @Test("Slitý soubor se zapíše, vydá diff a rebase doběhne")
    func stagesTheResolutionAndFinishesTheRebase() async throws {
        try await makeScratchRepository()
        let feature = try await makeConflictingBranch(alsoAdding: "vedlejsi.txt")
        let checkout = checkout()
        _ = try await checkout.rebase(pr, at: feature, onto: "main", keepingConflict: true)
        let worktree = layout.syncWorktree(for: pr)
        // Tohle je práce session: napsat do souboru výsledek bez značek.
        try "cizí verze\nmoje verze\n".write(
            to: worktree.appending(path: "README.md"),
            atomically: true,
            encoding: .utf8
        )

        let staging = try await checkout.stageResolution(in: worktree, paths: ["README.md"])

        #expect(staging.unresolved.isEmpty)
        #expect(staging.diff.contains("+moje verze"))
        #expect(staging.diff.contains("README.md"))
        // **Jen kolidující soubor.** Soubor, který v tom commitu taky je a nekolidoval, do výpisu
        // „co z toho vzniklo“ nepatří — je to diff slití, ne diff commitu.
        #expect(!staging.diff.contains("vedlejsi.txt"))
        // A diff je čitelný jako diff: jedna strana `-`, druhá `+`, ne kombinovaný `++`.
        #expect(!staging.diff.contains("++moje"))

        let outcome = try await checkout.continueRebase(pr, at: feature, onto: "main", keepingConflict: true)

        guard case .rebased(let rebased) = outcome else {
            Issue.record("čekal se dokončený rebase, přišlo \(outcome)")
            return
        }
        #expect(rebased.replayed == 1)
        #expect(rebased.rebasedFrom == feature)
        // V cache leží srovnaná větev, ne rozdělaný rebase.
        #expect(await checkout.syncWorktreeState(for: pr, at: feature, onto: "main") == .rebased(rebased))
    }

    /// **Soubor se značkami se do indexu nezapíše** — a je to to nejcennější tvrzení téhle sady.
    /// `git add` by značky zanesl do commitu a `rebase --continue` by **prošel**: uhádané slití,
    /// které se pozná až buildem.
    @Test("Soubor se zbylými značkami se nezapisuje")
    func refusesToStageLeftoverMarkers() async throws {
        try await makeScratchRepository()
        let feature = try await makeConflictingBranch()
        let checkout = checkout()
        _ = try await checkout.rebase(pr, at: feature, onto: "main", keepingConflict: true)
        let worktree = layout.syncWorktree(for: pr)

        // Session soubor „vyřešila“ tak, že v něm značky nechala.
        let staging = try await checkout.stageResolution(in: worktree, paths: ["README.md"])

        #expect(staging.unresolved == ["README.md"])
        #expect(staging.diff.isEmpty)
        // **Rebase pořád stojí**, takže se dá zahodit nebo dokončit v terminálu.
        #expect(await checkout.syncWorktreeState(for: pr, at: feature, onto: "main") == .unfinishedRebase)
    }

    /// **Jeden soubor se značkami nezablokuje ostatní.** Zapíše se, co je hotové, a řekne se, co
    /// není — jinak by session, která slila tři soubory ze čtyř, přišla o celou práci.
    @Test("Zapíše se, co je hotové, a řekne se, co ne")
    func stagesCleanFilesAndReportsTheRest() async throws {
        try await makeScratchRepository()
        let feature = try await makeTwoFileConflict()
        let checkout = checkout()
        _ = try await checkout.rebase(pr, at: feature, onto: "main", keepingConflict: true)
        let worktree = layout.syncWorktree(for: pr)
        try "slito\n".write(to: worktree.appending(path: "a.txt"), atomically: true, encoding: .utf8)

        let staging = try await checkout.stageResolution(in: worktree, paths: ["a.txt", "b.txt"])

        #expect(staging.unresolved == ["b.txt"])
        #expect(staging.diff.contains("a.txt"))
        #expect(!staging.diff.contains("b.txt"))
    }

    /// **Prázdný seznam není chyba** — je to stav „session nesáhla na nic“, a `git add` bez cest by
    /// jinak skončil chybou o chybějícím argumentu.
    @Test("Bez souborů se nic nezapisuje a nic nespadne")
    func emptyPathsDoNothing() async throws {
        try await makeScratchRepository()
        let feature = try await makeConflictingBranch()
        let checkout = checkout()
        _ = try await checkout.rebase(pr, at: feature, onto: "main", keepingConflict: true)

        let staging = try await checkout.stageResolution(
            in: layout.syncWorktree(for: pr),
            paths: []
        )

        #expect(staging == ConflictStaging())
    }

    // MARK: - Scéna

    private func makeScratchRepository() async throws {
        try FileManager.default.createDirectory(at: origin, withIntermediateDirectories: true)
        try await git(["init", "--initial-branch=main"], in: origin)
        try await git(["config", "user.email", "test@example.com"], in: origin)
        try await git(["config", "user.name", "Test"], in: origin)
        try "základ\n".write(to: origin.appending(path: "README.md"), atomically: true, encoding: .utf8)
        try "puvodni\n".write(to: origin.appending(path: "a.txt"), atomically: true, encoding: .utf8)
        try "puvodni\n".write(to: origin.appending(path: "b.txt"), atomically: true, encoding: .utf8)
        try await git(["add", "."], in: origin)
        try await git(["commit", "-m", "první"], in: origin)
    }

    /// Větev, která si s `mainem` odporuje v `README.md`. Vrací hlavu větve — `headSha` pull
    /// requestu. `alsoAdding` přidá do téhož commitu soubor, který **nekoliduje**: na tom stojí
    /// tvrzení, že diff mluví jen o kolizi.
    private func makeConflictingBranch(alsoAdding extra: String? = nil) async throws -> String {
        try await git(["checkout", "-b", "feature"], in: origin)
        try "moje verze\n".write(to: origin.appending(path: "README.md"), atomically: true, encoding: .utf8)
        if let extra {
            try "vedlejsi\n".write(to: origin.appending(path: extra), atomically: true, encoding: .utf8)
        }
        try await git(["add", "."], in: origin)
        try await git(["commit", "-m", "na větvi"], in: origin)
        let head = try await revision("HEAD", in: origin)
        try await git(["checkout", "main"], in: origin)
        try "cizí verze\n".write(to: origin.appending(path: "README.md"), atomically: true, encoding: .utf8)
        try await git(["add", "README.md"], in: origin)
        try await git(["commit", "-m", "na mainu"], in: origin)
        return head
    }

    /// Konflikt ve **dvou** souborech naráz.
    private func makeTwoFileConflict() async throws -> String {
        try await git(["checkout", "-b", "feature"], in: origin)
        try "moje a\n".write(to: origin.appending(path: "a.txt"), atomically: true, encoding: .utf8)
        try "moje b\n".write(to: origin.appending(path: "b.txt"), atomically: true, encoding: .utf8)
        try await git(["add", "."], in: origin)
        try await git(["commit", "-m", "na větvi"], in: origin)
        let head = try await revision("HEAD", in: origin)
        try await git(["checkout", "main"], in: origin)
        try "cizí a\n".write(to: origin.appending(path: "a.txt"), atomically: true, encoding: .utf8)
        try "cizí b\n".write(to: origin.appending(path: "b.txt"), atomically: true, encoding: .utf8)
        try await git(["add", "."], in: origin)
        try await git(["commit", "-m", "na mainu"], in: origin)
        return head
    }

    private func revision(_ name: String, in url: URL) async throws -> String {
        let result = try await runner.run(
            git,
            arguments: ["-C", url.path(percentEncoded: false), "rev-parse", name],
            timeout: .seconds(30)
        )
        #expect(result.exitCode == 0, "git rev-parse: \(result.standardError)")
        return result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func git(_ arguments: [String], in url: URL) async throws {
        let result = try await runner.run(
            git,
            arguments: ["-C", url.path(percentEncoded: false)] + arguments,
            timeout: .seconds(30)
        )
        #expect(result.exitCode == 0, "git \(arguments.joined(separator: " ")): \(result.standardError)")
    }
}
