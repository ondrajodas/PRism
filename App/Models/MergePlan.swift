import Foundation

/// S čím se potvrzení merge otevřelo (#465, rozdělené u #556) — **snímek, ne odkaz do storu**.
///
/// Tatáž úmluva jako u `ReviewDraft` v `ReviewSubmission`: co je v potvrzení vidět, to odejde.
/// Kdyby si sheet hodnoty dotahoval ze storu při kresbě, mohl by mezi otevřením a kliknutím
/// dorazit polling s jiným počtem commitů — a člověk by potvrdil něco jiného, než co četl.
///
/// **Proč dva typy, a ne jeden** (#556). Do #556 byl `MergePlan` obojí naráz: metoda byla
/// konstanta, takže „fakta o PR“ a „co odejde“ byla jedna a tatáž věc. Volbou metody se to
/// rozdělilo — z jednoho snímku faktů jdou složit **tři různé payloady** a dva z nich mají jiný
/// titulek i jiný počet commitů. `MergeProposal` je tedy to, s čím se sheet otevřel, `MergePlan`
/// to, co odejde; a `plan == nil` je platný stav, ne nedodělek: znamená **nic není vybráno**.
struct MergeProposal: Hashable, Sendable {
    let pullRequest: PRIdentifier
    /// Hlava, na kterou se merguje.
    ///
    /// Posílá se **v payloadu** (`sha`), ne jen kontroluje v pre-flightu: GitHub na tenhle
    /// parametr odpoví `409`, když se větev mezitím pohnula, takže je to jediná ochrana, která
    /// zabírá i na commit pushnutý mezi pre-flightem a voláním. U review taková možnost není
    /// (tam se `commit_id` bere jako údaj, ne jako podmínka — změřeno u #62).
    let headSha: String
    /// Jméno slévané větve, jak stojí v panelu i v potvrzení. **Titulek merge commitu se skládá
    /// z něj**, takže se výpis nemůže rozejít sám se sebou.
    let head: String
    /// Cílová větev.
    let base: String
    /// Kolik commitů se slévá. **Z načteného seznamu commitů**, ne z vlastního dotazu: tab
    /// `Commity` je má stejně, a druhý dotaz na totéž se s prvním umí rozejít.
    let commits: Int
    /// Titulek pull requestu — `commit_title` se z něj skládá **podle metody**
    /// (`Policy.mergeCommitTitle`).
    let title: String
    /// Výchozí metoda z nastavení (#556) — globální default přebitý tím, co si řeklo repo.
    ///
    /// **Snímek konfigurace z okamžiku kliknutí**, jako brána: co je předvybrané, je to, co
    /// v nastavení stálo, když se sheet otvíral.
    let defaultMethod: MergeMethod
    /// Co repozitář o mergi říká. `nil` = **nezjistilo se**, takže se nabídnou všechny tři metody
    /// a nic se o nich netvrdí.
    let repository: RepositoryMergeSettings?

    init(
        pullRequest: PRIdentifier,
        headSha: String,
        head: String,
        base: String,
        commits: Int,
        title: String,
        defaultMethod: MergeMethod = .squash,
        repository: RepositoryMergeSettings? = nil
    ) {
        self.pullRequest = pullRequest
        self.headSha = headSha
        self.head = head
        self.base = base
        self.commits = commits
        self.title = title
        self.defaultMethod = defaultMethod
        self.repository = repository
    }

    /// Payload pro jednu vybranou metodu — **to, co odejde**.
    ///
    /// Skládá ho `Policy` (`mergeCommitTitle`, `mergeCommitsLine`), ne tenhle typ: je to
    /// rozhodnutí nad daty, takže patří tam, kde se testuje výčtem.
    func plan(with method: MergeMethod) -> MergePlan {
        MergePlan(
            pullRequest: pullRequest,
            headSha: headSha,
            head: head,
            base: base,
            commits: commits,
            method: method,
            commitTitle: Policy.mergeCommitTitle(
                method: method,
                title: title,
                number: pullRequest.number,
                head: head
            )
        )
    }
}

/// Co se stane, když se klikne na `Mergnout` — **celý payload, nic mimo něj**.
///
/// Od #556 v něm je i **metoda**: do té doby ji nesla konstanta `MergeRequest.method` a plán ji
/// mít nemusel. Rozhodnutí „jedno místo pro kresbu i payload“ se tím **neruší, jen se přesouvá** —
/// sheet vypisuje řádky **z tohohle plánu** a `MergeRequest.Payload` ho kóduje, takže se ta dvě
/// místa nemají jak rozejít.
struct MergePlan: Hashable, Sendable {
    let pullRequest: PRIdentifier
    /// Hlava, na kterou se merguje — a **podmínka volání**, ne údaj (viz `MergeProposal.headSha`).
    let headSha: String
    /// Jméno slévané větve, jak stojí v panelu i v potvrzení.
    let head: String
    /// Cílová větev.
    let base: String
    /// Kolik commitů se slévá. Co se s nimi stane, je věc metody
    /// (`Policy.mergeCommitsLine(method:commits:)`).
    let commits: Int
    /// Jakou metodou. **Odejde doslova takhle** (`merge_method`).
    let method: MergeMethod
    /// Titulek commitu — **posílá se doslova takhle**, a `nil` znamená **neposílat**.
    ///
    /// `nil` je u rebase, kde žádný commit nevzniká. U squashe i merge commitu se posílá, protože
    /// bez `commit_title` si ho GitHub skládá podle nastavení repozitáře, do kterého aplikace
    /// nevidí — a potvrzení by pak ukazovalo titulek, který nemusí vzniknout (#465, platí dál).
    let commitTitle: String?
}

/// Co GitHub potvrdil po mergi (#465).
///
/// **Vrací se, co potvrdil GitHub, ne co jsme poslali** — stejně jako u `SubmittedReview`. Ze
/// `sha` je vidět, který commit doopravdy vznikl, takže se dá ukázat v okně bez dalšího čtení.
///
/// **Jen `sha`, i když odpověď má tři pole.** `merged` je podmínka, ne údaj (bez něj se
/// `MergedPullRequest` nesloží), a anglická věta `Pull Request successfully merged` se v českém
/// okně nikde neukazuje — držet ji by byl stav, který nikdo nečte. Do chybové hlášky se čte
/// **z odpovědi**, ne odsud.
struct MergedPullRequest: Hashable, Sendable {
    /// Sha commitu, který mergem vznikl.
    let sha: String
}
