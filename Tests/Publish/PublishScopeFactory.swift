import Foundation

@testable import PRism

extension PublishScope {
    /// Brána, která povolí vyjmenovaná repa a nic jiného.
    ///
    /// **Není to fake** — skládá se tou samou cestou jako v aplikaci (`Configuration`
    /// → `resolved(for:)`), jen si konfiguraci sestaví test. Druhý způsob, jak bránu
    /// postavit, by znamenal, že se testy dají projít i tehdy, když se ta cesta rozbije.
    static func allowing(_ repos: RepoID...) -> PublishScope {
        var configuration = Configuration.standard
        for repo in repos {
            configuration.setRepository(RepositoryConfig(allowsPublishing: true), for: repo)
        }
        return PublishScope(configuration: configuration)
    }

    /// Brána z **výchozí** konfigurace. Nepovolí nic — a to je vlastnost, na které stojí
    /// tvrdá podmínka č. 1: dokud si o odesílání někdo výslovně neřekne, neodejde nikam nic.
    static let standard = PublishScope(configuration: .standard)
}
