import SwiftUI

/// Jeden řádek diffu: dvě čísla, znak změny a obsah. V pohledu vedle sebe jedna buňka
/// dvojice — pak jen jedno číslo, viz `side`.
struct DiffLineView: View {
    let line: DiffLine
    /// Která čísla se ukazují a kdo kreslí pozadí.
    ///
    /// `nil` = pohled pod sebou: obě čísla vedle sebe a řádek si kreslí pozadí sám.
    ///
    /// `.left` / `.right` = jedna buňka pohledu vedle sebe: jedno číslo (staré vlevo, nové
    /// vpravo) a pozadí kreslí `DiffPairView`. Buňka si ho kreslit nemůže — prázdná
    /// protistrana i ta kratší musí být vysoká jako celý řádek, a to buňka o sobě neví.
    var side: DiffSide?
    /// Jazyk souboru kvůli obarvení. `nil` = jednobarevný řádek.
    var language: Language?
    /// Co jde s řádkem udělat v rozdělaném review. `nil` = nic, tlačítko se nekreslí.
    var draftAction: LineDraftAction?
    var performDraftAction: (LineDraftAction) -> Void = { _ in }

    @Environment(\.colorScheme) private var colorScheme
    /// Tlačítko se ukazuje až na najetí, jako na GitHubu. Trvalé tlačítko u každého řádku
    /// diffu je pruh ikon, ve kterém se ztratí kód.
    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // V buňce dvojice je číslo jedno: vlevo staré, vpravo nové. Bez `side` obojí.
            if side != .right { number(line.oldNumber) }
            if side != .left { number(line.newNumber) }
            Text(verbatim: sign)
                .foregroundStyle(signColor)
                .frame(width: 14, alignment: .leading)
            Text(content)
                .frame(maxWidth: .infinity, alignment: .leading)
                // Dlouhý řádek se zalomí; bez tohohle by se v líném seznamu ořízl.
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(.callout, design: .monospaced))
        .foregroundStyle(line.kind == .meta ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.primary))
        .padding(.horizontal, 8)
        .background(background)
        // **Na myš reaguje celý obdélník řádku, ne jen plocha textů.** Bez tohohle drží hover
        // jen nad číslicemi a nad glyfy kódu — kontextový řádek má průhledné pozadí a `Text`
        // uvnitř pružného rámce si hit-test nese jen na svou velikost, takže mezera za koncem
        // řádku a odsazení kódu nereagují. Projevilo se to jako „ikonka se ukáže jen nad
        // čísly“: myš vyjela z citlivé plochy dřív, než k tlačítku došla. Na rozvržení
        // `contentShape` nesahá, takže s pružnou výškou (a zaseknutím u ní) nemá nic společného.
        .contentShape(.rect)
        // Přes čísla řádků, ne vedle nich: vlastní sloupec by odsunul obsah o svou šířku
        // u **každého** řádku, i tam, kde se komentovat nedá.
        .overlay { draftButton }
        .onHover { isHovered = $0 }
    }

    /// Tlačítko na komentář, které se ukazuje po najetí myší.
    ///
    /// **Výšku si bere z řádku, ne z konstanty** (`maxHeight: .infinity` uvnitř overlay, kterému
    /// se navrhuje velikost řádku, takže je to ohraničené). Do #98 tu byla pevná `height: 18`,
    /// jenže řádek diffu je vysoký ~15 pt — tlačítko z něj **vyčnívalo do toho následujícího**,
    /// takže jak na něj myš zamířila, hover přešel na další řádek a ikonka zmizela. Komentovat
    /// pak nešlo vůbec a vypadalo to jako záhada; nahlášené při zkoušení #98, ale je to od #66.
    /// Konstanta by tu byla druhé místo, které se s výškou řádku může rozejít.
    @ViewBuilder private var draftButton: some View {
        if let draftAction, isHovered {
            HStack(spacing: 0) {
                Button {
                    performDraftAction(draftAction)
                } label: {
                    Image(systemName: symbol(of: draftAction))
                        .font(.caption)
                        .foregroundStyle(.white)
                        .frame(width: 18)
                        .frame(maxHeight: .infinity)
                        .background(.tint, in: .rect(cornerRadius: 4))
                        // Vidět je pilulka o 18 pt, trefit se dá do celého sloupce s číslem.
                        // Na řádku vysokém 15 pt je to rozdíl mezi „jde to“ a „myš to mine“;
                        // číslo řádku samo o sobě na kliknutí nereaguje, takže se tím nic
                        // nepřebíjí.
                        .frame(width: Self.numberColumn, alignment: .leading)
                        .contentShape(.rect)
                }
                // `.plain`, ne `.borderless`: ten se v offscreen renderu (kontrola vzhledu bez
                // screenshotu) nevykreslí a místo ikony vyjde žlutý placeholder.
                .buttonStyle(.plain)
                .help(hint(of: draftAction))
                Spacer(minLength: 0)
            }
            .padding(.leading, 4)
        }
    }

    private func symbol(of action: LineDraftAction) -> String {
        switch action {
        case .comment: "plus.bubble.fill"
        case .note: "text.badge.plus"
        }
    }

    /// U poznámky musí být z nápovědy poznat **proč** to nejde jako komentář — jinak to
    /// vypadá jako jiné tlačítko na totéž.
    private func hint(of action: LineDraftAction) -> String {
        switch action {
        case .comment: "Přidat komentář k tomuhle řádku"
        case .note: "Řádek není v diffu, takže GitHub komentář k němu nepřijme. Přidá se do těla review jako odkaz na kód."
        }
    }

    /// Obsah řádku obarvený podle jazyka.
    ///
    /// Prázdný řádek se nahrazuje mezerou: prázdný `Text` má nulovou výšku, takže by
    /// z diffu zmizel a přestala by u něj sedět čísla vedle.
    ///
    /// Obarvení se počítá **při vykreslení řádku**, ne dopředu pro celý soubor. Seznam je
    /// líný, takže se to spočítá jen pro to, na co je vidět; nad jedním řádkem je to práce
    /// v řádu mikrosekund.
    private var content: AttributedString {
        guard !line.text.isEmpty else { return AttributedString(" ") }
        guard let language, line.kind != .meta else { return AttributedString(line.text) }

        let palette = SyntaxPalette.forScheme(colorScheme)
        var result = AttributedString()
        for run in SyntaxHighlighter.runs(of: line.text, in: language) {
            var piece = AttributedString(run.text)
            // `nil` u obyčejného textu schválně: řádek si tak nechá barvu, kterou mu dal
            // okolní styl (třeba ztlumenou u poznámky).
            piece.foregroundColor = palette.color(for: run.kind)
            result += piece
        }
        return result
    }

    /// Čísla řádků se píšou `verbatim` — `Text("\(number)")` jde přes locale a z řádku
    /// 21663 udělá „21 663“. Číslo řádku není množství.
    private func number(_ value: Int?) -> some View {
        Text(verbatim: value.map(String.init) ?? "")
            .font(.system(.caption, design: .monospaced))
            .monospacedDigit()
            .foregroundStyle(.tertiary)
            .frame(width: 44, alignment: .trailing)
            .padding(.trailing, 8)
    }

    /// Šířka sloupce s číslem řádku. Bere ji i cíl tlačítka na komentář a `DiffRowView` na
    /// odsazení bublin ve split pohledu — jedna hodnota místo tří, které se rozejdou.
    static let numberColumn = 52.0

    private var sign: String {
        switch line.kind {
        case .added: "+"
        case .removed: "-"
        case .context: " "
        case .meta: "\\"
        }
    }

    private var signColor: Color {
        switch line.kind {
        case .added: .green
        case .removed: .red
        case .context, .meta: .secondary
        }
    }

    /// V pohledu vedle sebe kreslí pozadí `DiffPairView` za celou dvojici, ne buňka — viz
    /// `side`. Tady tedy zbývá průhledno, aby se barvy nesčítaly.
    private var background: Color {
        side == nil ? Self.background(of: line.kind) : .clear
    }

    /// Barva pozadí podle druhu řádku.
    ///
    /// Statická schválně: tutéž barvu si bere `DiffPairView`, který ve split pohledu kreslí
    /// pozadí za dvojici. Dvě palety by se rozešly a přidaný řádek by v jednom pohledu
    /// vypadal jinak než v druhém.
    static func background(of kind: DiffLine.Kind) -> Color {
        switch kind {
        case .added: .green.opacity(0.12)
        case .removed: .red.opacity(0.12)
        case .context, .meta: .clear
        }
    }
}
