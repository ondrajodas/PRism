import Foundation
import Testing

@testable import PRism

/// Přehrání commitů nad základem (#466) proti **skutečnému `gitu`** a skutečnému repozitáři na
/// disku — bez sítě, remote je `file://`.
///
/// Fake runner ověří, jaké argumenty se posílají; tohle ověří, že jim `git` rozumí a že z toho
/// vypadne to, co se čeká. Ta druhá půlka se namockovat nedá a zrovna u rebase je to podstatné:
/// **jak se pozná konflikt** a **kde leží rozdělaný rebase** jsou obojí věci, na kterých v tomhle
/// repu něco stojí, a obojí platí jen tehdy, když to `git` doopravdy tak dělá. Že `rebase-merge`
/// u pracovního stromu leží uvnitř klonu, ne ve stromě, je změřené — a bez tohohle testu by se to
/// dalo potichu rozbít.
///
/// **Nepushuje se tudy nic.** `RepoCheckout` je lokální modul (tvrdá podmínka č. 1) a `remote` je
/// složka na disku; do remote zapisuje jedině `BranchPushing`.
@Suite("Rebase proti skutečnému gitu")
struct RealBranchRebaseTests {
    /// Systémový `git`, ne `KnownPath.git`: tenhle test binárku skutečně spouští.
    private let git = URL(filePath: "/usr/bin/git")
    private let runner = SubprocessRunner()
    private let repo = RepoID(owner: "scratch", name: "sample")
    private let pr: PRIdentifier

    /// **Musí být uložená v suite**, ne lokální proměnná v testu — `TemporaryDirectory` se maže
    /// v `deinit` a umí složku smazat `gitu` pod rukama (viz `RealRepoCheckoutTests`).
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
            // `file://`, ne holá cesta: u holé cesty `git` partial filtr ignoruje a udělá klon
            // s hardlinky, takže by test nejel tou cestou kódu co aplikace.
            remote: { _ in self.origin.absoluteString }
        )
    }

    // MARK: - Bez konfliktu

    /// **Commity se přehrají a hlava se posune.** Zároveň se ověřuje, že se do stromu doopravdy
    /// dostal obsah z obou stran — bez toho by „rebase proběhl“ znamenalo jen „git skončil nulou“.
    @Test("Rebase bez konfliktu přehraje commity nad základem")
    func replaysCommitsOntoTheBase() async throws {
        try await makeScratchRepository()
        let feature = try await makeBranch("feature", file: "feature.txt", content: "moje\n")
        try await advanceMain(file: "main.txt", content: "cizí\n")

        let outcome = try await checkout().rebase(pr, at: feature, onto: "main")

        guard case .rebased(let rebased) = outcome else {
            Issue.record("čekal se rebase, přišlo \(outcome)")
            return
        }
        #expect(rebased.replayed == 1)
        #expect(rebased.headSha != feature)
        // Obsah z obou stran, tedy doopravdy přehráno — ne jen přepnuto na základ.
        #expect(FileManager.default.fileExists(atPath: rebased.worktree.appending(path: "feature.txt").path))
        #expect(FileManager.default.fileExists(atPath: rebased.worktree.appending(path: "main.txt").path))
        #expect(await checkout().rebaseInProgress(for: pr) == false)
    }

    /// **Strom pro srovnání není strom pro review** (`CacheLayout.syncWorktree`). Rebase posune
    /// `HEAD` pryč z `headSha` — a strom review je právě ten kód, proti kterému nálezy vznikly
    /// a ve kterém stojí shell v zásuvce (#459).
    @Test("Rebase nesáhne na strom, ve kterém běželo review")
    func leavesTheReviewWorktreeAlone() async throws {
        try await makeScratchRepository()
        let feature = try await makeBranch("feature", file: "feature.txt", content: "moje\n")
        try await advanceMain(file: "main.txt", content: "cizí\n")
        let checkout = checkout()
        let review = try await checkout.worktree(for: pr, at: feature)

        let outcome = try await checkout.rebase(pr, at: feature, onto: "main")

        guard case .rebased(let rebased) = outcome else {
            Issue.record("čekal se rebase, přišlo \(outcome)")
            return
        }
        #expect(rebased.worktree != review)
        // Nálezy platí proti `headSha` (tvrdá podmínka č. 5), takže strom review musí zůstat
        // stát přesně tam, kde byl.
        #expect(try await revision("HEAD", in: review) == feature)
    }

    /// Větev, která už nad základem je: `git` nemá co přehrát a hlava zůstane. Store z toho dělá
    /// `alreadyInSync` a **nepushuje** — tady se ověřuje ta půlka, která je na `gitu`.
    @Test("Srovnaná větev vydá tutéž hlavu")
    func keepsTheHeadWhenNothingToReplay() async throws {
        try await makeScratchRepository()
        let feature = try await makeBranch("feature", file: "feature.txt", content: "moje\n")

        let outcome = try await checkout().rebase(pr, at: feature, onto: "main")

        guard case .rebased(let rebased) = outcome else {
            Issue.record("čekal se rebase, přišlo \(outcome)")
            return
        }
        #expect(rebased.headSha == feature)
    }

    // MARK: - Konflikt

    /// **Konflikt je návratová hodnota, ne chyba** — a jména kolidujících souborů se doopravdy
    /// zjistí. Rebase se přitom zahodí, takže v cache po něm nic nezůstane.
    @Test("Konflikt vydá jména souborů a rebase se zahodí")
    func reportsConflictingFilesAndAborts() async throws {
        try await makeScratchRepository()
        let feature = try await makeBranch("feature", file: "README.md", content: "moje verze\n")
        try await advanceMain(file: "README.md", content: "cizí verze\n")

        let outcome = try await checkout().rebase(pr, at: feature, onto: "main")

        #expect(outcome == .conflicted(files: ["README.md"], aborted: true))
        // Zahozený rebase znamená, že se v tom stromě dá hned pracovat dál.
        #expect(await checkout().rebaseInProgress(for: pr) == false)
    }

    /// **Rozdělaný rebase se najde a nepřepíše se.**
    ///
    /// Tři tvrzení v jednom, protože jsou to tři kroky jednoho stavu: že se pozná (a to je ta
    /// změřená věc — `rebase-merge` leží u pracovního stromu **uvnitř klonu**, takže dotaz
    /// `FileManageru` na `<strom>/.git/rebase-merge` by vyšel prázdný), že ho druhý pokus
    /// **nezahodí** (je to rozdělaná práce, o které rozhoduje člověk) a že ho `discardRebase`
    /// ukliší.
    @Test("Rozdělaný rebase se najde, nepřepíše a jde zahodit")
    func findsAnUnfinishedRebaseAndDiscardsIt() async throws {
        try await makeScratchRepository()
        let feature = try await makeBranch("feature", file: "README.md", content: "moje verze\n")
        try await advanceMain(file: "README.md", content: "cizí verze\n")
        let checkout = checkout()
        // První pokus si strom založí a rebase zahodí; druhý ho pak najde rozdělaný.
        _ = try await checkout.rebase(pr, at: feature, onto: "main")
        try await startConflictingRebase(in: layout.syncWorktree(for: pr))

        #expect(await checkout.rebaseInProgress(for: pr))

        let outcome = try await checkout.rebase(pr, at: feature, onto: "main")

        #expect(outcome == .conflicted(files: ["README.md"], aborted: false))
        // **Nepřepsal se**: druhý pokus rozdělanou práci nechal ležet.
        #expect(await checkout.rebaseInProgress(for: pr))

        try await checkout.discardRebase(for: pr)

        #expect(await checkout.rebaseInProgress(for: pr) == false)
    }

    /// Zahození bez rozdělaného rebase **není chyba** — na remote se nesáhlo, takže není co
    /// vracet. Kdyby to házelo, po každém úspěšném srovnání by v panelu stála hláška o selhání.
    @Test("Zahození bez rebase projde a nic nerozbije")
    func discardingWithoutARebaseIsNotAnError() async throws {
        try await makeScratchRepository()
        let checkout = checkout()

        try await checkout.discardRebase(for: pr)

        #expect(await checkout.rebaseInProgress(for: pr) == false)
    }

    /// **Neznámý základ je chyba, ne konflikt.** `git` skončí nenulově v obou případech, takže
    /// kdyby se rozhodovalo podle návratového kódu, hlásilo by okno „vyřeš konflikt“ nad překlepem
    /// v jméně větve.
    @Test("Neznámý základ skončí chybou, ne konfliktem")
    func unknownBaseIsAFailure() async throws {
        try await makeScratchRepository()
        let feature = try await makeBranch("feature", file: "feature.txt", content: "moje\n")

        await #expect(throws: CheckoutError.self) {
            _ = try await checkout().rebase(pr, at: feature, onto: "takova-vetev-neni")
        }
        #expect(await checkout().rebaseInProgress(for: pr) == false)
    }

    // MARK: - Scratch repozitář

    private func makeScratchRepository() async throws {
        try FileManager.default.createDirectory(at: origin, withIntermediateDirectories: true)
        try await git(["init", "--initial-branch=main"], in: origin)
        try await git(["config", "user.email", "test@example.com"], in: origin)
        try await git(["config", "user.name", "Test"], in: origin)
        try "základ\n".write(to: origin.appending(path: "README.md"), atomically: true, encoding: .utf8)
        try await git(["add", "README.md"], in: origin)
        try await git(["commit", "-m", "první"], in: origin)
    }

    /// Větev s jedním vlastním commitem, odbočená z aktuální hlavy `mainu`. Vrací se její hlava —
    /// to je `headSha` pull requestu.
    private func makeBranch(_ name: String, file: String, content: String) async throws -> String {
        try await git(["checkout", "-b", name], in: origin)
        try content.write(to: origin.appending(path: file), atomically: true, encoding: .utf8)
        try await git(["add", file], in: origin)
        try await git(["commit", "-m", "na větvi"], in: origin)
        let head = try await revision("HEAD", in: origin)
        // Zpátky na `main`, aby se dal posunout — jinak by commit přibyl na větvi.
        try await git(["checkout", "main"], in: origin)
        return head
    }

    private func advanceMain(file: String, content: String) async throws {
        try content.write(to: origin.appending(path: file), atomically: true, encoding: .utf8)
        try await git(["add", file], in: origin)
        try await git(["commit", "-m", "na mainu"], in: origin)
    }

    /// Rozdělaný rebase **naostro**: rozjede se tentýž konfliktní rebase, jaký by rozjela
    /// aplikace, a nechá se stát. Nasimulovat ho vyrobením složky `rebase-merge` by znamenalo
    /// testovat vlastní domněnku o tom, jak to `git` dělá.
    private func startConflictingRebase(in worktree: URL) async throws {
        let result = try await runner.run(
            git,
            arguments: ["-C", worktree.path(percentEncoded: false), "rebase", "refs/heads/main"],
            environment: ["GIT_TERMINAL_PROMPT": "0", "GIT_EDITOR": "true"],
            timeout: .seconds(30)
        )
        #expect(result.exitCode != 0, "rebase měl uváznout na konfliktu")
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
