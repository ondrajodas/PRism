import SwiftUI

/// Diff v plné šířce: soubory pod sebou, hlavička souboru se při scrollu drží nahoře.
///
/// Skládá se líně (`LazyVStack`) — diff o tisících řádků je běžný a vykreslit ho celý
/// naráz by okno na chvíli položilo.
struct DiffView: View {
    let diff: Diff
    /// Kam odscrollovat. Nastaví ho panel nálezů; po skoku se vrací na `nil`, aby šlo
    /// na totéž místo skočit i podruhé.
    @Binding var scrollTarget: String?
    /// Rozbalování kontextu. Bere se ze store, ne z vlastního stavu — jinak by rozbalení
    /// přeteklo z jednoho pull requestu na druhý.
    let expansion: DiffExpansionActions
    /// Sbalování celých souborů. Taky ze store, ze stejného důvodu jako `expansion`.
    let folding: DiffFoldingActions
    /// Nálezy k zavěšení pod řádky. Seskupené podle místa už volajícím.
    var findings: [FindingGroup] = []
    var blockingCategories: Set<String> = Policy.defaultBlockingCategories
    /// Místo, na které se právě skočilo z tabulky nálezů.
    var highlighted: FindingHighlight?
    /// Vlákna konverzace, která mají v tomhle diffu kotvu. Vybral je volající
    /// (`Policy.threadsInTheDiff`) — zastaralá patří do `Overview`, ne sem.
    var threads: [ReviewThread] = []
    /// Kolik vláken se do stránky konverzace nevešlo. Nula u běžného PR — sto vláken je
    /// řádově víc, než kolik jich vzniká.
    var missingThreads = 0
    var viewer: String = ""
    var isThreadExpanded: (ReviewThread) -> Bool = { _ in true }
    var toggleThread: (ReviewThread) -> Void = { _ in }
    /// Moje rozdělané komentáře. Kreslí se ty, které v diffu mají kotvu — celý seznam je
    /// v panelu, takže se komentář na zmizelém řádku neztratí.
    var comments: [ReviewDraftComment] = []
    var draft = DraftActions()

    /// Předvolba pohledu napříč pull requesty, takže patří do `UserDefaults`, ne do store.
    @AppStorage("showFindingBubbles") private var showBubbles = true
    @State private var isPickingFile = false

    var body: some View {
        ScrollViewReader { proxy in
            VStack(alignment: .leading, spacing: 0) {
                summary(jumpingWith: proxy)
                Divider()
                files
            }
            // Doprostřed, ne na vrch: bublina visí **pod** svým řádkem, takže u horní hrany
            // by bylo vidět jen ji a kód nad ní ne. Ukotvená hlavička souboru navíc vršek
            // překrývá, takže by řádek scrollnutý „na vrch“ skončil pod ní.
            .onChange(of: scrollTarget) { _, target in
                guard let target else { return }
                withAnimation { proxy.scrollTo(target, anchor: .center) }
                scrollTarget = nil
            }
        }
    }

    /// Každý **řádek** je vlastní buňka líného seznamu, ne každý hunk. Hunk jako celek
    /// se po změně šířky okna překresloval jen zčásti a v diffu zůstávala prázdná místa.
    private var files: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                ForEach(diff.files) { file in
                    Section {
                        // Sbalený soubor se nevykresluje vůbec — u padesátisouborového PR
                        // je to hlavní důvod, proč se sbaluje. Hlavička zůstává, takže
                        // sekce nezmizí a skok na soubor pořád funguje.
                        if !folding.isFolded(file) {
                            rows(of: file)
                        }
                    } header: {
                        fileHeader(file)
                    }
                    .id(file.id)
                }
            }
        }
    }

    private func rows(of file: FileDiff) -> some View {
        let state = expansion.state(file)
        let language = Language(path: file.displayPath)
        let rows = DiffRow.rows(
            of: file,
            revealed: state.revealed,
            content: state.content,
            findings: showBubbles ? findings : [],
            // Vlákna se přepínačem `Nálezy` **neschovávají**. Ten přepínač je o nálezech
            // naší aplikace; cizí komentář u kódu je důvod, proč se na PR člověk dívá,
            // a schovat ho spolu s nálezy by ho připravilo o to hlavní. Totéž platí o mých
            // rozdělaných komentářích — ty se schovat nesmí o důvod víc, protože se odešlou.
            threads: threads,
            comments: comments
        )
        // Kotvy jednou za soubor, ne pro každý řádek: `Policy.commentableSide` ověřuje
        // příslušnost k hunku hledáním, takže po řádcích je to kvadratické.
        let fileDraft = draft.bound(to: file, anchors: Policy.commentAnchors(in: file))
        return ForEach(rows) { row in
            DiffRowView(
                row: row,
                language: language,
                isLoadingContent: state.isLoading,
                contentFailure: state.failure,
                reveal: { expansion.reveal(file, $0) },
                highlighted: highlighted,
                blockingCategories: blockingCategories,
                viewer: viewer,
                isThreadExpanded: isThreadExpanded,
                toggleThread: toggleThread,
                draft: fileDraft
            )
        }
    }

    private func summary(jumpingWith proxy: ScrollViewProxy) -> some View {
        HStack(spacing: 12) {
            Text(verbatim: "\(files(diff.files.count)) · +\(diff.additions) −\(diff.deletions)")
                .font(.callout)
                .foregroundStyle(.secondary)
            if diff.unrecognizedLines > 0 {
                unrecognizedWarning
            }
            if missingThreads > 0 {
                missingThreadsWarning
            }
            Spacer()
            if !findings.isEmpty {
                // Jmenuje se `Nálezy`, ne `Bubliny`: schovává **jen** nálezy, kdežto
                // „bubliny“ jsou od #64 i vlákna konverzace. Chytilo se to při zkoušení —
                // obecný název sliboval, že vypne obojí.
                Toggle("Nálezy", isOn: $showBubbles)
                    .toggleStyle(.checkbox)
                    .font(.callout)
                    .help("Zobrazit nálezy u řádků, kterých se týkají. Vlákna konverzace zůstanou.")
            }
            foldAllButton
            if let collapse = expansion.collapse {
                Button("Zobrazit jen diff", systemImage: "arrow.down.right.and.arrow.up.left") {
                    collapse()
                }
                .font(.callout)
                .buttonStyle(.borderless)
            }
            jumpMenu(proxy)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    /// Jedno tlačítko, ne dvě. Který ze dvou stavů dává smysl, plyne z toho, co je zrovna
    /// na obrazovce — dvě tlačítka by znamenala, že je jedno z nich pořád k ničemu.
    ///
    /// Nepleteme si to se „Zobrazit jen diff“ vedle: to sbaluje **kontext uvnitř** souborů,
    /// tohle celé soubory.
    @ViewBuilder private var foldAllButton: some View {
        if !diff.files.isEmpty {
            let allFolded = diff.files.allSatisfy(folding.isFolded)
            Button {
                if allFolded { folding.unfoldAll() } else { folding.foldAll(diff.files) }
            } label: {
                Label(
                    allFolded ? "Rozbalit vše" : "Sbalit vše",
                    systemImage: allFolded ? "rectangle.expand.vertical" : "rectangle.compress.vertical"
                )
            }
            .font(.callout)
            .buttonStyle(.borderless)
            .help(allFolded ? "Rozbalit diffy všech souborů" : "Sbalit diffy všech souborů")
        }
    }

    /// Vlákna, která nedorazila, nemají jak chybět **viditelně**: v diffu se prostě
    /// neobjeví bublina a to od „nikdo tam nic nenapsal“ nikdo nepozná. Hlásí se proto
    /// stejně jako nepřečtené řádky diffu.
    private var missingThreadsWarning: some View {
        let count = Plural.czech(missingThreads, one: "vlákno", few: "vlákna", many: "vláken")
        return Label {
            Text(verbatim: "\(count) konverzace se nevešlo — otevři PR na GitHubu")
        } icon: {
            Image(systemName: "exclamationmark.triangle")
        }
        .font(.caption)
        .foregroundStyle(.orange)
    }

    /// Nerozpoznaný řádek znamená, že se člověk dívá na neúplný podklad. Bez téhle věty
    /// by neúplný diff vypadal jako úplný.
    private var unrecognizedWarning: some View {
        let count = Plural.czech(diff.unrecognizedLines, one: "řádek", few: "řádky", many: "řádků")
        return Label {
            Text(verbatim: "\(count) diffu se nepodařilo přečíst")
        } icon: {
            Image(systemName: "exclamationmark.triangle")
        }
        .font(.caption)
        .foregroundStyle(.orange)
    }

    /// Popover se stromem, ne rozbalovací menu: u PR přes třicet souborů je plochý seznam
    /// cest nepoužitelný a vnořená podmenu se špatně trefují.
    private func jumpMenu(_ proxy: ScrollViewProxy) -> some View {
        Button {
            isPickingFile = true
        } label: {
            Label("Přejít na soubor", systemImage: "list.bullet.indent")
        }
        .buttonStyle(.borderless)
        .popover(isPresented: $isPickingFile, arrowEdge: .bottom) {
            FileTreeView(files: diff.files) { file in
                isPickingFile = false
                // Skočit na sbalený soubor jde — hlavička zůstává — ale ukázala by se jen
                // ona. Kdo si ho ze stromu vybral, chce ho vidět.
                if folding.isFolded(file) { folding.toggle(file) }
                withAnimation { proxy.scrollTo(file.id, anchor: .top) }
            }
        }
    }

    /// Celá hlavička je tlačítko, ne jen šipka — na GitHubu se kliká kamkoli do řádku
    /// a trefit se do šipky u padesáti souborů je práce navíc.
    private func fileHeader(_ file: FileDiff) -> some View {
        Button {
            folding.toggle(file)
        } label: {
            headerContent(file)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: file.displayPath))
        .accessibilityHint(folding.isFolded(file) ? "Rozbalí diff souboru" : "Sbalí diff souboru")
    }

    private func headerContent(_ file: FileDiff) -> some View {
        HStack(spacing: 8) {
            Image(systemName: folding.isFolded(file) ? "chevron.right" : "chevron.down")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 10)
            Text(verbatim: file.displayPath)
                .font(.system(.callout, design: .monospaced).weight(.semibold))
                .lineLimit(1)
                .truncationMode(.head)
            if let badge = badge(for: file) {
                Text(badge)
                    .font(.caption2)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(.quaternary, in: .capsule)
            }
            if file.change == .renamed, let oldPath = file.oldPath {
                Text(verbatim: "← \(oldPath)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            Spacer()
            fileFindings(file)
            Text(verbatim: "+\(file.additions) −\(file.deletions)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
        // Ukotvená hlavička jede přes obsah, takže pod ní musí být neprůhledné pozadí.
        .background(.bar)
        // **Ne `Divider()`.** Ten si orientaci bere z okolní osy a v `overlay` žádná není,
        // takže se vykreslí **svisle** — pod hlavičkami tedy nikdy nebyla čára, kterou tam
        // tenhle kód chtěl, ale svislá čárka uprostřed. Dokud mezi hlavičkami byly řádky
        // diffu, ztrácely se; po sbalení všech souborů (#59) se poskládaly do jedné čáry.
        .overlay(alignment: .bottom) {
            Rectangle().fill(.separator).frame(height: 1)
        }
    }

    /// Kolik nálezů v souboru je.
    ///
    /// Ukazuje se **vždycky**, ne jen u sbaleného. U sbaleného je to nutnost — zavřený
    /// soubor s nevyřízeným nálezem by se dal zapomenout a tabulka nálezů je jiná
    /// obrazovka. U rozbaleného to není šum, ale zkratka: projedu hlavičky a vím, kde
    /// nálezy jsou, aniž bych scrolloval obsahem.
    @ViewBuilder private func fileFindings(_ file: FileDiff) -> some View {
        let groups = findings(in: file)
        if !groups.isEmpty {
            let blocking = groups.contains { group in
                group.findings.contains { Policy.isBlocking($0, categories: blockingCategories) }
            }
            Label(
                Plural.czech(groups.count, one: "nález", few: "nálezy", many: "nálezů"),
                systemImage: blocking ? "exclamationmark.triangle.fill" : "text.magnifyingglass"
            )
            .font(.caption)
            .foregroundStyle(blocking ? .red : .secondary)
        }
    }

    /// Nálezy patřící k souboru. Nález umí přijít pod **starou** cestou přejmenovaného
    /// souboru, takže se porovnává proti oběma.
    ///
    /// Stejně jako `DiffRow.groups(of:from:)`, a je to podmínka správnosti, ne kosmetika:
    /// odznak musí počítat přesně to, co se ukáže jako bubliny. Přes `Diff.file(at:)` by se
    /// to rozešlo u řetězu přejmenování, kde jedna cesta sedí na dva soubory — a bylo by to
    /// navíc lineární hledání uvnitř dvojité smyčky.
    private func findings(in file: FileDiff) -> [FindingGroup] {
        findings.filter { group in
            guard let path = group.file else { return false }
            return path == file.newPath || path == file.oldPath
        }
    }

    private func badge(for file: FileDiff) -> String? {
        if file.isBinary { return "binární" }
        switch file.change {
        case .added: return "nový"
        case .deleted: return "smazaný"
        case .renamed: return "přejmenovaný"
        case .modified: return nil
        }
    }

    private func files(_ count: Int) -> String {
        Plural.czech(count, one: "soubor", few: "soubory", many: "souborů")
    }
}
