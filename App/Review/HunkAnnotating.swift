import Foundation

/// Zadání jedné anotační session (#524).
struct AnnotationRequest: Sendable, Equatable {
    let pullRequest: PRIdentifier
    /// Hlava, nad kterou se anotuje. Putuje **s požadavkem**, jako všude jinde: session má doběhnout
    /// nad tou hlavou, se kterou začala, i kdyby mezitím přišel push.
    let headSha: String
    /// Pracovní strom na hlavě PR — **tentýž, jaký dostal reviewer** (tvrdá podmínka č. 3).
    let worktree: URL
    /// Commit, proti kterému se diffuje.
    let baseSha: String
    /// Za jak dlouho se session zabije.
    ///
    /// **Tentýž limit jako review** (#320), ne vlastní číslo — a je to tatáž úvaha jako u kontroly
    /// nálezů (#150): je to tatáž session, tentýž pracovní strom a tytéž peníze, takže kdo u pomalého
    /// repa limit zvedá, zvedá ho kvůli tomu repu. Vlastní kratší strop by z pomalé anotace udělal
    /// `timedOut`; strop, který se nevyčerpá, nestojí nic.
    let timeout: Duration
}

/// Co se v anotační session právě děje — podklad pro dráhu `anotace` v tabu `Průběh`.
enum AnnotationProgress: Sendable, Equatable {
    /// Session naběhla.
    case started(sessionID: String)
    /// Session si řekla o nástroj. **Pokus, ne použití** — odmítnutý nástroj je tu taky.
    case attemptedTool(ToolAttempt)
    /// Kolik anotací dorazilo.
    ///
    /// **Přijde jednou, na konci** — odpovědí je poslední sdělení (`AnnotationSchema`), takže dřív
    /// není co počítat. Je to rozdíl proti dráze revieweera, kde nálezy přibývají v průběhu, a je
    /// vidět v okně: fáze `píše anotace` skočí z prázdné rovnou na hotovou.
    ///
    /// **Není to `findings(count:)` a nesmí se s tím slít**: dráha z toho skládá jinou větu a číslo
    /// nálezů zůstává u anotační dráhy navěky `nil`. Je to hranice „anotace není nález“ v té
    /// poslední vrstvě, kde ještě může spadnout — v textu pod dráhou.
    case annotated(hunks: Int, files: Int)
}

/// Kam běh hlásí, co dělá. Synchronní ze stejného důvodu jako `ReviewProgressHandler`: události
/// mají pořadí a to pořadí je v okně vidět.
typealias AnnotationProgressHandler = @Sendable (AnnotationProgress) -> Void

/// Výsledek jedné anotační session.
///
/// **Nemá pole pro nález a nemá kam ho dostat.** Je to ta hranice v typu: `ReviewRun` umí
/// `findings`, tohle ne — takže se z anotační session nemůže stát reviewer, ani kdyby jí někdo
/// `ReportFindings` omylem povolil.
struct AnnotationRun: Sendable, Equatable {
    var hunks: [HunkAnnotation] = []
    var files: [FileAnnotation] = []
    var outcome: ReviewRunOutcome = .finished
    var sessionID: String?
    /// Přišla odpověď ve tvaru, který se dal přečíst? Viz `StoredAnnotations.answered`.
    var answered = false
    /// Kolik položek se nepodařilo přečíst.
    var dropped = 0
    var usage: RunUsage?
}

/// Popis změn jednoho pull requestu (#524) — **sedmá vyjmenovaná session**.
///
/// Za protokolem ze stejného důvodu jako `ReviewRunning` a `AskRunning`: v testech se nahradí fakem
/// a **z typu je vidět, co to umí**. Jedna metoda, která bere hlavu a vrací věty; není tu nic, čím
/// by se dalo zapsat nebo odeslat, takže tvrdá podmínka č. 1 se tímhle nemění.
///
/// **Selhání session není chyba volání**, jako u revieweera: spadlá i vytimeoutovaná session se
/// vrací jako `AnnotationRun` s příslušným `outcome`. Vyhodí se jen `CancellationError`.
///
/// **Zabitá session ale nepřináší nic, a je to důsledek cesty odpovědi, ne opomenutí.** Anotace
/// stojí v posledním sdělení (`AnnotationSchema`), takže session, která se do něj nedostala,
/// nenapsala nic, co by šlo uložit — na rozdíl od revieweera, který nálezy hlásí průběžně. V okně
/// se to musí poznat: `outcome` u takového běhu je `timedOut` nebo `failed` a dráha o něm mluví
/// jinak než o doběhlém (`ReviewerLaneText`).
protocol HunkAnnotating: Sendable {
    func annotate(
        _ request: AnnotationRequest,
        progress: @escaping AnnotationProgressHandler
    ) async throws -> AnnotationRun
}

extension HunkAnnotating {
    func annotate(_ request: AnnotationRequest) async throws -> AnnotationRun {
        try await annotate(request, progress: { _ in })
    }
}
