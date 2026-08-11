import SwiftUI

/// Jak vypadá stav pull requestu — ikona a barva na jednom místě.
///
/// Vlastní typ ze stejného důvodu jako `ReviewStateAppearance`: od #184 tutéž dvojici potřebují
/// **dvě** místa — řádek seznamu a řádek command palette. Dvě kopie `switch`e nad
/// `PullRequestState` by se rozešly a v paletě by pak zelenala jiná věc než v seznamu.
///
/// Barvy jsou **sémantické systémové**, ne hexy z návrhu, a to schválně: takhle to v seznamu
/// bylo od začátku a paleta má mluvit jeho jazykem, ne si zavést druhý.
///
/// Je to stav **pull requestu**, ne review, a ty dva se nesmí slít: PR může být otevřený
/// a review nad ním selhané zároveň. Stav review kreslí `ReviewStateAppearance`.
enum PullRequestStateAppearance {
    /// Ikona je pro všechny stavy **tatáž** — rozdíl nese barva a v seznamu ještě slovo `draft`.
    /// Tvar „pull request“ je jeden; kdyby se měnil, znamenal by druhou věc.
    static let symbol = "arrow.triangle.pull"

    static func color(of state: PullRequestState) -> Color {
        switch state {
        case .open: .green
        case .draft: .secondary
        case .merged: .purple
        case .closed: .red
        }
    }
}
