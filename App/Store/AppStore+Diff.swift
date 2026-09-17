import Foundation

/// Diff v `AppStore`: načtení, pohled a sbalování souborů.
///
/// Stav (`diffStates`, `diffLayoutOverride`, `fileFolding`) zůstává v `AppStore.swift` — dělí
/// se metody, ne data.
extension AppStore {
    func diffState(for pr: PRIdentifier) -> DiffState? { diffStates[pr] }

    /// Načte diff vybraného PR. Načtený se drží — na GitHub se sáhne znovu, teprve když
    /// se změní `updatedAt`.
    ///
    /// `updatedAt` se mění i po komentáři, takže se občas načte zbytečně. Opačná chyba —
    /// ukázat diff, ve kterém chybí nový commit — je dražší.
    func loadDiff(for pullRequest: PullRequestSummary) async {
        let id = pullRequest.id
        guard !hasCurrentDiff(for: pullRequest) else {
            // Diff je z paměti, ale **razítko návrhu mohlo přibýt mezitím** (#520): review doběhlo,
            // zatímco byl tab zavřený, a `updatedAt` se kvůli tomu nezměnilo. Bez tohohle volání by
            // se návrh složil teprve po dalším pushi, tedy tehdy, kdy už neplatí.
            await materializeAutoDraft(for: id)
            return
        }
        diffStates[id] = .loading

        do {
            let text = try await gateway.fetchDiff(id: id)
            diffStates[id] = .loaded(DiffParser.parse(text), updatedAt: pullRequest.updatedAt)
            revealFindingsOutsideTheDiff(for: id)
            // Teprve teď se dá návrh review (#520) složit: kam převzatý nález patří, rozhodují
            // hunky. Bez razítka, s rozepsaným draftem nebo nad posunutou hlavou se nestane nic.
            await materializeAutoDraft(for: id)
            // Nový diff = jiné otisky souborů, takže se stav značek `Prošlo` (#500) musí složit
            // znovu — tohle je ta chvíle, kdy se ze značky stane `změněno od prošlého`.
            refreshReadStates(for: id)
            // Nový diff = jiné řádky, takže výskyty hledání platí pro kód, který v okně už není
            // (#152). Bez tohohle by pruh ukazoval počet z minula a skok mířil do prázdna.
            refreshDiffSearches(in: id)
        } catch is CancellationError {
            // Přepnutí na jiné PR načítání zruší. Nechat tam `.loading` by znamenalo
            // spinner, který se nikdy nedotočí. Maže se **jen** rozdělaný stav: mezitím
            // spuštěné načtení už mohlo doběhnout a to se přepsat nesmí.
            if diffStates[id] == .loading { diffStates[id] = nil }
        } catch let error as GitHubError {
            // **Příčinu třídí `Policy`, ne tenhle `catch`** (#542): strop GitHubu na počet souborů
            // se pozná z odpovědi a v okně vede jinam než výpadek sítě — jinou větou i jinou
            // nabídkou, protože druhý pokus u něj vrátí totéž.
            diffStates[id] = .failed(Policy.diffFailure(error))
        } catch {
            diffStates[id] = .failed(.other(error.localizedDescription))
        }
    }

    /// Rozdělané načítání se za platný diff **nepovažuje** — dvě souběžná načtení jsou
    /// jen zbytečné volání navíc, kdežto přeskočit to jediné, které běží, znamená prázdno
    /// v okně, dokud si uživatel PR nevybere znovu.
    private func hasCurrentDiff(for pullRequest: PullRequestSummary) -> Bool {
        guard case .loaded(_, let updatedAt) = diffStates[pullRequest.id] else { return false }
        return updatedAt == pullRequest.updatedAt
    }

    /// S jakým pohledem se diff kreslí: odchylka z lišty, jinak hodnota z nastavení.
    var diffLayout: DiffLayout {
        diffLayoutOverride ?? configuration.global.diffLayout
    }

    /// Přepnutí z lišty nad diffem.
    ///
    /// Odchylka se zapíše **i tehdy, když se rovná nastavené hodnotě**. Je to totéž pravidlo
    /// jako u `Configuration.setRepository`, kde se maže podle prázdnosti a ne podle shody
    /// s globální hodnotou: kdo si pohled otočil sám, má ho podržet i po změně v nastavení.
    /// Do zavření aplikace — po restartu platí zase nastavení.
    func setDiffLayout(_ layout: DiffLayout) {
        diffLayoutOverride = layout
    }

    /// Je soubor sbalený? `commit == nil` = diff PR (`Změněné soubory`), jinak diff commitu (#317).
    ///
    /// **Sbalení se mezi těmi dvěma diffy nesdílí**, i když jde o týž soubor: jsou to dvě různé
    /// obrazovky a sbalit si `Foo.php` při čtení commitu neznamená, že ho nechci vidět v review.
    /// Rozhoduje o tom `FileExpansionKey`, tedy tentýž klíč jako u rozbaleného kontextu — jedna
    /// hranice pro obojí, ať se nedá zapomenout jen v jednom z nich.
    ///
    /// **Od #500 se odvozuje ze značky `Prošlo`**, dokud si člověk neřekne jinak: prošlý soubor
    /// je sbalený, změněný od prošlého se sám rozbalí. Rozhoduje `Policy.isFileFolded`, tady se
    /// jen dohledá odchylka a stav. V diffu commitu značky nejsou, takže tam platí odchylka nebo
    /// „rozbaleno“.
    func isFolded(_ path: String, in pr: PRIdentifier, commit: String? = nil) -> Bool {
        Policy.isFileFolded(
            state: commit == nil ? readState(of: path, in: pr) : .unread,
            override: fileFolding[FileExpansionKey(pullRequest: pr, path: path, commit: commit)]
        )
    }

    /// Klik na hlavičku souboru. Zapisuje se **odchylka od odvozeného**, ne absolutní stav —
    /// jinak by se sbalený prošlý soubor rozbalil a značka by se s ním rozešla.
    func toggleFolded(_ path: String, in pr: PRIdentifier, commit: String? = nil) {
        let key = FileExpansionKey(pullRequest: pr, path: path, commit: commit)
        fileFolding[key] = !isFolded(path, in: pr, commit: commit)
    }

    /// Rozbalí soubor, ať se dá skočit dovnitř. Skok na sbalený soubor by jinak skončil
    /// nikde — jeho řádky v líném seznamu vůbec nejsou.
    ///
    /// Bez `commit`u schválně: skáče se jedině v diffu PR (z nálezu, z palety, z anotace CI),
    /// takže parametr, který by tady nikdo nevyplnil jinak než `nil`, by byl jen další místo,
    /// kde se dá splést.
    /// **Zapíše výslovné rozbaleno**, ne jen smazání odchylky (#500): u prošlého souboru je
    /// odvozený stav „sbaleno“, takže smazaná odchylka by ho nechala zavřený a skok by skončil
    /// na jeho hlavičce.
    func unfold(_ path: String, in pr: PRIdentifier) {
        fileFolding[FileExpansionKey(pullRequest: pr, path: path)] = false
    }

    /// Sbalí vyjmenované soubory. Cesty dodává volající, protože co je v diffu, store neví.
    func foldAll(_ paths: [String], in pr: PRIdentifier, commit: String? = nil) {
        for path in paths {
            fileFolding[FileExpansionKey(pullRequest: pr, path: path, commit: commit)] = true
        }
    }

    /// Rozbalí všechno v tomhle diffu — **včetně prošlých souborů** (#500), protože `Rozbalit vše`
    /// je výslovný pokyn a značka je jen výchozí odpověď.
    ///
    /// Odchylky se proto nemažou, ale **přepisují na `false`** u všeho, co značku má; u zbytku
    /// stačí smazat, protože bez značky je odvozený stav „rozbaleno“. Cesty se berou ze značek,
    /// ne z diffu: `unfoldAll` seznam souborů nedostává a značka na soubor, který v diffu není,
    /// nikoho nezajímá.
    ///
    /// Sahá **jen na tohle PR a jen na tenhle diff**: sbalení v jiném je cizí stav a smazat ho
    /// při „rozbalit vše“ by znamenalo, že se tlačítko v jednom okně projeví jinde.
    func unfoldAll(in pr: PRIdentifier, commit: String? = nil) {
        fileFolding = fileFolding.filter { $0.key.pullRequest != pr || $0.key.commit != commit }
        guard commit == nil, let marks = readMarks[pr] else { return }
        for path in marks.marks.keys {
            fileFolding[FileExpansionKey(pullRequest: pr, path: path)] = false
        }
    }

    func loadedDiff(for pr: PRIdentifier) -> Diff? {
        guard case .loaded(let diff, _) = diffStates[pr] else { return nil }
        return diff
    }
}
