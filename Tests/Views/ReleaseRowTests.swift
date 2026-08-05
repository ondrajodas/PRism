import Foundation
import Testing

@testable import PRism

@Suite("ReleaseRow")
struct ReleaseRowTests {
    private func release(tag: String, name: String) -> Release {
        Release(
            tag: tag,
            name: name,
            publishedAt: Date(timeIntervalSince1970: 0),
            body: "",
            url: URL(string: "https://github.com/ondrajodas/PRism/releases/tag/\(tag)")!
        )
    }

    private func row(tag: String, name: String) -> ReleaseRow {
        ReleaseRow(release: release(tag: tag, name: name), isUnseen: false)
    }

    @Test("Tag na začátku názvu se v řádku nečte dvakrát")
    func stripsTagPrefix() {
        let row = row(tag: "v1.1.23", name: "v1.1.23 — notifikace o re-review")

        #expect(row.tag == "v1.1.23")
        #expect(row.title == "notifikace o re-review")
    }

    @Test("Oddělovač se zahodí i s mezerami, ať nezůstane viset pomlčka")
    func dropsSeparators() {
        #expect(row(tag: "v1.0.0", name: "v1.0.0: první verze").title == "první verze")
        #expect(row(tag: "v1.0.0", name: "v1.0.0 - první verze").title == "první verze")
        #expect(row(tag: "v1.0.0", name: "v1.0.0 – první verze").title == "první verze")
    }

    @Test("Vydání pojmenované jen tagem nemá v řádku druhý text")
    func emptyTitleWhenNameIsJustTheTag() {
        #expect(row(tag: "v1.0.0", name: "v1.0.0").title.isEmpty)
    }

    /// Hádat, co je oddělovač, se vyplatí jen tam, kde je jisté, co se odděluje.
    @Test("Název, který tagem nezačíná, zůstane celý")
    func keepsUnrelatedName() {
        #expect(row(tag: "v1.0.0", name: "První veřejná verze").title == "První veřejná verze")
    }

    @Test("Identitu dává tag, ať se řádky v seznamu nepletou")
    func identityIsTheTag() {
        #expect(row(tag: "v1.0.0", name: "cokoli").id == "v1.0.0")
    }

    @Test("Odznak nese řádek, ne vydání")
    func carriesTheUnseenFlag() {
        let release = release(tag: "v1.0.0", name: "v1.0.0")

        #expect(ReleaseRow(release: release, isUnseen: true).isUnseen)
        #expect(!ReleaseRow(release: release, isUnseen: false).isUnseen)
    }
}
