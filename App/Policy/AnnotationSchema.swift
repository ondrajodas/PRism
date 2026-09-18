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
        ///
        /// **Jazyk odpovědi tady stát nesmí** (#592) — viz `language(_:)`.
        let meaning: String
        let values: [String]?
        /// Píše se do něj **próza pro mě**, tedy text, o kterém rozhoduje věta o jazyku (#592)?
        ///
        /// Příznak, ne výčet jmen vedle: věta o jazyku se skládá z těch polí, která ho mají, takže
        /// pole, které jako věta přibude, dostane jazyk **samo** — a druhé místo, kde se jazyk
        /// vyslovuje, nemá jak vzniknout.
        let isProse: Bool

        init(
            _ name: String,
            required: Bool,
            meaning: String,
            values: [String]? = nil,
            prose: Bool = false
        ) {
            self.name = name
            isRequired = required
            self.meaning = meaning
            self.values = values
            isProse = prose
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
            meaning: "one sentence saying why this change is here — what it does, not what is wrong with it",
            prose: true
        ),
        Field(
            Key.source,
            required: false,
            meaning: "where you know it from — for example the subject of the commit it comes from, "
                + "or that the pull request description does not mention it; leave it out when you "
                + "have no source",
            prose: true
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

    /// Pole, do kterých session píše prózu — tedy ta, o kterých rozhoduje věta o jazyku (#592).
    ///
    /// **Odvozuje se z příznaku, nevypisuje se jmény**: kdo přidá pole s větou, dostane ho ve větě
    /// o jazyku, a kdo přidá pole s cestou nebo s uzavřeným výčtem, ho tam nedostane.
    static var proseFields: [Field] { everyField.filter(\.isProse) }

    /// Věta o jazyku odpovědi (#592) — **jediné místo, kde se jazyk anotací vyslovuje**.
    ///
    /// Do #592 stál jazyk **v popisu pole** (`why`: *„one sentence in Czech“*) a u pull requestu,
    /// jehož diff je plný cizojazyčného textu, **neplatil**: naostro z toho vyšly ruské věty
    /// (`keboola/job-queue#727`; měření je v `docs/claude-cli.md`). Přívlastek uvnitř popisu tvaru
    /// je slabší než samostatná věta, a hlavně **neříká, proti čemu platí** — proto ta druhá
    /// polovina věty: jazyk je **volba aplikace, ne vlastnost čteného kódu**.
    ///
    /// **Jazyk se bere z `findingsLanguage`, vlastní volbu nemá**, a je to to rozhodnutí: je to
    /// tatáž otázka („v jakém jazyce je próza v okně“), takže druhá volba vedle by znamenala dvě
    /// pravdy o jednom okně — a anotace se od #525 kreslí **uvnitř diffu** vedle českých popisků.
    /// Proč ne natvrdo česky a proč se **nepřekládá** (tedy žádná druhá session), je v záznamu
    /// rozhodnutí ve specifikaci.
    static func language(_ language: FindingsLanguage) -> String {
        let named = proseFields.map { "`\($0.name)`" }.joined(separator: " and ")
        return """
            Write \(named) in \(language.promptName), whatever language the diff, its commit \
            messages, its comments and its identifiers are written in: the language of the answer \
            is a setting of this application, not a property of the code you are reading. \
            The other fields are paths and values from the lists above and stay as they are.
            """
    }

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
