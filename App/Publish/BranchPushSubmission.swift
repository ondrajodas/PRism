import Foundation
import Observation

/// Jedno přetlačení větve — od otevření potvrzení po odpověď serveru. **Jediný volající
/// `BranchPushing`** (#466).
///
/// **Tvarem `MergeSubmission`, a je to vědomá volba, ne shoda.** Do rozdělení akce na dva kroky to
/// byla struktura bez stavu, kterou si `AppStore` složil a hned zavolal; od chvíle, kdy má
/// přetlačení **vlastní potvrzovací obrazovku**, je to tatáž věc jako merge: objekt vzniká
/// kliknutím na `Přetlačit…`, drží **snímek** toho, co se potvrzuje, a zaniká zavřením sheetu.
/// Proč zrovna sheet a ne tlačítko v panelu, je v [záznamu
/// rozhodnutí](../../docs/superpowers/specs/2026-07-31-prism-design.md).
///
/// **Rebase tudy nejde.** Přehrání commitů je lokální práce v cache a dělá ji `RepoCheckout`;
/// tenhle typ je jenom to místo, kde se **zapisuje ven** — a je to zároveň důvod, proč se ten dvojí
/// krok dá uhlídat: v cache se pracuje bez potvrzení, ven jedině s ním.
///
/// **Tady vzniká pusher a tady zaniká** (tvrdá podmínka č. 1). `AppStore` ho nemá kde uložit —
/// drží jen cestu ke `gitu`, ke `gh` a stav.
@MainActor
@Observable
final class BranchPushSubmission: Identifiable {
    /// Kvůli `.sheet(item:)`. Identita je „tohle jedno přetlačení“, ne PR — druhé kliknutí po
    /// zavření sheetu je nový snímek.
    let id = UUID()

    let pullRequest: PullRequestSummary
    /// Co se má přetlačit. **Snímek pořízený při otevření sheetu**: co je v potvrzení vidět, to
    /// odejde, i kdyby mezitím dorazil polling s jinými čísly.
    let plan: BranchPushPlan
    /// Kolik commitů se přehrálo — do výpisu v potvrzení. Z výsledku rebase, ne z plánu.
    let replayed: Int

    private(set) var state: State

    enum State: Equatable {
        case ready
        case pushing
        /// Nepovedlo se. Jestli se dá zkusit znovu, rozhoduje `BranchSyncError.canRetrySamePlan`:
        /// retry odsud posílá **tentýž plán**, takže má smysl jedině tam, kde se pokus
        /// **nedokončil** (timeout, přerušení, neznámá chyba). U **neshody stavu** — odmítnutý
        /// lease, posunutá hlava, přejmenovaná větev — je plán zastaralý z definice a druhý pokus
        /// by dopadl identicky; tam věta posílá obnovit data a tlačítko zhasne.
        case failed(BranchSyncError)
        /// Server větev přijal; tohle je hlava, která na ní teď leží.
        case pushed(String)
    }

    /// Jak vyrobit **cestu do remote**. Volá se až v `push()`.
    private let pusher: @MainActor () -> any BranchPushing
    /// Co udělat po úspěchu — načíst detail a stav větve znovu, protože se hlava změnila. Skládá to
    /// `AppStore`, protože je to jeho stav; tenhle objekt o něm nic neví.
    private let afterSuccess: @MainActor () async -> Void

    init(
        pullRequest: PullRequestSummary,
        plan: BranchPushPlan,
        replayed: Int,
        pusher: @escaping @MainActor () -> any BranchPushing,
        afterSuccess: @escaping @MainActor () async -> Void
    ) {
        self.pullRequest = pullRequest
        self.plan = plan
        self.replayed = replayed
        self.pusher = pusher
        self.afterSuccess = afterSuccess
        state = .ready
    }

    /// Ostrá cesta: pusher se skládá z `gitu`, `gh` (přihlášení), read-only gateway (pre-flight),
    /// cache, brány a mých loginů — a skládá se **až** ve chvíli pushnutí.
    convenience init(
        pullRequest: PullRequestSummary,
        plan: BranchPushPlan,
        replayed: Int,
        git: URL,
        gh: URL,
        layout: CacheLayout,
        gateway: any GitHubGateway,
        scope: PublishScope,
        mine: Set<String>,
        afterSuccess: @escaping @MainActor () async -> Void
    ) {
        self.init(
            pullRequest: pullRequest,
            plan: plan,
            replayed: replayed,
            // Brána je snímek konfigurace z okamžiku kliknutí — stejně jako plán.
            pusher: {
                GitBranchPush(
                    git: git,
                    gh: gh,
                    layout: layout,
                    runner: SubprocessRunner(),
                    gateway: gateway,
                    scope: scope,
                    mine: mine
                )
            },
            afterSuccess: afterSuccess
        )
    }

    /// Dá se (znovu) přetlačit?
    ///
    /// **Po selhání jen tam, kde druhý pokus s týmž plánem může uspět** — rozhoduje
    /// `BranchSyncError.canRetrySamePlan`. Tlačítko, po kterém se nic nestane, je horší než
    /// zašedlé; a živé tlačítko vedle věty „obnov okno a zkus to znovu“ je ještě horší, protože
    /// zve k opakování, které nemůže vyjít.
    var canPush: Bool {
        switch state {
        case .ready: true
        case .failed(let error): error.canRetrySamePlan
        case .pushing, .pushed: false
        }
    }

    /// Přetlačilo se a **není k tomu co dodat** — sheet se pak zavírá sám, jako u merge. Selhání ho
    /// nechává otevřený schválně: je to jediné místo, kde je vidět, co server odmítl.
    var closesItself: Bool {
        if case .pushed = state { true } else { false }
    }

    /// Věta o pojistce do potvrzení. Skládá ji `Policy`, ne tenhle typ ani sheet.
    var leaseWarning: String { Policy.leaseWarning(for: plan) }

    /// Přetlačí. **Jediné místo v aplikaci, které volá `BranchPushing.push`.**
    func push() async {
        guard canPush else { return }
        state = .pushing
        do {
            let head = try await pusher().push(plan)
            // Stav se přepíná **před** úklidem, jako u merge: načíst PR znovu je práce po síti
            // a potvrzení, že push prošel, na ni nemá čekat.
            state = .pushed(head)
            await afterSuccess()
        } catch let error as BranchSyncError {
            state = .failed(error)
        } catch is CancellationError {
            // **Ne `.ready`.** Zrušit jde jedině *během* volání, takže se nedá tvrdit, že do remote
            // nic neodešlo — tatáž úvaha jako u review a merge.
            state = .failed(.interrupted)
        } catch {
            state = .failed(.failed(error.localizedDescription))
        }
    }
}
