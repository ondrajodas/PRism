import AppKit
import SwiftUI

/// Sheet s kódem k vybrání a zkopírování — celý hunk (#157) i celý log jobu (#214).
///
/// **Jeden sheet, dva profily velikosti** (#417, sekce 28 návrhu). Co sheet *dělá*, je u obojího
/// totéž: jeden vybíratelný text, zalamování, `Zkopírovat vše`, `Zavřít`. Jak *velký* se otevře, je
/// vlastnost obsahu — u hunku se hledá šířka, ve které se kód nezalamuje (1 180 × 520, podlaha
/// 560 × 320), u logu **žádná šířka nestačí**, takže se bere obrazovka bez okrajů, nejvýš 2 700
/// (× 760, podlaha 820 × 420). Rozhoduje `Policy.codeSheetSizing(kind:screen:)` a druh nese
/// `CodeText`.
///
/// **Do #417 se sheet otevíral 560 bodů široký**, tedy v podlaze: bez `presentationSizing(.fitted)`
/// SwiftUI `idealWidth` u sheetu **zahodí** (změřeno u #327 nad skutečným oknem sheetu, i s oknem
/// 2 000 bodů za ním). U textu, jehož jediné téma je šířka, to byla ta nejhorší možná odpověď —
/// 66 znaků na řádek, z nich 29 na timestamp; 68 % řádků logu se lámalo.
///
/// **Dva klíče pro uloženou velikost jsou podmínka, ne pohodlí**: s jedním by roztažení logu přes
/// celý monitor otevíralo takhle i hunk o devíti řádcích.
struct CodeTextSheet: View {
    let content: CodeText
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var didCopy = false

    /// Velikost, kterou si uživatel natáhl u **hunku**. Nula = nic uloženého, viz
    /// `Policy.codeSheetSize`.
    @AppStorage(StorageKey.hunkWidth) private var hunkWidth = 0.0
    @AppStorage(StorageKey.hunkHeight) private var hunkHeight = 0.0
    /// Totéž u **logu**, a jsou to schválně vlastní klíče — viz dokumentace typu.
    @AppStorage(StorageKey.logWidth) private var logWidth = 0.0
    @AppStorage(StorageKey.logHeight) private var logHeight = 0.0

    /// Naposledy naměřená plocha sheetu. Drží se kvůli třem věcem: předává se dolů jako
    /// `availableWidth` (aby se uvnitř nevyjednávalo, #220), počítá se z ní věta o zalomených
    /// řádcích a je to vstup do ukládání.
    @State private var measured: CGSize?

    /// Kde je uložená velikost sheetu. **Dva klíče na dva profily** — jméno v jednom místě, ať se
    /// test nemusí odvolávat na literál, který se v repu vyskytne dvakrát.
    enum StorageKey {
        static let hunkWidth = "codeSheetHunkWidth"
        static let hunkHeight = "codeSheetHunkHeight"
        static let logWidth = "codeSheetLogWidth"
        static let logHeight = "codeSheetLogHeight"
    }

    /// Za jak dlouho po posledním přeměření se velikost uloží.
    ///
    /// **Odmlka, ne zápis z každého kroku**: tažení okrajem přeměří plochu po každém pixelu, takže
    /// bez ní by z jednoho tahu byly desítky zápisů do `UserDefaults`. `.task(id:)` se při dalším
    /// kroku zruší, takže se zapisuje **jednou za tažení**.
    ///
    /// Drží ještě jednu věc, a ta je důležitější: **sheet se rozvrhuje dvakrát a v prvním průchodu
    /// má podlahu** (změřeno u #327). Odmlka ten mezistav zahodí, takže se neuloží — jinak by se
    /// sheet od druhého otevření otevíral nejmenší možný, tedy přesně do té vady, kterou #417
    /// opravuje. Není `private`, aby si o ni čekání v testu mohlo říct místo toho, aby ten samý
    /// počet milisekund stál v repu dvakrát.
    static let resizeSettle = Duration.milliseconds(400)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            code
            Divider()
            footer
        }
        // **Roztahovatelný sheet, a je to změřené, ne odvozené z dokumentace** (#327, `CodeTextSheet`
        // je druhý výskyt téže třídy): sheet dostane `.resizable` do `styleMask`u jedině
        // s `presentationSizing(.fitted)` a pružným rámcem — a bez `.fitted` se `idealWidth` zahodí
        // a zbyde `minWidth`. Do #417 tady stál komentář, že sheet roztáhnout nejde, takže šířka
        // z obrazovky vypadala jako jediná možnost; s tím měřením padlo obojí.
        .frame(
            minWidth: sizing.floor.width,
            idealWidth: opened.width,
            maxWidth: .infinity,
            minHeight: sizing.floor.height,
            idealHeight: opened.height,
            maxHeight: .infinity
        )
        .presentationSizing(.fitted)
        // Ať uvnitř sheetu nikdo šířku nevyjednává (#220) — obsah ji má znát. Naměřená, protože
        // roztahovatelný sheet žádnou zadrátovanou nemá.
        .availableWidth(measured?.width ?? opened.width)
        // Akce `onGeometryChange` se při nezměněné hodnotě **nespustí** (změřeno u #361), takže to
        // není bezpodmínečný zápis z každého snímku, kterému se vyhýbá #358.
        .onGeometryChange(for: CGSize.self) { $0.size } action: { measured = $0 }
        .task(id: measured) { await rememberSize() }
    }

    /// Podlaha a ideál pro tenhle druh obsahu. `NSScreen.main` je ta s klávesovým oknem, tedy ta,
    /// na které sheet vyjede — stejně jako u sheetu s přepisem session.
    private var sizing: CodeSheetSizing {
        Policy.codeSheetSizing(kind: content.kind, screen: NSScreen.main?.visibleFrame.size)
    }

    /// S jakou velikostí se sheet otevře: uloženou, když je použitelná, jinak ideální.
    private var opened: CGSize {
        Policy.codeSheetSize(
            kind: content.kind,
            storedWidth: storedWidth,
            storedHeight: storedHeight,
            screen: NSScreen.main?.visibleFrame.size
        )
    }

    private var storedWidth: Double {
        switch content.kind {
        case .hunk: hunkWidth
        case .log: logWidth
        }
    }

    private var storedHeight: Double {
        switch content.kind {
        case .hunk: hunkHeight
        case .log: logHeight
        }
    }

    /// Uloží velikost, kterou si uživatel natáhl — teprve když se tažení usadí.
    ///
    /// Rozhodnutí, jestli vůbec zapsat, drží `Policy.codeSheetResize`: **první průchod rozvržení
    /// hlásí podlahu**, takže bezpodmínečný zápis by sheet od druhého otevření otevíral nejmenší
    /// možný.
    private func rememberSize() async {
        guard let measured else { return }
        do {
            try await Task.sleep(for: Self.resizeSettle)
        } catch {
            // Zrušení znamená další krok tažení, tedy „ještě se to hýbe“ — ne chybu.
            return
        }
        guard let size = Policy.codeSheetResize(kind: content.kind, opened: opened, measured: measured)
        else { return }
        switch content.kind {
        case .hunk:
            hunkWidth = size.width
            hunkHeight = size.height
        case .log:
            logWidth = size.width
            logHeight = size.height
        }
    }

    // MARK: - Hlavička

    /// Tři řádky, jak to má návrh (`.sheet-head`): co to je, odkud to je a k čemu se to vztahuje.
    /// **Akce v ní nejsou** — u logu je jedna z těch řádek věta, takže by po ní tlačítka plavala.
    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(verbatim: content.title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
                .truncationMode(.head)
            Text(verbatim: content.slug)
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(Palette.ink2)
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
            Text(verbatim: content.note)
                .font(.system(size: 12))
                .foregroundStyle(Palette.ink3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.raised)
    }

    // MARK: - Obsah

    /// Kód k vybírání. Kreslí ho `SelectableCodeView` (`NSTextView`) — SwiftUI `Text` dává selekci
    /// po jednotlivých textech, viz tam.
    ///
    /// Pružný rámec je tady **podmínka roztahovatelnosti** (`NSScrollView` vlastní ideální výšku
    /// nemá), ne zakázaná třída z #375: ta zakazuje pružnou výšku v řádku líného seznamu, a tohle je
    /// plocha sheetu.
    private var code: some View {
        SelectableCodeView(code: content.code, language: language, colorScheme: colorScheme)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Palette.surface)
    }

    /// **Log se sází jednou barvou** (#417): obarvit v něm timestamp nebo `[ERROR]` znamená skládat
    /// text po řádcích, a to na 8,78MB logu stojí 155 ms proti 7,9 ms jednolitě (změřeno u #214).
    /// U hunku se obarvuje — `Language` tam jazyk pozná a řádků jsou desítky.
    private var language: Language? {
        content.path.flatMap(Language.init(path:))
    }

    // MARK: - Patička

    /// Akce dole, jako u sheetu s přepisem session — a `Zkopírovat vše` je ta hlavní.
    private var footer: some View {
        HStack(spacing: MiniButtonStyle.Metrics.spacing) {
            Button(CodeSheetText.close) { dismiss() }
                .buttonStyle(MiniButtonStyle(emphasis: .secondary))
                .keyboardShortcut(.cancelAction)
            if let link = content.link { githubLink(link) }
            Spacer(minLength: 8)
            if let overflow = CodeSheetText.overflow(overflow) {
                Text(verbatim: overflow)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Palette.ink3)
                    .monospacedDigit()
                    .help("Řádek delší než šířka sheetu se zalomí. Zalomení není znak, takže se do zkopírovaného textu nedostane.")
            }
            Button(didCopy ? CodeSheetText.copied : CodeSheetText.copyAll) {
                Clipboard.copy(content.code)
                didCopy = true
            }
            .buttonStyle(MiniButtonStyle(emphasis: .primary))
            .disabled(didCopy)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.raised)
    }

    /// **Odkaz místo přírůstku** (#417): u přepisu session patička hlásí, kolik od otevření přibylo,
    /// protože je to lokální soubor. Log jobu je na síti — `gh` stahoval 8,78 MB 5,75 až 27,44 s
    /// (#292) —, takže živé číslo by byl request na tik.
    private func githubLink(_ link: URL) -> some View {
        Link(destination: link) {
            Text(verbatim: CodeSheetText.openOnGitHub)
        }
        .buttonStyle(MiniButtonStyle(emphasis: .secondary))
    }

    /// Kolik řádků se nevešlo na šířku. **Jen u hunku** — u logu by to byl scan megabajtů při každém
    /// přerovnání šířky (#224) a věta „dvě třetiny řádků se nevešly“ nikomu nepomůže.
    private var overflow: CodeSheetOverflow? {
        guard content.kind == .hunk else { return nil }
        return Policy.codeSheetOverflow(
            code: content.code,
            width: measured?.width ?? opened.width,
            characterWidth: SelectableCodeView.characterWidth
        )
    }
}
