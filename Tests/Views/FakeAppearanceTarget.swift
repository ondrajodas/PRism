@testable import PRism

/// Cíl vzhledu, který nic nepřebarvuje — zapíše si, co po něm kdo chtěl (#278).
///
/// Existuje proto, že živý cíl je `NSApp`, tedy v testech **hostitel testů**: vynucený režim by
/// z jednoho testu přetekl do render sond, které si režim nastavují samy, a ty by pak měřily něco
/// jiného, než o co si řekly.
///
/// Vlastní soubor, ne přírůstek do jedné ze suit: ptá se na něj `AppAppearanceTests` (mapování)
/// i `AppStoreAppearanceTests` (cesta konfigurace do aplikace).
@MainActor
final class FakeAppearanceTarget: AppearanceApplying {
    /// Co se nastavovalo, v pořadí. Na tomhle seznamu stojí i tvrzení, že se nenastavilo **nic**.
    private(set) var applied: [AppearanceMode] = []

    func applyAppearance(_ mode: AppearanceMode) {
        applied.append(mode)
    }
}
