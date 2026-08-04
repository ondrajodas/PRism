import Foundation

/// Přístup k souborům v `Tests/Fixtures/`.
///
/// Cesta se odvozuje z `#filePath`, ne z bundlu testů. Testy jsou psané ve Swift Testing,
/// takže tu není `XCTestCase`, od kterého by se dal `Bundle(for:)` odpíchnout — a hledat
/// bundle jinak je víc práce než ukázat na složku vedle.
enum Fixture {
    private static let directory = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .appending(path: "Fixtures")

    /// Obsah fixture jako text, např. `Fixture.text("gh/search-prs.json")`.
    static func text(_ relativePath: String) throws -> String {
        try String(contentsOf: directory.appending(path: relativePath), encoding: .utf8)
    }

    /// Obsah fixture jako bajty — pro to, co se dekóduje z `Data` (HTTP odpovědi).
    static func data(_ relativePath: String) throws -> Data {
        try Data(contentsOf: directory.appending(path: relativePath))
    }
}
