import Foundation

/// Volba metody merge (#556) — **co se nabídne, co se vybere a co o tom potvrzení říká**.
///
/// Je to čistá funkce a je to schválně, ze stejného důvodu jako u `mergeOffer`: merge je nevratný,
/// takže otázka „smí se tahle metoda nabídnout, a co se s ní stane“ má mít **jednu** odpověď,
/// vyjmenovanou a testovanou výčtem. Rozhodovala by se jinak na třech místech — v nastavení
/// globálně, v nastavení repa a v potvrzení —, a ta tři místa by si každé řekla něco jiného.
///
/// **Tři odpovědi, ne dvě.** Repozitář metodu buď pustí, nebo nepustí, nebo se to **nedá zjistit**:
/// nad repem bez práva zápisu (`cli/cli`) GitHub příznaky **vůbec nepošle**. „Nevím“
/// se tady chová jako „ano“ — nabídne se a **netvrdí se nic** —, protože u nevratné akce je
/// rozhodnout z chybějících dat, že něco nejde, tatáž chyba jako rozhodnout, že jde.
extension Policy {
    /// Pořadí metod v nabídce. **Pevné, ne podle toho, co repo povoluje**: nabídka, ve které se
    /// pilulky přeskládají podle repa, se nedá naučit — a `squash` je první proto, že je to
    /// výchozí hodnota a chování aplikace do #556.
    static let mergeMethods: [MergeMethod] = [.squash, .mergeCommit, .rebase]

    /// Jedna pilulka v nabídce.
    struct MergeMethodOption: Hashable, Sendable, Identifiable {
        let method: MergeMethod
        /// Dá se vybrat? `false` = repo ji **jmenovitě** nepovoluje.
        ///
        /// Nepovolená metoda se z nabídky **nesmí ztratit**: zmizet by znamenalo, že se nedá
        /// poznat rozdíl mezi „repo to nepustí“ a „tuhle metodu GitHub nemá“. Kreslí se zašedlá,
        /// přeškrtnutá a se slovem `nejde`.
        let isSelectable: Bool

        var id: MergeMethod { method }
    }

    /// Dá se ta metoda vybrat? **`nil` (nevím) i `true` znamenají „ano“; jedině `false` je zákaz.**
    ///
    /// **Jedno místo pro dvě různá použití**: kreslí se z toho nabídka (zašedlá pilulka v potvrzení,
    /// přeškrtnutá položka v nastavení) **a zahazuje se podle toho zápis** do konfigurace. Dvě
    /// podmínky by znamenaly, že se dá uložit hodnota, kterou nabídka nedovolí vybrat.
    static func isMergeMethodSelectable(
        _ method: MergeMethod,
        in settings: RepositoryMergeSettings?
    ) -> Bool {
        settings?.allows(method) != false
    }

    /// Celá nabídka. `nil` u nastavení znamená „nezjistilo se“ — pak jsou vybratelné všechny tři.
    static func mergeMethodOptions(in settings: RepositoryMergeSettings?) -> [MergeMethodOption] {
        mergeMethods.map {
            MergeMethodOption(method: $0, isSelectable: isMergeMethodSelectable($0, in: settings))
        }
    }

    /// Metody, které repozitář povoluje **jmenovitě**. Prázdné pole znamená „nevíme, nebo
    /// nepovoluje ani jednu“ — a proto se z něj nedá skládat věta bez druhé otázky.
    static func allowedMergeMethods(in settings: RepositoryMergeSettings?) -> [MergeMethod] {
        guard let settings else { return [] }
        return mergeMethods.filter { settings.allows($0) == true }
    }

    /// Metoda, se kterou se potvrzení otevře. `nil` = **nic není vybráno**.
    ///
    /// **Nepovolená výchozí metoda se nepodstrčí jinou** (#556). Tiše přepnout na první povolenou
    /// by znamenalo, že se u nevratné akce stane něco, o co nikdo nepožádal — a řádky `commitů`
    /// a `titulek` by přitom vypadaly jako potvrzený payload. Sheet se proto otevře bez vybrané
    /// metody, `Mergnout` je zakázané a pod výpisem stojí výstraha s tím, co repo povoluje.
    static func initialMergeMethod(
        default method: MergeMethod,
        in settings: RepositoryMergeSettings?
    ) -> MergeMethod? {
        settings?.allows(method) == false ? nil : method
    }

    /// Věta do výstrahy pod výpisem, když výchozí metoda v tomhle repu nejde. `nil` = není co
    /// říkat.
    ///
    /// **Ke každé podobě patří další krok** — důvod, ze kterého neplyne, co s ním, je jen zpráva
    /// o smůle. Tatáž úmluva jako u `MergeObstacle.sentence`.
    static func mergeMethodWarning(
        default method: MergeMethod,
        in settings: RepositoryMergeSettings?
    ) -> String? {
        guard settings?.allows(method) == false else { return nil }
        let allowed = allowedMergeMethods(in: settings).filter { $0 != method }
        let head = "Výchozí metoda \(method.displayName) tady nejde — "
        let tail = " nebo přepni výchozí hodnotu v nastavení tohohle repa."
        switch allowed.count {
        case 0:
            // Nemá nastat (GitHub aspoň jednu metodu povolit musí), ale **prázdný výčet je stav,
            // ne nemožnost**: kdyby přišel, nesmí z něj vzniknout věta „repozitář povoluje“
            // s ničím za dvojtečkou.
            return head + "a repozitář nepovoluje ani žádnou jinou. Mergni to na GitHubu,"
                + " nebo změň nastavení repozitáře."
        case 1:
            return head + "repozitář povoluje jen \(allowed[0].displayName). Vyber ji," + tail
        default:
            return head + "repozitář povoluje \(joined(allowed.map(\.displayName)))."
                + " Vyber jednu z nich," + tail
        }
    }

    /// Věta pod výpisem o tom, že přepnutí je **jednorázové**. `nil` = vybraná metoda je ta výchozí.
    ///
    /// Bez téhle věty by picker vypadal jako zkratka do nastavení a člověk by čekal, že si to okno
    /// bude pamatovat.
    static func mergeMethodOverrideNote(
        selected: MergeMethod,
        default method: MergeMethod
    ) -> String? {
        guard selected != method else { return nil }
        return "Přepnutá metoda platí pro tenhle merge — výchozí hodnota v nastavení zůstává"
            + " \(method.displayName)."
    }

    /// Řádek `commitů` ve výpisu payloadu.
    ///
    /// **Je to tvrzení o metodě, ne údaj o PR** (#556): do té doby tu stálo `3 → 1`, což je věta
    /// o squashi — u merge commitu je výsledek `3 + merge commit` a u rebase `3 přehrané`. Řádek
    /// payloadu, který nad jinou metodou lže, je horší než řádek, který tam není, takže se
    /// s metodou přepisuje.
    static func mergeCommitsLine(method: MergeMethod, commits: Int) -> String {
        switch method {
        // Číslo se sází `verbatim` ve view; tady je to počet položek seznamu, ne množství —
        // stejně jako u `commits` v `MergePlan`.
        case .squash: "\(commits) → 1"
        case .mergeCommit: "\(commits) + merge commit"
        case .rebase: Plural.czech(commits, one: "přehraný", few: "přehrané", many: "přehraných")
        }
    }

    /// `commit_title`, který odejde. **`nil` u rebase** — žádný commit tam nevzniká, takže by to
    /// bylo pole, které GitHub zahodí, a potvrzení by slibovalo titulek, který se nikde neobjeví.
    ///
    /// **Posílá se u obou metod, které commit vytvoří**, a důvod z #465 platí dál: bez
    /// `commit_title` si ho GitHub skládá podle nastavení repozitáře — a nad repem bez práva
    /// zápisu se to nastavení ani nedá přečíst (`cli/cli` neposílá ani
    /// `squash_merge_commit_title`), takže by potvrzení ukazovalo titulek, který nemusí vzniknout.
    ///
    /// U merge commitu je to **vlastní úmluva GitHubu** (`Merge pull request #N from <větev>`), aby
    /// historie vypadala stejně jako po mergi z webu; větev se bere **doslova ta, kterou vypisuje
    /// řádek `větev`** nad ním, takže se potvrzení nedá rozejít samo se sebou.
    static func mergeCommitTitle(
        method: MergeMethod,
        title: String,
        number: Int,
        head: String
    ) -> String? {
        switch method {
        case .squash: squashTitle(of: title, number: number)
        // Číslo se sází ručně, ne přes formátování: `#85` není množství a v české locale by se
        // z něj stalo `#8 5`. Tatáž úvaha jako u `squashTitle`.
        case .mergeCommit: "Merge pull request #\(number) from \(head)"
        case .rebase: nil
        }
    }

    /// Věta o **těle** commitu pod výpisem.
    ///
    /// **Přestala se hádat** (#556). Do té doby tu stálo „Tělo squash commitu složí GitHub ze zpráv
    /// N commitů“, což je pravda jedině v repu se `squash_merge_commit_message = COMMIT_MESSAGES`
    /// — tenhle repo ho má (změřeno), ale záruka to není; v repu s `PR_BODY` ta věta lhala.
    /// Nastavení přijde **týmž voláním** jako povolené metody, takže věta umí říct, co v tom těle
    /// doopravdy bude.
    ///
    /// **Kde se to zjistit nepodařilo, zůstává přiznání** — „složí GitHub podle nastavení
    /// repozitáře“. Je to tatáž úvaha jako u `nevím` v řádku stavu větve: nevědět je vlastní
    /// odpověď.
    static func mergeBodyNotice(
        method: MergeMethod,
        commits: Int,
        base: String,
        in settings: RepositoryMergeSettings?
    ) -> String {
        // Rebase tělo nemá, protože nemá commit — a mluvit o „nastavení repozitáře“ by tady bylo
        // tvrzení o poli, které se u rebase nečte.
        guard method.makesCommit else {
            return "Rebase žádný commit nevytváří — commity se přehrají nad \(base), jak jsou,"
                + " i s titulky a těly."
        }
        let subject = method == .squash ? "squash commitu" : "merge commitu"
        switch settings?.bodySource(for: method) {
        case .commitMessages:
            // **Skloňuje se** — „ze zpráv 1 commitů“ je zrovna ta chyba, kvůli které `Plural`
            // existuje.
            let word = Plural.czech(commits, one: "commitu", few: "commitů", many: "commitů")
            return "Tělo \(subject) složí GitHub ze zpráv \(word)."
        case .pullRequestBody:
            return "Tělo \(subject) složí GitHub z popisu pull requestu."
        case .pullRequestTitle:
            return "Tělo \(subject) složí GitHub z titulku pull requestu."
        case .blank:
            return "Tělo \(subject) zůstane prázdné."
        case .none:
            return "Tělo \(subject) složí GitHub podle nastavení repozitáře."
        }
    }

    /// Výčet do věty — `squash a merge commit`, `squash, merge commit a rebase`.
    ///
    /// **Vlastní, ne `ListFormatter`**: ten by šel přes locale procesu, a ta je v testovacím hostu
    /// jiná než v aplikaci (`CFBundleLocalizations = [cs]`, viz `CLAUDE.md`) — takže by týž výčet
    /// vyšel v testu jinak než v okně.
    private static func joined(_ items: [String]) -> String {
        guard let last = items.last else { return "" }
        guard items.count > 1 else { return last }
        return items.dropLast().joined(separator: ", ") + " a " + last
    }
}
