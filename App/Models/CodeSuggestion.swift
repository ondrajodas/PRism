import Foundation

/// Návrh změny kódu (#528) — GitHubový blok ` ```suggestion `, jak se kreslí.
///
/// Dvě strany jednoho mini diffu, ne jen navrhovaný text: bez toho, co v souboru stojí dneska,
/// je z návrhu jenom blok kódu — a přesně tak se do #528 kreslil. Červená strana proto patří
/// k modelu, i když v ` ```suggestion ` samotném není: skládá ji `Policy` z diffu (u composeru)
/// nebo z `diffHunk`u vlákna (u čtení).
///
/// **Není to nic, co by se odesílalo.** Odesílá se **text komentáře**, ve kterém ten blok stojí —
/// tvrdá podmínka č. 1 se tím nemění a nová metoda protokolu nevzniká. Aplikovat návrh
/// (`applySuggestedChanges`) je zápis do repozitáře a schválně tu není.
struct CodeSuggestion: Hashable, Sendable {
    /// Co v souboru stojí dneska — červená strana. **Prázdné znamená „nevíme“**, ne „nic tam
    /// není“: u komentáře pod PR se návrh k žádnému řádku neváže, takže se kreslí jen zelená
    /// strana. Tvrdit prázdný původní kód by lhalo o tom, co návrh nahradí.
    var original: [String]
    /// Co se navrhuje místo toho — zelená strana. **Prázdné je legitimní**: návrh, který nemá
    /// jediný řádek, ten kus kódu maže, a GitHub to tak přijme.
    var replacement: [String]

    init(original: [String] = [], replacement: [String] = []) {
        self.original = original
        self.replacement = replacement
    }

    /// Návrh, který nic nemění — předvyplněný blok, do kterého nikdo nesáhl.
    ///
    /// Není to chyba a nezakazuje se: odeslat ho je legitimní způsob, jak říct „tenhle řádek
    /// nech být“. Composer to jen **napíše**, ať se to nestane omylem.
    var changesNothing: Bool { original == replacement }
}

/// Dá se k tomuhle výběru řádků návrh vůbec napsat? (#528)
///
/// Dva případy, ne `CodeSuggestion?`: odmítnutí nese **větu proč**. Zašedlé tlačítko bez důvodu
/// vypadá jako rozbitá aplikace — a u výběru přes hranici hunku je ten důvod zrovna to jediné,
/// co se z obrazovky nedá poznat.
enum SuggestionOffer: Hashable, Sendable {
    case available(CodeSuggestion)
    /// Proč to nejde. Věta říká **proč**, ne „nejde to“.
    case refused(String)

    var suggestion: CodeSuggestion? {
        if case .available(let suggestion) = self { return suggestion }
        return nil
    }

    var refusal: String? {
        if case .refused(let reason) = self { return reason }
        return nil
    }
}
