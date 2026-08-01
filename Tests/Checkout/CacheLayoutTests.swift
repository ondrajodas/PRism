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
        let path = CacheLayout.applicationSupport.root.path(percentEncoded: false)

        #expect(path.hasSuffix("/Library/Application Support/PRism"))
    }
}
