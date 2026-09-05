import Foundation

/// Co stojí v okně místo diffu, když se nedotáhl (#542).
///
/// Skládá to `Policy`, ne view: rozhodnutí „tohle je strop GitHubu, a ten se nedá zkusit znovu“
/// je tvrzení nad odpovědí od `gh`, a takové patří do čisté funkce, kde se dá vyčerpat výčtem.
struct DiffFailureNotice: Equatable, Sendable {
    let title: String
    /// Věta pod titulkem — `nil` tam, kde se nedá říct víc, než co stojí v syrové odpovědi.
    /// Vymyslet ji i tam by znamenalo hádat příčinu, kterou neznáme.
    let message: String?
    /// Syrová odpověď od `gh`. **Zůstává, jak přišla** — tatáž zásada jako u `EmptyStateView`.
    let detail: String
    /// Co se pod tím nabídne.
    let action: DiffFailureAction
}

/// Jediné, co se s nenačteným diffem dá v okně dělat.
enum DiffFailureAction: Equatable, Sendable {
    /// Druhý pokus má smysl — výpadek sítě, vypršelý token, timeout.
    case retry
    /// Druhý pokus vrátí totéž, dokud se nepřepíše historie pull requestu. Místo tlačítka,
    /// které nemůže pomoct, se nabízí to jediné, co pomůže: přečíst ten pull request tam,
    /// kde diff je.
    case openOnGitHub
}

extension Policy {
    /// Proč diff není — **výčet, ne `if` ve view** (#542).
    ///
    /// Strop se pozná **z odpovědi**, ne z počtu souborů: kolik jich pull request mění, aplikace
    /// v tu chvíli neví, protože právě ten diff, ze kterého by se to spočítalo, nedorazil.
    static func diffFailure(_ error: GitHubError) -> DiffFailure {
        guard let response = error.responseText,
              response.lowercased().contains(diffFileCapSignal)
        else { return .other(error.userDescription) }
        return .tooManyFiles(limit: diffFileCap(inResponse: response), response: response)
    }

    /// Věta z odpovědi GitHub API, podle které se strop pozná.
    ///
    /// Znění je z živé odpovědi (fixture `gh/pr-diff-too-large.txt`, `home-assistant/core#181088`):
    /// `HTTP 406: Sorry, the diff exceeded the maximum number of files (300).` **Číslo se do
    /// signálu nebere** — je to hodnota, která se může změnit, kdežto věta kolem ní je to, co
    /// tu příčinu odlišuje.
    static let diffFileCapSignal = "diff exceeded the maximum number of files"

    /// Strop přečtený z odpovědi — `nil`, když v ní číslo nestojí.
    ///
    /// **Nikdy se nedosazuje konstanta.** Tři sta je dnešní hodnota GitHubu, ne naše rozhodnutí;
    /// věta, která by ho tvrdila i nad odpovědí bez čísla, by lhala v den, kdy se strop pohne.
    static func diffFileCap(inResponse text: String) -> Int? {
        let lowered = text.lowercased()
        guard let signal = lowered.range(of: diffFileCapSignal) else { return nil }
        // Číslo stojí v závorce hned za tou větou: `…maximum number of files (300).`
        let tail = lowered[signal.upperBound...]
        guard let open = tail.firstIndex(of: "("),
              let close = tail[open...].firstIndex(of: ")")
        else { return nil }
        let digits = tail[tail.index(after: open)..<close]
        // **Samé číslice, ne jen „projde to přes `Int`“.** Adresu z druhé závorky téže hlášky
        // (`(https://api.github.com/…)`) by odmítl i `Int`, jenže znaménko ne — a ze `(-5)` by
        // vyšel záporný strop, tedy věta „GitHub vydá diff nejvýš pro −5 souborů“.
        guard !digits.isEmpty, digits.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        return Int(digits)
    }

    /// Co se o tom selhání napíše a co se pod tím nabídne.
    static func diffFailureNotice(_ failure: DiffFailure) -> DiffFailureNotice {
        switch failure {
        case .tooManyFiles(let limit, let response):
            DiffFailureNotice(
                title: "Diff je nad stropem GitHubu",
                // **Zbytek pull requestu na diffu nestojí**, a je to půlka té informace: bez téhle
                // věty vypadá prázdná plocha jako „tenhle pull request se nedá otevřít“.
                message: diffFileCapNote(limit: limit),
                detail: response,
                action: .openOnGitHub
            )
        case .other(let detail):
            DiffFailureNotice(
                title: "Diff se nepodařilo načíst",
                // Bez věty schválně: co se stalo, ví jedině ta syrová odpověď pod tím.
                message: nil,
                detail: detail,
                action: .retry
            )
        }
    }

    /// Věta o stropu — s číslem, jedině když se přečetlo z odpovědi.
    private static func diffFileCapNote(limit: Int?) -> String {
        let cap = limit.map { "GitHub vydá diff nejvýš pro \($0) souborů a tenhle pull request je nad tím." }
            ?? "GitHub tenhle diff nevydá — pull request je nad stropem jeho API na počet souborů."
        // **Tvrzení o tom, na čem co stojí**, ne slib, že se všechno ostatní načetlo: přehled,
        // commity, kontroly ani konverzace se z diffu neberou, takže tahle věta platí vždycky.
        return cap + " Přehled, commity, kontroly ani konverzace na diffu nestojí — chybí jen ten."
    }
}
