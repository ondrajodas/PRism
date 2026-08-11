import SwiftUI

/// Command palette ⌘K (#184) — jedno pole nad nálezy, soubory otevřeného PR, pull requesty
/// a akcemi.
///
/// **Nerozhoduje nic o výsledcích**: co na dotaz sedne, v jakém pořadí to je a kolik se toho
/// ukáže, spočítá `Policy.paletteResults` nad katalogem z `AppStore.paletteItems`. Tady zůstává
/// pole, kurzor a klávesy.
///
/// **Dotaz i kurzor jsou `@State`, ne stav ve storu**, a je to schválně: mají zaniknout se
/// zavřením palety. Text z minula by po ⌘K vypadal jako výsledky k něčemu, na co se nikdo
/// neptal — a `CommandPaletteView` vzniká až s otevřenou paletou, takže se pokaždé začíná
/// naprázdno.
struct CommandPaletteView: View {
    /// Co je k prohledání. Skládá se z paměti store, žádný dotaz na GitHub.
    let items: [CommandPalette.Item]
    /// Vykonání řádku. Paletu zavírá **volající** — ví, jestli po vykonání zůstává okno na místě.
    let run: (CommandPalette.Item) -> Void
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
    /// Strop seznamu. Nad ním se scrolluje; čtyři skupiny po šesti řádcích se do okna nevejdou
    /// a paleta nemá zaclonit celé okno.
    private static let maxListHeight = 400.0

    var body: some View {
        // **Jednou za překreslení, ne na řádek.** Hledání je průchod celým katalogem, takže
        // dotaz z každé buňky by z jednoho stisku klávesy udělal desítky průchodů.
        let sections = Policy.paletteResults(of: items, query: query)
        let selected = selected(in: sections)
        return VStack(spacing: 0) {
            field { open(selected) }
            Rectangle().fill(Palette.lineSoft).frame(height: 1)
            if sections.isEmpty {
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
        // Fokus musí skončit v poli: paleta bez blikajícího kurzoru vypadá jako obrázek.
        .onAppear { isFieldFocused = true }
        // Po změně dotazu se začíná nahoře. Kurzor uprostřed nových výsledků by znamenal, že
        // `↵` otevře něco, na co se nikdo nedíval.
        .onChange(of: query) { cursor = 0 }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Paleta příkazů")
    }

    // MARK: - Pole

    private func field(submit: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13))
                .foregroundStyle(Palette.ink3)
            TextField(
                "",
                text: $query,
                prompt: Text("Najít nález, soubor, pull request nebo akci")
                    .foregroundStyle(Palette.ink3)
            )
            .textFieldStyle(.plain)
            .font(.system(size: 14))
            .focused($isFieldFocused)
            // `↵` bere pole samo, ne zkratka: `keyboardShortcut(.defaultAction)` se v okně
            // s fokusem v textovém poli o tutéž klávesu přetahuje.
            .onSubmit(submit)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
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
        Text(verbatim: section.group.title.uppercased())
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
    /// neznamená, že takový pull request neexistuje.
    private var nothingFound: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: "Na „\(query)“ nic nesedí.")
                .font(.system(size: 12.5))
                .foregroundStyle(Palette.ink2)
            Text("Hledá se v nálezech, souborech otevřeného PR, pull requestech a akcích — jen v tom, co je načtené.")
                .font(.system(size: 11.5))
                .foregroundStyle(Palette.ink3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .filling()
    }

    private var footer: some View {
        HStack(spacing: 14) {
            hint("↑↓", "pohyb")
            hint("↵", "otevřít")
            hint("⌘↵", "otevřít na GitHubu")
            hint("esc", "zavřít")
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
        Button("Zavřít paletu", action: close)
            .keyboardShortcut(.cancelAction)
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
