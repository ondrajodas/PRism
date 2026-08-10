import SwiftUI

/// Jeden řádek tabulky nálezů (#242, `.frow`).
///
/// Sloupce mají **spočítanou** šířku, ne pružnou (#220): buňka s `frame(maxWidth: .infinity)` na
/// každém řádku je přesně ten vzor, kvůli kterému okno na velkém PR tuhlo 20 minut.
struct FindingTableRowView: View {
    let row: FindingTableRow
    let layout: FindingTableLayout
    var blockingCategories: Set<String> = Policy.defaultBlockingCategories
    /// Stojí na tomhle místě kurzor procházení (#187)?
    var isCurrent = false
    var isExpanded = false
    var findingActions: FindingActions?
    /// Převzetí nálezu do rozdělaného review. Bere se z toho jen `adopt`, `isAdopted`, `target`
    /// a `canCompose` — komentáře k řádkům se z tabulky nezakládají, ty patří k diffu.
    var draft = FileDraftActions()
    let toggle: () -> Void
    /// Skok do diffu na místo nálezu.
    let jump: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            columns
            if isExpanded { expansion }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, FindingTableLayout.inset)
        .background(isCurrent ? Palette.accentWeak : .clear)
        .overlay(alignment: .bottom) { Rectangle().fill(Palette.lineSoft).frame(height: 1) }
        // Ztlumit, ne schovat: odmítnutý řádek zůstává k přečtení, protože jinak by se nedalo
        // zkontrolovat, co jsem odmítl. Tatáž úvaha jako `DismissedRowStyle` u karet.
        .opacity(row.dismissal == nil ? 1 : 0.52)
    }

    // MARK: - Sbalený řádek

    /// Sbalený řádek. **Kliknutí kamkoli do něj skáče do diffu** — tentýž pohyb, jaký umí karta
    /// v panelu a odkaz na nález v `Přehledu`; je to to, co se dělá nejčastěji.
    ///
    /// Gesto sedí na **buňkách bez akcí**, ne na celém řádku: kdyby leželo pod `⋯` a šipkou,
    /// soutěžilo by s nimi o klik a odmítnutí nálezu by odscrollovalo diff.
    private var columns: some View {
        HStack(alignment: .top, spacing: FindingTableLayout.spacing) {
            HStack(alignment: .top, spacing: FindingTableLayout.spacing) {
                bar
                severity
                summary
                location
                reviewer
            }
            .contentShape(.rect)
            .onTapGesture(perform: jump)
            actions
        }
    }

    /// Proužek závažnosti na hraně řádku — čte se dřív než text, stejně jako v řádku fronty
    /// (#172) a na kartě nálezu (#175). Barvy jsou proto z **téže** škály.
    private var bar: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(accent)
            .frame(width: FindingTableLayout.bar)
            .frame(minHeight: 20)
            .accessibilityHidden(true)
    }

    private var accent: Color {
        if row.dismissal != nil { return Palette.ink3 }
        return row.isBlocking ? Palette.crit : Palette.find
    }

    /// Sloupec závažnosti nese **jen to, co je vidět na první pohled**: blokuje / neplatný.
    /// Kategorie do něj nepatří, ta je u reviewera — jinak by se ve 92 bodech nevešlo ani jedno.
    ///
    /// Prázdno se kreslí `Color.clear`, ne prázdným `Group`em: **`EmptyView` `frame(width:)`
    /// ignoruje**, takže by se u nálezu bez odznaku sloupec sesypal a celý řádek by se posunul
    /// o 92 bodů vlevo — tabulka by pak měla dva různé rastry. Chyceno offscreen renderem.
    private var severity: some View {
        HStack(spacing: 0) {
            if let dismissal = row.dismissal {
                pill(dismissal.reason.label, tint: Palette.ink2, background: Palette.raised)
                    .help(row.representative.categoryHelp)
            } else if row.isBlocking {
                pill("blokuje", tint: Palette.crit, background: Palette.crit.opacity(0.15))
                    .help("Blokující nález — kvůli němu se PR nemerguje")
            } else {
                Color.clear.frame(height: 1)
            }
            Spacer(minLength: 0)
        }
        .frame(width: layout.severity, alignment: .leading)
    }

    private var summary: some View {
        Button(action: jump) {
            Text(verbatim: row.representative.summary)
                .font(.callout)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: layout.summary, alignment: .leading)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help("Skočí na místo v diffu")
    }

    private var location: some View {
        Text(verbatim: row.representative.location)
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(Palette.ink2)
            .lineLimit(1)
            // Zepředu, ať zůstane jméno souboru a číslo řádku — z dlouhé cesty je zajímavý konec.
            .truncationMode(.head)
            .frame(width: layout.location, alignment: .leading)
            .help(row.representative.locationHelp)
    }

    /// Reviewer a jeho kategorie pod sebou — a `2×` místo jména, když se dva shodli.
    ///
    /// Odznak, ne dva řádky: dva řádky by tvrdily, že jsou to dva různé nálezy. Kdo přesně to byl,
    /// je v rozbalené části a v bublině u kódu.
    @ViewBuilder private var reviewer: some View {
        if let width = layout.reviewer {
            VStack(alignment: .leading, spacing: 2) {
                if row.agreement > 1 {
                    pill("\(row.agreement)×", tint: .accentColor, background: .accentColor.opacity(0.15))
                        .help("Nezávisle nahlásili \(reviewers)")
                } else {
                    Text(verbatim: row.representative.reviewer)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Palette.ink3)
                        .lineLimit(1)
                }
                Text(verbatim: row.representative.category)
                    .font(.caption2)
                    .foregroundStyle(Palette.ink3)
                    .lineLimit(1)
            }
            .frame(width: width, alignment: .leading)
        }
    }

    private var reviewers: String {
        row.findings.map(\.reviewer).joined(separator: ", ")
    }

    /// Co se dá s řádkem udělat.
    ///
    /// **Odmítnutí je tady v `⋯`, v bublině zůstává dvěma odkazy** — vědomý rozdíl proti #113:
    /// v tabulce by se šest odkazů opakovalo na každém řádku a přebily by shrnutí, kvůli kterému
    /// se tabulka čte. `Vrátit` je proti tomu jeden odkaz, takže zůstává vidět.
    ///
    /// `Převzít` se nabízí **jen u řádku s jediným nálezem**: u shody dvou reviewerů není co
    /// převzít „za celý řádek“ — texty jsou dva a převzít jeden potichu by byla polovina akce.
    /// Od toho je rozbalená část, kde má každý nález svoje tlačítko.
    private var actions: some View {
        HStack(spacing: 9) {
            Spacer(minLength: 0)
            if row.dismissal != nil {
                restore
            } else if row.findings.count == 1 {
                adoption(of: row.representative)
            }
            if row.dismissal == nil { menu }
            disclosure
        }
        .font(.caption)
        .frame(width: layout.actions, alignment: .trailing)
    }

    @ViewBuilder private var restore: some View {
        if let findingActions {
            Button("Vrátit") { findingActions.restore(row.representative.finding) }
                .buttonStyle(.link)
                .help("Vrátit nález mezi platné")
        }
    }

    @ViewBuilder private func adoption(of finding: FindingRow) -> some View {
        if draft.canCompose {
            if draft.isAdopted(finding.finding) {
                Label("v mém review", systemImage: "checkmark.circle.fill")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.tint)
                    .help("Text je už v rozdělaném review")
            } else {
                Button("Převzít") { draft.adopt(finding.finding) }
                    .buttonStyle(.link)
                    .help("Vloží text nálezu do mého review. Text jde přepsat.")
            }
        }
    }

    @ViewBuilder private var menu: some View {
        if let findingActions {
            Menu {
                ForEach(FindingDismissal.Reason.allCases, id: \.self) { reason in
                    Button("Označit jako \(reason.label)") {
                        findingActions.dismiss(row.representative.finding, reason)
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .foregroundStyle(Palette.ink3)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Odmítnout nález")
        }
    }

    private var disclosure: some View {
        Button(action: toggle) {
            Image(systemName: "chevron.right")
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                .foregroundStyle(Palette.ink3)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(isExpanded ? "Sbalit podrobnosti" : "Rozbalit celý nález")
        .accessibilityLabel(isExpanded ? "Sbalit podrobnosti" : "Rozbalit celý nález")
    }

    // MARK: - Rozbalený řádek

    /// Rozbalená část je **ta samá bublina jako u kódu**, ne druhá sazba téhož.
    ///
    /// Nese celé texty, „Kdy to selže“, převzetí a odmítnutí každého nálezu zvlášť — tedy přesně
    /// to, co se do sbaleného řádku nevejde. Druhá varianta téhož by znamenala dvě místa, ve
    /// kterých se zapomene na nový stav; tady se s bublinou nemá čím rozejít.
    private var expansion: some View {
        FindingBubbleView(
            group: row.group,
            blockingCategories: blockingCategories,
            // V tabulce se o kotvě nemluví: „řádek v diffu není“ je tvrzení o diffu, a ten je
            // v jiném tabu. Kde nález je, říká sloupec `místo`.
            isAnchored: true,
            draft: draft,
            actions: findingActions,
            indent: 0
        )
        .padding(.top, 6)
        .frame(width: expansionWidth, alignment: .leading)
        .padding(.leading, expansionIndent)
    }

    /// Bublina začíná u sloupce `shrnutí` — pod proužkem a závažností by visela v prázdnu.
    private var expansionIndent: Double {
        FindingTableLayout.bar + layout.severity + FindingTableLayout.spacing * 2
    }

    /// A končí u pravé hrany řádku. Spočítaná šířka, ne pružná: viz #220.
    private var expansionWidth: Double {
        let columns = [layout.summary, layout.location, layout.reviewer, layout.actions]
            .compactMap { $0 }
        return columns.reduce(0, +) + FindingTableLayout.spacing * Double(columns.count - 1)
    }

    private func pill(_ text: String, tint: Color, background: Color) -> some View {
        Text(verbatim: text)
            .font(.caption2)
            .lineLimit(1)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(background, in: .capsule)
            .foregroundStyle(tint)
    }
}
