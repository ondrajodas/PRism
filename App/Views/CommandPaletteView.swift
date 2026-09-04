import SwiftUI

/// Command palette ⌘K (#184) — jedno pole nad nálezy, soubory otevřeného PR, pull requesty,
/// repozitáři a akcemi.
///
/// **Nerozhoduje nic o výsledcích ani o úrovni**: co na dotaz sedne, v jakém pořadí to je a kolik
/// se toho ukáže, složí `AppStore.paletteSections(for:)` nad `Policy`; co říká patka, výzva pole
/// a věta prázdného stavu, přijde hotové v `CommandPalette.Stage` (#533). Tady zůstává pole,
/// kurzor a klávesy.
///
/// **Dotaz i kurzor jsou `@State`, ne stav ve storu**, a je to schválně: mají zaniknout se
/// zavřením palety. Paleta je „začínám hledat“, ne „vracím se k rozdělané práci“, takže text
/// z minula by po ⌘K vypadal jako výsledky k něčemu, na co se nikdo neptal — a `CommandPaletteView`
/// vzniká až s otevřenou paletou, takže se pokaždé začíná naprázdno. Ověřeno na běžící aplikaci
/// dvěma otevřeními za sebou: podruhé je pole prázdné a fokus je v něm zase.
///
/// **Úroveň je proti tomu ve storu** (#533): druhá úroveň si drží dotažený seznam PR, který by se
/// s každým překreslením karty tahal znovu.
struct CommandPaletteView: View {
    /// Výsledky pro to, co je v poli napsané.
    ///
    /// **Uzávěr, ne hotové sekce**: závisí to na dotazu, a ten je `@State` tady uvnitř. Skládá je
    /// store (`AppStore.paletteSections(for:)`), protože jedině on ví, ve které úrovni paleta
    /// stojí a co v ní je k prohledání — tohle view jen předá text.
    let sections: (String) -> [CommandPalette.Section]
    /// Chip, výzva, patka, věta prázdného stavu a případný puntík načítání.
    let stage: CommandPalette.Stage
    /// Vykonání řádku. Paletu zavírá **volající** — ví, jestli po vykonání zůstává okno na místě
    /// (u vstupu do repa zůstává, viz `Policy.paletteClosesAfter(_:)`).
    let run: (CommandPalette.Item) -> Void
    /// O úroveň zpět — `esc` a `⌫` na prázdném poli. V první úrovni se nevolá.
    var back: () -> Void = {}
    let close: () -> Void

    @State private var query = ""
    /// Kolikátý řádek je pod kurzorem, přes všechny skupiny dohromady. Index, ne `id`: řádky se
    /// mezi stisky klávesy mění a index se dá vždycky srovnat do rozsahu, kdežto `id`, které
    /// z výsledků vypadlo, by kurzor zahodilo.
    @State private var cursor = 0
    /// Výška seznamu — **změřená, ne vyjednaná** (#220). `ScrollView` je v ose scrollování
    /// nenasytný, takže bez toho by karta byla vysoká i nad dvěma výsledky.
    @State private var contentHeight = 0.0
    @FocusState private var isFieldFocused: Bool
    @Environment(\.openURL) private var openURL

    /// Šířka karty z návrhu (`width: min(560px, 100%)`). Nejmenší okno má 700, takže se vejde
    /// vždycky — a protože je **známá**, předá se dolů a řádky si ji nemusí vyjednávat (#220).
    static let width = 560.0
    /// Strop seznamu. Nad ním se scrolluje; **šest** skupin po šesti řádcích (#336, #533) se do
    /// okna nevejde a paleta nemá zaclonit celé okno.
    ///
    /// **S druhou skupinou PR se hodnota nezvedla** a je to úvaha o stropu skupiny, ne o kartě:
    /// vejít se všechno nemohlo ani ve čtyřech skupinách (šest nálezů a šest souborů samo o sobě
    /// přeteče), takže by zvednutí jen posunulo, od kolika řádků se scrolluje — za cenu karty,
    /// která v nejmenším okně zacloní obsah. Nad napsaným dotazem je situace jiná a je to ta
    /// častá: dvě skupiny PR mají po pár řádcích a vejdou se i s nadpisy.
    private static let maxListHeight = 400.0

    var body: some View {
        // **Jednou za překreslení, ne na řádek.** Hledání je průchod celým katalogem, takže
        // dotaz z každé buňky by z jednoho stisku klávesy udělal desítky průchodů.
        let sections = sections(query)
        let selected = selected(in: sections)
        return VStack(spacing: 0) {
            field { open(selected) }
            Rectangle().fill(Palette.lineSoft).frame(height: 1)
            if let notice = stage.notice {
                self.notice(notice)
            } else if sections.isEmpty {
                nothingFound
            } else {
                list(sections, selected: selected)
            }
            footer
        }
        .frame(width: Self.width)
        .background(Palette.surface, in: .rect(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(Palette.line, lineWidth: 1) }
        // `--shadow-lg` z návrhu. Karta visí nad oknem, takže bez stínu splyne s obsahem pod sebou.
        .shadow(color: .black.opacity(0.28), radius: 30, y: 12)
        .availableWidth(Self.width)
        .hiddenShortcuts { shortcuts(in: sections, selected: selected) }
        // Fokus musí skončit v poli, jinak paleta není „⌘K a piš“, ale „⌘K, klikni a piš“.
        //
        // **Až po jednom průchodu smyčky**, a ten `Task.yield()` je to jediné, co tady funguje:
        // přiřazení ve stejném průchodu, ve kterém pole vzniká, SwiftUI **zahodí**. Změřeno na
        // běžící aplikaci accessibilitou (`AXFocused`) a znaky poslanými hned po ⌘K:
        //
        // - `onAppear` i `task` bez yieldu — fokus v poli **nikdy**, ani po 300 ms;
        // - `defaultFocus($isFieldFocused, true)` — **taky nikdy**; je na počáteční fokus scény,
        //   a překryv, který se objeví v už otevřeném okně, žádná nová scéna není;
        // - s yieldem — fokus v poli pokaždé, ~40 ms po ⌘K (celý text v poli od mezery 50 ms;
        //   pod 30 ms znak předběhne vykreslení, což ale znamená psát rychleji, než se dá pustit
        //   ⌘K). Rozhoduje **počet průchodů, ne čas** — bez yieldu nepomůže žádná pauza.
        .task {
            await Task.yield()
            isFieldFocused = true
        }
        // Po změně dotazu se začíná nahoře. Kurzor uprostřed nových výsledků by znamenal, že
        // `↵` otevře něco, na co se nikdo nedíval.
        .onChange(of: query) { cursor = 0 }
        // **Změna úrovně vyprázdní pole** (#533), a je to podmínka, ne úklid: do repa se vchází
        // tím, že se napíše jeho jméno, takže by `vault` zůstalo ve filtru jeho pull requestů
        // a druhá úroveň by se otevřela jako „nic nesedí“. Platí to i na cestu zpět — `⌫` chip
        // odebere a pole má být připravené na nové hledání.
        .onChange(of: stage.level) {
            query = ""
            cursor = 0
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Paleta příkazů")
    }

    // MARK: - Pole

    private func field(submit: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13))
                .foregroundStyle(Palette.ink3)
            if let chip = stage.chip {
                repositoryChip(chip)
            }
            TextField(
                "",
                text: $query,
                prompt: Text(verbatim: stage.prompt)
                    .foregroundStyle(Palette.ink3)
            )
            .textFieldStyle(.plain)
            .font(.system(size: 14))
            .focused($isFieldFocused)
            // Fokus se hlásí do okna (#507): paleta leží **nad** detailem PR, jehož zkratky
            // v hierarchii zůstávají, takže mezerník do hledání se nesmí vzít na zastávku.
            .reportsTextFieldFocus(isFieldFocused)
            // `↵` bere pole samo, ne zkratka: `keyboardShortcut(.defaultAction)` se v okně
            // s fokusem v textovém poli o tutéž klávesu přetahuje.
            .onSubmit(submit)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    /// Chip s repem, ve kterém paleta stojí (#533) — `keboola/vault ›`.
    ///
    /// **V poli, ne v nadpisu karty** (návrh pozn. 60): je pořád vidět, kde jsem, a `⌫` na
    /// prázdném poli ho odebere, takže se chová jako token v poli, ne jako titulek obrazovky.
    ///
    /// `›` sází view, ne `Policy`: je to ukazatel „a v něm“, tedy kresba mezi chipem a textem —
    /// v `Stage` by z něj byla součást jména repa.
    private func repositoryChip(_ repo: String) -> some View {
        Text(verbatim: "\(repo) ›")
            .designPill(tint: Palette.accent, background: Palette.accentWeak)
            .lineLimit(1)
            .fixedSize()
            .accessibilityLabel("V repozitáři \(repo)")
    }

    // MARK: - Výsledky

    private func list(_ sections: [CommandPalette.Section], selected: CommandPalette.Hit?) -> some View {
        // Kurzor umí ujet mimo viditelnou část, takže se za ním scrolluje — jinak by šipka dolů
        // vypadala, že přestala fungovat.
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(sections) { section in
                        group(section, selected: selected)
                    }
                }
                .onGeometryChange(for: Double.self) { $0.size.height } action: { contentHeight = $0 }
            }
            .frame(height: min(max(contentHeight, 1), Self.maxListHeight))
            .onChange(of: selected?.id) {
                guard let id = selected?.id else { return }
                proxy.scrollTo(id)
            }
        }
    }

    @ViewBuilder private func group(
        _ section: CommandPalette.Section,
        selected: CommandPalette.Hit?
    ) -> some View {
        // **Nadpis se nezvětšuje o `detail`** (#533): dopisek za tečkou je tvrzení o tom, kde se
        // hledalo a jak je to seřazené, takže patří do téhož řádku a téhož řezu — nový prvek
        // vedle by z něj udělal druhý nadpis. `uppercased()` platí na obojí, jinak by dopisek
        // vypadal jako text obsahu.
        Text(verbatim: [section.group.title, section.detail].compactMap { $0 }
            .joined(separator: " · ")
            .uppercased())
            .font(.system(size: 9.5, design: .monospaced))
            .tracking(1)
            .foregroundStyle(Palette.ink3)
            .padding(.horizontal, 14)
            .padding(.top, 7)
            .padding(.bottom, 3)
        ForEach(section.hits) { hit in
            CommandPaletteRowView(
                hit: hit,
                isSelected: hit.id == selected?.id,
                run: { run(hit.item) }
            )
            .id(hit.id)
        }
    }

    /// Proč není nic vidět — větou, ne prázdnou kartou.
    ///
    /// Je v ní napsané i to, **kde** se hledalo: paleta nechodí na GitHub, takže „nic nesedí“
    /// neznamená, že takový pull request neexistuje. Obojí skládá `Policy`, protože to závisí na
    /// úrovni **i** na tom, jestli se vůbec na něco ptalo (#533) — repo bez otevřených PR není
    /// prázdný výsledek, ale prázdné repo.
    private var nothingFound: some View {
        let empty = Policy.paletteEmpty(at: stage.level, query: query)
        return VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: empty.headline)
                .font(.system(size: 12.5))
                .foregroundStyle(Palette.ink2)
                .fixedSize(horizontal: false, vertical: true)
            if let note = empty.note {
                Text(verbatim: note)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Palette.ink3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .filling()
    }

    /// Věta o tom, že se seznam PR repa tahá nebo že se nepovedl (#533).
    ///
    /// **Místo výsledků, ne nad nimi**: dokud odpověď nedorazila, žádné řádky nejsou — a prázdná
    /// karta bez věty by vypadala jako repo bez otevřených PR.
    ///
    /// Puntík je `ProgressView`, který je na macOS AppKitový, takže se na něj nevztahuje zákaz
    /// nekonečných animací ve SwiftUI (#350).
    @ViewBuilder private func notice(_ notice: CommandPalette.Notice) -> some View {
        HStack(spacing: 8) {
            switch notice {
            case .loading(let text):
                ProgressView()
                    .controlSize(.small)
                Text(verbatim: text)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Palette.ink2)
            case .failed(let text):
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.crit)
                Text(verbatim: text)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Palette.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .filling()
    }

    private var footer: some View {
        HStack(spacing: 14) {
            ForEach(stage.hints) { item in
                hint(item.key, item.what)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(Palette.chrome)
        .overlay(alignment: .top) { Rectangle().fill(Palette.lineSoft).frame(height: 1) }
        // Zaoblení jen dole, ať pruh nevykoukne z rohů karty.
        .clipShape(.rect(bottomLeadingRadius: 12, bottomTrailingRadius: 12))
    }

    private func hint(_ key: String, _ what: String) -> some View {
        HStack(spacing: 4) {
            Text(verbatim: key)
                .font(.system(size: 10.5, design: .monospaced))
            Text(verbatim: what)
                .font(.system(size: 10.5))
        }
        .foregroundStyle(Palette.ink3)
    }

    // MARK: - Klávesy

    /// Zkratky palety. Jak se schovávají, ví `hiddenShortcuts` — a **jsou to tlačítka, ne
    /// `onKeyPress`**: to se váže na fokus a v tomhle okně ho spolkne pole nebo seznam pod
    /// paletou (viz `HiddenShortcuts`).
    ///
    /// `⌘↵` si musí paleta vzít detailu PR, který na ní má potvrzení odeslání. Řeší to detail sám
    /// tím, že svou zkratku nad otevřenou paletou zakáže — dvě tlačítka se stejnou zkratkou by
    /// jinak znamenala, že se z palety omylem otevře potvrzení odeslání review.
    @ViewBuilder private func shortcuts(
        in sections: [CommandPalette.Section],
        selected: CommandPalette.Hit?
    ) -> some View {
        Button("Další výsledek") { move(by: 1, in: sections) }
            .keyboardShortcut(.downArrow, modifiers: [])
        Button("Předchozí výsledek") { move(by: -1, in: sections) }
            .keyboardShortcut(.upArrow, modifiers: [])
        Button("Otevřít na GitHubu") { openOnGitHub(selected) }
            .keyboardShortcut(.return, modifiers: .command)
        // `esc` **vrací o úroveň**, dokud je kam (#533) — zavírá teprve z první. Dvě tlačítka
        // se stejnou klávesou by znamenala, že vyhraje to zaregistrované později (#441), takže
        // je to jedno tlačítko a rozhoduje `Stage.goesBack`.
        if stage.goesBack {
            Button("O úroveň zpět", action: back)
                .keyboardShortcut(.cancelAction)
        } else {
            Button("Zavřít paletu", action: close)
                .keyboardShortcut(.cancelAction)
        }
        // `⌫` **jen na prázdném poli**: zkratka platí pro celé okno, takže nad napsaným dotazem
        // by přebila mazání znaků a psát by v paletě přestalo jít. Rozhoduje `Policy`, tlačítko
        // do hierarchie vůbec nevstoupí — viz `Policy.paletteBackspaceGoesBack(level:query:)`.
        if Policy.paletteBackspaceGoesBack(level: stage.level, query: query) {
            Button("O úroveň zpět", action: back)
                .keyboardShortcut(.delete, modifiers: [])
        }
    }

    /// Kurzor **cyklí**: šipka dolů na posledním řádku skočí na první. V seznamu, který se vejde
    /// na jednu obrazovku, je to rychlejší než hledat, kde přestal reagovat.
    private func move(by delta: Int, in sections: [CommandPalette.Section]) {
        let count = sections.reduce(0) { $0 + $1.hits.count }
        guard count > 0 else { return }
        cursor = (min(cursor, count - 1) + delta + count) % count
    }

    private func open(_ hit: CommandPalette.Hit?) {
        guard let hit else { return }
        run(hit.item)
    }

    /// `⌘↵` otevře věc v prohlížeči. U akcí se nestane nic — akce na GitHubu nikde není, takže
    /// `url` je `nil` a paleta zůstane otevřená; zavřít ji bez toho, aby se něco otevřelo, by
    /// vypadalo, že se něco povedlo.
    private func openOnGitHub(_ hit: CommandPalette.Hit?) {
        guard let url = hit?.item.url else { return }
        openURL(url)
        close()
    }

    /// Řádek pod kurzorem. Index se **srovnává do rozsahu**, protože výsledků může být po
    /// dopsání písmena méně než při jeho zmáčknutí.
    private func selected(in sections: [CommandPalette.Section]) -> CommandPalette.Hit? {
        let hits = sections.flatMap(\.hits)
        guard !hits.isEmpty else { return nil }
        return hits[min(cursor, hits.count - 1)]
    }
}
