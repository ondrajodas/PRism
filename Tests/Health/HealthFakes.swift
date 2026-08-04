import Foundation

@testable import PRism

/// HTTP, které nikam nechodí — vrátí, co si test předepsal, a pamatuje si dotazy.
///
/// Odpovědi se berou v pořadí a **poslední se opakuje**, stejně jako u `FakeGitHubGateway`:
/// test na 304 tak vystačí s dvěma položkami.
final class FakeHTTPGetter: HTTPGetting, @unchecked Sendable {
    struct Request: Equatable {
        let url: URL
        let ifNoneMatch: String?
    }

    private let outcomes: [Result<HTTPResponse, HTTPError>]
    private let lock = NSLock()
    private var recorded: [Request] = []

    init(_ outcomes: [Result<HTTPResponse, HTTPError>]) {
        self.outcomes = outcomes
    }

    init(responses: [HTTPResponse]) {
        outcomes = responses.map { .success($0) }
    }

    init(failing error: HTTPError) {
        outcomes = [.failure(error)]
    }

    var requests: [Request] { lock.withLock { recorded } }

    func get(_ url: URL, ifNoneMatch etag: String?) async throws -> HTTPResponse {
        let index: Int = lock.withLock {
            recorded.append(Request(url: url, ifNoneMatch: etag))
            return min(recorded.count - 1, outcomes.count - 1)
        }
        return try outcomes[index].get()
    }
}

/// Status page, která nic nestahuje. Umí odpovídat jinak na každou službu i na každé kolo.
///
/// Chyba je `any Error`, ne `StatusPageError`: monitor musí zrušení odlišit od selhané
/// kontroly, a to se bez `CancellationError` otestovat nedá.
final class FakeStatusPage: StatusPageReading, @unchecked Sendable {
    private let outcomes: [MonitoredService: [Result<StatusPageResult, any Error>]]
    private let lock = NSLock()
    private var counts: [MonitoredService: Int] = [:]
    private var recorded: [MonitoredService] = []

    /// Jedna odpověď pro obě služby.
    init(_ outcome: Result<StatusPageResult, any Error>) {
        outcomes = Dictionary(uniqueKeysWithValues: MonitoredService.allCases.map { ($0, [outcome]) })
    }

    /// Po kolech. Poslední odpověď se opakuje.
    init(_ outcomes: [MonitoredService: [Result<StatusPageResult, any Error>]]) {
        self.outcomes = outcomes
    }

    var reads: [MonitoredService] { lock.withLock { recorded } }

    func read(_ service: MonitoredService) async throws -> StatusPageResult {
        let outcome: Result<StatusPageResult, any Error>? = lock.withLock {
            recorded.append(service)
            let round = counts[service] ?? 0
            counts[service] = round + 1
            guard let planned = outcomes[service], !planned.isEmpty else { return nil }
            return planned[min(round, planned.count - 1)]
        }
        guard let outcome else { return .unchanged }
        return try outcome.get()
    }
}

/// Síť, jejíž stav si test řídí sám.
final class FakeReachability: NetworkReachability, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: AsyncStream<Bool>.Continuation?
    private let initial: [Bool]

    init(_ initial: [Bool] = []) {
        self.initial = initial
    }

    func updates() -> AsyncStream<Bool> {
        AsyncStream { continuation in
            lock.withLock { self.continuation = continuation }
            for value in initial { continuation.yield(value) }
        }
    }

    func send(_ online: Bool) {
        lock.withLock { continuation }?.yield(online)
    }
}

extension StatusPage {
    /// Stránka složená z „jméno: stav“ — zkratka pro testy `Policy`, ne fake.
    static func watching(_ components: KeyValuePairs<String, String>, missing: [String] = []) -> StatusPage {
        StatusPage(
            watched: components.map { StatusPageComponent(name: $0.key, status: $0.value) },
            missing: missing
        )
    }
}
