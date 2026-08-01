import Foundation

/// Drží cache v rozumné velikosti.
///
/// Repozitáře můžou být libovolné, takže bez úklidu by cache rostla, dokud nedojde disk.
/// Maže se ve třech krocích: nejdřív stromy, o které už není zájem, pak celá repa, po
/// kterých nezbyl žádný sledovaný PR, a nakonec podle stáří použití, dokud se cache
/// nevejde do rozpočtu.
///
/// **Repo s běžícím review je nedotknutelné** — smazat klon pod běžícím review by mu vzalo
/// pracovní strom pod rukama. Rozpočet je strop na místo na disku, ne důvod rozbít
/// rozdělanou práci.
struct CacheEviction: Sendable {
    private let layout: CacheLayout
    private let budget: Int
    private let checkout: (any RepoCheckout)?

    /// 10 GB je zatím konstanta; do konfigurace se přesune s #23.
    static let defaultBudget = 10 * 1024 * 1024 * 1024

    /// `checkout` je volitelný jen kvůli testům eviction samotné — v aplikaci se předává,
    /// aby se s repem zahodily i refy, které si aplikace k jeho PR založila.
    init(
        layout: CacheLayout = .applicationSupport,
        budget: Int = defaultBudget,
        checkout: (any RepoCheckout)? = nil
    ) {
        self.layout = layout
        self.budget = budget
        self.checkout = checkout
    }

    /// - Parameters:
    ///   - openPullRequests: co je teď ve sledovaném seznamu. **Ne totéž co „otevřené na
    ///     GitHubu“** — PR, který zůstal otevřený, ale už po mně review nechce, ze seznamu
    ///     vypadne a jeho cache je k zahození stejně jako u zavřeného.
    ///   - busy: repa, se kterými se právě pracuje. Ta se nemažou za žádnou cenu.
    ///     Předává se jako **dotaz**, ne jako snímek: úklid je dlouhá disková operace
    ///     a příprava, která začne uprostřed ní, by jinak přišla o ochranu.
    func run(
        openPullRequests: [PRIdentifier],
        busy: @Sendable () async -> Set<RepoID>
    ) async throws {
        let wanted = Set(openPullRequests.map(\.repo))
        let cached = cachedRepositories()

        try await discardUnwantedWorktrees(keeping: openPullRequests, busy: busy)

        for repo in cached where !wanted.contains(repo) {
            guard await !busy().contains(repo) else { continue }
            try evict(repo)
        }

        try await forgetClosedPullRequests(openPullRequests, cached: cached, busy: busy)
        try await evictOverBudget(busy: busy)
    }

    /// Stromy PR, které zmizely ze sledovaného seznamu. Bez tohohle by strom zavřeného PR
    /// přežil v repu, které v cache zůstává kvůli jiným PR, a nesmazal by ho nikdo.
    ///
    /// Stromy po **starším commitu** téhož PR se tu nepoznají: seznam z pollingu nese jen
    /// `PullRequestSummary`, a ten `headSha` nemá (`gh search prs` ho neumí). Uklidí se, až
    /// PR ze seznamu odejde — nebo je zahodí ten, kdo review spouští, protože ten sha zná.
    private func discardUnwantedWorktrees(
        keeping open: [PRIdentifier],
        busy: @Sendable () async -> Set<RepoID>
    ) async throws {
        // Klíčem je `(repo, číslo)`, ne samotné číslo: čísla PR se mezi repozitáři
        // opakují, takže `repoA#1` by si držel při životě strom `repoB#1`.
        let wanted = Set(open)

        var touched: Set<RepoID> = []
        for (repo, worktree) in allWorktrees() {
            guard await !busy().contains(repo) else { continue }
            let number = Int(worktree.lastPathComponent.split(separator: "-").first ?? "")
            guard let number, wanted.contains(PRIdentifier(repo: repo, number: number)) else {
                try remove(worktree)
                touched.insert(repo)
                continue
            }
        }

        // Smazat složku nestačí: klon si o stromu drží záznam a příští `worktree add` na
        // stejnou cestu skončí `missing but already registered` — a to už napořád.
        for repo in touched {
            try await checkout?.pruneWorktrees(in: repo)
        }
    }

    /// Refy, které si aplikace založila k PR (`refs/prism/pr/<n>`), kotví objekty commitu.
    /// Bez úklidu by je `git gc` nesměl nikdy zahodit. Místo se tím neuvolní hned — gc se
    /// odkotvených objektů dotkne až po své vlastní lhůtě — ale bez toho by nedošlo nikdy.
    private func forgetClosedPullRequests(
        _ open: [PRIdentifier],
        cached: [RepoID],
        busy: @Sendable () async -> Set<RepoID>
    ) async throws {
        guard let checkout else { return }
        let openByRepo = Dictionary(grouping: open, by: \.repo)

        for repo in cached {
            guard await !busy().contains(repo) else { continue }
            let keep = Set(openByRepo[repo, default: []].map(\.number))
            // Výpis refů dělá `git`, ne `FileManager`: `git gc` volné refy zabalí do
            // `packed-refs` a složku `refs/prism/pr` přitom smaže, takže čtení adresáře
            // by po prvním gc tiše přestalo cokoli najít.
            for number in try await checkout.trackedPullRequests(in: repo) where !keep.contains(number) {
                try await checkout.forgetPullRequest(PRIdentifier(repo: repo, number: number))
            }
        }
    }

    /// Nejdéle nepoužité odcházejí první. Kdo je zrovna v práci, zůstává — i za cenu
    /// překročeného rozpočtu.
    private func evictOverBudget(busy: @Sendable () async -> Set<RepoID>) async throws {
        var entries = try cachedRepositories().map {
            (repo: $0, size: try size(of: $0), lastUsed: lastUsed($0))
        }
        var total = entries.reduce(0) { $0 + $1.size }
        guard total > budget else { return }

        // Razítko se čte jednou dopředu, ne při každém porovnání.
        entries.sort { $0.lastUsed < $1.lastUsed }

        for entry in entries where total > budget {
            guard await !busy().contains(entry.repo) else { continue }
            try evict(entry.repo)
            total -= entry.size
        }
    }

    /// Do rozpočtu se počítá klon **i jeho stromy**. Klon je `--filter=blob:none`, takže
    /// materializované soubory leží právě ve stromech — počítat jen klon by znamenalo
    /// měřit menšinu toho, co cache zabírá.
    private func size(of repo: RepoID) throws -> Int {
        try size(of: layout.bareClone(for: repo)) + size(of: layout.worktrees(of: repo))
    }

    private func evict(_ repo: RepoID) throws {
        // S klonem jdou i jeho stromy: bez repozitáře je z nich jen složka, ve které
        // `git` neodpoví. A razítko taky — leží vedle klonu, ne v něm.
        try remove(layout.worktrees(of: repo))
        try remove(layout.bareClone(for: repo))
        try remove(layout.lastUsedMarker(for: repo))
    }

    /// Maže se jen to, co skutečně leží v cache.
    ///
    /// Symlink v cestě umí mazání vyvést ven — `removeItem` přes odkaz v rodičovské
    /// komponentě smaže **cíl**, ne odkaz. Aplikace si takový odkaz sama nevyrobí, ale
    /// „nikdy nesahat na uživatelovy klony“ je tvrdá podmínka, a tohle je jediné místo,
    /// které maže rekurzivně podle toho, co našlo na disku.
    private func remove(_ url: URL) throws {
        let resolved = url.resolvingSymlinksInPath().path(percentEncoded: false)
        let root = layout.root.resolvingSymlinksInPath().path(percentEncoded: false)
        guard resolved.hasPrefix(root + "/") else {
            throw CheckoutError.cacheUnavailable("Cesta \(resolved) vede mimo cache aplikace.")
        }

        do {
            try FileManager.default.removeItem(at: url)
        } catch CocoaError.fileNoSuchFile {
            return
        } catch {
            throw CheckoutError.cacheUnavailable(
                "\(url.path(percentEncoded: false)) nejde smazat: " + error.localizedDescription
            )
        }
    }

    /// Co v cache je. Vlastník je složka, repo je `<jméno>.git` v ní.
    private func cachedRepositories() -> [RepoID] {
        children(of: layout.repositories).flatMap { owner in
            children(of: layout.repositories.appending(path: owner)).compactMap { name in
                guard name.hasSuffix(".git") else { return nil }
                // Přes parsovací init: jméno pochází z disku, takže `..` ani prázdno
                // nesmí projít — a `RepoID(owner:name:)` by na tom spadl.
                return RepoID("\(owner)/\(String(name.dropLast(4)))")
            }
        }
    }

    private func allWorktrees() -> [(RepoID, URL)] {
        children(of: layout.worktrees).flatMap { owner -> [(RepoID, URL)] in
            let ownerRoot = layout.worktrees.appending(path: owner)
            return children(of: ownerRoot).flatMap { name -> [(RepoID, URL)] in
                guard let repo = RepoID("\(owner)/\(name)") else { return [] }
                let repoRoot = ownerRoot.appending(path: name)
                return children(of: repoRoot).map { (repo, repoRoot.appending(path: $0)) }
            }
        }
    }

    private func children(of directory: URL) -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false))) ?? []
    }

    private func size(of directory: URL) throws -> Int {
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .isRegularFileKey]
        guard let files = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: Array(keys)
        ) else { return 0 }

        var total = 0
        for case let file as URL in files {
            let values = try? file.resourceValues(forKeys: keys)
            guard values?.isRegularFile == true else { continue }
            total += values?.totalFileAllocatedSize ?? 0
        }
        return total
    }

    private func lastUsed(_ repo: RepoID) -> Date {
        // Neznámé stáří se bere jako nejstarší — repo bez záznamu je zbytek po starší
        // verzi nebo po klonu, který nedoběhl.
        (try? Self.lastUsed(repo, in: layout)) ?? .distantPast
    }
}

extension CacheEviction {
    /// Zaznamená, že se s repem právě pracovalo.
    ///
    /// Zápis je atomický a jde jen do cache — stejná kontrola jako u mazání. Symlink
    /// v cestě by jinak psal mimo ni, a „pracuje výhradně ve své cache“ je tvrdá podmínka.
    static func markUsed(_ repo: RepoID, at date: Date = .now, in layout: CacheLayout) throws {
        let marker = try insideCache(layout.lastUsedMarker(for: repo), of: layout)
        let stamp = ISO8601DateFormatter().string(from: date)
        try Data(stamp.utf8).write(to: marker, options: .atomic)
    }

    static func lastUsed(_ repo: RepoID, in layout: CacheLayout) throws -> Date? {
        let marker = try insideCache(layout.lastUsedMarker(for: repo), of: layout)
        let data = try Data(contentsOf: marker)
        return ISO8601DateFormatter().date(from: String(decoding: data, as: UTF8.self))
    }

    /// Vrátí cestu, jen když po rozbalení symlinků leží pod kořenem cache.
    private static func insideCache(_ url: URL, of layout: CacheLayout) throws -> URL {
        let root = layout.root.resolvingSymlinksInPath().path(percentEncoded: false)
        // Rozbaluje se rodič: samotný soubor ještě existovat nemusí.
        let parent = url.deletingLastPathComponent().resolvingSymlinksInPath().path(percentEncoded: false)
        guard parent == root || parent.hasPrefix(root + "/") else {
            throw CheckoutError.cacheUnavailable("Cesta \(parent) vede mimo cache aplikace.")
        }
        return url
    }
}
