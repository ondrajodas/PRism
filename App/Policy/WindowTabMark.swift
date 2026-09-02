import Foundation

/// Značka u záložky v pruhu nad obsahem okna (#180, pátý případ od #527).
///
/// Do #527 o ní rozhodovaly tři `if`y ve `ReviewTabsView` (`isRunning` → `hasDraft` → barevná
/// tečka). Přibyly dva stavy — **přijatá záložka, detail ještě není** a **mergnutý nebo zavřený PR** —
/// a pět pater `if`ů ve view je zrovna to, co `CLAUDE.md` popisuje jako věc, která patří do
/// `Policy`: dá se vyčerpat výčtem a otestovat bez kreslení.
enum WindowTabMark: Equatable, Sendable {
    /// Na PR běží review (nebo se pro něj klonuje) — točící se prstýnek.
    case running
    /// **Přijatá** záložka, o které se ještě neví nic než adresa — **dutý kroužek** (#527).
    ///
    /// Nejen obnovená po restartu: dostane ho i záložka otevřená **odkazem** (#531), u které se
    /// detail teprve dotahuje. Rozhoduje o tom `PullRequestTabContent.loading`, tedy tatáž
    /// odpověď, jakou kreslí plocha záložky — a proto se ta věta nesmí zúžit na restart (nález
    /// Copilota na #544; tentýž vzor jako u nápovědy kroužku a u `Policy.loadingTabNote`).
    case loading
    /// Leží tu rozdělané review — ✎.
    case draft
    /// Jak dopadl **pull request** (#527). Jen u `merged` a `closed` — viz `tabMark`.
    case pullRequest(PullRequestState)
    /// Jak dopadlo **review** — barevná tečka, tak jako do #527.
    case review(ReviewState)
}

extension Policy {
    /// Co se nakreslí u záložky. **Pořadí pater je celý obsah téhle funkce.**
    ///
    /// 1. **Běh přebíjí všechno** (z #180): je to jediný stav, který se mění sám, a prstýnek je
    ///    jediná věc v pruhu, ze které je vidět, že aplikace pracuje, aniž by se na tu záložku
    ///    muselo přepnout.
    /// 2. **Načítání** (#527, u přijaté záložky obecně) je hned pod ním, a **nad rozdělaným
    ///    review** schválně: dokud o pull requestu nevíme nic, nemá záložka co tvrdit — ✎ by
    ///    mluvilo o práci na PR, o kterém ještě není jasné, jestli existuje. Nad běh se to
    ///    nedostane, protože po startu nic neběží (obnovení nespouští nic), takže je to pořadí
    ///    bez sporu.
    /// 3. **Rozdělané review** je věc, která čeká na mě.
    /// 4. **Mergnutý a zavřený PR** (#527) přebíjí stav review: „jak to dopadlo“ je u nich
    ///    důležitější než „co našel reviewer“, protože další práce se od nálezů neodvíjí — dá se
    ///    to jedině dočíst a zavřít. `open` a `draft` sem **nepatří**: rozpracovaný pull request
    ///    je normální práce a stav review na něm platí dál.
    /// 5. **Stav review** jako do #527.
    ///
    /// - Parameters:
    ///   - isRunning: běží review, nebo se klonuje. Bere se ze **store**, ne ze `state`:
    ///     `ReviewState.running` vzniká z fáze běhu, kdežto u klonování je stav `cloning` —
    ///     a točit se má v obou případech, protože obojí je „něco se právě děje“ (z #180).
    ///   - isLoading: **přijatá** záložka, jejíž detail ještě nedorazil — obnovená po restartu
    ///     (#527) i otevřená odkazem (#531). Bere se z `PullRequestTabContent.loading`, tedy
    ///     z téže odpovědi, jakou kreslí plocha záložky: dvě místa by znamenala pruh, který
    ///     tvrdí něco jiného než obrazovka pod ním.
    ///   - state: stav pull requestu. `nil` = ještě se neví, což u obnovené záložky nastane vždycky
    ///     — a je to důvod, proč se o `merged` rozhoduje až po `isLoading`.
    static func tabMark(
        isRunning: Bool,
        isLoading: Bool,
        hasDraft: Bool,
        state: PullRequestState?,
        review: ReviewState
    ) -> WindowTabMark {
        if isRunning { return .running }
        if isLoading { return .loading }
        if hasDraft { return .draft }
        // Vyjmenované po jednom, ne `state.map`: pátý stav pull requestu si tím vynutí
        // rozhodnutí, jestli přebíjí review, nebo ne.
        switch state {
        case .merged: return .pullRequest(.merged)
        case .closed: return .pullRequest(.closed)
        case .open, .draft, nil: return .review(review)
        }
    }
}
