import SwiftUI

/// Tab `Zeptat se` (#452) — rozhovor s Claudem nad tímhle pull requestem.
///
/// **Rozhovor, ne jednorázový dotaz.** Druhá otázka navazuje na první, protože je to jedna
/// session na PR držená přes `--resume`; bez toho by se každá otázka ptala znovu na všechno
/// a odpovědi by si protiřečily.
///
/// **Pevný `VStack`, ne líný seznam**, a je to vědomé rozhodnutí podle pravidla z `CLAUDE.md`:
/// líný seznam patří tam, kde je seznam **neomezený** (diff — tisíce řádků). Rozhovor má strop
/// o řád níž než osa konverzace, která od #361 líný seznam nemá vůbec: osa jich má nejvýš čtyři
/// stovky (`ConversationQuery` se ptá `first: 100` na čtyři seznamy), kdežto tady je každá
/// položka **zaplacená session**, takže pár desítek zpráv je hodně.
///
/// **Změřeno, ne odvozeno** (`AskLogMeasurement`, Debug, v okně): první rozvržení stojí 18 ms
/// u dvaceti bublin, 87 ms u stovky a 242 ms u tří set — proti plochým 4,6 ms u líného seznamu
/// a proti 413 ms, které #361 naměřilo u tří set uzlů osy a **se kterými se u ní pevný stack
/// přijal**. Při reálném počtu otázek je to tedy pod dvacet milisekund jednou při otevření tabu,
/// a za to se nekreslí kolo `updateItemPhases` → `propagate_dirty`, kvůli kterému #361 líný seznam
/// z osy vyhodilo.
struct AskView: View {
    let content: AskTabContent
    /// Chipy `ví o tomhle PR:`.
    var chips: [AskContextChip] = []
    /// Co session zrovna dělá — řádek u prstýnku.
    var activity: String = ""
    var draft: String = ""
    /// Proč se zeptat nedá. `nil` = dá se.
    var block: String?
    /// Uloží rozepsanou otázku do zálohy pro přepnutí tabu.
    var persistDraft: (String) -> Void = { _ in }
    /// Odešle otázku a řekne, jestli odešla. Jednou cestou pro pole i pro nabízenou otázku —
    /// dvě by znamenaly dvě místa, kde se rozhoduje, co se pošle.
    var send: (String) -> Bool = { _ in false }
    /// Zastaví běžící odpověď. `nil` = zastavit se nedá (náhledy a testy skládání).
    var cancel: (() -> Void)?
    /// Zahodí rozhovor i session. `nil` = `Nový rozhovor` se nekreslí (náhledy a testy skládání).
    var reset: (() -> Void)?
    /// Kam se dá skočit z odpovědi. `nil` = odkazy se nekreslí.
    var jump: ((AskReference) -> Void)?

    @State private var isConfirmingReset = false

    var body: some View {
        let _ = RenderDiagnostics.pass(Self.self)
        VStack(spacing: 0) {
            contextBar
            Rectangle().fill(Palette.lineSoft).frame(height: 1)
            log
                .fillingSlot()
            AskComposer(
                draft: draft,
                block: block,
                isAnswering: isAnswering,
                persist: persistDraft,
                send: send,
                cancel: cancel
            )
        }
        .confirmationDialog(
            "Začít nový rozhovor?",
            isPresented: $isConfirmingReset,
            titleVisibility: .visible
        ) {
            Button("Začít znovu", role: .destructive) { reset?() }
            Button("Zpět", role: .cancel) {}
        } message: {
            Text(verbatim: "Otázky i odpovědi se smažou a příští otázka se ptá načisto. Zpátky to nejde a zaplatí se znovu.")
        }
    }

    // MARK: - Lišta

    /// `ví o tomhle PR:` — výčet toho, co aplikace do promptu **doopravdy dá**.
    ///
    /// Říká se to **nahoře a jednou**: jinak by se to muselo psát do každé otázky. A vpravo stojí
    /// `čte · neodesílá`, tedy práva session — **v okně, ne jen v dokumentaci**. Práva, o kterých
    /// ví jenom `CLAUDE.md`, uživateli neřeknou nic.
    private var contextBar: some View {
        HStack(spacing: 9) {
            // **Ne mono.** Kapsle `čte · neodesílá` mono je (`.pill`), ale tenhle popisek v návrhu
            // žádnou vlastní sazbu nemá — dědí písmo okolí, takže se sází jako věta, ne jako údaj.
            Text(verbatim: "ví o tomhle PR:")
                .font(.system(size: 11.5))
                .foregroundStyle(Palette.ink2)
            FlowRow(spacing: 7, lineSpacing: 5) {
                ForEach(chips) { chip in contextChip(chip) }
            }
            Spacer(minLength: 8)
            Text(verbatim: "čte · neodesílá")
                .designPill(tint: Palette.ink2, background: Palette.raised)
                .help("Session čte kód ve své kopii repa. Na GitHub odeslat nic neumí.")
            resetButton
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.chrome)
    }

    /// `Nový rozhovor` — tiché tlačítko vedle kapsle, ne akcentované: je to úklid, ne hlavní
    /// akce.
    ///
    /// **V prázdném tabu se nekreslí vůbec**, ne zašedle (`AskTabContent.offersReset`): zašedlé
    /// tlačítko tvrdí „tady se to dělá, jen teď ne“, kdežto tady prostě není co zahodit. Zašedlá
    /// s důvodem patří jinam — tam, kde je vypnutá brána.
    ///
    /// **Ptá se**, ačkoli se v tomhle okně skoro nic nepotvrzuje: odpověď stála kolem dolaru
    /// a smazaný rozhovor se nedá vrátit ani zopakovat za stejné peníze. Tatáž úvaha jako
    /// u zakládání labelu (#413) — potvrzuje se to, co je **nevratné**, ne to, co je důležité.
    @ViewBuilder private var resetButton: some View {
        if content.offersReset, reset != nil {
            Button("Nový rozhovor") { isConfirmingReset = true }
                .buttonStyle(.mini)
                .help("Zahodí rozhovor i navázanou session. Příští otázka se ptá načisto.")
        }
    }

    /// Jeden chip (`.rchip`). Puntík má **jen** ten s blokujícím nálezem — u počtu komentářů by
    /// z údaje o množství udělal upozornění.
    private func contextChip(_ chip: AskContextChip) -> some View {
        HStack(spacing: 6) {
            if chip.isBlocking {
                Circle().fill(Palette.crit).frame(width: 7, height: 7)
            }
            Text(verbatim: chip.label)
                .font(.system(size: 11.5))
                .foregroundStyle(Palette.ink2)
        }
        .padding(.leading, chip.isBlocking ? 7 : 9)
        .padding(.trailing, 9)
        .padding(.vertical, 3)
        .background(Palette.raised, in: .capsule)
        .overlay(Capsule().stroke(Palette.line, lineWidth: 1))
    }

    // MARK: - Rozhovor

    @ViewBuilder private var log: some View {
        switch content {
        case .empty(let tips): ScrollView { emptyState(tips) }
        case .thread(let messages, let isAnswering): thread(messages, isAnswering: isAnswering)
        }
    }

    private func thread(_ messages: [AskMessage], isAnswering: Bool) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(messages) { message in
                        AskBubbleView(message: message, jump: jump).id(message.id)
                    }
                    if isAnswering { answering.id(Self.answeringAnchor) }
                }
                .padding(16)
                .filling(alignment: .leading)
            }
            // Nová bublina se má ukázat, ne zůstat pod hranou. Posun jde **o průchod později**
            // (#325): ve stejném průchodu, ve kterém obsah narostl, ho SwiftUI zahodí.
            .onChange(of: messages.count) { _, _ in
                Task { proxy.scrollTo(messages.last?.id, anchor: .bottom) }
            }
            .onChange(of: isAnswering) { _, running in
                guard running else { return }
                Task { proxy.scrollTo(Self.answeringAnchor, anchor: .bottom) }
            }
        }
    }

    /// Kotva prstýnku. Vlastní konstanta, protože se na ni odkazuje kresba i posun scrollu —
    /// dva literály téhož by se rozešly a posun by tiše přestal fungovat.
    private static let answeringAnchor = "ask-answering"

    /// Že se zrovna odpovídá, nese **prstýnek na místě příští bubliny**, ne pruh nad plochou:
    /// odpověď přijde sem, tak ať je vidět, kde na ni čekat.
    private var answering: some View {
        HStack(spacing: 6) {
            AskAvatar()
            SpinningRing()
            Text(verbatim: activity)
                .font(.system(size: 11))
                .foregroundStyle(Palette.ink3)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("odpovídá — \(activity)")
    }

    /// Prázdná plocha by u rozhovoru znamenala „a co se mám ptát“. Místo ní otázky
    /// k odpíchnutí — a **klik je rovnou odešle**, protože jedno kliknutí je celý jejich smysl.
    ///
    /// Do prvního proklikání otázku jen předvyplnily do pole; zahodilo se to, protože
    /// předvyplněná otázka chce druhý klik na tomtéž místě, kde měl stačit první. Přepsat se dá
    /// pořád — píše se do pole pod tím. Které otázky se nabízejí, rozhoduje `Policy.askTips` podle
    /// toho, co na PR doopravdy je.
    private func emptyState(_ tips: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(verbatim: "Zatím ses na nic neptal. Třeba:")
                .font(.system(size: 12.5))
                .foregroundStyle(Palette.ink2)
            ForEach(tips, id: \.self) { tip in
                // Výsledek se zahazuje schválně: `false` znamená „neodešlo“ a composer podle něj
                // nechává text v poli — tady se ale žádný text nezadával, takže není co nechávat.
                // A stav, ve kterém by odeslání odmítlo, se sem nakreslit nedá: nabídka je jedině
                // v prázdném tabu (`AskTabContent.empty`), kde nic neběží.
                Button { _ = send(tip) } label: {
                    Text(verbatim: tip)
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.ink2)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 5)
                        .overlay(
                            Capsule().strokeBorder(
                                Palette.line,
                                style: StrokeStyle(lineWidth: 1, dash: [3, 3])
                            )
                        )
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .help("Zeptá se na tohle. Spustí session nad kopií tohohle PR.")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 18)
        .filling(alignment: .leading)
    }

    private var isAnswering: Bool {
        if case .thread(_, let isAnswering) = content { return isAnswering }
        return false
    }
}
