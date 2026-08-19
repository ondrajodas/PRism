import Foundation

extension Policy {
    /// Jeden řádek záznamu diagnostiky kreslení (#361). `nil` = **není co hlásit**, řádek se
    /// nezapíše.
    ///
    /// **Proč je to čistá funkce a ne `String(format:)` uvnitř diagnostiky.** Řádek je jediné, co
    /// z ní zbyde — přijde jako soubor v příloze a rozhoduje se podle něj, kde se hledá dál. Takže
    /// na něm musí být pořád totéž a ve stejném pořadí; a to se dá otestovat jedině tehdy, když
    /// skládání nezávisí na hodinách, na souboru ani na runloopu.
    ///
    /// **Nula se nezapisuje** (`nil`): mezera v záznamu znamená „aplikace nic nedělala“, což je
    /// informace. Kdyby se psal řádek každou sekundu, hořící okno by se v tichých řádcích utopilo
    /// a soubor by rostl i nad nečinnou aplikací.
    ///
    /// **Průchody těla se řadí podle počtu, ne podle jména.** Hledá se ten typ, který se překresluje
    /// nejvíc; abecedně by první bylo to, co je zrovna vidět. Při shodě rozhoduje jméno, ať je řádek
    /// stejný při každém běhu — bez toho by se dva soubory nedaly srovnat.
    ///
    /// **Pásmo se předává** (`zone`), nebere se z `TimeZone.current` uvnitř: jinak by se ta jediná
    /// věc, na které záznam stojí — kdy to bylo —, nedala v testu napsat literálem. V aplikaci je to
    /// místní čas, aby šel spárovat s `sample`m ze stejné chvíle.
    static func diagnosticLine(
        at moment: Date,
        in zone: TimeZone,
        over elapsed: TimeInterval,
        cycles: Int,
        cpu: TimeInterval,
        passes: [String: Int]
    ) -> String? {
        guard cycles > 0 || !passes.isEmpty else { return nil }
        let head = String(
            format: "%@ za %.2f s: %d kol runloopu, %.3f s CPU",
            stamp(of: moment, in: zone),
            elapsed,
            cycles,
            cpu
        )
        guard !passes.isEmpty else { return head }
        let sorted = passes.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
        return head + ", body: " + sorted.map { "\($0.key)=\($0.value)" }.joined(separator: " ")
    }

    /// Věta, kterou diagnostika **uzavře** soubor, až narazí na strop (#361).
    ///
    /// Strop musí být, jinak je to únik místa s odkladem — a jeho dosažení se musí **napsat do
    /// souboru**: záznam, který prostě přestane, se nedá odlišit od aplikace, která přestala hořet.
    static func diagnosticLimitLine(at moment: Date, in zone: TimeZone, bytes: Int) -> String {
        "\(stamp(of: moment, in: zone)) strop \(bytes) B vyčerpán, dál se nezapisuje"
            + " — restartuj aplikaci"
    }

    /// Hlavička sezení: čí je to instance, jaké má PID a čím se diagnostika vypíná.
    ///
    /// Na prvním řádku souboru schválně: záznam se posílá dál a bez téhle věty se z něj nepozná,
    /// jestli jde o zapnutou diagnostiku, nebo o běžný provoz. **PID je tam kvůli `sample`u** —
    /// druhá polovina hledání u #361 je vzorek ze živého procesu a bez čísla se k němu ta správná
    /// instance nedohledá. **Jméno bundlu kvůli slotům** (#228): `PRism-a` píše do vlastní cache,
    /// takže je potřeba vidět, který PRism to byl.
    ///
    /// **Verze v tom schválně není.** `MARKETING_VERSION` se v tomhle repu neudržuje (pořád je
    /// `0.1`), takže by to byl řádek, který vypadá jako fakt a lže; verze se pozná z tagu, který
    /// se ten den vydal.
    static func diagnosticHeaderLine(
        at moment: Date,
        in zone: TimeZone,
        bundle: String,
        pid: Int32
    ) -> String {
        "\(stamp(of: moment, in: zone)) diagnostika kreslení ZAPNUTÁ (PRISM_DIAGNOSE=1),"
            + " \(bundle) pid \(pid) — vypne se restartem bez toho přepínače"
    }

    private static func stamp(of moment: Date, in zone: TimeZone) -> String {
        moment.formatted(Date.ISO8601FormatStyle(timeZone: zone))
    }
}
