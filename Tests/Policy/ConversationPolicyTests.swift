import Foundation
import Testing

@testable import PRism

/// Rozhodování nad konverzací — čisté funkce, nic se nemockuje.
@Suite("Policy — konverzace")
struct ConversationPolicyTests {
    private func thread(
        id: String = "t1",
        path: String = "Cart.php",
        line: Int? = 27,
        originalLine: Int? = 27,
        resolved: Bool = false,
        outdated: Bool = false
    ) -> ReviewThread {
        ReviewThread(
            id: id,
            path: path,
            line: line,
            originalLine: originalLine,
            side: .right,
            isResolved: resolved,
            isOutdated: outdated,
            comments: ConversationPage(items: [], total: 0, hasNextPage: false)
        )
    }

    /// Diff s hunkem, ve kterém jsou nové řádky 25–27 (26 je přidaný, 25 a 27 kontext).
    private func diff(path: String = "Cart.php") throws -> Diff {
        let text = """
        diff --git a/\(path) b/\(path)
        --- a/\(path)
        +++ b/\(path)
        @@ -25,3 +25,3 @@
         kontext
        -staré
        +nové
         další
        """
        return DiffParser.parse(text)
    }

    // MARK: - Rozbalení

    @Test("Nevyřešené vlákno je rozbalené, vyřešené sbalené")
    func usesResolutionAsTheDefault() {
        #expect(Policy.isThreadExpanded(thread(resolved: false), toggled: []))
        #expect(!Policy.isThreadExpanded(thread(resolved: true), toggled: []))
    }

    /// Drží se **odchylka** od výchozího stavu, takže tatáž množina obrací obojí.
    @Test("Překliknutí obrátí výchozí stav v obou směrech")
    func flipsTheDefaultBothWays() {
        #expect(!Policy.isThreadExpanded(thread(resolved: false), toggled: ["t1"]))
        #expect(Policy.isThreadExpanded(thread(resolved: true), toggled: ["t1"]))
    }

    @Test("Cizí vlákno v množině nic nezmění")
    func ignoresOtherThreads() {
        #expect(Policy.isThreadExpanded(thread(id: "t1"), toggled: ["t2", "t3"]))
    }

    // MARK: - Kotvení

    @Test("Vlákno na řádku v hunku má kotvu")
    func anchorsAThreadInsideAHunk() throws {
        let threads = [thread(line: 27)]

        #expect(Policy.threadsInTheDiff(threads, renderedIn: try diff()).count == 1)
        #expect(Policy.threadsOutsideTheDiff(threads, renderedIn: try diff()).isEmpty)
    }

    /// Zastaralé vlákno má `line == nil` a do diffu nepatří: jeho `originalLine` platilo pro
    /// starý head, takže by bublina sedla na cizí kód. Domov má v `Overview` (#72).
    @Test("Zastaralé vlákno kotvu nemá, i když originalLine v diffu je")
    func neverAnchorsAnOutdatedThread() throws {
        let threads = [thread(line: nil, originalLine: 27, outdated: true)]

        #expect(Policy.threadsInTheDiff(threads, renderedIn: try diff()).isEmpty)
        #expect(Policy.threadsOutsideTheDiff(threads, renderedIn: try diff()).count == 1)
    }

    @Test("Vlákno na řádku mimo hunky kotvu nemá")
    func doesNotAnchorOutsideHunks() throws {
        let threads = [thread(line: 500)]

        #expect(Policy.threadsInTheDiff(threads, renderedIn: try diff()).isEmpty)
        #expect(Policy.threadsOutsideTheDiff(threads, renderedIn: try diff()).count == 1)
    }

    @Test("Vlákno k souboru mimo diff kotvu nemá")
    func doesNotAnchorInAnotherFile() throws {
        let threads = [thread(path: "Jinde.php", line: 27)]

        #expect(Policy.threadsInTheDiff(threads, renderedIn: try diff()).isEmpty)
    }

    /// Dokud diff není, nemá se kde kotvit — a vlákna se nesmí ztratit, takže vyjdou jako
    /// „mimo diff“.
    @Test("Bez diffu nemá kotvu nic, ale nic se neztratí")
    func keepsEverythingWithoutADiff() {
        let threads = [thread(line: 27), thread(id: "t2", line: nil, outdated: true)]

        #expect(Policy.threadsInTheDiff(threads, renderedIn: nil).isEmpty)
        #expect(Policy.threadsOutsideTheDiff(threads, renderedIn: nil).count == 2)
    }

    /// Rozdělení musí být úplné — vlákno, které vypadne z obou seznamů, zmizí z okna.
    @Test("Každé vlákno je právě v jednom ze dvou seznamů")
    func splitsExhaustively() throws {
        let threads = [
            thread(id: "a", line: 27),
            thread(id: "b", line: nil, outdated: true),
            thread(id: "c", line: 500),
            thread(id: "d", path: "Jinde.php", line: 27),
        ]
        let diff = try diff()

        let inside = Policy.threadsInTheDiff(threads, renderedIn: diff).map(\.id)
        let outside = Policy.threadsOutsideTheDiff(threads, renderedIn: diff).map(\.id)

        #expect(Set(inside).isDisjoint(with: Set(outside)))
        #expect(Set(inside).union(outside) == ["a", "b", "c", "d"])
    }

    // MARK: - Výběr a pořadí

    @Test("Vlákna se řadí podle řádku, ne podle pořadí v odpovědi")
    func ordersThreadsByLine() throws {
        let file = try #require(try diff().files.first)
        let threads = [thread(id: "c", line: 30), thread(id: "a", line: 26), thread(id: "b", line: 27)]

        #expect(Policy.threads(of: file, from: threads).map(\.id) == ["a", "b", "c"])
    }

    /// Bez druhého kritéria by dvě vlákna na jednom řádku poskakovala mezi překresleními.
    @Test("Při shodě řádku rozhoduje id")
    func breaksTiesByIdentity() throws {
        let file = try #require(try diff().files.first)
        let threads = [thread(id: "b", line: 27), thread(id: "a", line: 27)]

        #expect(Policy.threads(of: file, from: threads).map(\.id) == ["a", "b"])
    }

    /// Přejmenovaný soubor se pozná i pod starou cestou, stejně jako u nálezů.
    @Test("Vlákno se najde i pod starou cestou souboru")
    func matchesTheOldPath() {
        let renamed = DiffParser.parse("""
            diff --git a/Staré.php b/Nové.php
            rename from Staré.php
            rename to Nové.php
            --- a/Staré.php
            +++ b/Nové.php
            @@ -1,2 +1,2 @@
             kontext
            -staré
            +nové
            """)
        guard let file = renamed.files.first else { return }

        #expect(Policy.threads(of: file, from: [thread(path: "Staré.php", line: 2)]).count == 1)
        #expect(Policy.threads(of: file, from: [thread(path: "Nové.php", line: 2)]).count == 1)
    }

    @Test("Vlákna cizího souboru se nepřipletou")
    func ignoresThreadsOfOtherFiles() throws {
        let file = try #require(try diff().files.first)

        #expect(Policy.threads(of: file, from: [thread(path: "Jinde.php")]).isEmpty)
    }

    /// Zastaralé vlákno se z výběru **nevyhazuje** — do bublin se nedostane, ale `Overview`
    /// (#72) ho potřebuje, takže se jen řadí na začátek.
    @Test("Vlákno bez řádku se řadí na začátek, nezmizí")
    func keepsThreadsWithoutALine() throws {
        let file = try #require(try diff().files.first)
        let threads = [thread(id: "s-radkem", line: 27), thread(id: "bez-radku", line: nil)]

        #expect(Policy.threads(of: file, from: threads).map(\.id) == ["bez-radku", "s-radkem"])
    }
}
