import SwiftUI

/// Pruh záložek nad obsahem okna (#180).
///
/// Domácí záložka plus otevřená review. Tečka u záložky nese **stav toho review**, takže je
/// z pruhu vidět, co běží a kde leží rozdělaná práce, aniž by se na tu záložku muselo přepnout —
/// a přesně to bylo do #180 neviditelné.
///
/// **Od #527 má značka pět podob** a rozhoduje o nich `Policy.tabMark`: k běhu, rozdělanému
/// review a stavu review přibyla **obnovená záložka bez detailu** (dutý kroužek) a **mergnutý
/// nebo zavřený pull request** (jeho vlastní barva).
struct ReviewTabsView: View {
    @Binding var active: WindowTab
    let tabs: [PullRequestSummary]
    /// Co se u záložky nakreslí. **Jedna otázka, ne tři vstupy** (#527): do té doby si view
    /// bralo `state`, `hasDraft` a `isRunning` a rozhodovalo `if`y ve třech patrech — s pátým
    /// stavem (obnovená záložka, mergnutý PR) je to rozhodnutí, které patří do `Policy`, kde se
    /// dá vyčerpat výčtem. Skládá ho store (`AppStore.tabMark(for:)`).
    let mark: (PRIdentifier) -> WindowTabMark
    let close: (PRIdentifier) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 4) {
                homeTab
                ForEach(tabs, id: \.id) { tab($0) }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
        }
        .scrollIndicators(.never)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Domácí záložka **se jménem**, ne jen s ikonou: je to jediná záložka, která neukazuje
    /// pull request, takže by z domečku mezi `repo#číslo` nebylo poznat, co za ní je.
    private var homeTab: some View {
        Button { active = .home } label: {
            HStack(spacing: 8) {
                Image(systemName: "house")
                    .font(.system(size: 11))
                Text("Přehled")
                    .font(.system(size: 12.5))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .chrome(isActive: active == .home)
        }
        .buttonStyle(.plain)
        // Nese i **zkratky pruhu** (#245), protože `⌃Tab` po sobě v okně nenechává žádnou
        // viditelnou stopu — bez tohohle by se dala najít jedině v release notes. Sedí to na
        // domácí záložce ze dvou důvodů: v pruhu je **vždycky** a jako jediná mluví o pruhu, ne
        // o pull requestu (u těch je v nápovědě titulek, který je tam potřebnější).
        //
        // **Na samotném pruhu to nejde** — `.help` nad `ScrollView`em se nikde neprojeví;
        // změřeno na běžící aplikaci: `AXScrollArea` hlavičky zůstal bez `AXHelp`, kdežto
        // tlačítka záložek svoje nápovědy nesou.
        .help(
            // Zkratky z katalogu (#441), ne napsané vedle klávesy.
            """
            Fronta a rozdělaná review — mezi záložkami přepíná \
            \(Policy.windowShortcut(.nextTab).display) a \
            \(Policy.windowShortcut(.previousTab).display)
            """
        )
    }


    private func tab(_ summary: PullRequestSummary) -> some View {
        let item = WindowTab.pullRequest(summary.id)
        let isActive = active == item
        return HStack(spacing: 8) {
            dot(for: summary.id)
            // `verbatim`: `repo#číslo` není věta a číslo PR není množství k formátování.
            Text(verbatim: "\(summary.repo.name)#\(summary.number)")
                .font(.system(size: 11.5, design: .monospaced))
                .lineLimit(1)
            Button { close(summary.id) } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Palette.ink3)
            .help("\(Policy.shortcutHelp("Zavřít záložku", .closeTab)) — nic se tím nezahodí")
            .accessibilityLabel("Zavřít \(summary.repo.name)#\(summary.number)")
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 5)
        .chrome(isActive: isActive)
        .contentShape(.rect)
        .onTapGesture { active = item }
        .help(summary.title)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(summary.title)
        .accessibilityAddTraits(isActive ? [.isSelected, .isButton] : .isButton)
    }

    /// Značka stavu — pět podob podle toho, co se s PR zrovna děje. **Pořadí rozhoduje
    /// `Policy.tabMark`**, ne `if`y tady: je to rozhodnutí nad daty, ne kresba.
    @ViewBuilder private func dot(for id: PRIdentifier) -> some View {
        switch mark(id) {
        case .running:
            SpinningRing()
                .help("Review běží")
                .accessibilityLabel("Review běží")
        case .loading:
            loadingRing
        case .draft:
            Image(systemName: "square.and.pencil")
                .font(.system(size: 9))
                .foregroundStyle(.tint)
                .help("Leží tu rozdělané review")
        case .pullRequest(let state):
            Circle()
                .fill(PullRequestStateAppearance.color(of: state))
                .frame(width: 6, height: 6)
                .help("Pull request je \(state.czechLabel) — dá se dočíst a zavřít")
        case .review(let state):
            Circle()
                .fill(ReviewStateAppearance.color(of: state))
                .frame(width: 6, height: 6)
                .help(ReviewStateAppearance.label(of: state))
        }
    }

    /// Přijatá záložka, jejíž detail ještě nedorazil (#527, `.tdot-load` v sekci 44 návrhu) —
    /// obnovená po restartu, nebo otevřená odkazem (#531).
    ///
    /// **Dutý kroužek, ne plný puntík a ne prstýnek**, a je to celý obsah toho rozhodnutí. Plný
    /// puntík nese v pruhu **stav review**, a ten se u záložky, o které se ještě nic neví, nemá
    /// odkud vzít — nakreslil by tedy stav z minula. Prstýnek (`SpinningRing`) znamená **běží
    /// review**, a po startu neběží nic (obnovení nespouští nic), takže by o sobě záložka
    /// tvrdila víc, než co data unesou.
    ///
    /// **Nehybný schválně**, i když se na pozadí doopravdy dotahuje: pohyb v pruhu je v tomhle
    /// okně vyhrazený běžícímu review. A jako bonus se tím tenhle stav nedostane do třídy
    /// zakázaných nekonečných animací (#350) — kroužek je čistá kresba, nic se netočí.
    ///
    /// `--ink-3` (`Palette.ink3`), tedy tichá šedá: je to „nemám co říct“, ne barva ze škály —
    /// tatáž role, jakou má `.secondary` u `ReviewState.notStarted`.
    private var loadingRing: some View {
        Circle()
            .strokeBorder(Palette.ink3, lineWidth: 1.5)
            .frame(width: 8, height: 8)
            // **Neutrálně**, ne „vrátila se po restartu“: tenhle stav dostane i záložka otevřená
            // odkazem, u které se detail teprve dotahuje (#531) — a nápověda, která mluví
            // o restartu, by u ní tvrdila něco, co se nestalo.
            .help("Načítám pull request — o téhle záložce se zatím ví jenom adresa")
            .accessibilityLabel("Načítá se")
    }

}

private extension View {
    /// Vzhled záložky. **Aktivní má výplň i obrys**, ne jen jinou barvu textu: v titulkové liště
    /// jsou záložky blízko u sebe a bez ohraničení splynou v jednu řádku slov — a nedá se pak
    /// poznat, kde jedna končí. Obrys drží i to, že je aktivní záložka vidět na tmavém i světlém
    /// pozadí lišty, kde samotná výplň skoro zmizí.
    func chrome(isActive: Bool) -> some View {
        background(
            isActive ? AnyShapeStyle(Palette.raised) : AnyShapeStyle(.clear),
            in: .rect(cornerRadius: 7)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                // Obrys z palety, ne `.separator`: systémový oddělovač je v tmavé liště tak
                // jemný, že aktivní záložka splyne s pozadím a pruh se čte jako řada slov.
                .strokeBorder(Palette.line, lineWidth: isActive ? 1 : 0)
        }
        .foregroundStyle(isActive ? Palette.ink : Palette.ink2)
    }
}

/// Kroužek s rotujícím obloukem — značka běžícího review v záložce (#180).
///
/// **Ne `ProgressView`.** Systémový spinner na macOS je paprskové kolečko a v pruhu záložek
/// vypadá jako ozubené kolo mezi tečkami stavů; návrh má prstýnek, který se točí. Vedle toho je
/// `ProgressView` řízený AppKitem, takže se nedá zmenšit na velikost tečky, aniž by zhrubl.
///
/// Barva je **systémový akcent**, ne fialová z návrhu: fialová je v mockupu proto, že HTML žádný
/// systémový akcent nemá, kdežto v okně by byla jediná barva, která se neřídí nastavením systému —
/// a ikona rozdělaného review hned vedle ho používá taky.
///
/// **Točí se v CoreAnimation, ne ve SwiftUI, a je to podmínka, ne vkus** (#350). Do #350 to byl
/// `withAnimation(.linear.repeatForever)` nad `@State` úhlem — a nekonečná animace ve SwiftUI
/// znamená **nový snímek při každém obtažení obrazovky**, přičemž každý snímek jde přes
/// `NSHostingView.layout()`, které rozvrhne **celé okno** (a dvakrát: jednou pro kresbu, jednou pro
/// `minSize` do constraints). Změřeno sondou `IdleWindowSpinProbe`: nečinné okno s detailem PR
/// stálo s prstýnkem ve SwiftUI **99 % CPU** hlavního vlákna, s otáčením v CoreAnimation **2–3 %**,
/// tedy tolik, kolik stojí totéž okno bez prstýnku. V provozu z toho bylo okno, které se nedalo
/// ovládat, a `bin/run.sh` na něm padal na `-1712`, protože Apple event na ukončení nedostal
/// odpověď.
///
/// CoreAnimation proti tomu točí vrstvou v render serveru: hlavní vlákno o tom neví a SwiftUI
/// nedostane ani jeden snímek. Cena je, že se ta kresba musí napsat v AppKitu — proto ten
/// `NSViewRepresentable` níž.
struct SpinningRing: View {
    var size: CGFloat = 11
    var lineWidth: CGFloat = 2

    /// Vypnutý pohyb v systému. Prstýnek pak **stojí** — je nedokončený, takže je z něj pořád
    /// poznat, že se něco děje, jen se netočí.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        SpinningRingLayer(lineWidth: lineWidth, isSpinning: !reduceMotion)
            .frame(width: size, height: size)
    }
}

/// Prstýnek jako AppKitová vrstva — kresba i otáčení v CoreAnimation (#350).
private struct SpinningRingLayer: NSViewRepresentable {
    let lineWidth: CGFloat
    let isSpinning: Bool

    func makeNSView(context: Context) -> SpinningRingView {
        SpinningRingView(lineWidth: lineWidth, isSpinning: isSpinning)
    }

    func updateNSView(_ view: SpinningRingView, context: Context) {
        view.apply(lineWidth: lineWidth, isSpinning: isSpinning)
    }
}

/// Kruh s rotujícím obloukem, celý v `CAShapeLayer`.
///
/// **Barvy se resolvují znovu** (`resolveColours()`), ne jednou v initu: `CGColor` ve vrstvě se sám
/// podle vzhledu nepřebarví, takže by prstýnek zůstal v barvě z doby svého vzniku.
///
/// **A vyžádat si to musí každá změna zvlášť** — vzhled přes `viewDidChangeEffectiveAppearance()`,
/// akcent přes `NSColor.systemColorsDidChangeNotification`. Ve SwiftUI se `.tint` resolvovala sama,
/// takže tady je to práce, která s přepisem do AppKitu přišla: bez toho druhého by prstýnek po změně
/// akcentu v Nastavení systému držel starou barvu, dokud se nepřepne světlý/tmavý režim.
final class SpinningRingView: NSView {
    private let track = CAShapeLayer()
    private let arc = CAShapeLayer()
    private var lineWidth: CGFloat
    private var isSpinning: Bool

    /// Jak dlouho trvá jedna otáčka. Tatáž hodnota, jakou měla animace ve SwiftUI do #350 —
    /// mění se způsob otáčení, ne jeho tempo.
    static let turn: CFTimeInterval = 0.9
    /// Kolik kruhu je obtažené. Zbytek je tiché krytí pod ním, ze kterého je poznat, že je
    /// prstýnek nedokončený.
    static let arcShare: CGFloat = 0.3
    /// Krytí tichého kruhu pod obloukem — tolik, kolik měl ve SwiftUI (`.tint.opacity(0.25)`).
    static let trackAlpha: CGFloat = 0.25
    /// Pod jakým klíčem visí otáčení. Čte ho test — bez pojmenování by se „točí se v CoreAnimation“
    /// nedalo tvrdit jinak než okem.
    static let spinKey = "prism.spin"

    init(lineWidth: CGFloat, isSpinning: Bool) {
        self.lineWidth = lineWidth
        self.isSpinning = isSpinning
        super.init(frame: .zero)
        wantsLayer = true
        layer?.addSublayer(track)
        layer?.addSublayer(arc)
        arc.strokeEnd = Self.arcShare
        arc.lineCap = .round
        for shape in [track, arc] {
            shape.fillColor = nil
            shape.lineWidth = lineWidth
        }
        // Selektorem, ne blokem: observer registrovaný takhle nepotřebuje odregistrovat v `deinit`
        // (notifikační centrum od macOS 10.11 zaniklým observerům nedoručuje), takže tu nezůstává
        // token, na který se dá zapomenout.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(systemColoursDidChange),
            name: NSColor.systemColorsDidChangeNotification,
            object: nil
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Prstýnek se ze storyboardu nenačítá.") }

    override var wantsUpdateLayer: Bool { true }

    /// Točí se doopravdy, a v CoreAnimation? Čte to test.
    ///
    /// Bez pojmenovaného dotazu se invariant z #350 („nekonečná animace nesmí být ve SwiftUI“) nedá
    /// tvrdit jinak než okem nebo měřením CPU — a měření je strojově závislé, takže by z něj byl
    /// test padající bez chyby v kódu.
    var isSpinningInCoreAnimation: Bool { arc.animation(forKey: Self.spinKey) != nil }

    /// Jak je oblouk otočený **právě teď**, tedy hodnota z prezentační vrstvy. Čte ji sonda:
    /// nulové CPU samo o sobě nedokazuje, že se prstýnek točí — stejně dobře může stát. `nil`
    /// znamená, že vrstva zatím nemá prezentaci (okno není na obrazovce).
    var currentTurn: Double? {
        arc.presentation()?.value(forKeyPath: "transform.rotation.z") as? Double
    }

    func apply(lineWidth: CGFloat, isSpinning: Bool) {
        if lineWidth != self.lineWidth {
            self.lineWidth = lineWidth
            track.lineWidth = lineWidth
            arc.lineWidth = lineWidth
            // Cesta je o **půl tahu** zúžená dovnitř, takže se s šířkou tahu mění taky — a počítá se
            // v `layout()`. Bez tohohle by silnější tah vyjel z rámu a čekalo by se, až rozvržení
            // vyvolá něco jiného.
            needsLayout = true
        }
        guard isSpinning != self.isSpinning else { return }
        self.isSpinning = isSpinning
        updateSpin()
    }

    /// Akcent v Nastavení systému se změnil. Vzhled se přitom nemění, takže
    /// `viewDidChangeEffectiveAppearance()` nepřijde a barvu si musí vyžádat tohle.
    @objc private func systemColoursDidChange() {
        resolveColours()
    }

    /// Jakou barvou je oblouk obtažený **právě teď**. Čte to test: „notifikace si vyžádala barvy“
    /// se jinak nedá tvrdit — `updateLayer()` bez okna na obrazovce nikdo nezavolá a `needsDisplay`
    /// se u view s `wantsUpdateLayer` přepošle vrstvě, takže na view čte dál `false` (vyzkoušeno,
    /// test na něm padal nad správným kódem).
    var arcStrokeColour: CGColor? { arc.strokeColor }

    /// Vzhled se změnil (světlý/tmavý režim) — barvy se musí resolvovat znovu.
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        resolveColours()
    }

    override func updateLayer() {
        resolveColours()
    }

    /// Barvy z aktuálního vzhledu do vrstev. Volá se ze **tří** míst, protože každé z nich je jiná
    /// příležitost: první kresba (`updateLayer()`), přepnutí světlý/tmavý a změna akcentu.
    ///
    /// Nastavit `strokeColor` jde kdykoli, ne jen v kresbě — je to modelová vlastnost vrstvy, takže
    /// si o překreslení řekne CoreAnimation sama.
    private func resolveColours() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let accent = NSColor.controlAccentColor
            arc.strokeColor = accent.cgColor
            track.strokeColor = accent.withAlphaComponent(Self.trackAlpha).cgColor
        }
    }

    override func layout() {
        super.layout()
        // Cesta se kreslí v souřadnicích **vrstvy**, ne view: kdyby se vzal `bounds` s nenulovým
        // počátkem, byl by kruh odsazený o něj a z prstýnku by koukal jen kus.
        let box = CGRect(origin: .zero, size: bounds.size)
        for shape in [track, arc] {
            shape.frame = bounds
            // Otáčí se **kolem středu**, takže vrstvě patří střed jako záchytný bod — s výchozím
            // levým dolním rohem by oblouk objížděl okolo prstýnku. Poloha se dorovnává až po něm,
            // protože změna záchytného bodu vrstvou posune.
            shape.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            shape.position = CGPoint(x: bounds.midX, y: bounds.midY)
            shape.path = CGPath(
                ellipseIn: box.insetBy(dx: lineWidth / 2, dy: lineWidth / 2),
                transform: nil
            )
        }
        updateSpin()
    }

    /// Přidá nebo sundá otáčení. **Přidává se jen tehdy, když tam ještě není** — `layout()` běží
    /// vícekrát a druhé přidání by animaci restartovalo, takže by prstýnek poskakoval.
    private func updateSpin() {
        guard isSpinning else {
            arc.removeAnimation(forKey: Self.spinKey)
            return
        }
        guard arc.animation(forKey: Self.spinKey) == nil else { return }
        let spin = CABasicAnimation(keyPath: "transform.rotation.z")
        spin.fromValue = 0
        spin.toValue = -2 * Double.pi
        spin.duration = Self.turn
        spin.repeatCount = .infinity
        spin.timingFunction = CAMediaTimingFunction(name: .linear)
        // Animace **nesmí zmizet po dokončení**: bez toho by se prstýnek po první otáčce vrátil
        // do výchozí polohy a stál.
        spin.isRemovedOnCompletion = false
        arc.add(spin, forKey: Self.spinKey)
    }
}
