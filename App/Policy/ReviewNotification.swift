import Foundation

extension Policy {
    /// Notifikace o doběhlém review (#82). `nil` = není o čem dát vědět.
    ///
    /// **Staví na `ReviewState`, ne na běhech.** Ten stav už rozlišuje přesně to, co se má
    /// v notifikaci poznat — nálezy, čisto, spadlou session, timeout s částečnými nálezy
    /// i „nemám co říct“ (reviewer nenahlásil nálezy, nebo se část ztratila). Skládat to
    /// z `record.runs` znovu by znamenalo druhé místo, které o témž výsledku rozhoduje,
    /// a rozejít se v tom znamená, že **řádek seznamu a notifikace řeknou dvě různé věci**.
    ///
    /// Rozhoduje proto výsledek **celého záznamu**, ne jednotlivý běh: reviewery jedou
    /// paralelně a tři notifikace za jedno PR jsou tři vyrušení za jednu věc.
    ///
    /// `nil` vrací u stavů, které nejsou konec běhu (`notStarted`, `queued`, `cloning`,
    /// `running`) a u `stale`. Zastaralý záznam znamená, že během běhu přišel nový commit —
    /// oznamovat výsledek proti kódu, který v PR není, by posílalo číst nálezy, které se
    /// vzápětí zneplatní.
    static func reviewNotification(
        for pr: PRIdentifier,
        state: ReviewState,
        blocking: Int = 0
    ) -> PullRequestNotification? {
        guard let body = notificationBody(state: state, blocking: blocking) else { return nil }
        // Titulek nese **repo a číslo**, ne jen „Review doběhlo“: notifikací může viset víc
        // a bez identifikace se nepozná, které patří ke kterému PR. Číslo se skládá přes
        // `description` identifikátoru, takže se nikde neinterpoluje přes locale — z `#21663`
        // by jinak bylo `#21 663`.
        return PullRequestNotification(pullRequest: pr, title: pr.description, body: body)
    }

    /// Co se v notifikaci píše. `nil` = tenhle stav se neoznamuje.
    private static func notificationBody(state: ReviewState, blocking: Int) -> String? {
        switch state {
        case .notStarted, .queued, .cloning, .running, .stale:
            nil
        case .completed(let findings):
            findingsText(findings, blocking: blocking)
        case .timedOut(let findings):
            // Timeout musí být poznat i tehdy, když nálezy jsou: zabitý běh je mohl mít
            // rozepsané, takže „3 nálezy“ by tvrdilo víc, než se stalo.
            findings > 0
                ? "Review nedoběhlo do limitu. \(findingsText(findings, blocking: blocking))"
                : "Review nedoběhlo do limitu a nic nenahlásilo."
        case .clean:
            // Kratší a bez detailu — ale poznat se to musí, takže ne prázdné tělo.
            "Reviewer nenašel žádný nález."
        case .dismissed(let count):
            // „Našel a já to zamítl“ je jiné tvrzení než „nic nenašel“ (#113), takže se
            // v textu nesmí slít. Nastane po opakovaném review, kde odmítnutí zůstala.
            "Zbyly jen nálezy, které jsi odmítl (\(count))."
        case .failed(let detail):
            // Sem spadá i „nemám co říct“ — spadlá session i nereportující běh. Detail
            // z `Policy` je věta, se kterou se dá něco dělat, takže se posílá celá.
            "Review se nepovedlo. \(detail)"
        case .checkoutFailed(let detail):
            "Nepovedlo se připravit pracovní kopii. \(detail)"
        }
    }

    /// „3 nálezy, 1 blokující“ — a `blocking` se do textu dostane jen tehdy, když je z čeho.
    private static func findingsText(_ findings: Int, blocking: Int) -> String {
        let found = "\(findings) \(findingWord(findings))"
        guard blocking > 0 else { return "\(found), nic blokujícího." }
        return "\(found), z toho \(blocking) blokující\(blocking == 1 ? "" : "ch")."
    }

    /// Čeština má tři tvary a notifikace je krátký text, kde je to vidět.
    private static func findingWord(_ count: Int) -> String {
        switch count {
        case 1: "nález"
        case 2 ... 4: "nálezy"
        default: "nálezů"
        }
    }

    /// Kolik z platných nálezů záznamu blokuje.
    ///
    /// Počítají se **platné** (`activeFindings`), tedy bez odmítnutých (#113) — blokující
    /// nález, kterému nevěřím, není důvod k vyrušení.
    static func blockingCount(
        in record: ReviewRecord,
        categories: Set<String> = defaultBlockingCategories
    ) -> Int {
        record.activeFindings.count { isBlocking($0, categories: categories) }
    }
}
