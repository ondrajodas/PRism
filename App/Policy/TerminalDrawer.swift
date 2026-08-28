import CoreGraphics
import Foundation

/// Co se v zásuvce s terminálem spustí (#459).
///
/// **Adresář a příkaz zvlášť, jako u `TerminalSession`** — jen obráceně: tam se skládala řádka
/// pro cizí okno, tady se binárka spouští přímo, takže se nic nesází do shellu a nic se
/// neuvozovkuje. Cesta se předává jako pracovní adresář procesu, ne jako `cd` v příkazu.
struct TerminalShellCommand: Equatable, Sendable {
    /// Binárka shellu — z `SHELL`, jinak `/bin/zsh` (výchozí macOS od Cataliny).
    let executable: URL

    /// `argv[0]`. **S pomlčkou na začátku**, a je to celý rozdíl mezi „shell“ a „shell, ve kterém
    /// mám svoje nastavení“: pomlčka z něj dělá **login shell**, takže si přečte `.zprofile`
    /// a `.zshenv` — tedy i `PATH` s Homebrew. Bez ní by se v zásuvce nenašlo nic, co není
    /// v `/usr/bin`. Interaktivní je proto, že stdin je pty; `.zshrc` se tím přečte taky.
    let argv0: String
}

/// Jak si stojí shell v zásuvce (#459).
///
/// **`exited` nese kód**, ne jen příznak: `zsh` po `exit 1` je něco jiného než `zsh`, který spadl —
/// a v hlavičce zásuvky je to jediné, podle čeho se pozná, že se něco nepovedlo. `nil` je běh, ze
/// kterého kód nedorazil: čtení pty selhalo dřív, nebo se shell **vůbec nespustil** (`SHELL` míří
/// na binárku, která neexistuje). Je to odpověď, ne slabší „skončil“ — a hlavně se ani jeden
/// z těch stavů nesmí kreslit jako `běží`.
enum TerminalRunState: Equatable, Sendable {
    case running
    case exited(code: Int32?)
}

/// Jak dopadl pokus poslat řádku do zásuvky (#460).
///
/// **Čtyři stavy, ne `Bool`**, a je to tatáž úvaha jako u `TerminalRunState`: „neposlalo se“ má
/// dva úplně různé důvody — v zásuvce něco běží, nebo se v ní nepodařilo spustit shell —, a člověk
/// s každým z nich naloží jinak. `started` se od `sent` liší jen tím, co se stalo navíc; oba
/// znamenají, že řádka odešla.
enum TerminalCommandOutcome: Equatable, Sendable {
    /// Shell v zásuvce nebyl (nebo skončil), pustil se nový a řádka do něj odešla.
    case started
    /// Řádka odešla do shellu, který čekal na prompt.
    case sent
    /// V zásuvce běží cizí job v popředí — **nic se neposlalo**.
    case busy
    /// Shell se nepodařilo spustit, takže řádku nemá kdo přečíst.
    case noShell
}

/// Dotaz na ukončení aplikace (#459) — věta v `NSAlert`u.
///
/// Vlastní typ, protože se ptá **na dvě různé věci naráz**: běžící review (#94) a shelly
/// v zásuvce. Do #459 to byl jeden počet a text se skládal v `AppDelegate`u; s druhým počtem
/// by z toho byly čtyři větve `if`ů ve view vrstvě, tedy přesně to, co patří do `Policy`.
struct QuitPrompt: Equatable, Sendable {
    let title: String
    let detail: String
}

extension Policy {
    // MARK: - Výška zásuvky

    /// Nejnižší, jak smí zásuvka být — `min-height: 150px` u `.term-body` z návrhu plus hlavička.
    ///
    /// Pod tím to není terminál, ale proužek: `claude` kreslí rámeček a k němu aspoň řádek vstupu,
    /// takže na deseti řádcích se přestává dát používat.
    static let terminalDrawerMinHeight: CGFloat = 178

    /// S jakou výškou se zásuvka otevře poprvé.
    ///
    /// **Víc než podlaha**, protože poprvé se v ní pouští `claude --resume`, a to je celoobrazovkové
    /// TUI. Na podlaze by se otevřelo do rámečku bez obsahu a vypadalo by rozbitě dřív, než by kdo
    /// stačil něco napsat.
    static let terminalDrawerIdealHeight: CGFloat = 300

    /// Kolik musí zůstat **nad** zásuvkou.
    ///
    /// Zásuvka je pod diffem schválně (návrh, sekce 35: „vidím diff a pod ním výstup příkazu“),
    /// takže roztažená přes celé okno by zrušila jediný důvod, proč to není devátá záložka.
    /// Hlavička PR s pruhem záložek sama zabere ~104 bodů; 190 nechá pod nimi ještě pár řádků kódu.
    static let terminalDrawerContentFloor: CGFloat = 190

    /// S jakou výškou se zásuvka otevře: **uloženou, když je použitelná, jinak výchozí**.
    ///
    /// Nula znamená „nic uloženého“ — `@AppStorage` bez zapsané hodnoty vrací právě ji, a odlišit
    /// „neuloženo“ od „uloženo“ je potřeba k tomu, aby první otevření mohlo vyjít z ideálu.
    ///
    /// Ořez je **při použití, ne při zápisu** (tatáž úvaha jako u `rawSessionSheetSize`): v
    /// `UserDefaults` může být cokoli — ruční editace, hodnota z většího okna, nesmysl ze starší
    /// verze — a záporná výška by rozhodila celé okno.
    ///
    /// `available` je výška **celého detailu PR**, ne obrazovky: zásuvka bydlí uvnitř záložky,
    /// takže o jejím stropu rozhoduje okno, ne monitor. Nula (ještě se neměřilo) znamená ideál —
    /// zásuvka se nemá otevřít do podlahy jen proto, že první průchod rozvržení ještě nic nezná.
    static func terminalDrawerHeight(stored: Double, available: CGFloat) -> CGFloat {
        let wanted = stored.isFinite && stored > 0 ? CGFloat(stored) : terminalDrawerIdealHeight
        return clampTerminalDrawer(wanted, available: available)
    }

    /// Výška po tažení za horní hranu. Kladné `translation` je tažení dolů, tedy **zmenšení**.
    ///
    /// **Počítá se z výšky na začátku tahu, ne z té právě platné**, a je to podmínka toho, aby
    /// tažení nebylo trhané: přírůstek proti průběžně ořezané hodnotě by se u stropu sečetl s tím,
    /// co strop uřízl, takže by se zásuvka po dojetí ke hraně přestala vracet.
    static func terminalDrawerResize(
        from height: CGFloat,
        by translation: CGFloat,
        available: CGFloat
    ) -> CGFloat {
        clampTerminalDrawer(height - translation, available: available)
    }

    /// Mez shora i zdola. Když se do okna nevejde ani podlaha, **rozhoduje podlaha** — zásuvka
    /// zmizet nesmí, dokud si o to člověk neřekne.
    private static func clampTerminalDrawer(_ height: CGFloat, available: CGFloat) -> CGFloat {
        guard height.isFinite else { return terminalDrawerIdealHeight }
        guard available.isFinite, available > 0 else {
            return max(height, terminalDrawerMinHeight)
        }
        let ceiling = max(terminalDrawerMinHeight, available - terminalDrawerContentFloor)
        return min(max(height, terminalDrawerMinHeight), ceiling)
    }

    /// Má se natažená výška uložit? `nil` = **nezapisovat**.
    ///
    /// Tentýž tvar jako `rawSessionSheetResize` a `hoverChange(from:to:)`, ale **bez pasti s prvním
    /// průchodem rozvržení**: výšku tady nikdo nenavrhuje, mění ji jedině tažení za horní hranu —
    /// takže se ukládá na konci tahu a odmlka, která by zahazovala mezistav, potřeba není.
    /// Zapisuje se jen změna, aby zavření a otevření zásuvky nesahalo na disk.
    static func terminalDrawerStoredHeight(stored: Double, measured: CGFloat) -> Double? {
        guard measured.isFinite, measured >= terminalDrawerMinHeight else { return nil }
        let rounded = Double(measured.rounded())
        guard rounded != stored.rounded() else { return nil }
        return rounded
    }

    // MARK: - Klávesy

    /// Ustupuje ta zkratka okna terminálu, když má zásuvka fokus? (#459)
    ///
    /// **Pravidlo je jedno a zní: co nemá `⌘`, patří terminálu.** Návrh (sekce 35, poznámka 110)
    /// mluví o `Control`u — `⌃W` maže slovo, `⌃C` přerušuje běh, `⌃1`–`⌃5` a `⌃⇥` patří tomu, co
    /// uvnitř běží —, jenže hranice kolem jednoho modifikátoru by nechala venku `⎋` (vim, `claude`)
    /// a `⌥↑`/`⌥↓`, kde je `Option` v terminálu meta. `⌘` naopak terminál nikdy nedostane: je to
    /// modifikátor menu, ne klávesa, která by dojela do pty.
    ///
    /// **Jedinou výjimkou je `⌃\`` sama** — tou se zásuvka schovává, takže by se s vypnutými
    /// zkratkami nedala zavřít jinak než myší. Rozhoduje **akce**, ne kombinace: kdyby se zítra
    /// zásuvka přepínala jinou klávesou, výjimka jde s ní.
    ///
    /// Zkratka, která uprostřed psaní zavře záložku, je horší než žádný terminál — proto to není
    /// `if` ve view, ale funkce, kterou jde projít vyčerpávajícím výčtem nad celým katalogem.
    static func shortcutYieldsToTerminal(
        _ action: WindowShortcut.Action,
        _ combination: WindowShortcut.Combination
    ) -> Bool {
        guard action != .toggleTerminal else { return false }
        return !combination.modifiers.contains(.command)
    }

    // MARK: - Kde shell startuje

    /// Ve kterém adresáři se shell pustí. `nil` = **není kde**, a zásuvka to řekne místo prázdné
    /// plochy.
    ///
    /// Pořadí je podstatné a obojí je v cache aplikace (tvrdá podmínka č. 3 platí beze změny):
    ///
    /// 1. **Pracovní strom review**, když existuje. Je to ten adresář, na který se člověk dívá —
    ///    a hlavně jediný, ve kterém `claude --resume` session **najde**: vlákna se klíčují cestou
    ///    (`~/.claude/projects/<zakódovaná cesta>/`), takže tentýž příkaz jinde odpoví, že takové
    ///    vlákno nezná (viz `TerminalSession.directory`).
    /// 2. **Bare klon repa**, když strom není. `git log`, `git show` i `gh pr view` v něm fungují;
    ///    pracovní kopie v něm chybí, ale to je pořád víc než zavřená zásuvka na PR, na kterém
    ///    ještě neběželo review.
    ///
    /// **Existenci na disku ověřuje volající**, ne tahle funkce: `Policy` nesahá na I/O. Předává se
    /// sem tedy `nil` u toho, co v cache není.
    static func terminalWorkingDirectory(worktree: URL?, clone: URL?) -> URL? {
        worktree ?? clone
    }

    /// Cesta tak, jak se píše do hlavičky zásuvky — s `~` místo domovské složky.
    ///
    /// Vlastní funkce, ne `NSString.abbreviatingWithTildeInPath`: ta si domov bere z prostředí
    /// procesu, takže by se v testu chovala podle toho, kdo test pustil. Domov se proto předává.
    ///
    /// Zkracuje se **jen celý prefix po hranici složky** — `/Users/ondrej` se nesmí zkrátit kvůli
    /// domovu `/Users/ondra`.
    static func terminalDirectoryLabel(_ url: URL, home: URL) -> String {
        let path = url.path(percentEncoded: false)
        let root = home.path(percentEncoded: false)
        guard !root.isEmpty, root != "/" else { return path }
        if path == root { return "~" }
        guard path.hasPrefix(root + "/") else { return path }
        return "~" + path.dropFirst(root.count)
    }

    // MARK: - Co se spustí a s čím

    /// Shell, který se pustí, když z `SHELL` nic použitelného nekouká — `/bin/zsh` je výchozí
    /// macOS od Cataliny a je to tatáž volba jako v `LoginShellPathReader`.
    ///
    /// Konstanta, ne literál na dvou místech: bere si ji i volající, který zjistí, že binárka
    /// ze `SHELL` na disku není (viz `EmbeddedTerminalView.start(in:)`).
    static let fallbackShell = TerminalShellCommand(
        executable: URL(filePath: "/bin/zsh"),
        argv0: "-zsh"
    )

    /// Shell z prostředí, jinak `fallbackShell`.
    static func terminalShell(_ environment: [String: String]) -> TerminalShellCommand {
        // Relativní cesta se zahazuje: `SHELL` se dá nastavit na cokoli, a spustit `zsh` nalezené
        // podle `PATH` aplikace by znamenalo spustit něco jiného, než co si člověk nastavil.
        guard let configured = environment["SHELL"], configured.hasPrefix("/") else {
            return fallbackShell
        }
        let executable = URL(filePath: configured)
        return TerminalShellCommand(executable: executable, argv0: "-" + executable.lastPathComponent)
    }

    /// Prostředí pro shell v zásuvce, ve tvaru `KLÍČ=hodnota`.
    ///
    /// Tři věci v něm stojí za vysvětlení:
    ///
    /// - **`PATH` se nepředává schválně.** Aplikace spuštěná z Finderu má `PATH` osekaný na
    ///   systémové složky (právě proto v repu je `BinaryLocator`), takže předat ho dál by znamenalo
    ///   začít v zásuvce bez Homebrew. Login shell si ho složí sám — `/etc/zprofile` pouští
    ///   `path_helper` a `.zprofile` uživatele dodá zbytek.
    /// - **`TERM=xterm-256color`, `COLORTERM=truecolor`.** Emulátor umí xterm a 24bitovou barvu;
    ///   `claude` se podle těch dvou proměnných rozhoduje, jak se kreslit.
    /// - **`LANG` se dědí, a když není, dosadí se UTF-8.** Není to o jazyku, ale o kódování: bez
    ///   UTF-8 locale sypou `vi` i `claude` sekvence, které emulátor přečte jako rozsypaný čaj.
    ///   Aplikace je česká (`CFBundleLocalizations`), jenže locale shellu je vlastnost uživatelova
    ///   účtu, ne naše — proto se přebírá, když ji proces má.
    static func terminalEnvironment(_ environment: [String: String]) -> [String] {
        var variables = ["TERM=xterm-256color", "COLORTERM=truecolor"]
        // Vyjmenované, ne „všechno kromě“: prostředí GUI aplikace nese i věci, které do shellu
        // nepatří (`XPC_SERVICE_NAME`, `__CF*`), a zděděná proměnná se pak těžko hledá.
        for key in ["HOME", "USER", "LOGNAME", "SHELL", "TMPDIR", "LC_ALL", "LC_CTYPE"] {
            guard let value = environment[key] else { continue }
            variables.append("\(key)=\(value)")
        }
        variables.append("LANG=" + (environment["LANG"] ?? "en_US.UTF-8"))
        return variables
    }

    // MARK: - Co se řekne po `▶`

    /// Věta do stavového řádku po kliknutí na `▶` (#460). `nil` = **mlčet**, řádka odešla.
    ///
    /// Mlčí se schválně u obou úspěšných konců: co se povedlo, je vidět v zásuvce, která se
    /// zrovna otevřela — hláška o tom by byla text navíc nad tím, co má člověk před očima.
    /// Zbylé dva konce vidět **nejsou**: `busy` znamená relaci, ve které se nic nezměnilo, a
    /// `noShell` prázdnou plochu. Bez věty by obojí vypadalo jako tlačítko, které nic nedělá —
    /// tedy přesně to, co u `Terminal.app` hlídal `AppStore.terminalFailure` od #453.
    ///
    /// **Věta jmenuje relaci**, protože jich zásuvka od #460 drží víc — „něco běží“ bez jména by
    /// nutilo hledat, ve které.
    static func resumeNotice(_ outcome: TerminalCommandOutcome, in slot: String) -> String? {
        // **Bez zpětných apostrofů kolem příkazu.** Věty ze stavu jdou do `Text` jako proměnná,
        // ne jako literál, takže z nich SwiftUI markdown nedělá — apostrofy by se nakreslily.
        switch outcome {
        case .started, .sent: nil
        case .busy:
            // **Neříká „ukonči to“ jako jedinou cestu**: přerušit běžící příkaz kvůli tomu, že se
            // někam neposlal jiný, je rozhodnutí člověka. Od #460 k tomu přibyla ta podstatnější
            // věta — relace je vidět, takže se z odmítnutí nestává slepá ulička.
            "V relaci \(slot) něco běží, takže se claude --resume neposlal. "
                + "Zásuvka je na ní přepnutá, tak se podívej, co v ní je."
        case .noShell:
            // Důvod se **nehádá**: `EmbeddedTerminalView.start` už na chybějící `SHELL` sáhne po
            // `/bin/zsh`, takže sem se dojde jedině tehdy, když selhalo i to — a vymyšlená
            // příčina by byla horší než žádná.
            "Shell se v relaci \(slot) nepodařilo spustit, takže se claude --resume nepustil."
        }
    }

    /// Věta pro stav, kdy relace **vůbec nevznikla**, protože strop je plný a všechny běží.
    ///
    /// Mlčet se tady nesmí: nevzniklá záložka vypadá k nerozeznání od rozbitého tlačítka. A věta
    /// musí říct, **co s tím** — zavírací křížek u záložky návrh nekreslí, takže jediná cesta zpět
    /// vede přes ukončení toho, co v některé relaci běží.
    static func slotsFullNotice(_ slot: String) -> String {
        "Zásuvka drží nejvíc \(maxTerminalSlots) relací a ve všech něco běží, "
            + "takže relace \(slot) nevznikla. Ukonči, co v některé běží, a klikni znovu."
    }

    // MARK: - Ukončení aplikace

    /// Na co se aplikace zeptá, než se zavře. `nil` = **neptat se**, nic neběží.
    ///
    /// Do #459 to byl jen počet review (#94, #264). Shell v zásuvce se přidává ze stejného důvodu,
    /// z jakého se ptá na review: **co aplikace spustila, to i ukončí**, takže se s ní zavře
    /// i rozdělaný `claude --resume` v terminálu — a to je věc, kterou se vyplatí potvrdit.
    ///
    /// Věty se liší podle toho, co běží, a je to schválně: „Běží 2 věci“ nedává důvod kliknout na
    /// Zpět, kdežto „Běží review a v terminálu něco běží“ ano.
    static func quitPrompt(reviews: Int, terminals: Int) -> QuitPrompt? {
        guard reviews > 0 || terminals > 0 else { return nil }
        // **Počet terminálů se nevypisuje**, a je to schválně: „ve 2 terminálech“ by si kvůli
        // údaji, o kterém se nerozhoduje, říkalo o skloňování předložky (`v` / `ve`). Rozhoduje
        // se o tom, **jestli** ukončit, ne o tom kolikrát. U review to číslo smysl má — s každým
        // se ztrácí rozdělaná práce —, takže se píše, a tvar drží `Plural`.
        let runs = Plural.czech(reviews, one: "review", few: "review", many: "review")
        let title = switch (reviews, terminals) {
        case (0, _): "V terminálu něco běží. Ukončit teď?"
        case (1, 0): "Běží review. Ukončit teď?"
        case (_, 0): "Běží \(runs). Ukončit teď?"
        case (1, _): "Běží review a v terminálu něco běží. Ukončit teď?"
        case (_, _): "Běží \(runs) a v terminálu něco běží. Ukončit teď?"
        }
        // Text říká, co se stane, ne jen že se něco děje — a **neslibuje víc, než co data unesou**:
        // z nedoběhlého review se dotáhne jen to, co reviewer stihl nahlásit, a ze shellu nic.
        var detail = ""
        if reviews > 0 {
            detail = """
                Běžící session se ukončením zabijí. Co doběhlo, zůstane uložené; z nedoběhlého se \
                po dalším spuštění dotáhne, co reviewer nahlásil do té chvíle.
                """
        }
        if terminals > 0 {
            let shell =
                "Shell v zásuvce se zabije i s tím, co v něm běží — jeho výpis se nikam neukládá."
            detail = detail.isEmpty ? shell : detail + "\n\n" + shell
        }
        return QuitPrompt(title: title, detail: detail)
    }
}
