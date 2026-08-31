import AppKit
import Foundation
import SwiftUI
import Testing

@testable import PRism

/// Nabídka emotikonů — **rozměr a kotvení, ne pravidlo** (#483).
///
/// Pravidla jsou čisté funkce (`EmojiQueryTests`, `EmojiSuggestionRowTests`); tady se měří to, co
/// se dá pokazit jedině kresbou: že se nabídka **vejde do šířky** pole (300 b v konverzaci, 278 b
/// v panelu), že se kreslí **nad polem** a jak je **vysoká** — z té výšky se pozná, kolik místa nad
/// polem potřebuje.
///
/// **Měří se pixely, ne `fittingSize`** (`OverflowProbe`, viz jeho hlavička): nabídka má `maxWidth`,
/// takže obsah, který se do ní nevejde, přeteče **vizuálně**, aniž by se rámec změnil.
@MainActor
@Suite("Nabídka emotikonů (#483)")
struct EmojiSuggestionMenuTests {
    /// Šířka `.pkr` z návrhu — tolik má nabídka v široké konverzaci. **Bere se z aplikace**, ne
    /// z opsaného čísla: dvě pravdy o jedné šířce by se rozešly a test by zezelenal nad nabídkou,
    /// která přetéká.
    ///
    /// `nonisolated`, protože `arguments:` se vyhodnocuje mimo actor (jako `verbs`
    /// v `PickerKeyHintsTests`).
    nonisolated static let wide = EmojiSuggestionMenu.width
    /// Obsahová šířka pole v panelu (300 b panelu minus jeho odsazení), na které se v návrhu měřilo.
    nonisolated static let panel = 278.0

    // MARK: - Šířka

    /// Nabídka **nesmí přetéct** ani s nejdelším jménem z katalogu, ani s aliasem vpravo.
    ///
    /// Prohání se to čtyřmi scénami, které se od sebe liší zrovna tím, čím se šířka dá přetáhnout:
    /// nejdelší jméno v katalogu, jméno, které se **musí zalomit**, řádek s aliasem (nejdelší
    /// v zákresu) a plný strop šesti řádků.
    @Test("Nabídka nepřeteče šířku pole", arguments: [wide, panel], Scene.allCases)
    func doesNotOverflowTheField(width: Double, scene: Scene) throws {
        let probe = OverflowProbe(
            width: width,
            height: 400,
            name: "emoji-\(scene.rawValue)-\(Int(width))"
        )

        #expect(try probe.overflow(of: EmojiSuggestionMenu(suggestions: Self.box(scene.rows))) == 0)
    }

    /// **Dlouhé jméno se zalomí, neořeže** — a je to měření, ne domněnka.
    ///
    /// Návrh tvrdí, že `:woman_in_motorized_wheelchair:` (31 znaků) vyjde v panelu na jeden řádek
    /// s 20 body rezervy, což platí; jenže nejdelší jméno v katalogu je o devět znaků delší
    /// (`:hand_with_index_finger_and_thumb_crossed:`) a to se do 278 bodů **nevejde**. Musí se tedy
    /// zalomit, tedy nabídku **zvýšit** — kdyby zůstalo na jednom řádku, přeteklo by za hranu (to
    /// hlídá sonda výš) a tady by výška vyšla stejně jako u krátkého jména.
    ///
    /// **`fixedSize` na to nestačí** a bylo to změřeno: `Text` ve SwiftUI uvnitř slova nezalamuje,
    /// takže zlomy nabízí `Policy.emojiShortcodeLabel(of:)`.
    @Test("Dlouhé jméno se zalomí, neořeže", arguments: [wide, panel])
    func wrapsALongNameInsteadOfClipping(width: Double) {
        let short = height(of: Scene.short.rows, width: width)
        let long = height(of: Scene.longest.rows, width: width)

        print("MĚŘENÍ (\(Int(width)) b) krátké jméno: \(short) b, nejdelší z katalogu: \(long) b")
        #expect(long > short, "nejdelší jméno nabídku nezvýšilo — zůstalo na řádku a přeteklo")
    }

    // MARK: - Výška a kotvení

    /// **Kolik místa nad polem si nabídka řekne.** Je to číslo, ne odhad: pod ním se pozná, jestli
    /// se vejde nad composer (46 b na spodní hraně tabu) i nad odpověď ve vlákně.
    ///
    /// Strop je **210 bodů** a je z něj vidět, co ho drží: šest řádků, nadpis a patka. Kdyby
    /// `Policy.emojiSuggestionLimit` povyrostl, spadne to tady — a to je správné místo, protože
    /// nabídka, která nemá kam, se ořízne o hranu bubliny.
    @Test("Plná nabídka se vejde do 210 bodů")
    func staysShortEnoughToFitAboveTheField() {
        let full = height(of: Scene.full.rows, width: Self.panel)

        print("MĚŘENÍ plná nabídka (\(Policy.emojiSuggestionLimit) řádků): \(full) b")
        #expect(full <= 210, "plná nabídka má \(full) b")
    }

    /// **Nabídka se kreslí nad polem**, ne v něm a ne pod ním.
    ///
    /// Měří se to pixely v jednom sloupci: pole stojí 220 bodů od horní hrany plátna a nabídka se
    /// musí nakreslit **výš**. Kdyby se kotvení rozešlo (nabídka pod polem, nebo přes něj), vyjde
    /// první nakreslený řádek na poloze pole.
    ///
    /// **Přesná mezera se netvrdí** a je to schválně: měřená hrana je hrana **stínu**
    /// (`--shadow-lg`, radius 30), ne rámu — tvrdit 8 bodů by znamenalo tvrdit rozostření stínu.
    /// Tvrdí se to, co platit musí: nad polem a v dosahu vlastní výšky.
    @Test("Nabídka se kreslí nad polem")
    func drawsAboveTheField() throws {
        let room = 220.0
        let menu = height(of: Scene.alias.rows, width: Self.wide)
        let probe = OverflowProbe(width: Self.wide, height: 500, name: "emoji-nad-polem")

        let painted = try probe.firstPaintedRows(of: Self.fieldWithMenu(room: room), atColumns: [30])
        let top = try #require(painted.first)

        print("MĚŘENÍ pole na \(room) b, nabídka vysoká \(menu) b, kresba začíná na \(top) b")
        #expect(top >= 0, "nad polem se nenakreslilo nic")
        #expect(Double(top) < room, "nabídka se nekreslí nad polem")
        #expect(Double(top) > room - menu - 60, "nabídka je výš, než je její vlastní výška a mezera")
    }

    /// **Proč se nabídka kreslí až za `clipShape` bubliny** — číslem.
    ///
    /// `ThreadBubbleView` ořezává, takže nabídka nasazená **uvnitř** by se uřízla o horní hranu
    /// bubliny. Nestačí na to „bublina bývá vysoká“: bublina o jednom komentáři je **nižší** než
    /// plná nabídka, takže by se v ní neuřízl kus, ale většina — a to včetně vybraného řádku, který
    /// je nahoře.
    ///
    /// Netvrdí se nerovnost (výška bubliny závisí na délce komentáře), jen se **vypíše**: kdyby se
    /// kotvení někdy měnilo, je z čeho vyjít.
    @Test("Výška bubliny vlákna proti výšce nabídky")
    func measuresTheThreadBubbleAgainstTheMenu() {
        let menu = height(of: Scene.full.rows, width: Self.panel)
        let bubble = NSHostingView(
            rootView: ThreadBubbleView(
                thread: Self.shortThread,
                viewer: "ondrajodas",
                indent: 0,
                placement: .timeline
            )
            .availableWidth(700)
            .frame(width: 700)
        ).fittingSize.height

        print("MĚŘENÍ bublina vlákna: \(bubble) b, plná nabídka: \(menu) b")
        #expect(menu > 0)
        #expect(bubble > 0)
    }

    /// Vlákno o **jednom krátkém komentáři** — tedy ta nejnižší bublina, jaká na ose vzniká.
    private static let shortThread = ReviewThread(
        id: "PRRT_1",
        path: "src/Vault/Encryptor.php",
        line: 41,
        originalLine: 41,
        side: .right,
        isResolved: false,
        isOutdated: false,
        comments: ConversationPage(
            items: [
                ThreadComment(
                    id: "1",
                    author: "odinuv",
                    body: "Chybí test na chybějící klíč.",
                    createdAt: Date(timeIntervalSince1970: 1_754_000_000),
                    url: URL(string: "https://github.com/cli/cli/pull/3#discussion_1")!
                )
            ],
            total: 1,
            hasNextPage: false
        )
    )

    // MARK: - Scény

    /// Pět podob nabídky, každá kvůli jinému způsobu, jak se dá šířka přetáhnout. **Ze skutečného
    /// katalogu**, ne z vymyšlených jmen: rezervy se měří na tom, co v okně doopravdy vyjde.
    enum Scene: String, Sendable, CaseIterable {
        /// Krátké jméno — podlaha, proti které se měří zalomení.
        case short
        /// Jméno ze zákresu (31 znaků se dvěma dvojtečkami), o kterém návrh tvrdí rezervu 20 b.
        case designed
        /// **Nejdelší** jméno, které v katalogu doopravdy je (42 znaků s dvojtečkami).
        case longest
        /// Řádek s aliasem vpravo — v zákresu ten nejdelší.
        case alias
        /// Plný strop řádků.
        case full

        var rows: [Policy.EmojiSuggestion] {
            switch self {
            case .short: Policy.emojiSuggestions(for: "tada")
            case .designed: Policy.emojiSuggestions(for: "woman_in_motorized")
            case .longest: Policy.emojiSuggestions(for: "hand_with_index")
            case .alias: Policy.emojiSuggestions(for: "thu")
            case .full: Policy.emojiSuggestions(for: "a")
            }
        }
    }

    /// Pole s nabídkou nad ním, a **s místem nad polem** — bez toho místa by se nabídka nakreslila
    /// mimo plátno a sonda by měřila prázdno.
    ///
    /// Kotvení je `emojiMenuAbove`, tedy **tentýž kód, jakým to kreslí okno**. Vlastní posun
    /// v sondě by měřil sondu.
    private static func fieldWithMenu(room: Double) -> some View {
        Rectangle()
            .fill(Palette.raised)
            .frame(height: 46)
            .emojiMenuAbove { EmojiSuggestionMenu(suggestions: box(Scene.alias.rows)) }
            .padding(.top, room)
    }

    /// Výška, kterou si nabídka řekne na dané šířce. Měří se na `NSHostingView`, tedy na tom, na čem
    /// se kreslí.
    private func height(of rows: [Policy.EmojiSuggestion], width: Double) -> Double {
        let view = NSHostingView(
            rootView: EmojiSuggestionMenu(suggestions: Self.box(rows)).frame(width: width)
        )
        return Double(view.fittingSize.height)
    }

    /// Box s otevřenou nabídkou. **Sonda ho plní přímo**, protože klávesnici nemá — pole ho
    /// v aplikaci plní z `Policy.emojiSuggestions`, tedy z týchž řádků.
    private static func box(_ rows: [Policy.EmojiSuggestion]) -> EmojiSuggestionBox {
        let box = EmojiSuggestionBox()
        box.rows = rows
        return box
    }
}
