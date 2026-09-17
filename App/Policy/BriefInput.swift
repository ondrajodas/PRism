import Foundation

/// Co dostane šestá session (#516) a kdy se vůbec pustí. **Čisté funkce, žádné I/O.**
///
/// **Rozhodovací logika do promptu nepatří.** Session je tu od toho, aby stav aplikace
/// **přeformulovala** — vybrat, co je na tahu, co blokuje a co se dá mergnout, umí `Policy` sama
/// a umí to deterministicky. Kdyby o tom rozhodoval model, byl by to druhý zdroj pravdy o desce,
/// jen dražší a pokaždé jiný.
extension Policy {
    // MARK: - Vstup

    /// Materiál pro brief — **stav aplikace, nic jiného** (#516).
    ///
    /// Skládá se z toho, co store **doopravdy má**: z pruhů desky (a ty už jsou po filtru
    /// odložených, viz `AppStore.boardEntries`), z počtu odložených a z bloku `Dění`. Není v tom
    /// ani cesta k repozitáři, ani obsah souboru, ani řádek diffu — session nemá jediný nástroj,
    /// takže co jí tenhle text neřekne, se nedozví. To je celá hranice mezi *čtením nahlas*
    /// a *review logikou*: brief mluví o **aplikaci**, ne o kódu.
    ///
    /// **Nenačtená fronta se sem nedostane**, o to se stará `Policy.brief(mode:…)`: text
    /// z prázdného seznamu by tvrdil „nic na tahu“ nad daty, která se ještě nestáhla.
    ///
    /// **Deterministický a bez locale.** Časy jsou relativní a počítané z `now` (`před 3 h`), ne
    /// formátované přes `DateFormatter` — jinak by se tentýž stav popsal na každém stroji jinak
    /// a nedal by se testovat výčtem.
    static func briefInput(board: Board, snoozed: Int = 0, now: Date) -> String {
        var lines: [String] = [
            "Stav aplikace PRism. Jsou to hotová data, ne dotaz do repozitáře.",
            "",
            briefCounts(board, snoozed: snoozed),
        ]
        for lane in board.visibleLanes {
            lines.append("")
            lines.append("Pruh \(lane.lane.title) (\(lane.count)):")
            lines += lane.rows.map { "- " + briefRow($0, now: now) }
        }
        let events = board.activity.rows
        if !events.isEmpty {
            lines.append("")
            lines.append("Dění (\(events.count) nejnovějších):")
            lines += events.map { "- " + briefEvent($0, now: now) }
        }
        return lines.joined(separator: "\n")
    }

    /// První řádek vstupu — tytéž počty, jaké nese věta pod pozdravem.
    ///
    /// **Z pruhů, ne vlastním sčítáním**: kdyby si brief počty počítal sám, uměl by se s deskou
    /// pod sebou rozejít — a nejhůř zrovna ve chvíli, kdy se pravidlo pro některý pruh změní.
    private static func briefCounts(_ board: Board, snoozed: Int) -> String {
        let counts = Dictionary(uniqueKeysWithValues: board.lanes.map { ($0.lane, $0.count) })
        let onMove = board.lanes.filter { $0.lane.isOnMove }.reduce(0) { $0 + $1.count }
        return "Celkem: na tahu \(onMove), čeká na ostatní \(counts[.waiting] ?? 0), "
            + "k merge \(counts[.merge] ?? 0), odložených \(snoozed)."
    }

    /// Jeden pull request jako řádek vstupu.
    ///
    /// **Bez URL a bez cesty na disk.** Adresa pull requestu je odkaz ven, ne stav, a session ho
    /// nemá jak otevřít (nástroje nemá žádné) — zbyl by z toho jen text, který by se mohl objevit
    /// v briefu jako falešný odkaz.
    private static func briefRow(_ entry: QueueEntry, now: Date) -> String {
        let pr = entry.pullRequest
        var parts = [
            "\(pr.repo) #\(pr.number) „\(pr.title.singleLine)“ od \(pr.author)",
            "review: \(briefReviewState(entry.state))",
        ]
        if entry.row.blocking > 0 {
            parts.append("blokuje \(entry.row.blocking)")
        }
        if entry.hasDraft {
            parts.append("leží tu rozdělané review")
        }
        parts.append("naposledy \(briefAge(from: pr.updatedAt, to: now))")
        return parts.joined(separator: ", ")
    }

    /// Jeden řádek dění. Headline i detail jsou texty, které aplikace **sama složila** — do
    /// briefu tedy nevstupuje nic, co by si model mohl splést se zadáním.
    private static func briefEvent(_ event: ActivityEvent, now: Date) -> String {
        let when = briefAge(from: event.at, to: now)
        guard let detail = event.detail, !detail.isEmpty else {
            return "\(when): \(event.headline.singleLine)"
        }
        return "\(when): \(event.headline.singleLine) — \(detail.singleLine)"
    }

    /// Stav review jedním slovem. **Výčet, ne `String(describing:)`**: syntetizovaný popis
    /// případu by do promptu pustil jména z kódu (`completed(findings: 3)`) a změnil by se
    /// s každým přejmenováním.
    static func briefReviewState(_ state: ReviewState) -> String {
        switch state {
        case .notStarted: "neběželo"
        case .queued: "čeká ve frontě"
        case .cloning: "klonuje se"
        case .checkoutFailed: "checkout selhal"
        case .running(let finished, let total): "běží (\(finished) z \(total))"
        case .clean: "čisté"
        case .completed(let findings): "\(findings) \(briefFindingWord(findings))"
        case .dismissed(let findings): "\(findings) \(briefFindingWord(findings)), všechny odmítnuté"
        case .inconclusive: "doběhlo bez závěru"
        case .failed: "spadlo"
        case .timedOut(let findings): "nedoběhlo v limitu, \(findings) \(briefFindingWord(findings))"
        case .interrupted(let findings): "přerušené, \(findings) \(briefFindingWord(findings))"
        case .stale: "zastaralé"
        }
    }

    private static func briefFindingWord(_ count: Int) -> String {
        Plural.word(count, one: "nález", few: "nálezy", many: "nálezů")
    }

    /// Jak dávno — **hrubě a bez locale** (`dnes`, `před 3 h`, `před 2 dny`).
    ///
    /// Přesná minuta by v briefu nic nezměnila a stála by za to, že se tentýž stav popíše na
    /// každém stroji jinak. Budoucí datum (posunuté hodiny na stroji) je `právě teď`, ne
    /// `před -2 h`.
    static func briefAge(from date: Date, to now: Date) -> String {
        let seconds = Int(now.timeIntervalSince(date))
        switch seconds {
        case ..<60: return "právě teď"
        case ..<3600: return "před \(seconds / 60) min"
        case ..<86_400: return "před \(seconds / 3600) h"
        default:
            let days = seconds / 86_400
            return "před \(days) \(Plural.word(days, one: "dnem", few: "dny", many: "dny"))"
        }
    }

    // MARK: - Kdy se pouští

    /// Co spustilo brief.
    enum BriefTrigger: Hashable, Sendable {
        /// Tlačítko v bloku. Za tímhle vždycky stojí člověk.
        case button
        /// Úspěšný tik pollingu. **Jediná cesta, kterou se session pustí bez kliknutí** — a
        /// proto jediná, která si žádá `firstTickOfDay`.
        case tick
    }

    /// Smí se brief teď složit? **Výčet důvodů, ne `Bool`** — každý z nich se testuje zvlášť
    /// a v okně se podle nich nekreslí totéž.
    enum BriefDecision: Hashable, Sendable {
        case start
        /// Brána je vypnutá (`BriefMode.off`), nebo automat chce spustit brief v režimu
        /// `onDemand`. V obou případech platí „samo nic nezačne“.
        case notAllowed
        /// Fronta se ještě nenačetla. Brief nad nenačtenými daty by tvrdil „nic na tahu“ —
        /// tatáž úvaha jako u věty pod pozdravem (`Policy.boardEmpty(isLoaded:)`).
        case notLoaded
        /// Jedna session už běží. Druhá by mluvila o témže stavu a stála by podruhé.
        case running
        /// Dnešek už shrnutý. Týká se **jenom automatu** — tlačítko složí brief kdykoli.
        case alreadyToday
    }

    /// Rozhodnutí o spuštění (#516).
    ///
    /// **Jedna funkce na obě cesty**, protože se liší jedinou podmínkou (`startsByItself`
    /// a dnešek) a dvě funkce by se rozešly zrovna v tom, co je na nich důležité: že tlačítko smí
    /// víc než automat, ale ani jedno nesmí bez brány.
    ///
    /// **Uložený brief rozhoduje o dnešku, ne paměť.** Kdyby se den držel jen v paměti, spustil by
    /// se brief po každém restartu znovu — tedy session za peníze pokaždé, když aplikaci zavřu
    /// a otevřu.
    static func brief(
        mode: BriefMode,
        state: BriefState,
        last: Brief?,
        isLoaded: Bool,
        now: Date,
        trigger: BriefTrigger,
        calendar: Calendar = .current
    ) -> BriefDecision {
        guard mode.isOn else { return .notAllowed }
        if trigger == .tick, !mode.startsByItself { return .notAllowed }
        guard !state.isRunning else { return .running }
        guard isLoaded else { return .notLoaded }
        guard trigger == .tick else { return .start }
        guard let last, calendar.isDate(last.writtenAt, inSameDayAs: now) else { return .start }
        return .alreadyToday
    }

    // MARK: - Co je v bloku vidět

    /// Co má blok `brief` na desce ukázat (#516). `nil` = **nekreslí se vůbec**.
    ///
    /// **Text nesmí tvrdit víc, než data unesou**, a tady je to celý obsah rozhodnutí: blok má
    /// čtyři různé podoby a každá odpovídá jednomu stavu. Prázdno mezi nimi není — prázdný
    /// rámeček je k nerozeznání od „nic se neděje“, a u spadlé session by to byla lež o tom, že se
    /// nic nedělo.
    static func briefBlock(mode: BriefMode, state: BriefState) -> BriefBlock? {
        guard mode.isOn else { return nil }
        switch state {
        case .never:
            return BriefBlock(
                body: .never("Zatím se neshrnovalo. Tři věty o tom, co je na tahu, složí session ze stavu aplikace."),
                action: "Shrň"
            )
        case .running:
            // **Tlačítko se nekreslí, ne zašedle**: běžící session se nedá spustit podruhé a druhé
            // tlačítko by o tom mlčelo. Věta říká, co se děje.
            return BriefBlock(body: .running("Shrnuji stav aplikace…"), action: nil)
        case .ready(let brief):
            return BriefBlock(body: .text(brief), action: "Shrň znovu")
        case .failed(let reason):
            return BriefBlock(body: .failed("Shrnutí se nepovedlo.", detail: reason), action: "Zkusit znovu")
        }
    }

    /// Řádek pod textem — `shrnuto 21:48 · 0,03 $ · ze stavu aplikace, ne z kódu`.
    ///
    /// **Hodiny a peníze se sem předávají naformátované**, protože obojí jde přes locale a v
    /// `Policy` by se nedalo testovat (tatáž úvaha jako u `RunUsageText`). Co tady zůstává, je
    /// **rozhodnutí, co se vypíše** — a to je jediné, co se dá pokazit potichu.
    ///
    /// **`nil` cena není nula.** Session, která cenu nenahlásila (zabitá, bez `result` eventu),
    /// peníze stála taky, takže `0,00 $` by bylo tvrzení o účtu, které neplatí.
    static func briefMeta(at clock: String, cost: String?) -> String {
        "shrnuto \(clock) · \(cost ?? "cenu nenahlásilo") · ze stavu aplikace, ne z kódu"
    }
}

/// Podoba bloku `brief` na desce (#516).
struct BriefBlock: Equatable, Sendable {
    /// Co stojí v těle bloku.
    enum Body: Equatable, Sendable {
        /// Hotový brief i s razítkem a cenou.
        case text(Brief)
        /// Ještě se neshrnovalo — věta místo prázdna.
        case never(String)
        /// Běží to.
        case running(String)
        /// Spadlo to. **Dvě věty**: co se stalo a proč — samotné „nepovedlo se“ je prázdno
        /// s rámečkem.
        case failed(String, detail: String)
    }

    let body: Body
    /// Popisek tlačítka vpravo v řádku pod textem. `nil` = tlačítko se nekreslí.
    let action: String?
}
