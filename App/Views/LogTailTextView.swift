import AppKit
import SwiftUI

/// Konec logu jako **jeden `NSTextView`** (#292), ne SwiftUI `Text`.
///
/// **Tohle je to, co dovoluje ukázat tisíce řádků.** SwiftUI `Text` se `.fixedSize()` sází celý
/// naráz a u dlouhých řádků z Actions logu roste kvadraticky — změřeno na skutečném 8,78MB logu
/// (`keboola/job-queue-daemon`, job 93844012547):
///
/// | Řádků konce logu | SwiftUI `Text` | `NSTextView` |
/// |---|---|---|
/// | 300 | 123,77 ms | **2,58 ms** |
/// | 2 000 | 6 392,79 ms | **2,02 ms** |
/// | 6 000 (dnešní mez) | 57 554,33 ms | **5,45 ms** |
/// | 10 000 | 202 533,12 ms | **14,34 ms** |
///
/// Dvě a půl minuty na deseti tisících řádcích nejsou opomenutí, které by šlo doladit: `Text` musí
/// znát velikost celku dopředu (a u řádků o 2 258 znacích je to 13 930 bodů na šířku), kdežto
/// TextKit sází **líně po viewportu**. Projíždění proto stojí 0,00 ms medián (nejhorší snímek
/// 0,01 ms) bez ohledu na velikost — a to je zrovna ta cena, na kterou si stěžuje #275.
///
/// Čísla jsou z `CheckLogPerformanceMeasurement`, takže se dají pustit znovu.
///
/// **Nezalamuje se**, jak to má návrh (`.logtail`): kontejner je „nekonečně" široký a scrolluje se
/// dvěma osami. Zalamování by u řádku o 2 258 znacích (v tom logu jich je 272 nad tisíc znaků)
/// snědlo celé okýnko jedním řádkem logu.
///
/// Vedlejší zisk, který se nehledal: konec logu je **vybíratelný**, takže se z něj dá kopírovat bez
/// otevírání sheetu — `⌘C` i kontextové menu dává systém.
struct LogTailTextView: NSViewRepresentable {
    let text: String
    /// Velikost písma. Drží se tady, protože z ní se počítá výška — a ta se musí měřit na tom, na
    /// čem se doopravdy kreslí (#236).
    let fontSize: CGFloat
    let lineSpacing: CGFloat
    let color: Color

    /// Odsazení textu od hran — dovnitř `NSTextView`u, ne paddingem ve SwiftUI, aby scroller
    /// nejezdil po prázdném pruhu.
    nonisolated static let inset = NSSize(width: 0, height: 4)

    func makeNSView(context: Context) -> LogTailScrollView {
        let scroll = Self.makeScrollView()
        // Skok se dělá odsud, protože `updateNSView` běží dřív, než SwiftUI okýnku dá výšku.
        // Zachycuje se **jen koordinátor**, ne celý `Context`: ten drží i snímek prostředí, a nic
        // z něj tady není potřeba.
        let coordinator = context.coordinator
        scroll.onLayout = { [weak scroll] in
            guard let scroll else { return }
            Self.jumpToEnd(in: scroll, coordinator: coordinator)
        }
        return scroll
    }

    /// Okýnko poskládané **ručně**, ne `NSTextView.scrollableTextView()`.
    ///
    /// Ručně kvůli skoku na konec logu: ten musí přijít až ve chvíli, kdy okýnko **má rozměr**
    /// (#303, rozbor u `jumpToEnd(in:coordinator:)`), a jediné místo, ze kterého se to pozná, je
    /// `layout()` vlastního `LogTailScrollView`u. Továrnička z AppKitu vrací `NSScrollView`, takže
    /// vlastní podtyp z ní vzít nejde.
    ///
    /// **`static`, aby si totéž mohlo postavit i měření** (`CheckLogPerformanceMeasurement`). Do #303
    /// si harness sazbu skládal vlastní kopií „nastavené stejně jako `LogTailTextView`“ — tedy druhé
    /// místo, kde se to dá nastavit jinak, a měření by pak popisovalo view, které aplikace nekreslí.
    @MainActor
    static func makeScrollView() -> LogTailScrollView {
        let scroll = LogTailScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false

        let textView = NSTextView(frame: .zero)
        scroll.documentView = textView
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = Self.inset
        // **Bez zalamování.** `widthTracksTextView = false` a „nekonečný" kontejner znamenají, že
        // dlouhý řádek zůstane jedním řádkem a jede se za ním do strany.
        textView.isHorizontallyResizable = true
        textView.isVerticallyResizable = true
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.size = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        return scroll
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    /// Co už je ve view nasázené. Drží se proto, aby se text **nepřepisoval při každém průchodu**
    /// `body`: přepsání zahodí výběr i polohu scrollu, takže by uživateli mizel pod rukama vybraný
    /// řádek pokaždé, když se v okně změní cokoli jiného.
    ///
    /// Porovnává se celý `String`, a není to drahé: SwiftUI podává tutéž hodnotu, takže obě strany
    /// ukazují na jednu paměť a `==` na ní končí hned. Rozejít se můžou jedině tím, že se text
    /// doopravdy změnil — a to je zrovna ta chvíle, kdy se přepsat má.
    ///
    /// Barva se sleduje spolu s textem, i když `Palette.ink2` je `NSColor` s dynamickým providerem
    /// a přepnutí režimu si tedy vyřídí sám. Je to pojistka na volajícího, který by podal barvu
    /// **staticky** rozhodnutou podle `colorScheme` — pak by se bez přepsání textu tmavý režim
    /// nakreslil světlou barvou, a to potichu.
    ///
    /// Skok na konec se drží tady jako **nevyřízená žádost**, ne jako hotová věc: text dorazí dřív,
    /// než okýnko dostane výšku, a do té doby se skočit nedá (viz `jumpToEnd(in:coordinator:)`).
    @MainActor
    final class Coordinator {
        var shownText: String?
        var shownColor: Color?
        var needsJumpToEnd = false
    }

    func updateNSView(_ scroll: LogTailScrollView, context: Context) {
        guard let textView = scroll.documentView as? NSTextView else { return }
        let coordinator = context.coordinator
        guard coordinator.shownText != text || coordinator.shownColor != color else { return }
        let textChanged = coordinator.shownText != text
        coordinator.shownText = text
        coordinator.shownColor = color

        textView.textStorage?.setAttributedString(Self.attributed(
            text,
            fontSize: fontSize,
            lineSpacing: lineSpacing,
            color: color
        ))

        guard textChanged else { return }
        coordinator.needsJumpToEnd = true
        // Když okýnko rozměr **už má** (přišel nový text do vysázeného view), skočí se hned;
        // jinak žádost zůstane ležet a vyřídí ji `layout()`.
        Self.jumpToEnd(in: scroll, coordinator: coordinator)
    }

    /// **Otevírá se na konci logu, ne na začátku ocasu** (#292). To, kvůli čemu se log otevírá
    /// (selhaná assertace, exit code), je na posledních řádcích — a se šesti tisíci řádků je začátek
    /// ocasu dvě stě obrazovek daleko.
    ///
    /// Vodorovně se vrací **na nulu**: skok na konec dokumentu jinak zůstane u konce nejdelšího
    /// řádku (v největším změřeném logu 2 258 znaků), takže by okýnko začínalo uprostřed slova.
    ///
    /// **Skočit jde jedině do okýnka, které má výšku** — a to je celá ta oprava z #303. Do té doby
    /// se skákalo z `DispatchQueue.main.async` hned po vsazení textu, jenže `LogTailTextView` vzniká
    /// **až když log dorazí**, takže v tu chvíli mu SwiftUI ještě rozměr nedalo:
    /// `scrollToEndOfDocument` do nulového `clipView`u dokument nasází (výška vyjde přesně), ale
    /// posun **zahodí** a okýnko zůstane na nule. Změřeno vedle sebe, obě cesty: s framem předem
    /// `origin.y = 71 680`, s framem až po skoku `0`.
    ///
    /// Proč to #292 nechytilo, ať je zapsané: sonda tam skládala `NSScrollView` ručně **a rozměr mu
    /// dala předem**, tedy měřila cestu, kterou aplikace nejde — tatáž chyba jako u vynucené sazby
    /// celého dokumentu, jen o vrstvu vedle.
    ///
    /// **Žádost se zahodí teprve tehdy, když je konec doopravdy vidět.** Rozložení totiž nemusí být
    /// jedno: když se vodorovný scroller objeví **až po** skoku, viewport se o jeho 17 bodů zmenší
    /// a okýnko zůstane o řádek nad koncem. Chyceno plným během testů pod zátěží (samostatně to
    /// vycházelo), takže je to zrovna ten druh chyby, který by se v aplikaci projevil jednou za čas
    /// a nedal by se zopakovat.
    @MainActor
    static func jumpToEnd(in scroll: LogTailScrollView, coordinator: Coordinator) {
        guard coordinator.needsJumpToEnd,
              scroll.bounds.height > 0,
              let textView = scroll.documentView as? NSTextView
        else { return }
        // Skok je tu i proto, že **vynutí sazbu až na konec** — bez něj je `textView.frame.height`
        // jen odhad TextKitu a dopočítaný cíl by mířil vedle.
        textView.scrollToEndOfDocument(nil)
        let end = max(0, textView.frame.height - scroll.contentView.bounds.height)
        scroll.contentView.setBoundsOrigin(NSPoint(x: 0, y: end))
        scroll.reflectScrolledClipView(scroll.contentView)
        coordinator.needsJumpToEnd = scroll.documentVisibleRect.maxY + 1 < textView.frame.height
    }

    /// **Jednolitý text, ne po řádcích.** Log žádný jazyk nemá, takže se nemá co obarvovat — dělení
    /// a slepování řádek po řádce stojí u dvoumegového textu 38 ms proti 2,2 ms (#214).
    nonisolated static func attributed(_ text: String, fontSize: CGFloat, lineSpacing: CGFloat, color: Color) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = lineSpacing
        return NSAttributedString(string: text, attributes: [
            .font: Self.font(size: fontSize),
            .foregroundColor: NSColor(color),
            .paragraphStyle: paragraph,
        ])
    }

    nonisolated static func font(size: CGFloat) -> NSFont {
        NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }

    /// Jak vysoké okýnko konec logu potřebuje, nejvýš `limit`.
    ///
    /// Počítá se **z metriky toho fontu, kterým se kreslí** (#236): kdo si říká o velikost, musí ji
    /// měřit na tom, na čem kreslí, jinak nakreslí jiný počet řádků, než na kolik si řekl. Bez
    /// zalamování je to přesné — jeden řádek textu je jeden řádek sazby.
    ///
    /// Krátký log tedy nedostane celý strop s prázdnem pod sebou a dlouhý se do stropu zastropuje
    /// a scrolluje uvnitř. Kolik ten strop je, rozhoduje `CheckDetailView.logMaxHeight` — je to
    /// rozhodnutí o okně, ne o textu.
    ///
    /// **Obsah je o `lineSpacing` velkorysejší, než co text potřebuje**, a je to schválně: posledního
    /// řádku se prokládání netýká, takže vysázený dokument je `N × lineHeight − lineSpacing + 2 × inset`
    /// vysoký, kdežto tady se počítá `N × lineHeight + 2 × inset`. Dva body slacku znamenají, že okýnko
    /// je na obsah vždycky o chlup **větší**, nikdy menší — a to je ta strana, na které se chybovat má.
    /// Změřeno u #347 (`LogTailScrollerReserveTests`); kdo to bude chtít zpřesnit, musí spolu s tím
    /// posunout `CheckDetailView.logMaxHeight`, protože strop na tom stojí.
    nonisolated static func height(forLines lines: Int, fontSize: CGFloat, lineSpacing: CGFloat, limit: CGFloat) -> CGFloat {
        let manager = NSLayoutManager()
        let lineHeight = manager.defaultLineHeight(for: font(size: fontSize)) + lineSpacing
        let content = CGFloat(max(lines, 1)) * lineHeight + 2 * inset.height
        // Vodorovný scroller si ukusuje z výšky, takže se k obsahu přidává — jinak by na
        // zastropovaném okýnku zakrýval poslední řádek, tedy ten, kvůli kterému se log otevírá.
        return min(limit, content + horizontalScrollerHeight)
    }

    /// Kolik se nechává na vodorovný scroller: **17 bodů**, tedy
    /// `NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy)` na tomhle systému.
    ///
    /// **Na čem se to měřilo, protože právě tohle se tady rozešlo** (#347; do té doby tu stálo 13
    /// bodů). Třináct je `scrollerWidth` pro velikost **`.small`** — tedy pro scroller, který okýnko
    /// nikdy nekreslí: `makeScrollView()` nechává `NSScrollView`u výchozí `.regular`, a ten bere 17.
    /// Konstanta odměřená na jiném ovládacím prvku, než jaký se kreslí, je zrovna ta chyba, kterou
    /// popisuje #236 — a vypadala odměřeně, protože měření bylo skutečné, jen jinde.
    ///
    /// Změřeno na tom, na čem se kreslí, a **u obou stylů**: `LogTailScrollView` o výšce 441 má
    /// s **legacy** stylem `contentView.bounds.height` 424, tedy zábor **17**; s **overlay** stylem
    /// 441, tedy zábor **0** — overlay scroller plave nad obsahem, i když je 17 bodů vysoký.
    /// Rezervuje se proto legacy: je to horší z těch dvou, takže při overlay zbyde 17 bodů prázdna,
    /// kdežto naopak by se z obsahu ukusovalo.
    ///
    /// Čtyři body, o které to bylo vedle, nebyly kosmetika, a **projevily se na obou koncích jinak**
    /// (změřeno u #347, obě čísla z kresby):
    ///
    /// - **Nezastropované okýnko** bylo o 2 body nižší než jeho vlastní dokument — z těch čtyř dva
    ///   spolkl slack na prokládání z odstavce výš. Log, který se měl vejít celý, tím dostal svislý
    ///   scroller a odscrolloval se o 2 body (`origin.y` 2 místo 0), takže se **horní řádek ořezal**.
    ///   Na třířádkovém logu je to 63 bodů okýnka na dokument o 50, po opravě 67 na 50.
    /// - **Zastropované okýnko** ukazovalo `(441 − 8 − 17) / 14` = **29,71 řádku** místo 30, tedy
    ///   o řádek méně, než na kolik si strop řekl.
    ///
    /// Co se u stropu **nezměnilo**, ať to někdo nehledá jako regresi: u konce logu je i po opravě
    /// u horní hrany vidět necelý řádek. To není z rezervy, ale z toho, že `2 × inset` leží **uvnitř**
    /// dokumentu a skáče se na jeho úplný konec — mřížka řádků na hranu viewportu prostě nepadne.
    /// Rezerva rozhoduje o **výšce**, ne o zarovnání mřížky.
    ///
    /// **Zůstává to opsané číslo, ne dotaz na API** (rozhodnuto u #347, zdůvodnění v specifikaci).
    /// `NSScroller.scrollerWidth` je `@MainActor` — dědí to z `NSControl` —, kdežto výška se počítá
    /// `nonisolated`; a hlavně `CheckDetailView.logMaxHeight` je ručně vybraná konstanta, která musí
    /// být `14N + 2 × inset + rezerva`. S rezervou známou teprve za běhu by se u stropu nedalo
    /// tvrdit, že padne na celý řádek, právě tam, kde se ten strop vybírá. Ty dvě konstanty jsou pár
    /// a hýbe se s nimi společně.
    ///
    /// Na `NSScroller.preferredScrollerStyle` se schválně neptáme: **mění se za běhu** podle toho,
    /// jestli je připojená myš (změřeno u #347 — dva běhy sondy za sebou se usadily jednou na
    /// `legacy`, jednou na `overlay`), a okýnko, kterému se výška mění připojením myši, je horší než
    /// 17 bodů prázdna u krátkého logu.
    ///
    /// **Nedrží to komentář, ale test** (`LogTailScrollerReserveTests`) — a ten se od #347 ptá
    /// **kresby**, ne API s ručně vybranou velikostí: postaví `makeScrollView()`, položí do něj
    /// dokument širší než okýnko a odečte, kolik z výšky ubylo. Kdyby se ptal jen
    /// `scrollerWidth(for: .small, …)`, spletl by se znovu a stejně — a přesně to se stalo.
    nonisolated static let horizontalScrollerHeight: CGFloat = 17
}

/// `NSScrollView`, který umí říct, že se právě rozložil.
///
/// Existuje kvůli jedné jediné věci: **skok na konec logu se dá udělat teprve tehdy, když okýnko má
/// výšku** (#303). `updateNSView` běží dřív, takže z něj se to nedozvíme — a `NSViewRepresentable`
/// žádný „po rozložení" nemá.
///
/// `layout()` se zavolá při každém přerovnání, ale `LogTailTextView.jumpToEnd` si sám drží, jestli je
/// skok **ještě** potřeba, takže se scroll uživateli nepřetahuje pod rukama při každé změně šířky
/// okna.
class LogTailScrollView: NSScrollView {
    var onLayout: (() -> Void)?

    override func layout() {
        super.layout()
        onLayout?()
    }
}
