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
    private let timeout: Duration

    init(
        gh: URL,
        runner: ProcessRunning,
        gateway: any GitHubGateway,
        timeout: Duration = .seconds(30)
    ) {
        self.gh = gh
        self.runner = runner
        self.gateway = gateway
        self.timeout = timeout
    }

    func submit(_ draft: ReviewDraft) async throws -> SubmittedReview {
        // Brána na sandbox je **první**, ještě před sítí: dokud se odesílá jen tam, nemá se
        // kvůli cizímu repu ani ptát na detail.
        guard PublishScope.allows(draft.pullRequest.repo) else {
            throw PublishError.outsideAllowedScope(draft.pullRequest.repo)
        }
        guard let payload = PublishRequest.payload(for: draft), !draft.isEmpty else {
            throw PublishError.nothingToSend
        }

        try await preflight(draft)
        return try await post(payload, to: draft.pullRequest)
    }

    /// Ověří, že se posílá na to, co jsme viděli. **Při neshodě se nevolá zápis.**
    ///
    /// `headSha` je to hlavní: approve na kód, který jsi neviděl, tak nejde poslat ani
    /// závodem s pushnutým commitem. GitHub proti tomu nechrání — změřeno u #62, že review
    /// se zastaralým `commit_id` **přijme**.
    private func preflight(_ draft: ReviewDraft) async throws {
        let pullRequest: PullRequest
        do {
            pullRequest = try await gateway.fetchDetail(id: draft.pullRequest)
        } catch let error as GitHubError {
            throw PublishError(preflight: error)
        }

        guard pullRequest.headSha == draft.headSha else {
            throw PublishError.staleDraft(draft: draft.headSha, head: pullRequest.headSha)
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
        let file = try writePayload(payload)
        // Soubor jde pryč, ať se odeslání povede nebo ne — je v něm text review.
        //
        // `try?` je tady v pořádku, i když se jinak v tomhle repu nesmí: **nepovedený úklid
        // nemá na výsledek vliv** a uživatel by se místo toho, jak dopadlo review, dozvěděl,
        // že nešel smazat soubor v `/tmp`, který systém uklidí sám. Ztracená informace tu
        // není žádná — na rozdíl od `try?` nad operací, jejíž selhání se nedá poznat jinak.
        defer { try? FileManager.default.removeItem(at: file) }

        let result: ProcessResult
        do {
            result = try await runner.run(
                gh,
                arguments: PublishRequest.arguments(for: pr, payload: file),
                timeout: timeout
            )
        } catch ProcessError.timedOut {
            throw PublishError.timedOut
        } catch ProcessError.launchFailed(let detail) {
            throw PublishError.toolUnavailable(detail)
        } catch {
            throw PublishError.toolUnavailable(error.localizedDescription)
        }

        guard result.exitCode == 0 else { throw PublishError(failure: result) }
        return try submitted(from: result.standardOutput)
    }

    /// Payload do dočasného souboru, protože `ProcessRunning` neumí stdin.
    ///
    /// Práva `0600`: je v něm text review, který ještě nikdo neviděl, a dočasná složka je
    /// společná pro celý systém.
    private func writePayload(_ payload: PublishRequest.Payload) throws -> URL {
        let file = URL(filePath: NSTemporaryDirectory())
            .appending(path: "prism-review-\(UUID().uuidString).json")
        let data = try PublishRequest.encoded(payload)
        try data.write(to: file, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: file.path(percentEncoded: false)
        )
        return file
    }

    /// Odpověď se čte typovaně, protože o jejím tvaru rozhoduje `--json`-like kontrakt REST
    /// API a zajímá nás z ní jen pár polí.
    private func submitted(from output: String) throws -> SubmittedReview {
        let decoded: GhSubmittedReview
        do {
            decoded = try GhOutput.decoder.decode(GhSubmittedReview.self, from: Data(output.utf8))
        } catch {
            throw PublishError.malformedResponse("\(error)")
        }
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
