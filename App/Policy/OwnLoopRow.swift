import Foundation

/// Dráha vlastního PR (#508) **zmenšená do jednoho řádku seznamu** (#509).
///
/// **Nesestavuje se, odvozuje se.** Řádek si vlastní výčet stanic neskládá — dostane `OwnLoop`
/// a vytáhne si z něj tečky, slovo a odstín. Dvě skládání jedné smyčky by uměla říct každé něco
/// jiného: hlavička otevřeného PR by tvrdila `Push · o 4 vzadu` a řádek v seznamu nad tímtéž PR
/// třeba `CI`, protože by se každý zastavil jinde. To je zrovna ten druh rozporu, který se
/// v okně nedá odhalit jinak než tím, že se člověk dívá na obojí naráz.
///
/// **Tři věci, a každá odpovídá na jinou otázku:**
///
/// - `dots` — *kde v kole to stojí*. Pět teček v pořadí `OwnLoop.Station.allCases`, tedy celá
///   dráha v osmi bodech výšky. Bez slova by z nich šlo přečíst jen „kolik je hotových“;
/// - `word` — *co je zrovna na tahu*. **Jméno stanice a její detail**, protože samotné
///   `o 4 vzadu` v řádku neříká, čeho se to týká, a samotné `Push` neříká, co s ním je;
/// - `tone` — *jak vážné to je*. Stav aktivní stanice, ze kterého se bere barva pilulky
///   **i hrany řádku**. Je to `ReviewerLane.PhaseState`, tedy tatáž hodnota jako na dráze —
///   barvu z ní dělá `LanePhaseChip`, jediné místo v okně, kde se stav fáze na barvu překládá.
struct OwnLoopRow: Equatable, Sendable {
    /// Jedna tečka. **Identitu nese stanice, ne pořadí v poli** (#361): řádek se kreslí v líném
    /// seznamu, a tam je identita přes tuple ta past, kvůli které se u enumu s asociovanými
    /// hodnotami kopíruje payload při každém průchodu.
    struct Dot: Identifiable, Hashable, Sendable {
        let station: OwnLoop.Station
        let state: ReviewerLane.PhaseState

        var id: OwnLoop.Station { station }
    }

    /// Pět teček, vždycky a v pořadí, ve kterém se kolo jde.
    let dots: [Dot]
    /// Slovo k aktivní stanici (`Push o 4 vzadu`, `CI 1 neprošel`). Nikdy prázdné.
    let word: String
    /// Stav, ze kterého se bere barva pilulky i hrany řádku.
    let tone: ReviewerLane.PhaseState
}

extension Policy {
    /// Co z dráhy vlastního PR unese řádek seznamu (#509). `nil` = **řádek dráhu nekreslí**.
    ///
    /// **`nil` na cizím PR se sem přenáší samo**, protože `Policy.ownLoop` ho na cizím vrací —
    /// není tady tedy druhá kontrola vlastnictví, která by se s tou první uměla rozejít.
    ///
    /// **Slovo je `detail` aktivní stanice, ne její `reason`** (#508, čtvrté kolo), a je to
    /// rozhodnutí, ne přehlédnutí. `reason` je jedno slovo bez čísla schválně: kreslí se v šedé
    /// kapsli **za** zastávkou, tedy vedle věty, která mluví o jiné stanici, a číslo by se v té
    /// poloze četlo jako tvrzení o tom, co je na tahu. V řádku je to obráceně — pilulka je
    /// **jediná** věta o tomhle PR a tečky u ní ukazují, které stanice se týká, takže `o 4 vzadu`
    /// je zrovna to, co se má dozvědět. Jméno stanice před ní stojí ze stejného důvodu: bez něj
    /// by `zjišťuju` nebo `spadlo` mohlo být o čemkoli z těch pěti.
    ///
    /// **Dojetá smyčka neříká `k merge`, a je to změna proti zákresu** (deck, směr D, poznámka
    /// 20). Zákres pohlcoval N4 („co brání mergi“) tak, že se pilulka měla ptát na slévatelnost;
    /// jenže na tu už odpovídá **pruh `K merge` na desce** (#515, `Policy.isMergeReady` nad
    /// `mergeOffer`) a sekce `Větev` (#465). Dráha na ni neodpovídá schválně — od čtvrtého kola
    /// #508 nebere `MergeOffer` **ani jako vstup** —, takže by `k merge` odsud byla druhá odpověď
    /// na jednu otázku, složená z jiných dat než ta první. Řádek proto říká `hotovo`: **všech pět
    /// stanic je hotových**, což je tvrzení, které dráha unese, a kde se merguje, ví sekce
    /// `Větev`.
    static func ownLoopRow(_ loop: OwnLoop?) -> OwnLoopRow? {
        guard let loop else { return nil }
        // Ptá se **adresně přes `state(of:)`**, ne `stations.map`: pět teček v pořadí walku je
        // celý smysl kresby, takže se pořadí ani počet nesmí vzít z toho, co kdo do pole přidal.
        let dots = OwnLoop.Station.allCases.map {
            OwnLoopRow.Dot(station: $0, state: loop.state(of: $0))
        }
        guard let active = loop.active else {
            // Bez zastávky smyčka **došla**, a jsou to dva různé konce. Mergnutá je pět hotových
            // stanic, zavřená pět `stopped` (viz `Policy.ownLoop`), takže se od sebe poznají bez
            // druhého vstupu — ptát se sem znovu na stav pull requestu by znamenalo dvě místa,
            // která o tomtéž rozhodují.
            let finished = dots.allSatisfy { $0.state == .done }
            return OwnLoopRow(
                dots: dots,
                word: finished ? "hotovo" : "zavřeno",
                tone: finished ? .done : .stopped
            )
        }
        let state = loop.state(of: active)
        // `detail` u zastávky vyplněný je (skládá ho `Policy.ownLoop`), ale typ ho nemá jak
        // vynutit — a samotné jméno stanice je pořád pravdivá odpověď, jen chudší.
        guard let detail = loop.detail(of: active) else {
            return OwnLoopRow(dots: dots, word: active.title, tone: state)
        }
        return OwnLoopRow(dots: dots, word: "\(active.title) \(detail)", tone: state)
    }
}
