import SwiftUI

/// Mapa PR v **řádku fronty** (#502) — mini pás místo spektra reviewerů (#172).
///
/// **Rozdíl proti spektru je věcný, ne jen v umístění.** Spektrum říkalo, **kdo** nálezy nechal;
/// pás říká, **kde v PR** jsou a **jak zle** — a to je otázka, na kterou se odpovídá dřív, než se
/// PR otevře. V okně tím zůstává jedno kódování: **barva je závažnost**, ať se kreslí v řádku,
/// pod hlavičkou nebo v okraji diffu. Kdo se ptá „odkud ty nálezy jsou“, má runbar po otevření.
///
/// **Kreslí to `PullRequestMapView.drawSegments`, tedy táž funkce jako velký pás** — a data skládá
/// `Policy.pullRequestMap`, tedy táž funkce jako pro velký pás. Odsud je jen geometrie: 110 × 6
/// bodů z návrhu. Dvě kresby nebo dvě skládání by znamenala, že řádek a hlavička téhož PR tvrdí
/// každý něco jiného.
///
/// **Pevná šířka i výška, ne pružná** (#375, #220): řádek fronty je řádek líného seznamu, takže
/// se v něm o rozměr nevyjednává. `Canvas` si o velikost sám neříká, takže by bez rámce vyšel
/// nulový — a `maxWidth: .infinity` by z jednoho pásu udělal pružinu, která se přerovnává s celým
/// oknem.
///
/// Nápověda i odečítání nesou **popisek mapy** (`7 souborů · 3 prošlé · 5 nálezů`), protože barva
/// sama nestačí. Vlákna v něm nejsou, a je to důsledek toho, co se o PR ve frontě ví — viz
/// `AppStore.queueMap(for:)`.
struct QueueMapStrip: View {
    let map: PullRequestMap

    /// Šířka pásu v bodech (návrh, sekce 42 — mini podoba pro řádek fronty).
    ///
    /// **Vejde se i do nejužšího okna**: řádek má vedle pásu titulek a odznak stavu, takže je to
    /// šířka pevná, ne podíl. Že se do 636 bodů (nejužší okno bez railu) vejde všechno, tvrdí
    /// `QueueMapStripTests` měřením, ne odhadem.
    static let width = 110.0
    /// Výška pásu. Nižší než velký pás (10 bodů) — v řádku stojí vedle textu, ne pod hlavičkou.
    /// Výšku řádku fronty přitom **nezvedá**: řádek je vysoký na dvě řádky textu a šest bodů se
    /// do nich vejde. Tvrdí to měřená výška v `QueueMapStripTests`.
    static let height = 6.0
    /// Mezera mezi segmenty, jako u velkého pásu — **a ustupuje stejně** (`Policy.mapSpacing`):
    /// od dvaceti tří souborů padá na nulu, protože ve 110 bodech by z pásu byla tečkovaná linka.
    static let spacing = 2.0

    var body: some View {
        Canvas(opaque: false, rendersAsynchronously: false) { context, size in
            PullRequestMapView.drawSegments(
                in: &context,
                of: map.segments,
                geometry: PullRequestMapGeometry(
                    segments: map.segments,
                    width: size.width,
                    spacing: Self.spacing
                ),
                top: 0,
                height: size.height
            )
        }
        .frame(width: Self.width, height: Self.height)
        // **Jeden prvek, ne segment po segmentu** — tatáž úvaha jako u velkého pásu: per-segment
        // odečítání by ty views muselo postavit, tedy vrátit cenu, kvůli které je pás kresba.
        .accessibilityElement()
        .accessibilityLabel("Mapa souborů")
        .accessibilityValue(map.summary)
        .help(map.summary)
    }
}

#Preview {
    let files = [4, 64, 12, 240, 8, 2790, 30]
    VStack(alignment: .leading, spacing: 12) {
        QueueMapStrip(map: PullRequestMap(
            segments: files.enumerated().map { index, lines in
                PullRequestMapSegment(
                    path: "src/File\(index).php",
                    name: "File\(index).php",
                    changedLines: lines,
                    additions: lines,
                    deletions: 0,
                    marker: index == 3 ? .blocking : (index == 1 ? .findings : nil),
                    isNew: index == 5,
                    readState: index < 2 ? .read(at: Date(timeIntervalSince1970: 1_000_000)) : .unread,
                    findings: index == 3 ? 2 : (index == 1 ? 1 : 0),
                    threads: []
                )
            },
            summary: "7 souborů · 2 prošlé · 3 nálezy"
        ))
    }
    .padding()
}
