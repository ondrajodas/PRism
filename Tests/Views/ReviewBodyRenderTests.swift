import AppKit
import Foundation
import SwiftUI
import Testing

@testable import PRism

/// Že pruh nad panelem a dráha v `Průběhu` (#521) **doopravdy kreslí to, co v razítku je** —
/// stavy vedle sebe a rozdíl bitmap.
///
/// Existuje kvůli mezeře, kterou `ReviewBodyLaneTests` nezavřou: ty tvrdí, co `Policy` vydá, takže
/// by prošly i nad pruhem, který druhou řádku vůbec nenapojil. **Rozdíl bitmap, ne čtení textu**
/// (jako u #514): accessibility tree se v hostovaném okně nenaplní, takže „je vidět“ se dá tvrdit
/// jedině z pixelů.
///
/// `NSHostingView` v okně, ne `ImageRenderer`; okno se ukazuje **bez animace** (#462).
@MainActor
@Suite("Tělo review se kreslí z razítka (#521)")
struct ReviewBodyRenderTests {
    /// Šířka panelu na jeho minimu (300) po odečtení vodorovného odsazení `DraftPanel`u.
    private static let panelWidth: CGFloat = 268

    private var note: String { Policy.autoDraftNote(at: "21:52", adopted: 3, contested: 2) }

    // MARK: - Pruh nad panelem

    /// **Nejcennější tvrzení téhle sady.** Kdyby se `bodyNote` nenapojil, byly by všechny tři
    /// bitmapy shodné — a `ReviewBodyLaneTests` by u toho zůstaly zelené, protože testují `Policy`.
    @Test("Tři stavy těla se kreslí různě")
    func theBandDrawsAllThreeStates() throws {
        let voice = try band("pruh-hlas", AutoDraftBody(samples: 7))
        let neutral = try band("pruh-neutral", AutoDraftBody(samples: 0))
        let failed = try band(
            "pruh-selhani",
            AutoDraftBody(samples: 4, failure: .session(detail: "Tělo review nedoběhlo v limitu 3 minuty."))
        )

        #expect(voice != neutral)
        #expect(voice != failed)
        #expect(neutral != failed)
    }

    /// Razítko z doby před #521 tělo nemá — pruh musí vyjít **stejně jako bez druhé řádky**,
    /// tedy žádné prázdné místo pod první větou.
    @Test("Bez těla je pruh stejný jako před #521")
    func theBandIsUnchangedWithoutABody() throws {
        let withoutBody = try band("pruh-bez-tela", nil)
        let bare = try bitmap("pruh-jednoradkovy", width: Self.panelWidth) {
            AutoDraftNoteView(note: note)
        }

        #expect(withoutBody == bare)
    }

    /// Druhá řádka pruh **zvýší** — a je to to jediné, co o rozvržení jde tvrdit bez čtení textu:
    /// `if let` může projít, aniž by se řádka do pruhu vešla.
    @Test("Druhá řádka pruh zvýší")
    func theSecondLineMakesTheBandTaller() throws {
        let withBody = try band("pruh-vysky-s-telem", AutoDraftBody(samples: 7))
        let withoutBody = try band("pruh-vysky-bez-tela", nil)

        #expect(try height(of: withBody) > height(of: withoutBody))
    }

    // MARK: - Dráha v Průběhu

    /// Dráha `tělo review` musí rozeznat doběhlou od nepoužité — věta pod ní je to jediné, čím se
    /// ty dva stavy v okně liší (obě jsou `finished`, tedy stejně barevné).
    @Test("Doběhlá a nepoužitá dráha se kreslí různě")
    func theLaneDistinguishesUsedFromUnused() throws {
        let used = try lane("draha-pouzito", AutoDraftBody(samples: 5, usage: RunUsage(cost: 0.12)))
        let unused = try lane(
            "draha-nepouzito",
            AutoDraftBody(samples: 5, failure: .handWritten, usage: RunUsage(cost: 0.12))
        )

        #expect(used != unused)
    }

    @Test("Neutrální tělo má na dráze vlastní větu")
    func theLaneSaysWhenTheVoiceWasMissing() throws {
        let voice = try lane("draha-hlas", AutoDraftBody(samples: 5))
        let neutral = try lane("draha-neutral", AutoDraftBody(samples: 0))

        #expect(voice != neutral)
    }

    // MARK: - Kreslení

    private func band(_ name: String, _ body: AutoDraftBody?) throws -> Data {
        try bitmap(name, width: Self.panelWidth) {
            AutoDraftNoteView(note: note, bodyNote: Policy.reviewBodyNote(body))
        }
    }

    private func lane(_ name: String, _ body: AutoDraftBody) throws -> Data {
        let lane = try #require(Policy.reviewBodyLane(isRunning: false, body: body))
        return try bitmap(name, width: Self.panelWidth) {
            ReviewerLaneView(lane: lane, shortName: lane.skill, feed: .none, toggleFeed: {})
        }
    }

    private func height(of png: Data) throws -> Int {
        try #require(NSBitmapImageRep(data: png)).pixelsHigh
    }

    private func bitmap<Content: View>(
        _ name: String,
        width: CGFloat,
        _ content: () -> Content
    ) throws -> Data {
        let appearance = try #require(NSAppearance(named: .darkAqua))
        var result: Result<Data, any Error>?
        appearance.performAsCurrentDrawingAppearance {
            do {
                let scene = content()
                    .frame(width: width)
                    .background(Palette.chrome)
                    .environment(\.colorScheme, .dark)
                    .tint(Palette.accent)
                let hosting = NSHostingView(rootView: scene)
                // Výška se **měří**, nenasazuje: podle ní se pozná, že druhá řádka pruh zvýšila.
                hosting.frame = NSRect(
                    x: 0,
                    y: 0,
                    width: width,
                    height: max(hosting.fittingSize.height, 40)
                )
                let window = NSWindow(
                    contentRect: hosting.frame,
                    styleMask: [.borderless],
                    backing: .buffered,
                    defer: false
                )
                window.contentView = hosting
                // Mimo obrazovku, ať test nikomu neskočí před oči — v paralelním běhu stojí vedle
                // sebe víc instancí.
                window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
                window.orderFrontUnanimated()
                defer { window.orderOut(nil) }
                RunLoop.current.run(until: Date().addingTimeInterval(0.4))
                let rep = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
                hosting.cacheDisplay(in: hosting.bounds, to: rep)
                let png = try #require(rep.representation(using: .png, properties: [:]))
                if let directory = ProcessInfo.processInfo.environment["PRISM_RENDER_DIR"] {
                    let url = URL(filePath: directory).appending(path: "telo-\(name).png")
                    try png.write(to: url)
                    print("RENDER \(url.path)")
                }
                result = .success(png)
            } catch {
                result = .failure(error)
            }
        }
        return try #require(result).get()
    }
}
