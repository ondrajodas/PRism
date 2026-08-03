import Foundation

/// **Jediná cesta, kterou z aplikace něco odejde na GitHub.**
///
/// Do #67 to vynucoval typ: `GitHubGateway` schválně neměl metodu, kterou by šlo něco
/// odeslat. Ta vlastnost **zůstává** — zápis dostal vlastní modul, takže polling, diff,
/// checkout ani reviewer nemají čím něco poslat. `grep ReviewPublishing` vyjmenuje všechna
/// místa, odkud to jde; má jich být jedno.
///
/// Protokol má jednu metodu schválně. Cokoli dalšího (komentář, approve mimo review, label)
/// by byla druhá cesta ven — a pravidlo, které nahradilo tvrdou podmínku č. 1, stojí na tom,
/// že je jedna.
protocol ReviewPublishing: Sendable {
    /// Odešle rozdělané review. Vrací to, co GitHub potvrdil, ne to, co jsme poslali —
    /// z odpovědi je vidět, jak review doopravdy dopadlo.
    ///
    /// Před voláním si ověří, že repo je v `PublishScope`, že draft míří na aktuální hlavu
    /// PR a že je PR otevřený. **Při neshodě se nevolá nic.**
    func submit(_ draft: ReviewDraft) async throws -> SubmittedReview
}
