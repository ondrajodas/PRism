import AppKit
import Foundation
import Testing

@testable import PRism

/// Obrázky uživatelů (#171) — proti `FakeHTTPGetter`, takže se nikam nechodí.
@MainActor
@Suite("AvatarLoader")
struct AvatarLoaderTests {
    private let url = URL(string: "https://avatars.githubusercontent.com/u/1?s=40&v=4")!
    private let other = URL(string: "https://avatars.githubusercontent.com/u/2?s=40&v=4")!

    /// Malý platný PNG. Vyrábí se **v testu**, ne jako fixture: skutečný avatar je obrázek
    /// konkrétního člověka a v repu nemá co dělat.
    private func pixel() -> Data {
        let image = NSImage(size: NSSize(width: 2, height: 2))
        image.lockFocus()
        NSColor.systemOrange.drawSwatch(in: NSRect(x: 0, y: 0, width: 2, height: 2))
        image.unlockFocus()
        let representation = NSBitmapImageRep(data: image.tiffRepresentation!)!
        return representation.representation(using: .png, properties: [:])!
    }

    @Test("Obrázek se stáhne a zapamatuje")
    func loadsAndCachesAnImage() async {
        let http = FakeHTTPGetter(responses: [HTTPResponse(statusCode: 200, body: pixel())])
        let loader = AvatarLoader(http: http)

        #expect(loader.image(for: url) == nil, "dokud se nenačte, není co kreslit")
        await loader.load(url)

        #expect(loader.image(for: url) != nil)
        #expect(http.requests.count == 1)
    }

    /// Řádky přehledu se překreslují a jsou v líném seznamu, takže se `load` zavolá znovu.
    /// Druhý dotaz na obrázek, který už máme, je volání za nic.
    @Test("Načtený obrázek se netahá znovu")
    func doesNotFetchTwice() async {
        let http = FakeHTTPGetter(responses: [HTTPResponse(statusCode: 200, body: pixel())])
        let loader = AvatarLoader(http: http)

        await loader.load(url)
        await loader.load(url)

        #expect(http.requests.count == 1)
    }

    /// **Kontrola musí ležet před prvním `await`.** Dva řádky se stejným autorem se
    /// vykreslí naráz, takže mezi kontrolou a zápisem nesmí být mezera, do které se vejde
    /// druhé volání — tatáž lekce jako u dvojkliku na odeslání odpovědi (#73). Test je
    /// **souběžný**: sekvenční by prošel i bez té ochrany.
    @Test("Dva souběžné požadavky na týž obrázek dají jeden dotaz")
    func coalescesConcurrentLoads() async {
        let http = FakeHTTPGetter(responses: [HTTPResponse(statusCode: 200, body: pixel())])
        let loader = AvatarLoader(http: http)

        async let first: Void = loader.load(url)
        async let second: Void = loader.load(url)
        _ = await (first, second)

        #expect(http.requests.count == 1)
    }

    /// Selhaný obrázek se v témže běhu **nezkouší znovu**: řádek se překresluje často
    /// a opakovaný dotaz na něco, co nevyšlo, by chodil na síť při každém odscrollování.
    /// Cena je zástupný symbol až do restartu, což je u obrázku snesitelné.
    @Test("Selhání se nezkouší znovu", arguments: [404, 500])
    func doesNotRetryAFailure(status: Int) async {
        let http = FakeHTTPGetter(responses: [
            HTTPResponse(statusCode: status),
            HTTPResponse(statusCode: 200, body: pixel()),
        ])
        let loader = AvatarLoader(http: http)

        await loader.load(url)
        await loader.load(url)

        #expect(loader.image(for: url) == nil)
        #expect(http.requests.count == 1)
    }

    @Test("Výpadek sítě nic nepoloží")
    func survivesATransportError() async {
        let http = FakeHTTPGetter(failing: .transport("bez sítě"))
        let loader = AvatarLoader(http: http)

        await loader.load(url)

        #expect(loader.image(for: url) == nil)
    }

    /// Odpověď, které nerozumíme (HTML chybová stránka místo obrázku), nesmí projít jako
    /// obrázek — `NSImage` z takových dat nevznikne a `nil` je správná odpověď.
    @Test("Data, která nejsou obrázek, se zahodí")
    func rejectsDataThatIsNotAnImage() async {
        let http = FakeHTTPGetter(responses: [
            HTTPResponse(statusCode: 200, body: Data("<html>nope</html>".utf8))
        ])
        let loader = AvatarLoader(http: http)

        await loader.load(url)

        #expect(loader.image(for: url) == nil)
    }

    /// **Zrušení není zjištění** — tatáž zásada jako u `HealthMonitoru` a `StatusPageClientu`.
    /// Řádky přehledu jsou v líném seznamu, takže `.task` se při odscrollování ruší uprostřed
    /// stahování; kdyby po sobě zrušení nechalo značku „už jsem žádal“, ten avatar by se
    /// v celém běhu **nikdy** nenačetl, i když nic neselhalo.
    @Test("Zrušené stahování se dá zkusit znovu")
    func retriesAfterCancellation() async {
        let http = ScriptedHTTP(outcomes: [.failure(CancellationError()), .success(pixel())])
        let loader = AvatarLoader(http: http)

        await loader.load(url)
        #expect(loader.image(for: url) == nil)

        await loader.load(url)
        #expect(loader.image(for: url) != nil)
        #expect(http.count == 2)
    }

    @Test("Obrázky se mezi uživateli nepletou")
    func keepsImagesApart() async {
        let http = FakeHTTPGetter(responses: [HTTPResponse(statusCode: 200, body: pixel())])
        let loader = AvatarLoader(http: http)

        await loader.load(url)

        #expect(loader.image(for: url) != nil)
        #expect(loader.image(for: other) == nil)
    }
}

/// Getter, který umí vrátit **libovolnou** chybu, ne jen `HTTPError`.
///
/// `FakeHTTPGetter` bere `Result<HTTPResponse, HTTPError>`, takže se jím `CancellationError`
/// nasimulovat nedá — a zrovna na tom stojí, že se zrušené stahování dá zkusit znovu.
private final class ScriptedHTTP: HTTPGetting, @unchecked Sendable {
    private let outcomes: [Result<Data, any Error>]
    private let lock = NSLock()
    private var index = 0

    init(outcomes: [Result<Data, any Error>]) {
        self.outcomes = outcomes
    }

    var count: Int { lock.withLock { index } }

    func get(_ url: URL, ifNoneMatch etag: String?) async throws -> HTTPResponse {
        let outcome: Result<Data, any Error> = lock.withLock {
            defer { index += 1 }
            return outcomes[min(index, outcomes.count - 1)]
        }
        return HTTPResponse(statusCode: 200, body: try outcome.get())
    }
}
