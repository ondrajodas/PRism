import Foundation
import Testing

@testable import PRism

/// Co se má hlásit (#86).
///
/// To hlavní tady není, že se dá něco vypnout, ale dvě věci, které se dají pokazit tiše:
/// že **hlavní vypínač přebíjí všechno** a že **rozbitá hodnota aplikaci neumlčí** — o vypnuté
/// notifikaci se pozná jen tím, že nic nepřišlo, takže by se to hledalo dlouho.
@Suite("Nastavení notifikací")
struct NotificationSettingsTests {
    @Test("Výchozí stav hlásí všechno")
    func announcesEverythingByDefault() {
        // Vypnuté notifikace by znamenaly, že se funkce po vydání nikdy neprojeví.
        let settings = NotificationSettings()

        for event in NotificationEvent.allCases {
            #expect(settings.allows(event), "\(event) má být ve výchozím stavu zapnuté")
        }
    }

    @Test("Hlavní vypínač přebíjí jednotlivé události")
    func theMasterSwitchWins() {
        // Jinak by „vypnuto“ znamenalo „vypnuto, ale ještě se podívej na ty čtyři přepínače“.
        let settings = NotificationSettings(isEnabled: false)

        for event in NotificationEvent.allCases {
            #expect(!settings.allows(event), "\(event) se s vypnutým vypínačem nesmí hlásit")
        }
    }

    @Test("Vypnutá událost vypne jen sebe")
    func turningOneOffKeepsTheRest() {
        let settings = NotificationSettings(clean: false)

        #expect(!settings.allows(.clean))
        #expect(settings.allows(.findings))
        #expect(settings.allows(.newPullRequest))
        #expect(settings.allows(.failure))
    }

    @Test("Chybějící sekce v souboru znamená výchozí hodnoty")
    func aMissingSectionMeansDefaults() throws {
        // Ručně psaný `config.json` málokdy obsahuje všechno — a starší soubory tuhle sekci
        // nemají vůbec.
        let json = Data("""
        { "global": { "pollIntervalSeconds": 90 } }
        """.utf8)

        let configuration = try JSONDecoder().decode(Configuration.self, from: json)

        #expect(configuration.global.notifications == NotificationSettings())
        #expect(configuration.global.pollIntervalSeconds == 90)
    }

    @Test("Chybějící přepínač uvnitř sekce se bere jako zapnutý")
    func aMissingToggleMeansOn() throws {
        let json = Data("""
        { "global": { "notifications": { "clean": false } } }
        """.utf8)

        let configuration = try JSONDecoder().decode(Configuration.self, from: json)

        #expect(!configuration.global.notifications.allows(.clean))
        #expect(configuration.global.notifications.allows(.findings))
        #expect(configuration.global.notifications.isEnabled)
    }

    @Test("Rozbitá hodnota aplikaci neumlčí")
    func aBrokenValueDoesNotSilenceTheApp() throws {
        // Opačná volba než u `allowsPublishing`, kde se překlep sráží na zakázáno: tam nesmí
        // otevřít cestu ven, kdežto tady je nejhorším následkem notifikace, o kterou si nikdo
        // neřekl — a ta se dá zavřít. Umlčená aplikace se naopak pozná až tím, že nic nepřišlo.
        let json = Data("""
        { "global": { "notifications": { "isEnabled": "ano", "findings": 3 } } }
        """.utf8)

        let configuration = try JSONDecoder().decode(Configuration.self, from: json)

        #expect(configuration.global.notifications.isEnabled)
        #expect(configuration.global.notifications.allows(.findings))
    }

    @Test("Rozbitý přepínač nezahodí ty ostatní")
    func aBrokenToggleKeepsTheOthers() throws {
        // Celá sekce se kvůli jednomu překlepu zahazovat nemá — jinak by se s ním vypnulo
        // i to, co je napsané správně.
        let json = Data("""
        { "global": { "notifications": { "clean": false, "findings": "nesmysl" } } }
        """.utf8)

        let configuration = try JSONDecoder().decode(Configuration.self, from: json)

        #expect(!configuration.global.notifications.allows(.clean))
        #expect(configuration.global.notifications.allows(.findings))
    }

    @Test("Nastavení projde round-tripem")
    func survivesARoundTrip() throws {
        let settings = NotificationSettings(
            isEnabled: true,
            newPullRequest: false,
            findings: true,
            clean: false,
            failure: true
        )

        let decoded = try JSONDecoder().decode(
            NotificationSettings.self,
            from: JSONEncoder().encode(settings)
        )

        #expect(decoded == settings)
    }
}
