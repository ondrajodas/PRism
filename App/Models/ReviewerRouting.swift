import Foundation

/// Pravidlo, na kterých cestách se reviewer pouští (#518).
///
/// **Prázdné `paths` znamená „bez pravidla“, tedy pouštěj vždycky** — ne „nikdy“. Je to vědomé
/// rozhodnutí a míří na stejný mezistav jako `Configuration.activeSources`: řádek v tabulce
/// nastavení vzniká **prázdný**, takže mezi vybráním revieweera a dopsáním vzoru je konfigurace
/// chvíli bez vzorů. Kdyby prázdný seznam znamenal „nikdy“, jedno kliknutí by revieweera tiše
/// vypnulo — a „tady tenhle reviewer nemá běžet“ se odpovídá **odebráním ze sady skillů**, ne
/// prázdným pravidlem. Routing tedy zužuje jedině tehdy, když má čím.
struct ReviewerRouting: Equatable, Sendable {
    let skill: String
    /// Vzory cest, **už očištěné** (bez prázdných). Skládá je `Policy.routingRules(of:paths:)`,
    /// takže se to čištění nemá kde rozejít s tím, co se pak vypisuje v důvodu přeskočení.
    let paths: [String]

    init(skill: String, paths: [String] = []) {
        self.skill = skill
        self.paths = paths
    }
}

/// Co routing rozhodl o jedné sadě reviewerů (#518).
///
/// **Dvě části, ne jeden slovník rozhodnutí**: volající potřebuje dvě různé věci — koho pustit
/// (a v jakém pořadí) a co říct o tom, koho ne. Sada rozhodnutí by ho nutila si obojí odvozovat
/// a pořadí sady by se v `Set`u ztratilo.
struct ReviewerRoutingPlan: Equatable, Sendable {
    /// Reviewery, které se pustí — **v pořadí nastavené sady**, protože v tom pořadí stojí dráhy
    /// v tabu `Průběh` i chipy v pruhu běhu.
    var skills: [String] = []
    /// Přeskočení: klíčem je skill, hodnotou vzory, ze kterých **nesedělo nic**. Vzory se nesou
    /// s sebou, protože bez nich se důvod (`routing: žádný soubor z …`) nedá napsat — a hádat ho
    /// v okně znovu z konfigurace by znamenalo dvě pravdy o jednom rozhodnutí.
    var skipped: [String: [String]] = [:]
}

/// Co routing přeskočil na posledním průchodu jednoho pull requestu (#518).
///
/// **Drží se jen v paměti, jako živá osa** (`AppStore.reviewTimelines`) — a je to rozhodnutí, ne
/// nedodělek. Přeskočení je funkce **dnešní konfigurace a dnešního diffu**, takže uložené na disk
/// by tichounce zestárlo: po změně vzorů by v souboru leželo tvrzení, které už neplatí, a nikdo by
/// se to nedozvěděl. Odvodit ho znovu přitom nic nestojí — je to čistá funkce nad seznamem souborů.
///
/// `headSha` je součástí záznamu schválně: bez něj by se přeskočení z minulé hlavy počítalo za
/// hotové review té dnešní (`AppStore.hasCurrentReview`), a automat by po pushi mlčel.
struct ReviewerRoutingPass: Equatable, Sendable {
    let headSha: String
    /// Klíčem je skill, hodnotou vzory, ze kterých nesedělo nic.
    let skipped: [String: [String]]
}
