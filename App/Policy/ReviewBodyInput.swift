import Foundation

/// Co dostane osmá session (#521) — **hotové nálezy a moje starší těla review, nic jiného**.
/// Čisté funkce, žádné I/O.
///
/// **Rozhodovací logika do promptu nepatří.** Co se převzalo a co zůstalo sporné, rozhodla
/// `Policy.autoDraft` (#520) a je to vidět v panelu; session je tu od toho, aby to **napsala mým
/// hlasem**. Kdyby o tom rozhodoval model, byl by to druhý zdroj pravdy o návrhu, jen dražší
/// a pokaždé jiný.
extension Policy {
    /// Materiál pro tělo review (#521).
    ///
    /// **Není v tom ani cesta k repozitáři, ani obsah souboru, ani řádek diffu** — a je na to
    /// negativní test. Session nemá jediný nástroj, takže co jí tenhle text neřekne, se nedozví;
    /// cesta do cache by v něm byla údaj, který nikomu neslouží a v odstavci se umí objevit.
    /// `file:line` v něm je, ale je to **cesta uvnitř repozitáře**, tedy totéž, co stojí v panelu
    /// u komentáře.
    ///
    /// **Verdikt se do zadání nedává, a je to rozhodnutí.** Prompt zakazuje verdikt psát (zůstává
    /// návrhem, #114), takže dát ho do materiálu by znamenalo přiložit údaj, který se v textu nesmí
    /// použít — tedy pozvat model k tomu, aby pravidlo obešel. Tón plyne z nálezů samotných:
    /// blokující se v zadání pozná.
    ///
    /// **Sporné jdou do zadání, i když z nich v draftu není ani komentář.** Je to ta věta, na které
    /// celá skupina #520–#521 stojí: tělo review je první místo, kde se sporný nález dá zamluvit,
    /// takže o něm session **vědět musí** — a prompt jí pak zakazuje vydávat ho za vyřízený.
    ///
    /// **Strop na velikost tu není**, ze stejného, změřeného důvodu jako u briefu (#516): cenu
    /// session určuje boot, ne délka vstupu, a osekaný vstup by se zaplatil tím nejdražším, co
    /// tělo review umí — odstavcem, který o části nálezů mlčí, aniž by to přiznal.
    ///
    /// - Parameters:
    ///   - plan: co si automat vzal a co nechal (`Policy.autoDraftPlan`).
    ///   - voice: moje starší těla review, **od nejnovějšího** (`Policy.mergedReviewVoice`).
    ///     Prázdné = píše se neutrálně, a pruh nad panelem to řekne.
    static func reviewBodyInput(plan: AutoDraftPlan, voice: [ReviewVoiceSample]) -> ReviewBodyMaterial {
        var lines = ["Nálezy z review tohohle pull requestu. Jsou to hotová data, ne dotaz do repozitáře."]

        lines.append("")
        if plan.adopt.isEmpty {
            lines.append("Převzaté nálezy (0): žádný.")
        } else {
            lines.append("Převzaté nálezy (\(plan.adopt.count)) — tyhle už v rozdělaném review leží jako komentáře:")
            lines += plan.adopt.map { "- " + reviewBodyFinding($0) }
        }

        lines.append("")
        if plan.contested.isEmpty {
            lines.append("Sporné nálezy (0): žádný, takže o sporných nepiš vůbec.")
        } else {
            lines.append(
                "Sporné nálezy (\(plan.contested.count)) — tyhle si automat NEvzal a rozhodne o nich člověk:"
            )
            // **Řadí se podle důvodu a textu, ne podle pořadí ve slovníku**: nesetříděný výpis by
            // se mezi dvěma běhy nad týmiž nálezy přeskládal, takže by se zadání měnilo bez důvodu
            // a nedalo by se testovat výčtem.
            lines += plan.contested.values.map(\.label).sorted().map { "- nález s důvodem \($0)" }
        }

        lines.append("")
        if voice.isEmpty {
            lines.append("Ukázky mých starších těl review: žádné. Piš neutrálně a stručně.")
        } else {
            lines.append("Ukázky mých starších těl review (\(voice.count)), od nejnovějšího — vzor stylu, ne obsahu:")
            for sample in voice {
                lines.append("---")
                lines.append(sample.body)
            }
            lines.append("---")
        }

        return ReviewBodyMaterial(text: lines.joined(separator: "\n"), samples: voice.count)
    }

    /// Jeden převzatý nález jako řádek zadání.
    ///
    /// **Řádek musí být jednoznačný sám o sobě** (poučení z #516): model si u nejednoznačného
    /// vstupu domyslí, čeho je to údaj, a domyslí si ho špatně. Proto `blokuje` slovem a `soubor`
    /// před cestou — a proto se **nedává verdikt nálezu**: převzaté jsou z definice `CONFIRMED`
    /// (`Policy.autoDraftPick`), takže by to byl sloupec s jedinou hodnotou.
    private static func reviewBodyFinding(_ finding: Finding) -> String {
        var parts = ["\(finding.reviewer): \(finding.summary.singleLine)"]
        if let category = finding.category { parts.append("kategorie \(category)") }
        if let file = finding.file {
            parts.append(finding.line.map { "soubor \(file):\($0)" } ?? "soubor \(file)")
        }
        if isBlocking(finding) { parts.append("blokuje") }
        return parts.joined(separator: " · ")
    }
}

/// Zadání pro osmou session a to, z čeho se skládalo (#521).
///
/// **Dvojice, ne jen text**, a je to tentýž vzor jako u `BriefMaterial`: počet vzorků hlasu je to,
/// co o hotovém těle říká pruh nad panelem — a kdyby ho skládalo druhé místo, rozešly by se ty dvě
/// zrovna tam, kde na tom záleží. Pruh by tvrdil „podle tvých posledních review“ nad odstavcem,
/// který se psal neutrálně.
struct ReviewBodyMaterial: Equatable, Sendable {
    let text: String
    /// Kolik mých těl review šlo do zadání. **Nula je legitimní** (nový uživatel).
    let samples: Int
}
