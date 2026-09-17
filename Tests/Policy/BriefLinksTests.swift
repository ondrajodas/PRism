import Foundation
import Testing

@testable import PRism

/// Odkazy ve větách briefu (#516) — které číslo se stane klikatelným a na co ukazuje.
///
/// **Nejcennější tvrzení téhle sady jsou negativní**: že se odkaz **nevyrobí** na číslo, které do
/// briefu nešlo, a že se **nehádá** repozitář tam, kde ho text neurčuje. Obojí se rozbije potichu
/// — výsledkem porušení není chyba, ale zvýrazněné číslo, po kterém se otevře záložka nad
/// pull requestem, o kterém v briefu nebyla řeč.
@Suite("Brief — odkazy ve větách (#516)")
struct BriefLinksTests {
    private let prism = PRIdentifier("ondrajodas/PRism#584")!
    private let queue = PRIdentifier("keboola/job-queue#727")!

    /// Číslo, které do briefu doopravdy šlo, se stane odkazem — a **odkazem je jen číslo**, ne
    /// celé `owner/name #584`: jméno repozitáře před ním je próza.
    @Test("Číslo z briefu je odkaz, jméno repa zůstává textem")
    func linksTheNumberOnly() {
        #expect(
            Policy.briefSpans(of: "Review na ondrajodas/PRism #584 skončil čistě.", mentioning: [prism])
                == [
                    .text("Review na ondrajodas/PRism "),
                    .link("#584", prism),
                    .text(" skončil čistě."),
                ]
        )
    }

    /// **Číslo, které do briefu nešlo, zůstane prostým textem.** Text je volný výstup modelu, takže
    /// v něm může stát cokoli — a odkaz na neexistující pull request je horší než prostý text:
    /// klikne se na něj a otevře se záložka nad ničím.
    @Test("Číslo, které do briefu nešlo, není odkaz")
    func refusesUnknownNumbers() {
        #expect(
            Policy.briefSpans(of: "Vezmi si ondrajodas/PRism #999.", mentioning: [prism])
                == [.text("Vezmi si ondrajodas/PRism #999.")]
        )
    }

    /// **Bez jména repa rozhoduje jednoznačnost.** Jedno číslo v seznamu jednou → odkaz.
    @Test("Holé číslo se odkazem stane, jestli je v seznamu jediné")
    func linksBareNumberWhenUnambiguous() {
        #expect(
            Policy.briefSpans(of: "Na #727 leží 4 nálezy.", mentioning: [prism, queue])
                == [.text("Na "), .link("#727", queue), .text(" leží 4 nálezy.")]
        )
    }

    /// **Totéž číslo ve dvou repech a bez jména před ním je otázka, na kterou v textu odpověď
    /// není** — hádat se nemá co, takže zůstane text.
    @Test("Dvojznačné holé číslo zůstává textem")
    func refusesAmbiguousBareNumbers() {
        let twin = PRIdentifier("keboola/vault#584")!

        #expect(
            Policy.briefSpans(of: "Na #584 leží nález.", mentioning: [prism, twin])
                == [.text("Na #584 leží nález.")]
        )
    }

    /// **Jméno repa před číslem cíl určuje** — i když je totéž číslo ve dvou repech.
    @Test("Jméno repa před číslem vybere z dvojice tu správnou")
    func repoPrefixPicksTheTarget() {
        let twin = PRIdentifier("keboola/vault#584")!

        #expect(
            Policy.briefSpans(of: "Vezmi keboola/vault #584 dřív.", mentioning: [prism, twin])
                == [.text("Vezmi keboola/vault "), .link("#584", twin), .text(" dřív.")]
        )
        #expect(
            Policy.briefSpans(of: "Vezmi ondrajodas/PRism #584 dřív.", mentioning: [prism, twin])
                == [.text("Vezmi ondrajodas/PRism "), .link("#584", prism), .text(" dřív.")]
        )
    }

    /// **Cizí jméno repa je odmítnutí, ne nejbližší podobný.** Kdyby se tenhle případ spolehl jen
    /// na jednoznačnost čísla, odkazoval by `keboola/job-queue #584` nad deskou, kde je jenom
    /// `ondrajodas/PRism #584`, na cizí pull request.
    @Test("Cizí jméno repa odkaz nevyrobí, i když je číslo jednoznačné")
    func refusesForeignRepoNames() {
        #expect(
            Policy.briefSpans(of: "Hoří keboola/job-queue #584.", mentioning: [prism])
                == [.text("Hoří keboola/job-queue #584.")]
        )
        // Cesta se dvěma lomítky je taky nárok na repozitář, který se se seznamem nepotká.
        #expect(
            Policy.briefSpans(of: "V a/b/c #584 nic není.", mentioning: [prism])
                == [.text("V a/b/c #584 nic není.")]
        )
    }

    /// Jméno repa se srovnává **bez ohledu na velikost písmen** — `PRism` a `prism` je týž
    /// repozitář a model velikost neopisuje spolehlivě.
    @Test("Na velikosti písmen ve jménu repa nezáleží")
    func ignoresRepoNameCase() {
        #expect(
            Policy.briefSpans(of: "Vezmi ondrajodas/prism#584.", mentioning: [prism])
                == [.text("Vezmi ondrajodas/prism"), .link("#584", prism), .text(".")]
        )
    }

    /// Věta beze změny: bez čísla, bez seznamu, nebo s číslem, které číslem není.
    @Test("Co se nedá odkázat, projde jako jeden text")
    func passesPlainTextThrough() {
        #expect(
            Policy.briefSpans(of: "Fronta je prázdná.", mentioning: [prism])
                == [.text("Fronta je prázdná.")]
        )
        #expect(
            Policy.briefSpans(of: "Review na ondrajodas/PRism #584 doběhlo.", mentioning: [])
                == [.text("Review na ondrajodas/PRism #584 doběhlo.")]
        )
        // Mřížka bez číslice a číslo, za kterým hned pokračuje písmeno — ani jedno není odkaz.
        #expect(Policy.briefSpans(of: "# nic", mentioning: [prism]) == [.text("# nic")])
        #expect(
            Policy.briefSpans(of: "Posun o #584px.", mentioning: [prism]) == [.text("Posun o #584px.")]
        )
    }

    /// Dva odkazy v jedné větě a odkaz na jejím **konci** — kolem odkazu se nesmí objevit prázdný
    /// kus textu, jinak by se věta v okně skládala z prázdných běhů.
    @Test("Dva odkazy v jedné větě a žádný prázdný kus")
    func linksTwiceWithoutEmptySpans() {
        let spans = Policy.briefSpans(
            of: "#727 blokuje ondrajodas/PRism #584",
            mentioning: [prism, queue]
        )

        #expect(spans == [
            .link("#727", queue),
            .text(" blokuje ondrajodas/PRism "),
            .link("#584", prism),
        ])
        for span in spans {
            if case .text(let plain) = span { #expect(!plain.isEmpty) }
        }
    }

    /// **Celá věta se ze spanů složí zpátky doslova.** Rozdělení je jen o tom, kde se dá kliknout
    /// — text se jím nesmí změnit ani o znak, jinak by blok tvrdil něco jiného než session.
    @Test("Ze spanů se věta složí doslova zpátky")
    func keepsTheSentenceIntact() {
        let sentences = [
            "Review na ondrajodas/PRism #584 skončil čistě.",
            "Na keboola/job-queue #727 jsou 2 blokující nálezy z 4.",
            "Vezmi si do merge ondrajodas/PRism #584.",
            "Fronta je prázdná.",
            "#727",
        ]
        for sentence in sentences {
            let joined = Policy.briefSpans(of: sentence, mentioning: [prism, queue])
                .map { span in
                    switch span {
                    case .text(let plain): plain
                    case .link(let label, _): label
                    }
                }
                .joined()
            #expect(joined == sentence)
        }
    }
}
