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
    /// Smím vlákno označit za vyřešené? Říká to GitHub (`viewerCanResolve`) — právo na to
    /// nemá každý, kdo PR vidí.
    ///
    /// Drží se **obě** práva, ne jedno odvozené: GitHub je vyhodnocuje podle stavu vlákna
    /// (u vyřešeného je `canResolve` false a `canUnresolve` true), takže složit je do jednoho
    /// příznaku už při mapování by zahodilo, co k tomu API řeklo. Co potřebuje okno, dává
    /// `canToggleResolution`.
    let canResolve: Bool
    /// Smím vyřešené vlákno otevřít zpátky (`viewerCanUnresolve`)?
    let canUnresolve: Bool
    /// Unified diff od začátku hunku **po komentovaný řádek**, jak ho GitHub pořídil proti
    /// commitu, na kterém vlákno vzniklo (`diffHunk`). `nil` = nedorazil (starší odpověď).
    ///
    /// Je to **snímek z minulosti**, ne dnešní kód — a právě proto se drží: zastaralé vlákno
    /// se u kódu nekreslí, protože jeho číslo platilo pro starý head, takže tohle je jediné,
    /// čím se dá v `Přehledu` ukázat, o čem je řeč. Dopočítat úryvek z dnešního souboru by
    /// u zastaralého vlákna ukázalo jiný kód.
    ///
    /// Nesmí se splést s `Policy.snapshot` u kotev draftu (#69) — ten je z **dnešního** diffu.
    ///
    /// Drží se **surový text**, ne rozparsované řádky: kolik se z něj ukáže, je rozhodnutí,
    /// a to patří do `Policy` (`Policy.snippet(of:)`), ne do mapování odpovědi.
    let diffHunk: String?
    let comments: ConversationPage<ThreadComment>

    init(
        id: String,
        path: String,
        line: Int?,
        originalLine: Int?,
        side: DiffSide?,
        isResolved: Bool,
        isOutdated: Bool,
        canResolve: Bool = true,
        canUnresolve: Bool = true,
        diffHunk: String? = nil,
        comments: ConversationPage<ThreadComment>
    ) {
        self.id = id
        self.path = path
        self.line = line
        self.originalLine = originalLine
        self.side = side
        self.isResolved = isResolved
        self.isOutdated = isOutdated
        self.canResolve = canResolve
        self.canUnresolve = canUnresolve
        self.diffHunk = diffHunk
        self.comments = comments
    }

    /// Dá se stav vyřešení z aplikace přepnout?
    ///
    /// Podle stavu vlákna, protože každé z těch dvou práv platí v jiném: u otevřeného vlákna
    /// rozhoduje `canResolve`, u vyřešeného `canUnresolve`. Bez toho by okno nabízelo
    /// `Znovu otevřít` na základě práva, které se vztahuje k opačné akci.
    var canToggleResolution: Bool { isResolved ? canUnresolve : canResolve }

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
