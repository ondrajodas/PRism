import SwiftUI

/// Editor promptu review na stránce `Review a skilly` (#281).
///
/// Dvě plochy, ne jedno pole — přesně jak to má návrh (sekce 10): nahoře **psaná šablona**,
/// pod ní **náhled**, ve kterém je vidět, co z ní vyjde a co se k ní připojí. Psaná plocha je
/// světlá a ohraničená, připojované jádro tmavší a čárkované, aby se rozdíl poznal bez čtení
/// popisků.
///
/// **Neplatná šablona se neukládá.** Pole si drží, co je do něj napsané, a chybějící zástupný
/// text pojmenuje pod polem; do konfigurace se propíše teprve platná hodnota. Je to celý důvod,
/// proč tu je `text` jako `@State` a ne `Binding` do konfigurace — zápis rozepsané šablony bez
/// `{{baseSha}}` by běhu sebral to, proti čemu diffuje, a „nic se nestalo“ je k nerozeznání od
/// „funguje“. Ruční editace `config.json` je proti tomu jiná cesta a hlídá si ji `AppStore`,
/// který s takovou šablonou review nespustí.
struct ReviewPromptEditor: View {
    /// Hodnota v konfiguraci. Píše se do ní jen tehdy, když je rozepsaná šablona platná.
    @Binding var stored: String
    /// Co je zrovna v poli — včetně stavu, který se ukládat nesmí.
    @State private var text: String

    init(stored: Binding<String>) {
        _stored = stored
        _text = State(initialValue: stored.wrappedValue)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            editor
            preview
        }
        // Zápis do konfigurace je **podmíněný**: rozepsaná šablona bez zástupného textu
        // v souboru skončit nemá.
        .onChange(of: text) { _, edited in
            guard Policy.reviewPromptProblems(in: edited).isEmpty else { return }
            stored = edited
        }
        // Změna zvenčí (ručně editovaný soubor) pole srovná. Vlastní zápis se sem vrátí taky,
        // ale se shodnou hodnotou, takže nic nepřepíše.
        .onChange(of: stored) { _, saved in
            if saved != text { text = saved }
        }
    }

    // MARK: - Psaná šablona

    private var editor: some View {
        VStack(alignment: .leading, spacing: 7) {
            caption("Šablona zadání")
            TextEditor(text: $text)
                .font(.system(size: 11, design: .monospaced))
                .lineSpacing(5)
                .scrollContentBackground(.hidden)
                .padding(.vertical, 6)
                .padding(.horizontal, 7)
                .frame(minHeight: 116)
                .background(Palette.surface, in: .rect(cornerRadius: 6))
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(problems.isEmpty ? Palette.line : Palette.crit, lineWidth: 1)
                }
                .accessibilityLabel("Šablona zadání pro reviewera")
            footer
            ForEach(problems) { problem in
                complaint(problem.reason)
            }
            // Prázdná šablona **není chyba** (znamená „ber výchozí“), takže se k ní nevypisuje
            // stížnost, ale poznámka — a `problems` je u ní prázdné, protože se vyhodnocuje to,
            // s čím se doopravdy poběží.
            if isBlank {
                hint("Prázdná šablona — bere se výchozí text. Pustit reviewera bez zadání nejde.")
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            chip(ReviewPromptTemplate.skillPlaceholder)
            chip(ReviewPromptTemplate.baseShaPlaceholder)
            Spacer(minLength: 8)
            Button("Obnovit výchozí") { text = ReviewPromptTemplate.standard }
                .controlSize(.small)
                .disabled(text == ReviewPromptTemplate.standard)
        }
    }

    // MARK: - Náhled

    /// Složený prompt s ukázkovými hodnotami. Bez něj člověk edituje polovinu textu naslepo
    /// a nepozná, proč se reviewer chová jinak, než co má v poli.
    private var preview: some View {
        VStack(alignment: .leading, spacing: 7) {
            caption("Náhled — takhle se prompt poskládá; dosazené hodnoty jsou ukázkové")
            Text(verbatim: Policy.reviewPromptBody(
                template: text,
                skillID: ReviewPromptTemplate.sampleSkillID,
                baseSha: ReviewPromptTemplate.sampleBaseSha
            ))
            .textSelection(.enabled)
            .font(.system(size: 11, design: .monospaced))
            .lineSpacing(5)
            .foregroundStyle(Palette.ink)
            // Bez `fixedSize` si `Form` řádek srazí na tři řádky a zbytek promptu uřízne
            // třemi tečkami — tedy náhled, který zamlčí zrovna to, kvůli čemu se do něj kouká.
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .background(Palette.surface, in: .rect(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6).strokeBorder(Palette.line, lineWidth: 1)
            }

            Label("Připojí se vždycky, přepsat to nejde", systemImage: "lock")
                .font(.system(size: 11))
                .foregroundStyle(Palette.ink2)
            // **Přes `Policy`, ne z konstanty `core`** (#120): od chvíle, kdy se k jádru něco
            // připojuje, by čtení konstanty znamenalo druhou pravdu o jednom textu — náhled by
            // ukazoval jádro bez věty o zadání a nikdo by si toho nevšiml. Ukázková cesta je
            // pevná, jako `sampleSkillID` a `sampleBaseSha`.
            // **A od #517 i s přírůstkem**, ze stejného důvodu: věty, které rozhodují, nad čím
            // reviewer běží, se v náhledu ukázat musí — jinak by se dalo přečíst, že po pushi
            // dostane totéž zadání jako v prvním kole.
            Text(verbatim: Policy.reviewPromptCore(
                intentPath: ReviewPromptTemplate.sampleIntentPath,
                increment: ReviewPromptTemplate.sampleIncrement
            ))
                .textSelection(.enabled)
                .font(.system(size: 11, design: .monospaced))
                .lineSpacing(5)
                .foregroundStyle(Palette.ink3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
                .padding(.horizontal, 10)
                .background(Palette.raised, in: .rect(cornerRadius: 6))
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Palette.line, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
            // Bez téhle věty by odznak se zámkem výš tvrdil, že se **celý** blok připojí vždycky
            // — a to o poslední větě neplatí: PR bez popisu a bez odkazu žádné zadání nemá, takže
            // se nepřipojí nic. Cesta v náhledu je navíc ukázková, ne cesta konkrétního běhu.
            hint("Věta o zadání PR se připojí jen u PR, ke kterému se zadání sehnalo. Věty "
                + "o přírůstku jen po pushi, když je zapnuté `Po pushi review jen přírůstku` — "
                + "v prvním kole reviewer prochází celý diff. Cesty v obojím jsou ukázkové.")
        }
    }

    // MARK: - Kousky

    private var problems: [ReviewPromptTemplate.Problem] {
        Policy.reviewPromptProblems(in: text)
    }

    private var isBlank: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func caption(_ title: String) -> some View {
        Text(verbatim: title)
            .font(.system(size: 11))
            .foregroundStyle(Palette.ink2)
    }

    /// Chybějící zástupný text. Druhá věta je tam schválně: bez ní vypadá pole jako uložené
    /// a rozdíl proti souboru by se poznal až po restartu.
    private func complaint(_ reason: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(reason, systemImage: "exclamationmark.triangle")
                .foregroundStyle(Palette.crit)
            Text("Neuloží se — v konfiguraci zůstává poslední platná šablona.")
                .foregroundStyle(Palette.ink3)
        }
        // 11,5 bodu je velikost vysvětlivky pod sekcí z návrhu (`.set-sec > .note`), ne `.caption`:
        // stížnost stojí uvnitř bloku a má číst stejně jako popisky kolem něj.
        .font(.system(size: 11.5))
        .fixedSize(horizontal: false, vertical: true)
    }

    private func hint(_ text: String) -> some View {
        Label(text, systemImage: "info.circle")
            .font(.system(size: 11.5))
            .foregroundStyle(Palette.ink3)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func chip(_ placeholder: String) -> some View {
        Text(verbatim: placeholder)
            .font(.system(size: 10.5, design: .monospaced))
            .foregroundStyle(Palette.ink2)
            .padding(.vertical, 2)
            .padding(.horizontal, 7)
            .background(Palette.raised, in: .rect(cornerRadius: 5))
            .overlay {
                RoundedRectangle(cornerRadius: 5).strokeBorder(Palette.lineSoft, lineWidth: 1)
            }
            .textSelection(.enabled)
    }
}
