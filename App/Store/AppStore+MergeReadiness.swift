import Foundation

/// Slévatelnost vlastních PR **bez otevřené záložky** (#572) — to, na čem stojí pruh `K merge`
/// na domácí desce.
///
/// Do #572 se hlavička i slévatelnost dotahovaly teprve při otevření záložky, takže deska po
/// startu odpovídala `waiting` u všech vlastních PR — pravidlo z #563 („co je `mergeable`, patří
/// do `K merge`“) platilo až po otevření. **Nemění se rozhodování, mění se, kdy má data**:
/// `Policy.mergeOffer`, `isMergeReady` ani `lane` se nedotýkají.
///
/// **Jedno volání na celou sadu, ne jedno na PR.** Ptát se po jednom je ta `N+1` past, kvůli které
/// se pollingem netahá ani detail — a je změřená: 46 volání a 29,6 s proti **1 volání a 2,60–3,64 s**
/// nad týmiž 23 vlastními PR.
extension AppStore {
    /// Dotáhne hlavičku a slévatelnost vlastních otevřených PR, kterým chybí, nebo jim zestarala.
    ///
    /// **Na klidný tik nula volání.** Předfiltr (`Policy.mergeReadinessProbe`) se ptá **týmiž
    /// strážemi, jakými se ptá otevřená záložka** (`hasCurrentDetail`, `hasCurrentBranchStatus`) —
    /// dvě kopie téhle jedné podmínky by znamenaly dvě různá „už to máme“ nad jedněmi daty. Dokud
    /// se pull request nepohne, není se nač ptát a prázdný seznam se **nespouští**.
    ///
    /// **Zapisuje do týchž map jako otevřená záložka**, ne do vlastních. Dvě mapy na jednu otázku
    /// by znamenaly dvě odpovědi, které se umí rozejít — a hlavně by deska musela skládat plán
    /// merge zvlášť, tedy podruhé. Odsud tím zároveň zlevní otevření vlastního PR: hlavička
    /// i slévatelnost už jsou v cache.
    ///
    /// **Návštěva se z toho nestane** (`noteHead` se nevolá). Ledger návštěv odpovídá na „co jsem
    /// u toho PR naposledy viděl“, a zapsat mu hlavu, na kterou se nikdo nepodíval, znamená
    /// spolknout příští „přibyly commity“.
    ///
    /// **Selhání nic nemaže a nic nehlásí.** Razítka se neposunou, takže se příští tik zeptá znovu
    /// — tatáž nesymetrie jako u `refreshHeads`. Do okna se to nehlásí: nic v něm netvrdí, že
    /// slévatelnost zná, a stav GitHubu drží stavový řádek z pollingu.
    func refreshMergeReadiness(in summaries: [PullRequestSummary]) async {
        let candidates = Policy.mergeReadinessProbe(
            of: summaries,
            mine: ownLogins,
            isFresh: { hasCurrentDetail(for: $0) && hasCurrentBranchStatus(for: $0) }
        )
        guard !candidates.isEmpty else { return }

        let readiness: [PRIdentifier: MergeReadiness]
        do {
            readiness = try await gateway.fetchMergeReadiness(of: candidates)
        } catch {
            return
        }

        // Shrnutí se vytáhne **jednou**, ne hledáním v seznamu u každého kandidáta — tatáž úvaha
        // jako v `refreshHeads`.
        let asked = Dictionary(
            summaries.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        for id in candidates {
            // Chybějící odpověď se **nezapisuje**: „na tuhle PR nevíme“ se od „zeptali jsme se“
            // musí poznat, jinak by se z prázdna stalo tvrzení. Chybí i tehdy, když GitHub
            // slévatelnost ještě nedopočítal — viz `GhMergeReadinessResponse.readiness(of:)`.
            guard let answer = readiness[id], let pullRequest = asked[id] else { continue }
            // **Rozdělaná odpověď se nepřepisuje.** Mezitím otevřená záložka umí mít načteno víc
            // (hlavně polohu větve proti základu) a běžící načtení se ještě nemuselo vrátit;
            // hromadná odpověď je z těch dvou ta chudší, takže má ustoupit.
            if !hasCurrentDetail(for: pullRequest) {
                detailStates[id] = .loaded(answer.detail, updatedAt: pullRequest.updatedAt)
            }
            if !hasCurrentBranchStatus(for: pullRequest) {
                branchStatuses[id] = .loaded(answer.status, updatedAt: pullRequest.updatedAt)
            }
        }
    }
}
