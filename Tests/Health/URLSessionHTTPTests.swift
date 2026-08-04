import Foundation
import Testing

@testable import PRism

/// `URLSessionHTTP` proti skutečnému systému — bez sítě a bez závislosti na cizí službě.
///
/// Fake `HTTPGetting` ověří, co si s odpovědí počne `StatusPageClient`, ale ne to, jestli
/// `URLSession` odmítnuté spojení hlásí tak, jak si myslíme. Chodí se proto na
/// `127.0.0.1` na port, kde nikdo neposlouchá: to selže lokálně a stejně tak na stroji
/// bez sítě.
@Suite("URLSessionHTTP — proti skutečnému systému")
struct URLSessionHTTPTests {
    @Test("Odmítnuté spojení je doprava, ne rozbitá odpověď")
    func refusedConnection() async {
        // Port 1 je vyhrazený a neposlouchá na něm nic.
        let url = URL(string: "http://127.0.0.1:1/api/v2/components.json")!

        await #expect(throws: HTTPError.self) {
            try await URLSessionHTTP().get(url, ifNoneMatch: nil)
        }
    }

    @Test("Zrušené volání je CancellationError, ne výpadek sítě")
    func cancellationIsNotAnOutage() async throws {
        let url = URL(string: "http://127.0.0.1:1/api/v2/components.json")!
        let http = URLSessionHTTP()

        // Zrušení je deterministické: tělo tasku se rozjede teprve tehdy, když se test
        // uspí na `task.value` — tedy po `cancel()`. Bez překladu na `CancellationError`
        // by po zavření okna probleskla hláška, že status page není k dispozici.
        let task = Task { try await http.get(url, ifNoneMatch: nil) }
        task.cancel()

        await #expect(throws: CancellationError.self) { try await task.value }
    }
}
