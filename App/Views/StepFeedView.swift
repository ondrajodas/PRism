import SwiftUI

/// Živý výpis kroků pod fázemi dráhy — druhá vrstva tabu `Průběh` (#325, sekce 20 návrhu).
///
/// **Okno o pevné výšce, ne rostoucí blok.** Blok, který roste s každou událostí, posune všechno
/// pod sebou — a to je přerovnání celého tabu několikrát za vteřinu. Výpis je proto vlastní scroll
/// a přibývající řádek hýbe jen s ním; dráha nad ním se nehne vůbec.
///
/// **Próza modelu se nekreslí.** Otázka, kvůli které se do `Průběhu` chodí, je „koukal se tam, kam
/// měl“, a odpověď na ni jsou nástroje, ne úvahy. Próza je řádově víc dat a v okně o pevné výšce by
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

    /// Výška okna. **Pevná, a to je celý smysl** — viz komentář u typu. Sedm řádků a osmý
    /// useknutý hranou, tedy z výpisu je poznat, že se scrolluje (138 bodů jako v návrhu).
    private static let windowHeight = 138.0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if state == .expanded { window }
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
                    // uprostřed. V hlavičce proto, že ta je vidět i sbalená.
                    if let shortfall = ReviewerLaneText.stepShortfall(lane.droppedEntries) {
                        Text(verbatim: shortfall)
                            .font(.caption)
                            .foregroundStyle(Palette.stale)
                    }
                    Spacer(minLength: 8)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            if state == .expanded {
                tailToggle
            } else {
                Text(verbatim: ReviewerLaneText.expandFeed)
                    .font(.caption)
            }
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

    private var window: some View {
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
            .frame(height: Self.windowHeight)
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
            if let cut = ReviewerLaneText.stepCut(lane.droppedEntries) { cutRow(cut) }
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
