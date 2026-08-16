import Foundation
import Testing

@testable import PRism

/// Co si `PullRequestCommit` odvozuje sám (#316): první řádka zprávy a zkrácené sha.
///
/// Vypadá to jako dva `prefix`y, a přesně proto to má test: **první řádka není `components(
/// separatedBy: "\n").first`** — git píše konce řádků i jako `\r\n` a zpráva z GitHubu je ta, jakou
/// autor napsal, včetně čehokoli, co si do ní nalepil editor.
@Suite("Commit pull requestu")
struct PullRequestCommitTests {
    private func commit(_ message: String, sha: String = "abcdef0123456789") -> PullRequestCommit {
        PullRequestCommit(
            sha: sha,
            message: message,
            authorName: "Odin Uv",
            authorLogin: nil,
            avatarURL: nil,
            committedAt: nil,
            isMerge: false
        )
    }

    @Test("Z víceřádkové zprávy zbyde první řádka")
    func takesTheFirstLine() {
        #expect(commit("feat: něco\n\nDelší tělo.\nA další řádek.").subject == "feat: něco")
        #expect(commit("feat: něco").subject == "feat: něco")
    }

    /// `\r\n` je normální konec řádku v commitech psaných na Windows a ve zprávách, které projdou
    /// webovým editorem. Kdyby se hledalo jen `\n`, zbyl by na konci `\r` a řádek by končil
    /// neviditelným znakem, který se do sazby počítá.
    @Test("Windowsový konec řádku se do titulku nedostane")
    func handlesCarriageReturns() {
        #expect(commit("fix: cesta\r\n\r\ntělo").subject == "fix: cesta")
    }

    @Test("Prázdná zpráva dá prázdný titulek, ne vymyšlený")
    func doesNotInventASubject() {
        #expect(commit("").subject.isEmpty)
        #expect(commit("\n\ntělo bez titulku").subject.isEmpty)
    }

    @Test("Zkrácené sha má sedm znaků, jako git a GitHub")
    func shortensTheSha() {
        #expect(commit("x", sha: "abcdef0123456789").shortSha == "abcdef0")
        // Kratší sha se nedoplňuje — vypsat sedm znaků z pěti nejde a nula navíc by lhala.
        #expect(commit("x", sha: "abc").shortSha == "abc")
    }

    /// Identita je **celé sha**, ne zkrácené: dvě různá sha se stejnými sedmi znaky jsou vzácná,
    /// ale v `ForEach`i by se slila potichu.
    @Test("Řádek se klíčuje celým sha")
    func identifiesByTheFullSha() {
        #expect(commit("x", sha: "abcdef0111").id == "abcdef0111")
        #expect(commit("x", sha: "abcdef0111").id != commit("x", sha: "abcdef0222").id)
    }
}
