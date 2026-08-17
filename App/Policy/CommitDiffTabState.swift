import Foundation

/// Co je vidět, když se v tabu `Commity` rozklikne jeden commit (#317).
///
/// **Čtyři stavy, a `nothing` je ten, kvůli kterému to je vlastní typ.** Diff, který se stáhl
/// a nic v něm není, není porucha ani načítání — je to platná odpověď, kterou musí říct věta.
/// Prázdná plocha by se od nedotočeného spinneru ani od chyby nedala rozeznat, a je to
/// **měřený**, ne teoretický případ: tři commity na `keboola/job-queue#727` (přetočení CI přes
/// `git commit --allow-empty`) vracejí z API **nula bajtů**.
enum CommitDiffTabState: Equatable, Sendable {
    /// Ještě se stahuje. **Nesmí tvrdit, že commit nic nemění.**
    case loading
    case diff(Diff)
    /// Stáhlo se a nic v tom není — s větou, která říká, proč to není porucha.
    case nothing(CommitDiffEmpty)
    case failed(String)
}

/// Proč je diff commitu prázdný (#317).
///
/// **Dvě věty, ne jedna univerzální**: u sloučení je prázdno vlastnost toho, jak se diff počítá,
/// u obyčejného commitu vlastnost commitu samotného — a ta nesprávná by se četla jako výmluva.
struct CommitDiffEmpty: Equatable, Sendable {
    let title: String
    let message: String
}

/// Čísla do hlavičky rozkliknutého commitu (#317) — **spočítaná ze staženého diffu**, tedy bez
/// volání navíc. Seznam commitů je nést nemůže (`stats` ani `files` v odpovědi nejsou, ověřeno
/// u #316), takže tohle je jediné místo, kde je aplikace zadarmo má.
struct CommitDiffFacts: Equatable, Sendable {
    /// `3 soubory` — už vyskloňované, aby se skloňování nepsalo ve view podruhé.
    let files: String
    let additions: Int
    let deletions: Int
}

extension Policy {
    /// Který commit je rozkliknutý — a jestli se vůbec dá rozkliknout (#317).
    ///
    /// Hledá se **podle sha v seznamu**, ne podle uložené pozice: seznam se dotahuje znovu
    /// s detailem, takže po force pushi umí commit z PR zmizet. Když v seznamu není, vrací se
    /// `nil` a tab spadne zpátky na seznam — kreslit hlavičku commitu, který na PR není, by
    /// znamenalo obrazovku, ze které se nedá poznat, že už neplatí.
    ///
    /// Je to tatáž úvaha jako u `headCommit(in:head:)`: o tom, co se ukáže, rozhoduje sha, ne
    /// pozice v poli.
    static func openCommit(_ sha: String?, in commits: [PullRequestCommit]) -> PullRequestCommit? {
        guard let sha else { return nil }
        return commits.first { $0.sha == sha }
    }

    /// Co je v tabu vidět místo seznamu.
    ///
    /// **Cizí sha je `loading`, ne prázdno**: v okně se drží nejvýš jeden diff commitu na PR
    /// (viz `CommitDiff`), takže hned po kliknutí na jiný commit tam ještě chvíli leží ten
    /// předchozí — a nakreslit ho pod hlavičkou nového commitu by byl diff, který k ní nepatří.
    static func commitDiffTab(_ stored: CommitDiff?, of commit: PullRequestCommit) -> CommitDiffTabState {
        guard let stored, stored.sha == commit.sha else { return .loading }
        switch stored.content {
        case .loading: return .loading
        case .failed(let reason): return .failed(reason)
        case .loaded(let diff):
            guard diff.isEmpty else { return .diff(diff) }
            return .nothing(emptyCommitDiff(isMerge: commit.isMerge))
        }
    }

    /// Proč je diff prázdný.
    ///
    /// Změřeno na `keboola/job-queue#727`: tři sloučení tam prázdná **nebyla** (842 B, 514 kB
    /// a 760 kB proti prvnímu rodiči), kdežto tři commity z `git commit --allow-empty` (přetočení
    /// CI) vrátily nula bajtů. Zadání #317 čekalo prázdno hlavně u sloučení; v datech to vyšlo
    /// obráceně, takže **obě věty musí obstát samy o sobě** a rozhoduje mezi nimi `isMerge`, ne
    /// dohad o tom, co je běžnější.
    static func emptyCommitDiff(isMerge: Bool) -> CommitDiffEmpty {
        guard isMerge else {
            return CommitDiffEmpty(
                title: "Tenhle commit nemění žádný soubor",
                message: "Prázdný commit jde vyrobit (`git commit --allow-empty`) a běžně se jím "
                    + "přetáčí CI. Není to porucha — diff se stáhl a nic v něm není."
            )
        }
        return CommitDiffEmpty(
            title: "Sloučení nepřineslo vlastní změnu",
            message: "Diff sloučení se počítá proti prvnímu rodiči, takže co přišlo z druhé "
                + "větve, je vidět v jejích vlastních commitech. Není to porucha."
        )
    }

    /// Tělo zprávy commitu — všechno pod první řádkou (#317).
    ///
    /// **Prázdné u jednořádkové zprávy**, a pak hlavička nekreslí ani blok s linkou, ani přepínač
    /// pod titulkem: první řádka **je** ten titulek, takže by se sbalovalo prázdno. Tělo je zároveň
    /// jediná část hlavičky, která roste bez omezení — sha, autor a počty jsou pořád tři řádky.
    ///
    /// **Dělí se na `isLineTerminator`, ne na `isNewline`** (#339) — tedy tam, kde končí řádek
    /// `gitu`, a na tomtéž znaku, na kterém řádky počítá `commitMessageToggle`. Titulek
    /// (`PullRequestCommit.subject`) a tělo jsou dvě půlky jednoho rozdělení, takže musí mít jeden
    /// pojem „konec řádky“: s `isNewline` by `U+2028` uvnitř titulku titulek usekl a jeho zbytek by
    /// se v hlavičce objevil ještě jako první řádka těla — tentýž text dvakrát, a přitom `git`
    /// (`%s`/`%b`) tam žádnou hranici nevidí.
    static func commitMessageBody(of commit: PullRequestCommit) -> String {
        commit.message
            .drop(while: { !$0.isLineTerminator })
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Popisek přepínače, kterým se tělo zprávy sbaluje (#317).
    ///
    /// **Počet řádků je jen ve sbaleném stavu.** Je to jediné, co o schovaném textu řekne, kolik ho
    /// je — tedy jestli se vyplatí ho rozbalit. V rozbaleném stavu si to člověk přečte sám a číslo
    /// by bylo šum vedle textu, o kterém mluví.
    ///
    /// Počítají se **řádky zprávy včetně prázdných** mezi odstavci: tělo je useknuté z obou stran
    /// (`commitMessageBody`), takže prázdný řádek uvnitř je odstavcová mezera, a ta v hlavičce místo
    /// zabírá stejně jako text. Zalomení sazbou se do počtu nepromítá — číslo mluví o zprávě, ne
    /// o tom, jak široké je zrovna okno. Proto `TextLines.all` (drží prázdné) a ne `content`.
    ///
    /// **Dělí `TextLines`, ne `split(separator: "\n")`** (#339). `"\r\n"` je ve Swiftu jeden
    /// `Character`, takže `split` na `CRLF` nerozdělil vůbec a popisek tvrdil `1 řádek` u zprávy
    /// jakékoli délky — tedy přesný opak toho, na co má odpovědět. Zprávy commitů chodí z `gh`
    /// z cizích repozitářů, takže zakončení řádků si nevybíráme.
    static func commitMessageToggle(_ body: String, expanded: Bool) -> String {
        guard !expanded else { return "Tělo zprávy" }
        let lines = TextLines.all(body).count
        return "Tělo zprávy · \(Plural.czech(lines, one: "řádek", few: "řádky", many: "řádků"))"
    }

    /// Kolik souborů a `+X −Y` — do hlavičky rozkliknutého commitu.
    static func commitDiffFacts(of diff: Diff) -> CommitDiffFacts {
        CommitDiffFacts(
            files: Plural.czech(diff.files.count, one: "soubor", few: "soubory", many: "souborů"),
            additions: diff.additions,
            deletions: diff.deletions
        )
    }

    /// Adresa commitu na GitHubu — `otevřít na GitHubu ↗` v hlavičce.
    ///
    /// Skládá se přes `URLComponents` ze stejného důvodu jako `permalink(to:line:in:at:)`: ručně
    /// slepená URL by u neobvyklého jména repa vyšla rozbitá a odkaz by mlčky nikam nevedl.
    /// `nil` je tedy „nedá se složit“, ne „commit není“ — tlačítko se v takovém případě nekreslí.
    static func commitURL(of sha: String, in repo: RepoID) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "github.com"
        components.path = "/\(repo)/commit/\(sha)"
        return components.url
    }

    /// `2 ze 7` vedle cesty zpět — kolikátý v pořadí, ve kterém je seznam **nakreslený**.
    ///
    /// Počítá se z pořadí kresby (od nejnovějšího, `commitsNewestFirst`), ne z pořadí z API:
    /// je to údaj o tom, kde v seznamu člověk byl, a ten se čte shora dolů. `nil` = commit
    /// v seznamu není, takže se nemá co počítat.
    static func commitPosition(of sha: String, in commits: [PullRequestCommit]) -> String? {
        guard let index = commits.firstIndex(where: { $0.sha == sha }) else { return nil }
        return "\(index + 1) ze \(commits.count)"
    }
}
