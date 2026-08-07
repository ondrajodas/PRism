import Foundation

/// Souhrn nad frontou PR (#155): kolik jich čeká, kolik má blokující nález a kolik rozdělané review.
///
/// **Sčítá, nezužuje.** Filtr reviewerů (#117) seznam zužuje a je to *pohled*; souhrn je tvrzení
/// o tom, co ve frontě **je**. Kdyby se počítal z toho, co je po filtru vidět, tvrdil by, že práce
/// ubyla, jen protože jsem si schoval jednoho revieweera — tatáž úvaha jako u zahození nálezů.
struct QueueSummary: Hashable, Sendable {
    /// Kolik PR je ve frontě.
    let pullRequests: Int
    /// U kolika z nich má některý reviewer **platný** blokující nález.
    let blocking: Int
    /// U kolika z nich mám rozdělané review.
    let drafts: Int

    /// Je vůbec co ukazovat? Prázdná fronta souhrn nepotřebuje — o tom, že nic nečeká, mluví
    /// prázdný stav seznamu, a to i s důvodem (`PollEmptyReason`).
    var isEmpty: Bool { pullRequests == 0 }
}

extension Policy {
    /// Souhrn fronty. Čistá funkce nad seznamem PR, uloženými záznamy a drafty.
    ///
    /// **Počítá PR, ne nálezy.** „Tři blokující nálezy“ nedává odpověď na otázku „na kolik věcí se
    /// musím podívat“ — když jsou všechny na jednom PR, je to jedna položka práce. Řádek seznamu
    /// odpovídá za jeden PR, souhrn za frontu, takže obojí musí počítat totéž.
    ///
    /// Blokující se bere z `Policy.blockingCount(in:categories:)`, tedy z **platných** nálezů:
    /// odmítnutý nález (#113) strašit nemá a druhý výpočet by se s řádkem seznamu rozešel.
    ///
    /// **Nedá se z toho poznat, jestli je „čisto“** — a to je schválně. Souhrn nezná stav pollingu,
    /// takže by po selhaném tiku tvrdil „0 blokujících“ nad daty, která nemusí platit. Rozhodnutí
    /// o tom, jestli se má vůbec ukázat, patří tomu, kdo ten stav zná (`AppStore.queueSummary`).
    static func summary(
        of pullRequests: [PullRequestSummary],
        records: [PRIdentifier: ReviewRecord],
        drafts: [PRIdentifier: ReviewDraft],
        categories: Set<String> = defaultBlockingCategories
    ) -> QueueSummary {
        QueueSummary(
            pullRequests: pullRequests.count,
            blocking: pullRequests.count { pr in
                guard let record = records[pr.id] else { return false }
                return blockingCount(in: record, categories: categories) > 0
            },
            // **Prázdný draft se nepočítá.** Draft vzniká i tím, že se otevře panel a napíše se do
            // něj znak, který se pak smaže; „rozdělané review“ má znamenat, že je co poslat.
            drafts: pullRequests.count { drafts[$0.id]?.isEmpty == false }
        )
    }
}
