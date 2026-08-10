import SwiftUI

/// Co se na PR stalo od poslední návštěvy (#173).
///
/// Stojí **nahoře v `Přehledu`**, nad popisem: je to jediná věc na obrazovce, která odpovídá na
/// otázku „co je tu nového“, a ta se ptá dřív než „o čem to je“.
///
/// Ukazuje se, jen když **opravdu něco přibylo**. Trvalý pruh s „nic nového“ by z obrazovky
/// ubíral místo a po týdnu by se přestal číst — na rozdíl od stavového řádku, kde je trvalost
/// smyslem, protože se tam hlásí zdraví aplikace.
///
/// Sazba je z návrhu (`.since`, #226): okrový tón (`--stale`), levý okraj 3 body, obrys smíchaný
/// s tónem, poloměr 7 jako u ostatních karet `Přehledu`.
///
/// **Barva je jedna, ne dvě** — do #226 byl blok systémově modrý a při přepsané historii žlutý.
/// Obojí bylo mimo paletu okna: modrá je systémový akcent, kdežto okno stojí na fialové z návrhu
/// (#180), a systémová žlutá je **výstraha**. `--stale` znamená „platilo to, dneska už ne“, což je
/// přesně to, co tenhle blok říká — a proto ho návrh kreslí okrový vždycky. Že se přepsala historie,
/// nese `staleRow` větou a tlačítkem, ne odstínem pozadí.
struct SinceLastVisitView: View {
    let changes: VisitChanges
    /// Proti čemu se to počítá. Bez toho by „od tvé poslední návštěvy“ neřeklo od kdy.
    let since: Date?
    /// Zastaraly kvůli tomu nálezy nebo rozdělané review? Počítá store, ne tenhle typ —
    /// je to tvrzení o uložených datech, ne o časové ose.
    var isStale = false
    /// Nová hlava PR, pokud se od minule posunula. Je to **druhý zdroj** vedle časové osy:
    /// `TimelineEvent.at` je u commitu datum commitu, ne pushnutí, takže po rebase commity
    /// z „od minule“ vypadnou — porovnání sha na to nesáhne.
    var movedHead: String?
    var rerun: (() -> Void)?
    /// „Přečteno“. Bez toho by pruh visel, dokud je aplikace spuštěná — správně napoprvé,
    /// otravně napopáté.
    var dismiss: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            header
            VStack(alignment: .leading, spacing: 3) {
                // Identita je **pořadí**, ne text: dvě položky se snadno složí do stejné věty
                // (dvě review od téhož autora se stejným verdiktem) a `id: \.self` by z nich
                // udělal jeden řádek.
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    Label {
                        Text(verbatim: line).font(.system(size: 12))
                    } icon: {
                        Image(systemName: "circle.fill").font(.system(size: 4))
                    }
                    .foregroundStyle(Palette.ink2)
                }
            }
            if isStale { staleRow }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.stale.opacity(0.09))
        // Pruh je v návrhu **levý okraj rámečku** (`border-left: 3px`), takže se zaoblením
        // zatáčí. `overlay` s obdélníkem by z něj udělal rovnou tyčku useknutou v rozích —
        // proto pozadí a `clipShape`, které mu ten oblouk dá.
        .background(alignment: .leading) { Rectangle().fill(Palette.stale).frame(width: 3) }
        .clipShape(.rect(cornerRadius: 7))
        // Obrys **je**, a to je půlka problému, kterou to řeší: bez něj plavala plná barevná
        // plocha vedle obrysových karet `Přehledu`. Barva je obrys smíchaný s tónem bloku,
        // jak to má návrh (`color-mix(--stale 45%, --line)`).
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .strokeBorder(Palette.stale.mix(with: Palette.line, by: 0.55), lineWidth: 1)
        }
    }

    private var header: some View {
        HStack(spacing: 7) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 12))
                .foregroundStyle(Palette.stale)
            Text("Od tvé poslední návštěvy")
                .font(.system(size: 12.5, weight: .semibold))
            Spacer(minLength: 8)
            if let since {
                // Mono a `--ink-3`, jak to má návrh (`.since .hd .when`): je to údaj, ne věta.
                Text(since, format: .relative(presentation: .named))
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Palette.ink3)
            }
            if let dismiss {
                Button(action: dismiss) {
                    Image(systemName: "xmark")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                // Nápověda říká **důsledek**, ne jméno ikony: křížek u oznámení se dá číst
                // i jako „zahodit ty změny“, a to by tohle tlačítko nikdy neudělalo.
                .help("Označit za přečtené — pruh zmizí, dokud nepřibude něco dalšího")
                .accessibilityLabel("Označit za přečtené")
            }
        }
    }

    /// Důsledek stojí u události, která ho způsobila — ne v jiném rohu okna. Tlačítko je tady
    /// proto, že po přepsané historii je pustit review znovu jediná rozumná další věc.
    private var staleRow: some View {
        HStack(spacing: 8) {
            Text("Nálezy i rozdělané review jsou proti commitu, který na větvi už není.")
                .font(.system(size: 11.5))
                .foregroundStyle(Palette.ink2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            if let rerun {
                Button("Pustit review znovu", action: rerun)
                    .controlSize(.small)
            }
        }
        .padding(.top, 2)
    }

    /// Věty se skládají **tady**, ne v `Policy`: je to próza pro člověka, ne rozhodnutí.
    /// Pořadí je podle dopadu — co mění kód, pak co mění diskuzi.
    private var lines: [String] {
        var lines: [String] = []
        if !changes.forcePushes.isEmpty {
            lines.append("Přepsaná historie větve\(rewriteDetail)")
        }
        if !changes.commits.isEmpty {
            lines.append(
                "\(Plural.czech(changes.commits.count, one: "nový commit", few: "nové commity", many: "nových commitů"))\(commitDetail)"
            )
        } else if let movedHead {
            // Hlava se posunula, ale žádný commit se do „od minule“ nevešel — typicky po
            // rebase, kde jsou commity starší než moje návštěva. Říct se to musí, protože
            // kód se změnil; kolik commitů to bylo, se z těch dat poctivě zjistit nedá.
            lines.append("Hlava se posunula na \(movedHead.prefix(7))")
        }
        for review in changes.reviews {
            lines.append("\(review.author) \(verb(of: review))")
        }
        if !changes.comments.isEmpty {
            lines.append(
                Plural.czech(
                    changes.comments.count,
                    one: "nový komentář",
                    few: "nové komentáře",
                    many: "nových komentářů"
                )
            )
        }
        for event in changes.events {
            lines.append(TimelineEventRow(event: event).title)
        }
        return lines
    }

    /// Krátká sha posledního commitu. Celá je nečitelná a bez ní zase nejde poznat, jestli
    /// mluvíme o tom, co je vidět v diffu.
    private var commitDetail: String {
        guard case .commit(let oid, _)? = changes.commits.last?.kind, !oid.isEmpty else { return "" }
        return " — poslední \(oid.prefix(7))"
    }

    /// U přepsané historie je zajímavější, **co zmizelo**, než co přibylo: proti té staré sha
    /// jsou psané nálezy, které jsou zrovna na obrazovce.
    private var rewriteDetail: String {
        guard case .forcePushed(let before, _)? = changes.forcePushes.last?.kind,
              let before, !before.isEmpty
        else { return "" }
        return " — \(before.prefix(7)) na větvi už není"
    }

    private func verb(of review: SubmittedReview) -> String {
        switch review.state {
        case .approved: "schválil PR"
        case .changesRequested: "vyžádal změny"
        case .dismissed: "má zamítnuté review"
        // `commented` i neznámý stav: víc než „napsal review“ se z toho tvrdit nedá.
        case .commented, .pending, nil: "napsal review"
        }
    }
}

#Preview {
    let actor = EventActor(login: "odinuv", avatarURL: nil, isBot: false)
    return VStack(spacing: 16) {
        SinceLastVisitView(
            changes: VisitChanges(
                commits: [
                    TimelineEvent(
                        id: "1",
                        kind: .commit(oid: "9c1de0212ab", headline: "fix: nevracet prázdný secret"),
                        actor: actor,
                        at: Date().addingTimeInterval(-3600)
                    )
                ],
                forcePushes: [
                    TimelineEvent(
                        id: "2",
                        kind: .forcePushed(before: "4f2ac9188cd", after: "9c1de0212ab"),
                        actor: actor,
                        at: Date().addingTimeInterval(-3600)
                    )
                ],
                events: [],
                reviews: [],
                comments: []
            ),
            since: Date().addingTimeInterval(-86400),
            isStale: true,
            rerun: {}
        )
    }
    .padding()
    .frame(width: 620)
}
