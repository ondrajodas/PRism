import Foundation

/// Služba, na které aplikace stojí, a kde se dá zjistit, jak jí je.
///
/// Sledují se **komponenty, ne celostránkový indikátor**. Oba provozovatelé jezdí na
/// Statuspage.io a vystavují komponenty zvlášť; incident v `Actions` nebo `Packages` se
/// téhle aplikace netýká, takže celostránkový `status.json` by lhal — svítil by na něco,
/// co nepoužíváme.
enum MonitoredService: String, CaseIterable, Sendable, Hashable {
    case github
    case claude

    var name: String {
        switch self {
        case .github: "GitHub"
        case .claude: "Claude"
        }
    }

    /// Jméno ve druhém pádě — české věty ho potřebují („stav GitHubu“) a skloňovat řetězec
    /// za běhu nejde. `Claude` je nesklonné, takže se druhý pád od prvního neliší; shodou
    /// okolností je u obou stejný i šestý pád („o GitHubu“, „o Claude“).
    var nameInGenitive: String {
        switch self {
        case .github: "GitHubu"
        case .claude: "Claude"
        }
    }

    /// Kde leží stav komponent.
    ///
    /// U Claude se používá **`status.claude.com`**, ne `status.anthropic.com`: ta adresa už
    /// jen přesměrovává a spoléhat se na redirect znamená mít v aplikaci závislost na tom,
    /// že ho někdo bude udržovat.
    var componentsURL: URL {
        switch self {
        case .github: URL(string: "https://www.githubstatus.com/api/v2/components.json")!
        case .claude: URL(string: "https://status.claude.com/api/v2/components.json")!
        }
    }

    /// Komponenty, na kterých téhle aplikaci záleží — přesnými jmény ze status page.
    ///
    /// GitHub jich vystavuje dvanáct a Claude šest; hlídá se z nich to, co aplikace
    /// doopravdy volá. `Git Operations` je kvůli klonům a fetchům v cache, `API Requests`
    /// a `Pull Requests` kvůli `gh`, `Claude Code` a `Claude API` kvůli headless session.
    ///
    /// Jméno je jediné, čím se komponenta pozná — `id` je stabilnější, ale ze status page
    /// se nedá přečíst bez toho, aby ho někdo zadrátoval naslepo. Přejmenovaná komponenta
    /// proto **nesmí projít tiše**: `StatusPage.missing` ji vypíše a nápověda to řekne.
    var watchedComponents: [String] {
        switch self {
        case .github: ["API Requests", "Pull Requests", "Git Operations"]
        case .claude: ["Claude Code", "Claude API (api.anthropic.com)"]
        }
    }
}
