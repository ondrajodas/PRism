import Foundation

/// Co reviewer dělal, v pořadí, v jakém se to dělo.
///
/// **Přežije restart** (#203). Do té doby se držela jen v paměti s odůvodněním, že se k průběhu
/// člověk vrací hned po běhu; jenže s ní mizelo i `sessionID`, tedy jediná cesta zpátky do session
/// (`claude --resume`) — a nálezy, ke kterým patří, na disku zůstávaly. Ukládá ji `StoredReviewRun`,
/// takže je klíčovaná `headSha` jako všechno ostatní: po novém commitu zestárne s nálezy.
struct ReviewerTimeline: Identifiable, Equatable, Sendable {
    let skill: String
    /// Pracovní strom, ve kterém běh běžel. Podle něj se v ose zkracují cesty — bez toho
    /// začíná každý řádek stejnými sedmdesáti znaky cache.
    let worktree: URL?
    /// Cesta k `claude --resume`. Přijde s prvním eventem session.
    var sessionID: String?
    /// Co běh stál (#148). Přijde s koncem běhu, protože ji nese `result` event — takže
    /// běžící reviewer ji nemá a zabitý ji mít nebude. `nil` je odpověď „nevíme“, ne nula.
    var usage: RunUsage?
    private(set) var entries: [Entry] = []
    /// Kolik událostí se na začátek osy nevešlo (#203). **Musí být vidět** — tiše zkrácená osa
    /// tvrdí, že běh začal uprostřed, a je to tatáž past jako u `droppedFindings`.
    private(set) var droppedEntries = 0
    /// Odvozené údaje, počítané **při zápisu** (#325). Čte je `Policy.lanes` — viz `Digest`.
    private(set) var digest = Digest()

    var id: String { skill }

    /// Doběhl už tenhle běh? Pozná se podle toho, že v ose je jeho konec.
    var isFinished: Bool { digest.finish != nil }

    /// Co se z osy dá odvodit, spočítané **při zápisu, přírůstkově** (#325).
    ///
    /// **Proč to není osm `lazy` průchodů polem, jako do #325.** `Policy.lanes` skládá dráhy při
    /// každém překreslení tabu — a při běžícím review to je několikrát za vteřinu —, takže každý
    /// odvozený údaj tam znamenal průchod až třemi stovkami událostí: kam se běh dostal, jeho
    /// konec, poslední nástroj, počet kroků, počet nálezů, čekání na slot, načtený skill a příznak
    /// zadání. Je to tatáž třída úlohy jako #224: co se počítá při každém překreslení, se pamatuje.
    ///
    /// **Není to druhá kopie osy, je to její souhrn** — a aby se od ní nerozešel (což je ta past,
    /// kterou `CLAUDE.md` u dvou kopií téhož popisuje), drží ho jediné místo: mutující metody
    /// `ReviewerTimeline`. Že souhlasí s průchodem polem, tvrdí `TimelineDigestTests`.
    ///
    /// **Dvě věci se ořezáním osy nesmí zapomenout.** Strop (#325) zahazuje **začátek**, takže by
    /// průchod přeživšími událostmi u dlouhého běhu tvrdil, že session nenaběhla a že nálezy
    /// nenahlásila — a fáze dráhy by po třech stech krocích spadly zpátky na `nedošlo na ni`.
    /// Souhrn je proto u těchhle údajů **monotónní**: co se v ose jednou stalo, se z něj neubírá.
    /// Naopak `toolSteps` a `lastTool` popisují, co je v ose **vidět**, takže ty se ořezáním
    /// zmenšují — přesně jak to má návrh (`prochází kód · 300 kroků` u osy s 214 zahozenými).
    struct Digest: Equatable, Sendable {
        /// Kam se běh dostal: 0 nikam, 1 session, 2 kroky nad kódem, 3 nahlášené nálezy.
        /// **Monotónní** — viz výš.
        var reached = 0
        /// Čekalo se na volný slot? Monotónní: fáze `čeká na slot` se kreslí jen tehdy, když ji
        /// osa zaznamenala, a ořezáním ta událost zmizí jako první.
        var hadQueued = false
        /// Kolik pokusů o nástroj je v ose **vidět**. Ořezáním klesá.
        var toolSteps = 0
        /// Poslední pokus o nástroj — z něj se skládá věta „právě čte…“. Ořezáním zmizí jedině
        /// tehdy, když byl v ose jediný.
        var lastTool: ToolAttempt?
        /// Kolik nálezů reviewer nahlásil. **`nil` = nenahlásil nic, ani prázdný seznam.**
        var reportedFindings: Int?
        /// Konec běhu i s jeho časem. `nil` = neskončil, nebo ho někdo zrušil.
        var finish: Finish?
        /// Který skill si session doopravdy načetla — **první** takový (`Skill` mezi nástroji).
        var loadedSkill: String?
        /// Proč nebylo zadání celé (#345) — **první** takový příznak.
        var intentGap: IntentGap?

        struct Finish: Equatable, Sendable {
            let outcome: ReviewRunOutcome
            let at: Date
        }
    }

    struct Entry: Identifiable, Hashable, Codable, Sendable {
        /// Pořadí v ose. `Date` na identitu nestačí — dva eventy můžou padnout do stejné
        /// milisekundy.
        let id: Int
        let at: Date
        let kind: Kind

        enum Kind: Hashable, Codable, Sendable {
            case queued
            case started
            case tool(ToolAttempt)
            case findings(count: Int)
            /// Zadání pro reviewera nebylo celé (#345). **Není to fáze běhu** — je to fakt
            /// o materiálu, se kterým běh začal, takže osu nikam neposouvá.
            case intentGap(IntentGap)
            case finished(ReviewRunOutcome)
        }
    }

    init(skill: String, worktree: URL? = nil) {
        self.skill = skill
        self.worktree = worktree
    }

    /// Osa poskládaná z uloženého běhu (#203).
    ///
    /// `skill`, `sessionID` a cenu bere z **běhu**, ne z uložené osy: obojí by v souboru leželo
    /// dvakrát a dvě kopie téhož se dřív nebo později rozejdou.
    init(_ run: StoredReviewRun) {
        skill = run.skillID
        worktree = run.timeline?.worktree
        sessionID = run.sessionID
        usage = run.usage
        entries = run.timeline?.entries ?? []
        droppedEntries = run.timeline?.dropped ?? 0
        // Souhrn se z uložené osy počítá **jedním** průchodem, a to jen tady: soubor přichází
        // hotový, takže není nad čím přírůstkovat. Vyjde z něj totéž, co by vyšlo průchodem
        // v `Policy.lanes` — a přesně to je ta shoda, kterou hlídá `TimelineDigestTests`.
        digest = Self.digest(of: entries)
        // Strop platí i na to, co přijde z disku. Soubor ho má mít (`stored(limit:)`), ale
        // spolehnout se na cizí data znamená mít v okně tři tisíce řádků kvůli starému formátu.
        trimToLimit()
        completeTail(from: run)
    }

    /// Souhrn z hotové osy, jedním průchodem. **Jediné místo, kde se počítá jinak než při zápisu**
    /// — a proto se drží vedle `note(_:)`, ať je vidět, že obojí čte tytéž případy.
    private static func digest(of entries: [Entry]) -> Digest {
        var digest = Digest()
        for entry in entries { note(entry, into: &digest) }
        return digest
    }

    /// Co jedna událost přidá do souhrnu.
    ///
    /// **Osu neposouvá příznak zadání** (#345): je to fakt o materiálu, se kterým běh začal, ne
    /// o tom, co běh dělal. Kdyby posouval, dráha ve frontě by tvrdila, že už něco dělá.
    private static func note(_ entry: Entry, into digest: inout Digest) {
        switch entry.kind {
        case .queued:
            digest.hadQueued = true
        case .started:
            digest.reached = max(digest.reached, 1)
        case .tool(let tool):
            digest.reached = max(digest.reached, 2)
            digest.toolSteps += 1
            digest.lastTool = tool
            // Načtený skill je **první** takový: session si ho bere na začátku a pozdější
            // `Skill` by přepsal to, čím doopravdy začala.
            if tool.name == "Skill", digest.loadedSkill == nil, let detail = tool.detail {
                digest.loadedSkill = detail
            }
        case .findings(let count):
            digest.reached = max(digest.reached, 3)
            digest.reportedFindings = count
        case .intentGap(let gap):
            if digest.intentGap == nil { digest.intentGap = gap }
        case .finished(let outcome):
            digest.finish = Digest.Finish(outcome: outcome, at: entry.at)
        }
    }

    /// Ořeže začátek osy na strop a přizná to (#325).
    ///
    /// Ubírá se **jen to, co je v ose vidět** — `toolSteps` a s ním případně `lastTool` (ten jedině
    /// tehdy, když byl krok v ose jediný; ořez zpředu jiný poslední krok sebrat nemůže). Zbytek
    /// souhrnu je monotónní, viz `Digest`.
    private mutating func trimToLimit() {
        while entries.count > Self.entryLimit {
            if case .tool = entries[0].kind {
                digest.toolSteps -= 1
                if digest.toolSteps == 0 { digest.lastTool = nil }
            }
            entries.removeFirst()
            droppedEntries += 1
        }
    }

    /// Doplní **konec** osy z běhu, pod kterým leží.
    ///
    /// **Uložená osa svůj konec neobsahuje**, a není to výjimka: snímek pro zápis se v `runSkills`
    /// bere dřív, než proud událostí dojede, takže v souboru chybí `hlásí nálezy` i `doběhlo`.
    /// Změřeno na skutečné cache — **7 ze 7** os po skutečném běhu je bez konce (osy vyrobené
    /// v testech ho mají, proto to testy nechytily). Bez doplnění by tab `Průběh` po restartu tvrdil
    /// `nedoběhlo — běh někdo zrušil` nad doběhlým review a `nálezy vůbec nenahlásilo` nad tím,
    /// které nahlásilo prázdný seznam; chip vedle toho ukazuje `čisto`.
    ///
    /// Doplňuje se **jen to, co běh sám ví** — jeho výsledek a jeho počet nálezů, ne dohad — a jen
    /// tehdy, když to v ose není. Dvě věci, které se tím zachovávají:
    /// - `calledReportFindings == false` nedoplní **nic**: reviewer, který nálezy nenahlásil, je
    ///   vlastní stav a `hlásí nálezy` u něj zůstává nedotčené;
    /// - **prázdná osa se nedoplňuje**, takže běh, jehož osa se vůbec neuložila, zůstane bez osy
    ///   (v tabu z něj je `bez průběhu`, ne vymyšlený průběh o dvou událostech).
    private mutating func completeTail(from run: StoredReviewRun) {
        // **Příznak zadání se za průběh nepočítá** (#345): je to fakt o materiálu, se kterým běh
        // začal, ne o tom, co běh dělal. Osa, ve které je jen on, je pořád osa bez průběhu — a
        // doplnit jí konec by z ní udělala dráhu, která tvrdí `doběhlo` nad prázdnými fázemi.
        let progress = entries.contains { if case .intentGap = $0.kind { false } else { true } }
        guard progress, !isFinished else { return }
        let hasFindings = entries.contains { if case .findings = $0.kind { true } else { false } }
        if !hasFindings, run.calledReportFindings {
            // Nahlášený počet, ne jen ten uložený: nález, který se nepodařilo přečíst, reviewer
            // nahlásil — jen se z něj nedal složit nález (`droppedFindings`).
            append(.findings(count: run.findings.count + run.droppedFindings), at: run.finishedAt)
        }
        append(.finished(run.outcome), at: run.finishedAt)
    }

    /// Co se z osy uloží. Ořezává se **začátek**, ne konec: kdo se do osy dívá po restartu,
    /// hledá, čím to skončilo.
    ///
    /// **Od #325 tady obvykle není co ořezávat** — strop platí i na živou osu, takže se do souboru
    /// vejde celá. Ořez zůstává, protože `limit` se dá zvenčí snížit (dělají to testy) a protože
    /// „co se ukládá“ nemá záležet na tom, že si to jinde už někdo ořezal.
    func stored(limit: Int = Self.entryLimit) -> StoredTimeline {
        let dropped = max(entries.count - limit, 0)
        return StoredTimeline(
            worktree: worktree,
            entries: Array(entries.suffix(limit)),
            dropped: droppedEntries + dropped
        )
    }

    /// Strop událostí v ose — **jeden pro živou i uloženou** (#325).
    ///
    /// Delší běh jich nadělá stovky (každé čtení souboru je jedna) a záznam leží vedle nálezů,
    /// které se čtou při každém startu. Do #325 platil jen na ukládání (`storedEntryLimit`), takže
    /// se za běhu držely stovky událostí, které po restartu zmizely — a nikde to nebylo napsané.
    /// **Vyšší strop pro živou osu by sliboval, že se ke krokům dá vrátit; nižší by zahodil kroky,
    /// které v souboru zůstanou.** Se stejným číslem platí, že co bylo vidět za běhu, je vidět
    /// i po restartu.
    static let entryLimit = 300

    /// Který skill si session doopravdy načetla. `nil` = žádný.
    var loadedSkill: String? { digest.loadedSkill }

    /// Načetl se **jiný** skill, než jaký byl nastavený?
    ///
    /// Stává se to, když nakonfigurované id na nic nemapuje: model si domyslí nejbližší,
    /// co jde oslovit — ověřeno u #78, kde se z `code-review` stalo `code-review:code-review`.
    /// Bez upozornění by osa i chip tvrdily, že běžel nastavený skill, a běžel by jiný.
    ///
    /// Běh **bez** načteného skillu se sem nepočítá: reviewer, který si žádný nevzal, udělal
    /// obecné review, a to je jiná situace než záměna.
    var loadedADifferentSkill: Bool {
        guard let loadedSkill else { return false }
        return loadedSkill != skill
    }

    /// Proč zadání pro reviewera nebylo celé (#345). `nil` = bylo, nebo se na to neptalo.
    ///
    /// Počítá se **z osy**, stejně jako `loadedSkill`, a je to ten důvod, proč to není pole:
    /// s událostí to **přežije restart** (ukládá se ve `StoredTimeline`), takže tab `Průběh`
    /// tvrdí o starším běhu totéž, co tvrdil, když běžel.
    ///
    /// Bere se **první** událost. Za jeden běh přijde jedna; kdyby jich přišlo víc, je pravda ta,
    /// s jakou běh začal — ne ta, kterou by přepsalo pozdější hlášení.
    var intentGap: IntentGap? { digest.intentGap }

    mutating func record(_ progress: ReviewProgress, at time: Date) {
        switch progress {
        case .queued:
            append(.queued, at: time)
        case .started(let sessionID):
            self.sessionID = sessionID
            append(.started, at: time)
        case .attemptedTool(let tool):
            append(.tool(tool), at: time)
        case .resolvedTool(let resolution):
            resolve(resolution, at: time)
        case .findings(let count):
            append(.findings(count: count), at: time)
        case .intentGap(let gap):
            append(.intentGap(gap), at: time)
        }
    }

    mutating func finish(_ outcome: ReviewRunOutcome, usage: RunUsage? = nil, at time: Date) {
        self.usage = usage
        append(.finished(outcome), at: time)
    }

    /// Zavře krok, na který dorazila odpověď (#326).
    ///
    /// **Nepřidává událost, mění tu, která už v ose je.** Jeden `tool_use` je jeden krok, ať se
    /// o něm dozvíme cokoli dalšího — druhý řádek „a takhle to dopadlo“ by osu zdvojil a sledování
    /// konce ve výpisu (#325) by skákalo na událost, která žádný nový krok není.
    ///
    /// Páruje **poslední** krok s tím `id`; odpověď na krok, který v ose není, ji nechá být.
    /// Jestli smí přepsat, co už krok má, rozhoduje `Policy.replacesToolOutcome` — **tatáž funkce,
    /// jakou se řídí parser**. Dokud to byla vlastní podmínka „jen nezavřený krok“, záchrana
    /// z `permission_denials` (`failed` → `denied`) se do souhrnu propsala a do kroku, který se
    /// kreslí, ne; nálezem Copilota na #394.
    ///
    /// Trvání se počítá z časů osy, takže **záporné být nemůže** ani po posunu systémových hodin —
    /// tatáž pojistka jako u `RunUsageText.elapsed`.
    private mutating func resolve(_ resolution: ToolResolution, at time: Date) {
        guard let index = entries.lastIndex(where: { entry in
            guard case .tool(let tool) = entry.kind else { return false }
            return tool.id == resolution.id
                && Policy.replacesToolOutcome(tool.outcome, with: resolution.outcome)
        }), case .tool(var tool) = entries[index].kind else { return }

        let entry = entries[index]
        let wait = Duration.seconds(max(time.timeIntervalSince(entry.at), 0))
        tool.outcome = resolution.outcome.measured(after: wait)
        entries[index] = Entry(id: entry.id, at: entry.at, kind: .tool(tool))
        // Souhrn nese **hodnotu** posledního kroku, ne odkaz na něj, takže se odpověď na ten
        // poslední musí propsat i do něj. Pozná se podle `id` — je unikátní na `tool_use`, takže
        // shoda znamená „tohle je ten krok, který je v souhrnu“.
        if digest.lastTool?.id == resolution.id { digest.lastTool = tool }
    }

    /// Identita se počítá **z poslední události, ne z počtu**. V živé ose je to totéž, ale osa
    /// poskládaná z uloženého běhu je zkrácená (`droppedEntries`), takže si nechává původní čísla —
    /// a podle počtu by doplněný konec dostal číslo menší než jeho předchůdce.
    private mutating func append(_ kind: Entry.Kind, at time: Date) {
        let entry = Entry(id: (entries.last?.id ?? -1) + 1, at: time, kind: kind)
        entries.append(entry)
        Self.note(entry, into: &digest)
        trimToLimit()
    }
}


/// Osa, jak se ukládá k běhu (#203).
///
/// Vlastní typ, ne `ReviewerTimeline` samotná: ta nese i to, co `StoredReviewRun` už má
/// (`skill`, `sessionID`, cenu), a dvě kopie téhož v jednom souboru se rozejdou.
struct StoredTimeline: Codable, Hashable, Sendable {
    /// Pracovní strom, ve kterém běh běžel — podle něj se v ose zkracují cesty.
    var worktree: URL?
    var entries: [ReviewerTimeline.Entry] = []
    /// Kolik událostí se na začátku nevešlo do stropu.
    var dropped = 0
}
