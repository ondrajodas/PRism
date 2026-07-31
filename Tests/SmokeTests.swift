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
    _ = ContentView()
}
