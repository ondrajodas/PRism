import Foundation

/// Tvar odpovědi anotační session (#524) — **jediné místo, kde je napsaný**.
///
/// **Odpovídá se posledním sdělením, ne nástrojem** — a je to změna proti zadání #524, kde stál
/// vlastní nástroj `ReportAnnotations`. Proč se zahodil, je v záznamu rozhodnutí ve specifikaci;
/// krátce: nástroj, který aplikace „definuje“, existuje jedině jako MCP server, tedy jako **další
/// proces, který by PRism spouštěl** — a to je nová hranice pod tvrdou podmínkou č. 1 i č. 2.
/// Bez něj si session `ReportAnnotations` prostě nezavolá (změřeno, `docs/claude-cli.md`).
/// Precedens je **kontrola nálezů** (#150) a **rozhovor nad PR** (#452): odpověď je v `result`
/// eventu a čte se defenzivně.
///
/// **Popis a čtení bydlí spolu**, jako u `RecheckCommand`: tvar, o který se prompt řekne, je
/// totéž, co parser čeká. Věty do promptu se proto **skládají z výčtu polí** níž a `AnnotateCommand`
/// čte podle týchž konstant — přidané pole, o kterém ví parser a ne model (nebo naopak), tak nemá
/// jak vzniknout.
///
/// **A je to ta hranice mezi anotací a nálezem.** Schéma **nemá pole pro závažnost** — ani pro
/// verdikt, kategorii ani blokující příznak. Kdyby ho mělo, byl by to druhý `ReportFindings`
/// a anotace by se dřív nebo později začaly počítat do odznaků. Napsat to do promptu (*„nehlas
/// chyby“*) nestačí: prompt je prosba, tvar je podmínka — model nemá kam závažnost napsat a parser
/// by ji neměl odkud přečíst. Tvrdí to `AnnotationSchemaTests` nad `everyField`.
enum AnnotationSchema {
    /// Klíče, pod kterými to přijde. **Konstanty, ne literály na dvou místech**: prompt i parser
    /// berou tyhle.
    enum Key {
        static let hunks = "hunks"
        static let files = "files"
        static let file = "file"
        static let hunk = "hunk"
        static let why = "why"
        static let source = "source"
        static let kind = "kind"
    }

    /// Jedno pole schématu. `values` vyplněné znamená **uzavřený výčet** — z něj se v promptu
    /// vypíšou dovolené hodnoty a parser mimo ně nic nepustí.
    struct Field: Hashable, Sendable {
        let name: String
        let isRequired: Bool
        /// Co do něj patří. Jde to do promptu doslova, takže je to anglicky jako zbytek zadání.
        let meaning: String
        let values: [String]?

        init(_ name: String, required: Bool, meaning: String, values: [String]? = nil) {
            self.name = name
            isRequired = required
            self.meaning = meaning
            self.values = values
        }
    }

    /// Pole jedné položky v `hunks`. **Závažnost mezi nimi není.**
    static let hunkFields: [Field] = [
        Field(
            Key.file,
            required: true,
            meaning: "path of the changed file, exactly as it appears in the diff"
        ),
        Field(
            Key.hunk,
            required: true,
            meaning: "which hunk of that file this is, counted from 1 in the order they appear in the diff"
        ),
        Field(
            Key.why,
            required: true,
            meaning: "one sentence in Czech saying why this change is here — what it does, not what is wrong with it"
        ),
        Field(
            Key.source,
            required: false,
            meaning: "where you know it from, in Czech — for example \"z commitu <subject>\" "
                + "or \"popis PR to nezmiňuje\"; leave it out when you have no source"
        ),
    ]

    /// Pole jedné položky v `files`. **Závažnost mezi nimi taky není.**
    static let fileFields: [Field] = [
        Field(
            Key.file,
            required: true,
            meaning: "path of the changed file, exactly as it appears in the diff"
        ),
        Field(
            Key.kind,
            required: true,
            meaning: "what kind of change this file carries",
            values: FileChangeKind.allCases.map(\.rawValue)
        ),
    ]

    /// Všechna pole schématu na jednom místě — nad tímhle se tvrdí, že tam závažnost není.
    static var everyField: [Field] { hunkFields + fileFields }

    /// Slova, kterými by se závažnost do schématu dostala. **Výčet, ne úsudek**: stráž má vydat
    /// odpověď i tomu, kdo pole přidává za rok a o #524 neví.
    ///
    /// Je mezi nimi i `category` — u nálezu je to volný slug, na kterém stojí blokující sada
    /// (`Policy.isBlocking`), takže by do anotace přinesl přesně tu vazbu, kvůli které tohle
    /// schéma vzniká jako druhé a ne jako další pole toho prvního.
    static let severityWords = [
        "severity", "verdict", "blocking", "priority", "confidence", "category", "risk", "impact",
    ]

    /// Věty do promptu, složené z výčtu polí výš.
    ///
    /// **Skládá se, nepíše ručně**, a to je celý smysl typu: přidané pole se v promptu objeví samo.
    ///
    /// Formulace *„answer with your last message and nothing else“* je doslova ta z
    /// `RecheckCommand.verdictFormat` — je to tentýž způsob odpovědi, takže se od něj nemá čím
    /// lišit; jen tvar je objekt se dvěma seznamy, ne pole.
    static var instruction: String {
        """
        Answer with your last message and nothing else: a JSON object with the two keys below, \
        with no prose around it and no code fences. That message is the only output that counts, \
        so answer even when you have nothing to say — with empty lists. \
        \(list(named: Key.hunks, of: hunkFields, saying: "one entry per hunk of the diff")) \
        \(list(named: Key.files, of: fileFields, saying: "one entry per changed file")) \
        This run explains the change, it does not judge it: do not report problems, risks or \
        anything that should be fixed, and do not rate what you see — that is a review, and it \
        runs separately. There is no field for it here.
        """
    }

    /// Popis jednoho seznamu i s jeho poli.
    private static func list(named name: String, of fields: [Field], saying purpose: String) -> String {
        let described = fields.map { field -> String in
            let values = field.values.map { " (one of: \($0.joined(separator: ", ")))" } ?? ""
            return "`\(field.name)`\(field.isRequired ? "" : " (optional)") — \(field.meaning)\(values)"
        }
        return "`\(name)`: \(purpose); each entry has \(described.joined(separator: "; "))."
    }
}
