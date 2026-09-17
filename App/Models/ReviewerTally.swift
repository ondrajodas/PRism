import Foundation

/// Jak si **jeden reviewer v jednom repu** vedl za posledních třicet dní (#514).
///
/// Aplikace u každého odmítnutého nálezu ukládá důvod (#113), ale nikde je nesčítala — takže
/// se nedalo říct, který skill v kterém repu hlásí věci, co neplatí, a kam tedy sáhnout.
/// Tenhle typ je ten součet, a je to **čtení uložených dat, ne review logika**: co má reviewer
/// hlásit, zůstává ve skillu.
///
/// **Dvojice `(repo, reviewer)`, ne jen reviewer.** Tentýž skill se na dvou repech chová jinak,
/// protože se liší kód i pravidla — slít obojí do jednoho řádku by zahodilo zrovna tu
/// informaci, kvůli které se na blok kouká.
///
/// **Čtyři čísla, ne dvě.** `neplatí` a `nepatří sem` jsou dva různé signály (viz
/// `FindingDismissal.Reason`) a `převzato` se od `nerozhodnuto` liší tím, jestli se o nálezu
/// vůbec rozhodlo — počítat nepřečtený nález jako schválený by reviewera chválil za to, že se
/// na něj nikdo nepodíval.
struct ReviewerTally: Hashable, Sendable, Identifiable {
    /// Skill, který nálezy nahlásil (`Finding.reviewer`).
    let reviewer: String
    let repo: RepoID
    /// Nálezy, které jsem nechal platit a jejichž případ je uzavřený — viz
    /// `Policy.reviewerTallies(from:now:)`.
    var taken: Int
    /// Odmítnuté jako `Neplatí` — signál o **skillu**.
    var invalid: Int
    /// Odmítnuté jako `Nepatří sem` — signál o **pravidlech repa**.
    var irrelevant: Int
    /// Nálezy, o kterých se zatím nerozhodlo.
    var undecided: Int

    init(
        reviewer: String,
        repo: RepoID,
        taken: Int = 0,
        invalid: Int = 0,
        irrelevant: Int = 0,
        undecided: Int = 0
    ) {
        self.reviewer = reviewer
        self.repo = repo
        self.taken = taken
        self.invalid = invalid
        self.irrelevant = irrelevant
        self.undecided = undecided
    }

    /// Identita řádku. Svislítko ze stejného důvodu jako v `Policy.key(of:)` — jméno repa ho
    /// obsahovat nemůže (`RepoID` ho odmítne) a jméno skillu ho nemá kde vzít.
    var id: String { "\(repo.description)|\(reviewer)" }

    var total: Int { taken + invalid + irrelevant + undecided }

    /// Kolik jsem jich odmítl, oběma důvody dohromady. **O tomhle čísle je práh** — věta se
    /// ozve podle toho, kolik nálezů neobstálo, a teprve pak pojmenuje ten častější důvod.
    var dismissed: Int { invalid + irrelevant }
}

/// Věta pod pruhem (#514) — `9 z 14 neplatí → skill`.
///
/// **Nese i kam míří**, ne jen text: barvu i nápovědu z toho skládá view, a kdyby se cíl
/// odvozoval z řetězce, byly by to dvě pravdy o jedné větě.
struct ReviewerSignal: Hashable, Sendable {
    /// Kam ta věta ukazuje. `none` = nic se neozývá, je to prostý součet.
    enum Aim: Hashable, Sendable {
        /// `Neplatí` převažuje — reviewer se mýlí, oprava patří do skillu.
        case skill
        /// `Nepatří sem` převažuje — reviewer má pravdu, jen se hlásí, co repo nechce.
        case repoRules
        /// Nic nepřevažuje.
        case none
    }

    let text: String
    let aim: Aim
}
