import SwiftUI

/// Pět teček dráhy v řádku seznamu (#509, `.rv-step7` ze zákresu).
///
/// **Celá dráha v osmi bodech výšky.** Hlavička otevřeného PR kreslí tutéž smyčku jako pět
/// kapslí s textem (#508); v řádku na to místo není, takže z kapsle zbude jedině její barva —
/// a slovo o aktivní stanici řekne pilulka vedle.
///
/// **Barvu vydává `LanePhaseChip`, ne tenhle soubor.** Je to tentýž stav (`PhaseState`) a tentýž
/// význam, jen menší kresba; druhé mapování by se s kapslí rozešlo první den, kdy někdo změní
/// odstín. Tvrdí to `LanePhaseChipTests` nad zdrojáky.
///
/// **Rozměr si říká sám a pevně** (#375, #220): v řádku líného seznamu se nevyjednává, takže
/// `HStack` dostane spočítaný rámec. Bez něj by se pruh teček roztahoval podle toho, kolik místa
/// zrovna zbylo, a řádky by přestaly být porovnatelné — a porovnání je jediný důvod, proč tečky
/// v seznamu jsou.
struct OwnLoopDots: View {
    /// Průměr tečky. Osm bodů je ze zákresu (`.rv-step7 i { width: 8px }`).
    static let dot = 8.0
    /// Mezera mezi tečkami (`gap: 3px`).
    static let spacing = 3.0
    /// Šířka celého pruhu — **počítaná z počtu stanic**, ne zapsaná číslem. Kdyby stanic ubylo
    /// nebo přibylo (a jednou už ubyly, #508 čtvrté kolo), zapsané číslo by zůstalo.
    static var width: Double {
        let count = Double(OwnLoop.Station.allCases.count)
        return count * dot + (count - 1) * spacing
    }

    let row: OwnLoopRow

    var body: some View {
        // **Skládá se jednou, ne dvakrát na každé překreslení** (#224). `help` i
        // `accessibilityLabel` chtějí týž řetězec a řádek se v líném seznamu staví při každém
        // průchodu — dvě stejné věty by byly dvakrát pět interpolací na řádek za nic.
        let spoken = Self.spoken(row)
        HStack(spacing: Self.spacing) {
            // **Identita ze stanice, ne z pořadí v poli** (#361): `OwnLoopRow.Dot` je
            // `Identifiable` právě proto, aby se tady neiterovalo pole tuplů.
            ForEach(row.dots) { dot in
                Circle()
                    .fill(LanePhaseChip.dotFill(of: dot.state))
                    .overlay { Circle().strokeBorder(LanePhaseChip.dotStroke(of: dot.state), lineWidth: 1) }
                    .frame(width: Self.dot, height: Self.dot)
            }
        }
        .frame(width: Self.width, height: Self.dot)
        // **Jeden prvek, ne pět.** Odečítat pět teček po jedné je horší než jedna věta: pořadí
        // stanic je to jediné, čím tečky mluví, a to se ze samostatných prvků nepřečte.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
        .help(spoken)
    }

    /// Dráha slovy — `Nálezy hotovo · Zadání právě běží · Push nedošlo na ni · …`. Stav
    /// pojmenovává **`ReviewerLaneText.phase`**, tedy tentýž slovník jako na dráze v hlavičce.
    static func spoken(_ row: OwnLoopRow) -> String {
        row.dots
            .map { "\($0.station.title) \(ReviewerLaneText.phase($0.state))" }
            .joined(separator: " · ")
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 10) {
        OwnLoopDots(
            row: OwnLoopRow(
                dots: [
                    .init(station: .findings, state: .done),
                    .init(station: .handoff, state: .running),
                    .init(station: .push, state: .idle),
                    .init(station: .ci, state: .done),
                    .init(station: .review, state: .done),
                ],
                word: "Zadání 2 k předání",
                tone: .running
            )
        )
        OwnLoopDots(
            row: OwnLoopRow(
                dots: OwnLoop.Station.allCases.map { .init(station: $0, state: .done) },
                word: "hotovo",
                tone: .done
            )
        )
    }
    .padding()
}
