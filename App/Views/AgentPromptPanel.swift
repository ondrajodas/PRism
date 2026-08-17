import SwiftUI

/// Tab `Zadání` v panelu vpravo — na vlastním PR místo verdiktu (#333).
///
/// **Verdikt ani `Odeslat` tady nejsou, a nezašedly — zmizely celé.** `APPROVE`
/// i `REQUEST_CHANGES` na vlastní PR GitHub odmítne (422, změřeno u #62), takže zakázané tlačítko
/// by svádělo na něj kliknout a přečíst si chybu. Panel má jednu úlohu a ta se jmenuje v jeho
/// hlavičce: sesbírat, co je potřeba opravit, a udělat z toho jedno zadání pro agenta.
///
/// **Nic se odsud neodesílá.** Tlačítko otevře sheet s celým textem; ten skončí ve schránce nebo
/// v souboru. Proto tu není druhé potvrzení — dvě kliknutí na dvou tlačítkách jsou brána proti
/// odeslání na GitHub a tady se neodesílá nic (stejná úvaha jako u odpovědi do vlákna, #73).
struct AgentPromptPanel: View {
    /// Zadání složené z toho, co aplikace o PR ví. Skládá ho store při každém čtení — panel
    /// z něj kreslí počty i náhled, takže by dvě volání znamenala dvě různá čísla.
    let prompt: AgentPrompt
    /// Stav načtení konverzace. `nil` = ještě se o ni nikdo nepokusil.
    var conversation: ConversationState?
    /// Zapnutí a vypnutí volby.
    var toggle: (AgentPromptChoice) -> Void = { _ in }
    var isEnabled: (AgentPromptChoice) -> Bool = { _ in false }
    /// Otevře sheet s celým textem. **Neodesílá nic.**
    var compose: () -> Void = {}
    /// Rozdělané review, které na vlastním PR zbylo z dřívějška. `nil` = žádné není.
    var leftoverDraft: ReviewDraft?
    var discardDraft: () -> Void = {}

    @State private var isConfirmingDiscard = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    title
                    conversationNote
                    choices
                    preview
                    if let leftoverDraft { leftover(leftoverDraft) }
                }
                .padding(.horizontal, 13)
                .padding(.vertical, 11)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            composer
        }
    }

    // MARK: - Hlavička

    /// Titulek s klávesovou zkratkou, jak ho má návrh v hlavičce panelu (`.side > header`).
    /// Segment nad ním se jmenuje `Zadání`, aby se do 300 bodů vešel vedle `Nálezů`.
    private var title: some View {
        HStack(spacing: 6) {
            Text("Zadání pro agenta")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Palette.ink)
            Spacer(minLength: 4)
            Text(verbatim: "⌘⇧P")
                .font(.system(size: 9.5, design: .monospaced))
                .padding(.horizontal, 4)
                .foregroundStyle(Palette.ink3)
                .overlay { RoundedRectangle(cornerRadius: 4).strokeBorder(Palette.line) }
        }
    }

    /// Že konverzace **není** načtená, se musí říct.
    ///
    /// `Conversation` se nepersistuje (načítá se při zobrazení PR), takže se zadání skládá z toho,
    /// co je v paměti — a bez téhle věty by prázdný počet vláken vypadal jako „nikdo nic nenapsal“.
    /// Rozlišuje se **načítání od selhání**: čekání samo přejde, chyba ne.
    @ViewBuilder private var conversationNote: some View {
        switch conversation {
        case .loaded:
            EmptyView()
        case .loading, nil:
            note("Konverzaci k PR ještě načítám — vlákna, komentáře a souhrny review v zadání zatím nejsou.", tint: Palette.ink2)
        case .failed(let detail):
            note("Konverzaci k PR se nepovedlo načíst, takže v zadání nejsou vlákna, komentáře ani souhrny review. \(detail)", tint: Palette.crit)
        }
    }

    private func note(_ text: String, tint: Color) -> some View {
        Label {
            Text(verbatim: text)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "info.circle")
        }
        .font(.caption)
        .foregroundStyle(tint)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Volby

    /// Zaškrtávací řádky z návrhu (`.radio` se čtvercovým `i`) — sedm, v pořadí výčtu.
    ///
    /// **Vyřešená vlákna a odmítnuté nálezy jsou vidět s počtem, i když jsou vypnuté.** Zmizet
    /// nesmí: `vyřešeno` je stav vlákna na GitHubu, ne důkaz, že je hotovo, a odmítnutý nález je
    /// moje rozhodnutí, které si můžu chtít v zadání připomenout.
    private var choices: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(AgentPromptChoice.allCases, id: \.self) { choice in
                choiceRow(choice)
            }
        }
    }

    private func choiceRow(_ choice: AgentPromptChoice) -> some View {
        let on = isEnabled(choice)
        return Button {
            toggle(choice)
        } label: {
            HStack(spacing: 7) {
                checkbox(on: on)
                Text(verbatim: choice.label)
                    .font(.system(size: 11.5))
                    .foregroundStyle(on ? Palette.ink : Palette.ink2)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let count = prompt.inventory.count(of: choice) {
                    Text(verbatim: "\(count)")
                        .font(.system(size: 10.5, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(Palette.ink3)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(choice.explanation)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    /// Čtvereček z návrhu: 12 bodů, poloměr 3. Zapnutý má akcentové obtažení **4 body dovnitř**
    /// (`border-width: 4`) na ploše panelu, ne plnou barvu — proto se kreslí obtažením přes plochu.
    private func checkbox(on: Bool) -> some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(Palette.surface)
            .overlay {
                RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(on ? Palette.accent : Palette.ink3, lineWidth: on ? 4 : 1)
            }
            .frame(width: 12, height: 12)
    }

    // MARK: - Náhled

    /// Náhled textu, jak ho má návrh (`.pl-sec` + `.pl-mono` s omezenou výškou).
    ///
    /// Ukazuje **začátek toho, co se zkopíruje**, ne parafrázi: kdo mění volby, má rovnou vidět,
    /// co se v textu změnilo. Celý text je v sheetu.
    private var preview: some View {
        VStack(alignment: .leading, spacing: 6) {
            caption(previewCaption)
            Text(verbatim: prompt.text)
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(Palette.ink2)
                .lineLimit(9)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.horizontal, 11)
                .padding(.vertical, 9)
                .background(Palette.raised, in: .rect(cornerRadius: 7))
                .overlay { RoundedRectangle(cornerRadius: 7).strokeBorder(Palette.line) }
        }
    }

    private var previewCaption: String {
        let items = Plural.czech(
            prompt.included.total,
            one: "položka",
            few: "položky",
            many: "položek"
        )
        return "Náhled · \(items), \(prompt.sizeText)"
    }

    private func caption(_ text: String) -> some View {
        Text(verbatim: text.uppercased())
            .font(.system(size: 10, design: .monospaced))
            .tracking(1)
            .foregroundStyle(Palette.ink3)
    }

    // MARK: - Rozdělané review z dřívějška

    /// Draft, který na vlastním PR zbyl z doby, kdy se tam zakládat dal.
    ///
    /// **Nezahazuje se sám a nemizí.** Odeslat ho nejde (GitHub review na vlastní PR odmítne),
    /// ale tiše zmizelá data jsou horší než data, která nejdou odeslat — takže je vidět, co v něm
    /// je, a jde smazat. Komentáře se dají otevřít i v diffu, kde jim bublina zůstává.
    private func leftover(_ draft: ReviewDraft) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            caption("Rozdělané review z dřívějška")
            // **Ne „GitHub review nepřijme“**: `COMMENT` by tam prošel (změřeno u #62), takže by
            // ta věta tvrdila víc, než je změřené. Odsud se review nesbírá, a to je to, co platí.
            Text("Odeslat ho odsud nejde — na vlastním PR se review nesbírá. Zůstává tady, aby se dalo přečíst a smazat.")
                .font(.caption)
                .foregroundStyle(Palette.ink2)
                .fixedSize(horizontal: false, vertical: true)
            if !draft.body.isEmpty {
                Text(verbatim: draft.body)
                    .font(.caption)
                    .foregroundStyle(Palette.ink2)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(draft.comments) { comment in
                Text(verbatim: "\(Policy.location(of: comment)) — \(comment.body.singleLine)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Palette.ink2)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Button("Zahodit review", systemImage: "trash") {
                isConfirmingDiscard = true
            }
            .buttonStyle(.borderless)
            .font(.callout)
            .confirmationDialog(
                "Zahodit rozdělané review?",
                isPresented: $isConfirmingDiscard,
                titleVisibility: .visible
            ) {
                Button("Zahodit", role: .destructive) { discardDraft() }
                Button("Zpět", role: .cancel) {}
            } message: {
                Text("Tělo, verdikt i všechny řádkové komentáře. Zpátky to nejde.")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Palette.stale.opacity(0.11), in: .rect(cornerRadius: 7))
        .overlay { RoundedRectangle(cornerRadius: 7).strokeBorder(Palette.stale.opacity(0.4)) }
    }

    // MARK: - Patička

    /// Tlačítko dole na hraně panelu, jak ho má návrh (`.composer .send`).
    ///
    /// Zakázané je jedině tehdy, když **není co předat** — a s důvodem, ne mlčky: prázdný sheet
    /// s hlavičkou a bez položek by vypadal jako rozbitá aplikace.
    private var composer: some View {
        VStack(spacing: 0) {
            Button(action: compose) {
                Text("Sestavit prompt →")
                    .font(.system(size: 12.5, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .foregroundStyle(prompt.isEmpty ? Palette.ink3 : Palette.surface)
                    .background(
                        prompt.isEmpty ? Palette.raised : Palette.accent,
                        in: .rect(cornerRadius: 7)
                    )
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(prompt.isEmpty)
            .help(prompt.isEmpty
                ? "Není co předat — zapni volbu, ve které něco je, nebo pusť review"
                : "Ukáže celý text; zkopírovat nebo uložit se dá až tam. Nikam se to neodesílá.")
        }
        .padding(11)
        .overlay(alignment: .top) { Rectangle().fill(Palette.line).frame(height: 1) }
    }
}
