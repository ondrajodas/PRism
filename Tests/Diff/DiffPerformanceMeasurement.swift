import Foundation
import SwiftUI
import Testing

@testable import PRism

/// Měření, ne test (#220). Nic netvrdí — vypisuje, kde se na velkém PR tráví čas.
///
/// Existuje proto, že u tuhnoucího okna je první otázka „co z toho je drahé“, a ta se nedá
/// zodpovědět čtením kódu. Sample běžícího procesu (20 minut na 100 % CPU) ukázal, že čas nejde
/// do našich funkcí, ale do `StackLayout.sizeThatFits` — a počty vzorků se s každou úrovní
/// zanoření **půlí**, což je podpis exponenciálního layoutu.
///
/// Časy se **netvrdí** `#expect`em: na jiném stroji vyjdou jinak a byl by z toho test, který padá
/// bez chyby v kódu. Prahovou hodnotu má smysl hlídat až tam, kde se ukáže, co je horké.
/// **Pouští se ručně**, ne v běžném běhu: `PRISM_MEASURE=1`. Jeden render v hloubce 8 stojí
/// 15 sekund CPU, což ostatním testům bere stroj — u #220 z toho spadly dva časově citlivé testy
/// v `RealEnvironmentTests`, které v izolaci procházejí. Měření tedy nesmí být součástí suite.
@Suite(
    "Měření výkonu (#220)",
    .enabled(if: ProcessInfo.processInfo.environment["PRISM_MEASURE"] != nil)
)
struct DiffPerformanceMeasurement {
    // MARK: - Měřidlo

    private func measure(_ label: String, iterations: Int = 10, _ body: () -> Void) {
        let clock = ContinuousClock()
        body()    // zahřátí — první průchod platí za líné inicializace
        let elapsed = clock.measure {
            for _ in 0..<iterations { body() }
        }
        print("MĚŘENÍ \(label): \((elapsed / iterations).milliseconds) na volání")
    }

    // MARK: - Hlavní podezřelý: hloubka zanoření pružných stacků

    /// **Tohle je to měření, o které jde.** Zanořené stacky s pružnou šířkou a `Spacer`em —
    /// tvar, který v okně vzniká skládáním views přes sebe (detail → tab → osa → uzel → karta →
    /// bublina → řádek). Když cena roste exponenciálně s hloubkou, je příčina tuhnutí tvar
    /// stromu, ne velikost dat — a to vysvětluje, proč tuhnou oba taby.
    @MainActor
    @Test("Cena layoutu podle hloubky zanoření")
    func nestingCost() {
        // **Nad hloubku 6 se v suite nechodí.** Každá úroveň násobí čas ~5,5×, takže hloubka 8
        // stojí 15 sekund a hloubka 12 běží hodiny — přesně to, co dělá okno. Naměřeno u #220:
        // 4 → 11 ms, 6 → 350 ms, 8 → 15 700 ms.
        for depth in [4, 6] {
            let clock = ContinuousClock()
            let elapsed = clock.measure { render(nested(depth), width: 900) }
            print("MĚŘENÍ základ, hloubka \(depth): \(elapsed.milliseconds)")
        }
    }

    /// Co exponent zabije. Jedna proměnná na jeden běh, hloubka pevná — jinak se nedá poznat,
    /// jestli pomohla změna, nebo menší strom.
    @MainActor
    @Test("Které opatření exponent zabije")
    func remedies() {
        // Hloubka 8: teprve na ní je vidět rozdíl mezi „pevně všude“ a „pevná hranice každou
        // čtvrtou úroveň“, a právě to rozhoduje o rozsahu opravy.
        let depth = 8
        for variant in NestingVariant.allCases {
            let clock = ContinuousClock()
            let elapsed = clock.measure { render(nested(depth, variant: variant), width: 900) }
            print("MĚŘENÍ \(variant.label), hloubka \(depth): \(elapsed.milliseconds)")
        }
    }

    enum NestingVariant: CaseIterable {
        /// Tvar, jaký je v okně dnes.
        case baseline
        /// `Spacer(minLength:)` nahrazený zarovnáním — `Spacer` je pružný prvek, který nutí
        /// stack ptát se dětí na velikost zvlášť.
        case withoutSpacer
        /// Pružná šířka nahrazená konkrétní. Když dítě šířku zná, vyjednávání končí.
        case fixedWidth
        /// Konkrétní šířka **jen na každé čtvrté úrovni**. Tohle je návrh opravy: řetězec se
        /// rozdělí na kratší úseky, takže z `5,5^12` je `3 × 5,5^4`. Kdyby to stačilo, nemusí se
        /// pružná šířka vymýtit ze všech devadesáti míst — stačí pár hranic.
        case fixedEveryFourth
        /// Oprava tak, jak je v appce: šířka se předává v environmentu (`availableWidth`), každá
        /// úroveň ji zúží o své odsazení (`narrowingWidth`) a roztažení jde přes `filling()`.
        /// Musí vyjít stejně jako `fixedWidth` — když ne, plumbing něco nepředává.
        case environmentWidth

        var label: String {
            switch self {
            case .baseline: "základ"
            case .withoutSpacer: "bez Spaceru"
            case .fixedWidth: "s pevnou šířkou všude"
            case .fixedEveryFourth: "s pevnou hranicí každou 4. úroveň"
            case .environmentWidth: "přes availableWidth (oprava)"
            }
        }
    }

    @MainActor
    private func nested(_ depth: Int, variant: NestingVariant) -> AnyView {
        guard depth > 0 else {
            return AnyView(Text(verbatim: "list").frame(maxWidth: .infinity, alignment: .leading))
        }
        let child = nested(depth - 1, variant: variant)
        return AnyView(
            HStack(alignment: .top, spacing: 8) {
                Rectangle().fill(.gray).frame(width: 2)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 7) {
                        Text(verbatim: "úroveň \(depth)")
                        if variant == .withoutSpacer || variant == .fixedWidth {
                            Text(verbatim: "9c1de02")
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        } else {
                            Spacer(minLength: 8)
                            Text(verbatim: "9c1de02")
                        }
                    }
                    child
                }
                .modifier(WidthStyle(
                    fixed: fixedWidth(at: depth, variant: variant),
                    viaEnvironment: variant == .environmentWidth
                ))
            }
        )
    }

    /// Má tahle úroveň dostat konkrétní šířku? Šířka se s hloubkou zužuje o odsazení osy,
    /// jinak by pevný rámec přetékal.
    private func fixedWidth(at depth: Int, variant: NestingVariant) -> CGFloat? {
        let width = 860 - CGFloat(depth) * 10
        switch variant {
        case .baseline, .withoutSpacer, .environmentWidth: return nil
        case .fixedWidth: return width
        case .fixedEveryFourth: return depth % 4 == 0 ? width : nil
        }
    }

    /// Pružná versus pevná šířka na jednom místě, ať se varianty liší jedinou věcí.
    private struct WidthStyle: ViewModifier {
        let fixed: CGFloat?
        var viaEnvironment = false

        func body(content: Content) -> some View {
            if viaEnvironment {
                // Osa vlevo je 2 body a mezera 8 — dohromady 10, o které se šířka pro obsah zúží.
                content.filling(alignment: .leading).narrowingWidth(by: 10)
            } else if let fixed {
                content.frame(width: fixed, alignment: .leading)
            } else {
                content.frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// Zanoření, které kopíruje tvar `ConversationNodeView` — osa vlevo, pružný obsah vpravo,
    /// `Spacer(minLength:)` v řádku. Pružnost je podstatná: stack s pevnými dětmi se měří jednou.
    @MainActor
    private func nested(_ depth: Int) -> AnyView {
        guard depth > 0 else {
            return AnyView(Text(verbatim: "list").frame(maxWidth: .infinity, alignment: .leading))
        }
        return AnyView(
            HStack(alignment: .top, spacing: 8) {
                Rectangle().fill(.gray).frame(width: 2)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 7) {
                        Text(verbatim: "úroveň \(depth)")
                        Spacer(minLength: 8)
                        Text(verbatim: "9c1de02")
                    }
                    nested(depth - 1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        )
    }

    /// Vynutí layout a vykreslení. `ImageRenderer` je `@MainActor`, proto je i tohle.
    @MainActor
    private func render(_ view: AnyView, width: CGFloat) {
        // Šířka se ustaví i v environmentu — varianty, které ji nečtou, to neovlivní.
        let renderer = ImageRenderer(content: view.frame(width: width).availableWidth(width))
        _ = renderer.nsImage
    }

    // MARK: - Skutečný podstrom konverzace

    /// Číslo před a po opravou — na **skutečných** views, ne na syntetickém tvaru.
    ///
    /// `ConversationNodeView` se dá postavit bez storu (bere uzel a akce), takže se osa dá
    /// vyrenderovat offscreen a změřit. Tohle je ten test, který má po opravě spadnout na
    /// zlomek — a kdyby se řetězec pružných šířek vrátil, číslo vyletí zpátky.
    @MainActor
    @Test("Osa konverzace: cena layoutu podle počtu uzlů")
    func conversationTimelineCost() {
        for count in [1, 5, 20] {
            let nodes = (0..<count).map { conversationNode(index: $0) }
            let view = AnyView(
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(nodes.enumerated()), id: \.element.id) { _, node in
                        ConversationNodeView(node: node, viewer: "ondrajodas")
                    }
                }
            )
            let clock = ContinuousClock()
            let elapsed = clock.measure { render(view, width: 900) }
            print("MĚŘENÍ osa konverzace, \(count) uzlů: \(elapsed.milliseconds)")
        }
    }

    private func conversationNode(index: Int) -> ConversationNode {
        .entry(.thread(ReviewThread(
            id: "t\(index)",
            path: "src/Module\(index)/Handler.swift",
            line: 12 + index,
            originalLine: 12 + index,
            side: .right,
            isResolved: false,
            isOutdated: false,
            comments: ConversationPage(
                items: [
                    ThreadComment(
                        id: "c\(index)",
                        author: "kolega",
                        body: "Tady bych to raději rozdělil na dvě metody, ať se to dá testovat zvlášť.",
                        createdAt: Date(timeIntervalSince1970: 1_760_000_000),
                        url: URL(string: "https://github.com/o/r/pull/1#discussion_c\(index)")!
                    )
                ],
                total: 1,
                hasNextPage: false
            )
        )))
    }

    // MARK: - Cena bloku podle jeho délky (#223)

    /// Kolik stojí vykreslit blok podle toho, kolik má řádků. Z toho se vybírá strop — číslo
    /// nemá vzniknout odhadem.
    ///
    /// **Měří se dvě různé věci a nesmí se splést:**
    ///
    /// 1. **Jeden blok** podle délky. Tohle je ten údaj, ze kterého se strop vybírá — je to práce,
    ///    kterou appka zaplatí i za blok, jehož je vidět kousek, protože `LazyVStack` umí přeskočit
    ///    jen celý blok.
    /// 2. **Celý soubor** o 2400 řádcích rozdělený na bloky různé délky. To je kontrola, co
    ///    rozdělení stojí — a vychází **plochá** (150–280 ms bez trendu), protože `ImageRenderer`
    ///    nic nelení. Přínos stropu z téhle série vidět **není** a nesmí se z ní vyvozovat;
    ///    svádí totiž k opačnému závěru, že rozdělení je dražší.
    @MainActor
    @Test("Cena vykreslení podle délky bloku")
    func blockLengthCost() {
        let language = Language(path: "Schema.swift")
        let lines = (0..<2400).map { index in
            DiffLine(kind: .context, oldNumber: index + 1, newNumber: index + 1, text: "    let value\(index) = compute(\(index))")
        }

        // **Cena jednoho bloku** — to je to, co se zaplatí za blok, i když je vidět jen jeho kousek.
        // `LazyVStack` lení po řádcích seznamu, takže nerozdělený soubor je jeden řádek a rozloží se
        // celý. Tohle je tedy ten údaj, ze kterého se strop vybírá.
        for size in [2400, 600, 200, 60, 20] {
            let slice = Array(lines.prefix(size))
            let block = DiffBlock(lines: slice, ids: slice.indices.map { "l\($0)" })
            let view = AnyView(DiffCodeBlockView(block: block, language: language, colorScheme: .light))
            let clock = ContinuousClock()
            let elapsed = clock.measure { render(view, width: 900) }
            print("MĚŘENÍ jeden blok o \(size) řádcích: \(elapsed.milliseconds)")
        }

        // A pro srovnání celý soubor rozdělený na bloky — tady se lenost neuplatní, protože
        // `ImageRenderer` kreslí všechno. Slouží k tomu, aby bylo vidět, **co rozdělení stojí**.
        for size in [2400, 600, 200, 60, 20] {
            let blocks = stride(from: 0, to: lines.count, by: size).map { start in
                let slice = Array(lines[start..<min(start + size, lines.count)])
                return DiffBlock(lines: slice, ids: slice.indices.map { "l\(start + $0)" })
            }
            let view = AnyView(
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                        DiffCodeBlockView(block: block, language: language, colorScheme: .light)
                    }
                }
            )
            let clock = ContinuousClock()
            let elapsed = clock.measure { render(view, width: 900) }
            print("MĚŘENÍ blok po \(size) řádcích (\(blocks.count) bloků): \(elapsed.milliseconds)")
        }
    }

    // MARK: - Co se počítá při každém překreslení diffu

    private func hunk(start: Int, count: Int) -> DiffHunk {
        var lines: [DiffLine] = []
        var old = start
        var new = start
        for index in 0..<count {
            switch index % 3 {
            case 0:
                lines.append(DiffLine(kind: .context, oldNumber: old, newNumber: new, text: "    let value = compute(\(index))"))
                old += 1
                new += 1
            case 1:
                lines.append(DiffLine(kind: .removed, oldNumber: old, newNumber: nil, text: "    return legacy(value, \(index))"))
                old += 1
            default:
                lines.append(DiffLine(kind: .added, oldNumber: nil, newNumber: new, text: "    return modern(value, \(index))"))
                new += 1
            }
        }
        return DiffHunk(oldStart: start, oldCount: count, newStart: start, newCount: count, heading: "func handle()", lines: lines)
    }

    private func file(path: String, hunks: Int, linesPerHunk: Int) -> FileDiff {
        FileDiff(
            oldPath: path,
            newPath: path,
            change: .modified,
            isBinary: false,
            hunks: (0..<hunks).map { hunk(start: 1 + $0 * (linesPerHunk + 20), count: linesPerHunk) }
        )
    }

    @Test("Model diffu na 2400 řádcích")
    func diffModelCost() {
        let spread = Diff(
            files: (0..<20).map { file(path: "src/Module\($0)/Handler\($0).swift", hunks: 4, linesPerHunk: 30) },
            unrecognizedLines: 0
        )
        let single = Diff(files: [file(path: "src/Generated/Schema.swift", hunks: 1, linesPerHunk: 2400)], unrecognizedLines: 0)

        measure("Diff.additions + deletions (lišta záložek, oba taby)") {
            _ = spread.additions
            _ = spread.deletions
        }
        measure("DiffRow.rows + blocked, 20 souborů po 120 řádcích") {
            for file in spread.files { _ = DiffRow.blocked(DiffRow.rows(of: file)) }
        }
        measure("Policy.commentAnchors, 20 souborů") {
            for file in spread.files { _ = Policy.commentAnchors(in: file) }
        }

        let big = single.files[0]
        measure("DiffRow.rows + blocked, jeden soubor o 2400 řádcích") {
            _ = DiffRow.blocked(DiffRow.rows(of: big))
        }
        if let language = Language(path: big.displayPath) {
            measureHighlighting(of: big.hunks.flatMap(\.lines).map(\.text), in: language)
        }

        // Jeden blok = jeden `NSTextView`. Bez stropu je to celý soubor.
        let biggest = DiffRow.blocked(DiffRow.rows(of: big)).compactMap { row -> Int? in
            if case .block(_, let block) = row { block.lines.count } else { nil }
        }.max() ?? 0
        print("MĚŘENÍ největší blok: \(biggest) řádků v jednom NSTextView")
    }

    // MARK: - Co stojí obarvení (#224)

    /// Před a po zavedení cache, na jednom souboru o 2400 řádcích.
    ///
    /// Měří se **tři** různé věci a nesmí se splést:
    ///
    /// 1. **`scan` bez cache** — práce, která se do #224 dělala při každém překreslení.
    /// 2. **`runs` z plné cache** — co se za totéž platí od #224, tedy při hoveru a při skoku
    ///    mezi nálezy.
    /// 3. **`runs` do prázdné cache** — jednorázová cena při prvním zobrazení souboru, tedy
    ///    průchod plus uložení. Naměřeno stejně jako `scan` (44 ms), takže uložení se ve zbytku
    ///    ztratí; kdyby tohle číslo od `scan` odskočilo, platí se za cache i tam, kde nepomáhá.
    ///
    /// **Řádky jsou tu všechny různé**, takže je to nejhorší případ. Ve skutečném diffu se
    /// závorky, prázdné řádky a importy opakují, takže i první průchod část práce ušetří.
    private func measureHighlighting(of texts: [String], in language: Language) {
        measure("SyntaxHighlighter.scan, \(texts.count) řádků bez cache") {
            for text in texts { _ = SyntaxHighlighter.scan(text, in: language) }
        }

        let warm = SyntaxRunCache()
        for text in texts { _ = warm.runs(of: text, in: language) }
        measure("SyntaxRunCache.runs, \(texts.count) řádků z plné cache") {
            for text in texts { _ = warm.runs(of: text, in: language) }
        }

        // Vlastní smyčka, ne `measure`: ta si nejdřív zahřeje, což je u prázdné cache přesně to,
        // co se měřit nemá.
        let iterations = 10
        let elapsed = ContinuousClock().measure {
            for _ in 0..<iterations {
                let cold = SyntaxRunCache()
                for text in texts { _ = cold.runs(of: text, in: language) }
            }
        }
        print("MĚŘENÍ SyntaxRunCache.runs, \(texts.count) řádků do prázdné cache: \((elapsed / iterations).milliseconds) na volání")

        measureRunFootprint(of: texts, in: language)
    }

    /// Kolik textu za tenhle soubor v cache zůstane ležet — z toho se překládá strop „nejvýš
    /// 4000 řádků“ na kilobajty.
    ///
    /// **Není to měření paměti procesu.** Rezidentní velikost se po naplnění cache nehne (zkoušeno
    /// přes `task_info`: přírůstek vyšel 0 kB, protože alokátor sáhne po stránkách, které už má),
    /// takže by to tvrdilo, že cache nic nestojí. Sčítá se proto **text run**, tedy hodnoty, které
    /// v ní leží. Klíč se nepočítá — je to tentýž řetězec, jaký drží model diffu, takže se kopíruje
    /// jen jeho hlavička. Režie slovníku v tom taky není, je to spodní odhad.
    private func measureRunFootprint(of texts: [String], in language: Language) {
        let runs = texts.flatMap { SyntaxHighlighter.scan($0, in: language) }
        let bytes = runs.reduce(0) { $0 + $1.text.utf8.count }
        let perLine = texts.isEmpty ? 0 : bytes / texts.count
        print("MĚŘENÍ text run, \(texts.count) řádků: \(bytes / 1024) kB (~\(perLine) B na řádek, \(runs.count) run) — tolik zůstane v cache")
    }
}

private extension Duration {
    /// Milisekundy na tři desetiny — `Duration` se jinak vypisuje v attosekundách.
    var milliseconds: String {
        let value = Double(components.seconds) * 1000
            + Double(components.attoseconds) / 1_000_000_000_000_000
        return String(format: "%.3f ms", value)
    }
}
