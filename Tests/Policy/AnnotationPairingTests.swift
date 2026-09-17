import Foundation
import Testing

@testable import PRism

/// Co se z uložených anotací smí ukázat a kam se posadí (#524).
///
/// Dvě tvrzení se rozbijí potichu a proto mají vlastní test: **anotace z jiné hlavy se neukáže
/// vůbec** (tvrdá podmínka č. 5 — index hunku je poziční, takže by po pushi ukazovala na cizí kód,
/// ne na starý) a **páruje se přes index, ne přes text** (úryvek by se musel v diffu hledat
/// a řádek, který je v souboru dvakrát, by anotaci posadil jinam).
@Suite("Anotace hunků — párování a platnost (#524)")
struct AnnotationPairingTests {
    private let pr = PRIdentifier(repo: RepoID(owner: "cli", name: "cli"), number: 42)

    private func stored(
        headSha: String = "aaaa1111",
        hunks: [HunkAnnotation] = [],
        files: [FileAnnotation] = [],
        outcome: ReviewRunOutcome = .finished,
        answered: Bool = true,
        dropped: Int = 0
    ) -> StoredAnnotations {
        StoredAnnotations(
            pullRequest: pr,
            headSha: headSha,
            hunks: hunks,
            files: files,
            outcome: outcome,
            sessionID: "s1",
            answered: answered,
            dropped: dropped,
            finishedAt: Date(timeIntervalSince1970: 100),
            usage: nil
        )
    }

    private func hunk(_ start: Int) -> DiffHunk {
        DiffHunk(oldStart: start, oldCount: 3, newStart: start, newCount: 3, heading: "", lines: [])
    }

    private func file(_ path: String, hunks count: Int, oldPath: String? = nil) -> FileDiff {
        FileDiff(
            oldPath: oldPath ?? path,
            newPath: path,
            change: oldPath == nil ? .modified : .renamed,
            isBinary: false,
            hunks: (0..<count).map { hunk($0 * 10 + 1) }
        )
    }

    // MARK: - Platnost proti hlavě

    /// **Jiná hlava = neukáže se nic.** Nález se smí ukázat jako `zastaralý`, anotace ne: je
    /// vázaná na **pořadí** hunku, takže stačí hunk přidaný nad ní a všechny se posunou.
    @Test("Anotace z jiné hlavy se nevydá")
    func annotationsFromAnotherHeadAreHidden() {
        let record = stored(headSha: "aaaa1111")

        #expect(Policy.annotations(of: record, head: "aaaa1111") == record)
        #expect(Policy.annotations(of: record, head: "bbbb2222") == nil)
    }

    /// **Neznámá hlava je zákaz, ne povolení.** Dokud se detail nenačetl, není proti čemu platnost
    /// posoudit — a věta nad hunkem, o které se neví, jestli platí, je horší než prázdno.
    @Test("Neznámá nebo prázdná hlava anotace nevydá", arguments: [nil, ""])
    func anUnknownHeadHidesEverything(head: String?) {
        #expect(Policy.annotations(of: stored(), head: head) == nil)
    }

    @Test("Bez uloženého záznamu se nevydá nic")
    func nothingStoredMeansNothingShown() {
        #expect(Policy.annotations(of: nil, head: "aaaa1111") == nil)
    }

    // MARK: - Párování přes index

    /// **Index, ne text** (zadání #524). Nástroj hlásí pořadí od jedné, klíčem výsledku je index
    /// od nuly — tedy to, čím se v diffu indexuje.
    @Test("Anotace se posadí podle pořadí hunku")
    func pairsByHunkOrder() {
        let record = stored(hunks: [
            HunkAnnotation(file: "App/A.swift", hunk: 1, why: "první", source: nil),
            HunkAnnotation(file: "App/A.swift", hunk: 3, why: "třetí", source: nil),
        ])

        let paired = Policy.annotations(of: record, in: file("App/A.swift", hunks: 3))

        #expect(paired[0]?.why == "první")
        #expect(paired[1] == nil)
        #expect(paired[2]?.why == "třetí")
    }

    /// **Index mimo rozsah se zahazuje.** Dvanáctý hunk u souboru o třech znamená, že se session
    /// spletla — a věta u posledního hunku „aby se neztratila“ by tvrdila něco o kódu, kterého se
    /// netýká.
    @Test("Index mimo rozsah se zahodí, neposadí na kraj")
    func dropsOutOfRangeIndexes() {
        let record = stored(hunks: [
            HunkAnnotation(file: "App/A.swift", hunk: 12, why: "mimo", source: nil)
        ])

        #expect(Policy.annotations(of: record, in: file("App/A.swift", hunks: 3)).isEmpty)
    }

    /// Cesta z anotace musí sedět **přesně**. Soubor stejného jména v jiné složce je jiný soubor,
    /// takže se nepáruje podle přípony ani podle konce cesty.
    @Test("Cizí cesta se nespáruje")
    func doesNotPairAForeignPath() {
        let record = stored(hunks: [
            HunkAnnotation(file: "Tests/A.swift", hunk: 1, why: "jinde", source: nil)
        ])

        #expect(Policy.annotations(of: record, in: file("App/A.swift", hunks: 2)).isEmpty)
    }

    /// U přejmenování si session může opsat **kterékoli** ze dvou jmen a obojí je pravda o tomtéž
    /// souboru.
    @Test("U přejmenovaného souboru sedí nové i staré jméno")
    func pairsBothNamesOfARenamedFile() {
        let renamed = file("App/New.swift", hunks: 1, oldPath: "App/Old.swift")

        let byNewName = stored(hunks: [
            HunkAnnotation(file: "App/New.swift", hunk: 1, why: "nové", source: nil)
        ])
        let byOldName = stored(hunks: [
            HunkAnnotation(file: "App/Old.swift", hunk: 1, why: "staré", source: nil)
        ])

        #expect(Policy.annotations(of: byNewName, in: renamed)[0]?.why == "nové")
        #expect(Policy.annotations(of: byOldName, in: renamed)[0]?.why == "staré")
    }

    @Test("Bez záznamu se nepáruje nic")
    func pairsNothingWithoutARecord() {
        #expect(Policy.annotations(of: nil, in: file("App/A.swift", hunks: 2)).isEmpty)
    }

    // MARK: - Druh změny u souboru

    @Test("Druh změny se najde podle cesty")
    func findsTheChangeKind() {
        let record = stored(files: [
            FileAnnotation(file: "App/A.swift", kind: .refactor),
            FileAnnotation(file: "App/B.swift", kind: .test),
        ])

        #expect(Policy.changeKind(of: record, in: file("App/A.swift", hunks: 1)) == .refactor)
        #expect(Policy.changeKind(of: record, in: file("App/C.swift", hunks: 1)) == nil)
        #expect(Policy.changeKind(of: nil, in: file("App/A.swift", hunks: 1)) == nil)
    }

    // MARK: - Slévání sad

    /// Pozdější hlášení přepíše dřívější a **pořadí drží to první**: uložený soubor se má dát číst
    /// očima ve stejném pořadí, v jakém stojí diff.
    @Test("Slévání přepisuje na místě, nepřidává druhý řádek")
    func mergingOverwritesInPlace() {
        let existing = [
            HunkAnnotation(file: "a.swift", hunk: 1, why: "první", source: nil),
            HunkAnnotation(file: "a.swift", hunk: 2, why: "druhá", source: nil),
        ]
        let batch = [
            HunkAnnotation(file: "a.swift", hunk: 1, why: "opravená", source: "z commitu x"),
            HunkAnnotation(file: "b.swift", hunk: 1, why: "nová", source: nil),
        ]

        let merged = Policy.mergedHunkAnnotations(existing, reporting: batch)

        #expect(merged.map(\.why) == ["opravená", "druhá", "nová"])
        #expect(merged.first?.source == "z commitu x")
    }

    /// **Klíčem hunku je dvojice `(soubor, index)`**, ne řetězec slepený dohromady: cesta může
    /// obsahovat cokoli včetně oddělovače, takže by `"\(file)#\(hunk)"` uměl srazit dvě různá
    /// místa do jednoho.
    @Test("Podobné cesty se neslijí do jednoho klíče")
    func doesNotCollideOnLookalikePaths() {
        let merged = Policy.mergedHunkAnnotations(
            [],
            reporting: [
                HunkAnnotation(file: "a#1", hunk: 2, why: "první", source: nil),
                HunkAnnotation(file: "a", hunk: 12, why: "druhá", source: nil),
            ]
        )

        #expect(merged.count == 2)
    }

    /// U souborů je klíčem **cesta**, protože druh je na soubor jeden.
    @Test("Druh změny se u téhož souboru přepíše")
    func mergesFileKindsByPath() {
        let merged = Policy.mergedFileAnnotations(
            [FileAnnotation(file: "a.swift", kind: .behaviour)],
            reporting: [
                FileAnnotation(file: "a.swift", kind: .refactor),
                FileAnnotation(file: "b.swift", kind: .test),
            ]
        )

        #expect(merged == [
            FileAnnotation(file: "a.swift", kind: .refactor),
            FileAnnotation(file: "b.swift", kind: .test),
        ])
    }

    // MARK: - Dráha v tabu Průběh

    /// Dráha z **uloženého** výsledku se kreslí jen pro dnešní hlavu — jinak by v tabu tvrdila,
    /// že se tenhle diff popsal.
    @Test("Dráha se z uloženého záznamu kreslí jen pro dnešní hlavu")
    func laneFollowsTheHead() {
        let record = stored(hunks: [
            HunkAnnotation(file: "a.swift", hunk: 1, why: "věta", source: nil)
        ])

        #expect(Policy.annotationLane(pass: nil, stored: record, head: "aaaa1111") != nil)
        #expect(Policy.annotationLane(pass: nil, stored: record, head: "bbbb2222") == nil)
        #expect(Policy.annotationLane(pass: nil, stored: nil, head: "aaaa1111") == nil)
    }

    /// **Dráha anotací nenese počet nálezů, a to je to tvrzení.** `reportedFindings` u ní zůstává
    /// `nil` navěky — jinak by se popis změn dřív nebo později začal číst jako „tolik toho našla“.
    @Test("Dráha anotací nikdy nenese počet nálezů")
    func theLaneNeverCarriesFindings() {
        let running = Policy.annotationLane(
            pass: AnnotationPass(worktree: nil, headSha: "aaaa1111", startedAt: Date(timeIntervalSince1970: 1)),
            stored: nil,
            head: "aaaa1111"
        )
        let finished = Policy.annotationLane(
            pass: nil,
            stored: stored(hunks: [HunkAnnotation(file: "a", hunk: 1, why: "v", source: nil)]),
            head: "aaaa1111"
        )

        #expect(running?.reportedFindings == nil)
        #expect(finished?.reportedFindings == nil)
        #expect(running?.kind == .annotations(hunks: nil, files: nil, dropped: 0))
        #expect(finished?.kind == .annotations(hunks: 1, files: 0, dropped: 0))
    }

    /// Běh má přednost před uloženým výsledkem: dokud session běží, je pravdou o tom PR ona.
    @Test("Běžící session přebije uložený výsledek")
    func aRunningPassWinsOverTheStoredResult() {
        var pass = AnnotationPass(worktree: nil, headSha: "aaaa1111", startedAt: Date(timeIntervalSince1970: 1))
        pass.record(.started(sessionID: "s2"))

        let lane = Policy.annotationLane(pass: pass, stored: stored(), head: "aaaa1111")

        #expect(lane?.state == .running)
        #expect(lane?.sessionID == "s2")
    }

    /// **Zahozené položky musí být vidět, a dráha je jediné místo, kde se to dá říct** — výpis
    /// kroků anotační dráha nemá, takže `droppedEntries` o tom mlčí. Bez té věty je anotace bez
    /// povinného pole k nerozeznání od hunku, který session schválně nepopsala.
    @Test("Zahozené položky se dostanou z běhu i z disku až do věty pod dráhou")
    func droppedItemsReachTheLaneText() {
        var pass = AnnotationPass(worktree: nil, headSha: "aaaa1111", startedAt: Date(timeIntervalSince1970: 1))
        pass.finish(
            AnnotationRun(
                hunks: [HunkAnnotation(file: "a.swift", hunk: 1, why: "v", source: nil)],
                files: [],
                answered: true,
                dropped: 2
            ),
            at: Date(timeIntervalSince1970: 2)
        )

        let fromRun = Policy.annotationLane(pass: pass, stored: nil, head: "aaaa1111")
        let fromDisk = Policy.annotationLane(
            pass: nil,
            stored: stored(hunks: [HunkAnnotation(file: "a.swift", hunk: 1, why: "v", source: nil)], dropped: 2),
            head: "aaaa1111"
        )

        #expect(fromRun?.kind == .annotations(hunks: 1, files: 0, dropped: 2))
        #expect(fromDisk?.kind == .annotations(hunks: 1, files: 0, dropped: 2))
        for lane in [fromRun, fromDisk] {
            let text = ReviewerLaneText.last(of: try! #require(lane)) ?? ""
            #expect(text.contains("2 položky se nepodařilo přečíst"), "chybí věta o zahozených: \(text)")
        }
    }

    /// **Bez zahozených se o nich nemluví** — „0 položek se nepodařilo přečíst“ je šum, který
    /// z běžné věty udělá hlášení o poruše.
    @Test("Bez zahozených položek věta o nich není")
    func noDropMeansNoSentence() {
        let lane = Policy.annotationLane(
            pass: nil,
            stored: stored(hunks: [HunkAnnotation(file: "a.swift", hunk: 1, why: "v", source: nil)]),
            head: "aaaa1111"
        )

        #expect(ReviewerLaneText.last(of: lane!)?.contains("nepodařilo přečíst") == false)
    }

    /// **Nepřečtená odpověď není prázdný seznam.** Doběhlá session bez odpovědi má v dráze `nil`,
    /// ne nulu — text pod dráhou z toho skládá jinou větu.
    @Test("Doběhlá session bez čitelné odpovědi má v dráze nil, ne nulu")
    func anUnreadableAnswerIsNotZero() {
        let unreadable = Policy.annotationLane(
            pass: nil,
            stored: stored(answered: false),
            head: "aaaa1111"
        )
        let empty = Policy.annotationLane(pass: nil, stored: stored(answered: true), head: "aaaa1111")

        #expect(unreadable?.kind == .annotations(hunks: nil, files: nil, dropped: 0))
        #expect(empty?.kind == .annotations(hunks: 0, files: 0, dropped: 0))
    }

    // MARK: - Tichý konec

    /// **Selhání, ze kterého nezbyl ani běh, musí dráhu vyrobit samo.** Bez téhle větve nezbyde po
    /// kliknutí v tabu `Průběh` nic — a prázdno je k nerozeznání od „neklikalo se“. Přesně tím se
    /// #524 poprvé projevil: tlačítko šlo zmáčknout a nestalo se nic.
    @Test("Selhání bez běhu i bez záznamu dráhu vyrobí")
    func aFailureAloneStillDrawsALane() {
        let lane = Policy.annotationLane(
            pass: nil,
            stored: nil,
            head: "aaaa1111",
            failure: "Popis změn se nespustil."
        )

        #expect(lane?.state == .failed(detail: "Popis změn se nespustil."))
        #expect(lane?.skill == Policy.annotationLaneName)
        // Ani tahle dráha nesmí nést počet nálezů — hranice mezi anotací a nálezem platí i tady.
        #expect(lane?.reportedFindings == nil)
        #expect(lane?.phases.allSatisfy { $0.state == .failed } == true)
    }

    /// Selhání je **poslední záchyt, ne přebíječ**: platný záznam ani běh se jím nepřekreslí.
    /// Věta z minula nad doběhlým popisem by tvrdila, že se to nepovedlo, i když se povedlo.
    @Test("Selhání nepřebije ani běh, ani platný záznam")
    func aFailureNeverOverridesTheRealThing() {
        var pass = AnnotationPass(worktree: nil, headSha: "aaaa1111", startedAt: Date(timeIntervalSince1970: 1))
        pass.record(.started(sessionID: "s3"))

        let running = Policy.annotationLane(pass: pass, stored: nil, head: "aaaa1111", failure: "stará věta")
        let recorded = Policy.annotationLane(pass: nil, stored: stored(), head: "aaaa1111", failure: "stará věta")

        #expect(running?.state == .running)
        #expect(recorded?.state == .finished)
    }

    /// Prázdná věta dráhu nevyrobí — dráha bez důvodu je to horší z obojího: zabírá místo
    /// a neřekne nic.
    @Test("Chybějící i prázdná věta dráhu nevyrobí", arguments: [nil, ""])
    func anEmptyFailureDrawsNothing(_ failure: String?) {
        #expect(Policy.annotationLane(pass: nil, stored: nil, head: "aaaa1111", failure: failure) == nil)
    }

    // MARK: - Ovladač v liště

    /// Tři stavy, ne dva — a **běh přebíjí selhání z minula**: nové spuštění starou větu zahazuje,
    /// takže dvojice „běží a k tomu selhalo“ znamená selhání z minula.
    @Test("Stav ovladače rozlišuje klid, běh a selhání")
    func theControlHasThreeStates() {
        #expect(Policy.annotationControl(isRunning: false, failure: nil) == .idle)
        #expect(Policy.annotationControl(isRunning: false, failure: "") == .idle)
        #expect(Policy.annotationControl(isRunning: false, failure: "spadlo") == .failed(detail: "spadlo"))
        #expect(Policy.annotationControl(isRunning: true, failure: nil) == .running)
        #expect(Policy.annotationControl(isRunning: true, failure: "spadlo") == .running)
    }
}
