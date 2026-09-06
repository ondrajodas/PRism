import Foundation

/// Cizí aktivita na **vlastních** PR (#335) — komentář kolegy, odpověď ve vlákně, Copilotovo
/// review.
///
/// Do #335 se konverzace tahala **jedině při zobrazení PR**, takže „od minule“ vznikalo teprve ve
/// chvíli, kdy se koukám — tedy přesně tehdy, kdy už notifikaci nepotřebuju. Tady je ta druhá půlka:
/// rozhlídka na pozadí, která se drobnou podmnožinou vejde do jednoho tiku, a notifikace, která
/// o téže věci nepřijde dvakrát.
///
/// **Nic se tím neposílá ven** — je to `fetchConversation`, tedy čtení; tvrdá podmínka č. 1 zůstává
/// nedotčená.
extension AppStore {
    /// Zeptá se na diskuzi vlastních PR a dá vědět, co v ní přibylo (#335).
    ///
    /// Volá se **jen po úspěšném tiku**, jako všechno ostatní v `afterSuccessfulTick`, a právě tím
    /// se vejde do backoffu pollingu: při rate limitu se netiká, takže se ani nekouká. Vlastní
    /// časovač by tu ochranu obešel.
    ///
    /// Koho a jak často se ptát, rozhoduje `Policy.activitySweep` — tady je jen to, co se s odpovědí
    /// udělá. Rozhlídka jde PR po PR **postupně**, ne souběžně: tři podprocesy `gh` naráz kvůli
    /// hlášce na pozadí by soutěžily s tím, na co se člověk zrovna kouká.
    ///
    /// **Netahá se to jen kvůli notifikaci**, takže tady brána na notifikační centrum není: text
    /// `2 nové komentáře od minule` v řádku stojí na téže konverzaci, a bez ní by řádek o cizí
    /// aktivitě mlčel i v okně, které je zrovna vepředu.
    func refreshOwnActivity(in summaries: [PullRequestSummary]) async {
        let candidates = Policy.activitySweep(
            of: summaries,
            mine: ownLogins,
            // Konverzace v paměti a `updatedAt`, se kterým dorazila — tedy tentýž předfiltr, jaký
            // má `loadConversation(for:)`. Bez něj by se PR, na které se nic nestalo, tahalo znovu.
            loadedAt: { conversationUpdatedAt(for: $0) },
            now: time.now,
            lastSweep: lastActivitySweep
        )
        guard !candidates.isEmpty else { return }
        // Razítko rozhlídky se posouvá jedině tehdy, když se **doopravdy ptáme** — viz
        // `Policy.activitySweep`. Klidná chvíle okno nespotřebuje.
        lastActivitySweep = time.now

        for pullRequest in candidates {
            guard let summary = summaries.first(where: { $0.id == pullRequest }) else { continue }
            // PR, jehož konverzace se **právě načítá** (člověk na něj zrovna klikl), se přeskočí:
            // `loadConversation(for:)` rozdělané načtení schválně nepřeskakuje (jinak by v okně
            // zbylo prázdno), takže by z toho byl týž dotaz dvakrát. Na příští rozhlídku už bude
            // načtená — a když ne, zeptá se tehdy.
            guard conversationStates[pullRequest] != .loading else { continue }
            // Značka „od minule“ **před** načtením: po něm už by se z konverzace nedalo poznat, co
            // je nové. Návštěva se přitom nezapisuje — viz `seedVisitBaseline(for:)`.
            seedVisitBaseline(for: pullRequest)
            await loadConversation(for: summary)
            await notifyAboutForeignActivity(on: pullRequest)
            // Agent na vlastním PR (#510) — **až za notifikací**, protože o cizím hlasu se má
            // vědět, ať se agent pustí, nebo ne. Razítko si drží vlastní (`AgentFixLedger`), takže
            // se ta dvě rozhodnutí nemůžou přebít: vypnuté notifikace agenta nezastaví a spuštěný
            // agent notifikaci neumlčí.
            //
            // **Samo od sebe se tím nespustí nic**: brána `autoAgent` je ve výchozím stavu vypnutá
            // a rozhoduje `Policy.agentFix`.
            await startAgentFix(on: pullRequest)
        }
    }

    /// `updatedAt` načtené konverzace. `nil` = žádná v paměti není, nebo se nepovedla načíst —
    /// obojí znamená „zeptej se“, takže se selhaná rozhlídka zkusí znovu při té příští.
    func conversationUpdatedAt(for pr: PRIdentifier) -> Date? {
        guard case .loaded(_, let updatedAt) = conversationStates[pr] else { return nil }
        return updatedAt
    }

    /// Dá vědět o cizí aktivitě na jednom vlastním PR (#335).
    ///
    /// **Razítko se posouvá až po doručení**, a je to tatáž nesymetrie jako u nových PR (#85):
    /// opačné pořadí znamená, že se položka zapíše jako ohlášená, notifikace se nepovede a už nikdy
    /// nepřijde. Přechodná chyba proto razítko nechá být (`isWorthRetrying`), kdežto odmítnuté
    /// oprávnění nebo vypnutý přepínač ano — opakovat každou rozhlídku něco, co je zakázané, nemá
    /// cenu a v okně je ta aktivita vidět na řádku.
    ///
    /// **Vlastní PR, ne cizí**: na cizím je moje práce spustit review, ne hlídat diskuzi — a hlídá
    /// ji `Policy.activitySweep`, který sahá jen na `.mine`. Tady je to znovu jako pojistka, protože
    /// tuhle metodu volá i test a jedna zapomenutá podmínka by z toho udělala notifikace o cizí
    /// diskuzi, tedy hlášky o práci, o kterou mě nikdo nepožádal.
    func notifyAboutForeignActivity(on pr: PRIdentifier) async {
        let ownership = ownership(of: pr)
        // Razítko oznámení se nespotřebuje, když ho nikdo nekonzumuje — tatáž úvaha jako u snímku
        // fronty (#414). Do #414 tu stálo `notifications != nil`.
        guard ownership == .mine, watchesPullRequestActivity else { return }
        let baseline = Policy.activityBaseline(
            lastVisit: visitSnapshots[pr],
            lastNotice: activityNotices.lastNotice(for: pr)
        )
        let activity = Policy.foreignActivity(in: conversation(for: pr), since: baseline)
        guard let notification = Policy.activityNotification(for: pr, activity: activity),
              let announced = activity.latest
        else { return }

        // **Guard na notifikační centrum se přesunul dolů** (#414): do dění se zapisuje i tehdy,
        // když se odsud neposílá nebo když je hláška vypnutá — přepínače (#86) rozhodují
        // o vyrušení, ne o záznamu.
        var delivery: NotificationDelivery?
        if notifications != nil { delivery = await notify(notification) }
        guard delivery?.isWorthRetrying != true else { return }
        activityNotices.record(pr, announced: announced, at: time.now)
        // Za razítkem oznámení, ze stejného důvodu jako u nových PR: dokud se razítko neposunulo,
        // vrátí příští rozhlídka tutéž aktivitu — a druhý řádek o jednom komentáři je šum.
        await recordActivity(Policy.foreignActivityEvent(
            for: pr,
            ownership: ownership,
            activity: activity,
            at: time.now,
            announced: delivery?.isDelivered == true
        ))
    }

}
