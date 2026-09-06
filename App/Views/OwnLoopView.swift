import SwiftUI

/// Dráha smyčky vlastního PR pod hlavičkou (#508, návrh sekce 52).
///
/// **Tytéž třídy jako dráha reviewera** (`.lane`, `.phases`, `.ph`): rám s okrajem, hlavička,
/// pět kapslí vedle sebe a věta pod nimi. Kapsli kreslí `LanePhaseChip`, tedy **týž** prvek jako
/// v tabu `Průběh` — kdyby si tahle dráha mapovala stav na barvu sama, byl by to druhý slovník
/// pro totéž a rozešel by se první den, kdy někdo změní odstín.
///
/// **Nekreslí obsah stanic.** Panel `Zadání` (#334) i sekce `Větev` (#465, #466) zůstávají tam,
/// kde jsou; dráha říká, **kde v kole jsem**, a jediná akce aktivní stanice do toho místa
/// **odkáže**. Kdyby akce odesílala sama, byla by to druhá cesta ven (tvrdá podmínka č. 1)
/// a druhé místo, které skládá plán merge.
///
/// **Stanice `Agent` a `Merge` na dráze nejsou** (#508, čtvrté kolo). Ani jedna z nich v okně
/// nikdy nic neukázala — `Agent` nemá živý obsah a `Merge` stojí na celém kole —, takže z nich
/// byly jen užší kapsle pro ostatních pět. Merge se dál dělá ze sekce `Větev` (#465), agenta má
/// dodat #511.
struct OwnLoopView: View {
    let loop: OwnLoop
    /// Co udělá jediná akce aktivní stanice. `nil` = akce se nekreslí — buď žádná není
    /// (`OwnLoop.move`), nebo ji hostitel nedokáže obsloužit.
    var perform: ((OwnLoop.Move) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            phases
            Text(verbatim: loop.last)
                .font(.callout)
                .foregroundStyle(Palette.ink2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
        }
        .background(Palette.surface)
        .clipShape(.rect(cornerRadius: 7))
        .overlay {
            RoundedRectangle(cornerRadius: 7).strokeBorder(Palette.line, lineWidth: 1)
        }
    }

    /// Hlavička: jméno dráhy, razítko předání a jediná akce.
    ///
    /// Razítko se kreslí **jen když nějaké je** — `nepředáno` by v hlavičce zabíralo místo větou,
    /// kterou o řádek níž říká kapsle `Zadání` přesněji.
    private var header: some View {
        HStack(spacing: 9) {
            Text("smyčka")
                .font(.system(.callout, design: .monospaced).weight(.semibold))
                .lineLimit(1)
                .help(
                    "Kde vlastní pull request stojí v kole "
                        + "Nálezy → Zadání → Push → CI → Review."
                )
            if let stamp = loop.stamp {
                Text(verbatim: stamp)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Palette.ink3)
                    .lineLimit(1)
                    .help("Kolik položek se agentovi předalo a proti jaké hlavě PR to bylo (#334).")
            }
            Spacer(minLength: 8)
            action
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    /// Jediná akce aktivní stanice. **Jedna, ne řada** — dráha je rozcestník, ne panel nástrojů;
    /// co se dá s pull requestem dělat jinak, bydlí dál tam, kde to bydlelo.
    ///
    /// **Malá, ne akcentová, a je to změřené na obrazovce** (#508): `Spustit review` v hlavičce je
    /// od #218 **jediné akcentové místo** v celém pruhu, a druhé tlačítko té velikosti o pár bodů
    /// níž z něj udělalo semafor (vidět na screenshotu z prvního kola). Velikost drží
    /// `controlSize(.small)`, ne `font(.caption)`: `bordered` si metriku bere z control size
    /// a samotné písmo tlačítko nezmenší.
    @ViewBuilder private var action: some View {
        if let move = loop.move, let perform {
            Button(move.title, systemImage: move.symbol) { perform(move) }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
    }

    /// Kreslí se akce? **Pojmenované rozhodnutí, ne `if` v `body`** — v hostované hierarchii se
    /// SwiftUI `Button` nedá najít (`NSButton` v ní není, změřeno u #508), takže je to jediné
    /// místo, nad kterým se to dá tvrdit. Tentýž vzor jako `PullRequestRow.showsPromptAction`
    /// (#333): tlačítko **bez akce** se nekreslí, protože prvek, který nic nedělá, je zrovna ten
    /// stav, ve kterém člověk hledá, co je rozbité.
    var showsAction: Bool { loop.move != nil && perform != nil }

    /// Pět kapslí **rovným dílem**: na rozdíl od dráhy reviewera, kde `prochází kód` bere víc
    /// místa, tady žádná stanice netrvá déle než ostatní — dráha je pořadí, ne rozpočet času.
    /// Šířku dělí `ProportionalColumns`, aby se nevyjednávala na každé úrovni (#220).
    private var phases: some View {
        ProportionalColumns(ratios: loop.stations.map { _ in 1 }, spacing: 3) {
            ForEach(loop.stations, id: \.station) { stop in
                LanePhaseChip(title: stop.station.title, detail: stop.detail, state: stop.state)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 9)
    }
}

#Preview {
    let stations: [OwnLoop.Stop] = [
        OwnLoop.Stop(station: .findings, state: .done, detail: "3 nálezy"),
        OwnLoop.Stop(station: .handoff, state: .running, detail: "2 k předání"),
        // Za zastávkou: zelené, co je hotové, a **jedno slovo** u toho, co není (#508).
        OwnLoop.Stop(station: .push, state: .idle, detail: "pozadu"),
        OwnLoop.Stop(station: .ci, state: .done, detail: "zeleno"),
        OwnLoop.Stop(station: .review, state: .done, detail: "schváleno"),
    ]
    return OwnLoopView(
        loop: OwnLoop(
            stations: stations,
            active: .handoff,
            last: "Od předání přibyly 2 položky.",
            move: .openHandoff,
            stamp: "předáno 6 položek · proti 9c1de02"
        ),
        perform: { _ in }
    )
    .padding()
    .frame(width: 760)
}
