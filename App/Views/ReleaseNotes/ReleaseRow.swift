import Foundation

/// Vydání převedené na řádek seznamu — texty, identita a odznak `nové`.
///
/// Vlastní typ mimo view ze stejného důvodu jako `FindingRow`: skládání textů se dá testovat
/// bez UI, a je co testovat. Datum se **neformátuje tady** — hodnota zůstane `Date` a na
/// řetězec ji převádí až view, aby texty nezávisely na locale testovacího prostředí.
struct ReleaseRow: Identifiable, Hashable {
    let id: String
    /// Tag vydání, jak je na GitHubu (`v1.1.23`).
    let tag: String
    /// Název **bez tagu na začátku**. Prázdný u vydání, které se jmenuje jen svým tagem.
    let title: String
    let publishedAt: Date
    /// Je novější než poslední viděné vydání?
    let isUnseen: Bool

    init(release: Release, isUnseen: Bool) {
        id = release.tag
        tag = release.tag
        title = Self.strippingTag(from: release)
        publishedAt = release.publishedAt
        self.isUnseen = isUnseen
    }

    /// Zahodí tag ze začátku názvu.
    ///
    /// Release v tomhle repu se jmenují `v1.1.23 — notifikace o re-review`, takže by se tag
    /// v řádku četl dvakrát a delší polovina — název — by se ořezala dřív. Zadání #127 chce
    /// v seznamu tag i název; tohle je způsob, jak tam být můžou oba.
    ///
    /// Když název tagem nezačíná, **nesahá se na něj** — hádat, co je oddělovač, se vyplatí
    /// jen tam, kde je jisté, co se odděluje.
    private static func strippingTag(from release: Release) -> String {
        let name = release.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard name.hasPrefix(release.tag) else { return name }
        let rest = name.dropFirst(release.tag.count)
        return String(rest.drop { $0.isWhitespace || Self.separators.contains($0) })
    }

    /// Čím se v názvu odděluje tag od zbytku. Pomlčka i dvojtečka, protože obojí se
    /// v release notes tohohle repa vyskytlo.
    private static let separators: Set<Character> = ["—", "–", "-", ":", "·"]
}
