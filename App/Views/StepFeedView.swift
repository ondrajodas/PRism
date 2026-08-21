import SwiftUI

/// Živý výpis kroků pod fázemi dráhy — druhá vrstva tabu `Průběh` (#325, sekce 20 návrhu).
///
/// **Okno se stropem, ne rostoucí blok.** Blok, který roste s každou událostí, posune všechno pod
/// sebou — a to je přerovnání celého tabu několikrát za vteřinu. Výpis je proto vlastní scroll
/// se stropem a přibývající řádek hýbe jen s ním; dráha nad ním se nehne vůbec.
///
/// **Do stropu je to ale výška obsahu.** Pevná výška od začátku znamenala, že krátký běh nakreslil
/// okno vysoké 138 bodů a dvě třetiny z něj byly prázdné, což je stav, ve kterém každé review
/// začíná. Roste se proto jen po strop (`Policy.stepFeedWindow`) — cena za to je přerovnání pod
/// prvními osmi událostmi běhu, ne pod každou.
///
/// **Próza modelu se nekreslí.** Otázka, kvůli které se do `Průběhu` chodí, je „koukal se tam, kam
/// měl“, a odpověď na ni jsou nástroje, ne úvahy. Próza je řádově víc dat a v okně se stropem by
/// kroky vytlačila z dohledu, tedy zhoršila přesně to, kvůli čemu výpis vzniká. Kdo ji potřebuje,
/// má `claude --resume` v hlavičce dráhy.
///
/// **Vestavěný terminál to není a nemá být**: řeší **zásah** do běžící session, tohle **sledování**.
/// Do výpisu se nedá psát.
struct StepFeedView: View {
    let lane: ReviewerLane
    /// Sbalený, nebo rozbalený. Rozhoduje **tab** (`StepFeedExpansion`), ne tohle view — `@State`
    /// uvnitř dráhy se v líném seznamu zahodí odrolováním (#325).
    let state: StepFeedState
    let toggle: () -> Void

    /// Drží se výpis u nejnovějšího kroku?
    ///
    /// **Jeden `Bool`, ne poloha scrollu.** Co se při scrollování mění, nesmí být v observable
    /// stavu (#252), takže se offset nikam nezapisuje — sem se píše jedině tehdy, když se
    /// **změní odpověď** na otázku „je výpis na konci?“ (viz `onScrollGeometryChange` níž).
    ///
    /// Neukládá se: je to gesto v jednom běhu, ne nastavení. #242 klíč `progressFollowsTail`
    /// zrušilo jako „stav, který se drží a nikdo ho nečte“, a ten důvod trvá — mýlilo se jen v tom,
    /// že není co následovat.
    @State private var followsTail = true

    /// `id` nejnovější události ve chvíli, kdy se konec přestal sledovat. Z něj se počítá pilulka
    /// `↓ N nových`. `nil` = konec se sleduje, takže není co dohánět.
    @State private var arrivalAnchor: Int?

    /// Dohání výpis nový krok? Viz `catchUp(in:)`.
    @State private var isCatchingUp = false

    /// `id` kroku, na který se naposledy posunulo. Drží se proto, že **výška obsahu se při
    /// rozvržení mění i naplano** (změřeno `1825 → 3505 → 1825` na jedné scéně), takže sama o sobě
    /// není doklad, že přišel nový krok — a posun naplano by přebil člověka, který si zrovna
    /// odroloval nahoru.
    @State private var stuckAt: Int?

    /// Vzduch nad prvním a pod posledním řádkem (`.scroll { padding: 5px 0 }` v návrhu).
    ///
    /// **`internal` schválně, kvůli testu** (`StepFeedTailTests`): sledování konce se o tuhle
    /// hodnotu opírá, takže test, který by si ji opsal, by hlídal jiné číslo než to, na kterém
    /// okno stojí.
    static let rowsInset = 5.0

    /// Výška řádku s řezem na začátku výpisu — `caption2` plus svislé odsazení.
    ///
    /// Měří se tady, protože `cutRow(_:)` se kreslí tady (#236), a je to **změřená sazba, ne
    /// nasazený rámec** — ze stejného důvodu jako u `TimelineEntryRow.height`. Do výšky okna se
    /// počítá jen tehdy, když se ten řádek doopravdy kreslí; obojí rozhoduje `cutText`, aby to
    /// byla jedna pravda.
    static let cutRowHeight = 21.0

    /// Strop výšky okna: osm řádků a devátý useknutý hranou, tedy z výpisu je poznat, že se
    /// scrolluje (138 bodů, `.stepfeed .rows { max-height }` v návrhu). Že strop **není** celý
    /// počet řádků, hlídá test — kdyby na řádky vyšel přesně, vypadal by rolovatelný výpis jako
    /// celý.
    ///
    /// **Rozměry pohromadě a `internal` schválně, kvůli testu**: `StepFeedWindowTests` počítají
    /// tímtéž vstupem, jakým počítá okno — vlastní kopie čísel v testu by hlídala jinou výšku, než
    /// na které okno stojí.
    static let metrics = StepFeedMetrics(
        row: TimelineEntryRow.height,
        cut: cutRowHeight,
        inset: rowsInset,
        cap: 138
    )

    /// Řez na začátku výpisu, nebo `nil` u neořezané osy. **Jedna pravda pro kresbu i pro výšku** —
    /// dvě podmínky o tomtéž řádku by se rozešly a okno by o něj přerostlo obsah.
    private var cutText: String? { ReviewerLaneText.stepCut(lane.droppedEntries) }

    /// Jak vysoké okno je a je-li v něm co rolovat. Rozhoduje `Policy`, tady se jen dodají rozměry.
    private var window: StepFeedWindow {
        Policy.stepFeedWindow(rows: lane.entries.count, cut: cutText != nil, metrics: Self.metrics)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if state == .expanded { feedWindow }
        }
        .overlay(alignment: .top) { Rectangle().fill(Palette.lineSoft).frame(height: 1) }
    }

    // MARK: - Hlavička

    /// Hlavička výpisu — a **sbalený řádek je ona, jen zavřená**, takže je to jedno místo, ne dvě.
    private var header: some View {
        HStack(spacing: 8) {
            Button(action: toggle) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .rotationEffect(.degrees(state == .expanded ? 90 : 0))
                        .font(.caption2)
                    Text(verbatim: ReviewerLaneText.stepCount(lane.entries.count))
                        .font(.caption)
                        .monospacedDigit()
                    // Zkrácená osa to musí říct (#203, #325) — jinak vypadá, že běh začal
                    // uprostřed. V hlavičce proto, že ta je vidět i sbalená. Bere se
                    // z `droppedEntries`, ne z `cutText`: hlavička mluví o celém běhu, řez o tom,
                    // co v okně chybí nad prvním řádkem.
                    if let shortfall = ReviewerLaneText.stepShortfall(lane.droppedEntries) {
                        Text(verbatim: shortfall)
                            .font(.caption)
                            .foregroundStyle(Palette.stale)
                    }
                    Spacer(minLength: 8)
                    // Sbalený řádek je klikací **celý, včetně slova `rozbalit`** — mimo tlačítko
                    // by ten text sliboval klik, který nic nedělá.
                    if state == .collapsed {
                        Text(verbatim: ReviewerLaneText.expandFeed)
                            .font(.caption)
                    }
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            // **Jen když je co rolovat.** Nad obsahem, který se vejde celý, by to byla nabídka,
            // která nedělá nic — a zašedlá by tvrdila „tady se to dělá, jen teď ne“, kdežto tady
            // není co následovat vůbec (`Policy.stepFeedAtEnd` u krátkého obsahu vrací `true`).
            if state == .expanded, window.scrolls { tailToggle }
        }
        .foregroundStyle(Palette.ink3)
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, state == .expanded ? 6 : 10)
    }

    /// Přepínač `Sledovat konec`. **Zapnutý je stav, ne akce**, takže nese barvu běžícího kroku
    /// (`find`), ne akcentovou.
    private var tailToggle: some View {
        Button {
            followsTail.toggle()
        } label: {
            HStack(spacing: 5) {
                Circle()
                    .fill(followsTail ? Palette.find : Palette.ink3)
                    .frame(width: 6, height: 6)
                Text(verbatim: ReviewerLaneText.followTail)
                    .font(.caption2)
                    .fontWeight(followsTail ? .semibold : .regular)
            }
            .foregroundStyle(followsTail ? Palette.find : Palette.ink3)
            .padding(.horizontal, 8)
            .padding(.vertical, 1)
            .background(followsTail ? Palette.find.opacity(0.12) : Palette.chrome, in: .capsule)
            .overlay {
                Capsule().strokeBorder(followsTail ? Palette.find.opacity(0.45) : Palette.line, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .help(ReviewerLaneText.followTailHelp)
        .accessibilityAddTraits(followsTail ? [.isSelected] : [])
    }

    // MARK: - Okno s kroky

    private var feedWindow: some View {
        ScrollViewReader { proxy in
            ScrollView {
                rows
            }
            // Krátký obsah stojí **u dolní hrany**, jak to má návrh: nejnovější krok je celý vidět.
            .defaultScrollAnchor(.bottom)
            // Poloha scrollu a výška obsahu → **jedna hodnota, jeden callback**. Transformace běží
            // při každém přepočtu geometrie, **akce jen při změně hodnoty** (#361), takže se do
            // stavu píše jedině na přechodu — bezpodmínečný zápis by byl kolo z #358.
            //
            // Od dolní hrany se odečítá vnitřní odsazení řádků: **konec znamená „nejnovější krok je
            // celý vidět“**, ne „scroll dojel na poslední bod obsahu“ — pod posledním řádkem je
            // `rowsInset` bodů vzduchu a čekat i na ně by znamenalo, že se konec nesleduje nikdy
            // (změřeno, `StepFeedTailTests`).
            .onScrollGeometryChange(for: FeedGeometry.self) { geometry in
                FeedGeometry(
                    isAtEnd: Policy.stepFeedAtEnd(
                        offset: geometry.contentOffset.y,
                        visible: geometry.containerSize.height,
                        content: geometry.contentSize.height - Self.rowsInset
                    ),
                    contentHeight: geometry.contentSize.height
                )
            } action: { old, new in
                react(from: old, to: new, in: proxy)
            }
            // **Jediné místo, kde se sledování konce dopočítává do zbytku stavu** — ať se to
            // přepne odrolováním, klikem na přepínač nebo klikem na pilulku:
            //
            // - kotva pro `↓ N nových` se bere z chvíle, kdy se konec **přestal** sledovat (kdyby ji
            //   nastavovalo jen odrolování, po vypnutí klikem by pilulka nepřišla nikdy);
            // - `stuckAt` se zahazuje, protože na tomhle kroku už výpis jednou byl, ale mezitím se
            //   odrolovalo — takže se tam musí dostat znovu;
            // - a zapnutý přepínač musí **dojet na konec**, jinak by se projevil až příští událostí.
            .onChange(of: followsTail) { _, follows in
                arrivalAnchor = follows ? nil : lane.entries.last?.id
                stuckAt = nil
                catchUp(in: proxy)
            }
            // Když se rolovat přestalo (osa se zkrátila novým během téhož revieweera), je výpis na
            // konci z definice — a sledování se proto vrací na zapnuté. Bez toho by tu zůstalo
            // vypnuté z minula a **až** by obsah zase přerostl strop, výpis by konec nesledoval,
            // aniž by na to bylo kde přijít: přepínač je do té doby schovaný.
            .onChange(of: window.scrolls) { _, scrolls in
                if !scrolls { followsTail = true }
            }
            .frame(height: window.height)
            .background(Palette.chrome)
            .clipShape(.rect(cornerRadius: 6))
            .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(Palette.lineSoft, lineWidth: 1) }
            // **Vpravo dole, ne na střed**: uprostřed by pilulka seděla na textu řádku, který má
            // člověk zrovna číst.
            .overlay(alignment: .bottomTrailing) { arrivals }
            .padding(.horizontal, 12)
            .padding(.bottom, 11)
        }
    }

    private var rows: some View {
        // **Líný**, i když je okno vysoké 138 bodů: prvek, který se nekreslí, se pořád umisťuje
        // (#252), a při třech stech krocích je to tři sta umístění při každém přerovnání obsahu.
        LazyVStack(alignment: .leading, spacing: 0) {
            // Řez na místě, kde ta useknutá část byla — druhé přiznání zkrácení (#325).
            if let cut = cutText { cutRow(cut) }
            ForEach(lane.entries) { entry in
                TimelineEntryRow(
                    entry: entry,
                    worktree: lane.worktree,
                    isNewest: entry.id == lane.entries.last?.id
                )
            }
        }
        .padding(.vertical, Self.rowsInset)
    }

    private func cutRow(_ text: String) -> some View {
        HStack(spacing: 7) {
            Text(verbatim: text)
                .font(.caption2)
                .foregroundStyle(Palette.stale)
            Rectangle()
                .fill(Palette.line)
                .frame(height: 1)
        }
        .padding(.horizontal, 11)
        .padding(.top, 3)
        .padding(.bottom, 5)
        .overlay(alignment: .bottom) { Rectangle().fill(Palette.line).frame(height: 1) }
    }

    /// `↓ N nových`, když se konec nesleduje a mezitím něco přišlo.
    @ViewBuilder
    private var arrivals: some View {
        if let count = Policy.stepFeedArrivals(
            scrolls: window.scrolls,
            follows: followsTail,
            newest: lane.entries.last?.id,
            anchor: arrivalAnchor
        ) {
            Button {
                followsTail = true
            } label: {
                Text(verbatim: ReviewerLaneText.stepArrivals(count))
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .foregroundStyle(Palette.surface)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 2)
                    .background(Palette.find, in: .capsule)
            }
            .buttonStyle(.plain)
            .padding(.trailing, 9)
            .padding(.bottom, 4)
        }
    }

    /// Co se o výpisu čte z geometrie scrollu — **dvě hodnoty pohromadě**, protože jedna bez druhé
    /// vede ke špatnému rozhodnutí; viz `Policy.stepFeedReaction(grew:isAtEnd:isCatchingUp:)`.
    private struct FeedGeometry: Equatable {
        let isAtEnd: Bool
        let contentHeight: Double
    }

    /// Rozhodnutí je v `Policy`, tady se jen provádí.
    private func react(from old: FeedGeometry, to new: FeedGeometry, in proxy: ScrollViewProxy) {
        switch Policy.stepFeedReaction(
            grew: old.contentHeight != new.contentHeight,
            isAtEnd: new.isAtEnd,
            isCatchingUp: isCatchingUp
        ) {
        case .catchUp: catchUp(in: proxy)
        case .follow(let follows): setFollows(follows)
        case .ignore: break
        }
    }

    /// Dojede výpis na nejnovější krok — **jen se zapnutým sledováním konce**.
    ///
    /// **Posouvá se o kolo později (`Task`), a je to změřené, ne opatrnost.** Posun ve **stejném**
    /// průchodu, ve kterém se obsah přerovnal, SwiftUI zahodí: výpis zůstal 20 bodů od konce (řádek
    /// plus vnitřní odsazení) a nedojel tam ani po pěti kolech smyčky. Je to tatáž past jako
    /// u fokusu do textového pole (#184) — rozhoduje **počet průchodů, ne čas**, takže se nečeká
    /// časovačem (a ten je navíc zakázaná třída, #350).
    ///
    /// A **musí to být z geometrie, ne z dat**: posun navěšený na `id` posledního kroku doběhl moc
    /// brzo (řádek ještě nebyl rozvržený) a výpis zůstal o řádek pozadu — taky změřeno.
    ///
    /// `Task` je tady **na hlavním aktoru**, i když to na něm není napsané: konformance k `View`
    /// dělá z typu `@MainActor` (#219) a `Task.init` izolaci volajícího dědí. Není to úvaha, ale
    /// vlastnost, kterou v jazykovém režimu Swift 6 vynucuje překladač — `Task.detached` na tomtéž
    /// místě neprojde (`passing closure as a 'sending' parameter risks causing data races between
    /// main actor-isolated code…`, vyzkoušeno). Nálezem Copilota na #402.
    private func catchUp(in proxy: ScrollViewProxy) {
        guard followsTail, let newest = lane.entries.last?.id, newest != stuckAt else { return }
        stuckAt = newest
        isCatchingUp = true
        Task {
            proxy.scrollTo(newest, anchor: .bottom)
            isCatchingUp = false
        }
    }

    /// Zapisuje se **jen na přechodu**: hodnota sem chodí sice už profiltrovaná
    /// `onScrollGeometryChange`em, ale ten filtruje **celou** `FeedGeometry`, takže na tenhle `Bool`
    /// dojde i tehdy, když se změnila jen výška obsahu. Zbytek stavu se dopočítá v `onChange`.
    private func setFollows(_ atEnd: Bool) {
        guard followsTail != atEnd else { return }
        followsTail = atEnd
    }
}
