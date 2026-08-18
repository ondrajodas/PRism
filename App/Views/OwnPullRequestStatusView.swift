import SwiftUI

/// `Vlastní PR — review se odsud neodesílá` ve stavovém řádku (#334, návrh sekce 22, `.sitem plain`).
///
/// Odpovídá na otázku, kterou vlastní PR v okně otevírá: **proč tady nejsou tlačítka, na která jsem
/// zvyklý.** Verdikt ani `Odeslat` na vlastním PR nejsou (GitHub `APPROVE` na vlastní PR odmítá,
/// změřeno u #62), takže bez téhle věty vypadá okno ochuzeně, ne jinak zaměřeně.
///
/// **Tichá, bez kapsle** (`plain`), jako stav pracovní kopie vedle: je to konstatování, ne
/// upozornění. Mint ze stejného důvodu — barva stavu, se kterým se nic nedělá (viz `Palette.mint`).
///
/// Kreslí se **jen nad otevřeným vlastním pull requestem**: na domácí záložce ani nad cizím PR není
/// o čem mluvit, a věta, která platí vždycky, se přestane čítat.
struct OwnPullRequestStatusView: View {
    let store: AppStore

    var body: some View {
        if case .pullRequest(let id) = store.activeTab, store.ownership(of: id) == .mine {
            content
        }
    }

    private var content: some View {
        HStack(spacing: 5) {
            // ◈ z návrhu. `diamond.fill` je nejblíž tomu, co mockup kreslí znakem — a je to
            // symbol, který v okně nic jiného neznamená (puntíky služeb jsou kolečka).
            Image(systemName: "diamond.fill")
                .font(.system(size: 8))
            Text("Vlastní PR — review se odsud neodesílá")
        }
        .font(.caption)
        .foregroundStyle(Palette.mint)
        .help("""
            Na vlastním PR se review nesbírá ani neodesílá — GitHub approve na vlastní PR odmítá.
            Místo verdiktu se z nálezů a konverzace skládá zadání pro agenta (panel Zadání, ⌘⇧P).
            """)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Vlastní pull request")
        .accessibilityValue("Review se odsud neodesílá")
    }
}
