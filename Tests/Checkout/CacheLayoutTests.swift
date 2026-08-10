import Foundation
import Testing

@testable import PRism

@Suite("CacheLayout")
struct CacheLayoutTests {
    private let layout = CacheLayout(root: URL(filePath: "/tmp/prism-cache"))
    private let vault = RepoID(owner: "keboola", name: "vault")

    @Test("Klon leží pod repos/<owner>/<repo>.git")
    func bareClonePath() {
        #expect(layout.bareClone(for: vault).path(percentEncoded: false)
            == "/tmp/prism-cache/repos/keboola/vault.git")
    }

    @Test("Dvě repa stejného vlastníka se nepletou")
    func repositoriesOfOneOwnerStaySeparate() {
        let other = RepoID(owner: "keboola", name: "kbc-stacks")

        #expect(layout.bareClone(for: vault) != layout.bareClone(for: other))
    }

    @Test("Výchozí cache je ve složce aplikace")
    func defaultCacheLivesInApplicationSupport() {
        // Nikdy ne vedle uživatelových klonů — appka má vlastní místo a jinam nesahá.
        // Jméno složky je `CFBundleName`, což je v testech test host, tedy `PRism`.
        let path = CacheLayout.applicationSupport.root.path(percentEncoded: false)

        #expect(path.hasSuffix("/Library/Application Support/PRism"))
    }

    @Test("Pojmenovaná cache leží ve složce aplikace pod svým jménem")
    func namedCacheLivesUnderItsOwnName() {
        let path = CacheLayout(named: "PRism-a").root.path(percentEncoded: false)

        #expect(path.hasSuffix("/Library/Application Support/PRism-a"))
    }

    @Test("Slot na cache hlavní instance nesáhne, ani jedním směrem")
    func aSlotNeverReachesIntoTheMainInstanceCache() {
        // Tohle je celý smysl slotů (#228): rozestavěný build nesmí smazat rozdělaný draft
        // ani uložené nálezy té instance, se kterou se pracuje. Chytá to i past, do které
        // by se spadlo připojením slotu bez oddělovače — „PRism“ + „“ je pořád „PRism“.
        let main = CacheLayout(named: "PRism")
        let slot = CacheLayout(named: "PRism-a")

        #expect(main.root != slot.root)
        #expect(!main.contains(slot.configFile))
        #expect(!slot.contains(main.configFile))
        #expect(!main.contains(slot.root))
        #expect(!slot.contains(main.root))
    }

    @Test("Výsledky review leží pod reviews/<owner>/<repo>/<pr>-<sha>.json")
    func reviewFilePath() {
        let file = layout.reviewFile(for: PRIdentifier(repo: vault, number: 42), at: "aaaa1111")

        #expect(file.path(percentEncoded: false)
            == "/tmp/prism-cache/reviews/keboola/vault/42-aaaa1111.json")
    }

    @Test("Cesta uvnitř cache je uvnitř, cesta mimo ni ne")
    func containsAnswersForBothSides() {
        #expect(layout.contains(layout.bareClone(for: vault)))
        #expect(layout.contains(layout.root.appending(path: "cokoli")))
        #expect(!layout.contains(URL(filePath: "/tmp/prism-cache-jineho/soubor")))
        // Kořen sám do cache nepatří — smazat ho by znamenalo smazat celou cache.
        #expect(!layout.contains(layout.root))
    }

    @Test("Symlink v cestě odpověď nezmění")
    func aSymlinkInThePathDoesNotFoolIt() throws {
        // Tohle je celý důvod, proč se cesta rozbaluje: `removeItem` přes odkaz
        // v rodičovské komponentě smaže cíl, ne odkaz.
        let cache = try TemporaryDirectory()
        let outside = try TemporaryDirectory()
        let layout = CacheLayout(root: cache.url)
        try FileManager.default.createSymbolicLink(
            at: cache.url.appending(path: "ven"),
            withDestinationURL: outside.url
        )

        #expect(!layout.contains(cache.url.appending(path: "ven/uzivateluv-soubor")))
    }
}
