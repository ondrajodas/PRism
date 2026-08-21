import AppKit
import SwiftUI
import Testing

@testable import PRism

/// Sledování konce v okně výpisu kroků (#325) — **na skutečném scrollu, ne na čisté funkci**.
///
/// Rozhodnutí mají svoje testy jako čisté funkce (`StepFeedTests`); tady se ověřuje to, co z nich
/// čistou funkci neudělá: **že se okno doopravdy dojede na nejnovější krok**, když do osy přibude
/// událost. Bez toho by číslo 20 → 5 v komentáři u `catchUp(in:)` bylo tvrzení bez dokladu — a byla
/// to zrovna ta věc, kterou implementace napoprvé neměla (posun ve stejném průchodu SwiftUI zahodí).
///
/// Poloha se čte z `NSScrollView` uvnitř hostované hierarchie, protože jinde není — do observable
/// stavu se **nezapisuje** (#252) a to je záměr, ne mezera v testu.
///
/// **Druhou polovinu (odrolovaný výpis se nesmí sám vrátit na konec) harness neuveze**, a je to
/// změřené, ne odhad: `WheelGesture` nad tímhle scrollem neposune vůbec nic (skončil na 1687,
/// tedy tam, kde začal) a `contentView.scroll(to:)` si SwiftUI přerovná zpátky. Tatáž mez jako
/// u `onContinuousHover` v #358. Testuje se proto rozhodnutí
/// (`Policy.stepFeedReaction`, výčtem) a zbytek ověří člověk v pauze — je to v popisu PR.
@MainActor
@Suite("Sledování konce ve výpisu kroků")
struct StepFeedTailTests {
    private let worktree = URL(filePath: "/tmp/cache/worktrees/keboola/job-queue/725-c66a21")
    private let start = Date(timeIntervalSince1970: 1_000_000)

    /// Tolik kroků, aby obsah okna (138 bodů) přerostl mnohonásobně.
    private let steps = 120

    @Test("Rostoucí osa se drží u konce")
    func followsTheTail() async throws {
        let scene = try prepared()
        let scroll = try #require(scene.scroll)

        #expect(isAtEnd(scroll), "po usazení zbývá od konce \(distanceFromEnd(of: scroll)) bodů")

        let before = scene.contentHeight
        scene.model.append(step: 1)
        _ = await waitUntil("výpis vysází nový krok") { [scene] in
            await MainActor.run { scene.layout(); return scene.contentHeight > before }
        }

        // **Čeká se na jev se stropem** (#269), ne na pevný okamžik: posun je odpověď na
        // přerovnání obsahu, takže se stane o kolo smyčky později než sazba nového řádku.
        _ = await waitUntil("výpis dojede na konec") { [self] in
            await MainActor.run { scene.layout(); return isAtEnd(scroll) }
        }
        #expect(
            isAtEnd(scroll),
            "po nové události zbývá od konce \(distanceFromEnd(of: scroll)) bodů"
        )
    }

    // MARK: - Scéna

    /// Hostovaný výpis a osa, do které se dá sypat.
    @MainActor
    private final class Scene {
        let model: Model
        let hosting: NSHostingView<StepFeedHarness>
        let window: NSWindow

        init(model: Model) {
            self.model = model
            hosting = NSHostingView(rootView: StepFeedHarness(model: model))
            hosting.frame = NSRect(x: 0, y: 0, width: 900, height: 400)
            window = NSWindow(
                contentRect: hosting.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.contentView = hosting
            // Mimo obrazovku, ať sonda nikomu neskočí před oči.
            window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
            window.orderFront(nil)
        }

        deinit { window.orderOut(nil) }

        var scroll: NSScrollView? { Scene.scrollView(in: hosting) }

        var contentHeight: Double { Double(scroll?.documentView?.frame.height ?? 0) }

        func layout() {
            hosting.layoutSubtreeIfNeeded()
            hosting.displayIfNeeded()
        }

        private static func scrollView(in view: NSView) -> NSScrollView? {
            if let scroll = view as? NSScrollView { return scroll }
            for subview in view.subviews {
                if let found = scrollView(in: subview) { return found }
            }
            return nil
        }
    }

    @Observable
    @MainActor
    final class Model {
        var timeline: ReviewerTimeline

        init(timeline: ReviewerTimeline) {
            self.timeline = timeline
        }

        func append(step: Int) {
            timeline.record(
                .attemptedTool(ToolAttempt(name: "Read", detail: "src/Nový\(step).php", id: "n\(step)")),
                at: Date()
            )
        }
    }

    struct StepFeedHarness: View {
        let model: Model

        var body: some View {
            let lane = Policy.lanes(
                of: [model.timeline],
                skills: ["code-review"],
                running: ["code-review"]
            )[0]
            StepFeedView(lane: lane, state: .expanded, toggle: {})
                .frame(width: 900)
                .background(Palette.surface)
        }
    }

    private func prepared() throws -> Scene {
        // Styl scrollerů se nechává usadit napřed (#343): legacy scroller z výšky ubírá, overlay
        // ne, takže by se okno mohlo přerovnat uprostřed měření.
        TestWait.awaitSettledScrollerStyle()
        var timeline = ReviewerTimeline(skill: "code-review", worktree: worktree)
        timeline.record(.started(sessionID: "abc123"), at: start)
        for index in 0..<steps {
            timeline.record(
                .attemptedTool(ToolAttempt(name: "Read", detail: "src/Job\(index).php", id: "t\(index)")),
                at: start + Double(index)
            )
        }
        let scene = Scene(model: Model(timeline: timeline))
        // Usazení hierarchie: bez něj se čte poloha okna, které se ještě nerozvrhlo.
        for _ in 0..<5 {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            scene.layout()
        }
        return scene
    }

    /// Je výpis na konci? Ptá se **tou samou funkcí, jakou se rozhoduje okno** — vlastní vzorec
    /// v testu by hlídal jiné číslo, než na kterém aplikace stojí.
    private func isAtEnd(_ scroll: NSScrollView) -> Bool {
        guard let document = scroll.documentView else { return true }
        return Policy.stepFeedAtEnd(
            offset: Double(scroll.documentVisibleRect.origin.y),
            visible: Double(scroll.contentView.bounds.height),
            content: Double(document.frame.height) - StepFeedView.rowsInset
        )
    }

    /// Kolik bodů zbývá od dolní hrany obsahu. Počítá se **bez ohledu na překlopení dokumentu**:
    /// jestli je `NSScrollView` uvnitř SwiftUI flipped, je detail AppKitu, ne věc, kterou by měl
    /// test tvrdit.
    private func distanceFromEnd(of scroll: NSScrollView) -> Double {
        guard let document = scroll.documentView else { return 0 }
        let visible = scroll.documentVisibleRect
        return Double(document.isFlipped ? document.frame.height - visible.maxY : visible.minY)
    }
}
