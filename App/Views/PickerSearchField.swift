import SwiftUI

/// Hledací řádek nabídky v panelu (#392) — jedno místo pro labely i pro reviewery.
///
/// **Klávesnice tady doopravdy funguje, protože nabídka není `Menu`.** Obě nabídky jsou od začátku
/// `popover` s vlastními views (kvůli dotažení seznamu při otevření a kvůli puntíku s barvou
/// labelu), takže se v nich dá mít pole i obsluha šipek. V systémovém `Menu` by se nedalo ani jedno
/// — a předstírat chování, které tam není, je horší než ho nemít.
///
/// Co obsluhuje: **psaní filtruje**, **šipky vybírají**, `↵` **potvrdí** vybraný řádek. `esc`
/// zavírá popover systémově, takže se na něj nesahá — vlastní obsluha by ho jen vzala tomu, kdo ji
/// umí líp.
///
/// **Fokus je v poli hned po otevření**, protože jinak je nabídka „otevři, **klikni** a piš“, tedy
/// o krok delší, než musí být. Jak se to dělá, je popsané u `.task` níž.
///
/// **Fokus nabídku nepřežije**, a drží to `@FocusState` uvnitř tohohle view: zaniká s popoverem,
/// takže po zavření není co držet a psaní nemá kam mizet. Změřeno sondou v popoveru — po zavření
/// jdou znaky do okna a v poli se neobjeví.
///
/// Rozhodování je v `Policy` (`pickerSelection`, `filteredPicker`, `pickerShowsSearch`); tady
/// zůstává jen předání klávesy.
struct PickerSearchField: View {
    @Binding var query: String
    /// Kolik řádků je po filtru — z toho se počítá, kam smí šipka.
    let count: Int
    /// Posun kurzoru; `nil` = není co vybírat.
    let move: (Int) -> Void
    /// Potvrzení vybraného řádku.
    let confirm: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10))
                .foregroundStyle(Palette.ink3)
            TextField("Hledat", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($isFocused)
                // Šipky a `↵` se berou **na poli**, ne na kontejneru: fokus je v něm, takže
                // kdekoli jinde by je nedostal. `.handled` je podmínka — bez něj si šipku vezme
                // pole na posun kurzoru v textu a v seznamu se nestane nic.
                .onKeyPress(.downArrow) {
                    move(1)
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    move(-1)
                    return .handled
                }
                .onKeyPress(.return) {
                    confirm()
                    return .handled
                }
                // Fokus **až po jednom průchodu smyčky**, a ten `Task.yield()` je to jediné, co
                // funguje: přiřazení ve stejném průchodu, ve kterém pole vzniká, SwiftUI zahodí.
                // Změřeno na běžící aplikaci u palety ⌘K (#184) accessibilitou: `onAppear`, `task`
                // bez yieldu i `defaultFocus($isFocused, true)` daly `AXFocused = false`
                // **navždycky**, ne později. Rozhoduje **počet průchodů, ne čas** — proto tady
                // není žádná pauza a hlavně nic, co by si plánovalo další kolo (#350): jeden
                // yield, jeden zápis, konec.
                //
                // Do #392 tu stálo `onAppear` a nabídka se musela **kliknout**, i když docstring
                // tvrdil opak — nález z proklikání.
                //
                // `Task.isCancelled` se tady **neptáme schválně**: zápis do `@FocusState` view,
                // které zaniklo, je no-op (fokus s popoverem zaniká), kdežto vynechaný zápis by
                // byl zpátky ten stav, kdy se do nabídky musí kliknout.
                .task {
                    await Task.yield()
                    isFocused = true
                }
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Palette.ink3)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .help("Zahodit hledání")
            }
            // Počet je vidět jedině při hledání: nad nefiltrovaným seznamem by opakoval to, co je
            // vidět v něm.
            if !query.isEmpty {
                Text(verbatim: "\(count)")
                    .font(.system(size: 10.5, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(Palette.ink3)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(Palette.raised, in: .rect(cornerRadius: 6))
        .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(Palette.line) }
        .padding(.horizontal, 11)
        .padding(.bottom, 7)
    }
}
