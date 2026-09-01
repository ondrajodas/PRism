import SwiftUI

/// Místo pro blok kódu, ve kterém je blok nasazený, **jen když je v pásu kolem výřezu** (#469).
///
/// Od #469 kreslí diff pevný `VStack` — líný seznam do grafu zapisuje při umisťování položek
/// a to kolo se nemá kde zastavit (#361). Laznost se tím ale nezahodila, jen **přestěhovala
/// z rozvržení do jednoho rozhodnutí**: `Policy.mountBand(visible:)`, čistá funkce, o které se
/// dá psát test.
///
/// **Co odsud zmizí, když blok v pásu není:** textové view (`NSTextView`), plocha na tažení
/// rozsahu, pilulka na komentář, kontextové menu i hlášení rámečků. Zbyde `Color.clear`
/// s naposledy změřenou výškou, takže se v seznamu nic neposune.
///
/// **Dokud výška změřená není, blok se nasazuje** — o nezměřeném bloku se nedá tvrdit nic, takže
/// ho nemá co zastoupit. Na první rozvržení se proto vyrobí i bloky, které v pásu neskončí, a hned
/// nato se odpojí; **kolik jich to je, se řídit nedá** a měřená cena prvního rozvržení leží mezi
/// oběma krajnostmi (6000 řádků: 3 ms líný seznam, **50 ms** takhle, 150 ms pevný stack bez okna —
/// `DiffShapeProbe.firstLayoutCost`).
///
/// **Odhad výšky by tu cenu ušetřil a je zamítnutý**: obsah pod prstem by měnil výšku pokaždé, když
/// se blok poprvé nasadí, a skok na nález by mířil vedle. Přesná výška od začátku je to, co drží
/// `⌥↓` i kotvy z `DiffRow.blockSpot`.
///
/// **Rámeček se čte v souřadnicích obsahu, ne výřezu**, a to je výkonová podmínka, ne libovůle:
/// v souřadnicích obsahu se scrollováním **nemění**, takže se za to čtení při projíždění neplatí.
/// Co se mění, čte jedno místo — viz `DiffViewport`.
struct DiffBlockSlot<Content: View>: View {
    @ViewBuilder let content: Content

    /// Kde je výřez. **Volitelně**, protože mimo `DiffView` (náhledy, sondy) ho nikdo nedodá —
    /// a chybějící výřez znamená **nasadit**: prázdné místo je horší odpověď než blok navíc.
    @Environment(DiffViewport.self) private var viewport: DiffViewport?

    /// Kde blok leží a jak je vysoký. **Mimo observable stav** (`@State` na třídě, jejíž pole
    /// nikdo nesleduje), stejně jako `DiffBlockPlacement` a `DiffRowFrames`: zapisuje se do toho
    /// z geometrie, a kdyby se tím překresloval, byla by z toho zpětná vazba z každého snímku
    /// (#358). O tom, kdy se tělo přeloží znovu, rozhoduje **pás** — a ten se mění jednou za výřez.
    @State private var span = DiffBlockSpan()

    var body: some View {
        // Čtení `band` je zároveň **přihlášení k odběru**: jinak by se tělo po posunu pásu
        // nepřeložilo a blok by se nikdy nenasadil.
        if let viewport, span.matches(viewport.generation), let range = span.range,
           !Policy.isBlockMounted(range, band: viewport.band) {
            // Šířku si bere od stacku, výšku má z měření — kdyby se lišila, seznam by se
            // odpojením bloku posunul pod rukou.
            Color.clear.frame(height: range.upperBound - range.lowerBound)
        } else {
            content
                .onGeometryChange(for: CGRect.self) {
                    $0.frame(in: .named(DiffView.contentSpace))
                } action: { rect in
                    span.note(rect.minY...max(rect.maxY, rect.minY), in: viewport?.generation ?? 0)
                }
        }
    }
}

/// Kde blok leží v obsahu diffu. Třída, aby zápis z geometrie nepřekresloval — viz `DiffBlockSlot`.
///
/// `nil` znamená **ještě se nikdy nekreslil**, a to je rozdíl proti „leží v nule“: podle toho se
/// pozná, že se blok musí nasadit, aby se vůbec dal změřit.
@MainActor final class DiffBlockSpan {
    private(set) var range: ClosedRange<Double>?
    private var generation: Int?

    /// Platí to, co je změřené, pro **tenhle** diff? Cizí měření se zahodí tím, že se blok
    /// nasadí — viz `DiffViewport.generation`.
    func matches(_ generation: Int) -> Bool { self.generation == generation }

    func note(_ range: ClosedRange<Double>, in generation: Int) {
        self.range = range
        self.generation = generation
    }
}
