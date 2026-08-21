import AppKit
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
            // Prázdné místo pro pilulku s ikonkou — ta visí v overlay, takže sama šířku nezabere.
            // **Vlevo od čísel** (vyžádané při zkoušení #157): mezi čísly a kódem působila jako
            // součást kódu a odsouvala ho od čísel.
            Color.clear.frame(width: Self.iconColumn)
            numbers
            Text(verbatim: sign)
                .foregroundStyle(signColor)
                .frame(width: 14, alignment: .leading)
            Text(content)
                .frame(maxWidth: .infinity, alignment: .leading)
                // Dlouhý řádek se zalomí; bez tohohle by se v líném seznamu ořízl.
                .fixedSize(horizontal: false, vertical: true)
                // **Vybírat text jde jen tady, v obsahu řádku** (#157) — ne nad čísly a ne nad
                // znakem změny. Do schránky má jít kód, ne diff, takže co se nedá vybrat, se
                // nemůže do vybraného textu ani připlést.
                .textSelection(.enabled)
        }
        .font(.system(.callout, design: .monospaced))
        .foregroundStyle(line.kind == .meta ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.primary))
        .padding(.horizontal, 8)
        .background { background }
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
        .onGeometryChange(for: CGRect.self) {
            RenderDiagnostics.inGraph(.lineGeometry)
            return $0.frame(in: .named(DiffView.contentSpace))
        } action: { rect in
            guard let dragID else { return }
            // Jeden řádek je z pohledu krabice blok o jednom řádku; řádek, na který se komentovat
            // nedá, se nehlásí a tím z krabice vypadne (#252).
            let rows = dragAnchor.map { [DiffRowFrames.Entry(id: dragID, rect: rect, anchor: $0)] } ?? []
            if let box = rangeDrag.box { box.frames.note(rows, covering: rect, of: box.subject) }
        }
        // **Tažení rozsahu visí na celém řádku, ne na sloupci s čísly** — a je to návrat k #110,
        // ke kterému mě dohnalo zkoušení #157. Přesun do sloupce vypadal správně (GitHub to tak
        // má, a hlavně: nad kódem se od #157 vybírá text), ale **přestalo se u toho zvýrazňovat**
        // to, co se právě táhne, takže při tažení nebylo vidět, co je vybrané. Zvýraznění jde
        // přes store a překreslení celého diffu; s gestem na řádku funguje, s gestem uvnitř
        // overlay ne.
        //
        // Nad kódem si tedy gesto a selekce **konkurují o totéž tažení** — a rozhoduje to, že
        // `Text` se svým vybíráním je potomek, takže hit-test dostane první. Nad čísly, znakem
        // změny a pilulkou žádný vybíratelný text není, takže tam zbude tažení rozsahu.
        .gesture(rangeGesture)
    }

    /// Sloupec (nebo dva) s čísly řádků. Tažení rozsahu se odsud **neobsluhuje** — leží nad tím
    /// `draftButton`, který zabírá celý sloupec (viz níž).
    private var numbers: some View {
        HStack(alignment: .top, spacing: 0) {
            // V buňce dvojice je číslo jedno: vlevo staré, vpravo nové. Bez `side` obojí.
            if side != .right { number(line.oldNumber) }
            if side != .left { number(line.newNumber) }
        }
    }

    /// Sloupec s čísly jako **plocha na tažení rozsahu**, a v něm tlačítko na komentář.
    ///
    /// **Výšku si bere z řádku, ne z konstanty** (`maxHeight: .infinity` uvnitř overlay, kterému
    /// se navrhuje velikost řádku, takže je to ohraničené). Do #98 tu byla pevná `height: 18`,
    /// jenže řádek diffu je vysoký ~15 pt — tlačítko z něj **vyčnívalo do toho následujícího**,
    /// takže jak na něj myš zamířila, hover přešel na další řádek a ikonka zmizela. Komentovat
    /// pak nešlo vůbec a vypadalo to jako záhada; nahlášené při zkoušení #98, ale je to od #66.
    /// Konstanta by tu byla druhé místo, které se s výškou řádku může rozejít.
    ///
    /// Tažení rozsahu obsluhuje **celý řádek** (viz `body`), ne tenhle pruh — zvýraznění taženého
    /// rozsahu jinak nefunguje.
    private var draftButton: some View {
        HStack(spacing: 0) {
            dragStrip
            Spacer(minLength: 0)
        }
        .padding(.leading, 8)
    }

    /// Sloupec s čísly a v něm zprava pilulka s ikonkou.
    ///
    /// Pozn. k `contentShape`: musí být **za** `frame`, ne před ním — před ním tvaruje `Color.clear`
    /// v jeho vlastní, tedy nulové velikosti. Stálo to jedno kolo u #157, kdy na tomhle pruhu
    /// viselo tažení rozsahu a nefungovalo.
    private var dragStrip: some View {
        ZStack(alignment: .leading) {
            Color.clear
            icon
        }
        .frame(width: gutterWidth + Self.iconColumn)
        .frame(maxHeight: .infinity)
        .contentShape(.rect)
    }

    /// Samotná pilulka s ikonkou. Ukazuje se po najetí myší.
    ///
    /// **Výšku si bere z řádku, ne z konstanty** (`maxHeight: .infinity` uvnitř overlay, kterému
    /// se navrhuje velikost řádku, takže je to ohraničené). Do #98 tu byla pevná `height: 18`,
    /// jenže řádek diffu je vysoký ~15 pt — tlačítko z něj **vyčnívalo do toho následujícího**,
    /// takže jak na něj myš zamířila, hover přešel na další řádek a ikonka zmizela. Komentovat
    /// pak nešlo vůbec a vypadalo to jako záhada; nahlášené při zkoušení #98, ale je to od #66.
    /// Konstanta by tu byla druhé místo, které se s výškou řádku může rozejít.
    @ViewBuilder private var icon: some View {
        if let draftAction, showsButton {
            Image(systemName: symbol(of: draftAction))
                .font(.caption)
                .foregroundStyle(.white)
                // **Pilulka má vlastní úzký sloupec, vlevo od čísel řádků.**
                //
                // Třetí umístění a obě předchozí měla svůj důvod: do #110 stála u pravé hrany
                // sloupce a působila odděleně od diffu, od #110 sedla **na číslo řádku** a zpola ho
                // překryla (vyšlo najevo až u #157, kdy se zapnulo vybírání textu — doloženo
                // offscreen renderem, že to tak bylo už předtím). Vlastní sloupec vlevo nepřekrývá
                // nic; napravo od čísel působil jako součást kódu a odsouval ho. Vyžádané při
                // zkoušení #157.
                //
                // Cena je 18 pt odsazení obsahu u **každého** řádku, i tam, kde se komentovat nedá
                // — přesně to, co #110 zamítlo. Zaplaceno vědomě: procento šířky okna proti
                // nečitelnému číslu řádku pod myší.
                //
                // Výšku si bere z řádku, ne z konstanty. Do #98 tu byla pevná `height: 18`, jenže
                // řádek diffu je vysoký ~15 pt — pilulka z něj vyčnívala do toho následujícího,
                // takže jak na ni myš zamířila, hover přešel na další řádek a ikonka zmizela.
                .frame(width: 18)
                .frame(maxHeight: .infinity)
                .background(.tint, in: .rect(cornerRadius: 4))
                .contentShape(.rect)
                // **`onTapGesture`, ne `Button`** (#157). `Button` si tažení vezme pro sebe, takže
                // z pilulky nešlo roztáhnout rozsah — a začít tažení nad ikonkou je to nejbližší,
                // co má člověk pod rukou, když už jednou míří na komentář. Klepnutí a tažení se
                // takhle vylučují samy: `DragGesture` má `minimumDistance`, takže klik zůstane
                // klikem. Modifikátor se čte z AppKitu — SwiftUI ho akci nepředá a jiná cesta na
                // macOS není; co ⇧ **znamená**, rozhoduje store (`extendDraftComment`).
                .onTapGesture {
                    performDraftAction(draftAction, NSEvent.modifierFlags.contains(.shift))
                }
                // Kurzor jako nad tlačítkem — bez `Button`u ho SwiftUI sám nenastaví.
                .onHover { NSCursor.pointingHand.set(); if !$0 { NSCursor.arrow.set() } }
                .help(hint(of: draftAction))
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel(hint(of: draftAction))
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
                rangeDrag.move(anchor, rangeDrag.box?.frames.anchor(at: value.location, on: side))
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
    /// líný, takže se to spočítá jen pro to, na co je vidět.
    ///
    /// Tohle je computed property, takže se to volá při **každém** překreslení — i když se hnulo
    /// jen myší. Průchod řádkem se proto od #224 pamatuje (`SyntaxRunCache`) a zbývá tu složení
    /// `AttributedString`u, které se cachovat nedá: barva v něm už je, a ta se s režimem mění.
    private var content: AttributedString {
        guard !line.text.isEmpty else { return AttributedString(" ") }
        guard let language, line.kind != .meta else { return AttributedString(line.text) }

        let palette = SyntaxPalette.forScheme(colorScheme)
        var result = AttributedString()
        for run in SyntaxHighlighter.runs(of: line.text, in: language) {
            var piece = AttributedString(run.text)
            // `nil` u obyčejného textu schválně: řádek si tak nechá barvu, kterou mu dal
            // okolní styl (třeba ztlumenou u poznámky). **Platí to jedině ve SwiftUI** —
            // v atributovaném řetězci je chybějící barva černá, takže blok kódu si ji nasazuje
            // sám (`SyntaxColors.plain`, #393).
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

    /// Šířka sloupce, ve kterém bydlí pilulka s ikonkou na komentář (#157). Ze stejného důvodu
    /// jako `numberColumn` je to jedna hodnota: odsazení bublin se od šířky sloupců **nesmí
    /// rozejít**, jinak bubliny přestanou začínat tam, kde začíná kód.
    static let iconColumn = 18.0

    /// Šířka sloupce se znakem změny (`+`/`−`).
    static let signColumn = 14.0

    /// Odsazení obsahu řádku od levé hrany: sloupec ikonky, čísla řádků a znak změny.
    ///
    /// **Musí sedět s tím, jak si gutter dělí `DiffTextView`** — čísla i znak se v bloku kreslí
    /// ručně na dané `x`, takže rozejít se to smí jen tehdy, když má být kód nakřivo. Jeden součet
    /// na jednom místě je jediná pojistka; když v něm chyběl `signColumn`, kreslil se znak přes
    /// číslo řádku a čísla vycházela uříznutá (nahlášené při zkoušení #157).
    static func contentInset(for layout: DiffLayout) -> Double {
        iconColumn + numbers(for: layout) + signColumn
    }

    /// Šířka sloupců s čísly — v pohledu vedle sebe jedno číslo, pod sebou dvě.
    static func numbers(for layout: DiffLayout) -> Double {
        layout == .split ? numberColumn : numberColumn * 2
    }

    private var sign: String {
        switch line.kind {
        case .added: "+"
        case .removed: "-"
        case .context: " "
        case .meta: "\\"
        }
    }

    private var signColor: Color {
        Self.signColor(of: line.kind)
    }

    /// Barva znaku změny na začátku řádku.
    ///
    /// Statická ze stejného důvodu jako `background(of:)`: bere si ji i souhrn nad diffem
    /// a hlavička souboru na počty `+X −Y` (#156). Dvě sady barev by se rozešly a `+` v řádku
    /// by bylo jinak zelené než `+12` v hlavičce nad ním.
    ///
    /// **Ne `background(of:)`** — to je plocha řádku, tedy barva, která je jako písmo nečitelná.
    /// Sytá barva znaku je to, co v diffu už dneska stojí jako text.
    ///
    /// **Od #277 z `Palette`, ne systémová `.green`/`.red`.** Byl to poslední kus diffu, který si
    /// barvu bral ze systému, a u znaku to bylo měřitelně špatně: systémová zelená měla ve světlém
    /// režimu na pozadí přidaného řádku kontrast **2,01** a v hlavičce nad diffem **2,22**, tedy
    /// znak `+` k přečtení jen podle polohy. S `Palette.ok` je to **4,65** a **5,08**; v tmavém
    /// režimu 7,42 → 5,95, tedy pořád s rezervou. Podrobnosti u `Palette.ok`.
    static func signColor(of kind: DiffLine.Kind) -> Color {
        switch kind {
        case .added: Palette.ok
        case .removed: Palette.crit
        case .context, .meta: .secondary
        }
    }

    /// V pohledu vedle sebe kreslí pozadí `DiffPairView` za celou dvojici, ne buňka — viz
    /// `side`. Tady tedy nezbývá nic, aby se barvy nesčítaly.
    ///
    /// **Pruh rozsahu leží nad barvou druhu řádku, ne pod ní** (#277). Do té doby to bylo obráceně
    /// (`.background(background).background(tint)` staví pruh **pod** pozadí) a fungovalo to jen
    /// proto, že pozadí bylo z dvanácti procent průhledné — pruh jím prosvítal. S vyčíslenou
    /// barvou by pod ní zmizel, a s ním jediná zpětná vazba o tom, co se zrovna vybírá. Blok kódu
    /// (`DiffTextView.drawRows`) kreslil v tomhle pořadí odjakživa, takže se tím obě cesty
    /// srovnaly na jedno.
    @ViewBuilder private var background: some View {
        if side == nil {
            Self.background(of: line.kind)
                .overlay(Self.tint(dragged: isInDraggedRange, saved: isInCommentRange))
        }
    }

    /// Pruh přes celý řádek u komentovaného rozsahu (#110) — jinak by u víceřádkového komentáře
    /// nebylo poznat, kam až sahá. Kreslí se **přes** pozadí druhu řádku, aby zůstalo vidět, co
    /// je přidané a co odebrané; ve split pohledu ho stejně jako to pozadí kreslí dvojice.
    ///
    /// **Akcent z palety, ne `Color.accentColor`** (#309): systémová modrá byla i tady, jen ji
    /// dvanáct procent krytí schovalo natolik, že to nebylo vidět na první pohled — a nad zeleným
    /// řádkem se modrá míchá do jiného tónu než fialová. Krytí zůstává **záměrně**: pruh má být
    /// vrstva nad barvou řádku, ne místo ní, takže je to jediné místo v paletě, kde je
    /// prosvítající podklad ta žádaná vlastnost. Že se dynamická barva krytím nerozbije (a tmavá
    /// větev zůstane tmavá i po převodu na `NSColor` v `DiffTextView`), hlídá `MintTokenTests`.
    static let rangeTint = Palette.accent.opacity(0.12)

    /// Právě tažený rozsah svítí **výrazněji** než hotový komentář: u hotového je vidět i bublina,
    /// kdežto při tažení je pruh jediná zpětná vazba o tom, co se vybírá.
    ///
    /// Ne o mnoho výrazněji: při 0,3 pruh přebil zelenou a červenou u změněných řádků, tedy to
    /// hlavní, co má diff říkat. Vyladěné na offscreen renderu — a **procenta se u #309 nehnula**,
    /// změnila se jen barva pod nimi.
    static let dragTint = Palette.accent.opacity(0.16)

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
    ///
    /// **Z `Palette`, ne krytí nad podkladem** (#277) — proč a s jakými čísly, je u
    /// `Palette.diffAdded`.
    static func background(of kind: DiffLine.Kind) -> Color {
        switch kind {
        case .added: Palette.diffAdded
        case .removed: Palette.diffRemoved
        case .context, .meta: .clear
        }
    }

    /// Pozadí **změněného kusu** přepsaného řádku (#153) — word-level zvýraznění.
    ///
    /// Tatáž barva jako u řádku, jen sytější: kus, který se přepsal, se má lišit od zbytku
    /// **svého** řádku, ne od okolí. Kreslí se jako druhá vrstva nad pozadím řádku.
    ///
    /// **Od #277 je to vyčíslená barva, ne krytí 50 %** — a hodnota se přitom změnila, protože
    /// padesát procent nad novým pozadím řádku sebralo pod sebou obarvení syntaxe. Čísla obou
    /// stavů i to, co se za to vyměnilo, jsou u `Palette.diffAddedWord`. **Rozhodnutí z #153
    /// zůstává v platnosti** v tom, na čem stálo: vrstva musí být na první pohled jiná plocha než
    /// zbytek řádku (ΔE 16 z 10 potřebných), protože zvýraznění se hledá **v celém diffu**, ne
    /// v jednom bloku vedle sebe.
    ///
    /// `nil` u kontextu a poznámky: co se nezměnilo, nemá co zvýrazňovat.
    static func wordBackground(of kind: DiffLine.Kind) -> Color? {
        switch kind {
        case .added: Palette.diffAddedWord
        case .removed: Palette.diffRemovedWord
        case .context, .meta: nil
        }
    }
}
