import Foundation

/// Čísla o pull requestu do dlaždic v `Přehledu` (#198).
///
/// Nic se pro ně nedotahuje — jsou to údaje, které v okně **už jsou**: diff, časová osa,
/// hlava PR a sha, proti které platí nálezy. Dlaždice je jen sesbírá na jedno místo, protože
/// dneska jsou roztroušené po hlavičce a po liště nad diffem.
struct PullRequestFacts: Hashable, Sendable {
    /// Jedna dlaždice: popisek, hodnota a případný dovětek drobným písmem.
    struct Tile: Hashable, Sendable, Identifiable {
        let caption: String
        let value: String
        var note: String?
        /// Sha se sází mono — je to identifikátor, ne množství.
        var isMonospaced = false
        /// Zvýrazněná hodnota (zastaralá sha). `nil` = obyčejná.
        var isStale = false

        var id: String { caption }
    }

    let tiles: [Tile]

    var isEmpty: Bool { tiles.isEmpty }
}

extension Policy {
    /// Dlaždice pro `Přehled` (#198).
    ///
    /// **Dlaždice, o které se nedá nic říct, se nekreslí.** Řádek plný nul je řádek, ve kterém
    /// se ztratí to jedno číslo, na kterém záleží — tatáž úvaha jako u souhrnu fronty (#155).
    /// Proto se vynechává počet commitů, dokud se nenačte konverzace, i počet souborů, dokud
    /// nedorazí diff: nula by tvrdila, že PR nic nemění.
    static func facts(
        commits: Int,
        newCommits: Int,
        files: Int,
        filesWithFindings: Int,
        areCommitsExact: Bool,
        headSha: String?,
        findingsHeadSha: String?
    ) -> PullRequestFacts {
        var tiles: [PullRequestFacts.Tile] = []

        // Utnutá stránka událostí znamená, že přesný počet commitů **neznáme** — a číslo, které
        // je „aspoň tolik“, se do dlaždice bez značky nevejde. Radši žádná dlaždice než menší
        // číslo vydávané za úplné (nález Copilota na #198).
        if commits > 0, areCommitsExact {
            tiles.append(
                .init(
                    caption: "Commity",
                    value: "\(commits)",
                    // Kolik z nich je nových od minule (#173) — jen když nějaké jsou.
                    note: newCommits > 0 ? "\(newCommits) nové" : nil
                )
            )
        }
        if files > 0 {
            tiles.append(
                .init(
                    caption: "Soubory",
                    value: "\(files)",
                    note: filesWithFindings > 0 ? "\(filesWithFindings) s nálezem" : nil
                )
            )
        }
        if let headSha {
            tiles.append(.init(caption: "Hlava", value: short(headSha), isMonospaced: true))
        }
        // **Dlaždice je vždycky, když nálezy jsou** — návrh ji tak kreslí a rozchod nese
        // **barva**, ne přítomnost. Do #198 jsem ji při shodě schovával podle vlastní úvahy
        // („shodná sha nikoho nezajímá“), jenže tím z řádku zmizel údaj, který k němu patří:
        // proti čemu nálezy platí, je fakt o PR i tehdy, když se to shoduje.
        if let findingsHeadSha {
            tiles.append(
                .init(
                    caption: "Nálezy proti",
                    value: short(findingsHeadSha),
                    isMonospaced: true,
                    // Žlutá jedině při rozchodu — tam je to důvod, proč nálezy neplatí
                    // (tvrdá podmínka č. 5).
                    isStale: findingsHeadSha != headSha
                )
            )
        }
        return PullRequestFacts(tiles: tiles)
    }

    /// Sha na sedm znaků, jako všude jinde v okně.
    private static func short(_ sha: String) -> String { String(sha.prefix(7)) }
}
