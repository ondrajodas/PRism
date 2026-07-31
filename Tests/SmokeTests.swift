import Foundation
import Testing

@testable import pr_review

/// Smoke testy scaffoldu. Nedělají nic chytrého — ověřují, že se testy linkují proti
/// app bundlu a že se do něj propsaly build settings. Když se projekt rozbije, padá tohle.
@Test func appBundleIdentifierMatchesProjectSetting() {
    #expect(Bundle.main.bundleIdentifier == "com.ondrajodas.pr-review")
}

@Test @MainActor func contentViewCanBeCreated() {
    _ = ContentView()
}
