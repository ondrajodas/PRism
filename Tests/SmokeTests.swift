import Foundation
import Testing

@testable import pr_review

/// Smoke testy scaffoldu. Nedělají nic chytrého — ověřují, že se testy linkují proti
/// app bundlu a že se do něj propsaly build settings. Když se projekt rozbije, padá tohle.
@Test func appBundleIdentifierMatchesProjectSetting() {
    #expect(Bundle.main.bundleIdentifier == "com.ondrajodas.pr-review")
}

/// Projekt, target i repo se jmenují `pr-review`; uživateli se aplikace hlásí jinak.
@Test func appPresentsItselfUnderFriendlyName() {
    let displayName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
    let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String

    #expect(displayName == "GitHub PR Review")
    #expect(name == "GitHub PR Review")
}

@Test @MainActor func contentViewCanBeCreated() {
    _ = ContentView()
}
