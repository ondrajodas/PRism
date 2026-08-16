import Foundation
import Testing

@testable import PRism

/// Co je v tabu `Commity`, jaký nad ním svítí odznak a která věta je nad seznamem (#316).
///
/// Pět věcí se tu dá pokazit potichu:
///
/// - **nakreslit klidnou hlášku o prázdnu.** Pull request bez commitů neexistuje, takže by
///   „tenhle PR nemá commity“ tvrdila něco, co platit nemůže — je to obrácená volba než
///   u `Kontrol`, kde prázdno **je** odpověď;
/// - **udělat z poruchy nenačteno**, tedy nechat nad chybou sítě věčně točit `Načítám commity…`;
/// - **nakreslit seznam v pořadí z API a nechat nad ním větu, že je otočený** — pořadí a věta
///   o pořadí jsou dvě místa, která se dají rozejít, a okno by pak lhalo o tom, co ukazuje;
/// - **označit první řádek jako `hlava`, i když se hlava mezitím posunula.** Nálezy jsou
///   klíčované `headSha` (tvrdá podmínka č. 5), takže je to tvrzení, ne dekorace;
/// - **splést české skloňování**, kvůli kterému by `1 commit` znělo jako chyba sazby — a to je
///   jeden ze tří stavů, které se podle zadání nesmí slít.
@Suite("Tab Commity, jeho odznak a věta nad seznamem")
struct CommitsTabStateTests {
    private func commit(
        _ sha: String,
        message: String = "feat: něco",
        merge: Bool = false,
        days: Double = 0
    ) -> PullRequestCommit {
        PullRequestCommit(
            sha: sha,
            message: message,
            authorName: "Odin Uv",
            authorLogin: "odinuv",
            avatarURL: nil,
            committedAt: Date(timeIntervalSince1970: 1_700_000_000 + days * 86_400),
            isMerge: merge
        )
    }

    private var one: [PullRequestCommit] { [commit("aaa1111")] }

    // MARK: - Tři stavy tabu, vyčerpávajícím výčtem

    /// Vstupy jsou dva a jejich kombinací je šest — `commits` nenačtené / prázdné / neprázdné krát
    /// `failure` je / není. Tady je celá ta mřížka, protože právě v ní se odpovědi dají splést:
    /// každé prázdno vypadá zvenku stejně.
    ///
    /// **Prázdné pole bez chyby je porucha**, ne čtvrtý stav — a je to jediný řádek téhle tabulky,
    /// který se od `checksTab` liší.
    @Test("Šest kombinací vstupů dá tři odpovědi a žádná netvrdí prázdno")
    func coversEveryCombination() {
        let one = one
        #expect(Policy.commitsTab(commits: nil, failure: nil) == .loading)
        #expect(Policy.commitsTab(commits: one, failure: nil) == .list(one, failure: nil))
        #expect(Policy.commitsTab(commits: nil, failure: "gh spadl") == .failed("gh spadl"))
        #expect(Policy.commitsTab(commits: [], failure: "gh spadl") == .failed("gh spadl"))
        #expect(Policy.commitsTab(commits: one, failure: "gh spadl") == .list(one, failure: "gh spadl"))

        // Prázdno bez chyby: porucha s vlastní větou, ne `loading` a ne klidné „nic tu není“.
        guard case .failed(let reason) = Policy.commitsTab(commits: [], failure: nil) else {
            Issue.record("prázdný seznam se má hlásit jako porucha")
            return
        }
        #expect(reason.contains("prázdný"))
        #expect(reason.contains("neexistuje"), "věta musí říct, proč je prázdno nemožný stav")
    }

    /// **Nejcennější test téhle sady** — tvrdí, že se něco NEstalo: prázdná odpověď se nikdy
    /// nenakreslí jako klidný stav. Kdyby `CommitsTabState` někdy dostal `empty`, spadne to tady,
    /// ne až v okně.
    @Test("Prázdný seznam nikdy nevyjde jako seznam")
    func neverYieldsAnEmptyList() {
        for failure in [nil, "gh spadl"] {
            let state = Policy.commitsTab(commits: [], failure: failure)
            if case .list = state {
                Issue.record("prázdné pole se dostalo do seznamu (failure: \(failure ?? "nil"))")
            }
        }
    }

    /// Neprázdný seznam přebíjí poruchu — zastaralý seznam s větou nad sebou je pořád lepší než
    /// plocha s chybou místo commitů, které se před chvílí načetly.
    @Test("Načtený seznam přežije selhaný pokus o obnovení")
    func keepsTheListAfterAFailedRefresh() {
        let one = one
        guard case .list(let list, let failure) = Policy.commitsTab(commits: one, failure: "timeout") else {
            Issue.record("seznam se po selhání zahodil")
            return
        }
        #expect(list == one)
        #expect(failure == "timeout", "bez důvodu by seznam vypadal jako čerstvý")
    }

    // MARK: - Pořadí: nejnovější nahoře

    /// **Otočeno proti návrhu** (#316): mockup, sekce 19, i specifikace měly „od nejstaršího, jako
    /// na GitHubu, protože PR se čte jako postup“. Na hotové obrazovce to neobstálo — v tomhle okně
    /// se PR nečte od začátku, ale od toho, co přibylo naposled. Test tvrdí **to nové**: co přišlo
    /// z API poslední, je v tabu první.
    @Test("Seznam jde do tabu od nejnovějšího")
    func listComesOutNewestFirst() {
        let fromApi = [commit("aaa"), commit("bbb"), commit("ccc")]

        guard case .list(let list, _) = Policy.commitsTab(commits: fromApi, failure: nil) else {
            Issue.record("neprázdný seznam se nedostal do `list`")
            return
        }
        #expect(list.map(\.sha) == ["ccc", "bbb", "aaa"])
        #expect(list.first?.sha == fromApi.last?.sha, "nahoře má být to, co přišlo z API poslední")
    }

    /// Otočí se i seznam, nad kterým visí porucha — jinak by se zastaralý seznam kreslil obráceně
    /// než čerstvý a věta nad ním by mluvila o tom druhém.
    @Test("Zastaralý seznam se otáčí stejně jako čerstvý")
    func flipsTheStaleListToo() {
        guard case .list(let list, let failure) =
            Policy.commitsTab(commits: [commit("aaa"), commit("bbb")], failure: "timeout")
        else {
            Issue.record("seznam se po selhání zahodil")
            return
        }
        #expect(list.map(\.sha) == ["bbb", "aaa"])
        #expect(failure == "timeout")
    }

    /// **Otáčí se, neřadí.** Pořadí z API je topologické, takže po rebase nebo cherry-picku má
    /// commit uprostřed novější datum než ten za ním. Seřadit podle času by ten postup rozházelo —
    /// tenhle test spadne, kdyby se z otočení stalo `sorted(by: committedAt)`.
    @Test("Pořadí se otáčí, neřadí podle data")
    func flipsTheOrderInsteadOfSortingByDate() {
        let fromApi = [commit("aaa", days: -5), commit("bbb", days: -1), commit("ccc", days: -3)]

        #expect(Policy.commitsNewestFirst(fromApi).map(\.sha) == ["ccc", "bbb", "aaa"])
    }

    // MARK: - Odznak

    @Test("Odznak je prostý počet, a jen nad seznamem")
    func badgeCountsOnlyOverAList() {
        #expect(Policy.commitsBadge(of: .loading) == nil)
        #expect(Policy.commitsBadge(of: .failed("gh spadl")) == nil)
        #expect(Policy.commitsBadge(of: .list(one, failure: nil)) == .count(1))
        #expect(Policy.commitsBadge(of: .list(one, failure: "timeout")) == .count(1))
        // Do `list` se prázdno nedostane, ale odznak si to hlídá sám: nula nad prázdnem by
        // tvrdila, že se spočítalo.
        #expect(Policy.commitsBadge(of: .list([], failure: nil)) == nil)
    }

    /// Tichá kapsle, ne červená: kolik je commitů, je údaj o množství — kdyby se z toho stalo
    /// `blocking`, přestaly by se číst odznaky, které o něco jdou.
    @Test("Odznak commitů nikdy neblokuje a nebliká")
    func badgeIsNeverAnAlert() {
        let badge = Policy.commitsBadge(of: .list([commit("a"), commit("b")], failure: nil))
        #expect(badge == .count(2))
    }

    // MARK: - Která hlava (tvrdá podmínka č. 5)

    /// **Druhý nejcennější test**: pilulka `hlava` se nesmí objevit u commitu, který hlavou není.
    /// Od otočení seznamu (#316) je „nahoře“ a „hlava“ obvykle tentýž řádek, a právě proto se to
    /// dá splést — po pushnutém commitu je seznam o krok pozadu a nahoře stojí commit, proti
    /// kterému nálezy neplatí. Test proto hledá hlavu **všude jinde než nahoře**.
    @Test("Hlava se bere ze sha, ne z pozice v poli")
    func headComesFromTheShaNotTheOrder() {
        let list = Policy.commitsNewestFirst([commit("aaa"), commit("bbb"), commit("ccc")])
        #expect(list.first?.sha == "ccc", "nahoře je nejnovější — a přesto o pilulce nerozhoduje")

        #expect(Policy.headCommit(in: list, head: "bbb")?.sha == "bbb", "hlava uprostřed se má najít")
        #expect(Policy.headCommit(in: list, head: "aaa")?.sha == "aaa", "hlava naspod se má najít")
        #expect(Policy.headCommit(in: list, head: "ddd") == nil, "hlava mimo seznam se nesmí označit")
    }

    /// Dokud detail nedorazil, platí definice endpointu: GitHub vrací commity od nejstaršího a tab
    /// je otáčí, takže hlavou je **první**. Je to jediný okamžik, kdy o pilulce rozhoduje pozice.
    @Test("Bez známé hlavy se označí první commit")
    func fallsBackToTheFirstCommit() {
        let list = Policy.commitsNewestFirst([commit("aaa"), commit("bbb")])
        #expect(Policy.headCommit(in: list, head: nil)?.sha == "bbb")
        #expect(Policy.headCommit(in: [], head: nil) == nil)
        #expect(Policy.headCommit(in: [], head: "aaa") == nil)
    }

    // MARK: - Věta nad seznamem

    /// Tři tvary, protože čeština je má tři. `1 commit` je jeden ze stavů, které se podle zadání
    /// nesmí slít s ostatními.
    @Test("Skloňování má tři tvary")
    func declensionHasThreeForms() {
        #expect(Policy.commitNoun(1) == "commit")
        #expect(Policy.commitNoun(2) == "commity")
        #expect(Policy.commitNoun(4) == "commity")
        #expect(Policy.commitNoun(5) == "commitů")
        #expect(Policy.commitNoun(7) == "commitů")
        #expect(Policy.commitNoun(21) == "commitů", "dvacet jedna je v češtině „commitů“, ne „commit“")
        #expect(Policy.commitNoun(0) == "commitů")
    }

    /// Věta se sází ve dvou kusech (počet tmavě, zbytek tlumeně), ale je to **jedna věta** — a ta
    /// jde do čtečky, takže se musí dát složit zpátky.
    @Test("Věta nad seznamem říká počet i pořadí")
    func headlineSaysCountAndOrder() {
        #expect(Policy.commitsHeadline(count: 1).count == "1 commit")
        #expect(Policy.commitsHeadline(count: 1).sentence == "1 commit · od nejnovějšího")
        #expect(Policy.commitsHeadline(count: 7).sentence == "7 commitů · od nejnovějšího")
    }

    /// **Tvrdí, že se něco NEstalo**: pruh je jediné místo, které o pořadí něco říká, takže se
    /// s otočením musel změnit. Kdyby v něm zůstalo staré slovo, okno by lhalo o tom, co ukazuje —
    /// a poznalo by se to jedině přečtením obrazovky, ne z testu na pořadí.
    @Test("Věta nikde netvrdí staré pořadí")
    func headlineNeverClaimsTheOldOrder() {
        for count in [1, 7, Policy.commitListCap] {
            #expect(!Policy.commitsHeadline(count: count).sentence.contains("nejstarš"),
                    "věta nad seznamem od nejnovějšího mluví o nejstarším (\(count))")
        }
    }

    /// **Text nesmí tvrdit víc, než data unesou.** GitHub vydá na PR nejvýš 250 commitů, takže
    /// nad tím počtem seznam celý být nemusí — a věta o „250 commitech“ by o něm tvrdila, že je.
    @Test("Na stropu API věta řekne, že seznam nemusí být celý")
    func headlineAdmitsTheApiCap() {
        let below = Policy.commitsHeadline(count: Policy.commitListCap - 1)
        #expect(!below.sentence.contains("nevydá"), "pod stropem se o stropu nemá co říkat")

        let atCap = Policy.commitsHeadline(count: Policy.commitListCap)
        #expect(atCap.count == "prvních 250 commitů")
        #expect(atCap.sentence.contains("nevydá"))
    }
}
