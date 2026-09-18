import Foundation

/// Zahození záznamu (#81) a odmítnutí jednotlivého nálezu (#113).
///
/// Obojí je mazání výsledku, ale **jiného rozsahu**: `clearFindings` zahodí celý záznam,
/// `dismissFinding` jeden nález a záznam nechá platit.
extension AppStore {
    /// Zahodí uložené nálezy vybraného PR.
    ///
    /// Smysl je pustit review znovu, typicky jiným skillem: nový běh **nahrazuje jen běh
    /// téhož skillu**, takže po změně sady zůstávají v záznamu nálezy od revieweera, který
    /// už neběží — a návrh verdiktu počítá z obojího.
    ///
    /// Maže se jen záznam pro commit, který je **vidět** — ostatní zůstávají. „Historie
    /// zůstává“ se tedy vztahuje na ostatní záznamy, ne na ochranu toho viditelného: kdo
    /// zmáčkne zahodit nad zastaralými nálezy, chce se zbavit právě jich.
    ///
    /// Selhání **letí ven**: nesmazaný záznam, o kterém se mlčí, vypadá v panelu jako
    /// smazaný, dokud si někdo nevšimne, že se po restartu vrátil.
    func clearFindings(for pr: PRIdentifier) async throws {
        guard let reviews, let record = reviewRecords[pr] else { return }
        try await reviews.delete(for: pr, at: record.headSha)
        reviewRecords[pr] = nil

        // Plánovač si pamatuje `updatedAt`, se kterým PR naposledy zvažoval, takže by ho po
        // vyčištění považoval za vyřízený až do dalšího pushe. Zahození nálezů je ale právě
        // ta chvíle, kdy se má review pustit znovu.
        consideredForAutomation[pr] = nil
        // A hned, ne až za minutu: kdo nálezy zahodí, čeká výsledek, ne příští tik. Jde se
        // tou samou cestou jako po tiku, včetně rozpočtu a limitu souběhu. U manuálního repa
        // se nestane nic — tam se spouští tlačítkem.
        await startAutomaticReviews(for: pullRequests)
    }

    /// Odmítne nález jako falešně pozitivní (#113).
    ///
    /// Je to opak `clearFindings`: ten je hrubý nástroj („pusť review znovu s jinou sadou“),
    /// tohle řeší jeden nález a **ostatní nechá platit**. Proto se z toho ani nespouští další
    /// review — nic nového se nezjistilo, jen jsem něco posoudil.
    ///
    /// Rozdělané review se tím **nemění**: cizí nález je cizí věta, můj převzatý komentář je
    /// moje próza. Vyjímá se v tabu `Moje review`, ne jedním bitem odsud.
    func dismissFinding(_ finding: Finding, as reason: FindingDismissal.Reason, for pr: PRIdentifier) async {
        await applyDismissal(for: pr) { reviews in
            try await reviews.dismiss(finding, as: reason, in: pr)
        }
    }

    /// Vrátí odmítnutý nález mezi platné.
    func restoreFinding(_ finding: Finding, for pr: PRIdentifier) async {
        await applyDismissal(for: pr) { reviews in
            try await reviews.restore(finding, in: pr)
        }
    }

    /// Zapíše změnu a srovná podle ní paměť. Disk rozhoduje: kdyby se mapa v paměti měnila
    /// před zápisem, odmítnutí by po neúspěšném zápisu zůstalo vidět a po restartu zmizelo.
    private func applyDismissal(
        for pr: PRIdentifier,
        _ write: (ReviewStore) async throws -> ReviewRecord
    ) async {
        guard let reviews else { return }
        do {
            reviewRecords[pr] = try await write(reviews)
            dismissalFailure = nil
            // Součet po reviewerech (#514) se přepočítá **jen po úspěšném zápisu**: je to čistá
            // funkce nad diskem, takže po selhání by vydala totéž co předtím — a přepočet za
            // neúspěchem by tvrdil, že se něco změnilo.
            await refreshReviewerTallies()
        } catch {
            dismissalFailure = "Posouzení nálezu se nepodařilo uložit. \(error.localizedDescription)"
        }
    }

    // MARK: - Zastaralé nálezy (#174)

    /// Rozešly se nálezy s hlavou PR **z načteného detailu**? `nil` = nerozešly, nebo se to nedá
    /// říct.
    ///
    /// Čte to hlavička nad taby (`StaleHeadView`), odznak v pruhu „od tvé poslední návštěvy“ (#284)
    /// i zápis do dění (#414) — a všechno to mluví o témže stavu, takže samotné **porovnání sha je
    /// jedno** (`Policy.staleFindings(of:head:)`). Tady zůstává jen to, odkud se dnešní hlava bere:
    /// z detailu. Druhý zdroj té sha je dávkový dotaz na hlavy (#420), který jde tou samou čistou
    /// funkcí — dvě porovnání by znamenala dvě pravdy o jedné věci (tvrdá podmínka č. 5).
    ///
    /// Bez načteného detailu je odpověď `nil`, ne „zastaralo“: dokud neznáme dnešní hlavu,
    /// nevíme o rozchodu nic. Záznam bez review v mapě není vůbec, takže PR, na kterém se
    /// review nikdy nepustilo, tudy nikdy neprojde.
    func staleFindings(for pr: PRIdentifier) -> StaleFindings? {
        guard case .loaded(let detail, _) = detailState(for: pr) else { return nil }
        return Policy.staleFindings(of: reviewRecords[pr], head: detail.headSha)
    }

    // MARK: - Rozbalení bubliny (#185)

    /// Jak je nález u kódu rozbalený. Kategorie se berou z konfigurace **toho repa**, protože
    /// blokující sada je per repo — s konstantou by bublina v jednom repu přišpendlila něco,
    /// co v druhém neblokuje.
    func findingDisclosure(of group: FindingGroup, in pr: PRIdentifier) -> FindingDisclosure {
        Policy.disclosure(
            of: group,
            categories: resolved(for: pr.repo).blockingCategories,
            toggled: toggledFindings[pr] ?? []
        )
    }

    /// Překlikne rozbalení. Drží se **odchylka** od výchozího stavu, takže tatáž hodnota
    /// v množině sbalí blokující nález i rozbalí ten ostatní.
    func toggleFinding(_ group: FindingGroup, in pr: PRIdentifier) {
        let key = Policy.disclosureKey(of: group)
        var toggled = toggledFindings[pr] ?? []
        if toggled.contains(key) {
            toggled.remove(key)
        } else {
            toggled.insert(key)
        }
        // Prázdná množina se maže, ať v mapě nezůstávají klíče bez obsahu — stejně jako
        // u vláken.
        toggledFindings[pr] = toggled.isEmpty ? nil : toggled
    }

    /// Rozbalí nález, na který se právě skočilo — z lišty nad diffem i z tabulky.
    ///
    /// Bez toho by skok na sbalený nález ukázal **značku** místo nálezu, na který se kliklo. Je
    /// to tatáž úvaha, kvůli které skok rozbaluje i sbalený soubor: cíl, na kterém není co
    /// přečíst, je k nerozeznání od skoku, který se nepovedl.
    ///
    /// Odmítnutá skupina se **nerozbaluje** ani takhle: rozbalovat u ní není co a její jediný
    /// řádek už tam je.
    func revealFinding(_ group: FindingGroup, in pr: PRIdentifier) {
        guard findingDisclosure(of: group, in: pr) == .collapsed else { return }
        toggleFinding(group, in: pr)
    }
}
