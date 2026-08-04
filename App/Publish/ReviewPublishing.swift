import Foundation

/// **Jediná cesta, kterou z aplikace něco odejde na GitHub.**
///
/// Do #67 to vynucoval typ: `GitHubGateway` schválně neměl metodu, kterou by šlo něco
/// odeslat. Ta vlastnost **zůstává** — zápis dostal vlastní modul, takže polling, diff,
/// checkout ani reviewer nemají čím něco poslat. `grep ReviewPublishing` vyjmenuje všechna
/// místa, odkud to jde; má jich být jedno.
///
/// Metody jsou **vyjmenované a jsou tři** (do #73 jedna). Každá odpovídá jedné věci, kterou
/// člověk v okně udělá — odeslat review, odpovědět do vlákna, přepnout jeho vyřešení — a nic
/// dalšího tady být nesmí: approve mimo review, label ani komentář pod PR by byly cesty ven,
/// o kterých okno nemluví. Roste-li tenhle výčet, roste to, co aplikace umí odeslat, a to má
/// být vidět v jednom souboru.
///
/// **Každá metoda si sama ověří bránu `PublishScope`** — proto všechny berou adresu, ze které
/// se dá zjistit repo. Kdyby ji jedna z nich brát nemusela, existovala by cesta ven, která se
/// nedá zakázat v nastavení.
protocol ReviewPublishing: Sendable {
    /// Odešle rozdělané review. Vrací to, co GitHub potvrdil, ne to, co jsme poslali —
    /// z odpovědi je vidět, jak review doopravdy dopadlo.
    ///
    /// Před voláním si ověří, že repo je v `PublishScope`, že draft míří na aktuální hlavu
    /// PR a že je PR otevřený. **Při neshodě se nevolá nic.**
    func submit(_ draft: ReviewDraft) async throws -> SubmittedReview

    /// Odpoví do existujícího vlákna. Vrací komentář, jak ho potvrdil GitHub, takže se dá
    /// vložit do konverzace bez dalšího čtení.
    ///
    /// Pre-flight je **užší než u review**: ověřuje se scope a stav PR, ne `headSha`. Odpověď
    /// se váže na vlákno, ne na commit — odpovědět kolegovi na vlákno, které vzniklo před třemi
    /// pushi, je běžné, takže kontrola hlavy by zakazovala zrovna to, na co se odpovídá.
    /// Prázdné tělo se **neodesílá**: GitHub ho tiše spolkne (změřeno v sandboxu).
    func reply(to thread: ThreadTarget, body: String) async throws -> ThreadComment

    /// Označí vlákno za vyřešené, nebo ho otevře zpátky. Vrací stav i práva, jak je přepočítal
    /// GitHub.
    func setResolved(_ resolved: Bool, of thread: ThreadTarget) async throws -> ThreadResolution
}
