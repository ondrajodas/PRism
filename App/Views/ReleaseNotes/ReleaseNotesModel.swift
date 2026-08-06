import Foundation
import Observation

/// Stav okna s novinkami (#127): historie vydání, výběr a značka „tohle už jsem viděl“.
///
/// Vlastní model vedle `AppStore`, ne jeho další sekce. Novinky nejsou doména review — okno
/// je samostatná scéna jako nastavení a s pull requesty nesdílí ani data, ani životní cyklus.
/// Vlastní ho proto `PreflightModel`, tedy něco **nad okny**; ke `@State` uvnitř hlavního okna
/// by se druhá scéna nedostala (tatáž úvaha, kvůli které tam žije `AppStore`).
///
/// Na síť se sahá **dvakrát za běh, oboje na vyžádání**: jednou při startu kvůli značce
/// a jednou při otevření okna (a to už je z paměti). V pollingu ani na pozadí se neptá.
/// Do puntíku dostupnosti GitHubu to neteče, stejně jako detail, diff nebo konverzace —
/// puntík stojí na tom, co běží pravidelně.
@MainActor
@Observable
final class ReleaseNotesModel {
    enum State: Equatable {
        case notLoaded
        case loading
        case loaded([Release])
        /// Věta pro okno — bez sítě nebo při chybě `gh`. Nesmí to být prázdný seznam:
        /// „nepovedlo se to načíst“ a „žádná vydání nejsou“ vypadají v okně stejně
        /// a znamenají opak.
        case failed(String)
    }

    private(set) var state: State = .notLoaded

    /// Tagy vydání, která jsou proti značce nová.
    ///
    /// Počítá se **při načtení**, tedy proti značce **před** jejím posunutím — jinak by odznak
    /// `nové` zhasl v tomtéž okamžiku, kdy se okno otevře, a nebylo by podle čeho poznat, co
    /// je vlastně nového. V rámci běhu se pak nemění: je to odpověď na „co přibylo od minula“,
    /// ne na „co jsem právě odscrolloval“.
    private(set) var unseen: Set<String> = []

    /// Vybraná verze (tag). Po načtení padne na nejnovější, ať okno není poloprázdné.
    var selection: String?

    private let gateway: any GitHubGateway
    private let preferences: any PreferenceStoring

    /// Nabídlo se okno po startu? **Jednou za běh** — zadání #127.
    ///
    /// Bez toho ho otevře každé přestavění hlavního okna (zavřít a otevřít ho jde), protože
    /// `unseen` se v rámci běhu nemění a značka je posunutá hned napoprvé. Chytila to vlastní
    /// revize diffu; komentář v `RootView` o tom původně tvrdil opak.
    private var hasOfferedAfterStart = false

    /// Značka bydlí v předvolbách, ne v `config.json` — viz `PreferenceStoring`.
    private static let lastSeenKey = "releaseNotes.lastSeenTag"

    init(gateway: any GitHubGateway, preferences: any PreferenceStoring = UserDefaults.standard) {
        self.gateway = gateway
        self.preferences = preferences
    }

    var releases: [Release] {
        if case .loaded(let releases) = state { return releases }
        return []
    }

    /// Poslední vydání, které aplikace ukázala. `nil` = ještě nikdy žádné, tedy první
    /// spuštění. Čte se i v testech — jestli se značka posunula, je půlka chování #127.
    var lastSeenTag: String? { preferences.preference(forKey: Self.lastSeenKey) }

    /// Stáhne historii, pokud ještě není.
    ///
    /// **Jednou za běh aplikace** — dvakrát, když se poprvé nepovedlo. Historie se na disk
    /// necachuje: dala by sice offline režim, ale je to další store s vlastním formátem
    /// a vlastním úklidem, a okno bez sítě umí říct proč. Do paměti se vejde (69 releasů
    /// s texty jsou stovky kilobajtů) a při dalším spuštění se stejně musí zeptat, jestli
    /// nepřibylo nové vydání.
    func load() async {
        switch state {
        case .loading, .loaded: return
        case .notLoaded, .failed: await fetch()
        }
    }

    /// Zkusit znovu po selhání. Na rozdíl od `load()` načte i to, co se už načetlo — je to
    /// výslovný pokyn člověka.
    func reload() async {
        guard state != .loading else { return }
        await fetch()
    }

    /// Poznamená si nejnovější vydání jako viděné.
    ///
    /// Značka se posouvá **až tady**, ne při načtení: načíst historii kvůli tomu, aby se
    /// zjistilo, jestli je co ukázat, ještě neznamená, že to někdo viděl. Volá ji **okno**,
    /// jakmile se ukáže — a kontrola při startu jen tehdy, když se okno otevírat nebude.
    ///
    /// `unseen` se tím **nemění**: odznaky mají v otevřeném okně zůstat.
    func markAsSeen() {
        guard let newest = releases.first else { return }
        preferences.setPreference(newest.tag, forKey: Self.lastSeenKey)
    }

    /// Má se okno po startu otevřít samo? Zároveň si značku posune.
    ///
    /// Vrací `false`, když se historie nenačetla — otevřít okno s chybou po každém startu
    /// bez sítě je vyrušení za nic a nikdo o něj nežádal. Kdo o novinky stojí, otevře si je
    /// z menu a chybu i s tlačítkem `Zkusit znovu` uvidí tam.
    ///
    /// **První spuštění mlčí** a značka se jen založí. Bez toho pravidla vypadá po startu
    /// všechno jako nové a okno by zařvalo celou historií — tatáž úvaha jako u snímku
    /// ohlášených PR (#85).
    func showsNewReleaseAfterStart() async -> Bool {
        let isFirstRun = lastSeenTag == nil
        await load()
        guard case .loaded = state else { return false }

        guard !isFirstRun, !unseen.isEmpty else {
            // Není co ukazovat, takže značku posune tahle cesta: buď je nejnovější vydání
            // viděné (posun je pak stejně bez efektu), nebo je tohle první spuštění a od
            // příště se má hlásit jen to, co přibude.
            markAsSeen()
            return false
        }

        // **Ani tady se značka neposouvá**, i když se v tomhle běhu okno už jednou nabídlo.
        // Je pořád co ukazovat — a když se to napoprvé nepovedlo, je tohle přesně ta situace,
        // kvůli které celé #141 vzniklo. Posunout ji tady by tu chybu vrátilo o větev vedle:
        // hlavní okno jde zavřít a otevřít, takže druhý průchod by vydání odbyl, aniž by ho
        // kdo viděl. Nález Copilota na #142.
        guard !hasOfferedAfterStart else { return false }

        hasOfferedAfterStart = true
        // **Značku tady neposouváme.** Posune ji až okno, jakmile se opravdu ukáže
        // (`ReleaseNotesView.task`). Pořadí je stejné pravidlo jako u snímku ohlášených PR
        // (#85): kdo si zapíše „ohlásil jsem“ dřív, než se to povedlo, tu hlášku **už nikdy
        // nepošle**. Stalo se to v provozu hned u prvního releasu, který se měl sám ohlásit —
        // okno se neotevřelo, ale značka se posunula, takže se v1.1.24 nedala ohlásit už nikdy.
        // Takhle se to samo spraví při příštím spuštění.
        return true
    }

    private func fetch() async {
        state = .loading
        do {
            let releases = Policy.sortedReleases(try await gateway.fetchReleases())
            state = .loaded(releases)
            unseen = unseenTags(in: releases)
            // Výběr se drží přes obnovení, ale jen dokud ta verze v seznamu je.
            if selection == nil || !releases.contains(where: { $0.tag == selection }) {
                selection = releases.first?.tag
            }
        } catch let error as GitHubError {
            // Žádné `try?`: bez sítě se z výpadku nesmí stát „nic tu není“.
            state = .failed(error.userDescription)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func unseenTags(in releases: [Release]) -> Set<String> {
        guard let mark = lastSeenTag else { return [] }
        return Set(Policy.newReleases(in: releases, since: mark).map(\.tag))
    }
}
