import Foundation

/// Hlava pull requestu — sha, na které PR stojí, a kdy ta hlava vznikla (#420).
///
/// **Vlastní model vedle `PullRequest`, ne jeho zúžení.** Detail (`gh pr view`) je odpověď na
/// „všechno o tomhle PR“ a tahá se na jeden pull request; tohle je odpověď na jednu otázku
/// (`headRefOid`) pro **celou frontu naráz**, a bere se dávkovým GraphQL dotazem, který nic
/// dalšího nenese. Kdyby se místo toho vracel `PullRequest` s vymyšlenými poli, měl by model
/// prázdný titulek, prázdné `baseSha` a nikdo by z typu nepoznal, které hodnoty jsou skutečné.
///
/// `committedAt` je **čas události** pro řádek dění: nálezy zastaraly ve chvíli, kdy se hlava
/// posunula na tuhle sha, tedy když ten commit vznikl. `nil` znamená, že se to z odpovědi říct
/// nedá — pak se řádek datuje okamžikem zjištění, protože vymyslet datum zpětně by znamenalo
/// tvrdit, co v datech není.
///
/// **Od #513 nese i větve** (`refs`). Není to rozšíření odpovědnosti, je to tentýž uzel téhož
/// dotazu: `headRefName` a `baseRefName` leží vedle `headRefOid`, takže je dávkový dotaz dostane
/// zadarmo — a jinak by je aplikace u cizí fronty neměla odkud vzít (`gh search prs` větve nevrací).
struct PullRequestHead: Hashable, Sendable {
    let sha: String
    let committedAt: Date?
    /// Jak se hlava jmenuje a proti čemu se merguje (#513). `nil` = odpověď to nenesla — starší
    /// uložená odpověď nebo alias, u kterého dorazila jen část. „Nevíme“ se od „nestojí na ničem“
    /// musí poznat, proto je to `Optional` a ne prázdné řetězce.
    var refs: BranchRefs?
}
