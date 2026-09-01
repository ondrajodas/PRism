import Foundation

@testable import PRism

/// Publisher, který nic neodesílá — jen si pamatuje, co po něm kdo chtěl.
///
/// Že **nic neodešlo**, je u tohohle protokolu to hlavní, co má fake zaručit: testy okolo
/// odesílání se nesmí spoléhat na síť ani na sandbox.
final class FakeReviewPublisher: ReviewPublishing, @unchecked Sendable {
    private let outcomes: [Result<SubmittedReview, any Error>]
    private let lock = NSLock()
    private var asked: [ReviewDraft] = []
    /// Co se chtělo po vláknech (#73), v pořadí. Stejný důvod jako u `asked`: na počtu stojí
    /// testy, které tvrdí, že se **nevolalo nic**.
    private var threadCalls: [ThreadCall] = []
    private var replyOutcome: Result<ThreadComment, any Error>?
    private var resolutionOutcome: Result<ThreadResolution, any Error>?
    private var commentOutcome: Result<ThreadComment, any Error>?
    private var labelsOutcome: Result<[PullRequestLabel], any Error>?
    private var reviewersOutcome: Result<RequestedReview, any Error>?
    private var newLabelOutcome: Result<PullRequestLabel, any Error>?
    private var mergeOutcome: Result<MergedPullRequest, any Error>?
    /// Jak dopadne přepnutí z draftu (#482). `Result<Void, …>`, protože metoda **nic nevrací** —
    /// úspěch je u ní jediná informace.
    private var readyOutcome: Result<Void, any Error>?
    /// Drží odeslání „rozběhnuté“, dokud se nepustí. Bez toho se nedá otestovat, co se stane
    /// **během** odesílání — a právě tam bydlí zákaz druhého odeslání. Stejný důvod, kvůli
    /// kterému `FakeReviewRunner` umí pozdržet běh.
    private var gate: (() async -> Void)?

    init(_ outcomes: [Result<SubmittedReview, any Error>]) {
        self.outcomes = outcomes
    }

    /// Co se po fake publisherovi chtělo nad vláknem — a od #216 i nad diskuzí pod PR.
    ///
    /// Komentář pod PR je tady schválně **v jednom výčtu s vlákny**: testy nad ním tvrdí
    /// hlavně to, že se **nevolalo nic**, a to se pozná jedině z jednoho seznamu všeho, co
    /// publisher dostal. Dva seznamy by znamenaly, že se dá zapomenout zkontrolovat druhý.
    enum ThreadCall: Equatable {
        case reply(ThreadTarget, body: String)
        case resolution(ThreadTarget, resolved: Bool)
        case comment(PRIdentifier, body: String)
        /// Labely (#392). Ve **stejném výčtu** jako vlákna a komentáře, a ze stejného důvodu:
        /// testy nad nimi tvrdí hlavně to, že se **nevolalo nic**, a to se pozná jedině z jednoho
        /// seznamu všeho, co publisher dostal.
        case labels(PRIdentifier, names: [String])
        case reviewers(PRIdentifier, logins: [String], teams: [String])
        /// Nový label v repozitáři (#413). Ve stejném výčtu jako ostatní, a hlavně **před**
        /// `labels`: zakládání jsou dvě volání za sebou, takže na jejich **pořadí** v tomhle seznamu
        /// stojí tvrzení o mezistavu.
        case newLabel(PRIdentifier, label: PullRequestLabel)
        /// Merge (#465). Ve stejném výčtu jako ostatní, a je to u něj to nejcennější: testy nad
        /// mergem tvrdí hlavně to, že se **nemergovalo** — a to se pozná jedině z jednoho seznamu
        /// všeho, co publisher dostal.
        case merge(MergePlan)
        /// Přepnutí z draftu na *ready for review* (#482). Ve stejném výčtu jako ostatní, a je to
        /// u něj to nejcennější: testy nad ním tvrdí hlavně to, že se **nepřepnulo** — a to se pozná
        /// jedině z jednoho seznamu všeho, co publisher dostal.
        case ready(PRIdentifier)
    }

    convenience init(reply outcome: Result<ThreadComment, any Error>) {
        self.init([])
        lock.withLock { replyOutcome = outcome }
    }

    convenience init(resolution outcome: Result<ThreadResolution, any Error>) {
        self.init([])
        lock.withLock { resolutionOutcome = outcome }
    }

    convenience init(comment outcome: Result<ThreadComment, any Error>) {
        self.init([])
        lock.withLock { commentOutcome = outcome }
    }

    convenience init(labels outcome: Result<[PullRequestLabel], any Error>) {
        self.init([])
        lock.withLock { labelsOutcome = outcome }
    }

    convenience init(reviewers outcome: Result<RequestedReview, any Error>) {
        self.init([])
        lock.withLock { reviewersOutcome = outcome }
    }

    convenience init(newLabel outcome: Result<PullRequestLabel, any Error>) {
        self.init([])
        lock.withLock { newLabelOutcome = outcome }
    }

    convenience init(merge outcome: Result<MergedPullRequest, any Error>) {
        self.init([])
        lock.withLock { mergeOutcome = outcome }
    }

    convenience init(ready outcome: Result<Void, any Error>) {
        self.init([])
        lock.withLock { readyOutcome = outcome }
    }

    var threadActions: [ThreadCall] { lock.withLock { threadCalls } }

    /// Odeslání se zastaví, dokud `release` nedovolí pokračovat.
    func hold(until gate: @escaping () async -> Void) {
        lock.withLock { self.gate = gate }
    }

    convenience init(always outcome: Result<SubmittedReview, any Error>) {
        self.init([outcome])
    }

    /// Co se po něm chtělo, v pořadí. Na počtu stojí testy, které tvrdí, že se **nevolalo nic**.
    var submitted: [ReviewDraft] { lock.withLock { asked } }

    func submit(_ draft: ReviewDraft) async throws -> SubmittedReview {
        let index: Int = lock.withLock {
            asked.append(draft)
            return asked.count - 1
        }
        // Zápis do `asked` je **před** bránou schválně: test se potřebuje dozvědět, že
        // odeslání běží, aby mohl zkusit to druhé.
        if let gate = lock.withLock({ gate }) { await gate() }
        guard !outcomes.isEmpty else {
            throw PublishError.unknown("Fake publisher nemá co vrátit.")
        }
        return try outcomes[min(index, outcomes.count - 1)].get()
    }

    func reply(to thread: ThreadTarget, body: String) async throws -> ThreadComment {
        lock.withLock { threadCalls.append(.reply(thread, body: body)) }
        // Brána je **za** zápisem, jako u `submit`: test musí poznat, že odesílání běží.
        if let gate = lock.withLock({ gate }) { await gate() }
        guard let outcome = lock.withLock({ replyOutcome }) else {
            throw PublishError.unknown("Fake publisher nemá co vrátit na odpověď.")
        }
        return try outcome.get()
    }

    func setResolved(_ resolved: Bool, of thread: ThreadTarget) async throws -> ThreadResolution {
        lock.withLock { threadCalls.append(.resolution(thread, resolved: resolved)) }
        if let gate = lock.withLock({ gate }) { await gate() }
        guard let outcome = lock.withLock({ resolutionOutcome }) else {
            throw PublishError.unknown("Fake publisher nemá co vrátit na vyřešení.")
        }
        return try outcome.get()
    }

    func comment(on pullRequest: PRIdentifier, body: String) async throws -> ThreadComment {
        lock.withLock { threadCalls.append(.comment(pullRequest, body: body)) }
        // Brána je **za** zápisem, jako u ostatních: test musí poznat, že odesílání běží.
        if let gate = lock.withLock({ gate }) { await gate() }
        guard let outcome = lock.withLock({ commentOutcome }) else {
            throw PublishError.unknown("Fake publisher nemá co vrátit na komentář.")
        }
        return try outcome.get()
    }

    // MARK: - Labely a reviewery (#392)

    func setLabels(_ labels: [String], on pullRequest: PRIdentifier) async throws -> [PullRequestLabel] {
        lock.withLock { threadCalls.append(.labels(pullRequest, names: labels)) }
        // Brána je **za** zápisem, jako u ostatních: test musí poznat, že odesílání běží.
        if let gate = lock.withLock({ gate }) { await gate() }
        guard let outcome = lock.withLock({ labelsOutcome }) else {
            throw PublishError.unknown("Fake publisher nemá co vrátit na labely.")
        }
        return try outcome.get()
    }

    func requestReviewers(
        _ logins: [String],
        teams: [String],
        on pullRequest: PRIdentifier
    ) async throws -> RequestedReview {
        lock.withLock { threadCalls.append(.reviewers(pullRequest, logins: logins, teams: teams)) }
        if let gate = lock.withLock({ gate }) { await gate() }
        guard let outcome = lock.withLock({ reviewersOutcome }) else {
            throw PublishError.unknown("Fake publisher nemá co vrátit na reviewery.")
        }
        return try outcome.get()
    }

    // MARK: - Nový label v repozitáři (#413)

    func createLabel(
        _ label: PullRequestLabel,
        for pullRequest: PRIdentifier
    ) async throws -> PullRequestLabel {
        lock.withLock { threadCalls.append(.newLabel(pullRequest, label: label)) }
        if let gate = lock.withLock({ gate }) { await gate() }
        guard let outcome = lock.withLock({ newLabelOutcome }) else {
            throw PublishError.unknown("Fake publisher nemá co vrátit na nový label.")
        }
        return try outcome.get()
    }

    // MARK: - Ready for review (#482)

    /// **Nezkonfigurovaný výsledek hodí chybu, ne úspěch**, i když metoda nic nevrací: fake, který
    /// mlčky uspěje, by zezelenil testy, které o téhle cestě ven nevědí — a u jediné cesty ven je
    /// „nikdo to nenastavil“ ta nejhorší chvíle na tichý úspěch.
    func markReadyForReview(on pullRequest: PRIdentifier) async throws {
        lock.withLock { threadCalls.append(.ready(pullRequest)) }
        if let gate = lock.withLock({ gate }) { await gate() }
        guard let outcome = lock.withLock({ readyOutcome }) else {
            throw PublishError.unknown("Fake publisher nemá co vrátit na ready for review.")
        }
        try outcome.get()
    }

    // MARK: - Merge (#465)

    func merge(_ plan: MergePlan) async throws -> MergedPullRequest {
        lock.withLock { threadCalls.append(.merge(plan)) }
        if let gate = lock.withLock({ gate }) { await gate() }
        guard let outcome = lock.withLock({ mergeOutcome }) else {
            throw PublishError.unknown("Fake publisher nemá co vrátit na merge.")
        }
        return try outcome.get()
    }
}
