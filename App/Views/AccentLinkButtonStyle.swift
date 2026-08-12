import SwiftUI

/// Textová akce v barvě akcentu (`.frow .acts .go` z návrhu) — akce v tabulce nálezů (#298).
///
/// **Proč vlastní styl, a ne `.link`.** `.buttonStyle(.link)` kreslí systémovou `NSColor.linkColor`
/// (`#0068DA` ve světlém, `#419CFF` v tmavém), tedy jedinou barvu v okně, která z palety návrhu
/// není — `.tint(Palette.accent)` z kořene okna si `.link` nebere. V okně z toho byla dvě různá
/// „klikni sem“ naráz: fialová na tlačítkách u nálezu v diffu (#283) a modrá na akcích v tabulce.
///
/// Návrh přitom u obojího chce **tentýž akcent**, jen jinou **formu**: v bublině plochu (`.mini`),
/// v tabulce holý text (`.go { color: var(--accent) }`). **Tvar se proto nemění, mění se barva** —
/// v tabulce se akce opakuje na každém řádku, takže plocha by přebila shrnutí, kvůli kterému se
/// tabulka čte. To je vědomý rozdíl proti #283 a `MiniButtonStyle` ho nemá nahradit.
///
/// Font si drží volající (v tabulce `.caption` celé řady akcí, ve stavovém řádku `.caption` pruhu):
/// styl nese jen to, co má být na všech výskytech stejné — barvu, zmáčknutí a kurzor.
struct AccentLinkButtonStyle: ButtonStyle {
    /// Barva **není `private` schválně**: čte ji test, protože „akce jde z palety, ne ze systému“ je
    /// tvrzení, které se dá potichu zrušit dosazením `.link` zpátky, a ve světlém režimu je rozdíl
    /// fialové a systémové modré na malém textu na první pohled snadné přehlédnout. Ven z aplikace
    /// se tím nic neotevírá — je to jeden modul. Tatáž úvaha jako u barev `MiniButtonStyle`.
    var foreground: Color { Palette.accent }

    /// **`ButtonStyleConfiguration` vypsané celé, ne `Configuration`** — aplikace má vlastní
    /// `Configuration` (nastavení) a ta jméno z protokolu přebije, viz `MiniButtonStyle`.
    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        configuration.label
            .foregroundStyle(foreground)
            .contentShape(.rect)
            // Zmáčknutí musí být vidět, a **ztlumením**, ne druhou barvou — stejně jako
            // u `MiniButtonStyle`, aby dvě formy téže akce nereagovaly na klik každá jinak.
            // Druhý odstín akcentu paleta nemá.
            .opacity(configuration.isPressed ? 0.6 : 1)
            // Kurzor je tady **schválně a je to rozhodnutí**, ne zachování systémového chování:
            // v tabulce nese „dá se kliknout“ jedině barva (návrh tam plochu nechce), takže ruka
            // nad textem je druhý signál. `pointerStyle`, ne `NSCursor.push()`/`pop()` — když view
            // zmizí uprostřed hoveru, druhá půlka páru se nikdy nezavolá a v aplikaci zůstane cizí
            // kurzor; viz `ReviewPanel.resizeHandle`.
            .pointerStyle(.link)
    }
}

extension ButtonStyle where Self == AccentLinkButtonStyle {
    /// Textová akce v barvě akcentu (`.go` z návrhu) — **místo systémového `.link`**.
    static var accentLink: AccentLinkButtonStyle { AccentLinkButtonStyle() }
}
