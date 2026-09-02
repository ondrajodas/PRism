import Foundation

/// Značky `Prošlo` u souborů v diffu (#500).
///
/// Stav (`readMarks`, `readStates`, `readMarkFailure`) zůstává v `AppStore.swift` — dělí se
/// metody, ne data.
///
/// **Store rozhoduje o tom, co je prošlé, view jen kreslí.** Je to totéž pravidlo jako u sbalování
/// a rozbaleného kontextu: `PullRequestDetailView` si SwiftUI mezi PR ponechá, takže cokoli
/// z tohohle ve `@State` by přeteklo na jiný pull request.
extension AppStore {
    /// Stav značky u jednoho souboru. `unread` je odpověď i tehdy, když se z disku ještě
    /// nečetlo — z okna se to nedá odlišit a čtení běží při otevření PR.
    func readState(of path: String, in pr: PRIdentifier) -> FileReviewState {
        readStates[pr]?[path] ?? .unread
    }

    /// Stavy všech souborů toho PR — bere si je strom i hlavička souboru, a z nich se počítá
    /// i číslo v hlavičce stromu (`Policy.readFileCount`).
    ///
    /// **Jmenuje se jinak než vlastnost, ve které to leží** (`readStates`): dvě jména pro totéž
    /// jsou snesitelná u getteru, ale ne když se to čte z views — `fileReviewStates(in:)` říká
    /// **čeho** stav to je, kdežto `readStates(in:)` by vedle `readStates[pr]` znělo jako totéž.
    func fileReviewStates(in pr: PRIdentifier) -> [String: FileReviewState] {
        readStates[pr] ?? [:]
    }

    /// Načte značky z disku. Volá se **při otevření PR**; co v mapě už je, se nečte znovu.
    ///
    /// **Chyba se ukáže a v mapě zůstane prázdno**, ne aby se tiše založily prázdné značky:
    /// nezaškrtnutý diff nad souborem, který na disku je, je tvrzení, které data neunesou —
    /// a stálo by přečtení celého PR znovu.
    func loadReadMarks(for pr: PRIdentifier) async {
        guard let readMarkStore, readMarks[pr] == nil else { return }
        do {
            readMarks[pr] = try await readMarkStore.load(for: pr) ?? ReadMarks(pullRequest: pr)
        } catch {
            readMarkFailure = "Značky prošlých souborů pro \(pr) se nepodařilo přečíst. "
                + error.localizedDescription
            return
        }
        refreshReadStates(for: pr)
    }

    /// Zaškrtne, nebo odškrtne jeden soubor.
    ///
    /// **Otisk dodává volající**, protože je to údaj o tom, co je zrovna na obrazovce
    /// (`FileDiff.blobs`) — store by ho musel hledat v načteném diffu a u přejmenovaného souboru
    /// by se přitom mohl minout. Zaškrtnutí i odškrtnutí navíc **zahodí odchylku sbalení**, takže
    /// se soubor rovnou sbalí (a odškrtnutý zase rozbalí): sbalení se řídí značkou, ne tím, co
    /// zbylo v okně z minula.
    ///
    /// U změněného souboru (`changed`) klik znamená **`Prošlo znovu`**, tedy nové razítko
    /// s dnešním otiskem — ne odškrtnutí. Odškrtnout se dá jedině to, co je prošlé.
    func toggleReadMark(_ path: String, blobs: String?, in pr: PRIdentifier) {
        var marks = readMarks[pr] ?? ReadMarks(pullRequest: pr)
        if readState(of: path, in: pr).isRead {
            marks.marks[path] = nil
        } else {
            marks.marks[path] = ReadMark(blobs: blobs, markedAt: time.now)
        }
        readMarks[pr] = marks
        fileFolding[FileExpansionKey(pullRequest: pr, path: path)] = nil
        refreshReadStates(for: pr)
        persistReadMarks(for: pr)
    }

    /// Přepočítá odvozené stavy značek. **Jediné místo, které plní `readStates`** — volá se po
    /// načtení diffu, po načtení značek z disku a po zaškrtnutí.
    ///
    /// Bez načteného diffu se mapa **maže**, ne nechává: stará mapa by nesla stavy odvozené
    /// z otisků, které v okně nejsou.
    func refreshReadStates(for pr: PRIdentifier) {
        guard let diff = loadedDiff(for: pr) else {
            readStates[pr] = nil
            return
        }
        readStates[pr] = Policy.fileReviewStates(of: diff.files, marks: readMarks[pr])
    }

    /// Uloží značky na disk. **Bez čekání na výsledek** — zaškrtnutí je gesto v okně a zápis pár
    /// set bajtů, takže by čekání zdrželo překreslení.
    ///
    /// **Hodnota se čte až v tasku**, ne v tomhle volání — tentýž vzor jako `persistAsk`
    /// a `persistDraft`, a ze stejného důvodu: zaškrtává se po jednom souboru, takže dva tasky
    /// běží krátce po sobě a **pořadí jejich doběhnutí není zaručené**. Se snímkem v parametru by
    /// starší zápis přebil novější a v souboru by po restartu chyběla poslední značka.
    private func persistReadMarks(for pr: PRIdentifier) {
        guard readMarkStore != nil else { return }
        Task { [weak self] in await self?.writeReadMarks(for: pr) }
    }

    /// Selhání se **hlásí**: neuložená značka po restartu zmizí a to se musí poznat. Úspěšný
    /// zápis hlášku **maže** — na rozdíl od rozhovoru je `readMarkFailure` jen o značkách, takže
    /// povedený zápis je odpověď na tutéž otázku, na kterou se ptal ten nepovedený.
    private func writeReadMarks(for pr: PRIdentifier) async {
        guard let readMarkStore, let marks = readMarks[pr] else { return }
        do {
            try await readMarkStore.save(marks)
            readMarkFailure = nil
        } catch {
            readMarkFailure = "Značky prošlých souborů pro \(pr) se nepodařilo uložit. "
                + error.localizedDescription
        }
    }
}
