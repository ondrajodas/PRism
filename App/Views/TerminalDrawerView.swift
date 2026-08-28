import AppKit
import SwiftUI

/// Zásuvka s terminálem přes spodek záložky PR (#459) — návrh, sekce 35.
///
/// **Zásuvka, ne devátá záložka**, a je to celý smysl: půlka užitku je vidět diff a **pod ním**
/// výstup příkazu. Záložka by diff schovala a udělala z terminálu druhé okno, do kterého se stejně
/// přepíná.
///
/// **Relací drží víc a přepíná se mezi nimi záložkami** (#460): aplikace pouští review paralelně,
/// takže jeden shell nutil jednu session ukončit, aby byla vidět druhá. Které to jsou a co je na
/// nich napsané, skládá `Policy` (`terminalSlotRows`) — tohle view z toho jen kreslí.
///
/// Rozměr se **předává, nevyjednává** (#220): výška je spočítaná (`Policy.terminalDrawerHeight`)
/// a šířku dostane plocha od rodiče. Pružná výška by tady byla obzvlášť drahá — plocha terminálu si
/// z ní počítá řádky a každé přeměření znamená `TIOCSWINSZ` a překreslení celého TUI.
struct TerminalDrawerView: View {
    /// Relace v přepínači, v pořadí vzniku. Skládá je `Policy`, ne tohle view.
    let rows: [TerminalSlotRow]
    /// Která relace je vidět. `nil` = zásuvka žádnou nemá.
    let activeSlot: TerminalSlot?
    /// Adresář, ve kterém shell té relace stojí. `nil` = v cache pro ni nic není.
    let directory: URL?
    /// Kdo drží plochu. `nil` znamená, že se zásuvka nekreslí — v testech, kde terminál není.
    let host: (any TerminalHosting)?
    /// Kolik místa má detail PR celkem — z něj je strop výšky.
    let available: CGFloat
    let select: (TerminalSlot) -> Void
    let close: () -> Void

    /// Výška, kterou si člověk natáhl. **Přežívá restart** — je to údaj o tom, kolik místa terminál
    /// v téhle práci potřebuje, a znovunatahovat ho po každém spuštění je přesně ta drobnost, kvůli
    /// které se funkce přestane používat. Nula = nic uloženého, viz `Policy.terminalDrawerHeight`.
    @AppStorage("terminalDrawerHeight") private var storedHeight = 0.0

    /// Výška na začátku tažení. `nil` = zrovna se netáhne.
    ///
    /// Drží se **mimo `storedHeight`**, aby tažení nesahalo na disk po každém pixelu: zapisuje se
    /// jednou, na konci tahu.
    @State private var dragOrigin: CGFloat?

    /// Kde zásuvka právě stojí. Během tažení je to průběžná hodnota, jinak ta uložená.
    @State private var draggedHeight: CGFloat?

    private var height: CGFloat {
        draggedHeight ?? Policy.terminalDrawerHeight(stored: storedHeight, available: available)
    }

    var body: some View {
        VStack(spacing: 0) {
            resizeHandle
            bar
            surface
        }
        .frame(height: height)
        // `--bg`, ne `--panel`: terminál není další panel okna, je to cizí plocha uvnitř něj —
        // a ta se má od chromu odlišit (komentář u `.term` v návrhu).
        .background(Palette.background)
        .overlay(alignment: .top) { Rectangle().fill(Palette.line).frame(height: 1) }
    }

    // MARK: - Tažení za horní hranu

    /// Proužek, za který se zásuvka roztahuje.
    ///
    /// **Vlastní plocha nad hlavičkou, ne gesto na celé hlavičce**: v hlavičce je tlačítko
    /// a kapsle, a gesto přes ně by znamenalo, že se klik na `⌄` někdy vyhodnotí jako tažení.
    /// Čtyři body jsou tolik, kolik má trvalý dělič v okně; kurzor se u nich mění, takže se dá
    /// najít.
    private var resizeHandle: some View {
        Color.clear
            .frame(height: 4)
            .contentShape(.rect)
            // **`pointerStyle`, ne `NSCursor.push()`/`pop()`.** Ta dvojice se rozváže, jakmile view
            // zmizí, zatímco je myš nad ním — a zásuvka se schovává klávesou, takže se to stane při
            // `` ⌃` `` s kurzorem na proužku. Zbyl by na obrazovce šipkový kurzor pro roztahování
            // nad něčím, co roztáhnout nejde. Cíl je macOS 26, takže tenhle modifikátor je
            // k dispozici a stav si řídí SwiftUI.
            .pointerStyle(.frameResize(position: .top))
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        let origin = dragOrigin ?? height
                        dragOrigin = origin
                        draggedHeight = Policy.terminalDrawerResize(
                            from: origin,
                            by: value.translation.height,
                            available: available
                        )
                    }
                    .onEnded { _ in
                        dragOrigin = nil
                        defer {
                            // **Průběžná výška se zahazuje**, ne nechává ležet: od téhle chvíle
                            // rozhoduje uložená hodnota, a ta se ořezává proti oknu. Kdyby tu
                            // zůstala hodnota z tahu, zmenšení okna by ji nikdy nedorovnalo
                            // a zásuvka by vytlačila obsah nad sebou.
                            draggedHeight = nil
                        }
                        guard let draggedHeight,
                            let stored = Policy.terminalDrawerStoredHeight(
                                stored: storedHeight,
                                measured: draggedHeight
                            )
                        else { return }
                        storedHeight = stored
                    }
            )
            .accessibilityHidden(true)
    }

    // MARK: - Hlavička

    /// `.term-bar` z návrhu: **přepínač relací**, cesta, kapsle a vpravo zkratka s tlačítkem
    /// na zavření.
    ///
    /// Do #460 tu stálo jméno `Terminál` a vpravo kapsle `běží` / `skončil (kód)`. Obojí nahradil
    /// přepínač: relací je víc, takže „která z nich běží“ se ptá u každé zvlášť — a jméno
    /// `Terminál` vedle záložek nic nepřidávalo.
    private var bar: some View {
        HStack(spacing: 9) {
            switcher
            if let directory {
                Text(verbatim: Policy.terminalDirectoryLabel(directory, home: Self.home))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Palette.ink3)
                    .lineLimit(1)
                    // **Zkracuje se zepředu** a od #460 to není kosmetika: přepínač si vzal místo,
                    // takže z cesty zbude konec — a ten je ta odpovídající půlka (`vault/85`).
                    .truncationMode(.head)
                    .help(directory.path(percentEncoded: false))
            }
            // **Kapsle říká pravdu o téhle ploše, ne o aplikaci** (návrh, poznámka 109): odsud jde
            // všechno, co jde z terminálu — `git push` i `gh pr merge`. Je to protějšek
            // `čte · neodesílá` v tabu `Zeptat se` a jediné místo, kde je změna tvrdé podmínky č. 1
            // vidět na obrazovce, ne jen v dokumentaci.
            //
            // **Bez adresáře se nekreslí**: bez pracovní kopie žádný shell není, takže by kapsle
            // mluvila o právech plochy, která tam není — a text, který tvrdí víc, než co data
            // unesou, je v tomhle okně chyba, ne ozdoba.
            if directory != nil {
                Text(verbatim: "plná práva")
                    .designPill(tint: Palette.crit, background: Palette.crit.opacity(0.15))
                    .help("Co se pustí odsud, běží pod tvým účtem a s tvým `gh` — aplikace to nijak neomezuje.")
            }
            Spacer(minLength: 8)
            Text(verbatim: Policy.windowShortcut(.toggleTerminal).display)
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(Palette.ink3)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .overlay { RoundedRectangle(cornerRadius: 5).strokeBorder(Palette.line, lineWidth: 1) }
            HeaderButton(
                symbol: "chevron.down",
                label: "Schovat terminál",
                help: Policy.shortcutHelp("Schovat terminál (shelly běží dál)", .toggleTerminal),
                action: close
            )
        }
        .font(.system(size: 11.5))
        .foregroundStyle(Palette.ink2)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.chrome)
        .overlay(alignment: .bottom) { Rectangle().fill(Palette.lineSoft).frame(height: 1) }
    }

    /// `.term-tabs` z návrhu — **záložky, ne rozbalovací nabídka**.
    ///
    /// Relace jsou dvě až tři a pořád jedna běží, takže nabídka by po každém pohledu na druhou
    /// stála dva kliky místo jednoho (návrh, sekce 35).
    private var switcher: some View {
        HStack(spacing: 3) {
            ForEach(rows) { row in
                Button { select(row.slot) } label: { tab(row) }
                    .buttonStyle(.plain)
                    .help(row.help)
                    .accessibilityLabel(row.help)
            }
        }
    }

    /// `.term-tab` — puntík a jméno relace.
    private func tab(_ row: TerminalSlotRow) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Self.markTint(row.mark))
                .frame(width: 6, height: 6)
            // Jméno dráhy se **nezalamuje**: přepínač je jeden řádek v hlavičce, takže druhá
            // řádka by zásuvce sebrala výšku, kterou si člověk natáhl na obsah.
            Text(verbatim: row.title)
                .lineLimit(1)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 2)
        .foregroundStyle(row.isActive ? Palette.ink : Palette.ink3)
        .background(row.isActive ? Palette.raised : .clear, in: .rect(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(row.isActive ? Palette.line : .clear, lineWidth: 1)
        }
    }

    /// Barva puntíku. **Tři, i když návrh kreslí dvě** — zdůvodnění je u `TerminalSlotMark`.
    private static func markTint(_ mark: TerminalSlotMark) -> Color {
        switch mark {
        case .running: Palette.accent
        case .failed: Palette.crit
        case .idle: Palette.ink3
        }
    }

    // MARK: - Plocha

    @ViewBuilder private var surface: some View {
        if let directory, let host, let activeSlot {
            TerminalSurface(slot: activeSlot, directory: directory, host: host)
                // **`id` na relaci je podmínka, ne optimalizace** (#460): bez ní by SwiftUI po
                // přepnutí záložky nechal v hierarchii plochu předchozí relace, protože
                // `makeNSView` se volá jen při vzniku representable. Se změněnou identitou se
                // representable postaví znovu a hostitel vydá plochu té nové relace; ta stará
                // zůstane u něj a shell v ní běží dál.
                .id(activeSlot)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // `.term-body { padding: 10px 12px }` z návrhu. Emulátor sám kreslí od `0,0`, takže
                // bez toho lepí první znak na hranu okna — a přesně o ten odstup se v návrhu jedná.
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
        } else {
            missingCheckout
        }
    }

    /// Co se ukáže, když v cache není ani pracovní strom, ani klon.
    ///
    /// **Vysvětlení, ne prázdná plocha.** Zásuvka se v tom stavu nemá „nechovat“, protože terminál
    /// bez repozitáře je obyčejný shell — ten má člověk vedle a smysl mu dává až to, že startuje
    /// v tom kódu, na který se dívá (návrh, sekce 35).
    private var missingCheckout: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: "Tenhle pull request nemá v cache pracovní kopii.")
                .foregroundStyle(Palette.ink2)
            Text(verbatim: "Shell nemá kde začít — pusť na PR review, nebo si připrav kopii repa.")
                .foregroundStyle(Palette.ink3)
        }
        .font(.system(size: 11.5))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    /// Domov pro zkrácení cesty na `~`. Čte se jednou — v běžící aplikaci se nemění.
    private static let home = URL(filePath: NSHomeDirectory())
}

/// Plocha emulátoru ve SwiftUI stromu.
///
/// **Plochu vlastní `TerminalHost`, ne tenhle typ**, a je to podmínka: `makeNSView` se volá při
/// každém složení stromu, takže vlastní plocha by znamenala nový shell po každém zavření
/// a otevření zásuvky.
private struct TerminalSurface: NSViewRepresentable {
    let slot: TerminalSlot
    let directory: URL
    let host: any TerminalHosting

    func makeNSView(context: Context) -> NSView {
        host.terminal(for: slot, in: directory)
    }

    /// **Prázdné schválně.** Plocha si všechno řídí sama: velikost dostane rozvržením (a přepošle ji
    /// jako `TIOCSWINSZ`), barvy si přenastaví na změnu vzhledu a obsah jí teče z pty. Nic z toho
    /// nejde ze SwiftUI stavu, takže by tu byl zápis, který se při každém přepočtu geometrie
    /// zopakuje pro nic — přesně ta třída, kterou popisuje #393.
    func updateNSView(_ view: NSView, context: Context) {}
}
