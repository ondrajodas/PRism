import Foundation
import Testing

@testable import PRism

@Suite("Source")
struct SourceTests {
    @Test("Přežije cestu na disk a zpět")
    func survivesRoundTrip() throws {
        let source = Source(name: "Tým backend", query: "team-review-requested:keboola/backend is:open")

        #expect(try roundTrip(source) == source)
    }

    @Test("Výchozí zdroj hledá review vyžádaná po mně")
    func defaultSourceAsksForMyReviewRequests() {
        #expect(Source.reviewRequested.query.contains("review-requested:@me"))
    }

    @Test("Výchozí zdroj se omezuje na otevřené PR")
    func defaultSourceIsLimitedToOpenPullRequests() {
        // Bez `is:open` vrací `gh search prs` i zavřené a mergnuté — fronta k review by
        // se plnila věcmi, se kterými se nedá nic dělat.
        #expect(Source.reviewRequested.query.contains("is:open"))
    }
}
