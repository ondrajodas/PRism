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
/// rozdělaná, historie, zdraví, nastavení); tady jich je pět, protože položka, po jejímž otevření
/// je prázdno, je horší než položka, která ještě není. `Zdraví` potřebuje napřed obsah, který
/// v aplikaci zatím nikde není — `Přehled` přibyl s dashboardem (#181), `Moje PR` s rozřazením
/// podle autora (#331) a `Dění` se záznamem toho, co proletělo jako notifikace (#414).
///
/// **Pořadí případů je pořadí položek v railu** a rail je kreslí z `allCases`, takže `mine` leží
/// mezi `queue` a `drafts` schválně: dolů přichází, co mám zrevidovat, nahoru jde, co posílám ven
/// — a rozdělaná práce je až to, co jsem si u toho nechal nedopsané. `Dění` je pátá a poslední,
/// jak to kreslí návrh (pátá ikona `◷` v railu od sekce 01): není o jednom PR ani o mojí frontě,
/// je to záznam, do kterého se chodí zpátky.
enum RailSection: String, CaseIterable, Identifiable, Sendable {
    /// Dashboard — co dneska hoří (#181).
    case overview
    /// Fronta — seznam PR, na které se čeká.
    case queue
    /// Moje pull requesty (#331) — druhá fronta, ne filtr v té první.
    case mine
    /// PR, na kterých leží rozdělané review.
    case drafts
    /// Dění (#414) — co se na pull requestech stalo, když jsem se nekoukal.
    ///
    /// **Nejmenuje se to `Novinky`**, i když se o tom tak mluvilo: `Novinky` je v aplikaci okno
    /// s release notes (`ReleaseNotesView`), tedy „co je nového v PRismu“. Tohle je „co se stalo
    /// na pull requestech“ a dvě různé věci pod jedním jménem se v paletě ⌘K nedají rozeznat.
    case activity

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "Přehled"
        case .queue: "Fronta"
        case .mine: "Moje PR"
        case .drafts: "Rozdělaná"
        case .activity: "Dění"
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
        // Návrh kreslí hodinový ciferník (`◷`) a smysl je v tom, že sekce mluví o **čase**:
        // je to jediná položka railu, která odpovídá na „co se stalo“, ne na „co je“.
        case .activity: "clock"
        }
    }

    /// Kreslí si sekce hlavičku sama?
    ///
    /// **Vlastnost sekce, ne `if` ve view** (#414). Do #414 se to ve `HomeView` psalo jako
    /// `railSection != .overview` na dvou místech, takže druhá sekce s vlastní hlavičkou by
    /// jedno z nich zapomněla — a nad nadpisem by zůstal prázdný pruh s linkou.
    var drawsOwnHeader: Bool {
        switch self {
        case .overview, .activity: true
        case .queue, .mine, .drafts: false
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
        case .activity: "Nový PR, výsledek review nebo cizí komentář se objeví tady."
        }
    }

    /// Nápověda u odkazu, který do sekce přepne — `Přepne do sekce Dění`.
    ///
    /// **Bydlí to na sekci, ne u odkazu** (dřív na `DashboardDestination`, který odešel s kartami
    /// v #515): dvě cesty do téže sekce mají mít i stejnou nápovědu. Čte to hlavička bloku `Dění`
    /// a jeho patka, tedy dvě místa nad jedním cílem.
    var switchHelp: String { "Přepne do sekce \(title)" }
}
