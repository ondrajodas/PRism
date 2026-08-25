import SwiftUI

/// Kontrola rozdělaného review proti novému commitu (#69) — **první stránka potvrzení odeslání**.
///
/// Je vidět, **co se stane s každou kotvou**, a to je celý smysl: draft se nemá na nový commit
/// přenést tiše. Sedí / posunulo se / nevím / ztraceno, u každého komentáře s volbou.
///
/// Vlastní okno to není schválně (rozhodnuto při zkoušení #69): zkontrolovat kotvy se musí tak či
/// tak, než review odejde, takže druhé okno by byl jen mezikrok, ve kterém se kliká na totéž.
/// Odesílá se pořád **dvěma kliknutími na dvě různá tlačítka** (pravidlo z #68) — jen to první je
/// teď „přenést“.
struct DraftTransferView: View {
    /// Komentáře se stavem kotvy, jak je složila `Policy`.
    let anchors: [DraftAnchorCheck]
    /// Commit, na který se přenáší.
    let head: String
    /// Rozhodnutí, která člověk změnil. Drží je **okno**, protože potvrzovací tlačítko je v jeho
    /// patičce; co v mapě není, se řídí výchozím pro svůj stav (`Policy.defaultChoice`).
    @Binding var choices: [UUID: DraftTransferChoice]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if anchors.isEmpty {
                Text("V review nejsou žádné řádkové komentáře — přenesením se jen posune commit, proti kterému je psané.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(anchors) { check in
                        row(check.comment, state: check.state)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Review je psané proti staršímu commitu", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(Palette.find)
            Text("Tady je vidět, co se stane s každým řádkovým komentářem. Po přenesení na \(head.prefix(7)) se ukáže payload a teprve pak se dá odeslat.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Jeden komentář

    /// Kotva jako karta se stavem na hraně (#178).
    ///
    /// Proužek je tatáž škála jako u nálezů a v řádku fronty: **červená znamená, že se s tím
    /// musí něco udělat**. Ztracená kotva je jediná věc, kterou GitHub odmítne i s celým
    /// review, takže musí být poznat bez čtení.
    private func row(_ comment: ReviewDraftComment, state: DraftAnchorState) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(verbatim: Policy.location(of: comment))
                    .font(.system(.callout, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.head)
                badge(state)
                Spacer(minLength: 8)
            }
            preview(of: comment)
            picker(for: comment, state: state)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 8))
        .overlay(alignment: .leading) {
            Rectangle().fill(Self.appearance(of: state).color).frame(width: 3)
        }
        .clipShape(.rect(cornerRadius: 8))
    }

    /// Stav kotvy jako odznak. Každý stav má **vlastní** text i barvu — „posunulo se“ a „ztratilo
    /// se“ vedou jinam, takže se nesmí slít do jednoho varování.
    ///
    /// Kapsle, ne `Label` v barvě textu: odznak v řádku s cestou jinak splyne s okolím a stav
    /// se hledá čtením. Tvar je tentýž jako u stavu review v seznamu.
    private func badge(_ state: DraftAnchorState) -> some View {
        let appearance = Self.appearance(of: state)
        return Label(appearance.text, systemImage: appearance.symbol)
            .font(.caption)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(appearance.color.opacity(0.15), in: .capsule)
            .foregroundStyle(appearance.color)
    }

    private static func appearance(of state: DraftAnchorState) -> (text: String, symbol: String, color: Color) {
        switch state {
        case .fits:
            ("sedí", "checkmark.circle.fill", Palette.ok)
        case .moved(let anchor):
            ("posunulo se na \(lines(of: anchor))", "arrow.down.circle.fill", .blue)
        case .uncertain:
            ("nevím, co tam bylo", "questionmark.circle.fill", Palette.find)
        case .lost:
            ("řádek v novém diffu není", "xmark.circle.fill", Palette.crit)
        }
    }

    /// Čísla nové kotvy — u rozsahu oba konce, ať je poznat, že se posunul celý.
    private static func lines(of anchor: DraftAnchor) -> String {
        guard let start = anchor.start else { return "\(anchor.line)" }
        return "\(start.line)–\(anchor.line)"
    }

    /// Text komentáře, ať je poznat, o co se rozhoduje. Zalomení se slévá do jednoho řádku —
    /// v seznamu jde o orientaci, ne o čtení celé prózy.
    private func preview(of comment: ReviewDraftComment) -> some View {
        Text(verbatim: comment.body.singleLine)
            .font(.callout)
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Volby jsou tři u každého stavu, ne jen u ztracené kotvy: vyjmout komentář nebo ho přepsat
    /// do těla je legitimní i u toho, který sedí — kdo se dívá na nový commit, může si to
    /// rozmyslet.
    private func picker(for comment: ReviewDraftComment, state: DraftAnchorState) -> some View {
        Picker("", selection: choice(for: comment, state: state)) {
            Text(keepLabel(for: state)).tag(DraftTransferChoice.keep)
            Text("Přepsat do těla review").tag(DraftTransferChoice.body)
            Text("Vyjmout").tag(DraftTransferChoice.delete)
        }
        .pickerStyle(.radioGroup)
        .labelsHidden()
    }

    /// „Nechat“ znamená u každého stavu něco jiného, takže se to musí říct — u posunuté kotvy je
    /// to přenesení na nový řádek, u nejisté ponechání tam, kde je.
    private func keepLabel(for state: DraftAnchorState) -> String {
        switch state {
        case .fits: "Nechat na svém řádku"
        case .moved(let anchor): "Přenést na řádek \(Self.lines(of: anchor))"
        case .uncertain: "Nechat, kde je (zkontroluj to)"
        case .lost: "Nechat kotvu — GitHub takový komentář odmítne"
        }
    }

    /// Volba komentáře; co v mapě není, se řídí výchozím pro stav. Zápis jde vždycky do mapy, i když
    /// se rovná výchozímu — jinak by se „vrátil jsem to zpátky“ nedalo odlišit od „nic jsem neřekl“.
    private func choice(for comment: ReviewDraftComment, state: DraftAnchorState) -> Binding<DraftTransferChoice> {
        Binding(
            get: { choices[comment.id] ?? Policy.defaultChoice(for: state) },
            set: { choices[comment.id] = $0 }
        )
    }
}
