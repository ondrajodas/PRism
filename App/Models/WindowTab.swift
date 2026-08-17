import Foundation

/// Co je zrovna v hlavní ploše okna (#180).
///
/// Do #180 mělo okno jediné rozvržení: seznam PR vlevo, detail vybraného vpravo. Rozdělané review
/// tím bylo **neviditelné, dokud se na PR neklikne** — a to je zrovna ta věc, kterou má člověk mít
/// před očima, protože se na ni zapomíná. Otevřená review jsou proto záložky.
enum WindowTab: Hashable, Sendable {
    /// Domácí záložka — obsah si vybírá rail vlevo.
    case home
    /// Otevřené review konkrétního PR.
    case pullRequest(PRIdentifier)

    var pullRequest: PRIdentifier? {
        guard case .pullRequest(let id) = self else { return nil }
        return id
    }
}

/// Sekce railu — co je vidět v domácí záložce (#180).
///
/// **Jen položky, které mají obsah.** Návrh jich kreslí sedm (přehled, fronta, moje PR,
/// rozdělaná, historie, zdraví, nastavení); tady jsou čtyři, protože položka, po jejímž otevření
/// je prázdno, je horší než položka, která ještě není. `Historie` a `Zdraví` potřebují napřed
/// obsah, který v aplikaci zatím nikde není — `Přehled` přibyl s dashboardem (#181),
/// `Moje PR` s rozřazením podle autora (#331).
///
/// **Pořadí případů je pořadí položek v railu** a rail je kreslí z `allCases`, takže `mine` leží
/// mezi `queue` a `drafts` schválně: dolů přichází, co mám zrevidovat, nahoru jde, co posílám ven
/// — a rozdělaná práce je až to, co jsem si u toho nechal nedopsané.
enum RailSection: String, CaseIterable, Identifiable, Sendable {
    /// Dashboard — co dneska hoří (#181).
    case overview
    /// Fronta — seznam PR, na které se čeká.
    case queue
    /// Moje pull requesty (#331) — druhá fronta, ne filtr v té první.
    case mine
    /// PR, na kterých leží rozdělané review.
    case drafts

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "Přehled"
        case .queue: "Fronta"
        case .mine: "Moje PR"
        case .drafts: "Rozdělaná"
        }
    }

    var symbol: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .queue: "tray.full"
        // Návrh kreslí holou šipku nahoru (`↑`) a smysl je v jejím **směru**: dolů přichází, co
        // mám zrevidovat, nahoru jde, co posílám ven. Šipka sama by v railu vypadala jako
        // ovládání scrollování, takže zůstává v téže rodině jako fronta (`tray.full`) — je to
        // tatáž volnost, s jakou se za `⌂` bere `square.grid.2x2`.
        case .mine: "tray.and.arrow.up"
        case .drafts: "square.and.pencil"
        }
    }

    /// Co se ukáže, když v sekci nic není. Věta na sekci, ne jedna společná: prázdná fronta
    /// znamená „hotovo“, kdežto prázdná rozdělaná znamená „nic jsi nezačal“ — a to je dobře.
    ///
    /// U `Moje PR` je to **jen jeden ze tří důvodů**, proč tam nic není (#331): chybějící zdroj
    /// a nenačtený login mají vlastní věty, protože „nic otevřeného nemáš“ by nad nenastavenou
    /// aplikací lhalo. Rozhoduje o tom `Policy.ownListEmptyReason(…)`.
    var emptyExplanation: String {
        switch self {
        case .overview: "Až se načte fronta, uvidíš tady, co je potřeba."
        case .queue: "Až po tobě někdo bude chtít review, objeví se tady."
        case .mine: "Až otevřeš vlastní pull request, objeví se tady."
        case .drafts: "Rozdělané review vzniká psaním do panelu u PR. Zatím žádné neleží."
        }
    }
}
