import Foundation

/// Vlákno komentářů u jednoho řádku diffu.
struct ReviewThread: Hashable, Codable, Sendable {
    let id: String
    let path: String
    /// Řádek v **aktuálním** diffu. `nil` znamená, že vlákno zastaralo — kotva zmizela.
    ///
    /// Ověřeno na `cli/cli#13084`: ze 38 vláken bylo 24 `isOutdated` a `line == nil` právě
    /// u těch 24, ani jedna výjimka v žádném směru. Je to tedy tatáž informace dvakrát,
    /// jenže `isOutdated` říká **proč** a `line` je to, s čím se dá kreslit — a stejné
    /// chování má REST (ověřeno u #62).
    let line: Int?
    /// Řádek, u kterého vlákno vzniklo. Zůstává i po zastarání, takže je to jediné, čím se
    /// dá zastaralé vlákno umístit.
    let originalLine: Int?
    /// Ke které straně diffu řádek patří. `nil` = GitHub poslal hodnotu, kterou neznáme.
    ///
    /// V rozpisu #63 to nebylo. Přidané schválně: bez toho by vlákno na **smazaném** řádku
    /// (`left`) vyšlo v #64 nad novým obsahem, tedy tiše u cizího kódu. Ve vzorku byly
    /// všechny `RIGHT`, což je přesně ten důvod, proč se na to nedá spolehnout mlčky.
    let side: DiffSide?
    let isResolved: Bool
    let isOutdated: Bool
    let comments: ConversationPage<ThreadComment>

    init(
        id: String,
        path: String,
        line: Int?,
        originalLine: Int?,
        side: DiffSide?,
        isResolved: Bool,
        isOutdated: Bool,
        comments: ConversationPage<ThreadComment>
    ) {
        self.id = id
        self.path = path
        self.line = line
        self.originalLine = originalLine
        self.side = side
        self.isResolved = isResolved
        self.isOutdated = isOutdated
        self.comments = comments
    }

    /// Číslo řádku, u kterého se vlákno má ukázat: aktuální, a když zastaralo, to původní.
    ///
    /// Nezastaralé vlákno bez `line` nevzniklo v datech ani jednou, ale fallback tady je
    /// schválně — vlákno bez čísla se nemá kde ukázat a zmizelý komentář kolegy je horší
    /// než komentář na starém řádku.
    var anchorLine: Int? { line ?? originalLine }
}

/// Strana diffu, ke které se komentář váže.
enum DiffSide: String, Codable, Sendable {
    case left = "LEFT"
    case right = "RIGHT"
}
