import SwiftUI

/// Nálezy k jednomu řádku, zavěšené pod ním — jako review komentář u kódu.
///
/// Texty se **neslučují**: když se dva reviewery potkají na jednom řádku, jsou v bublině
/// pod sebou a odznak říká, kolik jich je. Nesouhlas dvou reviewerů je informace.
struct FindingBubbleView: View {
    let group: FindingGroup
    var blockingCategories: Set<String> = Policy.defaultBlockingCategories
    /// `false` = řádek nálezu v diffu není. Bublina pak visí u hlavičky souboru a nabízí
    /// ten řádek dotáhnout.
    var isAnchored = true
    var reveal: ((ClosedRange<Int>) -> Void)?
    /// Skočilo se sem právě z tabulky? Samotný scroll nepoví, kam mířil.
    var isHighlighted = false
    /// Převzetí nálezu do rozdělaného review.
    var draft = FileDraftActions()
    /// Odmítnutí a vrácení nálezu (#113). `nil` = bublina je jen ke čtení, což je stav, ve
    /// kterém se staví v testech skládání řádků a v náhledech.
    var actions: FindingActions?
    /// Odsazení do sloupce s obsahem. Ve split pohledu je v buňce jedno číslo řádku místo
    /// dvou, takže je kratší — stejný parametr jako u `ThreadBubbleView`.
    var indent: Double = DiffLineView.contentInset(for: .unified)

    /// Kolik řádků kolem nálezu se ukáže, když si o to uživatel řekne. Samotný řádek bez
    /// okolí se čte špatně.
    private static let context = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !isAnchored { missingLine }
            if group.agreement > 1 { agreementHeader }
            ForEach(Array(group.findings.enumerated()), id: \.offset) { index, finding in
                if index > 0 { Divider() }
                entry(finding)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background, in: .rect(cornerRadius: 8))
        .overlay(alignment: .leading) { accent }
        .clipShape(.rect(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(.tint, lineWidth: isHighlighted ? 2 : 0)
        }
        .animation(.easeOut(duration: 0.2), value: isHighlighted)
        .padding(.leading, indent)   // odsazení do sloupce s obsahem, vedle čísel řádků
        .padding(.trailing, 16)
        .padding(.vertical, 4)
    }

    /// Nález mimo diff. Reviewer čte celý pracovní strom, takže tohle není chyba — jen se
    /// k tomu musí dotáhnout kód, který v diffu není.
    @ViewBuilder private var missingLine: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            if let line = group.line {
                Text(verbatim: "Řádek \(line) v diffu není — reviewer ho četl v souboru.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let reveal {
                    Button("Zobrazit ho") {
                        reveal(max(1, line - Self.context)...(line + Self.context))
                    }
                    .font(.caption)
                    .buttonStyle(.link)
                }
            } else {
                Text("Nález se váže k celému souboru, ne ke konkrétnímu řádku.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    /// Odmítnutý nález se **sbalí, nezmizí** (#113). Mizející nález je v tomhle okně nejhorší
    /// vzor: schovaný se nedá přečíst a nedá se odlišit od neexistujícího — a tady o důvod
    /// víc, protože to schování je moje rozhodnutí, takže musím mít jak zkontrolovat, co jsem
    /// odmítl. Ze stejného důvodu tu není přepínač „schovat odmítnuté“.
    @ViewBuilder private func entry(_ finding: Finding) -> some View {
        if let dismissal = group.dismissal(of: finding) {
            dismissed(finding, dismissal)
        } else {
            active(finding)
        }
    }

    private func active(_ finding: Finding) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            header(finding)
            Text(finding.summary)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            if let scenario = finding.failureScenario, !scenario.isEmpty {
                DisclosureGroup("Kdy to selže") {
                    Text(scenario)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.caption)
            }
            footer(of: finding)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Jeden řádek: proč neplatí, čeho se to týkalo a jak to vzít zpátky.
    ///
    /// Text nálezu zůstává (na jeden řádek), protože bez něj by se nedalo poznat, co jsem
    /// odmítl — a pak by se to nedalo ani zkontrolovat.
    private func dismissed(_ finding: Finding, _ dismissal: FindingDismissal) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: "slash.circle")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                pill(dismissal.reason.label, color: .secondary)
                Text(verbatim: finding.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if let actions {
                    Button("Vrátit") { actions.restore(finding) }
                        .font(.caption)
                        .buttonStyle(.link)
                        .help("Vrátit nález mezi platné")
                }
            }
            // Kdy jsem to posoudil, patří do nápovědy — u PR, ke kterému se vracím za dva
            // dny, je to rozdíl mezi „to jsem řešil“ a „to jsem řešil kdysi“. Bez toho by
            // `dismissedAt` byl stav, který se drží a nikdo ho nečte.
            .help(hint(for: dismissal))
            // Odmítnutí nesahá na rozdělané review, takže se to musí říct: bez téhle věty
            // vypadá review vyčištěné a převzatý komentář v něm odejde.
            if draft.isAdopted(finding) {
                Text("Text je pořád v mém review — vyjmout se dá v tabu Moje review.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Důvod a kdy jsem ho vybral. Datum se skládá do `String`u, ne interpoluje do `Text`u —
    /// v nápovědě je to jedna věta, ne dvě hodnoty pod sebou.
    private func hint(for dismissal: FindingDismissal) -> String {
        let when = dismissal.dismissedAt.formatted(date: .abbreviated, time: .shortened)
        return "\(dismissal.reason.explanation) Odmítnuto \(when)."
    }

    /// Co se s nálezem dá udělat: vlevo převzetí do mého review, vpravo odmítnutí. Dvě různé
    /// věci na dvou stranách — kliknout omylem na to druhé by znamenalo zahodit nález,
    /// o kterém jsem chtěl napsat komentář.
    private func footer(of finding: Finding) -> some View {
        HStack(spacing: 8) {
            adoption(of: finding)
            Spacer(minLength: 8)
            dismissal(of: finding)
        }
    }

    /// Dva důvody vedle sebe, ne rozbalovací menu: je to jedno kliknutí místo dvou a rozdíl
    /// mezi nimi vysvětlí nápověda.
    @ViewBuilder private func dismissal(of finding: Finding) -> some View {
        if let actions {
            HStack(spacing: 6) {
                Text("Odmítnout:")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                ForEach(FindingDismissal.Reason.allCases, id: \.self) { reason in
                    Button(reason.label) { actions.dismiss(finding, reason) }
                        .font(.caption)
                        .buttonStyle(.link)
                        .help(reason.explanation)
                }
            }
        }
    }

    /// Převzetí nálezu do mého review — hlavní pracovní smyčka: nález → komentář mými slovy.
    ///
    /// Když už převzatý je, místo tlačítka je odznak. Bez něj by se nález dal převzít
    /// podruhé, aniž by bylo poznat, že v draftu už jednou je.
    ///
    /// Odmítnutému nálezu se nenabízí vůbec — ta větev se do sbaleného řádku nedostane.
    @ViewBuilder private func adoption(of finding: Finding) -> some View {
        if draft.canCompose {
            // Cíl se počítá **jednou**: hledá řádek v hunkách, takže u velkého souboru je to
            // průchod, který se nemá dělat čtyřikrát za každé překreslení bubliny.
            let target = draft.target(finding)
            if draft.isAdopted(finding) {
                Label(adoptedLabel(for: target), systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.tint)
            } else {
                HStack(spacing: 8) {
                    Button(adoptLabel(for: target)) { draft.adopt(finding) }
                        .font(.caption)
                        .buttonStyle(.link)
                        .help(adoptHint(for: target))
                    // Proč to nejde jako komentář u řádku, musí být vidět **bez** najetí myší:
                    // tlačítko s jiným cílem, které vypadá stejně, je horší než delší text.
                    if case .body = target {
                        Text(verbatim: "· GitHub tady řádkový komentář nepřijme")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    private func adoptLabel(for target: DraftTarget) -> String {
        switch target {
        case .line: "Převzít do review"
        case .body: "Převzít do těla review"
        }
    }

    private func adoptedLabel(for target: DraftTarget) -> String {
        switch target {
        case .line: "v mém review"
        case .body: "v těle mého review"
        }
    }

    private func adoptHint(for target: DraftTarget) -> String {
        switch target {
        case .line:
            "Vloží text nálezu jako můj komentář k tomuhle řádku. Text jde přepsat."
        case .body(let path, _):
            path == nil
                ? "Nález se neváže k místu v kódu, takže půjde do těla review jako text."
                : "Řádek není v diffu, takže GitHub komentář k němu nepřijme. Půjde do těla review jako odkaz na kód, který GitHub vyrenderuje jako úryvek."
        }
    }

    private func header(_ finding: Finding) -> some View {
        HStack(spacing: 6) {
            if Policy.isBlocking(finding, categories: blockingCategories) {
                pill("blokuje", color: .red)
            }
            if let category = finding.category {
                pill(category, color: .secondary)
            }
            Text(verbatim: finding.verdict?.rawValue ?? "?")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text(verbatim: "· \(finding.reviewer)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Spacer()
        }
    }

    /// Shoda patří **bublině**, ne jednotlivému nálezu — u každého zvlášť by odznak
    /// tvrdil, že si přikyvuje sám se sebou.
    private var agreementHeader: some View {
        HStack(spacing: 6) {
            pill("\(group.agreement)×", color: .accentColor)
            Text(verbatim: "nezávisle nahlásili \(reviewers)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private func pill(_ text: String, color: Color) -> some View {
        Text(verbatim: text)
            .font(.caption2)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(color.opacity(0.15), in: .capsule)
            .foregroundStyle(color)
    }

    /// Červený pruh po straně u blokujícího nálezu — ať je hned poznat, na co se dívat
    /// dřív.
    @ViewBuilder private var accent: some View {
        if isBlocking {
            Rectangle().fill(.red).frame(width: 3)
        }
    }

    private var background: Color {
        isBlocking ? .red.opacity(0.07) : .gray.opacity(0.12)
    }

    /// Červený pruh a pozadí se řídí **platnými** nálezy: bublina, jejíž jediný blokující
    /// nález jsem odmítl, nemá dál křičet, že se na ni má koukat dřív.
    private var isBlocking: Bool {
        group.activeFindings.contains { Policy.isBlocking($0, categories: blockingCategories) }
    }

    /// Jen ti, jejichž nález pořád platí — jinak by odznak `2×` vyjmenoval revieweera, jehož
    /// nález jsem odmítl, a shoda by se počítala z něčeho jiného, než je napsané.
    private var reviewers: String {
        Set(group.activeFindings.map(\.reviewer)).sorted().joined(separator: ", ")
    }
}
