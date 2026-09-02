import Foundation

/// V jakém stavu je značka `Prošlo` u jednoho souboru (#500).
///
/// Tři stavy, ne dva: **„četl jsem starou verzi“ je jiná informace než „nečetl jsem“.** Bez
/// prostředního stavu by po každém pushi zmizelo všechno, co je přečtené, a diff by o tom, kde
/// jsem skončil, věděl zase přesně tolik co dneska.
enum FileReviewState: Hashable, Sendable {
    /// Nezaškrtnuto.
    case unread
    /// Zaškrtnuto a obsah od té doby sedí.
    case read(at: Date)
    /// Zaškrtnuto, ale soubor se od té doby změnil — `změněno od prošlého`.
    case changed(readAt: Date)

    /// Počítá se do `3 prošlé`? **Jen `read`.** `changed` je pobídka, ne hotová práce.
    var isRead: Bool {
        if case .read = self { return true }
        return false
    }

    /// Kdy se zaškrtlo. `nil` u nezaškrtnutého.
    var markedAt: Date? {
        switch self {
        case .unread: nil
        case .read(let at), .changed(let at): at
        }
    }
}

extension Policy {
    /// Stav značky ze tří vstupů: **záznam, otisk tehdy, otisk dnes** (#500).
    ///
    /// Pravidlo je jedna rovnost, a to schválně: otisk je `index` řádka diffu (`<základ>..<hlava>`),
    /// takže se shoduje právě tehdy, když se diff toho souboru nezměnil. Nový commit jinam do PR
    /// tedy značku **nechá**, commit do tohohle souboru — i rebase, po které se změnil základ —
    /// ji přepne na `changed`.
    ///
    /// **`nil == nil` je `read`, ne `changed`.** Otisk chybí jedině u přejmenování beze změny
    /// obsahu (`similarity index 100%`), a to je pořád týž soubor beze změny řádků; kdyby se
    /// dvakrát „nevím“ počítalo jako změna, taková značka by nešla udržet ani na vteřinu — po
    /// zaškrtnutí by hned zhasla na `změněno od prošlého`.
    static func fileReviewState(mark: ReadMark?, blobs: String?) -> FileReviewState {
        guard let mark else { return .unread }
        return mark.blobs == blobs ? .read(at: mark.markedAt) : .changed(readAt: mark.markedAt)
    }

    /// Stavy všech souborů diffu naráz — **jedno místo, ze kterého čte strom, hlavička souboru
    /// i sbalování.**
    ///
    /// Klíčem je `displayPath`, tedy to jméno, pod kterým soubor v okně vystupuje: strom kreslí
    /// je a značky se ukládají pod ně. Vrací se **jen to, co má značku** — `unread` je výchozí
    /// odpověď na cokoli, co v mapě není, takže by u padesátisouborového PR bylo padesát záznamů
    /// o tom, že se nic nestalo.
    ///
    /// Značka, jejíž soubor v diffu **není** (přejmenoval se, vypadl z PR), se do mapy nedostane
    /// — mapa popisuje diff, ne obsah souboru se značkami.
    static func fileReviewStates(of files: [FileDiff], marks: ReadMarks?) -> [String: FileReviewState] {
        guard let marks, !marks.isEmpty else { return [:] }
        var states: [String: FileReviewState] = [:]
        states.reserveCapacity(marks.marks.count)
        for file in files {
            let path = file.displayPath
            guard let mark = marks.mark(of: path) else { continue }
            states[path] = fileReviewState(mark: mark, blobs: file.blobs)
        }
        return states
    }

    /// Kolik souborů je prošlých — číslo do hlavičky stromu a do proužku pod ní.
    static func readFileCount(in states: [String: FileReviewState]) -> Int {
        states.count(where: { $0.value.isRead })
    }

    /// Podíl prošlých souborů pro proužek (`0…1`). `nil` = **proužek se nekreslí**: nad PR bez
    /// souborů, i když je to jen prázdný diff, by prázdná linka tvrdila „nic hotovo“ o práci,
    /// která žádná není.
    static func readFileShare(read: Int, of total: Int) -> Double? {
        guard total > 0, read > 0 else { return nil }
        return min(1, Double(read) / Double(total))
    }

    /// Popisek hlavičky stromu: `7 souborů · 3 prošlé`, nebo jen `7 souborů`, dokud není
    /// zaškrtnuté nic.
    ///
    /// Druhá polovina se **připojuje, až když má co říct** — `7 souborů · 0 prošlých` je
    /// v hlavičce stálý řádek o tom, že se nic nestalo, a ve sloupci 210 bodů širokém by ukrojil
    /// z počtu souborů.
    static func fileTreeSummary(files: Int, read: Int) -> String {
        let all = Plural.czech(files, one: "soubor", few: "soubory", many: "souborů")
        guard read > 0 else { return all }
        return "\(all) · \(Plural.czech(read, one: "prošlý", few: "prošlé", many: "prošlých"))"
    }

    /// Je soubor sbalený? **Rozhoduje značka, dokud si člověk neřekne jinak** (#500).
    ///
    /// `override` je to, co se naklikalo v tomhle sezení: `true` = sbaleno rukou, `false` =
    /// rozbaleno rukou (typicky `Rozbalit vše`), `nil` = nikdo nic neřekl, takže platí značka.
    ///
    /// Proč derivace a ne prosté „zaškrtnutí sbalí“: sbalení by pak bylo stav okna a po restartu
    /// by se prošlé soubory otevřely dokořán, i když značky na disku jsou. A `changed` se
    /// **rozbalí sám** — přesně to je ta úspora, kvůli které značka existuje: po druhém commitu
    /// zbude otevřené jen to, co se změnilo.
    static func isFileFolded(state: FileReviewState, override: Bool?) -> Bool {
        override ?? state.isRead
    }

    /// Co je napsané u zaškrtávátka v hlavičce souboru.
    ///
    /// **`Prošlo znovu` u změněného**, protože tlačítko tam neříká stav, ale co udělá: značka na
    /// starou verzi visí vedle jako kapsle, takže „Prošlo“ by u ní znělo jako popis toho, co
    /// platí.
    static func readToggleTitle(of state: FileReviewState) -> String {
        switch state {
        case .unread, .read: "Prošlo"
        case .changed: "Prošlo znovu"
        }
    }

    /// Kapsle vedle cesty u souboru, který se od zaškrtnutí změnil. `nil` = žádná se nekreslí.
    static func changedSinceReadLabel(of state: FileReviewState) -> String? {
        if case .changed = state { return "změněno od prošlého" }
        return nil
    }

    /// Nápověda zaškrtávátka — jediné místo, kde se ta věta skládá, i s klávesou z katalogu (#441).
    static func readToggleHelp(of state: FileReviewState) -> String {
        switch state {
        case .unread:
            shortcutHelp("Označit soubor za prošlý", .toggleFileRead)
        case .read:
            shortcutHelp("Zrušit značku prošlo", .toggleFileRead)
        case .changed:
            shortcutHelp("Označit za prošlé znovu — soubor se od té doby změnil", .toggleFileRead)
        }
    }
}
