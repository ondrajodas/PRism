import SwiftUI

/// Textové pole rozdělaného review — píše se do něj průběžně, ukládá se odloženě.
///
/// Zapisovat každý úhoz do store nejde: draft čtou bubliny v diffu, takže by se při psaní
/// překresloval celý diff. Text proto žije tady a dolů se pošle po odmlce — a **vždycky při
/// zmizení**, protože bublina je buňka líného seznamu a odscrollováním se zahodí. Ztracená
/// věta je tady to nejdražší, co se dá pokazit.
///
/// Odklad je stejná úvaha jako u okna nastavení (`SettingsModel`), jen bez `TimeSource`:
/// tohle je view, a views se v tomhle repu neunit-testují.
///
/// **Pro composer, ze kterého se odesílá jedním klikem, se to nehodí** (#452) — mezi „co je
/// vidět“ a „co store ví“ je celá ta odmlka, takže klik do ní trefený pošle starší text
/// a rozepsaný vrátí zpátky do pole. Tab `Zeptat se` má proto vlastní `AskComposer`, který text
/// drží u sebe a dolů ho posílá až při odeslání; podobu pole sdílejí přes `DraftTextField`.
struct DraftTextEditor: View {
    /// Text, jak ho zná store.
    let text: String
    var placeholder = ""
    var minHeight: Double = 60
    /// Strop výšky. `nil` = pole se roztáhne, kolik dostane. Podrobnosti u `DraftTextField`.
    var maxHeight: Double?
    /// Má se prázdný text doručit i tehdy, když se **nezměnil**?
    ///
    /// U řádkového komentáře ano. Prázdný komentář znamená „zahoď mě“ a vzniká právě tím, že
    /// se založí kliknutím a nic se do něj nenapíše — tedy beze změny textu. Bez tohohle by
    /// `flush()` na odmlku „nic se nezměnilo“ nic neposlal a prázdný komentář by zůstal
    /// v draftu i na disku, kde blokuje odeslání celého review.
    ///
    /// U těla review ne: tam prázdno neznamená nic a zápis by byl jen práce navíc.
    var commitsEmpty = false
    /// Kam se zapisuje otevřená nabídka emotikonů (#483). Podrobnosti u
    /// `DraftTextField.suggestions`.
    ///
    /// **Nepředává ho řádkový komentář v diffu**, což je čtvrtý uživatel tohohle pole a taky posílá
    /// text na GitHub. Důvod je kresba, ne opomenutí: `DraftCommentBubbleView` má na bublině
    /// `clipShape` a sedí uvnitř diffu, takže nabídka by se ořízla o hranu bubliny (změřeno, viz
    /// `EmojiSuggestionBox`). Zadání (#483) vyjmenovává tři pole a tohle mezi nimi není.
    var suggestions: EmojiSuggestionBox?
    /// Odkud se do pole vkládá text zvenku (#528) — tlačítko `Návrh změny` nad polem.
    ///
    /// Vkládá se do **živého** textu, ne přes store: mezi tím, co je vidět, a tím, co store ví,
    /// je odmlka 400 ms, takže blok složený nad hodnotou ze storu by tu odmlku přepsal
    /// rozepsanou větou. Podrobnosti u `TextInsertionBox`.
    var insertion: TextInsertionBox?
    let commit: (String) -> Void

    @State private var value = ""
    /// Co jsme naposledy poslali dál. Bez toho by se vlastní uložení vrátilo přes `text`
    /// zpátky a přepsalo rozepsaný řádek — stejná past jako `settled` v `SettingsModel`.
    @State private var committed = ""
    @State private var save: Task<Void, Never>?

    private static let delay = Duration.milliseconds(400)

    var body: some View {
        DraftTextField(
            text: $value,
            placeholder: placeholder,
            minHeight: minHeight,
            maxHeight: maxHeight,
            suggestions: suggestions
        )
        .onAppear { adopt(text) }
        .onChange(of: text) { _, new in
            // Vlastní zápis, který se vrátil ze store, se přeskočí — jinak by přepsal to,
            // co je zrovna rozepsané.
            guard new != committed else { return }
            // Cizí změna přišla dřív, než se rozepsané uložilo (typicky převzetí nálezu
            // do těla během psaní). Rozepsané se doručí, ať se neztratí — cena je, že
            // právě přidaná položka se tím přepíše, což je vidět a dá se kliknout znovu.
            // Mířit to může jen na tentýž draft: identita tohohle view je svázaná s PR,
            // takže při přepnutí se view **zahodí** (a flushne v `onDisappear`), ne
            // překreslí.
            flush()
            adopt(new)
        }
        .onChange(of: value) { _, new in schedule(new) }
        // Vložení zvenku (#528). Zapisuje se do `value`, takže se o uložení postará `schedule`
        // přes `onChange(of: value)` — vložení není zvláštní cesta k odeslání, jen zvláštní
        // cesta k **napsání**.
        .onChange(of: insertion?.pending) { _, new in
            guard let new, !new.isEmpty else { return }
            // Vynulovat hned: bez toho by tentýž blok naskočil znovu při každém překreslení,
            // které by `pending` přečetlo.
            insertion?.pending = nil
            value = Policy.blockInsertion(of: new, into: value)
        }
        .onDisappear { flush() }
    }

    private func adopt(_ new: String) {
        save?.cancel()
        value = new
        committed = new
    }

    private func schedule(_ new: String) {
        guard new != committed else { return }
        save?.cancel()
        save = Task {
            try? await Task.sleep(for: Self.delay)
            guard !Task.isCancelled else { return }
            commit(new)
            committed = new
        }
    }

    /// Doručí, co je rozepsané, dřív než view zmizí. Přepnutí PR i odscrollování bubliny jde
    /// touhle cestou.
    ///
    /// Prázdný text se u komentáře doručí **i beze změny** (`commitsEmpty`) — jinak by
    /// založený a nedopsaný komentář zůstal ležet v draftu, protože v něm od začátku prázdno
    /// bylo a `value == committed` by odchod utnul.
    private func flush() {
        save?.cancel()
        guard value != committed || (commitsEmpty && value.isEmpty) else { return }
        commit(value)
        committed = value
    }
}
