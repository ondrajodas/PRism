import SwiftUI

/// Hlavní okno: vlevo seznam PR, vpravo místo pro diff a nálezy.
struct ContentView: View {
    /// Store vlastní `PreflightModel` nad oknem, ne tohle view — okno nastavení je vlastní
    /// scéna a k `@State` uvnitř okna by se nedostalo.
    let store: AppStore
    @Environment(\.scenePhase) private var scenePhase

    /// Rozdělané odeslání review. `nil` = potvrzovací sheet je zavřený.
    ///
    /// Bydlí **tady, ne v detailu PR**, ačkoli se tam zakládá. Detail se kreslí jen tak dlouho,
    /// dokud je vybraný PR v seznamu z pollingu — a odeslané review ruší `review-requested`,
    /// takže právě ten PR z výchozího zdroje na příštím tiku **vypadne**. Sheet zavěšený na
    /// detailu by tím zmizel bez stopy: uprostřed odesílání, nebo zrovna nad hláškou „odpovědi
    /// nerozumím, zkontroluj to na GitHubu“, která je jediným místem, kde se to člověk dozví.
    /// Modalita proti tomu nechrání, ta zastaví uživatele, ne tik pollingu.
    ///
    /// Ve store to naopak být nesmí: objekt má zaniknout se zavřením sheetu, protože v něm
    /// vzniká jediná cesta ven (tvrdá podmínka č. 1).
    @State private var submission: ReviewSubmission?

    var body: some View {
        VStack(spacing: 0) {
            NavigationSplitView {
                PullRequestListView(store: store)
                    .navigationSplitViewColumnWidth(min: 320, ideal: 380, max: 520)
            } detail: {
                detail
            }
            // Stavový řádek je **přes celé okno a mimo split view** (#72, #31). Pod seznamem
            // PR to byl `safeAreaInset`, kvůli kterému obsah okna vycházel o výšku pruhu
            // vyšší než okno a spodní hrana ho odřízla v obou sloupcích — podrobnosti
            // v `AppNoticesView`.
            StatusBarView(store: store)
        }
        // Potvrzení odeslání. `item:`, ne `isPresented:`: sheet nemá co ukazovat bez snímku
        // draftu, takže `nil` je zavřený stav i zdroj dat naráz.
        .sheet(item: $submission) { submission in
            ReviewSubmissionSheet(submission: submission) { self.submission = nil }
        }
        // **Ztmavení, ne rozostření.** `.blur()` protlačí celé okno přes offscreen
        // vykreslení, a to i s poloměrem 0 — text tím ztratí subpixelové vyhlazení a
        // v seznamu, diffu i hlavičce vypadá rozmazaně a „skáče“. Ověřeno tím, že se
        // modifikátor odebral: bez něj je vykreslení v pořádku.
        //
        // Podmíněně ho aplikovat nejde: `if` kolem `NavigationSplitView` mu změní identitu
        // a otevření nastavení by zahodilo pozici scrollu v diffu. Překryv s nulovou
        // průhledností nic nerasterizuje, takže tuhle daň nemá.
        .overlay {
            Color.black
                .opacity(store.isSettingsFrontmost ? 0.18 : 0)
                // Klik má okno vybrat, ne se zastavit o překryv.
                .allowsHitTesting(false)
                .animation(.easeInOut(duration: 0.18), value: store.isSettingsFrontmost)
        }
        // Smyčka žije, dokud žije okno — zavření okna task zruší a polling se zastaví.
        .task { await store.keepFresh() }
        // Konfigurace se edituje v souboru mimo aplikaci, takže se načte pokaždé, když se
        // do ní člověk vrátí. Sledovat soubor by znamenalo řešit atomický zápis, po kterém
        // hlídaný deskriptor přestane platit — a tlačítko by byl krok navíc za něco, co se
        // dá udělat samo.
        .onChange(of: scenePhase) { _, phase in
            // Na pozadí se dostupnost služeb nekontroluje — aplikace, kterou nikdo nevidí,
            // nemá komu svítit puntíkem. `.inactive` je pořád vidět (okno jen není vepředu),
            // takže se hlídá jen `.background`: zavřené, skryté nebo minimalizované okno.
            store.windowVisibilityChanged(phase != .background)
            guard phase == .active else { return }
            Task { await store.reloadConfiguration() }
        }
    }

    @ViewBuilder private var detail: some View {
        if let selected = store.pullRequests.first(where: { $0.id == store.selection }) {
            PullRequestDetailView(store: store, pullRequest: selected, submission: $submission)
        } else {
            ContentUnavailableView(
                "Vyber pull request",
                systemImage: "sidebar.left",
                description: Text("Vlevo je seznam PR, u kterých se po tobě chce review.")
            )
        }
    }
}
