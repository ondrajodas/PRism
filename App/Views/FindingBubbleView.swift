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
    /// Odsazení do sloupce s obsahem. Ve split pohledu je v buňce jedno číslo řádku místo
    /// dvou, takže je kratší — stejný parametr jako u `ThreadBubbleView`.
    var indent: Double = 104

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

    private func entry(_ finding: Finding) -> some View {
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
            adoption(of: finding)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Převzetí nálezu do mého review — hlavní pracovní smyčka: nález → komentář mými slovy.
    ///
    /// Když už převzatý je, místo tlačítka je odznak. Bez něj by se nález dal převzít
    /// podruhé, aniž by bylo poznat, že v draftu už jednou je.
    @ViewBuilder private func adoption(of finding: Finding) -> some View {
        if draft.canCompose {
            // Cíl se počítá **jednou**: hledá řádek v hunkách, takže u velkého souboru je to
            // průchod, který se nemá dělat čtyřikrát za každé překreslení bubliny.
            let target = draft.target(finding)
            if draft.isAdopted(finding) {
                HStack(spacing: 6) {
                    Label(adoptedLabel(for: target), systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.tint)
                    Spacer(minLength: 0)
                }
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
                    Spacer(minLength: 0)
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

    private var isBlocking: Bool {
        group.findings.contains { Policy.isBlocking($0, categories: blockingCategories) }
    }

    private var reviewers: String {
        Set(group.findings.map(\.reviewer)).sorted().joined(separator: ", ")
    }
}
