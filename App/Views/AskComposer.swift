import SwiftUI

/// Pole a odesílací tlačítko na spodní hraně tabu `Zeptat se` (#452).
///
/// **Text drží tenhle view, ne store — a je to oprava, ne styl.** `DraftTextEditor` posílá text
/// dolů po odmlce 400 ms, protože rozdělané review čtou bubliny v diffu. Tady je ale to, co se
/// odesílá, **totéž pole**, do kterého se píše: klik trefený do té odmlky odeslal starší otázku
/// a rozepsanou vrátil zpátky do pole, takže v bublině byla půlka věty a v composeru celá.
/// Změřeno v `AskComposerTests`, ne odvozeno.
///
/// Store zůstává tím, kdo otázku **odesílá** (jediná cesta k session) i kdo drží **zálohu pro
/// přepnutí tabu** — dostane ji ale ve chvíli odeslání a při zmizení, ne po odmlce. Mezi tím
/// `askDrafts` nikdo nemění, takže se sem zvenčí nemá co vrátit; proto tu není `onChange(of:)`,
/// kterým se ta okružní cesta v `DraftTextEditor`u drží pohromadě.
///
/// **Identitu podle PR mu dává volající** (`.id(pullRequest.id)` v `PullRequestDetailView`):
/// detail se mezi pull requesty **znovupoužívá**, takže bez toho by se rozepsaná otázka
/// přenesla na cizí PR a při zmizení se do něj i uložila.
struct AskComposer: View {
    /// Rozepsaná otázka, jak ji zná store. Čte se **jen při objevení** — je to záloha, ne pravda.
    let draft: String
    /// Proč se zeptat nedá. `nil` = dá se.
    var block: String?
    var isAnswering = false
    /// Uloží text do zálohy pro přepnutí tabu.
    var persist: (String) -> Void = { _ in }
    /// Odešle otázku. Vrací, jestli se doopravdy odeslala — když ne, text v poli **zůstane**.
    var send: (String) -> Bool = { _ in false }
    /// Zastaví běžící odpověď. `nil` = zastavit se nedá (náhledy a testy skládání).
    var cancel: (() -> Void)?

    @State private var value = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            DraftTextField(
                text: $value,
                placeholder: "Zeptej se na cokoli v tomhle PR…",
                minHeight: 46,
                maxHeight: 46
            )
            .disabled(block != nil)
            controls
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.chrome)
        .overlay(alignment: .top) { Rectangle().fill(Palette.line).frame(height: 1) }
        .onAppear { value = draft }
        .onDisappear { persist(value) }
    }

    /// Věta u pole říká, co session smí — je to totéž tvrzení jako kapsle v liště, jen slovy,
    /// a stojí tam, kde se rozhoduje o odeslání otázky.
    private var controls: some View {
        HStack(spacing: 9) {
            Text(verbatim: "Čte kód ve své kopii repa. Odeslat na GitHub neumí.")
                .font(.system(size: 11))
                .foregroundStyle(Palette.ink3)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            // **Kreslená kapsle, ne `keyboardShortcut`.** Klávesu bere `Button` níž
            // (`.defaultAction`), takže by druhá registrace téže kombinace byla ta past
            // z #151 a #184 — v tomhle tabu je `⌘⏎` navíc **zakázané** zkratce okna
            // (`Policy.claimsReturnShortcut`), aby se sem propadlo.
            // A **jen když tu klávesu doopravdy někdo bere** — vedle `Zastavit` by kapsle
            // tvrdila zkratku, která v tu chvíli nic nedělá.
            if !isAnswering {
                Text(verbatim: "⌘⏎")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Palette.ink3)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Palette.raised, in: .rect(cornerRadius: 5))
                    .accessibilityHidden(true)
            }
            // **Během odpovědi se z tlačítka stane `Zastavit`.** Jedna odpověď stojí kolem
            // dolaru a běží minuty (změřeno, viz `docs/claude-cli.md`), takže „rozmyslel jsem si
            // to“ nesmí znamenat čekat na konec — a zakázané `Zeptat se` vedle prstýnku je
            // tlačítko, které v tu chvíli nedělá nic. Je to **tentýž ovládací prvek v jiném
            // stavu**, ne druhé tlačítko: dvě vedle sebe by v úzkém composeru braly místo
            // a jedno z nich by bylo vždycky zakázané.
            if isAnswering, let cancel {
                Button("Zastavit") { cancel() }
                    .buttonStyle(.bordered)
                    .font(.system(size: 12.5))
                    .help("Zabije běžící session. Otázka v rozhovoru zůstane.")
            } else {
                Button("Zeptat se") { submit() }
                    .buttonStyle(.borderedProminent)
                    .font(.system(size: 12.5))
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(!canSend)
                    .help(sendHelp)
            }
        }
    }

    /// Odeslat = **doručit text, spustit session a vyprázdnit pole**, v tomhle pořadí a jako
    /// jedna věc. Vyprázdnění není úklid navíc: odeslaná otázka, která zůstane v poli, se dá
    /// odeslat podruhé a stojí podruhé.
    ///
    /// Když se neodeslala, **nesahá se na nic** — text zůstane, kde je, a záloha ve store taky.
    private func submit() {
        guard send(value) else { return }
        value = ""
        persist("")
    }

    private var canSend: Bool {
        block == nil && !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isAnswering
    }

    private var sendHelp: String {
        if let block { return block }
        if isAnswering { return "Počkej na odpověď — v jednom rozhovoru běží jedna session." }
        if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Napiš otázku."
        }
        return "Spustí session nad kopií tohohle PR. Čte kód, nic neodesílá."
    }
}
