/// Podoba tlačítka „obnovit teď“ v hlavičce okna, dokud se aplikace ptá (#442).
///
/// **Je to jeden typ, ne čtyři `if`y u volajícího**, a je to schválně: tutéž podmínku („běží
/// obnovení?“) čtou **tři** místa — tlačítko `⟳` v hlavičce, `AppStore.refresh()` jako pojistka
/// proti druhému dotazu, a **#441 si odsud vezme povolení pro zkratku `⌘R`**. Tři kopie téhož
/// `if`u by se rozešly při první opravě, a rozešly by se **potichu**: zakázaná zkratka nad
/// povoleným tlačítkem vypadá jako nefunkční klávesa, povolená zkratka nad zakázaným tlačítkem
/// jako nefunkční tlačítko.
struct RefreshControl: Equatable {
    /// Místo šipky se v tlačítku točí prstýnek (`SpinningRing`, týž jako u běžícího review).
    var isSpinning: Bool
    /// Bere tlačítko klik a je zkratka k dispozici? Po dobu dotazu ne — druhý dotaz by ten
    /// první nezrychlil.
    var isEnabled: Bool
    /// Popisek pro čtečku obrazovky. **Liší se podle stavu**: bez toho by to byl pořád jen
    /// `Obnovit`, tedy tlačítko, na kterém se pro čtečku nezměnilo vůbec nic.
    var label: String
    /// Nápověda pod kurzorem.
    var help: String
}

extension Policy {
    /// Jak vypadá a co dovolí tlačítko obnovení, když polling zrovna běží — nebo neběží (#442).
    ///
    /// **Rozhoduje `AppStore.isRefreshing`, ne to, kdo dotaz spustil.** Prstýnek se točí i při
    /// **automatickém tiku**: je to stav aplikace, ne odezva na tlačítko. Kdyby se točil jen po
    /// kliknutí, znamenal by „tohle jsi spustil ty“ — tvrzení, které by většinu času neplatilo,
    /// protože většina tiků přijde ze smyčky.
    ///
    /// **Zakázané tlačítko se nekreslí zašedle** a nemá vedle sebe větu s důvodem, na rozdíl od
    /// vypnuté brány odesílání (#392). Rozdíl je v tom, že tady je důvod **vidět v tom samém
    /// tlačítku**: točící se prstýnek říká „ptám se“, a to je celá odpověď na otázku, proč klik
    /// nic neudělá. Navíc to trvá vteřiny, ne dokud si někdo nezmění nastavení.
    static func refreshControl(isRefreshing: Bool) -> RefreshControl {
        guard isRefreshing else {
            return RefreshControl(
                isSpinning: false,
                isEnabled: true,
                label: "Obnovit",
                help: "Obnovit seznam"
            )
        }
        return RefreshControl(
            isSpinning: true,
            isEnabled: false,
            label: "Obnovuje se",
            help: "Ptám se GitHubu…"
        )
    }
}
