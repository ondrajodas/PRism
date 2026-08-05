import Foundation
import Testing

@testable import PRism

@Suite("Policy — vydání")
struct ReleaseNotesPolicyTests {
    private func release(_ tag: String, at day: Int) -> Release {
        Release(
            tag: tag,
            name: "\(tag) — něco",
            publishedAt: Date(timeIntervalSince1970: Double(day) * 86_400),
            body: "notes",
            url: URL(string: "https://github.com/ondrajodas/PRism/releases/tag/\(tag)")!
        )
    }

    // MARK: - Řazení

    @Test("Řadí se od nejnovějšího, ať přijdou v jakémkoli pořadí")
    func sortsNewestFirst() {
        let sorted = Policy.sortedReleases([
            release("v1.0.0", at: 1),
            release("v1.1.2", at: 3),
            release("v1.1.0", at: 2),
        ])

        #expect(sorted.map(\.tag) == ["v1.1.2", "v1.1.0", "v1.0.0"])
    }

    @Test("Shodný čas rozhodne tag, aby pořadí nepřeskakovalo")
    func breaksTiesByTag() {
        let sorted = Policy.sortedReleases([release("v1.0.1", at: 5), release("v1.0.2", at: 5)])

        #expect(sorted.map(\.tag) == ["v1.0.2", "v1.0.1"])
        // A z obráceného vstupu totéž — kdyby řazení nebylo úplné, vyšlo by jinak.
        #expect(Policy.sortedReleases([release("v1.0.2", at: 5), release("v1.0.1", at: 5)])
            .map(\.tag) == ["v1.0.2", "v1.0.1"])
    }

    @Test("Prázdný seznam řazení nepoloží")
    func sortsEmpty() {
        #expect(Policy.sortedReleases([]).isEmpty)
    }

    // MARK: - Co je nového proti značce

    @Test("Nová jsou ta, co vyšla po značce")
    func findsNewerThanMark() {
        let releases = [release("v1.0.0", at: 1), release("v1.1.0", at: 2), release("v1.1.2", at: 3)]

        let new = Policy.newReleases(in: releases, since: "v1.0.0")

        #expect(new.map(\.tag) == ["v1.1.2", "v1.1.0"])
    }

    @Test("Značka na nejnovějším vydání znamená, že nové není nic")
    func nothingNewerThanNewest() {
        let releases = [release("v1.0.0", at: 1), release("v1.1.0", at: 2)]

        #expect(Policy.newReleases(in: releases, since: "v1.1.0").isEmpty)
    }

    /// Nejdůležitější test celé funkce: smazaný nebo přetagovaný release nesmí způsobit,
    /// že se za nové prohlásí celá historie.
    @Test("Značka, která v seznamu není, nedělá z celé historie novinky")
    func unknownMarkAnnouncesNothing() {
        let releases = [release("v1.0.0", at: 1), release("v1.1.0", at: 2)]

        #expect(Policy.newReleases(in: releases, since: "v0.9.9").isEmpty)
    }

    @Test("Nad prázdným seznamem není nové nic")
    func emptyHasNothingNew() {
        #expect(Policy.newReleases(in: [], since: "v1.0.0").isEmpty)
    }

    @Test("Nové se počítají podle data, ne podle pořadí ve vstupu")
    func ordersInputBeforeComparing() {
        let releases = [release("v1.1.0", at: 2), release("v1.0.0", at: 1), release("v1.1.2", at: 3)]

        #expect(Policy.newReleases(in: releases, since: "v1.1.0").map(\.tag) == ["v1.1.2"])
    }
}
