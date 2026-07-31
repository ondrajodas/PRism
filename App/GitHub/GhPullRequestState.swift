import Foundation

extension PullRequestState {
    /// Poskládá stav z toho, jak ho popisuje `gh` — dvěma poli a v každém příkazu jinak.
    ///
    /// `gh search prs` píše stav malými písmeny, `gh pr view` velkými; draft je vedle toho
    /// vlastní bool. Neznámý stav vrací `nil` — vymyslet si ho by znamenalo ukázat
    /// v seznamu odznak, který neodpovídá ničemu.
    init?(ghState raw: String, isDraft: Bool) {
        switch raw.lowercased() {
        case "open": self = isDraft ? .draft : .open
        case "merged": self = .merged
        case "closed": self = .closed
        default: return nil
        }
    }
}
