import Foundation

/// Otevřel reviewer aspoň jeden soubor z pracovní kopie? (#383)
///
/// **Tři odpovědi, ne dvě**, a ta třetí je celý smysl tohohle typu: „ze záznamu to nejde poznat“
/// se nesmí slít s „nepodíval se“. Osa se ukládá až od #203, ořezává se na 300 událostí a u části
/// nástrojů v ní cesta prostě není — a z chybějícího záznamu se nesmí stát obvinění, protože pak
/// by se okno rozkřičelo nad každým starším review a ta hláška by se přestala čítat.
enum CodeReading: Hashable, Sendable {
    /// Aspoň jeden soubor z pracovní kopie otevřený. Doklad, ne dohad — cesta je v ose.
    case read
    /// Ani jeden, a přitom je ze všech pokusů v ose vidět, kam sáhly.
    case unread
    /// Nedá se soudit: osa chybí, je zkrácená, nebo je v ní nástroj, u kterého cesta v záznamu
    /// není. **Není to `unread`.**
    case unknown
}

extension Policy {
    /// Co o čtení kódu říká uložená osa běhu (#383).
    ///
    /// Tohle je ten nejsilnější signál, který se z uloženého běhu dá vytáhnout, a **nezávisí na
    /// ceně ani na modelu**: reviewer, který se nepodíval do kódu, o kódu nic netvrdí. Změřeno na
    /// 40 uložených bězích z cache: pravidlo pojmenovalo **čtyři** — všechny `security-review`
    /// s nulou nálezů z „levné“ éry (od 17. 8.) — a u jednoho z nich (`db-extractor-adapter#39`)
    /// našel `code-review` na tomtéž commitu **dva nálezy**, tedy doložené falešné čisto.
    ///
    /// **Cena a doba běhu se do rozhodnutí neberou** a je to změřené, ne opatrnost: na týchž
    /// datech otevřel běh za 0,12 $ tři soubory (`platform-libraries#561`) a běh za 0,44 $
    /// osmnáct (`job-queue-daemon#930`), kdežto jeden z těch čtyř podezřelých stál 0,74 $
    /// — jako brána by cena vyrobila falešné poplachy a žádnou pravdu navíc. Zbývá jako
    /// materiál pro člověka: cena je u chipu revieweera vidět tak jako tak.
    ///
    /// Čtyři důvody, proč vyjde `unknown`, každý kvůli jinému druhu chybějícího záznamu:
    ///
    /// - **osa se neuložila** (`timeline == nil`) — soubory z doby před #203, a je jich na disku
    ///   plno: 15 ze 40 měřených běhů;
    /// - **osa nezná pracovní strom** — bez něj se cesta nemá s čím porovnat;
    /// - **osa je zkrácená** (`dropped > 0`) — ořezává se **začátek**, tedy zrovna ta část, ve
    ///   které se čte nejvíc. Takový běh má za sebou 300+ událostí, takže je to spíš doklad
    ///   práce než jejího chybění — ale tvrdit se z něj nedá ani jedno;
    /// - **v ose není jediný pokus o nástroj** — běh, který se nerozjel, o čtení nemluví.
    /// **Jeden průchod osou, bez mezipole.** Volá se z `reviewState`, tedy při každém překreslení
    /// řádku seznamu (a osa má až 300 událostí), takže tady nemá co dělat `compactMap` do dočasného
    /// pole ani převod cesty stromu na řetězec u každého pokusu. Prvním otevřeným souborem to končí.
    static func codeReading(of run: StoredReviewRun) -> CodeReading {
        guard let timeline = run.timeline, let worktree = timeline.worktree else { return .unknown }
        guard timeline.dropped == 0 else { return .unknown }

        let path = worktree.path(percentEncoded: false)
        let prefix = path.hasSuffix("/") ? path : path + "/"
        var sawTool = false
        var reachedOutOfSight = false

        for entry in timeline.entries {
            guard case .tool(let attempt) = entry.kind else { continue }
            sawTool = true
            // Doklad přebíjí nejistotu: kdo otevřel soubor, ten kód četl, ať v ose stojí cokoli
            // dalšího — proto se vrací hned a zbytek osy se nečte.
            if opensFile(attempt, under: prefix) { return .read }
            if reachesOutOfSight(attempt) { reachedOutOfSight = true }
        }

        guard sawTool else { return .unknown }
        return reachedOutOfSight ? .unknown : .unread
    }

    /// Otevřel tenhle pokus soubor **uvnitř** pracovní kopie?
    ///
    /// Dvě věci, na kterých to stojí a ani jedna není zjevná:
    ///
    /// - **Cesta se v ose ukládá celá.** Krátí se teprve při vykreslení
    ///   (`ToolAttempt.shortened(inside:)`), takže se porovnat dá — ověřeno na uložených
    ///   záznamech, kde `Read` nese absolutní `file_path`.
    /// - **Oddělovač v předponě je podmínka, ne kosmetika.** Zadání pro revieweera (#120) leží
    ///   jako `<strom>.md`, tedy **soubor vedle** pracovní kopie se stejnou předponou. Bez `/`
    ///   by ho `hasPrefix` spolkl jako soubor v ní — a právě jeho si přečte i ten běh, který se
    ///   do kódu vůbec nepodíval (změřeno: `Read` toho `.md` má každý ze čtyř podezřelých).
    ///
    /// Odmítnutý ani chybou skončený pokus se za čtení nepočítá — nepřečetl nic. `nil` výsledek
    /// se počítá **jako přečtené**: odpovědi na nástroje se ze streamu čtou teprve od #326, takže
    /// by starší osa jinak vyšla celá jako nepřečtená.
    private static func opensFile(_ attempt: ToolAttempt, under prefix: String) -> Bool {
        guard fileReadingTools.contains(attempt.name), let detail = attempt.detail else { return false }
        if let kind = attempt.outcome?.kind, kind != .passed { return false }
        return detail.hasPrefix(prefix)
    }

    /// Mohl tenhle pokus přečíst kód, aniž by to v záznamu bylo vidět?
    ///
    /// Jediné, co ta otázka dělá, je **zákaz obvinění**: takový pokus nedokazuje čtení, ale
    /// vylučuje tvrzení, že se nečetlo. Sedí v ní tři nástroje a u každého se to dá doložit
    /// z uložených dat:
    ///
    /// - **`Grep`** nese v ose **vzor, ne cestu** (`ToolAttempt.detailKeys` má `pattern` před
    ///   `path`), takže z `AJDA-3003` nejde poznat, jestli se hledalo ve stromě nebo v cizím
    ///   transkriptu;
    /// - **`Agent`** a **`Task`** nemají detail vůbec (změřeno: `«bez detailu»`), a jestli se
    ///   pokusy podagenta objeví v proudu rodiče, se z uložených běhů dokázat nedá.
    ///
    /// **`Bash` v tom výčtu schválně není**, i když `cat` přes vestavěný seznam čtecích příkazů
    /// projde (změřeno u #12). Kdyby byl, pravidlo by se nespustilo nikdy: všechny čtyři doložené
    /// případy `git diff` v pracovním stromě mají. Tvrzení je proto úzké a přesně takové, jaké
    /// záznam unese — **neotevřel soubor**, ne „nedíval se do kódu“.
    ///
    /// **`Glob` tam taky není** a je to jiný důvod: hledá **jména**, obsah nečte. Vzor je navíc
    /// relativní (`src/**/*.php`), takže by z něj tvrzení o čtení nešlo postavit ani při dobré vůli.
    private static func reachesOutOfSight(_ attempt: ToolAttempt) -> Bool {
        opaqueTools.contains(attempt.name)
    }

    /// Nástroje, které čtou obsah souboru a **cestu k němu mají v ose**.
    ///
    /// `Edit` a `Write` v tom výčtu nejsou schválně: reviewer je nemá povolené (tvrdá podmínka
    /// č. 2), takže by se z jejich přítomnosti nemělo stát čtení — a kdyby se tam objevily, je to
    /// vada jinde než tady.
    static let fileReadingTools: Set<String> = ["Read", "NotebookRead"]

    /// Nástroje, u kterých ze záznamu nejde poznat, kam sáhly.
    static let opaqueTools: Set<String> = ["Grep", "Agent", "Task"]
}
