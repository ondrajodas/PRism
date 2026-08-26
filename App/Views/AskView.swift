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
/// **Změřeno, ne odvozeno** (`AskLogMeasurement`, Debug): první rozvržení stojí 24 ms u dvaceti
/// bublin, 88 ms u stovky a 260 ms u tří set — proti 410 ms, které #361 naměřilo u tří set uzlů
/// osy. Při reálném počtu otázek je to tedy pod třicet milisekund jednou při otevření tabu, a za
/// to se nekreslí kolo `updateItemPhases` → `propagate_dirty`, kvůli kterému #361 líný seznam
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
    var setDraft: (String) -> Void = { _ in }
    var send: () -> Void = {}
    var useTip: (String) -> Void = { _ in }
    /// Zastaví běžící odpověď. `nil` = zastavit se nedá (náhledy a testy skládání).
    var cancel: (() -> Void)?
    /// Kam se dá skočit z odpovědi. `nil` = odkazy se nekreslí.
    var jump: ((AskReference) -> Void)?

    var body: some View {
        let _ = RenderDiagnostics.pass(Self.self)
        VStack(spacing: 0) {
            contextBar
            Rectangle().fill(Palette.lineSoft).frame(height: 1)
            log
                .fillingSlot()
            composer
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
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.chrome)
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

    /// Prázdná plocha by u rozhovoru znamenala „a co se mám ptát“. Místo ní tři otázky
    /// k odpíchnutí — obyčejná tlačítka, která **jen předvyplní pole**, takže se dají přepsat.
    private func emptyState(_ tips: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(verbatim: "Zatím ses na nic neptal. Třeba:")
                .font(.system(size: 12.5))
                .foregroundStyle(Palette.ink2)
            ForEach(tips, id: \.self) { tip in
                Button { useTip(tip) } label: {
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
                .help("Vloží otázku do pole — dá se přepsat.")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 18)
        .filling(alignment: .leading)
    }

    // MARK: - Composer

    /// Pole a odesílací tlačítko na spodní hraně tabu (`.composer`).
    ///
    /// Věta u pole říká, co session smí — je to totéž tvrzení jako kapsle v liště, jen slovy,
    /// a stojí tam, kde se rozhoduje o odeslání otázky.
    private var composer: some View {
        VStack(alignment: .leading, spacing: 9) {
            DraftTextEditor(
                text: draft,
                placeholder: "Zeptej se na cokoli v tomhle PR…",
                minHeight: 46,
                maxHeight: 46,
                commit: setDraft
            )
            .disabled(block != nil)
            controls
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.chrome)
        .overlay(alignment: .top) { Rectangle().fill(Palette.line).frame(height: 1) }
    }

    private var controls: some View {
        HStack(spacing: 9) {
            Text(verbatim: "Čte kód ve své kopii repa. Odeslat na GitHub neumí.")
                .font(.system(size: 11))
                .foregroundStyle(Palette.ink3)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            // **Kreslená kapsle, ne `keyboardShortcut`.** Klávesu bere `Button` níž
            // (`.defaultAction`), takže by druhá registrace téže kombinace byla ta past
            // z #151 a #184 — v tomhle tabu je `⌘⏎` navíc **zakázané** zkratce okna
            // (`Policy.claimsReturnShortcut`), aby se sem propadlo.
            // A **jen když tu klávesu doopravdy někdo bere** — vedle `Zastavit` by kapsle
            // tvrdila zkratku, která v tu chvíli nic nedělá.
            if !isAnswering {
                Text(verbatim: "⌘⏎")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Palette.ink3)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Palette.raised, in: .rect(cornerRadius: 5))
                    .accessibilityHidden(true)
            }
            // **Během odpovědi se z tlačítka stane `Zastavit`.** Jedna odpověď stojí kolem
            // dolaru a běží minuty (změřeno, viz `docs/claude-cli.md`), takže „rozmyslel jsem si
            // to“ nesmí znamenat čekat na konec — a zakázané `Zeptat se` vedle prstýnku je
            // tlačítko, které v tu chvíli nedělá nic. Je to **tentýž ovládací prvek v jiném
            // stavu**, ne druhé tlačítko: dvě vedle sebe by v úzkém composeru braly místo
            // a jedno z nich by bylo vždycky zakázané.
            if isAnswering, let cancel {
                Button("Zastavit") { cancel() }
                    .buttonStyle(.bordered)
                    .font(.system(size: 12.5))
                    .help("Zabije běžící session. Otázka v rozhovoru zůstane.")
            } else {
                Button("Zeptat se") { send() }
                    .buttonStyle(.borderedProminent)
                    .font(.system(size: 12.5))
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(!canSend)
                    .help(sendHelp)
            }
        }
    }

    private var canSend: Bool {
        block == nil && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isAnswering
    }

    private var isAnswering: Bool {
        if case .thread(_, let isAnswering) = content { return isAnswering }
        return false
    }

    private var sendHelp: String {
        if let block { return block }
        if isAnswering { return "Počkej na odpověď — v jednom rozhovoru běží jedna session." }
        if draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Napiš otázku."
        }
        return "Spustí session nad kopií tohohle PR. Čte kód, nic neodesílá."
    }
}
