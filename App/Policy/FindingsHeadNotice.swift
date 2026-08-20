import Foundation

/// Proti kterému kódu nálezy v panelu platí (#392).
///
/// Od #392 je panel i v tabu `Commity`, a tím vzniká situace, kterou do té doby nešlo mít: vedle
/// nálezů stojí **jiný commit, než na kterém nálezy vznikly**. Nálezy jsou klíčované `headSha`
/// (tvrdá podmínka č. 5), takže o kódu na obrazovce nemluví.
///
/// **Podmínka se tím neobchází, stává se z ní věta v UI.** Nálezy se nekreslí proti kódu, který
/// neexistuje — jen je u nich napsané, ke kterému kódu patří. Ve zbylých třech tabech s panelem
/// (`Přehled`, `Změněné soubory`, `Konverzace`) je vedle panelu vždycky hlava PR, takže tam není
/// co vysvětlovat a věta by byla šum na každé obrazovce.
extension Policy {
    enum FindingsHeadNotice: Hashable, Sendable {
        /// Nic se nekreslí — nálezy platí pro to, co je vedle nich.
        case none
        /// Klidná věta: nálezy jsou proti téhle hlavě.
        case head(String)
        /// Výstraha: na obrazovce je jiný commit než ten, ke kterému nálezy patří.
        case mismatch(head: String, commit: String)

        /// Mají se karty nálezů ztlumit? **Jen u neshody** — u klidné věty by ztlumení tvrdilo,
        /// že s nálezy něco není v pořádku.
        var dimsFindings: Bool {
            if case .mismatch = self { true } else { false }
        }

        /// Věta, kterou uvidí člověk. `nil` = nekreslí se nic.
        ///
        /// **Text patří sem, ne do view**, ze stejného důvodu jako `PullRequestState.czechLabel`:
        /// je to jediná věta, ze které se pozná, ke kterému kódu nálezy patří, takže se testuje
        /// tam, kde se rozhoduje — a ne odečítáním pixelů. Sha se krátí na sedm znaků, jako
        /// všude jinde v okně.
        var czechSentence: String? {
            switch self {
            case .none:
                nil
            case .head(let head):
                "Nálezy jsou proti hlavě \(Self.short(head))."
            case .mismatch(let head, let commit):
                "Nálezy jsou proti hlavě \(Self.short(head)). Tenhle commit je \(Self.short(commit)), "
                    + "takže o kódu na obrazovce nemluví."
            }
        }

        /// Sedm znaků, jako `PullRequestCommit.shortSha`.
        private static func short(_ sha: String) -> String { String(sha.prefix(7)) }
    }

    /// Věta nad kartami nálezů.
    ///
    /// `findingsHead` je hlava, na které nálezy vznikly (`ReviewRecord.headSha`) — **ne** dnešní
    /// hlava PR: kdyby se brala z detailu, mluvila by věta o commitu, se kterým ty nálezy nemají
    /// nic společného. `openCommit` je rozkliknutý commit, `nil` znamená seznam.
    static func findingsHeadNotice(
        tab: PullRequestTab,
        findingsHead: String?,
        openCommit: String?,
        hasFindings: Bool
    ) -> FindingsHeadNotice {
        // Bez nálezů není co kvalifikovat — proč je prázdno, vysvětluje `FindingsEmptyReason`.
        guard hasFindings, let findingsHead else { return .none }
        // Jediný tab, ve kterém vedle panelu stojí něco jiného než hlava PR.
        guard tab == .commits else { return .none }
        guard let openCommit, openCommit != findingsHead else { return .head(findingsHead) }
        return .mismatch(head: findingsHead, commit: openCommit)
    }
}
