import Foundation
import Testing

@testable import PRism

/// Snímek otevřených záložek na disku (#527).
///
/// Sada tvrdí dvě věci a obě se rozbijí potichu: že se snímek **přečte tak, jak se zapsal**
/// (rozbitý tvar by po restartu vypadal jako „nic nebylo otevřené“), a že se **nesahá mimo
/// cache** (tvrdá podmínka č. 3, tatáž kontrola jako u draftů a značek `Prošlo`).
@Suite("OpenTabsStore — tabs.json (#527)")
@MainActor
struct OpenTabsStoreTests {
    private let directory: TemporaryDirectory
    private let layout: CacheLayout
    private let store: OpenTabsStore
    private let vault = PRIdentifier("keboola/vault#85")!
    private let cli = PRIdentifier("cli/cli#1")!

    init() throws {
        directory = try TemporaryDirectory()
        layout = CacheLayout(root: directory.url)
        store = OpenTabsStore(layout: layout)
    }

    private var snapshot: OpenTabs {
        OpenTabs(
            tabs: [
                OpenTab(
                    pullRequest: vault,
                    tab: .filesChanged,
                    anchor: DiffScrollAnchor(file: "App/Store/AppStore.swift", line: 174),
                    openedByLink: true
                ),
                OpenTab(pullRequest: cli, tab: .overview)
            ],
            active: cli
        )
    }

    @Test("Snímek se přečte tak, jak se zapsal")
    func aRoundTripKeepsEverything() {
        store.save(snapshot)

        #expect(store.load() == snapshot)
    }

    /// **Bez souboru je prázdno, ne pád** — je to první spuštění po instalaci a taky stav před
    /// #527, na který aplikace musí umět odpovědět prázdným pruhem.
    @Test("Chybějící soubor znamená prázdný snímek")
    func aMissingFileIsEmpty() {
        #expect(store.load() == .none)
        #expect(store.load().isEmpty)
    }

    /// **Nečitelný soubor taky prázdno, a je to opačná volba než u nálezů.** Nejhorší následek je
    /// jedno spuštění bez záložek; hlásit to do okna by znamenalo poruchu nad něčím, co se opraví
    /// prvním otevřením záložky.
    @Test("Rozbitý soubor znamená prázdný snímek, ne chybu")
    func aBrokenFileIsEmpty() throws {
        try Data("{ tohle není json".utf8).write(to: layout.openTabsFile)

        #expect(store.load() == .none)
    }

    /// Snímek s **přejmenovaným tabem** se zahodí celý. Je to zapsaná cena za `String` raw value
    /// u `PullRequestTab`: jeden `?? .standard` by se tvářil jako volba člověka.
    @Test("Neznámý tab vezme s sebou celý snímek")
    func anUnknownTabDiscardsTheSnapshot() throws {
        let json = """
            {"active":"keboola/vault#85","tabs":[
              {"openedByLink":false,"pullRequest":"keboola/vault#85","tab":"tenhleTabNeexistuje"}
            ]}
            """
        try Data(json.utf8).write(to: layout.openTabsFile)

        #expect(store.load() == .none)
    }

    /// **Prázdný snímek se maže, ne ukládá**: soubor s prázdným seznamem by se nedal odlišit od
    /// „nikdy jsem nic neotevřel“ a v cache by zbyl po každém zavření poslední záložky.
    @Test("Prázdný snímek soubor smaže")
    func anEmptySnapshotRemovesTheFile() {
        store.save(snapshot)
        #expect(FileManager.default.fileExists(atPath: layout.openTabsFile.path(percentEncoded: false)))

        store.save(.none)

        #expect(!FileManager.default.fileExists(atPath: layout.openTabsFile.path(percentEncoded: false)))
        #expect(store.load() == .none)
    }

    /// **Symlink by přečetl soubor mimo cache.** Tatáž kontrola, jakou má `AskStore` (#452)
    /// a `ReadMarkStore` (#500) — tvrdá podmínka č. 3, ne opatrnost.
    @Test("Symbolický odkaz na místě snímku se nečte ani nepřepíše")
    func symlinkIsRejected() throws {
        let outside = directory.url.appending(path: "mimo.json")
        let foreign = OpenTabs(tabs: [OpenTab(pullRequest: cli, tab: .overview)], active: nil)
        try JSONEncoder().encode(foreign).write(to: outside)
        try FileManager.default.createSymbolicLink(
            at: layout.openTabsFile,
            withDestinationURL: outside
        )

        #expect(store.load() == .none)

        // A zápis přes odkaz nesmí přepsat cíl mimo cache.
        store.save(snapshot)
        #expect(try JSONDecoder().decode(OpenTabs.self, from: Data(contentsOf: outside)) == foreign)
    }

    /// `tabs.json` leží v **kořeni cache slotu**, ne pod `reviews/` — a kořen si aplikace bere
    /// z `CFBundleName`, takže je to zároveň to jediné, co dělí paralelní okna od sebe (#228).
    ///
    /// Z toho zároveň plyne, že druhá polovina `CacheFile.refusal` (`outsideCache`) je u tohohle
    /// souboru **nedosažitelná**: cesta je vždycky `root/tabs.json`, takže po rozbalení symlinků
    /// leží její rodič rovný kořeni. Kontrola v `OpenTabsStore` přesto zůstává celá, protože
    /// hranice cache má v repu **jedno místo** a půlka verdiktu je pobídka, aby si ho příště
    /// někdo opsal. Ta dosažitelná půlka (odkaz na souboru) má vlastní test výš.
    @Test("Snímek leží v kořeni cache, ne u nálezů")
    func theFileSitsInTheCacheRoot() {
        #expect(layout.openTabsFile == directory.url.appending(path: "tabs.json"))
        // Cestou, ne `URL`em: `deletingLastPathComponent()` nechává na konci lomítko, takže by
        // se dvě adresy téže složky nerovnaly.
        #expect(
            layout.openTabsFile.deletingLastPathComponent().path(percentEncoded: false)
                == layout.root.path(percentEncoded: false) + "/"
        )
    }

    /// Dva sloty jsou dvě cache, takže si snímky nepřepisují. Je to celé, co k tomu bylo potřeba
    /// udělat — a stojí to na tom, že `CacheLayout` bere kořen z jména bundlu.
    @Test("Dva sloty mají každý svůj snímek")
    func slotsDoNotShareTheSnapshot() throws {
        let other = try TemporaryDirectory()
        let otherStore = OpenTabsStore(layout: CacheLayout(root: other.url))

        store.save(snapshot)

        #expect(otherStore.load() == .none)
    }
}
