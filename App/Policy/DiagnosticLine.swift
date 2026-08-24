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
    /// **Klid se po sekundách nezapisuje** (`nil`): úsek, ve kterém se nepřeložilo ani jedno tělo
    /// a nehořelo CPU, jde do minutového souhrnu (`diagnosticQuietLine`), ne na vlastní řádek.
    ///
    /// **Změna proti #391** (#412; do té doby rozhodovalo i „aspoň jedno kolo runloopu“). Změřeno
    /// nad skutečným záznamem z provozu (985 754 B, 11,5 h, tři sezení): takových úseků bylo
    /// **9 279 z 10 077**, tedy 89 % hlavních řádků a 60 % objemu souboru — a **ani k jednomu**
    /// z nich nebyla příloha o grafu, takže se folding nemá čím dotknout toho, na co je záznam
    /// (příloha se váže na hlavní řádek úseku). Nečinné okno má 1–4 kola a jednotky milisekund CPU
    /// za sekundu, takže „kolo runloopu“ neodlišovalo práci od spánku; odlišuje ji **průchod tělem
    /// nebo hoření**. Kola se přitom neztrácejí — sečtená jsou v tom souhrnu.
    ///
    /// **Do „klidu“ ale nepatří hořící CPU** (#391, změna proti #386). Zaseknuté kolo z #361 nemá ani
    /// kola runloopu, ani průchody tělem — hlavní vlákno se z transakce nevrátí, takže obojí je
    /// nula a přesně ten stav by se se starým pravidlem nezapsal. Rozhoduje proto ještě CPU:
    /// nad `diagnosticBurnFloor` se řádek napíše, i když je zbytek nulový. Nečinná aplikace tím nic
    /// navíc nepíše — spící hlavní vlákno CPU nespotřebuje.
    ///
    /// **Věta o runloopu tvrdí právě to, co je změřené, a nic víc.** Hoření s nulou kol znamená, že
    /// hlavní vlákno za ten úsek runloop ani jednou nepustilo ke slovu — což je signatura #361, ale
    /// **jeden takový řádek ještě není záchvat**: takhle vypadá i drahá práce na hlavním vlákně
    /// (rozbor velkého diffu). Záchvat se pozná z toho, že takových řádků jde **za sebou desítky**,
    /// a to je z časů v souboru vidět. Proto tam nestojí „zaseklo se“.
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
        let burns = cpu >= elapsed * diagnosticBurnFloor
        guard !passes.isEmpty || burns else { return nil }
        var head = String(
            format: "%@ za %.2f s: %d kol runloopu, %.3f s CPU",
            stamp(of: moment, in: zone),
            elapsed,
            cycles,
            cpu
        )
        // Hoří a runloop nedošel ani jednou do čekání — to je ta signatura z #361 a v souboru má
        // být vidět slovy, ne jako nula, kterou musí někdo umět přečíst.
        if burns, cycles == 0 { head += " — HLAVNÍ VLÁKNO NEPUSTILO RUNLOOP KE SLOVU" }
        guard !passes.isEmpty else { return head }
        let sorted = passes.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
        return head + ", body: " + sorted.map { "\($0.key)=\($0.value)" }.joined(separator: " ")
    }

    /// Od kolika CPU se úsek považuje za práci, i když v něm není ani kolo runloopu, ani průchod
    /// tělem — **podíl z uplynulého času**, ne absolutní sekundy, aby to nezáviselo na cadenci
    /// zapisovacího vlákna.
    ///
    /// 5 % je nízko schválně: hledá se hoření na 99 %, kdežto nečinné okno stojí jednotky
    /// milisekund za sekundu (změřeno u #386: 1–4 kola a 5–14 ms), takže mezi tím je dva řády
    /// místa a hranice nemusí být přesná. Vyjmenovaná ale být musí, jinak by se soubor plnil i nad
    /// aplikací, která spí.
    static let diagnosticBurnFloor = 0.05

    /// Jak dlouhý klid se sráží do jednoho souhrnu (#412).
    ///
    /// Minuta je z měření na skutečném záznamu: klidných úseků je 89 % hlavních řádků, takže
    /// minutový souhrn z nich udělá **šedesátinu** objemu — a sezení se tím vejde do stropu na
    /// týdny místo hodin. Delší okno už nic podstatného nešetří a zhoršuje to jediné, co souhrn
    /// umí říct: **kdy** ten klid byl.
    static let diagnosticQuietInterval: TimeInterval = 60

    /// Souhrn klidu za `diagnosticQuietInterval` (#412) — **místo** řádků po sekundách, ne k nim.
    ///
    /// Souhrn se píše vždycky, i když v něm nic zajímavého není, a je to schválně: **mezera
    /// v záznamu se nesmí dát zaměnit s vypnutou diagnostikou.** Do #412 mezera znamenala „nic se
    /// nedělo“, což je informace jen tehdy, když se dá věřit, že nástroj běžel — a právě to se
    /// u #412 ukázalo jako nepravda (soubor narazil na strop a dalších 42 hodin mlčel z úplně
    /// jiného důvodu). Souhrn je tedy zároveň puls: dokud přichází, záznam žije.
    ///
    /// **`bez kola runloopu` je jediné, co souhrn říká navíc** proti sečtení řádků: úsek s nulou
    /// kol a bez hoření je hlavní vlákno, které se zaseklo, ale nespaluje CPU (typicky blokující
    /// I/O) — a to jsou úseky, které do #412 v záznamu nebyly vůbec. Netvrdí to „záchvat“, stejně
    /// jako věta o runloopu v `diagnosticLine`; je to počet, ne verdikt. Nad skutečným záznamem
    /// z provozu vyšel **nula z 9 279**, takže to není mez, která by se plnila sama.
    static func diagnosticQuietLine(
        at moment: Date,
        in zone: TimeZone,
        over elapsed: TimeInterval,
        sections: Int,
        cycles: Int,
        cpu: TimeInterval,
        stalled: Int
    ) -> String {
        String(
            format: "%@ za %.2f s klid: %d úseků, %d kol runloopu, %.3f s CPU, %d bez kola runloopu",
            stamp(of: moment, in: zone),
            elapsed,
            sections,
            cycles,
            cpu,
            stalled
        )
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

    /// Věta o tom, jestli se do grafu vůbec dá sáhnout — píše se **do souboru** hned za hlavičku
    /// sezení (#361).
    ///
    /// Bez ní by „graf nic neřekl“ a „graf nejde otevřít“ splynulo v tichu, což je u privátního
    /// API ta nejpravděpodobnější porucha: příští systém tu funkci přejmenuje a z záznamu prostě
    /// zmizí řádky o zásobníku, aniž by kdokoli poznal proč.
    static func diagnosticGraphLine(at moment: Date, in zone: TimeZone, available: Bool) -> String {
        let state = available
            ? "evaluační zásobník AttributeGraphu k dispozici"
            : "evaluační zásobník AttributeGraphu NEJDE otevřít — řádky „zásobník“ v záznamu nebudou"
        return "\(stamp(of: moment, in: zone)) \(state)"
    }

    /// Razítko na začátku každého řádku. **Internal, ne `private`**: od #412 ho skládají i řádky
    /// o rotaci záznamu (`DiagnosticsArchiving.swift`) a dvě různá razítka v jednom souboru jsou
    /// zrovna ta věc, kterou u čtení nikdo nečeká.
    static func stamp(of moment: Date, in zone: TimeZone) -> String {
        moment.formatted(Date.ISO8601FormatStyle(timeZone: zone))
    }
}
