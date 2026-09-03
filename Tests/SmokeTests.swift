import Foundation
import Testing

@testable import PRism

/// Smoke testy scaffoldu. Nedělají nic chytrého — ověřují, že se testy linkují proti
/// app bundlu a že se do něj propsaly build settings. Když se projekt rozbije, padá tohle.
///
/// **Hostitel se od #411 nejmenuje jako aplikace**, a je to celý ten fígl: výchozí `PRISM_SLOT`
/// v projektu je `.testhost`, takže `UserDefaults.standard` v testech není nastavení uživatele.
/// Hodnotu pro hlavní instanci a slot dosazuje `bin/run.sh`. Proč to tak je a co na tom stojí,
/// hlídají `ProcessPreferencesTests`.
@Test func appBundleIdentifierMatchesProjectSetting() {
    #expect(Bundle.main.bundleIdentifier == "com.ondrajodas.prism.testhost")
}

/// Název je jeden napříč vším — hlídá, že se v bundlu neobjeví jiný než `PRism` a jeho slot.
///
/// **Od #421 má i hostitel svůj slot** (`PRism-testhost`), takže se tady netvrdí rovnost
/// s `PRism`. Důvod je v `ProcessPreferencesTests` — `CFBundleName` určuje kořen cache, takže
/// hostitel s holým `PRism` pracoval nad cache hlavní instance; rovnost by tvrdila zrovna to, co
/// se opravovalo. Tvrdí se tedy tři věci: že se **oba klíče shodují** (do menu baru a do Docku
/// nesmí jít dvě různá jména), že jméno **začíná** na `PRism`, a jaké je jméno hostitele.
@Test func appPresentsItselfAsPRism() {
    let displayName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
    let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String

    #expect(displayName == name)
    #expect(name?.hasPrefix("PRism") == true)
    #expect(name == "PRism-testhost", "hostitel má mít vlastní slot, viz ProcessPreferencesTests")
}

@Test @MainActor func contentViewCanBeCreated() {
    _ = ContentView(store: AppStore(gateway: FakeGitHubGateway(always: .success([]))))
}

/// Gate obrazovka se staví z reportu, který v testech nikdy nevznikne z běžného provozu —
/// tohle hlídá, že se dá složit i pro stav, kdy chybí binárka a `gh` je nepřihlášené.
@Test @MainActor func preflightGateCanBeCreatedForBlockedEnvironment() {
    let report = PreflightReport(
        toolStates: [
            .gh: .found(URL(filePath: "/opt/homebrew/bin/gh"), source: .knownLocation),
            .git: .found(URL(filePath: "/usr/bin/git"), source: .loginShellPath),
            .claude: .missing,
        ],
        ghAuth: .loggedOut
    )

    _ = PreflightGateView(report: report, onRetry: {})
}

@Test @MainActor func rootViewCanBeCreated() {
    _ = RootView(model: PreflightModel())
}

/// Okno nastavení se dá otevřít i dřív, než projde preflight — musí se tedy dát složit
/// i bez store.
@Test @MainActor func settingsSceneCanBeCreatedBeforePreflightPasses() {
    _ = SettingsScene(preflight: PreflightModel())
}

@Test @MainActor func settingsViewCanBeCreated() {
    _ = SettingsView(store: AppStore(gateway: FakeGitHubGateway(always: .success([]))))
}
