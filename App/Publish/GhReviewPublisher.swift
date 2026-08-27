import Foundation

/// `ReviewPublishing` nad `gh`.
///
/// Pre-flight jde přes `GitHubGateway.fetchDetail` — **odchylka od zadání #67**, které psalo
/// „nad `ProcessRunning`“. Vlastní `gh pr view` by byl druhý seznam `--json` polí a druhé
/// mapování téhož DTO, které se s prvním můžou rozejít; gateway je navíc read-only, takže se
/// tím nic neotvírá. Odesílá se pořád přes `runner`, takže „nad `ProcessRunning`“ platí pro
/// to, o co v tomhle modulu jde.
struct GhReviewPublisher: ReviewPublishing {
    private let gh: URL
    private let runner: ProcessRunning
    private let gateway: any GitHubGateway
    /// Brána bez výchozí hodnoty: publisher se bez ní nedá složit, takže se nedá zapomenout.
    private let scope: PublishScope
    private let timeout: Duration

    init(
        gh: URL,
        runner: ProcessRunning,
        gateway: any GitHubGateway,
        scope: PublishScope,
        timeout: Duration = .seconds(30)
    ) {
        self.gh = gh
        self.runner = runner
        self.gateway = gateway
        self.scope = scope
        self.timeout = timeout
    }

    func submit(_ draft: ReviewDraft) async throws -> SubmittedReview {
        // Brána je **první**, ještě před sítí: na repo, které povolené není, se nemá ani ptát
        // na detail.
        guard scope.allows(draft.pullRequest.repo) else {
            throw PublishError.publishingNotAllowed(draft.pullRequest.repo)
        }
        guard let payload = PublishRequest.payload(for: draft), !draft.isEmpty else {
            throw PublishError.nothingToSend
        }

        try await preflight(draft.pullRequest, expecting: draft.headSha)
        return try await post(payload, to: draft.pullRequest)
    }

    // MARK: - Vlákna

    /// Odpoví do vlákna. Brána je stejná jako u review, pre-flight **užší** — viz `preflight`.
    func reply(to thread: ThreadTarget, body: String) async throws -> ThreadComment {
        guard scope.allows(thread.pullRequest.repo) else {
            throw PublishError.publishingNotAllowed(thread.pullRequest.repo)
        }
        // Prázdná odpověď se **nevolá**: GitHub ji přijme, nic nevytvoří a vrátí exit 0
        // (změřeno v sandboxu), takže by okno hlásilo odeslanou odpověď, která nevznikla.
        guard PublishRequest.isSendable(body) else { throw PublishError.blankReply }

        try await preflight(thread.pullRequest, expecting: nil)

        let output = try await call(ThreadRequest.replyArguments(to: thread, body: body))
        let decoded = try decoded(GhThreadReplyResponse.self, from: output)
        guard let comment = decoded.comment() else {
            throw PublishError.malformedResponse("V odpovědi chybí vložený komentář.")
        }
        return comment
    }

    /// Přepne vyřešení vlákna.
    func setResolved(_ resolved: Bool, of thread: ThreadTarget) async throws -> ThreadResolution {
        guard scope.allows(thread.pullRequest.repo) else {
            throw PublishError.publishingNotAllowed(thread.pullRequest.repo)
        }

        try await preflight(thread.pullRequest, expecting: nil)

        let output = try await call(ThreadRequest.resolutionArguments(of: thread, resolved: resolved))
        let decoded = try decoded(GhThreadResolutionResponse.self, from: output)
        guard let resolution = decoded.resolution() else {
            throw PublishError.malformedResponse("V odpovědi chybí stav vlákna.")
        }
        return resolution
    }

    // MARK: - Komentář pod PR (#216)

    /// Napíše komentář do diskuze pod PR. Brána i pre-flight stejné jako u odpovědi do vlákna —
    /// komentář se neváže na commit, takže se hlava neověřuje.
    func comment(on pullRequest: PRIdentifier, body: String) async throws -> ThreadComment {
        guard scope.allows(pullRequest.repo) else {
            throw PublishError.publishingNotAllowed(pullRequest.repo)
        }
        // Prázdné tělo se **nevolá**, ze stejného důvodu jako u odpovědi: GitHub ho spolkne
        // a okno by hlásilo odeslaný komentář, který nevznikl.
        guard PublishRequest.isSendable(body) else { throw PublishError.blankComment }

        try await preflight(pullRequest, expecting: nil)

        let output = try await call(CommentRequest.arguments(for: pullRequest, body: body))
        let decoded = try decoded(GhIssueCommentResponse.self, from: output)
        guard let comment = decoded.comment() else {
            throw PublishError.malformedResponse("V odpovědi chybí vložený komentář.")
        }
        return comment
    }

    // MARK: - Labely a reviewery (#392)

    /// Nastaví celou sadu labelů. Brána i pre-flight stejné jako u komentáře — štítek se neváže
    /// na commit, takže se hlava neověřuje.
    ///
    /// **Prázdná sada je platná akce**, na rozdíl od prázdného komentáře: sundání posledního
    /// štítku je právě `{"labels": []}`, takže tady žádná obdoba `blankComment` není a být nemá.
    func setLabels(_ labels: [String], on pullRequest: PRIdentifier) async throws -> [PullRequestLabel] {
        guard scope.allows(pullRequest.repo) else {
            throw PublishError.publishingNotAllowed(pullRequest.repo)
        }

        try await preflight(pullRequest, expecting: nil)

        let file = try writePayload(
            try MetadataRequest.encoded(MetadataRequest.LabelsPayload(labels: labels)),
            prefix: "prism-labels"
        )
        // Soubor jde pryč, ať se to povede nebo ne — `try?` je tady v pořádku ze stejného důvodu
        // jako u review: nepovedený úklid nemá na výsledek vliv a nic se jím neztrácí.
        defer { try? FileManager.default.removeItem(at: file) }

        let output = try await call(MetadataRequest.labelArguments(for: pullRequest, payload: file))
        return try decoded([GhLabel].self, from: output).map(\.label)
    }

    /// Vyžádá review od uvedených lidí. **Jen přidává** — odebrání není opravný krok (upozornění
    /// se vzít zpět nedá), takže tudy nevede.
    func requestReviewers(
        _ logins: [String],
        teams: [String],
        on pullRequest: PRIdentifier
    ) async throws -> RequestedReview {
        guard scope.allows(pullRequest.repo) else {
            throw PublishError.publishingNotAllowed(pullRequest.repo)
        }
        // Vyžádat nikoho **není akce** a nevolá se: GitHub prázdná pole přijme a nic neudělá, takže
        // by okno hlásilo vyžádané review, které nevzniklo. Tatáž úvaha jako u prázdného komentáře,
        // jen s vlastní hláškou — „napiš text“ by tady nedávalo smysl. Platí to i pro týmy: prázdné
        // je obojí, nebo se volá.
        guard !logins.isEmpty || !teams.isEmpty else { throw PublishError.noReviewer }

        try await preflight(pullRequest, expecting: nil)

        let output = try await call(
            MetadataRequest.reviewerArguments(for: pullRequest, logins: logins, teams: teams)
        )
        let decoded = try decoded(GhRequestedReviewersResponse.self, from: output)
        // Odpověď nese **jen** to, na koho se čeká; odpovědi ostatních v ní nejsou. Sloučení proto
        // patří volajícímu, který zná stav okna (`Policy.reviewers(requested:keeping:)`) — tady se
        // vrací to, co potvrdil GitHub, tedy samí čekající a všechny vyžádané týmy.
        return RequestedReview(
            reviewers: Policy.reviewers(requested: decoded.logins(), verdicts: []),
            teams: decoded.teamSlugs()
        )
    }

    // MARK: - Nový label v repozitáři (#413)

    /// Založí label, který repozitář ještě nezná. **Sedmá cesta ven a první, která zapisuje do
    /// repozitáře** — zdůvodnění je u `ReviewPublishing`.
    ///
    /// Pre-flight je stejně široký jako u labelů (scope a stav PR, ne `headSha`), a **je to tady
    /// důležitější než u ostatních**: hned za tímhle voláním jde `setLabels`, takže na zavřeném PR by
    /// druhé volání neprošlo a v repozitáři by po tom zbyl label, který nikdo nechtěl.
    func createLabel(
        _ label: PullRequestLabel,
        for pullRequest: PRIdentifier
    ) async throws -> PullRequestLabel {
        guard scope.allows(pullRequest.repo) else {
            throw PublishError.publishingNotAllowed(pullRequest.repo)
        }
        // **Prázdné jméno se nevolá** — tatáž sdílená kontrola jako u odpovědi a komentáře. GitHub
        // by ho odmítl 422, ale nezavolat je lepší než volat a číst odmítnutí.
        guard PublishRequest.isSendable(label.name) else { throw PublishError.blankLabelName }

        try await preflight(pullRequest, expecting: nil)

        let file = try writePayload(
            try MetadataRequest.encoded(MetadataRequest.NewLabelPayload(label)),
            prefix: "prism-new-label"
        )
        defer { try? FileManager.default.removeItem(at: file) }

        let output = try await call(
            MetadataRequest.newLabelArguments(in: pullRequest.repo, payload: file)
        )
        return try decoded(GhLabel.self, from: output).label
    }

    // MARK: - Merge (#465)

    /// Mergne pull request. **Osmá a nejnevratnější cesta ven** — zdůvodnění je u `ReviewPublishing`.
    ///
    /// Pre-flight ověřuje **i hlavu**, na rozdíl od labelů a komentářů: merge se váže na commit,
    /// takže mergnout kód, který jsi neviděl, je tatáž záměna jako approve na kód, který jsi
    /// neviděl. `sha` v payloadu je k tomu **druhá pojistka**, kterou review mít nemůže: GitHub ji
    /// bere jako podmínku a na commit pushnutý mezi pre-flightem a voláním odpoví `409`.
    ///
    /// Jedno volání, takže tvrdá podmínka č. 5 (atomicky, nebo vůbec) je splněná triviálně: merge
    /// buď proběhne celý, nebo se nestane nic.
    func merge(_ plan: MergePlan) async throws -> MergedPullRequest {
        guard scope.allows(plan.pullRequest.repo) else {
            throw PublishError.publishingNotAllowed(plan.pullRequest.repo)
        }
        // Prázdná hlava se **nevolá**: bez `sha` by GitHub mergnul, co je zrovna nahoře — tedy
        // přesně to, čemu ta podmínka brání. Do plánu se prázdná dostat nemá (`Policy.mergePlan`
        // ho skládá z načteného detailu), a právě proto je kontrola tady.
        guard PublishRequest.isSendable(plan.headSha) else { throw PublishError.mergeWithoutHead }

        try await preflight(plan.pullRequest, expecting: plan.headSha)

        let file = try writePayload(
            try MergeRequest.encoded(MergeRequest.Payload(plan)),
            prefix: "prism-merge"
        )
        defer { try? FileManager.default.removeItem(at: file) }

        let output = try await call(MergeRequest.arguments(for: plan.pullRequest, payload: file))
        let decoded = try decoded(GhMergeResponse.self, from: output)
        guard let merged = decoded.merge() else {
            // Návratový kód byl **nula**, takže volání prošlo — a přesto z odpovědi neplyne, že se
            // mergovalo. Vlastní hláška by tady tvrdila víc, než co víme; `malformedResponse` je
            // ta jediná pravdivá a posílá člověka na GitHub, což je jediný další krok.
            throw PublishError.malformedResponse(decoded.message ?? "V odpovědi chybí commit merge.")
        }
        return merged
    }

    // MARK: - Pre-flight

    /// Ověří, že se posílá na to, co jsme viděli. **Při neshodě se nevolá zápis.**
    ///
    /// `expecting` je hlava, na kterou má PR stát — a je **volitelná**, protože každá cesta ven
    /// se váže na něco jiného:
    ///
    /// - **Review** ji vyžaduje: approve na kód, který jsi neviděl, nesmí projít ani závodem
    ///   s pushnutým commitem. GitHub proti tomu nechrání (změřeno u #62, že review se
    ///   zastaralým `commit_id` přijme).
    /// - **Odpověď do vlákna** ji nemá čím vyplnit a nemá proč: váže se na vlákno, ne na commit.
    ///   Odpovědět na vlákno, které vzniklo před třemi pushi, je běžné — kontrola hlavy by
    ///   zakázala zrovna to, na co se odpovídá.
    ///
    /// Stav PR se ověřuje vždycky, a **je to striktnější než GitHub**: změřeno u #73, že odpověď
    /// na zavřeném PR projde. Schválně: aplikace ukazuje PR z `review-requested`, takže mergnutý
    /// PR ze seznamu vypadne a k jeho vláknům se z okna nedostaneš — a psát do diskuze, která se
    /// uzavřela, patří do prohlížeče, ne sem.
    private func preflight(_ id: PRIdentifier, expecting head: String?) async throws {
        let pullRequest: PullRequest
        do {
            pullRequest = try await gateway.fetchDetail(id: id)
        } catch let error as GitHubError {
            throw PublishError(preflight: error)
        }

        if let head, pullRequest.headSha != head {
            throw PublishError.staleDraft(draft: head, head: pullRequest.headSha)
        }
        // Draft je otevřený stav, takže se na něj review poslat dá — GitHub to dovolí a je to
        // běžné. Zavřený a mergnutý ne.
        guard pullRequest.state == .open || pullRequest.state == .draft else {
            throw PublishError.pullRequestNotOpen(pullRequest.state)
        }
    }

    private func post(
        _ payload: PublishRequest.Payload,
        to pr: PRIdentifier
    ) async throws -> SubmittedReview {
        let file = try writePayload(try PublishRequest.encoded(payload), prefix: "prism-review")
        // Soubor jde pryč, ať se odeslání povede nebo ne — je v něm text review.
        //
        // `try?` je tady v pořádku, i když se jinak v tomhle repu nesmí: **nepovedený úklid
        // nemá na výsledek vliv** a uživatel by se místo toho, jak dopadlo review, dozvěděl,
        // že nešel smazat soubor v `/tmp`, který systém uklidí sám. Ztracená informace tu
        // není žádná — na rozdíl od `try?` nad operací, jejíž selhání se nedá poznat jinak.
        defer { try? FileManager.default.removeItem(at: file) }

        let output = try await call(PublishRequest.arguments(for: pr, payload: file))
        return try submitted(from: output)
    }

    /// Jedno volání `gh` a klasifikace všeho, co z něj může vypadnout.
    ///
    /// Sdílené **všemi** cestami ven (review, odpověď, vyřešení): kdyby si každá třídila chyby
    /// sama, lišily by se v tom, co znamená timeout nebo zrušení — a `mightHaveReachedGitHub`
    /// pak rozhoduje o tom, jestli okno nabídne odeslat znovu.
    private func call(_ arguments: [String]) async throws -> String {
        let result: ProcessResult
        do {
            result = try await runner.run(gh, arguments: arguments, timeout: timeout)
        } catch ProcessError.timedOut {
            throw PublishError.timedOut
        } catch ProcessError.launchFailed(let detail) {
            throw PublishError.toolUnavailable(detail)
        } catch is CancellationError {
            // Zrušení **není chyba nástroje** a musí projít jako zrušení — jinak by volající
            // ukázal „gh se nepodařilo spustit“ nad odesláním, které si člověk sám zrušil.
            // Stejné pravidlo jako u `ReviewRunner`, který vyhazuje jedině `CancellationError`.
            throw CancellationError()
        } catch {
            throw PublishError.toolUnavailable(error.localizedDescription)
        }

        guard result.exitCode == 0 else { throw PublishError(failure: result) }
        return result.standardOutput
    }

    /// Dekódování odpovědi. Selhání je vždycky `malformedResponse`, protože exit kód byl nula —
    /// tedy volání prošlo a nerozumíme jen tomu, co přišlo zpátky.
    private func decoded<Response: Decodable>(
        _ type: Response.Type,
        from output: String
    ) throws -> Response {
        do {
            return try GhOutput.decoder.decode(type, from: Data(output.utf8))
        } catch {
            throw PublishError.malformedResponse("\(error)")
        }
    }

    /// Payload do dočasného souboru, protože `ProcessRunning` neumí stdin.
    ///
    /// Práva `0600`: je v něm text review, který ještě nikdo neviděl, a dočasná složka je
    /// společná pro celý systém.
    ///
    /// **Bere hotová data, ne payload review** (#392): souborem se od té doby posílá i sada labelů,
    /// a dvě skoro shodné funkce na „napiš JSON s právy 0600 a ukliď ho“ by se rozešly zrovna
    /// v těch právech. `prefix` je jen jméno v dočasné složce, aby se dalo poznat, co v souboru
    /// zůstalo, kdyby úklid selhal. Kódování zůstává **u volajícího a před tímhle voláním** —
    /// když selže, není co uklízet.
    private func writePayload(_ data: Data, prefix: String) throws -> URL {
        let file = URL(filePath: NSTemporaryDirectory())
            .appending(path: "\(prefix)-\(UUID().uuidString).json")
        let path = file.path(percentEncoded: false)

        // Nejdřív prázdný soubor s právy, teprve pak obsah — text review tak na disku nikdy
        // neexistuje se širšími právy. Zápis proto **není** `.atomic`: ten píše do vedlejšího
        // souboru a přejmenováním by práva `0600` zahodil.
        guard FileManager.default.createFile(
            atPath: path,
            contents: nil,
            attributes: [.posixPermissions: 0o600]
        ) else {
            throw PublishError.toolUnavailable("Nepodařilo se připravit soubor s review.")
        }
        do {
            try data.write(to: file)
        } catch {
            // Bez tohohle by po selhaném zápisu zůstal na disku soubor s textem review —
            // `defer`, který ho maže, se registruje až u volajícího.
            try? FileManager.default.removeItem(at: file)
            throw error
        }
        return file
    }

    /// Odpověď se čte typovaně, protože o jejím tvaru rozhoduje `--json`-like kontrakt REST
    /// API a zajímá nás z ní jen pár polí.
    private func submitted(from output: String) throws -> SubmittedReview {
        let decoded = try decoded(GhSubmittedReview.self, from: output)
        guard let review = decoded.review() else {
            throw PublishError.malformedResponse("V odpovědi chybí autor review.")
        }
        return review
    }
}

extension PublishError {
    /// Chyba pre-flightu. Překládá se z `GitHubError`, aby volající řešil jeden typ — a aby
    /// z ní bylo poznat, že se **ještě nic neodeslalo**.
    init(preflight error: GitHubError) {
        self = switch error {
        case .notAuthenticated: .notAuthenticated
        case .rateLimited(let detail): .rateLimited(detail)
        case .network(let detail): .network(detail)
        case .timedOut: .timedOut
        case .toolUnavailable(let detail): .toolUnavailable(detail)
        default: .unknown(error.userDescription)
        }
    }
}

/// Tvar odpovědi `POST /pulls/{n}/reviews`.
///
/// REST používá `user` a `submitted_at`, kdežto GraphQL v #63 `author` a `submittedAt` —
/// proto vlastní DTO a explicitní `CodingKeys`, ne sdílení s `GhConversationResponse`.
struct GhSubmittedReview: Decodable {
    let id: Int
    let state: String?
    let body: String?
    let submittedAt: Date?
    let user: GhAuthor?

    enum CodingKeys: String, CodingKey {
        case id, state, body, user
        case submittedAt = "submitted_at"
    }

    /// `nil` = odpovědi nerozumíme.
    ///
    /// **Chybějící `user` se nedoplňuje prázdným jménem.** Odeslané review vždycky autora má,
    /// takže jeho absence znamená, že odpověď není tím, co čekáme — a vymyslet k ní prázdného
    /// autora je totéž jako vymyslet identitu. Volající z toho udělá `malformedResponse`, ze
    /// kterého je vidět, že se to má zkontrolovat na GitHubu. Je to tatáž úvaha jako u #63,
    /// kde se komentář bez autora zahazuje.
    ///
    /// Prázdné **tělo** je naopak v pořádku: schválení bez prózy je plnohodnotné review
    /// (v datech z #63 čtvrtina vzorku).
    func review() -> SubmittedReview? {
        guard let author = user?.login else { return nil }
        return SubmittedReview(
            // REST dává číselné `id`, GraphQL řetězcové. `SubmittedReview` drží řetězec,
            // protože z něj skládáme klíče a texty; číslo by se muselo převádět všude jinde.
            id: String(id),
            author: author,
            state: state.flatMap(SubmittedReview.State.init(rawValue:)),
            body: body ?? "",
            submittedAt: submittedAt
        )
    }
}
