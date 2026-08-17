import SwiftUI

/// Sheet se zadáním pro agenta (#333) — celý text tak, jak se zkopíruje.
///
/// **Stejné pravidlo jako u potvrzení odeslání** (#68): co je vidět, to odejde. Rozdíl je v tom,
/// kam to jde — odsud nevede cesta na GitHub, jen do schránky nebo do souboru. Proto tu **není
/// druhé potvrzení**: dvě kliknutí na dvou tlačítkách jsou brána proti odeslání a zkopírovaný text
/// nikomu nic neudělá (tatáž úvaha jako u odpovědi do vlákna, #73).
struct AgentPromptSheet: View {
    let prompt: AgentPrompt
    @Environment(\.dismiss) private var dismiss

    /// Že se zkopírovalo, musí být vidět — kliknutí, po kterém se nestane nic viditelného,
    /// vypadá jako rozbité tlačítko.
    @State private var didCopy = false
    /// Kam se uložilo, nebo proč ne. `nil` = ještě se neukládalo.
    @State private var saved: SaveResult?

    private enum SaveResult: Hashable {
        case written(URL)
        case failed(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView { content.padding(16) }
            Divider()
            footer
        }
        // **Širší než ostatní sheety, a je to celý rozsah, ne jedna mez.** Obsah je markdown se
        // zanořenými nadpisy a fenced diffy, tedy text, kterému na 720 bodech zalamoval skoro každý
        // řádek — a zalomený diff se přestane číst jako diff. Rozsah je proto posunutý celý
        // (560 → 840, 720 → 1080): kdyby se zvedl jen `idealWidth`, zmenšené okno by spadlo zpátky
        // na šířku, kvůli které se to měnilo.
        .frame(minWidth: 840, idealWidth: 1080, minHeight: 420, idealHeight: 620)
    }

    // MARK: - Hlavička

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Prompt pro implementačního agenta")
                .font(.headline)
            // `verbatim` a ruční skládání: `Text("…#\(number)")` by číslo PR prohnalo locale
            // a z #21663 udělalo „#21 663“.
            Text(verbatim: slug)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(Palette.ink2)
            Text(verbatim: subtitle)
                .font(.caption)
                .foregroundStyle(Palette.ink3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
    }

    private var slug: String {
        [
            prompt.subject.pullRequest.description,
            prompt.subject.shortHead,
            prompt.subject.branch.isEmpty ? nil : prompt.subject.branch,
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }

    /// `6 položek z 8 · 2 nálezy · 2 vlákna u řádků · 3 kB` — kolik je v textu, z kolika a jak
    /// velký text z toho je.
    private var subtitle: String {
        let items = Plural.czech(
            prompt.included.total,
            one: "položka",
            few: "položky",
            many: "položek"
        )
        return (["\(items) z \(prompt.inventory.total)"] + includedPills + [prompt.sizeText])
            .joined(separator: " · ")
    }

    // MARK: - Obsah

    private var content: some View {
        VStack(alignment: .leading, spacing: 14) {
            summary
            text
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Odznaky nad textem: co v něm je a **co se vynechalo**.
    ///
    /// Tiché zahození by vypadalo jako „tohle je všechno“. Vypnutá volba proto dostane odznak
    /// `vynecháno`, a nenačtená konverzace vlastní větu — to není moje rozhodnutí, ale mezera
    /// v tom, co aplikace ví, takže je i v samotném textu.
    private var summary: some View {
        VStack(alignment: .leading, spacing: 6) {
            caption("Co je v textu")
            // Zalomená řada, ne `HStack` (`flex-wrap: wrap` z návrhu): odznaky nesou počty, takže
            // zkrácený odznak by zahodil zrovna to, kvůli čemu tam je.
            FlowRow {
                ForEach(includedPills, id: \.self) { pill($0, tint: Palette.ink2, background: Palette.raised) }
                if prompt.blocking > 0 {
                    pill(
                        Plural.czech(prompt.blocking, one: "blokuje", few: "blokují", many: "blokuje"),
                        tint: Palette.crit,
                        background: Palette.crit.opacity(0.15)
                    )
                }
                ForEach(omittedPills, id: \.self) { pill($0, tint: Palette.ink2, background: Palette.raised) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !prompt.isConversationLoaded {
                Label {
                    Text("Konverzace k PR není načtená, takže v textu nejsou vlákna u řádků, komentáře pod PR ani souhrny review. Je to napsané i v textu.")
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "exclamationmark.triangle")
                }
                .font(.caption)
                .foregroundStyle(Palette.stale)
            }
        }
    }

    private var includedPills: [String] {
        AgentPromptChoice.allCases.compactMap { choice in
            guard let count = prompt.included.count(of: choice), count > 0 else { return nil }
            return choice.countLabel(count)
        }
    }

    /// Co je k dispozici, ale v textu není — tedy vypnutá volba, ve které něco leží.
    ///
    /// `vynecháno:` je **předsazené**, ne na konci: „2 vyřešená vlákna vynecháno“ by se muselo
    /// skloňovat podle počtu a jeden z těch tvarů by pak byl špatně.
    private var omittedPills: [String] {
        AgentPromptChoice.allCases.compactMap { choice in
            guard prompt.included.count(of: choice) == 0,
                  let count = prompt.inventory.count(of: choice), count > 0
            else { return nil }
            return "vynecháno: \(choice.countLabel(count))"
        }
    }

    /// Text **tak, jak je napsaný**, ne vyrenderovaný markdown.
    ///
    /// Je to obsah schránky, ne náhled na GitHubu: nadpisy sekcí a fenced bloky musí být vidět
    /// jako značky, protože právě podle nich se agent v zadání orientuje.
    private var text: some View {
        VStack(alignment: .leading, spacing: 6) {
            caption("Text")
            Text(verbatim: prompt.text)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(9)
                .background(Palette.raised, in: .rect(cornerRadius: 7))
                .overlay { RoundedRectangle(cornerRadius: 7).strokeBorder(Palette.line) }
        }
    }

    private func caption(_ text: String) -> some View {
        Text(verbatim: text.uppercased())
            .font(.system(size: 10, design: .monospaced))
            .tracking(1)
            .foregroundStyle(Palette.ink3)
    }

    private func pill(_ text: String, tint: Color, background: Color) -> some View {
        Text(verbatim: text)
            .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
            .foregroundStyle(tint)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(background, in: .capsule)
    }

    // MARK: - Patička

    private var footer: some View {
        HStack(spacing: 9) {
            Button("Zavřít") { dismiss() }
                .buttonStyle(.mini)
                .keyboardShortcut(.cancelAction)
            Spacer(minLength: 12)
            status
            Button("Uložit do souboru…", systemImage: "square.and.arrow.down") { save() }
                .buttonStyle(.mini)
            Button(didCopy ? "Zkopírováno" : "Zkopírovat", systemImage: didCopy ? "checkmark" : "doc.on.doc") {
                Clipboard.copy(prompt.text)
                didCopy = true
            }
            .buttonStyle(.miniPrimary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    /// Vlevo od tlačítek: kam to jde, kam se to uložilo, nebo proč ne.
    @ViewBuilder private var status: some View {
        switch saved {
        case .written(let url):
            Text(verbatim: "Uloženo do \(url.lastPathComponent)")
                .font(.caption)
                .foregroundStyle(Palette.ok)
                .lineLimit(1)
                .truncationMode(.head)
        case .failed(let detail):
            Text(verbatim: "Uložit se nepovedlo: \(detail)")
                .font(.caption)
                .foregroundStyle(Palette.crit)
                .lineLimit(2)
        case nil:
            // Že se nic neodesílá, stojí v patičce návrhu doslova — je to jediná věta, která tenhle
            // sheet odlišuje od potvrzení odeslání, a ta se má číst dřív, než někdo klikne.
            Text("nikam se to neodesílá")
                .font(.caption)
                .foregroundStyle(Palette.ink3)
        }
    }

    /// Uložení do souboru. Chyba se **ukáže**, ne spolkne — jinak vypadá plný disk jako uložený
    /// soubor.
    private func save() {
        do {
            guard let url = try TextFileExport.save(
                prompt.text,
                suggestedName: Policy.agentPromptFileName(for: prompt.subject)
            ) else { return }
            saved = .written(url)
        } catch {
            saved = .failed(error.localizedDescription)
        }
    }
}
