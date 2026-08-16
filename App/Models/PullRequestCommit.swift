import Foundation

/// Jeden commit pull requestu (#316).
///
/// **Prohlížeč, ne review**: nálezy jsou klíčované `headSha` (tvrdá podmínka č. 5), takže se k
/// jednotlivému commitu nedá nic připnout — model proto nese jen to, co se v řádku kreslí.
///
/// Co v něm schválně **není**: počet souborů ani `+X −Y`. Seznam z GitHubu je nenese (ověřeno na
/// živém API: `stats` ani `files` v odpovědi nejsou) a dotahovat je po commitu je N+1 past —
/// u sedmi commitů sedm dalších volání k jedné otevřené záložce.
struct PullRequestCommit: Hashable, Sendable, Identifiable {
    /// Plný sha. Klíč řádku, takže se zkrácený nepoužívá ani tam: dva commity se stejnými sedmi
    /// znaky jsou vzácné, ale sloučily by se potichu.
    let sha: String
    /// Celá zpráva, jak ji napsal autor. V řádku je vidět jen `subject`, celá se dá přečíst
    /// v tooltipu — a tělo patří do hlavičky rozkliknutého commitu (#317), takže se nezahazuje.
    let message: String
    /// Jméno z `commit.author.name` — **git ho má vždycky** a účet na GitHubu k němu být nemusí.
    let authorName: String
    /// Účet na GitHubu (`author.login`). `nil`, když GitHub e-mail k účtu nepřiřadí — změřeno na
    /// `keboola/job-queue-daemon#858`, kde je `author: null` u **všech sedmi** commitů.
    let authorLogin: String?
    /// Obrázek autora. Přijde v téže odpovědi jako zbytek, takže nestojí volání navíc; `nil` jde
    /// ruku v ruce s `authorLogin`. Zástupný monogram kreslí `AvatarView` **vždycky, dokud obrázek
    /// nedorazí** — u `nil` tedy napořád —, a bere si ho ze `authorName`, ať se neshoduje s jiným
    /// jménem, než jaké je v řádku vidět.
    let avatarURL: URL?
    /// Kdy commit vznikl (`commit.author.date`). **Datum commitu, ne pushnutí** — tentýž
    /// kompromis jako u časové osy (#171): `pushedDate` GitHub už neplní.
    let committedAt: Date?
    /// Má víc rodičů? Řádek to musí říct dopředu, protože diff sloučení se počítá proti prvnímu
    /// rodiči a umí vyjít prázdný — a prázdný diff bez vysvětlení se čte jako porucha.
    let isMerge: Bool

    var id: String { sha }

    /// První řádka zprávy. To, co se v seznamu kreslí; zbytek je tělo.
    ///
    /// **Prázdná zpráva dá prázdný `subject`**, ne zástupný text: vymyslet za autora větu by
    /// znamenalo tvrdit něco, co v datech není. Že se v řádku místo prázdna nakreslí
    /// `(commit bez zprávy)`, je rozhodnutí **view** (`CommitListView`) — prázdné místo vedle
    /// avataru vypadá jako chyba kreslení, ale závorka je tam vidět jako zástupný text a model se
    /// tím nešpiní.
    var subject: String {
        String(message.prefix(while: { !$0.isNewline }))
    }

    /// Zkrácený sha do pilulky vpravo — sedm znaků, jako `git` a GitHub.
    var shortSha: String { String(sha.prefix(7)) }
}
