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
    /// Druhý parametr je „⇧ bylo držené“ — tedy roztáhnout rozsah místo nového komentáře (#110).
    var performDraftAction: (LineDraftAction, Bool) -> Void = { _, _ in }
    /// Leží řádek uvnitř rozsahu některého mého komentáře? Bez toho by nebylo vidět, co se
    /// odešle — u víceřádkového komentáře je bublina jen u posledního řádku.
    var isInCommentRange = false
    /// Leží řádek uvnitř rozsahu, který se **právě táhne**? Svítí výrazněji než hotový komentář —
    /// při tažení je pruh to jediné, z čeho se pozná, co se vybírá.
    var isInDraggedRange = false
    /// Konec právě taženého rozsahu. `nil` = netáhne se; jinak je tlačítko vidět **jen** na tom
    /// řádku, takže jde s myší a neposkakuje mezi hoverem a koncem rozsahu.
    var dragEnd: DraftAnchor.Endpoint?
    /// Tažení přes řádky, kterým se vybírá rozsah (#110).
    var rangeDrag = RangeDragActions()
    /// Identita řádku pro měření rámečku. `nil` = řádek se tažení neúčastní.
    var dragID: String?

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
        .background(side == nil ? Self.tint(dragged: isInDraggedRange, saved: isInCommentRange) : .clear)
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
        // Rámeček řádku pro tažení (#110) — v souřadnicích **obsahu**, takže se scrollováním
        // nemění a přeměřování se nespouští. Píše se do neobservable schránky, viz `DiffRowFrames`.
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(DiffView.contentSpace)) } action: { rect in
            guard let dragID else { return }
            rangeDrag.frames?.note(rect, id: dragID, anchor: dragAnchor)
        }
        // **Táhne se přes celý řádek, ne jen přes čísla.** GitHub má gesto ve sloupci s čísly, ale
        // tady je nad diffem vypnuté vybírání textu, takže tažení přes kód nic nepřebíjí — a úzký
        // sloupec by se navíc trefoval hůř než celý řádek. `minimumDistance` je nenulová, aby
        // samotný klik zůstal kliknutím (jednořádkový komentář je od tlačítka).
        .gesture(rangeGesture)
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
        if let draftAction, showsButton {
            HStack(spacing: 0) {
                Button {
                    // Modifikátor se čte z AppKitu: SwiftUI ho akci tlačítka nepředá a jiná
                    // cesta na macOS není. Co ⇧ **znamená**, rozhoduje store (`extendDraftComment`),
                    // takže tady je jen ta jedna otázka a testuje se bez UI.
                    performDraftAction(draftAction, NSEvent.modifierFlags.contains(.shift))
                } label: {
                    Image(systemName: symbol(of: draftAction))
                        .font(.caption)
                        .foregroundStyle(.white)
                        .frame(width: 18)
                        .frame(maxHeight: .infinity)
                        .background(.tint, in: .rect(cornerRadius: 4))
                        // Pilulka sedí **na čísle řádku**, ne u hrany: zarovnaná doprava přes
                        // celý sloupec s čísly skončí přímo tam, kde je číslo, a čte se jako
                        // součást řádku. U hrany působila odděleně od diffu (nahlášené při
                        // zkoušení #110). Trefit se dá do celého sloupce — na řádku vysokém
                        // 15 pt je to rozdíl mezi „jde to“ a „myš to mine“ a číslo řádku samo
                        // na kliknutí nereaguje, takže se tím nic nepřebíjí.
                        .frame(width: gutterWidth, alignment: .trailing)
                        .contentShape(.rect)
                }
                // `.plain`, ne `.borderless`: ten se v offscreen renderu (kontrola vzhledu bez
                // screenshotu) nevykreslí a místo ikony vyjde žlutý placeholder.
                .buttonStyle(.plain)
                .help(hint(of: draftAction))
                Spacer(minLength: 0)
            }
            .padding(.leading, 8)
        }
    }

    /// Šířka sloupce s čísly: v pohledu pod sebou dvě čísla, v buňce dvojice jedno.
    private var gutterWidth: Double {
        side == nil ? Self.numberColumn * 2 : Self.numberColumn
    }

    /// Kdy je tlačítko vidět: normálně na najetí myší, **při tažení jen na konci rozsahu**.
    /// Hover během tažení zůstává na řádku, kde se stisklo, takže bez tohohle by ikona svítila
    /// na dvou místech a poskakovala.
    private var showsButton: Bool {
        if let dragEnd { dragAnchor?.end == dragEnd } else { isHovered }
    }

    /// Kotva tohohle řádku pro tažení. `nil` = řádek komentář neunese (meta, mimo hunky), takže
    /// se rozsah nemá o co opřít — tažení ho přeskočí a drží poslední platný konec.
    private var dragAnchor: DraftAnchor? {
        guard case .comment(let anchor) = draftAction else { return nil }
        return anchor
    }

    private var rangeGesture: some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named(DiffView.contentSpace))
            .onChanged { value in
                guard let anchor = dragAnchor else { return }
                // Řádek pod myší se dohledá ze souřadnic: gesto patří tomu řádku, ve kterém
                // tažení začalo, takže o ostatních jinak neví. Když bod na žádný komentovatelný
                // řádek nepadne (mezi soubory, na hlavičku hunku), zůstane rozsah, kde byl.
                // Hledá se **jen ve svém sloupci** (ve split pohledu): tažení, které začalo
                // vpravo, nemá skočit vlevo, když myš zajede vedle nebo když levá protistrana
                // chybí. V pohledu pod sebou je `side` nil a hledá se všude.
                //
                // Když pod myší řádek není, posílá se `nil` — **ne začátek**. Dosazený začátek
                // rozsah srazil na jeden řádek pokaždé, když myš přejela prázdnou protistranu.
                rangeDrag.move(anchor, rangeDrag.frames?.anchor(at: value.location, on: side))
            }
            .onEnded { _ in rangeDrag.end() }
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
        // ⇧ je v nápovědě, protože jinak se o roztažení rozsahu nikdo nedozví — v okně na něj
        // není žádné tlačítko a být nemá (tažení přes čísla řádků se u #110 zamítlo).
        case .comment: "Přidat komentář k tomuhle řádku. ⇧ klik roztáhne rozsah od naposledy přidaného komentáře."
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

    /// Pruh přes celý řádek u komentovaného rozsahu (#110) — jinak by u víceřádkového komentáře
    /// nebylo poznat, kam až sahá. Kreslí se **přes** pozadí druhu řádku, aby zůstalo vidět, co
    /// je přidané a co odebrané; ve split pohledu ho stejně jako to pozadí kreslí dvojice.
    static let rangeTint = Color.accentColor.opacity(0.12)

    /// Právě tažený rozsah svítí **výrazněji** než hotový komentář: u hotového je vidět i bublina,
    /// kdežto při tažení je pruh jediná zpětná vazba o tom, co se vybírá.
    ///
    /// Ne o mnoho výrazněji: při 0,3 pruh přebil zelenou a červenou u změněných řádků, tedy to
    /// hlavní, co má diff říkat. Vyladěné na offscreen renderu.
    static let dragTint = Color.accentColor.opacity(0.16)

    /// Barva pruhu rozsahu, nebo průhledno. Tažení přebíjí hotový komentář — je to to, co se
    /// zrovna děje.
    static func tint(dragged: Bool, saved: Bool) -> Color {
        if dragged { dragTint } else if saved { rangeTint } else { .clear }
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
