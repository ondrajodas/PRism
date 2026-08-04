import Foundation

extension Policy {
    /// Ze signálů složí puntík u služby a věty do nápovědy. Čistá funkce, žádné I/O.
    static func health(of service: MonitoredService, from signals: HealthSignals) -> ServiceHealthReport {
        let incidents = signals.page?.incidents ?? []
        let state = state(from: signals, incidents: incidents)
        return ServiceHealthReport(
            service: service,
            state: state,
            reason: reason(for: state, of: service, from: signals, incidents: incidents),
            call: signals.lastCall,
            checkedAt: signals.pageCheckedAt
        )
    }

    /// Pořadí signálů, a záleží na něm.
    ///
    /// 1. **Bez sítě přebíjí všechno.** Když stroj nemá kudy, je zbytečné tvrdit cokoli
    ///    o službě — a je to jediná odpověď, se kterou uživatel může něco udělat.
    /// 2. **Selhané volání přebíjí incident.** „Nefunguje mi to“ je silnější tvrzení než
    ///    „oni něco hlásí“; incident se do věty přidá jako vysvětlení, ne jako stav.
    /// 3. **Incident přebíjí i „zatím nic neproběhlo“.** Puntík zežloutne ještě před prvním
    ///    voláním, protože ta informace už tu je a šedá by ji zahodila.
    /// 4. **Zelenou dá i samotná čistá status page.** Šedá znamená „nevíme nic“ — a když se
    ///    stránka čerstvě přečetla a je na ní čisto, tak něco víme. Claude by jinak zůstal
    ///    šedý, dokud neproběhne první review, tedy většinu času. Že vlastní volání ještě
    ///    neproběhlo, řekne **věta**, ne barva: status page mluví za provozovatele a rate
    ///    limit ani chybějící scope se v ní neprojeví.
    private static func state(from signals: HealthSignals, incidents: [StatusPageComponent]) -> ServiceHealth {
        if signals.isOnline == false { return .offline }
        if let call = signals.lastCall, !call.succeeded { return .failing }
        if !incidents.isEmpty { return .incident }
        if signals.lastCall != nil { return .operational }
        return knowsTheirState(signals) ? .operational : .unknown
    }

    /// Známe **čerstvý** stav služby? Stará stránka po selhané kontrole se nepočítá — ani
    /// pro zelenou, ani pro věty o tom, že je u nich čisto.
    private static func knowsTheirState(_ signals: HealthSignals) -> Bool {
        signals.page != nil && signals.pageFailure == nil
    }

    private static func reason(
        for state: ServiceHealth,
        of service: MonitoredService,
        from signals: HealthSignals,
        incidents: [StatusPageComponent]
    ) -> String {
        var sentences: [String] = []

        // „Oni na svém stavu nic nehlásí“ se smí říct **jen když ten stav známe**. Bez toho
        // by věta, která má rozhodnout „oni, nebo já?“, tvrdila víc, než data unesou —
        // a poslala by hledat chybu u sebe i ve chvíli, kdy o výpadku prostě nevíme.
        //
        // Opačným směrem je to schválně nesymetrické: **incident se hlásí, i když poslední
        // kontrola selhala** a stav je z minula. Zamlčet známý problém je dražší než ukázat
        // ho o deset minut starší — a jak starý je, říká čas kontroly v nápovědě.
        let knowsTheirState = knowsTheirState(signals)

        switch state {
        case .offline:
            sentences.append("Stroj je bez sítě, takže o \(service.nameInGenitive) nejde zjistit nic.")
        case .failing:
            sentences.append(signals.lastCall?.failure ?? "Poslední volání selhalo.")
            if !incidents.isEmpty {
                sentences.append(incidentSentence(of: service, incidents))
            } else if knowsTheirState {
                sentences.append("\(service.name) na svém stavu problém nehlásí.")
            }
        case .incident:
            sentences.append(incidentSentence(of: service, incidents))
            if signals.lastCall?.succeeded == true {
                sentences.append("Volání zatím procházejí.")
            }
        case .operational where signals.lastCall == nil:
            // Zelená ze samotné status page. Barva říká „nic nevím o tom, že by to
            // nefungovalo“, věta doříká, na čem to stojí — jinak by zelená slibovala, že
            // se to vyzkoušelo.
            sentences.append("\(service.name) na svém stavu problém nehlásí.")
            sentences.append("Vlastní volání ještě neproběhlo.")
        case .operational:
            sentences.append(knowsTheirState
                ? "Poslední volání prošlo a \(service.name) problém nehlásí."
                : "Poslední volání prošlo.")
        case .unknown:
            sentences.append("Zatím neproběhlo žádné volání \(service.nameInGenitive).")
        }

        if let note = pageNote(of: service, from: signals) {
            sentences.append(note)
        }
        return sentences.joined(separator: " ")
    }

    private static func incidentSentence(
        of service: MonitoredService,
        _ incidents: [StatusPageComponent]
    ) -> String {
        let listed = incidents.map { "\($0.name) — \($0.label)" }.joined(separator: ", ")
        return "\(service.name) hlásí problém: \(listed)."
    }

    /// Co je potřeba doříct o samotné kontrole stavu.
    ///
    /// Selhaná kontrola puntík nemění (viz `HealthSignals.pageFailure`), ale mlčet o ní
    /// nejde. Totéž u komponenty, kterou stránka nezná: kontrola, která tiše nehlídá nic,
    /// vypadá stejně jako „všechno v pořádku“.
    private static func pageNote(of service: MonitoredService, from signals: HealthSignals) -> String? {
        if let failure = signals.pageFailure { return failure }
        guard let page = signals.page else { return "Stav \(service.nameInGenitive) se ještě nezjišťoval." }
        guard !page.missing.isEmpty else { return nil }
        return "Status page nezná komponentu \(page.missing.joined(separator: ", ")) — tu hlídat nejde."
    }
}
