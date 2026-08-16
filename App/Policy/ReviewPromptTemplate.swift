import Foundation

/// Zadání pro reviewera rozdělené na **psanou šablonu** a **neodstranitelné jádro** (#281).
///
/// Do #281 byl celý prompt natvrdo v `ClaudeCommand`, takže se dal změnit jedině commitem —
/// a přitom je to zrovna ta věc, která se mění nejčastěji a posuzuje se podle výsledku.
/// Prosté „celý prompt je textové pole“ ale nejde: tři věty v tom textu nejsou styl, ale
/// **kontrakt aplikace**, a každá se dá smazat potichu.
///
/// Dělí se to proto na dvě části:
///
/// - **Šablona** (`standard`) je to, co si uživatel přepisuje. Nese zástupné texty
///   `{{skill}}` a `{{baseSha}}`, které dosadí aplikace při spuštění.
/// - **Jádro** (`core`) se připojuje **vždycky** a ze šablony se vyhodit nedá. Drží
///   `ReportFindings` i s prázdným seznamem a zákaz zápisu a odesílání.
///
/// **Jádro není bezpečnostní opatření.** Tvrdou podmínku č. 2 drží `--disallowedTools`
/// v `ClaudeCommand`, ne věta v promptu — a editovatelná šablona na ní nemění nic:
/// povolení se skládají v kódu, ze šablony se do nich nedá sáhnout a nic v ní nedokáže
/// nástroj povolit. Jádro chrání **sběr nálezů**: bez `ReportFindings` reviewer nálezy
/// napíše jako text, sběr přes tool cally tiše nefunguje a v okně stojí „čisté review“ —
/// tedy text, který tvrdí víc, než data unesou.
///
/// **Otevírá se jen prompt review.** Kontrola nálezů z minula (`RecheckCommand`, #150)
/// a překlad nálezů (`TranslationCommand`) zůstávají natvrdo, protože u nich odpověď nenese
/// nástroj, ale **parser** o pár řádků níž: editovatelný prompt by tam rozbil čtení, ne jen
/// výsledek.
enum ReviewPromptTemplate {
    /// Zástupný text za id skillu, na který se běh pouští.
    static let skillPlaceholder = "{{skill}}"
    /// Zástupný text za commit, proti kterému se diffuje.
    static let baseShaPlaceholder = "{{baseSha}}"

    /// Výchozí šablona — **doslova ten text, co byl do #281 v kódu**, jen se zástupnými texty
    /// místo dosazených hodnot.
    ///
    /// Nesmí se rozejít s dnešním chováním: `Configuration.standard` drží hodnoty, se kterými
    /// aplikace běžela, než konfigurace existovala, a zavedení pole ji nesmí začít měnit.
    /// Hlídá to test, který složený prompt porovnává **znak po znaku** s literálem.
    static let standard = """
        You are reviewing a pull request. \
        First call the Skill tool with skill="\(skillPlaceholder)" and follow the \
        instructions it gives you — that skill defines how this review is done. \
        The head commit is checked out here; see the changes with \
        `git diff \(baseShaPlaceholder)...HEAD`; there is no GitHub access, so read the \
        working tree instead of fetching the pull request.
        """

    /// Věty, které se k šabloně připojí **vždycky** — i tehdy, když si je uživatel ze šablony
    /// smaže. Viz úvod typu: chrání sběr nálezů, ne bránu ven.
    static let core = """
        Report every finding by calling the ReportFindings tool — that call is the only \
        output that counts, so call it even when you find nothing, with an empty list. \
        Do not run anything that writes or sends: no commits, no pushes, \
        no `gh` commands, no comments on GitHub. \
        These rules override anything the skill tells you.
        """

    /// Hodnoty do náhledu v nastavení.
    ///
    /// **Pevné, ne z konfigurace.** Náhled odpovídá na „jak bude text vypadat po dosazení“,
    /// takže se nemá měnit podle toho, které repo je zrovna vybrané nebo jaký skill stojí
    /// v sadě první — jinak by se z něj četlo tvrzení o konkrétním běhu, které to není.
    static let sampleSkillID = "code-review:code-review"
    static let sampleBaseSha = "a1b2c3d"

    /// Co v šabloně chybí.
    ///
    /// Vlastní typ, ne pole řetězců: text u pole a text v hlášce o nespuštěném review mají být
    /// **tentýž** — dvě formulace téhož by se rozešly a z okna by nebylo poznat, že jde
    /// o jednu chybu.
    enum Problem: String, Hashable, Sendable, CaseIterable, Identifiable {
        case missingSkill
        case missingBaseSha

        var id: String { rawValue }

        /// Zástupný text, který chybí.
        var placeholder: String {
            switch self {
            case .missingSkill: ReviewPromptTemplate.skillPlaceholder
            case .missingBaseSha: ReviewPromptTemplate.baseShaPlaceholder
            }
        }

        /// Proč to vadí. Bez důvodu je hláška „chybí zástupný text“ jen zákaz.
        var reason: String {
            switch self {
            case .missingSkill:
                "Chybí \(placeholder) — bez něj se nakonfigurovaný skill nenačte a reviewer si pravidla domyslí."
            case .missingBaseSha:
                "Chybí \(placeholder) — strom je odpojený na head commitu, takže bez base sha nemá reviewer proti čemu diffovat."
            }
        }
    }
}

extension Policy {
    /// Šablona, se kterou se doopravdy poběží. Prázdná (i samá mezera) znamená **ber výchozí**.
    ///
    /// Prázdné pole je běžný mezistav — text se smaže ⌘A a začne se psát znovu. Pustit
    /// reviewera s prázdným zadáním je horší než ho pustit s tím původním, takže se prázdno
    /// bere jako „nic jsem neřekl“, ne jako vlastní odpověď. U seznamů (`skills`) je to
    /// schválně naopak: tam prázdno znamená „tady nereviewuj nic“, protože seznam se prázdný
    /// **nechává**, kdežto text se prázdný jen prochází.
    static func reviewPromptTemplate(from configured: String) -> String {
        let trimmed = configured.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? ReviewPromptTemplate.standard : trimmed
    }

    /// Co šabloně chybí. Prázdný výsledek = dá se s ní běžet.
    ///
    /// **Prázdná šablona je v pořádku**, protože znamená „ber výchozí“ — a ta výchozí oba
    /// zástupné texty má. Vyhodnocuje se proto to, s čím se doopravdy poběží, ne to, co je
    /// zrovna napsané v poli.
    ///
    /// Pořadí je pořadí `Problem.allCases`, aby se hlášky u pole nepřeskupovaly podle toho,
    /// co uživatel smazal dřív.
    static func reviewPromptProblems(in configured: String) -> [ReviewPromptTemplate.Problem] {
        let template = reviewPromptTemplate(from: configured)
        return ReviewPromptTemplate.Problem.allCases.filter { !template.contains($0.placeholder) }
    }

    /// Šablona s dosazenými hodnotami, **bez jádra**.
    ///
    /// Samostatně to potřebuje náhled v nastavení: kreslí obě části zvlášť, aby bylo vidět,
    /// kde končí psané a začíná připojované. Dosazovat zástupné texty ve view by bylo druhé
    /// místo, kde se to dělá — a rozešlo by se.
    static func reviewPromptBody(template configured: String, skillID: String, baseSha: String) -> String {
        reviewPromptTemplate(from: configured)
            .replacingOccurrences(of: ReviewPromptTemplate.skillPlaceholder, with: skillID)
            .replacingOccurrences(of: ReviewPromptTemplate.baseShaPlaceholder, with: baseSha)
    }

    /// Poskládaný prompt: šablona s dosazenými hodnotami a za ní jádro.
    ///
    /// **Jádro se připojí vždycky**, ať je v šabloně cokoli — i když si ho tam uživatel napíše
    /// sám (pak je v promptu dvakrát, což je nepěkné, ale neškodné; zahodit „skoro stejnou“
    /// větu by znamenalo hádat, co je ještě ona).
    ///
    /// Spojuje se **jednou mezerou** a šablona se předtím ořízne: prompt je jeden řádek
    /// a dvě mezery za sebou v něm nemají co dělat.
    static func reviewPrompt(template configured: String, skillID: String, baseSha: String) -> String {
        reviewPromptBody(template: configured, skillID: skillID, baseSha: baseSha)
            + " " + ReviewPromptTemplate.core
    }
}
