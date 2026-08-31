import SwiftUI

/// Našeptávání emotikonů nad textovým polem (#483) — **klávesy a kotvení, nic víc**.
///
/// Rozhodování je v `Policy` (`emojiQuery`, `emojiSuggestions`, `emojiInsertion`), kresba
/// v `EmojiSuggestionMenu`; tady zůstává jen to, co jde jedině ve view: kurzor z pole, obsluha
/// kláves a místo, kam se nabídka položí.
///
/// **Klávesy si bere pole, ne okno.** `↑↓`, `↵` a `esc` jdou přes `onKeyPress` — touž cestou, jakou
/// si `⌥↵` bere pole u zakládání labelu (#413). S okenními zkratkami si proto nekonkurují
/// a `Policy.windowShortcut` se nemění.
///
/// - `↵` bere nabídka **holý**, protože právě ten by v poli zalomil řádek. Se `⌘` (a s čímkoli
///   jiným) se klávesa **propustí**, takže `⌘⏎` zůstává oknu (`Otevřít potvrzení odeslání`).
/// - `esc` je **ustupující**: `.handled` jedině s otevřenou nabídkou, jinak `.ignored` — a teprve
///   pak se k němu dostane okno (`Zpět na seznam commitů`). Tatáž úmluva jako u zásuvky
///   s terminálem (#459).
/// - `esc` nabídku zavře **jen do dalšího úhozu**: dotaz se počítá z textu a kurzoru, takže po
///   dopsání dalšího písmene je to jiný dotaz a nabídka se otevře znovu. Držet „zavřeno“ napříč
///   psaním by znamenalo druhý stav, který v okně není vidět.
///
/// **Nabídka se kotví nad polem, ne u kurzoru.** Kurzorový obdélník se ve SwiftUI bez sestupu do
/// AppKitu nezjistí a v panelu širokém 300 bodů by 300bodová nabídka stejně neměla kam ustoupit do
/// stran. `overlay` navíc nezabírá místo, takže se pole pod nabídkou **nehýbe** — a to je u pole,
/// do kterého se zrovna píše, podstatnější než pár bodů polohy.
///
/// **Kreslí ji ale volající, ne tenhle modifikátor**, a proč, je u `EmojiSuggestionBox`: `overlay`
/// ořízne každý předek, který ořezává, a dvě ze tří polí v takovém předkovi sedí.
///
/// **Řádky se pamatují, nepočítají se z těla** (#224): jeden dotaz je průchod katalogem o 1870
/// znacích, kdežto tělo view se vyhodnocuje i tehdy, když se dotaz nezměnil. Cache vyprazdňuje
/// `refresh()` a klíč je **text dotazu** — nic jiného výsledek neovlivňuje.
struct EmojiSuggesting: ViewModifier {
    @Binding var text: String
    @Binding var selection: TextSelection?
    /// Kam se otevřená nabídka zapisuje. Kreslí ji z něj volající.
    let suggestions: EmojiSuggestionBox

    /// Otevřený dotaz — **polohy v textu**, podle kterých se vkládá. `nil` = nabídka se nekreslí.
    ///
    /// Zůstává tady, ne v boxu: je to věc pole (funkce textu a kurzoru), kdežto box je to, co se
    /// kreslí. Kdo kreslí, nemá co vědět o rozsazích v cizím textu.
    @State private var query: Policy.EmojiQuery?

    /// Mezera mezi nabídkou a horní hranou pole, jak ji kreslí návrh (`gap: 8px`).
    static let gap = 8.0

    func body(content: Content) -> some View {
        content
            // **Dva zdroje, jeden výpočet.** Dotaz je funkcí textu **a** kurzoru, takže se musí
            // přepočítat po obojím: dopsané písmeno mění text, klik do věty jen kurzor.
            .onChange(of: text) { refresh() }
            .onChange(of: selection) { refresh() }
            .onKeyPress(.upArrow) { move(-1) }
            .onKeyPress(.downArrow) { move(1) }
            // **Jeden handler na `↵` i `⌘↵`, ne dva** (precedens #413): `onKeyPress(_:modifiers:)`
            // bere `modifiers` jako množinu, ve které stisk **smí** ležet, ne jako množinu, která
            // musí sednout přesně — takže dva zápisy by se přebíjely. Tvar `keys:` dává celý
            // `KeyPress`, takže se modifikátor přečte a rozhodne se z něj **tady**, viditelně.
            .onKeyPress(keys: [.return]) { insert($0) }
            .onKeyPress(.escape) { dismiss() }
    }

    // MARK: - Stav dotazu

    private func refresh() {
        guard let caret = caretOffset(), let found = Policy.emojiQuery(in: text, caret: caret) else {
            close()
            return
        }
        let previous = query?.text
        // Polohy se přepisují vždycky — vkládá se podle nich, takže zastaralý rozsah je to jediné,
        // čím se dá text rozsekat.
        query = found
        guard found.text != previous else { return }
        suggestions.rows = Policy.emojiSuggestions(for: found.text)
        suggestions.highlighted = 0
    }

    private func close() {
        query = nil
        suggestions.close()
    }

    /// Kurzor jako **počet znaků od začátku textu**. `nil` = kurzor není, je z něj vybraný úsek,
    /// nebo neukazuje do tohohle textu.
    ///
    /// **Počítá se průchodem, ne `distance(from:to:)`, a je to podmínka.** Pole mění text a kurzor
    /// ve dvou různých zápisech, takže se sem `String.Index` z **předchozí** verze textu dostat umí
    /// — a `distance(from:to:)` na něm proces **položí**. Průchod od začátku porovnává jen index
    /// s indexem, což je bezpečné, a když se cesta s cílem nepotká přesně, vrátí `nil`.
    private func caretOffset() -> Int? {
        guard case .selection(let range)? = selection?.indices else { return nil }
        // Vybraný úsek není kurzor: není z něj poznat, kde by dotaz končil.
        guard range.isEmpty else { return nil }

        var offset = 0
        var cursor = text.startIndex
        while cursor < range.lowerBound {
            guard cursor < text.endIndex else { return nil }
            cursor = text.index(after: cursor)
            offset += 1
        }
        return cursor == range.lowerBound ? offset : nil
    }

    // MARK: - Klávesy

    /// Šipky. Bez nabídky se **propustí** — spolknout klávesu, po které se nic nestane, je
    /// k nerozeznání od zaseknutého pole.
    ///
    /// `.handled` je u otevřené nabídky podmínka: bez něj si šipku vezme pole na posun kurzoru
    /// v textu a v nabídce se nestane nic.
    private func move(_ step: Int) -> KeyPress.Result {
        guard !suggestions.rows.isEmpty,
              let next = Policy.pickerSelection(
                  from: suggestions.highlighted,
                  step: step,
                  count: suggestions.rows.count
              )
        else { return .ignored }
        suggestions.highlighted = next
        return .handled
    }

    /// `↵` na vybraném řádku. Vloží **znak**, ne shortcode, a **zamění napsaný dotaz**, ne přidá na
    /// konec.
    private func insert(_ press: KeyPress) -> KeyPress.Result {
        guard press.modifiers.isEmpty else { return .ignored }
        guard let query, let row = suggestions.rows[safely: suggestions.highlighted] else {
            return .ignored
        }
        guard let insertion = Policy.emojiInsertion(
            into: text,
            replacing: query,
            with: row.emoji.character
        ) else {
            // Dotaz nesedí na text — jediné, co se s tím dá udělat, je zavřít nabídku. Text se
            // nesahá; `refresh()` z něj příští úhoz spočítá dotaz znovu.
            close()
            return .handled
        }
        text = insertion.text
        // Kurzor **za vložený znak**. Bez tohohle by zůstal, kde byl, a dopisovalo by se doprostřed.
        selection = TextSelection(
            insertionPoint: insertion.text.index(
                insertion.text.startIndex,
                offsetBy: insertion.caret
            )
        )
        close()
        return .handled
    }

    /// `esc` — ustupující, viz úvod.
    private func dismiss() -> KeyPress.Result {
        guard query != nil, !suggestions.rows.isEmpty else { return .ignored }
        close()
        return .handled
    }
}

extension View {
    /// Položí nabídku **nad** tuhle plochu, s mezerou z návrhu.
    ///
    /// `alignmentGuide` posune dítě o jeho **vlastní výšku** plus mezeru nahoru — je to jediný
    /// způsob, jak `overlay` položit mimo plochu rodiče, aniž by se ta výška měřila dopředu.
    /// A `overlay` je podstatné: nezabírá místo, takže se pole pod nabídkou **nehýbe**.
    ///
    /// **Je to jedno místo schválně** — sondy měří tutéž geometrii, jakou kreslí okno. Dvě kopie
    /// posunu by se rozešly a jediné, co by z toho bylo vidět, je nabídka nalepená na pole.
    /// **Stín patří sem, ne do nabídky**: `--shadow-lg` je tam proto, že nabídka visí nad obsahem,
    /// což je vlastnost tohohle položení. Hodnota je tatáž jako u palety ⌘K.
    func emojiMenuAbove(@ViewBuilder _ menu: () -> some View) -> some View {
        overlay(alignment: .topLeading) {
            menu()
                .shadow(color: .black.opacity(0.28), radius: 30, y: 12)
                .alignmentGuide(.top) { $0[.bottom] + EmojiSuggesting.gap }
        }
    }
}
