import Foundation

/// Co se stalo s konflikty při srovnání větve (#467) — **výsledek session, která smí psát**.
///
/// **Dvě různá tvrzení v jednom typu, a nesmí se slít.** `files` je **účet session** o tom, co
/// s kterým souborem udělala (vzala obojí, ruční slití, beze změny) — je to text od modelu, tedy
/// tvrzení, které aplikace neumí ověřit. `diff` je proti tomu **doklad z `gitu`**: co z toho
/// doopravdy vzniklo. Návrh (sekce 36) je proto kreslí vedle sebe a nadpisek u výpisu říká *Co
/// s tím session udělala*, ne *Co se stalo* — u nevratné akce má být poznat, která polovina je
/// čí.
///
/// **Nedrží se na disku.** Po restartu aplikace se z cache dá přečíst jedině to, co v ní leží
/// (přerovnaná větev, rozdělaný rebase) — účet session se z pracovního stromu zrekonstruovat nedá
/// a vymyslet se nesmí. Mezistav *přerovnáno, nepřetlačeno* proto po restartu nese `resolution
/// == nil` a sheet o konfliktech mlčí; leží v něm ale hlava, ze které se rebasovalo, takže se
/// pushuje pořád to samé.
struct ConflictResolution: Hashable, Sendable {
    /// Co session udělala s kterým souborem — **v pořadí, ve kterém kolidovaly**.
    var files: [ResolvedConflictFile]
    /// Diff toho, co vzniklo — `git diff HEAD -- <kolidující soubory>` v rozdělaném rebase.
    ///
    /// **Text z `gitu`, ne popis od session** (zadání #467). Prázdný znamená „nepodařilo se
    /// přečíst“, a sheet to řekne: prázdné místo pod nadpiskem by se čtlo jako „nic se nezměnilo“.
    var diff: String
    /// Kolik kol session potřebovala. Rebase se zastaví u **každého** commitu, který koliduje,
    /// takže kol může být víc než jedno — a každé stojí peníze.
    var rounds: Int
    /// Co jedna session utratila, sečteno přes kola. `nil` = nenahlásila (zabitá session).
    var usage: RunUsage?
    /// **Čím si session není jistá** — vlastní pole, ne součást účtu u souboru.
    ///
    /// Zadání #467: „ať do výsledku napíše, čím si jistá není“. Je to jediná věta, kterou model
    /// píše volně, takže se sráží na jeden řádek jako každý cizí text.
    var caveats: String?

    init(
        files: [ResolvedConflictFile] = [],
        diff: String = "",
        rounds: Int = 0,
        usage: RunUsage? = nil,
        caveats: String? = nil
    ) {
        self.files = files
        self.diff = diff
        self.rounds = rounds
        self.usage = usage
        self.caveats = caveats
    }
}

/// Jeden soubor, který kolidoval, a co s ním session udělala (#467).
struct ResolvedConflictFile: Hashable, Sendable, Identifiable {
    /// Cesta **relativní k pracovnímu stromu** — tak ji hlásí `git diff --name-only`, a tak se
    /// vejde do panelu i do sheetu. Absolutní cesta by byla sedmdesát znaků cache před jménem.
    let path: String
    let action: Action

    /// Co s tím soubor session udělala. **Účet session, ne měření** — hodnoty jsou z návrhu
    /// (sekce 36).
    enum Action: String, Hashable, Sendable {
        /// Obě strany zůstaly, jen se poskládaly za sebe.
        case tookBoth
        /// Session ten soubor doopravdy slila rukou.
        case manual
        /// Nechala ho tak, jak ho `git` nechal — tedy jednu stranu bez úprav.
        case unchanged
        /// **Nerozřešeno.** Vlastní případ, ne chybějící řádek: soubor, o kterém výpis mlčí, by
        /// se čtl jako vyřešený.
        case unresolved

        /// Co je u souboru napsané. Návrh sekce 36 kreslí první tři; `nevyřešeno` k nim patří
        /// z toho, že session nemusí stačit.
        var czechLabel: String {
            switch self {
            case .tookBoth: "vzala obojí"
            case .manual: "ruční slití"
            case .unchanged: "beze změny"
            case .unresolved: "nevyřešeno"
            }
        }

        /// Je to hotové? Na tom stojí to, jestli se dá pokračovat — ne kresba.
        var isResolved: Bool { self != .unresolved }

        /// **Sáhla na ten soubor session?** Rozhoduje o glyfu `✓` / `—` a o tónu popisku
        /// (návrh sekce 36: `rv-av done ✓` u slitých, `rv-av wait —` u `beze změny`).
        ///
        /// **Vlastní otázka, ne `isResolved`**, a je to rozdíl, kvůli kterému ta vlastnost vznikla:
        /// `beze změny` je vyřešené (dá se commitnout), ale session na něj **nesáhla** — a `✓` u něj
        /// tvrdilo, že za to někdo ručí. Zaměnit ty dvě otázky znamená, že se z výpisu nepozná, kde
        /// se doopravdy slévalo.
        var isTouched: Bool {
            switch self {
            case .tookBoth, .manual: true
            case .unchanged, .unresolved: false
            }
        }
    }

    var id: String { path }
}

/// Jak dopadlo jedno kolo session nad konflikty (#467).
///
/// **Nerozřešený konflikt není chyba volání**, tak jako u revieweera a u rozhovoru: session
/// doběhla, jen na to nestačila — a to je výsledek, který se ukazuje, ne výjimka. Vyhodí se jedině
/// `CancellationError`.
struct ConflictAnswer: Sendable, Equatable {
    /// Účet session po souborech. Prázdný = neřekla nic, co by šlo přečíst.
    var files: [ResolvedConflictFile] = []
    /// Čím si není jistá.
    var caveats: String?
    var usage: RunUsage?
    /// Věta pro okno, když session nedoběhla. `nil` = doběhla.
    var failure: String?
    /// **Cesty, do kterých session psala mimo svůj pracovní strom.**
    ///
    /// Prázdné je normální stav — brána v `--allowedTools` je změřená (viz `ConflictCommand`)
    /// a takový pokus odmítne. Je to **druhá vrstva**: kdyby se ta brána někdy změnila, pozná se
    /// to tady a výsledek se **nepřijme**, místo aby se potichu commitl.
    var writesOutside: [String] = []
}
