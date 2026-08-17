import Foundation

/// Kde má aplikace svoje soubory.
///
/// Tvrdá podmínka: **nikdy nesahat na uživatelovy klony.** Ty mohou být rozdělané, na jiné
/// branchi nebo mít vlastní worktrees. Všechno, co si aplikace naklonuje, leží pod jedním
/// kořenem, který si drží sama — a `root` je injektovatelný, aby testy nikdy nesáhly do
/// toho skutečného.
///
/// Kromě pracovních kopií sem patří i uložené výsledky review. Vlastní typ s vlastním
/// kořenem by znamenal dvě místa, která se můžou v kořeni rozejít — a `CacheLayout` je
/// právě to jedno místo, které ví, co kde leží.
struct CacheLayout: Sendable, Equatable {
    let root: URL

    /// Cache té instance, která právě běží.
    ///
    /// Jméno složky se bere z `CFBundleName`, ne z konstanty — na tom stojí sloty (#228).
    /// Build ve slotu `a` má v plistu `PRism-a`, takže si nese vlastní konfiguraci, klony
    /// i uložené nálezy a **nesáhne na data instance, se kterou se pracuje**. Rozestavěný
    /// build umí mít rozbitou persistenci a smazat rozdělaný draft je ztráta ručně psané
    /// práce; oddělit ho je levnější než to řešit až potom.
    static let applicationSupport = CacheLayout(named: bundleName(of: .main))

    /// Cache pojmenované instance. Oddělená od `applicationSupport` proto, aby se dala
    /// otestovat shoda dvou různých jmen bez sahání na `Bundle.main`.
    init(named name: String) {
        self.init(root: URL.applicationSupportDirectory.appending(path: name))
    }

    init(root: URL) {
        self.root = root
    }

    /// Jméno bundlu, pod kterým aplikace drží svoje soubory.
    ///
    /// Chybějící klíč **shazuje aplikaci** a nespadne na `?? "PRism"`. Tichý default by
    /// znamenal, že build ve slotu s rozbitým plistem sáhne do cache hlavní instance — tedy
    /// právě to, čemu se sloty vyhýbají, a to potichu. `CFBundleName` je přitom v `Info.plist`
    /// napsané napevno, takže jeho absence není provozní stav, ale rozbitý bundle.
    private static func bundleName(of bundle: Bundle) -> String {
        guard let name = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String,
            !name.isEmpty
        else {
            fatalError("Bundle nemá CFBundleName — bez něj není jasné, čí je cache.")
        }
        return name
    }

    /// Kde leží klony a stromy — eviction je potřebuje projít, ne jen skládat cesty.
    var repositories: URL { root.appending(path: "repos") }
    var worktrees: URL { root.appending(path: "worktrees") }

    /// Uložené výsledky review. **Mimo dosah eviction** — ta chodí jen po `repositories`
    /// a `worktrees`, protože nálezy jsou kilobajty a řídí se vlastní lhůtou, ne rozpočtem
    /// na místo.
    var reviews: URL { root.appending(path: "reviews") }

    /// Rozdělaná review. **Mimo dosah eviction**, ze stejného důvodu jako `reviews/` —
    /// a tady o to víc: je to ručně psaná práce, kterou by rozpočet na místo neměl smazat.
    var drafts: URL { root.appending(path: "drafts") }

    /// Konfigurace. Leží v kořeni cache, ne pod `reviews/` — edituje se ručně a má být
    /// vidět hned, jakmile člověk složku otevře.
    var configFile: URL { root.appending(path: "config.json") }

    /// Počitadlo dnešních automatických review. Vedle konfigurace, ne v ní: `config.json`
    /// píše uživatel, tohle aplikace.
    var autoRunsFile: URL { root.appending(path: "auto-runs.json") }

    /// Které PR už aplikace ohlásila jako nové (#85). Snímek posledního úspěšného tiku, ne
    /// rostoucí log — viz `AnnouncedPullRequests`.
    var announcedFile: URL { root.appending(path: "announced.json") }

    /// Co dneska stálo review (#148). Vedle počitadla automatických běhů a ze stejného
    /// důvodu: píše to aplikace, ne člověk.
    var spendFile: URL { root.appending(path: "spend.json") }

    /// Běhy, které začaly a o kterých se neví, jestli doběhly (#97). Po startu je v něm to,
    /// co aplikaci nepřežilo — viz `InterruptedRuns`.
    var interruptedFile: URL { root.appending(path: "interrupted.json") }

    /// Podprocesy, které aplikace právě drží (#351). Po startu je v něm to, co aplikaci
    /// **přežilo** — osiřelý `claude -p`, kterého má úklid zabít; viz `RunningSessions`.
    ///
    /// Vedle `interrupted.json`, ne v něm: tohle je klíčované operačním systémem
    /// (`(pid, startedAt)`), kdežto přerušené běhy `ReviewRunKey`.
    var sessionsFile: URL { root.appending(path: "sessions.json") }

    /// Výsledky review jednoho PR na jednom commitu: `reviews/<owner>/<repo>/<pr>-<sha>.json`.
    ///
    /// Zanořeno pod repo ze stejného důvodu jako stromy: ploché jméno se nedá filtrovat
    /// podle prefixu, takže úklid jednoho repa by sahal na cizí.
    func reviewFile(for pr: PRIdentifier, at headSha: String) -> URL {
        reviews(of: pr.repo).appending(path: "\(pr.number)-\(headSha).json")
    }

    func reviews(of repo: RepoID) -> URL {
        reviews.appending(path: repo.owner).appending(path: repo.name)
    }

    /// Rozdělané review jednoho PR: `drafts/<owner>/<repo>/<pr>.json`.
    ///
    /// Bez `headSha` v názvu, na rozdíl od nálezů: draft je jeden na PR a nový commit ho
    /// nezahazuje, jen zablokuje odeslání. Zanořeno pod repo ze stejného důvodu jako
    /// všechno ostatní — ploché jméno se nedá filtrovat podle prefixu.
    func draftFile(for pr: PRIdentifier) -> URL {
        drafts(of: pr.repo).appending(path: "\(pr.number).json")
    }

    func drafts(of repo: RepoID) -> URL {
        drafts.appending(path: repo.owner).appending(path: repo.name)
    }

    /// Leží cesta uvnitř kořene, i po rozbalení symlinků?
    ///
    /// Symlink v cestě umí mazání vyvést ven: `removeItem` přes odkaz v rodičovské
    /// komponentě smaže **cíl**, ne odkaz. Aplikace si takový odkaz sama nevyrobí, ale
    /// „nikdy nesahat na uživatelovy klony“ je tvrdá podmínka — a podle výpisu z disku maže
    /// `CacheEviction` i `ReviewStore`.
    ///
    /// Rozbaluje se **rodič**, ne cesta samotná: soubor se teprve může zakládat, a odkaz na
    /// cíl mimo cache je neškodný — `removeItem` smaže odkaz, ne to, kam ukazuje.
    func contains(_ url: URL) -> Bool {
        let root = root.resolvingSymlinksInPath().path(percentEncoded: false)
        let parent = url.deletingLastPathComponent()
            .resolvingSymlinksInPath()
            .path(percentEncoded: false)
        return parent == root || parent.hasPrefix(root + "/")
    }

    /// Je ta cesta symlink?
    ///
    /// **Doplňuje `contains`, nenahrazuje ho.** `contains` řeší mazání (rozbaluje **rodiče**,
    /// protože `removeItem` přes odkaz v cestě smaže cíl), tohle řeší **čtení**: odkaz na
    /// soubor `FileManager.enumerator` do výpisu **dá** — na rozdíl od odkazu na složku, do
    /// které nesestupuje (změřeno u #65). Přečíst by se tím dal soubor mimo cache.
    ///
    /// `contains` to nezachytí, protože rozbaluje symlinky na obou stranách, takže cíl vyjde
    /// rovný cíli. Odkaz se proto musí odmítnout výslovně.
    ///
    /// Bydlí to tady, ne v jednotlivých storech: potřebují to dva (`ReviewStore`
    /// i `ReviewDraftStore`) a je to totéž pravidlo o hranici cache jako `contains` (#106).
    func isSymbolicLink(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true
    }

    /// Bare klon repa: `repos/<owner>/<repo>.git`.
    func bareClone(for repo: RepoID) -> URL {
        repositories
            .appending(path: repo.owner)
            .appending(path: "\(repo.name).git")
    }

    /// Pracovní strom jednoho review: `worktrees/<owner>/<repo>/<pr>-<sha>`.
    ///
    /// `headSha` je v názvu schválně — nálezy na něm visí, takže dva běhy nad různými
    /// commity téhož PR si nesmí sáhnout na stejný strom.
    func worktree(for pr: PRIdentifier, at headSha: String) -> URL {
        // Celý sha, ne zkrácený: cesta je zároveň klíč koordinátoru, takže shoda prefixu
        // dvou commitů by dva běhy poslala na tentýž strom.
        worktrees(of: pr.repo).appending(path: "\(pr.number)-\(headSha)")
    }

    /// Zadání jednoho review: `worktrees/<owner>/<repo>/<pr>-<sha>.md` (#120).
    ///
    /// **Vedle stromu, ne v něm**, a je to celý důvod, proč to leží tady a ne v `worktree(for:at:)`:
    /// soubor uvnitř pracovní kopie by se objevil v `git status` i v `git diff`, takže by ho
    /// reviewer viděl jako součást změny, kterou má posoudit. Je to tatáž úvaha jako
    /// u `lastUsedMarker`, který ze stejného důvodu leží vedle klonu.
    ///
    /// Klíčem je `(PR, headSha)`, stejně jako u stromu: zadání se váže k témuž commitu, sdílí ho
    /// všechny skilly jednoho review a po novém commitu zestárne spolu se stromem i s nálezy.
    ///
    /// **Úklid jde tou cestou, která už existuje.** `CacheEviction.evict` maže celé
    /// `worktrees(of:)`, takže soubor jde s klonem, a `discardUnwantedWorktrees` parsuje číslo PR
    /// z názvu (`42-<sha>.md` → 42), takže odejde s tím, jak PR vypadne ze sledovaného seznamu.
    /// Vlastní mazací cesta by byla další místo, na které se dá zapomenout.
    func intentFile(for pr: PRIdentifier, at headSha: String) -> URL {
        // Přípona `.md` je zároveň to, co soubor odlišuje od pracovní kopie téhož PR — jméno
        // stromu je `<pr>-<sha>` bez ní, takže se nemají čím přebít.
        worktrees(of: pr.repo).appending(path: "\(pr.number)-\(headSha).md")
    }

    /// Stromy jsou zanořené pod repo, ne slepené do jednoho jména.
    ///
    /// Ploché `owner-repo-pr-sha` se nedá spolehlivě filtrovat podle prefixu: `keboola-kbc-`
    /// sedí i na `keboola-kbc-stacks-42-…`, takže úklid jednoho repa by sahal na stromy
    /// jiného — a to i takového, ve kterém zrovna běží review.
    func worktrees(of repo: RepoID) -> URL {
        worktrees.appending(path: repo.owner).appending(path: repo.name)
    }

    /// Značka „klon doběhl celý“, zapsaná až po úspěšném `git clone`.
    ///
    /// Vlastní soubor schválně, ne odvozování z toho, co je uvnitř klonu. `git` zakládá
    /// `HEAD`, `config` i `refs/` **hned na začátku**, takže po zabitém klonu složka
    /// vypadá jako hotový repozitář — ověřeno. Fetch nad ní pak projde, ale `HEAD`
    /// zůstane `ref: refs/heads/.invalid` a hlavně chybí `remote.origin.promisor`:
    /// klon tiše přestane být partial a od té chvíle tahá všechny bloby.
    func cloneMarker(for repo: RepoID) -> URL {
        bareClone(for: repo).appending(path: "prism-clone-complete")
    }

    /// Kdy se s repem naposledy pracovalo — podle toho se rozhoduje, co z cache odejde
    /// první.
    ///
    /// **Vedle** klonu, ne uvnitř: zapisuje se ještě před klonováním (jinak by rozklonované
    /// repo nemělo razítko a eviction by ho v LRU vzala jako první), a `git clone` odmítne
    /// klonovat do složky, ve které už něco leží. Eviction ho maže spolu s klonem.
    func lastUsedMarker(for repo: RepoID) -> URL {
        repositories.appending(path: repo.owner).appending(path: "\(repo.name).last-used")
    }
}
