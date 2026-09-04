import SwiftUI

/// Sheet se zadáním pro agenta (#333) — celý text tak, jak se zkopíruje, a od #377 i **výběr
/// jednotlivých položek**, ze kterých vzniká.
///
/// **Stejné pravidlo jako u potvrzení odeslání** (#68): co je vidět, to odejde. Rozdíl je v tom,
/// kam to jde — odsud nevede cesta na GitHub, jen do schránky nebo do souboru. Proto tu **není
/// druhé potvrzení**: dvě kliknutí na dvou tlačítkách jsou brána proti odeslání a zkopírovaný text
/// nikomu nic neudělá (tatáž úvaha jako u odpovědi do vlákna, #73).
///
/// **Výběr ani rozbalení nepřežijí zavření sheetu**, a je to rozhodnutí, ne zjednodušení (#377):
/// sheet se otevírá k jednomu předání, předvybrání je levné (počítá se z dat při každém složení
/// zadání) a uložený výběr by znamenal další stav u pull requestu vedle razítka v `handoffs.json`
/// — tedy druhou věc, která zastará pushem a o které se nikde nepíše. Proto to drží `@State`
/// tady: zaniká to s oknem, ve kterém to vzniklo.
struct AgentPromptSheet: View {
    /// Zadání a seznam položek, jak je složil panel — tedy **výchozí výběr** bez ručních zásahů.
    let selection: AgentPromptSelection
    /// Přeskládání podle výběru. Volá to store tou samou cestou, jakou vzniklo `selection`, takže
    /// se seznam nemá jak rozejít s textem (#377).
    var rebuild: (Set<String>) -> AgentPromptSelection
    /// Že si člověk text **vzal** (#334) — zkopíroval, nebo uložil do souboru. Zapisuje razítko
    /// předání, nic víc; kam text jde, se tím nemění.
    ///
    /// **Ne při otevření sheetu.** Otevřený náhled je náhled: kdyby razítko vznikalo jím, odznak
    /// v railu by zhasl nad zadáním, které nikdo nikam nedal.
    var handoff: (AgentPrompt) -> Void = { _ in }
    @Environment(\.dismiss) private var dismiss

    /// Co jsem v seznamu překlikal proti předvybranému — **odchylka**, ne seznam vybraných.
    @State private var toggled: Set<String> = []
    /// Které položky jsou rozbalené. Rozhodnutí „co se z položky ukáže“ dělá
    /// `Policy.pickDisclosure(of:toggled:)`; tady je jen ta množina.
    @State private var expanded: Set<String> = []
    /// Přeskládané zadání. `nil` = pořád platí to, s čím se sheet otevřel.
    @State private var edited: AgentPromptSelection?
    /// Že se zkopírovalo, musí být vidět — kliknutí, po kterém se nestane nic viditelného,
    /// vypadá jako rozbité tlačítko.
    @State private var didCopy = false
    /// Kam se uložilo, nebo proč ne. `nil` = ještě se neukládalo.
    @State private var saved: SaveResult?

    private enum SaveResult: Hashable {
        case written(URL)
        case failed(String)
    }

    /// Co je na obrazovce **teď** — jedna hodnota na text, počty i seznam.
    private var current: AgentPromptSelection { edited ?? selection }

    private var prompt: AgentPrompt { current.prompt }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView { content.padding(16) }
            Divider()
            footer
        }
        // **Širší než ostatní sheety, a rozhoduje o tom podlaha.** Obsah je markdown se zanořenými
        // nadpisy a fenced diffy, tedy text, kterému na 720 bodech zalamoval skoro každý řádek —
        // a zalomený diff se přestane číst jako diff. Proto se u #333 zvedla **podlaha** z 560 na
        // 840; ta jediná se totiž uplatní.
        //
        // **`idealWidth: 1080` tady do #491 stálo, a byla to mrtvá hodnota.** SwiftUI u sheetu bez
        // `presentationSizing(.fitted)` ideální **šířku** zahodí (změřeno u #327, podruhé u #417,
        // potřetí nad tímhle sheetem v `SheetSizingTests`) — sheet se tedy vždycky otevíral 840
        // bodů široký, ne 1080, a roztáhnout se nedal. Úvaha o zmenšeném okně, která tu stála, tím
        // platí **doslova**: rozhoduje `minWidth` a jenom on, takže její závěr — zvednout celý
        // rozsah, ne jen ideál — byl správný, jen z ještě tvrdšího důvodu, než se tehdy vědělo.
        //
        // **`idealHeight` zůstává, a je to změřený rozdíl, ne nedůslednost**: ideální výška se
        // u sheetu uplatňuje. Bez ní by se zadání otevíralo 420 bodů vysoké místo 620 — tedy
        // změna vzhledu, ne oprava mrtvé hodnoty.
        //
        // **Zamítnuto přidat `.fitted`** (#491, tatáž odpověď jako u #466): sheet by se rozšířil
        // o 240 bodů, což je změna velikosti hotové obrazovky — a ta jde přes zákres do návrhu
        // a souhlas, ne přes opravu rozvržení.
        .frame(minWidth: 840, minHeight: 420, idealHeight: 620)
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

    /// `vybráno 6 z 11 · 2 nálezy, 2 vlákna u řádků · 2,8 kB` — kolik položek je v textu, z kolika
    /// se vybíralo a jak velký text z toho je.
    ///
    /// **Počet vybraných se musí rovnat počtu položek v textu** (#377), takže jde z téhož seznamu
    /// jako text: kdyby se rozešly, obrazovka lže o tom, co se zkopíruje. Je na to test.
    private var subtitle: String {
        let pills = includedPills.isEmpty ? [] : [includedPills.joined(separator: ", ")]
        return (["vybráno \(current.selected) z \(current.available)"] + pills + [prompt.sizeText])
            .joined(separator: " · ")
    }

    // MARK: - Obsah

    private var content: some View {
        VStack(alignment: .leading, spacing: 14) {
            summary
            picks
            text
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Odznaky nad textem: co v něm je a **co se vynechalo**.
    ///
    /// Tiché zahození by vypadalo jako „tohle je všechno“. Vypnutá položka proto dostane odznak
    /// s **důvodem** (`1 vlastní vynechán`), nenačtená konverzace vlastní větu — to není moje
    /// rozhodnutí, ale mezera v tom, co aplikace ví, takže je i v samotném textu.
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
            if let note = narrowedNote {
                warning(note)
            }
            if !prompt.isConversationLoaded {
                warning("Konverzace k PR není načtená, takže v textu nejsou vlákna u řádků, komentáře pod PR ani souhrny review. Je to napsané i v textu.")
            }
        }
    }

    private func warning(_ text: String) -> some View {
        Label {
            Text(verbatim: text)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "exclamationmark.triangle")
        }
        .font(.caption)
        .foregroundStyle(Palette.stale)
    }

    /// Že je zadání **zúžené** (#334) — a kolik položek do něj proto nepatří.
    ///
    /// `nil` u celého zadání. Bez téhle věty by seznam se dvěma vlákny nad PR se šesti nálezy
    /// vypadal jako „tohle je všechno“ — je to tentýž důvod, proč se vypisují odznaky `vynecháno`.
    ///
    /// **Neříká, co ty zbylé položky jsou.** Do zúžení nepadnou nálezy proti staré hlavě, ale taky
    /// všechno, co už jednou odešlo, a vyjmenovat to by tvrdilo víc, než ten počet unese.
    private var narrowedNote: String? {
        guard current.only != nil else { return nil }
        let rest = max(0, prompt.inventory.total - current.available)
        guard rest > 0 else {
            return "Zúžené zadání — jsou v něm jen položky, které po předání přibyly v diskuzi."
        }
        let items = Plural.czech(rest, one: "položka", few: "položky", many: "položek")
        return "Zúžené zadání — jsou v něm jen položky, které po předání přibyly v diskuzi. "
            + "Zbylých \(items) se do něj nenabízí; celé zadání sestavíš z panelu."
    }

    private var includedPills: [String] {
        AgentPromptChoice.allCases.compactMap { choice in
            guard let count = prompt.included.count(of: choice), count > 0 else { return nil }
            return choice.countLabel(count)
        }
    }

    /// Co je v seznamu, ale v textu ne — **po důvodech** (#377), ne po volbách.
    ///
    /// `1 vlastní vynechán`, `2 souhrny bez obsahu vynechány`. Vypnutý **druh** dostane odznak
    /// z volby (`vynecháno: 2 komentáře pod PR`), protože „2 položky vynechány“ by neřeklo, které —
    /// a zrovna u hrubého filtru je druh ta informace, kterou hledám. Ručně odškrtnutá položka
    /// odznak **nedostane**: je vidět v seznamu a počet v hlavičce ji nezapočítal, takže by to byla
    /// třetí věta o tom samém.
    private var omittedPills: [String] {
        let excluded = current.groups.flatMap(\.picks).filter { !$0.isIncluded }
        let byReason = AgentPromptExclusion.allCases.compactMap { exclusion -> String? in
            let count = excluded.count { $0.exclusion == exclusion }
            guard count > 0 else { return nil }
            return exclusion.omittedLabel(count)
        }
        let byChoice = AgentPromptChoice.allCases.compactMap { choice -> String? in
            let count = excluded.count { $0.exclusion == .kindOff && $0.item.choice == choice }
            guard count > 0 else { return nil }
            return "vynecháno: \(choice.countLabel(count))"
        }
        return byReason + byChoice
    }

    // MARK: - Výběr položek (#377)

    /// Seznam položek se zaškrtávátkem u každé — a pod ním věta o tom, co aplikace předvybrala.
    ///
    /// **Nekreslí se, když není z čeho vybírat**: prázdná krabice s hlavičkami grup by tvrdila, že
    /// se něco dá vypnout. Že není co předat, říká text i patička.
    @ViewBuilder private var picks: some View {
        if !current.groups.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                caption("Co zahrnout")
                AgentPromptPickList(
                    groups: current.groups,
                    expanded: expanded,
                    toggle: { togglePick($0) },
                    toggleExpansion: { toggleExpansion($0) }
                )
                if let note = Self.preselectionNote(current.groups) {
                    Text(verbatim: note)
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.ink3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// Text **tak, jak je napsaný**, ne vyrenderovaný markdown.
    ///
    /// Je to obsah schránky, ne náhled na GitHubu: nadpisy sekcí a fenced bloky musí být vidět
    /// jako značky, protože právě podle nich se agent v zadání orientuje.
    private var text: some View {
        VStack(alignment: .leading, spacing: 6) {
            caption("Text")
            // **Že je náhled funkcí výběru, musí být napsané** (#377): bez té věty se souvislost
            // mezi seznamem výš a textem pod ním z obrazovky nepozná.
            Text(verbatim: Self.recomputedNote(prompt))
                .font(.system(size: 11))
                .foregroundStyle(Palette.ink3)
                .fixedSize(horizontal: false, vertical: true)
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
            .lineLimit(1)
            .designPill(tint: tint, background: background)
    }

    // MARK: - Texty

    /// Věta pod seznamem — **co aplikace předvybrala jako vypnuté**, a že to jde zapnout.
    ///
    /// Mluví jen o tom, co se poznalo z dat (`AgentPromptExclusion.isPreselected`). Vyřešená
    /// vlákna, odmítnuté nálezy ani vypnutý druh do ní nepatří: to jsou zaškrtávátka, která jsem
    /// vypnul já, a vysvětlovat mi vlastní rozhodnutí je šum. `nil` = aplikace nepředvybrala nic.
    nonisolated static func preselectionNote(_ groups: [AgentPromptGroup]) -> String? {
        let excluded = groups.flatMap(\.picks).filter { !$0.isIncluded }
        let parts = AgentPromptExclusion.allCases.compactMap { exclusion -> String? in
            guard exclusion.isPreselected else { return nil }
            let count = excluded.count { $0.exclusion == exclusion }
            return count > 0 ? exclusion.countLabel(count) : nil
        }
        guard !parts.isEmpty else { return nil }
        return "Vypnuté jsem předvybral: \(parts.joined(separator: ", ")). Jdou zapnout."
    }

    /// Věta pod nadpisem `Text` — že se text přepočítal podle výběru.
    nonisolated static func recomputedNote(_ prompt: AgentPrompt) -> String {
        let items = Plural.czech(prompt.included.total, one: "položka", few: "položky", many: "položek")
        return "Přepočítáno podle výběru — \(items), \(prompt.sizeText). Odškrtnuté v textu nejsou."
    }

    // MARK: - Přepínání

    /// Zapne nebo vypne položku a **přeskládá zadání**.
    ///
    /// Přeskládá se hned, ne až při dalším překreslení: text v sheetu je to, co se zkopíruje,
    /// takže mezi kliknutím a textem nesmí být okamžik, kdy si odporují.
    private func togglePick(_ pick: AgentPromptPick) {
        if toggled.contains(pick.id) {
            toggled.remove(pick.id)
        } else {
            toggled.insert(pick.id)
        }
        edited = rebuild(toggled)
        // Hlášky o tom, co se stalo s **předchozím** textem, se zahazují: „Zkopírováno“ nad textem,
        // který se od té doby změnil, tvrdí, že mám ve schránce něco jiného, než mám.
        didCopy = false
        saved = nil
    }

    private func toggleExpansion(_ pick: AgentPromptPick) {
        if expanded.contains(pick.id) {
            expanded.remove(pick.id)
        } else {
            expanded.insert(pick.id)
        }
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
                .disabled(prompt.isEmpty)
                .help(takeHelp)
            Button(didCopy ? "Zkopírováno" : "Zkopírovat", systemImage: didCopy ? "checkmark" : "doc.on.doc") {
                Clipboard.copy(prompt.text)
                didCopy = true
                handoff(prompt)
            }
            .buttonStyle(.miniPrimary)
            .disabled(prompt.isEmpty)
            .help(takeHelp)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    /// Proč se text nedá vzít, když je výběr prázdný — **zakázané tlačítko s důvodem** (#377).
    ///
    /// Odškrtnutím všeho zbyde text, který o sobě říká „aplikace nemá co předat“, a razítko nad ním
    /// by bylo předání nulové práce: odznak `Moje PR` by zhasl a nálezy by zůstaly ležet.
    private var takeHelp: String {
        prompt.isEmpty
            ? "Není vybraná ani jedna položka — zapni v seznamu výš, co se má předat"
            : "Text jde do schránky nebo do souboru. Nikam se to neodesílá."
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
            // Razítko až po **úspěšném** uložení: zrušený dialog (`nil`) ani plný disk předání
            // nejsou, a razítko nad nezapsaným souborem by zhaslo odznak nad prací, která leží.
            handoff(prompt)
        } catch {
            saved = .failed(error.localizedDescription)
        }
    }
}
