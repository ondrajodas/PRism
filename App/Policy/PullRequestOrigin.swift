import Foundation

/// Odkud se pull request v okně vzal (#531).
///
/// **Výčet, ne `Bool`**, a je to tatáž úvaha jako u `PullRequestOwnership`: obě odpovědi mají
/// jméno, takže se dají číst v podmínce i v testu bez toho, aby si čtenář pamatoval, co znamená
/// `true`. A hlavně je to místo, kam patří ta věta, kvůli které výčet vznikl — **frontu definují
/// zdroje** (#4), takže PR mimo ně není ve frontě, na kartách, v odznaku ani v automatu.
enum PullRequestOrigin: Hashable, Sendable {
    /// Přišel ze zdrojů, tedy z vyhledávacích dotazů v nastavení. Chová se jako každý jiný.
    case sources
    /// Otevřel ho člověk odkazem, paletou nebo `prism://` — ve zdrojích není a nedostane se do
    /// fronty. Hlavička to říká pilulkou.
    case outsideSources
}

extension Policy {
    /// Odkud je otevřený pull request.
    ///
    /// **Rozhoduje o tom, co je v seznamu teď**, ne o tom, jak se záložka otevřela: PR otevřený
    /// odkazem, na kterém si mezitím někdo vyžádal moje review, přijde do fronty přes zdroje —
    /// a pilulka `mimo zdroje` na něm musí zmizet, protože už by lhala. Obráceně to platí taky:
    /// PR, který ze zdrojů vypadl, se z otevřené záložky nedá dočíst jinak než jako `mimo zdroje`.
    ///
    /// - Parameters:
    ///   - adopted: přijaté záložky a **proč** (`AppStore.adoptedTabs`). Bez nich by
    ///     se pilulka objevila u **každého** PR, který zrovna vypadl z tiku — a to je stav, který
    ///     má okno hlásit větou „pull request zmizel ze seznamu“, ne pilulkou.
    ///
    ///     **Pilulku dostane jedině `link`** (#527): obnovená záložka běží před prvním tikem, kdy
    ///     je `sources` prázdné, takže by `mimo zdroje` bliklo u všech — a u těch, které z fronty
    ///     doopravdy vypadly, by tvrdilo „otevřel jsi ho odkazem“, což není pravda. Viz
    ///     `TabAdoption.restored`.
    ///   - sources: identifikátory z posledního tiku (`AppStore.pullRequests`).
    static func origin(
        of pullRequest: PRIdentifier,
        adopted: [PRIdentifier: TabAdoption],
        sources: Set<PRIdentifier>
    ) -> PullRequestOrigin {
        if sources.contains(pullRequest) { return .sources }
        return adopted[pullRequest] == .link ? .outsideSources : .sources
    }

    /// Odkud je pull request, o kterém se ví **jenom adresa** — tedy na řádku `Odkaz` v paletě.
    ///
    /// **Jiná otázka než u pilulky, proto jiná funkce.** Pilulka odpovídá na „odkud se tahle
    /// záložka vzala“, takže u PR, který nikdo odkazem neotevřel, vychází `sources` (viz výš).
    /// Vložený odkaz se ale ptá na „je tenhle pull request v mých zdrojích **teď**“, a tam je
    /// u neznámého PR správná odpověď `outsideSources` — jinak by řádek `Odkaz` u cizího repa
    /// tvrdil `je ve tvých zdrojích` a člověk by čekal, že ho najde ve frontě.
    ///
    /// Značka otevřených záložek se sem proto **nepředává**: to, že už je ten PR otevřený, na
    /// odpovědi nic nemění.
    static func linkOrigin(of pullRequest: PRIdentifier, sources: Set<PRIdentifier>) -> PullRequestOrigin {
        sources.contains(pullRequest) ? .sources : .outsideSources
    }

    /// Text pilulky v hlavičce (`.pill.idle` ze sekce 41 návrhu). `nil` = nekreslí se nic.
    ///
    /// **U PR ze zdrojů se nekreslí nic**, ne pilulka „ze zdrojů“: hlavička by nesla údaj, který
    /// platí u devadesáti devíti procent záložek, tedy šum. Je to tatáž úvaha, jakou má vedle
    /// stojící `moje PR` (#334) — pojmenovává se odchylka, ne pravidlo.
    static func originNote(_ origin: PullRequestOrigin) -> String? {
        switch origin {
        case .sources: nil
        // Dvě věty v jedné kapsli schválně: `mimo zdroje` říká, **proč** tu pilulka je,
        // `jen ke čtení` říká, **co z toho plyne** — a to druhé je ta část, kvůli které se člověk
        // nemusí ptát, jestli PR čeká na jeho review.
        case .outsideSources: "mimo zdroje · jen ke čtení"
        }
    }
}
