import Foundation

/// Co se o katalogu repozitářů napíše v nastavení (#532).
///
/// Vlastní typ, ne holý `String` — stejně jako `IssueTextTool.Note` a `ReviewTimeout.Problem`:
/// rozhodnutí („co se dá o katalogu říct“) patří do `Policy`, kde se testuje výčtem, a view z něj
/// jen sází text. A hlavně: **tři z těch stavů nejsou porucha**, což by `String?` neunesl.
///
/// **Je to jediné místo, kde se o katalogu píše — na řádcích organizací žádný stav není**, a je to
/// oprava z renderu: řádek `keboola … zatím nenačteno` nad souhrnem `Zatím nenačteno` říkal tutéž
/// věc dvakrát pod sebou a u jedné organizace se stejně zdvojoval i počet rep. Řádek si nechává
/// **jen větu o selhání** (tu souhrn říct neumí, protože je na organizaci).
enum RepositoryCatalogStatus: Equatable, Sendable {
    /// Žádná organizace není nastavená. Není co dotahovat a není to chyba.
    case noOrganizations
    /// Právě se tahá — `done` z `total` organizací je hotových.
    case refreshing(done: Int, total: Int)
    /// Nic se ještě nedotáhlo, ale organizace nastavené jsou.
    case neverFetched
    /// Katalog je načtený. `repositories` je součet přes organizace, `oldest` **nejstarší**
    /// razítko (viz níž), `missing` počet organizací bez snímku a `hitLimit`, jestli aspoň jeden
    /// výpis narazil na strop.
    case loaded(repositories: Int, oldest: Date, missing: Int, hitLimit: Bool)
}

extension Policy {
    /// Jak dlouho platí uložený výpis rep, než se má dotáhnout znovu (#532).
    ///
    /// Den, jak chce zadání. **Od dotažení, ne od půlnoci**: kalendářní den by po dotažení v 23:55
    /// znamenal obnovu za pět minut, tedy tři čtvrtě minuty práce nad `keboola` za nic.
    static let repositoryCatalogMaxAge: TimeInterval = 24 * 60 * 60

    /// Jméno organizace, se kterým se dá pracovat — nebo `nil`, když se s ním pracovat nedá.
    ///
    /// **Ověřuje se tady, protože z toho jména vzniká cesta do cache** (`catalogs/<org>.json`)
    /// a na té cestě se maže. Je to tatáž úvaha, jakou má `RepoID.isValidComponent`, jen na jednu
    /// komponentu: `..` nebo `a/b` v poli v nastavení by mazání pustilo ven z cache.
    ///
    /// Kromě toho se **sráží zápis, který člověk napíše, ale GitHub nezná**: obalové mezery a `@`
    /// před jménem (`@keboola`), protože přesně tak se organizace píše v textu a jednou za čas se
    /// to takhle vloží ze schránky.
    static func organizationName(from typed: String) -> String? {
        var name = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.hasPrefix("@") { name.removeFirst() }
        guard !name.isEmpty, name.count <= 100 else { return nil }
        // `.` a `..` jsou v cestě posun o složku výš; `/` by z jednoho jména udělal dvě.
        guard name != ".", name != ".." else { return nil }
        guard name.allSatisfy(isOrganizationCharacter) else { return nil }
        // Aspoň jeden znak, který jméno doopravdy je — `---` ani `...` organizace není.
        guard name.contains(where: { $0.isLetter || $0.isNumber }) else { return nil }
        return name
    }

    /// Organizace z konfigurace, se kterými se dá pracovat — ověřené, bez duplicit a v pořadí,
    /// v jakém je člověk napsal.
    ///
    /// **Pořadí ze souboru, ne abecedně**: je to seznam, který si člověk skládá sám, a přerovnat
    /// mu ho pod rukou znamená, že po každém uložení hledá, kam se řádek poděl. Duplicity vypadnou
    /// proto, že by se táž organizace tahala dvakrát a v součtu by se počítala dvakrát.
    ///
    /// Rozhoduje se podle **ověřeného** jména, takže `@keboola` a `keboola` je jedna organizace.
    static func searchOrganizations(in configuration: Configuration) -> [String] {
        searchOrganizations(configuration.global.searchOrganizations)
    }

    /// Totéž nad holým seznamem — pro formulář, který ještě nemá kam uložit.
    static func searchOrganizations(_ raw: [String]) -> [String] {
        var seen: Set<String> = []
        var organizations: [String] = []
        for raw in raw {
            guard let name = organizationName(from: raw) else { continue }
            guard seen.insert(name.lowercased()).inserted else { continue }
            organizations.append(name)
        }
        return organizations
    }

    /// Organizace, jejichž výpis se má dotáhnout — chybí, nebo je starší než den.
    ///
    /// **Chybějící snímek a starý snímek jedna funkce**, protože je to jedna otázka („co je
    /// potřeba dotáhnout“) a dvě odpovědi by znamenaly dvě místa, kde se dá zapomenout na jeden
    /// z těch dvou případů.
    ///
    /// Pořadí zůstává, jak přišlo: dotahuje se po jedné a to, co je nahoře v nastavení, má být
    /// hotové dřív.
    static func staleOrganizations(
        _ organizations: [String],
        snapshots: [String: RepositorySnapshot],
        now: Date,
        maxAge: TimeInterval = repositoryCatalogMaxAge
    ) -> [String] {
        organizations.filter { organization in
            guard let snapshot = snapshots[organization] else { return true }
            // Razítko **z budoucnosti** se bere jako čerstvé, ne jako prošlé: posunuté hodiny
            // nemají spustit tři čtvrtě minuty práce při každém otevření nastavení.
            return now.timeIntervalSince(snapshot.fetchedAt) >= maxAge
        }
    }

    /// Co se o katalogu napíše pod seznamem v sekci `Organizace k prohledávání`.
    ///
    /// **Nejstarší razítko, ne nejnovější.** Věta `obnoveno 7:58` je tvrzení o **celém** katalogu,
    /// takže musí platit i pro tu organizaci, která se tahala nejdřív. S nejnovějším razítkem by
    /// se nad týden starým seznamem `keboola` psalo, že se obnovil před minutou, protože se
    /// mezitím dotáhl `ondrajodas`.
    ///
    /// Organizace **bez snímku se počítají zvlášť** (`missing`) a do součtu rep nespadnou: součet,
    /// který jednu organizaci mlčky vynechá, tvrdí víc, než co data unesou.
    static func repositoryCatalogStatus(
        organizations: [String],
        snapshots: [String: RepositorySnapshot],
        refreshing: Set<String>
    ) -> RepositoryCatalogStatus {
        guard !organizations.isEmpty else { return .noOrganizations }
        // **Rozhoduje průnik, ne `refreshing.isEmpty`.** Organizaci se dá z pole smazat uprostřed
        // dotažení, takže se v `refreshing` může držet jméno, které v seznamu není — a z toho by
        // vyšlo `Obnovuje se… 2/2` nad katalogem, na kterém se nic netahá.
        let running = organizations.filter { refreshing.contains($0) }.count
        if running > 0 {
            return .refreshing(done: organizations.count - running, total: organizations.count)
        }

        let known = organizations.compactMap { snapshots[$0] }
        guard let oldest = known.map(\.fetchedAt).min() else { return .neverFetched }
        return .loaded(
            repositories: known.reduce(0) { $0 + $1.repositories.count },
            oldest: oldest,
            missing: organizations.count - known.count,
            hitLimit: known.contains(where: \.hitLimit)
        )
    }

    /// Věta pod seznamem, vlevo od tlačítka `Obnovit` — `412 rep · obnoveno 7:58`.
    ///
    /// Skládá se tady, ne ve view, protože o tom, co se smí tvrdit, rozhoduje `Policy`: `nejméně`
    /// u sraženého výpisu i `1 nenačtena` u organizace bez snímku jsou součást téhož tvrzení jako
    /// to číslo před nimi.
    static func repositoryCatalogSummary(_ status: RepositoryCatalogStatus, now: Date) -> String? {
        switch status {
        case .noOrganizations:
            return nil
        case .refreshing(let done, let total):
            return total == 1 ? "Obnovuje se…" : "Obnovuje se… \(done)/\(total)"
        case .neverFetched:
            return "Zatím nenačteno"
        case .loaded(let repositories, let oldest, let missing, let hitLimit):
            // `nejméně` je tam jedině při sražení na strop — bez něj by `1 000 rep` tvrdilo, že
            // jich tolik je, kdežto je jich tolik **vidět**.
            let count = Plural.czech(repositories, one: "repo", few: "repa", many: "rep")
            var parts = [hitLimit ? "nejméně \(count)" : count]
            parts.append("obnoveno \(moment(oldest, now: now))")
            if missing > 0 {
                parts.append(
                    "\(Plural.czech(missing, one: "organizace", few: "organizace", many: "organizací")) "
                        + Plural.word(missing, one: "nenačtena", few: "nenačtené", many: "nenačtených")
                )
            }
            return parts.joined(separator: " · ")
        }
    }

    /// Kdy se to stalo — dnes jen čas, jindy i datum.
    ///
    /// Samotné `7:58` nad snímkem z minulého týdne vypadá jako „před chvílí“, a to je zrovna
    /// u katalogu s denní obnovou ta informace, na kterou se člověk ptá. Je to tentýž tvar, jaký
    /// má razítko předání zadání v panelu (#334).
    private static func moment(_ date: Date, now: Date) -> String {
        Calendar.current.isDate(date, inSameDayAs: now)
            ? date.formatted(date: .omitted, time: .shortened)
            : date.formatted(date: .abbreviated, time: .shortened)
    }

    private static func isOrganizationCharacter(_ character: Character) -> Bool {
        character.isASCII && (character.isLetter || character.isNumber || character == "-"
            || character == "_" || character == ".")
    }
}
