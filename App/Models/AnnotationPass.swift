import Foundation

/// Co anotační session (#524) na tomhle PR zatím udělala.
///
/// **Jen v paměti, jako přeskočení routingu** (`AppStore.routingSkips`): dráha `anotace` v tabu
/// `Průběh` je záznam toho, co se **právě děje**, a po restartu z ní má zbýt to, co leží na disku —
/// tedy výsledek, ne průběh. Ukládat ji by znamenalo druhou kopii toho, co už `StoredAnnotations`
/// nese.
///
/// **Není to `ReviewerTimeline`** a je to rozhodnutí, ne zjednodušení. Osa je plný záznam kroků
/// s vlastním stropem, ořezáváním a `Codable` výčtem událostí; anotační session má v okně **jednu
/// dráhu bez rozbalovacího výpisu**, takže by z osy zbyl strop, který nikdo nevyčerpá, a případ
/// `findings(count:)` v ukládaném enumu, který se u anotací nikdy nepoužije. Souhrn je proti tomu
/// pět hodnot a počítá se **při zápisu**, přesně jako `ReviewerTimeline.Digest` (#325).
struct AnnotationPass: Equatable, Sendable {
    /// Pracovní strom, ve kterém session běží — z něj se v dráze zkracují cesty.
    let worktree: URL?
    /// Hlava, nad kterou se běží.
    ///
    /// **Drží ji i průběh, ne jen uložený výsledek** (tvrdá podmínka č. 5). Bez ní by dráha
    /// v tabu `Průběh` po pushi dál tvrdila „popsáno, 1 anotace“ o diffu, ze kterého se v okně
    /// nic nekreslí — anotace vázané na starou hlavu se totiž nevydají. Rozhoduje
    /// `Policy.annotationLane(pass:stored:head:)`.
    let headSha: String
    let startedAt: Date
    /// Cesta k `claude --resume`. Přijde s prvním eventem session.
    var sessionID: String?
    /// Poslední pokus o nástroj — z něj se skládá věta „právě čte…“.
    var lastTool: ToolAttempt?
    /// Kolik pokusů o nástroj zatím bylo.
    var toolSteps = 0
    /// Kolik anotací hunků dorazilo. **`nil` = nenahlásila nic, ani prázdný seznam.** Je to tatáž
    /// úmluva jako u `reportedFindings` na dráze — a **není to počet nálezů**, viz `ReviewerLane.Kind`.
    var hunks: Int?
    /// Kolik souborů dostalo druh změny. `nil` se čte stejně jako u `hunks`.
    var files: Int?
    /// Kolik položek odpovědi se nepodařilo přečíst. Přijde **s koncem**, jako počty: odpověď je
    /// jedna a celá.
    var dropped = 0
    /// Konec běhu i s jeho časem. `nil` = běží, nebo ho někdo zrušil.
    var finish: Finish?
    /// Co běh stál. Přijde s koncem, takže **zabitá session ji nemá** — `nil` je odpověď „nevíme“.
    var usage: RunUsage?
    /// Kam se běh dostal: 0 nikam, 1 session, 2 kroky nad kódem, 3 nahlášené anotace.
    /// **Monotónní**, jako u osy revieweera: co se jednou stalo, se neodebírá.
    private(set) var reached = 0

    struct Finish: Equatable, Sendable {
        let outcome: ReviewRunOutcome
        let at: Date
    }

    init(worktree: URL?, headSha: String, startedAt: Date) {
        self.worktree = worktree
        self.headSha = headSha
        self.startedAt = startedAt
    }

    /// Doběhl už běh? Pozná se podle toho, že má konec.
    var isFinished: Bool { finish != nil }

    /// Zapíše jednu událost. Souhrn se počítá **tady**, ne průchodem při každém překreslení.
    mutating func record(_ progress: AnnotationProgress) {
        switch progress {
        case .started(let sessionID):
            self.sessionID = sessionID
            reached = max(reached, 1)
        case .attemptedTool(let tool):
            lastTool = tool
            toolSteps += 1
            reached = max(reached, 2)
        case .annotated(let hunks, let files):
            self.hunks = hunks
            self.files = files
            reached = max(reached, 3)
        }
    }

    /// Zapíše konec běhu.
    ///
    /// **Počty se tady dopisují z výsledku**, protože průběžná událost nemusí dorazit: hlásí se
    /// ve chvíli, kdy přijde `result` (odpovědí je poslední sdělení, viz `AnnotationSchema`),
    /// a když se proud zavře dřív, než se stihne předat, zbyla by dráze `nil` — tedy tvrzení
    /// „odpověď se nedala přečíst“, což je **vlastní stav** a ne tenhle.
    ///
    /// **Jen když odpověď přišla.** Nepřečtená odpověď počty nedopisuje ani jako nuly: nula by
    /// v dráze znamenala „nemá co dodat“.
    mutating func finish(_ run: AnnotationRun, at moment: Date) {
        if run.answered {
            hunks = run.hunks.count
            files = run.files.count
            reached = max(reached, 3)
        }
        dropped = run.dropped
        usage = run.usage
        finish = Finish(outcome: run.outcome, at: moment)
    }

    /// Zapíše konec běhu, ze kterého nevypadl výsledek — spadlý start, zrušení.
    mutating func finish(_ outcome: ReviewRunOutcome, at moment: Date) {
        finish = Finish(outcome: outcome, at: moment)
    }
}
