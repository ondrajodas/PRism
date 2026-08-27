import CoreGraphics

extension Policy {
    /// Pás kolem výřezu, ve kterém je blok kódu **nasazený** (#469).
    ///
    /// Od #469 nekreslí diff líný seznam, ale **pevný `VStack`**. Důvod je tvrdý: `LazyVStack`
    /// zapisuje při umisťování položek do grafu, ze kterého sám čte, a to kolo se nemá kde
    /// zastavit — u osy konverzace to vyřešilo #361 a kolo se **přestěhovalo do diffu**. Pevný
    /// stack `LazySubview*` atributy do grafu nedostane vůbec.
    ///
    /// **Sám o sobě by ale pevný stack diff položil**, a je to změřené (`DiffShapeProbe`, Debug,
    /// okno 1200×800, projetí 150 × 40 pt, dvě série A/B/A/B):
    ///
    /// | řádků | `LazyVStack` | `VStack` se všemi bloky | `VStack` bez bloků |
    /// |---|---|---|---|
    /// | 500 | 0,60 / 0,61 s | 3,98 / 4,21 s | **0,20 / 0,21 s** |
    /// | 6000 | 0,69 / 0,55 s | 21,19 / 20,25 s | **0,19 / 0,19 s** |
    ///
    /// Čtou se z toho dvě věci. **Cena projíždění roste s počtem nasazených `NSTextView`, ne
    /// s počtem prvků v seznamu**: pevný stack, ve kterém jsou řádky jen rezervovanou výškou, je
    /// v počtu řádků **plochý** a **třikrát levnější než líný seznam**. A `updateNSView` se při tom
    /// gestu nevolá ani jednou (počitadla z #393 zůstala na 20 / 108), takže ta cena není v našem
    /// kódu — je v tom, že v dokumentu scroll view visí stovka textových views.
    ///
    /// Laznost se tedy nezahodila, jen **přestěhovala z rozvržení do jednoho rozhodnutí**: v pásu
    /// je blok nasazený, mimo něj zbyde `Color.clear` s naposledy změřenou výškou.
    ///
    /// **Pás je kvantovaný na násobky výřezu, a to je jeho druhá polovina.** Kdyby se počítal
    /// z okamžité polohy, měnil by se při každém otočení kolečka — a protože ho čte **každý** blok
    /// v diffu (`DiffViewport.band`), znamenalo by to přeložit při každém snímku celý seznam. Takhle
    /// se mění jednou za projetý výřez a mezi tím je pás **nejmíň o výřez širší** na každou stranu,
    /// takže se blok nasadí dřív, než na něj kdokoli může vidět.
    ///
    /// - Parameter visible: viditelná část obsahu (`ScrollGeometry.visibleRect`).
    static func mountBand(visible: CGRect) -> ClosedRange<Double> {
        let step = max(visible.height, minimumMountingMargin)
        // **Zaokrouhluje se každý konec zvlášť**, ne jeden a šířka od něj: výřez na kroky
        // zarovnaný není, takže od jednoho konce by rezerva na druhé straně vyšla o půl kroku
        // menší — a rezerva je to jediné, co pás slibuje.
        let top = ((visible.minY / step).rounded(.down) - 1) * step
        let bottom = ((visible.maxY / step).rounded(.up) + 1) * step
        return top...max(bottom, top)
    }

    /// Nejmenší krok pásu. Pojistka pro nízké okno — v pruhu o výšce dvou řádků by pás z výšky
    /// výřezu znamenal, že se bloky nasazují a odpojují při každém otočení kolečka.
    static let minimumMountingMargin = 400.0

    /// Je blok uvnitř pásu? `nil` (ještě se nikdy nekreslil, takže se o jeho výšce nic neví)
    /// znamená **nasadit** — prázdné místo je horší odpověď než blok navíc.
    static func isBlockMounted(_ block: ClosedRange<Double>?, band: ClosedRange<Double>) -> Bool {
        guard let block else { return true }
        return band.overlaps(block)
    }

    /// Která hlavička souboru se drží u horní hrany výřezu a o kolik je vysunutá (#469).
    ///
    /// Do #469 to dělal `LazyVStack(pinnedViews: [.sectionHeaders])`. Pevný stack ukotvené
    /// hlavičky neumí, a **zahodit je nešlo**: v návrhu je `.fhead { position: sticky; top: 0 }`,
    /// takže je to vzhled, ne detail implementace.
    ///
    /// **Kreslí se jedna hlavička navíc přes výřez, ne posun u každé.** První podoba posouvala
    /// každou hlavičku podle jejího vlastního rámečku ve výřezu; stálo to 0,83 s CPU na 24
    /// souborech (`DiffShapeProbe`, ablace `VStack bez bloků` se ukotvením a bez něj), protože se
    /// při každém snímku počítal rámeček **každého** souboru. Takhle je to jedno rozhodnutí a jedna
    /// hlavička.
    ///
    /// Chová se to jako `position: sticky` doslova: hlavička stojí u horní hrany, a když dojde
    /// konec souboru, **vysune se s ním** — hlavička dalšího souboru ji vytlačí místo aby ji
    /// překryla.
    ///
    /// - Parameters:
    ///   - files: rozsahy souborů v souřadnicích obsahu, v pořadí, jak jsou pod sebou.
    ///   - top: horní hrana výřezu v souřadnicích obsahu.
    ///   - headerHeight: výška hlavičky.
    /// - Returns: index souboru a posun (nula, nebo záporné číslo, když se hlavička vysunuje);
    ///   `nil`, když se u horní hrany nemá držet nic — tedy nad prvním souborem a dokud se
    ///   o rozsazích nic neví.
    static func pinnedFileHeader(
        files: [ClosedRange<Double>],
        top: Double,
        headerHeight: Double
    ) -> (index: Int, offset: Double)? {
        // **Poslední soubor, který začal nad hranou** — ne první, který ji protíná: mezi soubory
        // není mezera, takže hranu protíná právě jeden, ale hledá se od konce, aby to platilo
        // i na poslední řádce obsahu.
        guard let index = files.lastIndex(where: { $0.lowerBound <= top }) else { return nil }
        guard headerHeight > 0 else { return (index, 0) }
        return (index, min(0, files[index].upperBound - headerHeight - top))
    }
}
