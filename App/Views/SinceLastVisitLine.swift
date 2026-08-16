import Foundation

/// Odrážka pruhu „od tvé poslední návštěvy“ **po částech** (#284).
///
/// Do #284 to byl jeden `String` a kreslil se jedním `Text(verbatim:)`, takže v řádku nešlo nic
/// zdůraznit. Návrh (sekce 02, `.since li`) přitom sází tři různé věci: **co se stalo** tučně
/// a plnou barvou (`li b`), zbytek věty ztlumeně (`li`) a sha jako kód (`code`). Řádek se proto
/// skládá z typovaných částí — barvu a řez jim dává až view.
struct SinceLastVisitLine: Hashable {
    var parts: [Part]

    init(_ parts: [Part]) {
        self.parts = parts
    }

    /// Kus odrážky. **Význam, ne vzhled** — že „to podstatné“ je tučné a `--ink`, rozhoduje
    /// view; tady je řečeno jen, který kus to je.
    enum Part: Hashable {
        /// To, co se stalo: počet commitů, přepsaná historie, verdikt review.
        case strong(String)
        /// Zbytek věty — kdo a kdy.
        case plain(String)
        /// Zkrácená sha. Sází se jako kód, protože to kód je.
        case sha(String)
    }

    /// Celá odrážka jako holý text — **odvozený z částí**, ne psaný podruhé. Testy i nápověda
    /// se pak nemají s čím rozejít.
    var text: String {
        parts.map { part in
            switch part {
            case .strong(let value), .plain(let value), .sha(let value): value
            }
        }
        .joined()
    }
}

/// Věty pruhu „od tvé poslední návštěvy“ (#173).
///
/// **Skládají se tady, ne v `Policy`**: je to próza pro člověka, ne rozhodnutí. #284 na tom nic
/// nemění — jen se místo jednoho řetězce vracejí části, ze kterých návrh sází tučný začátek,
/// ztlumený zbytek a sha.
///
/// Mimo view, jako `TimelineEventRow` a `FindingRow`: text se pak testuje bez kreslení.
struct SinceLastVisitLines {
    let changes: VisitChanges
    /// Nová hlava PR, pokud se od minule posunula — viz `SinceLastVisitView.movedHead`.
    var movedHead: String?

    /// Pořadí je podle dopadu — co mění kód, pak co mění diskuzi.
    var lines: [SinceLastVisitLine] {
        var lines: [SinceLastVisitLine] = []
        if !changes.forcePushes.isEmpty { lines.append(rewriteLine) }
        if !changes.commits.isEmpty {
            lines.append(commitsLine)
        } else if let movedHead {
            // Hlava se posunula, ale žádný commit se do „od minule“ nevešel — typicky po
            // rebase, kde jsou commity starší než moje návštěva. Říct se to musí, protože
            // kód se změnil; kolik commitů to bylo, se z těch dat poctivě zjistit nedá.
            lines.append(SinceLastVisitLine([
                .strong("Hlava se posunula"),
                .plain(" na "),
                .sha(Self.short(movedHead)),
            ]))
        }
        lines.append(contentsOf: changes.reviews.map(reviewLine))
        if !changes.comments.isEmpty {
            lines.append(SinceLastVisitLine([
                .strong(
                    Plural.czech(
                        changes.comments.count,
                        one: "nový komentář",
                        few: "nové komentáře",
                        many: "nových komentářů"
                    )
                )
            ]))
        }
        lines.append(contentsOf: changes.events.map(Self.eventLine))
        return lines
    }

    /// U přepsané historie je zajímavější, **co zmizelo**, než co přibylo: proti té staré sha
    /// jsou psané nálezy, které jsou zrovna na obrazovce.
    private var rewriteLine: SinceLastVisitLine {
        let head = SinceLastVisitLine.Part.strong("Přepsaná historie větve")
        guard case .forcePushed(let before, _)? = changes.forcePushes.last?.kind,
              let before, !before.isEmpty
        else { return SinceLastVisitLine([head]) }
        return SinceLastVisitLine([
            head,
            .plain(" — "),
            .sha(Self.short(before)),
            .plain(" už na větvi není"),
        ])
    }

    /// „**3 nové commity** od odinuv — poslední `9c1de02`“, jak to má návrh.
    private var commitsLine: SinceLastVisitLine {
        var parts: [SinceLastVisitLine.Part] = [
            .strong(
                Plural.czech(
                    changes.commits.count,
                    one: "nový commit",
                    few: "nové commity",
                    many: "nových commitů"
                )
            )
        ]
        if let author { parts.append(.plain(" od \(author)")) }
        if case .commit(let oid, _)? = changes.commits.last?.kind, !oid.isEmpty {
            // Krátká sha posledního commitu. Celá je nečitelná a bez ní zase nejde poznat,
            // jestli mluvíme o tom, co je vidět v diffu.
            parts.append(.plain(" — poslední "))
            parts.append(.sha(Self.short(oid)))
        }
        return SinceLastVisitLine(parts)
    }

    /// Kdo ty commity pushnul — **jen když je to jeden člověk**. U smíšené dávky se jméno
    /// vynechá: „od odinuv“ nad commity dvou lidí by tvrdilo něco, co v datech není.
    private var author: String? {
        let logins = Set(changes.commits.compactMap { $0.actor?.login })
        return logins.count == 1 ? logins.first : nil
    }

    /// „vondrous **schválil** PR“ — autor ztlumeně, verdikt tučně, jak to má návrh.
    private func reviewLine(_ review: SubmittedReview) -> SinceLastVisitLine {
        SinceLastVisitLine([.plain("\(review.author) ")] + Self.verdict(of: review))
    }

    private static func verdict(of review: SubmittedReview) -> [SinceLastVisitLine.Part] {
        switch review.state {
        case .approved: [.strong("schválil"), .plain(" PR")]
        case .changesRequested: [.strong("vyžádal změny")]
        case .dismissed: [.plain("má "), .strong("zamítnuté review")]
        // `commented` i neznámý stav: víc než „napsal review“ se z toho tvrdit nedá.
        case .commented, .pending, nil: [.strong("napsal review")]
        }
    }

    /// Událost časové osy. Věta se **nepíše podruhé** — bere se z `TimelineEventRow`, včetně
    /// jeho zvýraznění: tučně jdou u ní **jména**, ne sloveso.
    ///
    /// Je to jiné pravidlo než u vět, které si pruh skládá sám (tam je tučně to, co se stalo),
    /// a je to vědomé: druhé znění téže věty by se s tím prvním rozešlo a testy by hlídaly to,
    /// které není vidět. Jedna věta, jeden zdroj — i za cenu dvou různých důvodů k tučnému.
    private static func eventLine(_ event: TimelineEvent) -> SinceLastVisitLine {
        let title = TimelineEventRow(event: event).attributedTitle
        return SinceLastVisitLine(
            title.runs.map { run in
                let text = String(title[run.range].characters)
                return run.inlinePresentationIntent?.contains(.stronglyEmphasized) == true
                    ? .strong(text)
                    : .plain(text)
            }
        )
    }

    /// Sha na sedm znaků, jako `git`, GitHub a zbytek okna.
    private static func short(_ sha: String) -> String { String(sha.prefix(7)) }
}
