import Foundation

/// Kam se **smí** odeslat review.
///
/// Zatím jedině do sandboxu. Je to vědomé omezení první verze odesílání, ne technická
/// překážka: pravidlo „jediná cesta ven“ je nové a než ho pustíme na PR kolegů, projde si
/// provozem na repu, kde omyl nikoho nestojí čas. Vyřazení řeší #107.
///
/// **Seznam je zadrátovaný schválně, ne v konfiguraci.** Kdyby se dal změnit editací
/// `config.json`, není to brána, ale nastavení — a omyl v souboru, který se edituje ručně,
/// by odeslal review na ostré repo. Rozšířit ho takhle vyžaduje změnu kódu, code review
/// a release, což je přesně ta cena, kterou tahle brána má mít.
enum PublishScope {
    static let allowed: Set<RepoID> = [
        RepoID(owner: "ondrajodas", name: "prism-review-sandbox"),
    ]

    static func allows(_ repo: RepoID) -> Bool { allowed.contains(repo) }
}
