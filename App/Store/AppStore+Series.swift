import Foundation

/// Série pull requestů (#513) — PR, jehož base větev je hlavou jiného otevřeného PR.
///
/// Odpovědnost storu je tady jediná: **spojit dvě cesty k větvím do jedné odpovědi** a nabídnout
/// ji tak, aby si kresba nic nepočítala sama. Rozhodování je v `Policy`.
extension AppStore {
    /// Větve toho PR. `nil` = nevíme.
    ///
    /// **Dva zdroje, jedno čtení.** Rozhlídka po hlavách (#420, od #513 s větvemi) pokrývá **cizí
    /// frontu**, načtený detail **vlastní PR a otevřené záložky** — a obojí je táž hodnota
    /// z GitHubu, ne dvě pravdy. Detail má přednost, protože je čerstvější u toho PR, na které se
    /// zrovna koukám: hlavičku si při otevření dotahuje záložka sama.
    func branchRefs(for pullRequest: PRIdentifier) -> BranchRefs? {
        if case .loaded(let detail, _) = detailStates[pullRequest], let refs = BranchRefs(detail) {
            return refs
        }
        return probedBranchRefs[pullRequest]
    }

    /// Série v dnešním seznamu (#513).
    ///
    /// **Nad plným seznamem**, ne nad zúženým filtrem ani odložením: stát na cizí větvi je
    /// vlastnost pull requestu, ne toho, co je zrovna vidět. Co se z toho **nakreslí**, rozhoduje
    /// `queueSeriesCaptions` nad tím, co v seznamu doopravdy zbylo.
    ///
    /// **Počítá se při čtení, necachuje se — a je to změřené, ne odhadnuté.** Jeden průchod
    /// (`Policy.series`) stojí nad dvacetičlennou frontou **153 µs** v Debug buildu (nad šedesáti
    /// 1,0 ms); seznam se z toho poskládá třemi průchody, tedy kolem půl milisekundy na jedno
    /// sestavení řádků — a to se neděje na snímek, ale na změnu stavu. Cache by musela říct, co ji
    /// vyprazdňuje (#224): seznam z tiku, každý načtený detail **a** každá rozhlídka po hlavách —
    /// tři invalidace za čtyři procenta snímku se neplatí.
    var pullRequestSeries: [PullRequestSeries] {
        Policy.series(in: pullRequests, refs: branchRefs(for:))
    }

    /// Kde v sérii ten PR stojí. `nil` = v žádné není.
    func seriesPlacement(for pullRequest: PRIdentifier) -> SeriesPlacement? {
        Policy.seriesPlacement(of: pullRequest, in: pullRequestSeries, refs: branchRefs(for:))
    }

    /// Popisky nad skupinami **ve frontě** — klíčem je první nakreslený člen série (#513).
    ///
    /// Počítá se nad `visibleQueuePullRequests`, tedy nad tím, co seznam doopravdy kreslí: členy
    /// z něj vyndá filtr i odložení, a popisek `2 PR` nad jedním řádkem by tvrdil víc, než je vidět.
    var queueSeriesCaptions: [PRIdentifier: String] {
        Policy.seriesCaptions(in: visibleQueuePullRequests, series: pullRequestSeries)
    }

    /// Věta pod souřadnicemi v hlavičce — `Diff je jen tahle vrstva: 4 soubory nad #726.` (#513)
    ///
    /// `nil` u PR, který v sérii není nebo je jejím základem. Počet souborů se bere z **načteného**
    /// diffu; dokud nedorazil, věta číslo vynechá (`Policy.seriesNote`).
    func seriesNote(for pullRequest: PRIdentifier) -> String? {
        guard let placement = seriesPlacement(for: pullRequest) else { return nil }
        var files: Int?
        if case .loaded(let diff, _) = diffState(for: pullRequest) { files = diff.files.count }
        return Policy.seriesNote(placement, changedFiles: files)
    }
}
