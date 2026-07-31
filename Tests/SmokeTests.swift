import Foundation
import Testing

@testable import PRism

/// Smoke testy scaffoldu. Nedělají nic chytrého — ověřují, že se testy linkují proti
/// app bundlu a že se do něj propsaly build settings. Když se projekt rozbije, padá tohle.
@Test func appBundleIdentifierMatchesProjectSetting() {
    #expect(Bundle.main.bundleIdentifier == "com.ondrajodas.prism")
}

/// Název je jeden napříč vším — hlídá, že se v bundlu neobjeví jiný než `PRism`.
@Test func appPresentsItselfAsPRism() {
    let displayName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
    let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String

    #expect(displayName == "PRism")
    #expect(name == "PRism")
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
    _ = RootView()
}
