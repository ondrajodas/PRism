import SwiftUI

/// Popisek s počty vpravo od pásu mapy PR — a zároveň **cesta k legendě** (#501, varianta A).
///
/// **V řádce nepřibude nic.** Sedm významů (blokuje, nález, nový soubor, bez nálezu, prošlo,
/// vlákno, čtu) se do desetibodové řádky natrvalo nevejde, takže je popisek od #501 tlačítko:
/// tečkované podtržení a `▾` napovídají, že se dá kliknout, a klik otevře popover se všemi sedmi.
/// Zamítnutá varianta B (zkrácená trvalá legenda místo počtů) i C (plná legenda jako druhá řádka
/// chromu) jsou v záznamu rozhodnutí; obojí platí chromem nebo souhrnem, kdežto popover nestojí
/// nic, dokud se neotevře.
///
/// **Cena je zapsaná: kdo neví, že se dá kliknout, legendu nenajde** — a v úzké podobě, kde
/// popisek mizí, k ní cesta není vůbec. Tam ta slova říká nápověda segmentu rovnou
/// (`1 nález · 1 vlákno · neprošlo`).
///
/// **Vlastní view, ne kus těla mapy, a je to výkonová podmínka** — tatáž jako u hoveru a sondy
/// výřezu: `isOpen` je stav, a kdyby ho drželo tělo pásu, přeložilo by se při otevření legendy
/// celé i s kresbou 158 segmentů. Takhle se přeloží jedno tlačítko.
struct PullRequestMapLegendButton: View {
    let summary: String

    @State private var isOpen = false

    /// Co se v řádce **doopravdy nakreslí** — a totéž se měří (`PullRequestMapView.summaryWidth`).
    /// Dvě podoby téhož textu by znamenaly, že práh na skrytí popisku počítá s jinou šířkou, než
    /// jaká je na obrazovce (#236).
    ///
    /// `▾` je v monospace systémovém písmu **glyf 1126**, tedy skutečný znak, ne náhrada z jiného
    /// řezu — doměřeno `CTFontGetGlyphsForCharacters` stejně jako u kapslí zkratek (#441). `⌄`
    /// (U+2304) v něm naopak **není**, proto se nepoužil.
    static func title(of summary: String) -> String { "\(summary) ▾" }

    var body: some View {
        Button {
            isOpen = true
        } label: {
            Text(verbatim: Self.title(of: summary))
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(Palette.ink3)
                // Tečkované podtržení je **jediné**, co o legendě prozrazuje, že tam je
                // (`border-bottom: 1px dotted` ze zákresu).
                .underline(true, pattern: .dot)
        }
        .buttonStyle(.plain)
        .fixedSize()
        .help(Policy.mapLegendTitle)
        // **Popisek se odečítá bez `▾`.** Odvozený z `Text`u by ho VoiceOver přečetl jako „black
        // down-pointing small triangle“ uprostřed počtů; ta šipka je kresba, ne text. Co tlačítko
        // dělá, říká nápověda.
        .accessibilityLabel(Text(verbatim: summary))
        .accessibilityHint(Policy.mapLegendTitle)
        // **Popover visí na nulovém kotvicím view, ne na tlačítku** — a je to změřené rozhodnutí.
        // `.popover` nasazený přímo na tlačítko zdražil **průchod tělem pásu** ze 3,0–4,8 na
        // 7,1–7,3 ms při 158 souborech, tedy skoro dvojnásobně; na nulovém potomkovi
        // v `background`u to bylo 5,1–5,2. Je to tentýž tvar, jaký v řádce už mají `probe`
        // a `shortcuts`. **Podmíněné připojení** (`if isOpen`) je změřené a zamítnuté: nebylo
        // lepší (5,5–7,4 ms) a nese riziko, že se popover v tom průchodu, ve kterém se modifikátor
        // objeví, neotevře. Čísla i mez měřidla jsou v `docs/testovani.md`.
        .background(alignment: .bottom) {
            Color.clear
                .frame(width: 0, height: 0)
                .popover(isPresented: $isOpen, arrowEdge: .bottom) {
                    PullRequestMapLegendPopover()
                }
        }
    }
}

/// Legenda pásu jako popover (#501).
struct PullRequestMapLegendPopover: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(Policy.mapLegendTitle)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Palette.ink3)
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 7) {
                ForEach(Policy.mapLegendRows()) { row in
                    GridRow {
                        ForEach(row.items) { item in
                            entry(item)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func entry(_ item: PullRequestMapLegendItem) -> some View {
        HStack(spacing: 6) {
            swatch(of: item.tone)
            Text(verbatim: item.label)
                .font(.system(size: 11.5))
                .foregroundStyle(Palette.ink2)
        }
        .accessibilityElement(children: .combine)
    }

    /// Vzorek tónu. **Barva i tvar se berou z týchž funkcí, jakými kreslí `Canvas` pásu** — u čárky
    /// a u značky souboru pod výřezem doslova, protože zrovna tam by se rozejití nedalo poznat:
    /// obojí je akcent, jen jinak nakreslený.
    @ViewBuilder private func swatch(of tone: PullRequestMapTone) -> some View {
        switch tone {
        case .blocking, .findings, .clean, .new:
            RoundedRectangle(cornerRadius: 2)
                .fill(PullRequestMapView.fill(of: tone))
                .frame(width: 14, height: 9)
        case .read:
            // Prošlý se tlumí **krytím nad výplní**, ne druhým odstínem — vzorek proto stojí na
            // tónu `clean` a bere tutéž hodnotu krytí, jakou nasazuje kresba.
            RoundedRectangle(cornerRadius: 2)
                .fill(PullRequestMapView.fill(of: .clean))
                .opacity(Policy.mapReadOpacity)
                .frame(width: 14, height: 9)
        case .thread:
            Canvas(opaque: false, rendersAsynchronously: false) { context, size in
                PullRequestMapView.drawTick(
                    in: &context,
                    at: 0.5,
                    in: CGRect(x: 0, y: 4, width: size.width, height: size.height - 8)
                )
            }
            .frame(width: 8, height: 14)
        case .current:
            Canvas(opaque: false, rendersAsynchronously: false) { context, size in
                PullRequestMapView.drawOutline(
                    in: &context,
                    around: CGRect(x: 5, y: 5, width: size.width - 10, height: PullRequestMapView.stripHeight)
                )
            }
            // **Vzorek má proporci pásu** (10 bodů na výšku), ne zmenšenou: obrys má odstup
            // dva až čtyři body a poloměr čtyři, takže na šestibodovém obdélníku by z něj byla
            // pilulka — a to už není ten tvar, který je v pásu.
            .frame(width: 22, height: 20)
        }
    }
}
