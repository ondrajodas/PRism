import Foundation

/// Materiál pro brief (#516) — **text pro session a seznam PR, o kterých se dozvěděla**.
///
/// Dvě pole schválně v jednom typu: vznikají **jednou procházkou** přes tytéž pruhy desky, takže
/// se nemají jak rozejít. Kdyby seznam skládala druhá funkce, rozešel by se s promptem zrovna tam,
/// kde na tom záleží — a odkaz v hotovém briefu by pak mohl vést na pull request, o kterém
/// v zadání nebyla řeč.
struct BriefMaterial: Equatable, Sendable {
    /// Co jde do promptu.
    let text: String
    /// Pull requesty, které v tom textu stojí. **Uzavřený seznam cílů odkazů** — nic mimo něj se
    /// klikatelné nestane.
    let mentioned: [PRIdentifier]
}

/// Kus věty briefu — buď obyčejný text, nebo číslo, které otevře záložku (#516).
enum BriefSpan: Equatable, Sendable {
    case text(String)
    /// Napsané číslo (`#584`) a pull request, na který ukazuje.
    case link(String, PRIdentifier)
}

extension Policy {
    /// Věta briefu rozdělená na text a odkazy (#516).
    ///
    /// **Odkaz vzniká z toho, co do briefu doopravdy šlo, ne z toho, co model napsal.** Text je
    /// volný výstup modelu, takže v něm může stát číslo, které na desce není, nebo si ho session
    /// může vymyslet — a odkaz na neexistující pull request je horší než prostý text: klikne se na
    /// něj a otevře se záložka nad ničím. Uzavřeným seznamem cílů je proto `BriefMaterial.mentioned`
    /// z `Policy.briefInput`; hledání `#\d+` v odpovědi je jen způsob, jak se v té větě **najde
    /// místo**, kde odkaz stojí.
    ///
    /// **Samotné číslo cíl neurčuje.** V briefu stojí čísla z víc repozitářů (`ondrajodas/PRism #584`
    /// i `keboola/job-queue #725`), takže `#584` samo o sobě neříká, který PR to je. Rozhoduje se
    /// tedy takhle, a je to výčet, ne heuristika:
    ///
    /// 1. **Před číslem stojí jméno repozitáře** (`owner/name #584`, i bez mezery) — cílem je
    ///    **jedině** ten repozitář s tím číslem. Jméno, které v seznamu není, je **prostý text**,
    ///    ne nejbližší podobný: `keboola/job-queue #727` nad deskou, kde je jen
    ///    `ondrajodas/PRism #727`, by jinak odkazoval na cizí PR.
    /// 2. **Před číslem jméno repozitáře nestojí** — cílem je PR s tím číslem, **jestli je
    ///    v seznamu jediný**. Dvě repa s týmž číslem znamenají prostý text; hádat se nemá co.
    ///
    /// **Když se odkaz složit nedá, zůstane prostý text.** Žádné mrtvé tlačítko a žádná hláška:
    /// věta se čte dál stejně, jen se na to číslo nedá kliknout.
    ///
    /// **Odkaz je jen číslo**, ne celé `owner/name #584`. Je to zvýrazněné číslo uvnitř věty —
    /// jméno repozitáře před ním je próza a slouží k rozpoznání cíle, ne ke kliknutí.
    static func briefSpans(of text: String, mentioning mentioned: [PRIdentifier]) -> [BriefSpan] {
        guard !mentioned.isEmpty, text.contains("#") else { return [.text(text)] }
        let characters = Array(text)
        var spans: [BriefSpan] = []
        var plainStart = 0
        var index = 0
        while index < characters.count {
            guard characters[index] == "#" else {
                index += 1
                continue
            }
            var end = index + 1
            while end < characters.count, characters[end].isNumber { end += 1 }
            // Za `#` musí stát aspoň jedna číslice a hned za číslem **nesmí stát písmeno**:
            // `#584px` je míra, ne pull request.
            guard end > index + 1, end == characters.count || !characters[end].isLetter else {
                index += 1
                continue
            }
            guard let number = Int(String(characters[(index + 1)..<end])),
                  let target = briefTarget(number: number, after: characters[..<index], among: mentioned)
            else {
                index = end
                continue
            }
            if plainStart < index { spans.append(.text(String(characters[plainStart..<index]))) }
            spans.append(.link(String(characters[index..<end]), target))
            plainStart = end
            index = end
        }
        if plainStart < characters.count { spans.append(.text(String(characters[plainStart...]))) }
        return spans
    }

    /// Na který pull request číslo ukazuje. `nil` = na žádný jistý, tedy prostý text.
    private static func briefTarget(
        number: Int,
        after prefix: ArraySlice<Character>,
        among mentioned: [PRIdentifier]
    ) -> PRIdentifier? {
        let candidates = mentioned.filter { $0.number == number }
        guard !candidates.isEmpty else { return nil }
        guard let claimed = briefRepoClaim(in: prefix) else {
            // **Jednoznačnost, ne první shoda.** Dvě repa s týmž číslem a bez jména před ním jsou
            // otázka, na kterou v textu odpověď není.
            return candidates.count == 1 ? candidates.first : nil
        }
        return candidates.first { $0.repo.description.lowercased() == claimed }
    }

    /// Jméno repozitáře, které stojí těsně před číslem. `nil` = nestojí tam žádné.
    ///
    /// Bere se **poslední slovo** před číslem (mezery se odečítají) a za jméno repozitáře se
    /// považuje jedině to, co má lomítko. Cokoli s lomítkem se tím stává **nárokem na repozitář**,
    /// který se musí potkat se seznamem — `a/b/c #1` tedy odkaz nedá, i kdyby bylo číslo
    /// jednoznačné.
    private static func briefRepoClaim(in prefix: ArraySlice<Character>) -> String? {
        var rest = prefix
        while let last = rest.last, last == " " { rest = rest.dropLast() }
        var word: [Character] = []
        for character in rest.reversed() {
            guard character.isLetter || character.isNumber || "._-/".contains(character) else { break }
            word.append(character)
        }
        guard word.contains("/") else { return nil }
        return String(word.reversed()).lowercased()
    }
}
