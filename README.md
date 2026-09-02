# PRism

Nativní macOS aplikace, která hlídá GitHub pull requesty, u kterých jsem požádán o
review, spouští na ně review skilly Claude Code a nálezy zobrazuje vedle diffu.

Aplikace je **orchestrátor a prohlížeč** — nemá vlastní review logiku. Veškerá analýza
žije ve skillech Claude Code; aplikace rozhoduje, kdy spustit který skill a kde, odchytí
strukturovaný výstup a vykreslí ho.

Hranol rozloží jeden paprsek na spektrum. Tahle aplikace dělá totéž s pull requestem —
pustí na něj několik nezávislých reviewerů a jejich nálezy schválně neslévá do jednoho
názoru.

> **Na GitHub vede jediná cesta a otevírá ji jen člověk.** Aplikace umí odeslat review,
> odpovědět do vlákna, napsat komentář pod PR a na **vlastním** PR nastavit labely, vyžádat
> review, založit label, který repozitář ještě nezná, mergnout ho a **přepnout ho z draftu na
> Ready for review**, ale výhradně přes jeden modul a jen na
> výslovný pokyn — review navíc proti commitu,
> který jsi opravdu viděl. Co tudy **nejde**: approve mimo review, zavření PR, milník,
> **smazání labelu** a **návrat do draftu**. Nic se neodesílá samo — ani návrh verdiktu, ani
> reviewer.
>
> **A jedině tam, kde se to povolilo.** Odesílání je ve výchozím stavu vypnuté — zapíná se
> v nastavení, globálně nebo u jednoho repa. Dokud si o to někdo výslovně neřekne, neodejde
> nikam nic.

## Stav

**Aplikace dělá to, kvůli čemu vznikla: pustí review na moje skutečné PR a ukáže nálezy.**

Okno má **vlastní hlavičku se záložkami** (#180): vlevo semafor, vedle něj domácí záložka
`Přehled` a otevřená review, vpravo kapsle `⌘K`, novinky, obnovení a nastavení. Systémová
titulková lišta je schovaná, takže okno se tahá za tuhle hlavičku. Seznam PR není trvalý sloupec —
je obsahem domácí záložky, takže diff dostane celou šířku okna. Otevřené review zůstává otevřené
a tečka u záložky nese jeho stav; u běžícího se točí prstýnek, u rozdělaného je pero. **Zavření
záložky nic nezahodí.**

**Dokud se aplikace ptá GitHubu, točí se prstýnek i v tlačítku obnovení** (#442) — týž, jaký na
záložce znamená běžící review, takže „pracuje se“ má v okně jeden tvar. Platí to **i pro
automatický tik**: je to stav aplikace, ne odezva na tlačítko. Po tu dobu tlačítko klik nebere
(rozhoduje o tom `Policy.refreshControl`, ze kterého si podmínku bere i `AppStore.refresh()`,
takže druhý dotaz nepustí ani paleta ⌘K ani `⌘R`), rozměr tlačítka se přitom nemění (27 × 25), aby
hlavička neposkočila. Do té doby bylo obnovování vidět **jen na dashboardu** (`ptám se…`
v pravém horním koutu), tedy jen z domácí záložky — kdo byl v záložce pull requestu, četl klik
bez odezvy jako klik, který nezabral.

**Pruhem se přepíná `⌃Tab` a `⌃⇧Tab`** (#245) — dokola a **včetně domácí záložky**, protože se na
ni chodí nejčastěji (je za ní fronta) a bez ní by zkratka nad jediným otevřeným PR nedělala nic.
Dočtenou záložku zavře **`⌃W`** (#441).
Pořadí je pořadí pruhu, ne pořadí použití. Funguje to i **s kurzorem v rozepsaném review**:
změřeno, že se do textu nevloží tabulátor ani nepřeskočí fokus — key equivalent tlačítka se
vyhodnocuje dřív, než se klávesa dostane k textovému editoru. Zkratky stojí v nápovědě u domácí
záložky, protože jinak by po nich v okně nebyla žádná stopa.

Barvy si okno drží samo (`Palette`), včetně fialového akcentu — systémová šedá je neutrální,
kdežto tenhle návrh stojí na neutrálech posunutých do modrofialové. **Od #277 z ní jdou i barvy
diffu**: pozadí přidaného a odebraného řádku byla do té doby systémová zelená a červená s krytím,
takže se v tmavém režimu mísila směrem k černé a blok změny vypadal jako tmavý obdélník. Teď jsou to
vyčíslené hodnoty z návrhu a řádky se v tmavém režimu odlišují o třetinu víc (ΔE 16,0 → 21,8), aniž
by se zhoršila čitelnost obarveného kódu. **Od #298 z ní jde i „klikni sem“**: akce u nálezu byly do
té doby dvě různé barvy — fialové tlačítko v bublině u kódu (#283) a systémově modrý odkaz v tabulce
nálezů, protože `.buttonStyle(.link)` si akcent okna nebere. Teď je barva jedna a **tvar zůstává
různý**, jak ho má návrh: v bublině plocha, v tabulce holý text, který se opakuje na každém řádku.
**Od #432 z palety jde celá sémantická škála** (`ok`, `find`, `crit`, `stale`): systémová zelená
a červená je navržená jako výplň ovládacího prvku s bílým textem, kdežto tady je to text na tlumeném
podkladu — čtyři kapsle kvůli tomu měly ve světlém režimu kontrast 1,63 až 2,70 a systémová oranžová
1,85; po převodu je nejnižší hodnota 3,05. Ze systému zůstává `.secondary` („nemám co říct“),
purpurová u mergnutého PR a modrá u přejmenovaného souboru.
**Od #309 má akcent dvojici**: `mint`. Akcent je to, co se nabízí udělat nebo co zrovna běží, mint
to, co se jen konstatuje — odznak shody `2×`, `✓ v mém review`, počet rozdělaných review ve stavovém
řádku, odmítnuté review. Do té doby měly stavy barvu akcí, a osm z nich dokonce systémovou modrou:
`.tint()` z kořene okna se na `Color.accentColor` nevztahuje, takže tam, kde ho někdo použil, byl
akcent okna jen zamýšlený.

Obsahem domácí záložky je **dashboard** (#181), ne prázdné „Vyber pull request“. Odpovídá na čtyři
otázky, na které se do té doby muselo hledat po okně: **kolik toho čeká**, **co z toho blokuje**,
**co mám venku vlastního** (#331) a **co mám rozdělané** — plus co mě dneska stálo review, i s grafem
za posledních sedm dní. Pod kartami jsou **dvě fronty pod sebou** (#331): `Čeká na moje review`
seřazené **podle závažnosti**, ne podle času, a pod ní `Moje PR`; vedle nich rozpad nálezů podle
revieweera za týden a blok `Co teď` s akcemi: pustit review na všechno, co neběželo (ptá se na
potvrzení — je to jediné kliknutí v aplikaci, které utratí víc než jednu session), nebo se vrátit
k nejstaršímu rozdělanému review. **Pod `Co teď` je od #443 třetí blok pravého sloupce, `Dění`** —
pět nejnovějších řádků toho, co se na pull requestech stalo, a cesta do celé sekce. Nic se pro to
nedotahuje; všechna ta čísla už v aplikaci byla, jen roztroušená.

**Karta `Čeká na mě` a blok `Čeká na moje review` počítají od #332 jen cizí PR**, karta a blok
`Moje PR` jen vlastní; `Rozdělaná review` počítá dál obojí. Podrobně je to níž, u sekce `Moje PR`.

**Blok kreslí od #371 nejvýš pět řádků** a pod nimi patku se zbytkem — `Zobrazit všech 13 ve frontě
+8 →`, kterou stačí kliknout, aby se okno přepnulo do plné fronty. Bez stropu roste blok s frontou
a ten druhý skončí pod hranou okna: u třinácti cizích PR o půl obrazovky, před #332 (kdy se do fronty
počítala i vlastní) o celou. **Karta nad blokem přitom počítá dál celou frontu** — `Čeká na mě`
ukazuje 13, i když je pod ní pět řádků; strop je o kresbě, ne o množině. Blok pod stropem patku nemá,
protože „zobrazit všechny“ nad seznamem, který je celý vidět, je akce, po které se nic nezmění.

**Čtyři karty z pěti vedou do své sekce** (#371): `Čeká na mě` a `Blokuje` do `Fronty`, `Moje PR`
a `Rozdělaná review` do svých. Pozná se to šipkou vpravo nahoře a rámečkem v akcentu na hover.
`Blokuje` u toho zapne filtr **„jen blokující“** — bez něj by skákala na totéž místo jako `Čeká na
mě` — a ostatní volby filtru nechá, jak si je člověk nastavil. **`Dneska stálo` klikatelná není**:
nemá kam vést, a karta, po které se nic nestane, je lež o tom, co okno umí; nemá proto ani ukazováček
kurzoru, ani hover stav.

**Karta `Ve frontě` se od #331 jmenuje `Čeká na mě`** a přibyla vedle ní `Moje PR`. Staré jméno
mluvilo o dvou různých druzích práce naráz: u cizího PR je moje úloha *přečíst a odpovědět*,
u vlastního *opravit a pushnout*. Velké číslo na kartě `Moje PR` je **kolik jich mám otevřených**,
věta pod ním **na kolika z nich leží tah** — šest PR, ze kterých pět čeká na CI, není šest věcí
k práci. Když mezi zdroji chybí `author:@me is:open`, řekne to ta věta místo nuly: nula bez zdroje
je údaj o nastavení, ne o mojí práci. Akcentový proužek nahoře se z karty `Rozdělaná review`
přestěhoval sem, jak to má návrh — dva proužky vedle sebe by přestaly znamenat, která karta je ta
o mně.

V pravém horním koutu stojí, kdy se seznam naposledy načetl a **kolik zbývá do příštího dotazu** —
`poslední tik 09:41 · za 43s znovu` (#237). Poslední tik je hodina, protože je to bod
v minulosti; příští je odpočet, protože otázka u něj zní „jak dlouho ještě“ — a při rate limitu,
kde čekání roste až na patnáct minut, je to celý obsah té informace. Delší čekání se píše ve dvou
jednotkách (`za 12min 29s znovu`). Zatímco se aplikace ptá, je tam místo čísla `ptám se…`.

**Mezera mezi číslem a jednotkou tam schválně není** (#260) — je to vědomá odchylka od české
typografie, kterou si aplikace platí vlastním formátováním odpočtu, protože systémový formát
mezeru v české locale má a nejde z něj vyndat.

Napravo v hlavičce stojí **`⌘K`** — command palette (#184), jedno pole nad nálezy, soubory
otevřeného PR, cizími i vlastními pull requesty (#336) a akcemi. Popsaná je níž.

Po startu si ověří, že má `gh`, `git` i `claude` a že je `gh` přihlášený — jinak řekne, co
chybí a čím se to spraví. Pak se otevře seznam pull requestů napříč repozitáři, který se
sám obnovuje. **Řádek začíná titulkem** (#172) a souřadnice — `repo #číslo · autor · čas
poslední změny` — stojí pod ním: seznam míchá repozitáře, ale otázka „co to je“ přijde dřív než
„odkud to je“. Stav review nese **barevná hrana řádku**, takže se fronta dá přejet očima, a vedle
odznaku je **proužek s podílem reviewerů** — z něj je poznat, jestli nálezy hlásí jeden reviewer,
nebo se na nich shodli dva. Blokující nález má vlastní barvu i text (`3 nálezy · 1 blokuje`); do
#172 se nedal od tří kosmetických odlišit vůbec. Při
výpadku sítě zůstanou poslední známá data a nad seznamem se objeví pruh, že nejsou
aktuální; při rate limitu pruh říká, kdy to zkusí znovu.

**Seznam se dá zúžit filtrem** (#117) — ikona vpravo v liště nad frontou, a jen tam: nad
rozdělanými review není co zúžit. Odškrtávají se v ní repozitáře a autoři (uvnitř osy „nebo“, mezi
osami „a“: dvě repa znamenají obojí, repo + autor jeho PR v tom repu), a od #371 je nad nimi třetí
osa **`Jen s blokujícím nálezem`** — tu zapíná i karta `Blokuje` na dashboardu, takže musí být vidět
a vypnutelná tam, kde se filtr nastavuje. U každé položky je **počet PR, kterých se týká** (#199), takže je před kliknutím vidět, co
se za ní schová; počítá se z **plného** seznamu, takže se odškrtáváním nemění — jinak by číslo
říkalo něco o pohledu místo o tom, co zapnutí položky udělá. Že je filtr zapnutý a kolik schovává,
je vidět na ikoně **bez otevírání nabídky**, protože skrytý filtr je způsob, jak přijít o review;
a když schová všechno, řekne to a nabídne se vypnout — zelené „Žádné PR k review“ by nad zapnutým
filtrem tvrdilo opak pravdy.

Filtr je **pohled, ne seznam**: nic se tím nepřestane stahovat, nezahodí se diffy ani rozdělaná
review, běžící review běží dál, automat plánuje dál a okno nastavení pořád vidí i schované repo.
**Nepřežije restart** — je to jediné, co umí PR schovat úplně, a zmizelý PR vypadá jako vyřízený.
Na trvalé schování jsou **zdroje** v nastavení (search dotaz umí i `-author:`), což je změna toho, co
se stahuje.

**Vlastní PR jsou druhá fronta, ne filtr v té první** (#331). V railu k tomu přibyla sekce
`Moje PR` mezi `Frontou` a `Rozdělanými`: šipka nahoru vedle vaničky, protože dolů přichází, co mám
zrevidovat, a nahoru jde, co posílám ven. Je to **tentýž seznam nad druhou množinou** — rozřazuje se
podle **autora** (`Policy.ownership`, #330), ne podle zdroje, ze kterého PR přišel, protože jeden PR
umí splňovat víc search dotazů naráz. Řádek vlastního PR má vpravo **`Prompt →`** místo verdiktu:
verdikt na vlastní PR GitHub odmítá, takže jediné, co s ním okno umí udělat, je složit z nálezů
a konverzace zadání pro agenta.

**`Prompt →` otevře PR a v něm panel `Zadání`** (#333), text neskládá. Je to schválně: konverzace se
tahá při zobrazení PR, takže složit markdown rovnou ze seznamu by dalo zadání **bez vláken
a komentářů pod PR** — tedy bez většiny toho, co se předává. Tlačítko proto taky není nikdy zakázané:
navigace udělá vždycky něco, kdežto sazba textu má vlastní bránu v panelu.

**Odznak u sekce počítá to, co čeká na tah**, ne otevřené PR: PR s nezpracovaným nálezem nebo
s nevyřešeným cizím vláknem. Nula se nekreslí (prázdno je dobrá zpráva) a `nil` — tedy nenačteno —
taky ne. Vlákna se přitom počítají **jen z konverzací, které se stáhly**, protože ty se tahají při
výběru řádku, ne při každém tiku; číslo je tedy spodní hranice a doplní ho #335.

Prázdná sekce má **tři různé věty**, ne jednu. Když mezi zdroji chybí `author:@me is:open`, řekne,
že se vlastní PR nesledují, a nabídne nastavení — nenastavená aplikace nesmí vypadat jako uklizený
stůl. Když se nepodařilo zjistit login (`gh api user`), řekne, že neví, kdo jsi, protože bez loginu
je podle autora všechno cizí. A teprve když je zdroj i login, znamená prázdno „nic vlastního
otevřeného“.

**Fronta jsou od #332 cizí PR, ne všechno, co přišlo.** Do té doby se vlastní PR počítal na obě
strany naráz: karta `Čeká na mě` tvrdila 32 (13 cizích a 19 vlastních) a tentýž řádek byl
na dashboardu vidět v obou blocích. Rozřazení podle autora je tedy vidět všude, kde se o **frontě**
něco tvrdí — v seznamu sekce `Fronta` a jejím odznaku, na kartách `Čeká na mě` a `Blokuje`, v bloku
`Čeká na moje review`, v souhrnu ve stavovém řádku, v hromadné akci `Pustit review na vše, co
neběželo` a v notifikacích. Blokující nález na vlastním PR se do karty `Blokuje` **nepočítá**: je to
seznam toho, co mám opravit, ne toho, co mi stojí v cestě. Věta pod pozdravem je proto od #332
**dvojitá** — „Pět pull requestů čeká na review, jeden z nich blokuje. Na 2 vlastních je co předat
agentovi.“ —, jak ji kreslí návrh; dřív by mluvila o týchž pull requestech dvakrát.

**Co se naopak řídí celým seznamem**: úklid cache, eviction a úklid nálezů (klon vlastního PR
zabírá místo stejně jako cizí, takže navázat je na frontu znamená cache, která tiše roste), okno
nastavení se seznamem repozitářů, nabídka filtru, sekce `Rozdělaná` a karta `Rozdělaná review`
(draft je ručně psaná práce a od #333 na vlastním PR nevznikne — ten z doby předtím se nesmí
ztratit) a klik na notifikaci.

**Automat vlastní PR nepustí nikdy, a není to volba** (#332) — ani při globálním
`mode: automatic`, ani když si o automat řekne repo svým nastavením. Přepínač se zvažoval
a **zamítl**: automat existuje kvůli čekání (u vlastního PR není na co čekat, review si na něm
pouštím, když vím, že jsem dopsal), vlastní PR se mění pod rukama (každý push je nová hlava, tedy
nálezy proti kódu, který za deset minut nebude) a jediné, co by přepínač přinesl, je způsob, jak si
to zapnout omylem. Denní strop `autoRunsPerDay` zůstává **jeden společný** — dvě poloviny limitu
jsou dohromady dvojnásobek — a po #332 ho čerpají jedině cizí PR. **Ruční spuštění na vlastním PR
jde dál**, i tlačítkem na řádku: pravidlo se týká automatu a hromadné akce, ne toho, když si
o review řeknu.

**Notifikace o review jsou cesta pro review requesty**, takže o vlastním PR nedají vědět: „Nový PR
k review“ o pull requestu, který jsem sám otevřel, je hláška o vlastním pushi, a výsledek review,
které jsem si sám spustil, je v okně vidět na řádku i v panelu.

**O vlastních PR se hlásí jedna věc, a je to ta opačná** (#335): že se na nich ozval **někdo jiný** —
kolega odpověděl do vlákna, Copilot dopsal review. Aplikace se proto na diskuzi vlastních PR ptá sama
na pozadí, a je to **záměrně skoupé**: konverzace se tahá jedině u PR, kde se `updatedAt` ze seznamu
posunul (tedy kde se doopravdy něco stalo), nejvýš **u tří PR za pět minut** a jedině po úspěšném tiku
pollingu — takže se to vejde do jeho backoffu a při rate limitu se nekouká vůbec. Na klidný den to
znamená **nula dotazů navíc**. Co v diskuzi přibylo, nese i řádek seznamu: `2 nové komentáře od minule`
místo autora a času. **Spadlé CI se nehlídá** — je to druhý dotaz na PR a jiná událost, takže na to
patří vlastní text i vlastní přepínač.

## Dění — co proletělo jako notifikace, zůstane

Notifikace **nemá historii**: banner zmizí, stejná identita přepíše to, co ještě visí, a v okně po
tom zbude jediný údaj — čas posledního doručení u zvonku. Když jsem byl dvě hodiny na schůzce,
aplikace ví, co se stalo, a nemá to kde ukázat. Pátá sekce railu `Dění` (#414) je to místo: **záznam
na disku**, do kterého se chodí zpátky.

**Osm druhů novinky**, čtyři z nich jsou tytéž události, které chodí jako notifikace (nové PR, znovu
k review, tři výsledky review, cizí aktivita na vlastním PR), a **dva se dopočítávají**: že **nálezy
zastaraly** (hlava se posunula pod uloženými nálezy — ta událost, po které je práce k zahození) a že
**PR odešel z fronty**. Za tyhle dva banner nechodí schválně: vyrušovat nemají, dohledat se mají.

**Zastaralých nálezů si aplikace všimne sama, ne až u otevřeného PR** (#420). Vyhledávání `headSha`
nedává, takže se hlava zjišťuje **jedním dávkovým GraphQL dotazem na celou frontu** — ne jedním na PR
ani na repozitář; změřeno, že dvanáct PR z deseti repozitářů stojí jeden bod z 5000/h. Ptá se jedině
na cizí PR, na kterých leží uložené nálezy a kterým se pohnul `updatedAt`, takže **na klidný den to
je nula volání**. Řádek u toho nese **čas vzniku té hlavy**, ne okamžik zjištění — jinak by po každém
spuštění aplikace vypadalo, že práce z minulého týdne zastarala dneska.

**Sekce unese věci, které banner unést nesmí — a plní se, i když je aplikace mlčící.** Zápis
**nezávisí na přepínačích notifikací**: ty rozhodují o vyrušení, ne o záznamu. Řádek, u kterého
banner nedorazil (vypnutý přepínač, odmítnuté oprávnění), to říká chipem **bez banneru**, takže
„nepřišlo mi to“ má na obrazovce odpověď.

**Strop je 200 položek, ne dní.** Dění odpovídá na „co jsem prošvihl“, a to je omezené pozorností,
ne kalendářem — týdenní okno by usekávalo přesně tu dovolenou, kvůli které se sem chodí. Záznam se
neuklízí ani s PR, které vypadne ze seznamu: zavřený pull request na tom, co se na něm stalo, nemění
nic.

**Přečtenost drží značka poslední návštěvy, ne příznak u položky** — jeden časový údaj na celou sekci
a nad ním pruh `Tady jsem skončil`, tedy tentýž mechanismus, jaký drží konverzaci. Značka se posouvá
**až při odchodu ze sekce**: kdyby ji přepsal vstup, přestalo by být nové zrovna to, na co koukám.
Řadí se **od nejnovějšího** jako commity, takže pruh stojí pod novinkami. Odznak v railu počítá
**nepřečtené** a na aktivní sekci se nekreslí (odznak by v tom railu překryl ikonu, takže by z něj
zbyl červený puntík bez identity); počet je proto v nadpisu bloku — `Dnes · 4 nové`.

**Každý řádek někam vede a je to v něm napsané** (`→ Nálezy`, `→ Konverzace`, `→ Commity`,
`→ Přehled`, `→ Průběh`), ne šipka bez obsahu — a jde to tou samou cestou jako klik na notifikaci
(#409). Jediný řádek, který do okna nevede (PR z fronty odešel, takže v seznamu není), vede **na
GitHub** a pozná se to i barvou; **proč** odešel netvrdí, protože mergnuto od zrušeného requestu se
ze samotné fronty rozlišit nedá.

**Prázdná sekce má čtyři různé věty**, ne jednu: klid („za poslední dny se nic nestalo“),
**ztracený záznam** (soubor byl a nepřečetl se — historie je pryč, nové události se zapisují dál),
**zakázané oprávnění** (bannery nechodí, ale seznam se plní dál — a jde se do Nastavení systému)
a **vypnutý přepínač** (jde se do nastavení aplikace). Klid a mlčící aplikace se nesmí slít ze
stejného důvodu jako `čisté review` a `review se nepovedlo` — a nad ztracenou historií by klidné
„nic se nestalo“ tvrdilo víc, než data unesou.

**Na dashboardu je z toho vidět pět nejnovějších řádků** (#443) — třetí blok pravého sloupce, pod
`Co teď`. Do té doby se do sekce muselo napřed **přepnout**, aby se zjistilo, jestli je do čeho
koukat: odznak v railu říká počet, ne co se stalo. Blok je **ukázka a rozcestník**, ne druhé místo,
kde se dá v dění zůstat: nemá vlastní pruh `Tady jsem skončil`, nekreslí se v něm hlavičky dní
a z prázdných obrazovek sekce v něm zbude **jedna věta** (tlačítka, kterými se mlčení spraví, patří
do sekce). Nadpis nese počet nepřečtených — `Dění · 3 nové` —, patka zbytek záznamu
(`Zobrazit celé dění +37 →`) a `celé dění →` v hlavičce i patka vedou do páté sekce railu.
**Značku poslední návštěvy blok neposouvá**, jinak by se nepřečtené vynulovalo tím, že jsem se
podíval na domácí záložku.

Řádek je **týž `ActivityRowView`** jako v sekci, ale v **úzkém tvaru**: pravý sloupec má 456 bodů,
což je na celou událost málo (změřeno nad návrhem: 42 až 66 bodů, tedy dvě až tři patra). Nese proto
**titulek, `repo#číslo` a čas** — a podrobnost („přišly 3 commity“), sha, chip `bez banneru`, autora
i cíl (`→ Nálezy`) vynechává; ty zůstávají v sekci. **Nezalamuje se**: co se nevejde, ořízne
**titulek**, protože `repo#číslo` a čas jsou souřadnice, podle kterých se pozná, čeho se to týká.
Čas si tady na rozdíl od sekce nese i **den** (`včera v 7:58`) — v sekci ho nese hlavička dne, tady
by ho nikdo nenesl. Klik dělá totéž co v sekci.

**Filtry sekce nemá**, dokud není co filtrovat: den je nadpis bloku a strop 200 položek znamená, že
se dá projít. Odškrtávátka po druzích by teď byla ovládání nad ničím.

U vybraného PR je tlačítko **Spustit review**. Za ním se stane tohle: dotáhne se head
commit, připraví se odpojený pracovní strom a v něm se spustí headless session Claude Code
omezená na čtení. Řádek mezitím ukazuje `ve frontě · clone` → `běží 0/1` → `čisté`, `N nálezů`,
nebo `kód nepřečten`, když se z běhu čisto tvrdit nedá (#383, viz níž); běh jde kdykoli zrušit. Nálezy se uloží na disk, takže přežijí restart, a v panelu
vedle diffu je seznam nálezů po kategoriích, s odznakem u těch blokujících. **Návrh verdiktu**
(`approve` / `request changes` / *není z čeho soudit*) se z nich předvyplní v tabu `Moje review`
a je u něj napsané, že je to návrh; do #218 stál navíc v hlavičce, kde byl druhou kopií téhož.
Kliknutím na nález diff odskočí na jeho `file:line`.

Nad záložkami je **hlavička ve třech řádcích** (#174, přesázená podle návrhu u #218). Nahoře
titulek a vedle něj číslo PR, vpravo `Spustit review` — a je to **jediné akcentové místo v celé
hlavičce**. Pod tím souřadnice: stav PR jako plná kapsle s puntíkem, `autor chce sloučit
větev → base`, `owner/repo`, souhrn kontrol (podrobnosti jsou v záložce `Kontroly`) a odkaz na
GitHub. Větve se do okna dostaly až
s #174 a je to první věc, kterou u cizího PR hledám. Třetí řádek je **pruh běhu**: kapsle
reviewerů (`● php-review 2`, klik filtruje jejich nálezy) a za nimi — když review běží — dráha
průběhu s popiskem `test-coverage · 2 z 3 hotovo · 1:12`.

Když se **hlava PR rozejde se sha, proti které platí nálezy**, přibude pod tím řádek s oběma —
dokud se rovnají, je to trivia, jakmile se rozejdou, je to nejdůležitější údaj na obrazovce,
protože všechno pod ním mluví o kódu, který na větvi už není. Vpravo u záložek je rozsah změny
(`+X −Y`) a za ním pět čtverečků v poměru přidaného a odebraného.

**Stav pracovní kopie je ve stavovém řádku dole** (`Pracovní kopie připravená · HEAD 4f2ac91`),
ne v hlavičce: je to stav prostředí, ne údaj o pull requestu. Selhaný checkout je výjimka —
zůstává bannerem v hlavičce, protože se u něj musí vypsat celý výstup `gitu` a z něj se teprve
pozná, co dělat dál.

Detail PR má **osm záložek** (#183, dvě přidal #242, jednu #215, jednu #316 a jednu #452): `Přehled` říká,
jak to teď stojí (popis, fakta, co se změnilo od minule), `Změněné soubory` je diff, `Commity`
je seznam commitů PR a diff toho, na který se klikne (popsané níž), a `Konverzace` je
**časová osa toho, co se dělo** — s uzly,
u kterých tvar nese druh, se seskupenými commity (jedenáct pushů nesmí utopit dva komentáře),
filtrem `Vše / Komentáře / Vlákna / Události` a značkou `Nové od tvé poslední návštěvy`. U force-pushe
je rovnou u události napsané, že tím zastaraly nálezy, a tlačítko pustit review znovu. Pátá je
`Kontroly` — checky z GitHub Actions a detail toho, na který se klikne (popsaná níž).

Za nimi stojí `Nálezy` (tabulka všeho, co reviewery nahlásily) a `Průběh` (co dělaly), a úplně
vpravo `Zeptat se` (#452) — **rozhovor s Claudem nad tímhle PR**, popsaný níž. Mezi těmi třemi
skupinami jsou **dva děliče**: vlevo je to, co je na PR a co má i GitHub, uprostřed to, co s ním
udělaly naše reviewery, vpravo to, co s tím dělám já teď. Kreslí se ze **skupiny, do které záložka
patří**, ne z její pozice — `Kontroly` i `Commity` sedí vlevo doprostřed, takže zadrátovaný index
by dělič posunul o jedno místo vedle. **Všech osm záložek je v pruhu vždycky** (#306, #316), takže
se jejich počet nemění podle dat.

**Pruh se v užším okně zúží ve třech stupních** (#316, #318, #452). Popisky se nezkracují, jen
zalamují, takže na šířce záleží — a pruh proto ustupuje po kusech, vždycky celý naráz. Čísla jsou
**po osmé záložce**:

| Okno | Co je v pruhu vidět |
|---|---|
| od **1186** | popisky u všech osmi záložek a vpravo `+X −Y` |
| **1076–1185** | popisky, bez `+X −Y` (#316) |
| do **1075** | ikony s odznaky, popisek jen u aktivní záložky (#318) |
| krajní data | jen ikony s odznaky, popisek nikde (#452) |

**První ustupuje `+X −Y`**, protože mluví o rozsahu celého PR, a to je odpověď na otázku
`Změněných souborů`; v `Commitech`, `Kontrolách` ani `Průběhu` není o čem. Sedmá záložka se tím
zaplatila skoro na nulu (pilulka stojí 110 bodů, záložka s odznakem 112); **osmá už ne** —
ve výchozím okně 1100 je od #452 vidět druhý stupeň, takže `+X −Y` se vrací až od ~1186 bodů.
**Druhý stupeň jsou ikony** a spravuje něco jiného: do #318 se pruh pod 939 body **zalamoval**
a v nejužším povoleném okně (700) byl vysoký 90 bodů místo 30 — se šesti záložkami 75, takže to
nebyla cena sedmé záložky. Odznaky v ikonovém pruhu zůstávají a jméno záložky říká nápověda pod
kurzorem.

**Čtvrtý stupeň přibyl s osmou záložkou** (#452) a je to změna měření, ne názoru: do té doby se na
něj nedalo přijít, protože se ikony vešly i s trojmístnými odznaky do okna 689. S osmi záložkami
chtějí 645–711 bodů proti 647, které v nejužším okně jsou — takže by se pruh v tom krajním stavu
(trojmístné počty u všech záložek naráz) zalomil. Poslední podoba shodí i popisek aktivní záložky
a vejde se s 598 body; **na běžná data se na ni nepřijde**.

V `Průběhu` má dráhu **každý reviewer z nastavené sady**, ne jen ten, který už na tomhle PR běžel:
otázka je „kde je které z mých review“ a *ještě nezačalo* je taky odpověď. Tři různá „nic tu není“
mají proto tři různá slova — `nespuštěno` (v sadě, tady nic), `ve frontě` (review běží a tenhle čeká
na slot) a `bez průběhu` (běh v záznamu je, ale jeho osa ne, což jsou soubory z doby, kdy se ještě
neukládala). Dráha po skillu, který v nastavení už není, **nezmizí** — nesla by s sebou doběhlé
review — jen je označená `mimo sadu`.

Záložky jsou podtržené jako na GitHubu a **odznak má každá** (#218), jen počítá pokaždé něco
jiného: `Přehled` novinky od poslední návštěvy, `Změněné soubory` počet souborů, `Commity` kolik
je commitů (tiše — je to množství, ne upozornění), `Konverzace`
kolik je toho k přečtení, `Kontroly` **kolik checků spadlo** (červeně; u běžícího puntík, nad
zeleným CI nic — a dokud není seznam, taky nic: nula nad nenačtenými daty by tvrdila, že se
spočítalo), `Nálezy` kolik jich je (**červeně, když něco blokuje**) a `Průběh` i `Zeptat se`
**puntík, ne počet** — „běží“ je stav, ne množství; počet otázek v rozhovoru by o tabu neřekl nic. Volba se pamatuje **u každého PR zvlášť**
a otevírá se `Přehled` — popis a diskuze se čtou dřív než kód, kterého se týkají.

Nad popisem PR jsou **dlaždice s fakty** (#198): kolik je commitů a kolik z nich přibylo od minule,
kolik souborů se mění a v kolika je nález, hlava PR a sha, proti které platí nálezy. Nic se pro ně
netahá z API; jsou to čísla, která v okně už byla, jen roztroušená. Dlaždice, o které se nedá nic
říct, se nekreslí — kdežto ta se sha nálezů je vždycky, když nálezy jsou, a **rozchod nese barva,
ne přítomnost**: proti čemu nálezy platí, je fakt o PR i tehdy, když se hlava shoduje.

**Nad popisem, ne pod ním** (#280). Do #280 to bylo obráceně, s odůvodněním, že popis je to, co
autor chce, aby se přečetlo. Rozhodla nesouměrnost délek: dlaždice jsou vždycky tři čísla a dvě
sha, kdežto popis je libovolně dlouhý — u pracovních PR běžně padesát řádků — takže se k faktům
scrollovalo přes prózu, jejíž délku neurčujeme my. A jedna z nich, `Nálezy proti`, odpovídá na
otázku „platí to, co v okně vidím?“; odpověď na ni nepatří za odrolování. Přehled patří nad čtení.
Mění se **jen pořadí**: dlaždice ani popis se nezúžily a prázdný popis (`Autor k PR nic nenapsal.`)
se dál neplete s nenačteným (`Načítám popis…`) — pod řadou faktů o to víc, protože prázdná plocha
se tam čte jako „nic tu není“ ještě snáz.

Úplně nahoře v `Přehledu` je **co se změnilo od tvé poslední návštěvy** (#173): nové commity,
cizí review, komentáře — a hlavně **přepsaná historie větve**, protože právě po ní zastarají
nálezy i rozdělané review. Banner se ukáže, **jen když opravdu něco přibylo**, a u PR otevřeného
poprvé nikdy — „od tvé poslední návštěvy" by tam znamenalo „od začátku věků". Značka se posune
hned při zobrazení, ale to, co je vidět, se během běhu aplikace nemění — odskok do `Změněných
souborů` a zpátky o něj nepřipraví. **Odchod na jiný PR a návrat už je nová návštěva**, takže se
banner podruhé neukazuje; projetí seznamu šipkami ho ale nespotřebuje, protože se posouvá jen
u PR, u kterého se stihla načíst konverzace. Odklidit ho jde i rovnou křížkem vpravo.

**Odrážky jsou sázené** (#284, návrh sekce 02): tučně to, co se stalo („3 nové commity",
„Přepsaná historie větve", verdikt cizího review), ztlumeně kdo, a **sha jako kód** na tichém
podkladu. Pod nimi stojí řada ovládání:

- odznak **`nálezy zastaraly`** — jedině tehdy, když nálezy proti staršímu commitu doopravdy
  jsou. Čte tentýž stav jako věta v hlavičce nad taby, takže si ty dvě nemají jak odporovat;
  nad PR, na kterém review nikdy neběželo, se nerozsvítí;
- **`Pustit review znovu`** — i tehdy, když ještě žádné nálezy nejsou: po přepsané historii je to
  ta rozumná další věc;
- **`Ukázat, co přibylo`** — diff **jen toho, co od minule přibylo**, otevřený v tabu `Změněné
  soubory` s lištou, ze které se jedním tlačítkem vrátíš na celý diff. Nabídne se **jen když je
  co s čím porovnat**: potřebuje hlavu z minulé návštěvy, dnešní hlavu a načtenou časovou osu.
  **Po přepsané historii se nenabídne** — porovnání by v takovém případě vrátilo víc než celý
  diff PR (změřeno na `cli/cli#14062`: 102 kB ve 22 souborech proti 15 kB ve třech), tedy přesně
  to, co už člověk viděl.

V úzkém `Přehledu` se řada zlomí pod sebe; rozhoduje o tom **spočítaná** šířka popisků, ne
vyjednávání s rodičem (#220).

**`Konverzace`** nese to, co se neváže k žádnému řádku: review ostatních s odznakem (`schválil`,
`vyžádal změny`), komentáře pod PR a vlákna, jejichž řádek v aktuálním diffu není (typicky
zastaralá po novém commitu). Ta se
kreslí **tou samou bublinou jako u kódu**, jen s cestou a řádkem nad ní — a **pod tím kus kódu,
ke kterému se komentář váže**, obarvený a naformátovaný jako v diffu. Kód se bere ze snímku,
který si GitHub k komentáři drží (`diffHunk`), takže platí pro commit, na kterém komentář vznikl
— nedopočítává se z dnešního souboru, kde už na tom řádku bývá něco jiného. Hunky bývají dlouhé
(medián 190 řádků), takže je vidět jeho konec po komentovaný řádek a **zkrácení je označené**.
Moje komentáře mají odznak `já`, text jde označit a zkopírovat (kromě úryvku kódu, kde selekci
brání gesto na výběr rozsahu) a konverzaci lze obnovit tlačítkem, aniž by se čekalo na tik
pollingu.

Mezi tím je vidět i **co se na PR stalo**: pushnuté commity (titulek a zkrácený sha),
vyžádaná a odebraná review, force push s `před → po`, převedení z draftu, merge, zavření
a změna base — každé s avatarem toho, kdo za tím stojí, a s relativním časem. Události jsou
jednořádkové, ne karty jako komentáře, takže se přehled čte jako časová osa na GitHubu.
Bere se to **týmž dotazem** jako konverzace, takže to nestojí ani jedno kolo po síti navíc.
Zavření hned po mergi se nekreslí zvlášť (mergnutím se PR zavírá), zavření bez mergnutí ano.

**Texty se renderují jako Markdown** — nadpisy, seznamy včetně zaškrtávacích, bloky kódu,
citace, odkazy. Vlastní blokový parser bez závislosti (jako obarvení kódu): systémový umí
formátování uvnitř řádku dobře, ale bloky tiše spolkne. Zvládá i **HTML, které do komentářů
posílají boti** — `<!-- … -->` se nekreslí (jako na GitHubu), `<details>` je rozbalovátko
a odkazy zůstávají klikatelné. Tabulky zůstávají jako monospace řádky a kód v blocích se
neobarvuje: jazyk z fence je volný řetězec, takže mapovat ho na obarvovací pravidla znamená
hádat, a špatně obarvený cizí kód je horší než neobarvený.

**Citace se sázejí do hloubky a GitHubové výstrahy mají rámeček** (#279). Obsah `> …` se parsuje
na bloky, takže `## nadpis`, odrážka i `- [ ]` **uvnitř** citace se vysázejí — do #279 z nich byl
jeden slitý `Text`, a protože boti do citací píšou celé zprávy, stál v okně místo komentáře od
`coderabbitai` jeho zdroj. `> [!NOTE]`, `[!TIP]`, `[!IMPORTANT]`, `[!WARNING]` a `[!CAUTION]` se
kreslí jako barevná výstraha s ikonou a titulkem; **neznámý druh se nakreslí jako obyčejná
citace**, ne spolkne. Nadpisy mají **šest velikostí** (do #279 dvě) a pod `#`/`##` linku, takže se
v dlouhém popisu PR dá skákat po struktuře, a inline `kód` má jemný podklad jako na GitHubu.
Barvy výstrah jsou z palety a u dvou druhů **vědomě jiné než ty GitHubovy**: `[!WARNING]` by se
jinak na hex sešlo se zastaráním a `[!CAUTION]` s blokujícím nálezem, tedy s barvami, které v okně
už něco znamenají. Sazba se **pamatuje** — u dvanáctikilobajtové zprávy od bota je
rozklad na bloky 1,91 ms proti 0,04 ms z cache a inline sazba jejích bloků dalších 1,81 ms.

### Záložka `Commity` (#316, #317)

**Proč vznikla.** `Změněné soubory` odpovídají na „co je na PR jinak proti základu“ — jeden slitý
diff, ze kterého je vidět výsledek, ne cesta. Otázka „proč tenhle řádek zmizel“ nebo „kdy se sem
dostala ta migrace“ má odpověď v jednotlivých commitech, a ta se do #316 hledala v prohlížeči. Je
to tentýž pohyb jako u `Konverzace` (#183) a `Kontrol` (#215): další věc, kvůli které se z okna
odcházelo. V pruhu proto sedí **hned vedle `Změněných souborů`** — obojí odpovídá na „co se
v kódu změnilo“, jen jednou naráz a jednou po krocích.

**Řádek na commit, od nejnovějšího.** Návrh měl původně pořadí z GitHubu (od nejstaršího, „PR se
takhle čte jako postup“), jenže v okně se PR nečte od začátku — čte se od toho, co přibylo
naposled. Je to tentýž pohyb, jaký dělá pruh `Od tvé poslední návštěvy`, a tentýž důvod, proč jsou
fakta v `Přehledu` nahoře; postup se z otočeného seznamu přečte pořád, jen odspodu. **Otáčí se,
neřadí:** pořadí z API je topologické, takže přerovnat ho podle data by po rebase nebo cherry-picku
ten postup rozházelo. V řádku je obrázek autora (monogram, dokud nedorazí nebo když k commitu není
účet), **první řádka zprávy**, jméno autora, relativní čas a zkrácené sha; celá zpráva se z řádku dá
zkopírovat spolu s ním. Nad seznamem je pruh s počtem (`7 commitů · od nejnovějšího`) a vpravo
`hlava` se sha, proti které platí nálezy.

**Dvě pilulky, a obě něco tvrdí.** `sloučení` u commitu s víc rodiči, protože jeho diff se počítá
proti prvnímu rodiči a umí vyjít prázdný — bez upozornění dopředu by prázdný diff vypadal jako
porucha. `hlava` u toho commitu, který je **opravdu** hlavou PR: bere se z `headSha` v detailu, ne
z pozice v seznamu. Nahoře **bývá**, ale je to důsledek toho, jak seznam přišel, ne pravidlo — po
pushnutém commitu (kdy je seznam o krok pozadu) i nad stropem API (kde novější část chybí) se
neoznačí nikdo. Nálezy jsou klíčované `headSha`, takže by pilulka na špatném řádku byla tvrzení,
ne dekorace.

**Panel s nálezy se v téhle záložce nekreslí** — je čtvrtá taková po #294 a má vlastní důvod:
u staršího commitu by panel ukazoval nálezy k **jinému kódu**, protože platí proti `headSha`.

**Co v řádku není:** počet souborů ani `+X −Y`. GitHub je v seznamu nedává (`stats` ani `files`
v odpovědi nejsou) a dotahovat je po commitu je N+1 — u sedmi commitů sedm dalších volání
k jedné otevřené záložce.

**Jedno volání na celý seznam** (`gh api repos/{o}/{r}/pulls/{n}/commits`, změřeno 1,20 s pro sedm
commitů), a tahá se **spolu s detailem**, aby byl odznak s počtem vidět, aniž by se do záložky
chodilo. Klon v cache se nepoužije: `refs/prism/pr/<n>` v něm existuje jen po checkoutu kvůli
review a úklid ho maže, takže by záložka u poloviny PR neměla data. GitHub vydá na jeden PR nejvýš
250 commitů — když se na ten strop narazí, je to nad seznamem napsané, jinak by počet tvrdil, že
je seznam celý.

**Tři stavy, a prázdný mezi nimi není.** Čeká se na odpověď (`Načítám commity…`), seznam, nebo se
ho nepodařilo načíst. Pull request bez commitů neexistuje, takže klidná hláška o prázdnu by
tvrdila něco, co platit nemůže — prázdná odpověď je proto hlášená jako porucha. Když se nepovede
načíst **znovu**, seznam zůstane a nad ním je okrová věta, že je to poslední známý stav, stejně
jako u `Kontrol`.

**Kliknutí na řádek ukáže diff jen toho jednoho commitu** (#317) — a teprve tím řádek dostal šipku
`›`, kterou návrh kreslí. Do #317 žádná nebyla schválně: šipka, za kterou se nic nestane, slibuje
interakci, která tam není.

Rozkliknutí **přepne obsah záložky**, jako to má GitHub: seznam zmizí a diff dostane celou plochu.
Nahoře je hlavička se sha (kliknutím se zkopíruje celé), zprávou i jejím tělem, autorem, časem,
počtem souborů, `+X −Y` a odkazem na GitHub; vlevo v ní je cesta zpět `‹ Commity` s pozicí
(`2 ze 7`), která funguje i klávesou `⎋`. Počty jsou spočítané **ze staženého diffu**, takže
nestojí volání navíc — a proto v seznamu být nemůžou, ale tady ano.

**Tělo zprávy jde sbalit** (`⌄ Tělo zprávy` / `› Tělo zprávy · 6 řádků`), a sbaluje se zrovna ono:
je to jediná část hlavičky, která roste bez omezení — sha, autor a počty jsou pořád tři řádky,
kdežto tělo squashnutého merge commitu má klidně třicet. Sbalená hlavička proto pořád odpovídá na
„na co se to koukám“: zůstává v ní cesta zpět, titulek, sha, odkaz na GitHub, autor, čas i počty.
Volba **platí napříč commity i pull requesty** a drží se do zavření aplikace, protože „kolik místa
nechat zprávě“ znamená u každého commitu totéž; výchozí stav je rozbaleno a u jednořádkové zprávy
se přepínač nekreslí vůbec.

Pod hlavičkou je **týž diff jako ve `Změněných souborech`**: pohled pod sebou i vedle sebe,
zvýraznění změněných slov, sbalování souborů, rozbalování kontextu, kopírování i strom souborů
vlevo (`⌘1`) — commit s třiceti soubory ho potřebuje.

**Nejsou tam ale bubliny nálezů ani rozdělaný komentář a do řádků se nedá klikat.** Není to
zjednodušení: komentář k řádku commitu by se musel klíčovat i sha (dnešní draft se váže na
`(soubor, řádek)` diffu PR) a odeslat by šel jedině pátou cestou ven z aplikace — a ten výčet je
krátký schválně. Nálezy navíc platí proti hlavě PR, takže by u staršího commitu ukazovaly na jiný
kód. Záložka je proto celá čtecí a v hlavičce je jedna tichá věta, která odkáže do `Změněných
souborů` — kdo přijde odtamtud, bude do řádku chtít kliknout.

**Rozbalený kontext se čte z toho commitu**, ne z hlavy PR. Bez toho by odkryté řádky kolem hunku
byly z dnešní hlavy, tedy posunuté o všechno, co mezitím přibylo — a vypadaly by úplně věrohodně.

**Prázdný diff dostane větu, ne prázdnou plochu**, a jinou podle toho, jestli je to sloučení.
U sloučení se diff počítá proti prvnímu rodiči, takže co přišlo z druhé větve, je vidět v jejích
vlastních commitech; u obyčejného commitu je to prostě prázdný commit (`git commit --allow-empty`,
kterým se běžně přetáčí CI). Změřeno na `keboola/job-queue#727`: prázdno vracely zrovna ty prázdné
commity, kdežto všechna tři sloučení diff měla.

**Návrat do seznamu si pamatuje, kde jsi byl** — řádek zůstane podbarvený a seznam na něj
odscrolluje. V okně se u jednoho PR drží nejvýš jeden stažený diff commitu, takže zpátky do téhož
commitu je zadarmo, kdežto přeskakování mezi dvěma si ho pokaždé stáhne znovu (jedno volání,
změřeno 0,7–1,8 s). Commit, který mezitím z PR zmizel (force push), se nekreslí a záložka spadne
zpátky na seznam.

### Záložka `Kontroly` (#215, #214, #306)

**Vlastní záložka, ne blok v `Přehledu`.** Do #215 to byl seznam checků pod dlaždicemi (#209), pak
chvíli jen souhrn — a nakonec ani ten: v `Přehledu` po tom stěhování **nezbylo nic**. Důvod je
detail spadlého checku (#214), kterým blok vyrostl natolik, že popis PR vytlačil mimo obrazovku;
`Přehled` má odpovídat na „jak to teď stojí“, ne být místem, kde se scrolluje log. Je to tentýž
pohyb jako u `Konverzace` (#183): co začne růst, přestane být kontextem a stane se obsahem. „Je to
zelené“ přitom z okna nezmizelo — nese ho **chip v hlavičce PR**, který je vidět ve všech
záložkách, takže souhrn v `Přehledu` byl třetí místo o téže věci.

**Kreslí se vždycky, i u PR bez CI** (#306) — a u něj v ní stojí `Tenhle PR nemá kontroly` s větou,
že to **není porucha**. Do #306 se u PR bez CI nekreslila vůbec, právě aby o něm netvrdila, že se
něco nepovedlo; otočilo to chování: pruh záložek problikával z pěti na šest při **každém** otevření
PR (checky dorazí až s detailem), kdežto prázdná záložka je jen u těch pár PR bez CI — a s tou větou
původní argument padá. Trvale přítomná záložka si vynutila odpověď na **každý** stav dat: čeká se na
odpověď (`Načítám kontroly…`, a to o CI netvrdí nic), PR CI nemá, seznam, nebo se ho nepodařilo
načíst. Když se nepovede načíst **znovu**, seznam zůstane a nad ním je okrová věta, že je to
poslední známý stav — okrová, ne červená, protože „nevím“ není „je to rozbité“.

V tabu je karta `Kontroly na GitHubu`: v hlavičce poměr (`1 selhala · 1 prošla · 1 přeskočeno`),
pod ním řádek na každý check s dobou běhu. **Nejhorší stav vyhrává** — dvanáct zelených a jeden
červený je červený stav — a **přeskočený check není prošlý**; přeskočené se sbalí za číslo, protože
jich na monorepu bývá většina (změřeno: 22 z 28). Odkaz na GitHub je jen u toho, co se nepovedlo.

**Kliknutím se check rozbalí na anotace a konec logu** (#214). Rozbalit jde každý, u kterého se dá
z odkazu vyčíst číslo jobu — i prošlý, protože `phpunit`, který prošel, ale trval dvacet minut, je
taky důvod se do logu podívat; u checku bez čísla (CodeQL, bors) zbývá odkaz ven, protože tlačítko,
které skončí chybou, je horší než tlačítko, které tam není. **Anotace z CI není nález z review** a
nesmí s ním splynout: je to plochý řádek se štítkem `error`/`warning`/`notice`, ne bublina — nedá
se odmítnout a nepočítá se nikam. Když anotace ukazuje na místo v diffu, je z ní odkaz, který tam
skočí; kolik se jich nevešlo, je pod nimi napsané. **Prázdno je běžný stav**, ne porucha: anotace
emituje jen workflow, které si o to řekne, a proto je log ta hlavní cesta.

**Konec logu je 6 000 řádků** (#303, do té doby 4 000 a před #292 tři stovky) v okýnku o třiceti
řádcích, které scrolluje samo — nasázet je naplno by odtlačilo seznam checků mimo obrazovku, tedy
zrovna to, kvůli čemu se detail z `Přehledu` stěhoval. Kolik se nevešlo, je nad okýnkem napsané
(`— starších N řádků se nevešlo —`): **tiše zkrácený log tvrdí, že job začal uprostřed**. ANSI se
strhává a timestampy se schovávají.
Celý text je v `Ukázat celý log` — **sheet, který se dá roztáhnout za okraj a velikost si pamatuje**
(#417). Otevírá se **široký podle obrazovky** (obrazovka bez 152 bodů, nejvýš 2 700; úzký sheet
znamená víc řádků sazby na jeden řádek logu — při 560 bodech se láme 68 % řádků logu, při 1 360 už
jen 13,5 %) a vysoký 760 bodů; pod 820 × 420 nejde. Je v něm log **surový, jen bez ANSI**: s
timestampy a bez ořezu na 6 000 řádků, a hlavička říká, jestli je log celý, nebo je to snímek
běžícího jobu. V patičce je `Zavřít`, odkaz na log na GitHubu a `Zkopírovat vše`.

**Tentýž sheet ukazuje i hunk k vybrání** z diffu, jen v jiné velikosti: 1 180 × 520, nejmenší
560 × 320. Velikost si pamatuje **zvlášť pro hunk a zvlášť pro log** — roztažený log by jinak
otevíral takhle i hunk o devíti řádcích.

Tři věci, které se u logu **nedělají**. Nestahuje se **dopředu ani pro celý seznam** — jen pro ten
jeden check, na který se kliklo; log běhu je log všech jeho jobů, takže seznam by byl N+1 past o tři
řády dražší. **Neukládá se na disk**: log není nález, neplatí proti `headSha` a nedá se odmítnout,
takže v cache vedle nálezů nemá co dělat — nepřežije ani sbalení checku, které stahování navíc
**zruší**. A nad **10 MB** se nestahuje vůbec: velikost se zjistí předem samostatným dotazem, který
se vrátí za ~1,2 s bez ohledu na to, jak je log velký, takže věta `Log má 8,4 MB, na zobrazení je
moc velký.` není odhad. Když velikost neřekne, **stáhne se i tak** a strop se uplatní na tom, co
doopravdy přišlo — `HEAD` je ochrana proti osmimegovému logu, ne podmínka toho, že se log ukáže
(#292: chyba jednoho dotazu tehdy vypnula celou funkci). Cena je zapsaná: u toho největšího logu
odpadá i jeho konec, tedy zrovna tam, kde je odchod do prohlížeče nejotravnější.

**`Změněné soubory`** ukazují **diff v plné šířce**: soubory pod sebou s hlavičkou, která při scrollu
zůstává nahoře, souhrn `N souborů · +X −Y` a menu na skok mezi soubory. Přejmenování, nové,
smazané i binární soubory jsou označené; dlouhé řádky se zalamují, protože 120 znaků se do
plné šířky vejde. **Zalomí se až tam, kde kód nemá kam pokračovat** (#236) — sloupce s čísly ubírají
místo jen vlevo. Do té doby se zalamovalo o jejich šířku dřív, takže se při šířce obsahu 600 pt vešlo
41 znaků místo 57 a u pravého okraje zůstávalo mrtvé místo; při té samé chybě se navíc bublina nálezu
kreslila přes poslední řádky bloku. Počty `+X` a `−Y` jsou obarvené jako znak změny v samotném řádku — zeleně
a červeně, v řadě záložek PR i v hlavičkách souborů, takže „velký přírůstek“ a „velké mazání“
jsou poznat na první pohled.

**Hlavička souboru nese celou cestu** (#219) — složka tlumeně, jméno tučně (`src/Vault/`**`SecretClient.php`**).
Do té doby tam bylo jen jméno, takže u dvou souborů, které se jmenují stejně, nešlo poznat, který
je který. V úzkém sloupci ustupuje složka, ne jméno.

**Lišta nad diffem** má vlevo pohled a procházení nálezů, vpravo `Rozbalit vše`. Co se používá
jednou za čas (bubliny nálezů u řádků, `Zobrazit jen diff`), sedí v nabídce pod ním. Přepínače
postranních sloupců v ní **nejsou**: strom i panel se skládají u sebe, takže by to byly třetí
dveře k témuž — zkratky `⌘1` a `⌘2` platí dál a stojí v nápovědě u těch tlačítek.

Diff se dá kreslit **dvěma způsoby** a přepíná se segmentovaným přepínačem v liště nad ním:
`Pod sebou` je klasický unified diff (odebrané a přidané řádky pod sebou, dvě čísla vlevo),
`Vedle sebe` staví starý obsah vlevo a nový vpravo, spárovaný po řádcích. U přepsaného bloku
se tím odpadá páření `-` a `+` řádků očima, což je u review nejčastější otázka. Blok
odebraných řádků se s následujícím blokem přidaných spáruje pozičně; přebytek na kterékoli
straně dostane prázdnou buňku s neutrálním pozadím. Kontextový řádek stojí na obou stranách,
hlavička hunku, rozbalovací řádek, bubliny i poznámky `git`u jdou přes celou šířku. Všechno,
co diff umí pod sebou, umí i vedle sebe — bubliny, rozbalování kontextu, obarvení, sbalování
souborů i skok z tabulky nálezů. **Komentovat jde i rozsah řádků**: **táhni myší přes sloupec s čísly** (nebo z pilulky s ikonkou) —
vybraný rozsah se průběžně zvýrazňuje a po puštění se otevře komentář. Tažením **přes kód** se od
#157 vybírá text, takže rozsah se táhne vlevo od něj. Bublina visí u posledního řádku rozsahu,
jako na GitHubu. Rozepsaný komentář jde ještě roztáhnout **⇧ klikem** na `+` u jiného řádku (to
tažení neumí, protože komentář už existuje). Rozsah smí přeskočit i mezeru mezi hunky a odesílá se
jako `start_line`/`start_side`, tedy tak, jak to čeká GitHub.

**Rozepsaný komentář visí jen v té půlce, které se týká** —
komentář k odebranému řádku vlevo, k novému vpravo, a když komentuješ obě strany téhož řádku,
stojí oba **vedle sebe**. Nálezy a cizí vlákna zůstávají přes celou šířku, protože se na stranu
nevážou a nesou delší text.

**S jakým pohledem se diff otevírá, je v nastavení** (`Diff → Pohled na diff`, v souboru
`global.diffLayout`); výchozí je `Pod sebou`, tedy dosavadní chování. Přepínač v liště je
proti tomu jen odchylka: platí napříč pull requesty do zavření aplikace a do konfigurace
nezapisuje — nastavení říká „takhle to chci mít“, přepínač „teď se na to podívám jinak“.
Per repo se pohled nenastavuje, protože jak se čte diff, je vlastnost člověka, ne repozitáře.

**Světlý a tmavý režim se přepínají v aplikaci** — jedním tlačítkem v **levé liště**, pod
oddělovačem. Klik cykluje `Světlý → Tmavý → Podle systému` (výchozí je `Podle systému`) a **stav
nese ikona**: slunce, měsíc, kolečko s „A“ pro automat. Kam klik povede, je v nápovědě po hoveru
(`Vzhled: tmavý · kliknutím podle systému`). Platí to pro všechna okna —
hlavní, nastavení, novinky i sheety — a uplatní se hned, bez restartu, včetně otevřeného diffu
i jeho obarvené syntaxe. Vzniklo to kvůli diffu: v obou režimech se čte jinak a přehazovat kvůli
jednomu PR celý systém je nepřiměřené. Přepínač volí **režim, ne barvy** — ty zůstávají tam, kde
byly, a jsou v obou režimech tytéž jako ve vizuálním návrhu. V souboru je to `global.appearance`
a **v nastavení stránku nemá**: ovládá se z lišty, kde ho má návrh, a druhé místo na tutéž volbu
by znamenalo dvě tvrzení o jednom stavu. Per repo se to nenastavuje ze stejného důvodu jako
pohled na diff.

**Klik na hlavičku souboru jeho diff sbalí a rozbalí**, jako na GitHubu — u PR přes deset
souborů je to hlavní způsob, jak se v něm pohybovat. Hlavička zůstává vidět i se `+N −M`
a s kapslí, kolik je v souboru nálezů (červenou, když je mezi nimi blokující). V horní
liště je `Sbalit vše` / `Rozbalit vše` a skok na soubor nebo na nález sbalený soubor sám
otevře.

V mezerách mezi hunky jsou **šipky na rozbalení kontextu** — dotáhnou kód, který v diffu
není, po dvaceti řádcích nebo celý úsek naráz. Obsah souboru se čte z GitHubu až na
kliknutí; když se mezera rozbalí celá, hunky se slijí a hlavička mezi nimi zmizí.
`Zobrazit jen diff` sbalí všechno zpátky. **Kód kolem nálezu, jehož řádek v diffu není,
se dotáhne sám** — nález bez svého kódu se nedá posoudit. Skok kamkoli v diffu je **stromem souborů** vlevo.
`Zobrazit jen diff` se schovalo do nabídky u `Rozbalit vše` (#219).

**Hledat v diffu jde na ⌘F** (#152). Pod lištou se otevře pruh: pole, počet výskytů (`4 z 17`),
šipky `⌘G` / `⌘⇧G` (v poli i `⏎` a `⇧⏎`), kapsle `Aa` na rozlišování velikosti a `✕` s `esc`. Skok
míří **na řádek, ne na jeho okolí** — výskyt přistane ve třetině shora, a v pohledu vedle sebe se
sloupec posune i **do šířky**, když výskyt leží za jeho pravou hranou (jedině tehdy: rozkoukanou
vodorovnou polohu skok nepřerovnává). Sbalený soubor **sám rozbalí** a kolik výskytů který soubor
má, stojí v jeho hlavičce; nalezené kusy
svítí v kódu, ten aktuální sytěji. `esc` pruh zavře a zvýraznění zhasne — **dotaz si drží**, takže
druhé ⌘F pokračuje tam, kde první skončilo. Hledá se i v diffu rozklikaného commitu, s vlastním
pruhem.

**Hledá se v hunkách a v rozbaleném kontextu, ne v celých souborech** — a je to napsané v pruhu
(kapsle `jen v diffu` u počtu). Zbytek souborů se kvůli hledání nedotahuje: u PR o padesáti
souborech je to padesát volání na GitHub kvůli jednomu slovu. Když se nic nenajde, pruh proto neříká
„nic nenalezeno“, ale **`v diffu nic — mimo hunky se nehledá`** a vedle toho `rozbal kontext (⌄)
a započítá se`. Rozbalený úsek se do počtu započítá hned.

**Kód se vybírá myší jako v editoru** (#157) — tažením přes libovolně mnoho řádků, ⌘C. Vybírá se jen
obsah, ne čísla řádků a ne znak změny, takže se do schránky nepřiplete diff. Kód proto kreslí
`NSTextView`, ne SwiftUI text: ve SwiftUI je každý text vlastní selekce, takže by šlo vybrat jen
jeden řádek. Souvislé řádky se slévají do bloku, který končí u hlavičky hunku, rozbalovacího řádku
nebo bubliny — vybírat jde přes celý úsek kódu mezi nimi, u většiny řádků přes celý hunk. Výběr
zůstává modrý, i když myš odjede jinam, a v pohledu vedle sebe žije **jen v jednom sloupci**.

Na to, co blok neumí — vybrat **přes** bubliny — je v kontextovém menu `Vybrat text z hunku…`: otevře
hunk v samostatném okně jako jeden text, s obarvením a s tlačítkem na zkopírování všeho. Zavírá se
Escem. Od #417 se to okno **dá roztáhnout za okraj** a otevírá se na 1 180 × 520 (nejmenší
560 × 320); v hlavičce stojí, že je to nová verze bez znaků změny, a v patičce, kolik řádků se
nevešlo na šířku. Velikost si pamatuje **zvlášť od sheetu s logem**.

Na víc řádků je **pravé kliknutí**: `Kopírovat řádek`, u řádku, který leží v rozsahu tvého
rozdělaného komentáře, i `Kopírovat rozsah` s počtem řádků, a na hlavičce hunku `Kopírovat hunk`.
Ve schránce je **kód, ne diff** — bez `+`/`-`, bez čísel řádků a bez hlavičky hunku. U rozsahu přes
odebrané i přidané řádky se kopíruje **nová** verze; rozsah čistě na levé straně naopak ten starý
kód. Kopírováním **nevzniká komentář**, takže po sobě není co uklízet.

Tažení rozsahu pro komentář se s vybíráním textu snese: nad kódem dostane tažení výběr textu, nad
čísly a pilulkou výběr rozsahu. Pilulka s ikonkou má vlastní sloupec **vlevo od čísel**, takže už
žádné číslo nepřekrývá, a **táhnout jde i z ní**. Kurzor se mění po sloupcích: ruka nad pilulkou,
šipka nad čísly, textový nad kódem.

**V pohledu vedle sebe se dlouhý řádek nezalamuje, ale posouvá vodorovně** — jinak by jeden sloupec
narostl o zalomený řádek, druhý ne, a přestalo by platit, že vlevo a vpravo je tentýž řádek.

**A od #422 je to vidět: pod každou půlkou je vodorovný pruh** (klasický posuvník, ne ten
zmizíkový), takže se z okna pozná, že za pravým okrajem kód pokračuje — a z šířky knobu i kolik ho
tam je. Pruh dostane **jen blok, který má co skrývat**; co se do sloupce vejde, o jeho 17 bodů
výšky nepřijde. Vodorovný pruh sloupec **nezúží**, takže znaků na stranu je stejně jako dřív
(22 ve výchozím okně s otevřeným stromem i panelem). Rozhodl o tom výběr ze tří možností: zmizíkový
posuvník se natrvalo zobrazit nedá (změřeno — nakreslí 0 pixelů, i když API tvrdí, že je vidět)
a zalamovat se ve splitu nesmí.

**A od #428 ten pruh jede s výřezem.** U dlouhého bloku byla jeho dolní hrana pod dolní hranou okna,
takže se k pruhu muselo sjet a zpátky nahoru k tomu, co si chce člověk přečíst — a týká se to
**9,6 %** bloků, u kterých pás leží pod hranou okna o 229 bodů (medián; p90 533). Pruh proto sedí na
dolní hraně **viditelné části svého bloku**: dokud blok hranu okna přesahuje, stojí na ní, a jak se
jeho vlastní pás do okna dostane, pruh v něm přistane a jede dál s kódem. Je to jedno pravidlo,
`y = min(vlastní pás, hrana okna − 17)`, ne přeskakování mezi dvěma stavy — a **pruh nikdy neopustí
svůj blok**, takže je z okna vidět, který blok řídí, bez popisku. Výška bloku se tím nemění a **prvek
nepřibyl**: je to tentýž posuvník, jen nakreslený jinde. Zakrývá spodních 17 bodů kódu (1,06 řádku),
tedy prakticky ten řádek, který hrana okna stejně řeže. Jediná výjimka je pojmenovaná: **pod třemi
viditelnými řádky** se pruh nepřišpendlí, protože by zakryl polovinu toho mála, co z bloku vidět je.

Vyšlo u toho najevo, že **se tam dosud nedalo rolovat vůbec** — ne že by to jen nebylo vidět:
plocha se roztahovala podle šířky textu bez sloupce s čísly, a AppKit ji navíc srážel zpátky na
šířku okýnka, takže konec dlouhého řádku byl z okna nedosažitelný. Od #422 si šířku určuje ten,
kdo kód kreslí. Co se **nemění**: čísla řádků odjedou s textem (kreslí je totéž view jako kód) —
je to tak i v návrhu a přišpendlit gutter je jiné issue. A **pohled pod sebou zůstává zalamovací**,
pruh v něm není.

**Kolik obsahu pruh tvrdí, se počítá půlce zvlášť a po řádcích.** První verze se ptala AppKitu na
jedno číslo za celý sloupec, a to u půlky, jejíž poslední řádek je prázdný — tedy u každé
šrafované strany dvojice —, vyšlo jako **deset milionů bodů**: knob velikosti vlasu u levého okraje
a rolování do prázdna. Půlka, ve které jsou jen šrafované řádky, proto pruh nedostane vůbec: nemá
co skrývat.

Kód je **obarvený podle jazyka** — vlastní pravidla, žádná externí závislost, paleta
Darcula v tmavém režimu a IntelliJ Light ve světlém. Barví se řádek po řádku bez paměti,
protože diff je útržek: víceřádkový komentář se obarví jen tam, kde začíná. Soubor
v neznámém jazyce zůstane jednobarevný.

**U přepsaného řádku svítí jen ta část, která se změnila** (#153) — sytější pruh přes zelené
nebo červené pozadí řádku, v obou pohledech. Do té doby svítil celý řádek, takže se u dlouhého
kódu rozdíl hledal přečtením obou verzí. Porovnává se **po slovech**, ne po znacích (přepsané
jméno svítí celé, ne po písmenech, a `==` proti `!=` je jedna změna), a jen tam, kde jsou si
řádky dost podobné: dvojice, která je ve skutečnosti smazání a přidání vedle sebe, zůstane
obarvená celá jako dosud. Obarvení syntaxe zůstává pod tím — word-diff je pozadí, syntaxe
barva písma. **Od #277 je ta vrstva o kus tišší**, protože v tmavém režimu pod sebou zhasínala
právě ten kód, kvůli kterému se člověk kouká: kontrast řetězce na ní byl 1,27, teď je 2,17.

**Prázdná strana dvojice je v pohledu vedle sebe prošrafovaná** (#277) — tam, kde je kód jen na
jedné straně, druhá polovina není hladká plocha, ale šikmé pruhy. Do té doby vypadala stejně jako
nezměněný řádek, takže z okna nešlo poznat, jestli se řádek nezměnil, nebo tam vůbec není. Odlišuje
se **texturou, ne světlostí** (a tak to má i návrh): v tmavém režimu už není kam ztmavovat
a světlejší plocha by křičela hlasitěji než sama změna.

**Nálezy visí jako bubliny u řádků, kterých se týkají** — pill kategorie, verdict, jméno
revieweru a rozbalitelný scénář selhání; blokující nález má červený pruh. Shodu dvou
reviewerů na jednom místě označí `2×`, ale jejich texty se neslučují. Nález na řádek, který
v diffu není, se neztratí: visí u hlavičky souboru a nabídne ten řádek dotáhnout. Bubliny
jdou vypnout v nabídce u `Rozbalit vše` (`Nálezy u řádků`) — vlákna konverzace zůstanou.

**Blokující nález je rozbalený rovnou, ostatní jsou značka na hraně řádku** (#185). Značka je
pruh s odznaky, kategorií, reviewerem a náhledem textu — kliknutím se rozbalí celá bublina
i s akcemi, druhým kliknutím se zavře. Rozbalit všechny by z diffu udělalo seznam nálezů
proložený kódem; sbalit i ten blokující je zase kliknutí navíc právě u toho jednoho, kvůli
kterému se PR nemerguje. **Odmítnutý se nerozbaluje nikdy** — je to jeden řádek s důvodem
a `Vrátit`, takže rozbalovat u něj není co. Skok z panelu i šipkami z lišty sbalenou bublinu
**rozbalí**, jinak by cíl skoku byl pruh, na kterém není co přečíst. Rozbalení se pamatuje
per PR, dokud PR nezmizí ze seznamu.

**Nálezy se procházejí šipkami v liště nad diffem** (#187): `2 z 3 nálezů` a dvě šipky, klávesově
`⌥↓` a `⌥↑`, na další blokující `⌥⇧↓`. Do té doby vedla cesta k dalšímu nálezu vždycky přes
panel — najít ho v seznamu a kliknout — takže seznam musel být pořád vidět. Zúžení
`jen blokující` mění, kam šipky skáčou; **odmítnuté nálezy se přeskakují**, protože nález,
kterému nevěřím, není práce k projití. Puntík zezelená, teprve až jsi prošel **všechna** místa,
ne když skončíš na posledním; a nálezy bez místa v kódu se do počtu neplete — nedá se na ně
skočit, tak je nápověda počítá zvlášť, aby `3/3` netvrdilo hotovo nad PR, kde zbývají v panelu.

**Ty zkratky do #151 fungovaly jen do prvního skoku** a stálo to za jednu poučku: SwiftUI páruje
u šipek zkratku **bez ohledu na shift**, takže `⌥↓` a `⌥⇧↓` jsou pro něj jedna klávesa a vyhrává
ta zaregistrovaná později. `⌥↓` tedy dělalo „další blokující“ — a protože blokující nález bývá
jeden, druhé zmáčknutí nikam neskočilo. Obojí je proto **jedno tlačítko** a shift se čte z události,
která akci spustila.

**Vlevo od diffu je strom souborů** (#197): cesty, u souboru s nálezem puntík (červený, když
blokuje). Skládá se na `⌘1` na proužek s počtem souborů, a týmž kliknutím se zase rozloží.
Popover `Přejít na soubor` odešel z lišty u #219 — byla to druhá dveře do téhož: sloupec je
na dosah jedním kliknutím a v liště bral místo, kvůli kterému se v užším okně nevešla.

**Napravo od diffu je panel se segmenty** (#182): nálezy jako karty a Moje review. Panel
je jediné místo, kde jsou vidět nálezy **bez místa v kódu** — chybějící testy nebo poznámky
k architektuře; kvůli nim samotné bubliny nestačí. Klik kamkoli do karty odscrolluje diff
(a přepne na něj, když jsi v jiném tabu) tak, aby nad nálezem zůstalo pár řádků kontextu,
a bublinu na chvíli zvýrazní.

**Vidět je ve čtyřech záložkách ze sedmi** (#294, #316, #392): v `Přehledu`, ve `Změněných
souborech`, v `Commitech` a v `Konverzaci` — tedy tam, kde se vedle něj čte **něco jiného** a otázka
„co k tomu nahlásily reviewery“ má smysl. V `Kontrolách`, `Nálezech` a `Průběhu` se schová **celý,
i se složeným proužkem**: v `Kontrolách` ukrajuje šířku obsahu, který ji potřebuje (konec logu),
v `Nálezech` a `Průběhu` je to duplikát — tytéž nálezy přes celou šířku a záznam týchž běhů.
Proužek je úzký, ale ne zdarma, a v úzkém okně je to zrovna to místo, kde se obsah láme. Do #242
tu stálo, že panel je vidět všude; **smyčka nález → `Převzít` → text v mém review se tím nezahodila,
jen se přestěhovala** — z tabu bez panelu si `Převzít` přepne do tabu, ve kterém panel je, jinak by
rozepsaná věta spadla někam, kde ji nikdo nehledá. Ze stejného důvodu je `⌘2` v těch třech tabech
zakázaná a ⌘K v nich složení panelu nenabízí: přestavět tab, do kterého se člověk vrátí, a nenechat
po tom v okně stopu je horší než zkratka, která nedělá nic.

**V `Commitech` panel do #392 nebyl** a otočily to labely s reviewery: nejsou o commitu, platí pro
celý pull request, takže panel, který se tam nekreslí, schová i to, co v něm platí vždycky. Druhý
důvod — nálezy jsou klíčované `headSha`, takže u staršího commitu mluví o jiném kódu — se **neobešel**:
nad seznamem commitů je u nálezů věta *Nálezy jsou proti hlavě e8d4a60.*, u rozkliknutého **staršího**
commitu **výstraha** (*… Tenhle commit je 5e2b1aa, takže o kódu na obrazovce nemluví.*) a karty jsou
ztlumené. Šířku to bere **obsahu**, ne pruhu záložek: se stromem souborů a rozloženým panelem zbude
na diff commitu 531 bodů, tedy 22 znaků na stranu ve pohledu *Vedle sebe* a 49 pod sebou. Nevynucuje
se nic — strom se složí `⌘1`, panel `⌘2`, a se složeným proužkem je to ve splitu 39 znaků.

**Nad segmenty stojí labely a vyžádaní reviewery** (#392) — dvě sekce, které platí pro celý PR, ne
pro vybraný segment. Labely jsou chipy s **puntíkem v barvě z repozitáře** (plná výplň by u každé
barvy musela počítat kontrast textu a přebíjela by odznak závažnosti nálezu), u reviewera je
iniciála, login a **odpověď ve třech hodnotách**: `schválil`, `chce změny`, `čeká`. Prostřední je
jediná, která něco blokuje.

**Vyžádaný tým je čtvrtý druh řádku, pod lidmi.** GitHub drží vyžádané reviewery ve dvou polích
a tým **nemá odpověď** — dá ji až ten, kdo za tým odpoví, a ten se pak objeví jako osoba v řádku
výš. Tým proto nemá kolečko s iniciálou (to znamená osobu), ale skupinovou ikonu ve **čtverci**,
a v pravém sloupci stojí `tým`. Bez toho byla sekce u PR s týmovou žádostí prázdná, i když review
někdo vyžádal — u čtyř PR ze čtrnácti. Když se panel zúží, ustupují tři věci v tomhle pořadí: řádek chipů se
zalomí, na **dvou řádcích** se zastaví a zbytek je `+2`, a teprve jméno, které je samo širší než
panel, se ořeže — puntík u něj zůstane a `chce změny` se neořezává nikdy.

**Měnit se to dá jen na vlastním PR.** Tam jsou u sekcí `+ label` a `+ reviewer`; na cizím PR akce
**nejsou vůbec** (ne zašedlé — u cizí fronty se to nedělá nikdy). Label se vybírá **jen z labelů,
které repo zná**: je vratný jedním klikem, takže nedostal potvrzovací sheet, ale volný text tam
nepatří, protože z něj se dá omylem vyrobit nový label a ten už z repozitáře sám nezmizí.

**Nový label se od #413 dá založit z nabídky, ale druhým krokem.** Uzavřený zůstává **seznam**, ne
nabídka: řádky nesou dál jen labely repozitáře a `↵` na vybraném pořád jen přepíná. Založení je
vlastní akce **pod děličem** se zkratkou `⌥↵` a vede na **druhou obrazovku téhož popoveru**, kde je
jméno doslova, slug repozitáře, hex barvy a věta o tom, že to v repu zůstane. **Barvu vybírá aplikace
podle jména** (stejné jméno = stejná barva, z palety, kterou nabízí GitHub) — přebarvit ani smazat
label odsud nejde, obojí se dělá na GitHubu. Akce **zmizí**, když label toho jména už existuje, a to
i v jiné velikosti písmen: `Bug` se vedle `bug` nezaloží. Naopak se nabídne i tehdy, když seznam něco
našel — `bug-ui` v repu, které zná `bug-ui-legacy`.

`Založit a přidat` jsou **dvě volání** (jedno do repozitáře, druhé na PR), takže existuje stav, ve
kterém je label v repu a na PR ne. Píše se to proto přímo v patce potvrzení (`dvě volání`) a když
druhé volání nedopadne, je v panelu věta, která říká **oba konce** i důvod — a dorovná se to jedním
kliknutím na řádek, který od té chvíle v nabídce je.

**V nabídce je sloveso v nadpisu a v položkách jen jména** (`Vyžádat review od` / `Přepnout label`).
Kdyby ho nesla každá položka, čtrnáct řádků by opakovalo totéž a předpona by ořezala to jediné, čím
se od sebe liší. Od šesti položek je nad seznamem **hledání**: psaní filtruje, `↑↓` vybírají, `↵`
potvrdí, `esc` zavře — a filtruje se podle toho, co je v řádku vidět (jméno, login, slug, jméno
labelu). **Ty klávesy jsou od #434 napsané v patce nabídky** (`↑↓ vybírá`, `↵ přepne` / `vyžádá`,
`esc zavře`); nad prázdným výsledkem patka není, protože tam by dvě z těch tří slibovaly klávesu,
po které se nic nestane. `⌥↵` v ní není schválně — zakládání nového labelu má zkratku napsanou
přímo u své akce. Pravidlo shody je **totéž jako v paletě ⌘K**: bez diakritiky, bez ohledu na velikost
písmen, víc slov jako „a zároveň“ a silnější shoda nahoru. Hledání **nezakládá** — co se v nabídce
nenajde, nejde vybrat. Reviewer
se vyžádá **jedním pojmenovaným kliknutím** (`Vyžádat review od …`) z lidí a **týmů**, které na repo
smí — request pošle upozornění a odebráním se nedá vzít zpět, takže je na tlačítku napsané, co se
stane a komu; u týmu je v něm slovo `týmu`, protože upozornění odejde všem jeho členům. Když je
odesílání vypnuté, jsou akce zakázané a **důvod je napsaný pod sekcemi**, ne jen v tooltipu. Odesílá se to **tou samou jedinou cestou ven** a **tou samou branou** jako review
a komentáře; s vypnutým odesíláním jsou akce zakázané s důvodem, což je jiný stav než cizí PR.

**Pod nimi je od #465 sekce `Větev`** — stav vlastní větve a to, co se s ní dá udělat. Dva řádky
říkají, **kam se to slévá** (`issue-465-… → main`, a jestli je větev srovnaná, **o kolik commitů je
vzadu**, nebo v konfliktu) a **co je na tom hotové** (`3 commity · 6 checků` / `zeleno`). Pod nimi
jsou **dvě akce**: `Mergnout…` — se třemi tečkami, protože otevírá potvrzení; merge je nevratný
a týká se `main`u, ne jen pull requestu — a od #466 `Rebase`. **U vlastního draftu je nad nimi ještě
třetí**, `Připravit k review` (#482, viz níž).

**Obě akce jsou v panelu vždycky, mění se jen to, která z nich je zvýrazněná**: `Mergnout…` když je
zeleno, jinak `Rebase`. Srovnat větev dává smysl i tehdy, když už mergnout jde, a schovávat
akci podle stavu by znamenalo, že se tlačítko pod rukou stěhuje.

**Potvrzení vypisuje, co se stane**, jako u odeslání review: větev → base, metoda (`squash`,
jiná se odsud neposílá — kdo chce jinou, jde na GitHub), kolik commitů se slévá do jednoho, jaký
bude titulek a proti které hlavě se merguje. **A hlavně píše i to, co v tom výpisu není**: tělo
squash commitu skládá GitHub ze zpráv slévaných commitů, takže se neslibuje, že je v okně vidět
celé. Tlačítko **není výchozí** — Enterem se nic nemergne.

**Po úspěšném mergi se zavře potvrzení i záložka toho pull requestu.** Mergnutý PR je dočtený, tak
se nemusí zavírat ručně; okno přeskočí na sousední záložku, a když žádná nezbyla, domů. Zavírá se
**jen po úspěchu** — když GitHub merge odmítne (`409` po pushnutém commitu, `405`, spadlá síť),
zůstane otevřené obojí i s hláškou, proč to nešlo, a dá se zkusit znovu. Pravidlo, že záložku
mergnutého PR zavírá **člověk a ne polling**, tím platí dál: tady ji zavírá tentýž klik, kterým se
mergovalo. Prázdný stav *Pull request zmizel ze seznamu* se `Zavřít záložku` zůstává pro to, co se
stalo jinde — cizí merge, odebraný request na review. **Rozdělané review se zavřením neztratí**,
draft leží na disku a s otevřenou záložkou je zpátky.

**Hlava PR jde v payloadu jako podmínka, ne jako údaj.** Když se větev mezi otevřením potvrzení
a kliknutím pohne, GitHub odpoví `409` a **nemergne nic** — v okně je pak věta, že se nic nestalo
a co přibylo. Je to jediná akce v aplikaci se dvěma pojistkami proti závodu (pre-flight a `sha`
v payloadu), a je to schválně: mergnout kód, který jsi neviděl, je tatáž záměna jako approve na
kód, který jsi neviděl.

**Kdy se `Mergnout…` nenabídne, a proč to okno řekne.** Na cizím PR se sekce **nekreslí vůbec** —
mergnout cizí frontu se odsud nedělá nikdy. Na vlastním je tlačítko zašedlé, když se stav teprve
zjišťuje, když je odesílání vypnuté, když je větev pozadu nebo v konfliktu, když merge nepouštějí
pravidla repozitáře, když **neprošel check** — a když **můj vlastní reviewer hlásí blokující
nález**. Důvod stojí **v panelu**, ne jen v nápovědě pod kurzorem, a je jich vypsaných tolik,
kolik jich platí: každý vede jinam. Červený check merge zakazuje, i když by ho GitHub pustil
(u nepovinných checků dovolí) — zeleno je jediný stav, ve kterém se dá mergnout bez čtení. Běžící
check naopak nebrání.

**Slévatelnost se u GitHubu počítá až na vyžádání**, takže se na ni aplikace ptá opakovaně (tři
pokusy) — bez toho by tlačítko u čerstvého PR svítilo zašedle podle náhody. A ptá se **jen na
vlastním otevřeném PR**: na cizím se sekce nekreslí a mergnutý vrací „nevím“ navždycky.

### `Připravit k review` — jediná překážka mergnutí, kterou aplikace odklidí jedním kliknutím (#482)

Sekce `Větev` vypisuje, proč se nedá mergnout. Většina těch důvodů je práce — jeden z nich byl ale
**jedno kliknutí kdesi jinde**, a aplikace to o sobě sama psala: u rozpracovaného PR stálo v panelu
*„Označ ho na GitHubu jako připravený.“* Od #482 je z té půlky věty tlačítko a věta se zkrátila.

**Kreslí se jedině u vlastního draftu, a to přes celou šířku panelu** — nad řadou `Mergnout…` /
`Rebase`, protože se do ní nevejde: tři tlačítka vedle sebe potřebují 273–274 bodů, což je celá
šířka obsahu panelu (274 b) a o ~60 bodů víc, než na kolik panel má, když se stáhne na svou podlahu
(214 b). Nad otevřeným, zavřeným ani mergnutým PR není v sekci o řádek víc; není tam co přepínat.

**Odesílá se hned, bez potvrzení, ale s větou pod tlačítkem.** Potvrzovací okno je v aplikaci tam,
kde je **co číst** (tělo review, plán merge); tady je payload jeden bit. Nevratná část na tom ale
je — GitHub při přepnutí **vyžádá review od vlastníků kódu** a to se odebráním nevezme zpět —, takže
pod tlačítkem stojí *„Kdo je v `CODEOWNERS`, dostane vyžádání review. Zpátky do draftu se chodí na
GitHub.“* a tlačítko **není výchozí akce**: `Enter` z draftu nic nepřepne.

**Zpátky do draftu odsud nejde a nepůjde.** Tlačítko, které by viselo u každého vlastního PR kvůli
akci jednou za pololetí, je mrtvá váha; na GitHubu je to jeden klik.

**Po úspěchu se stav PR načte znovu**: tlačítko i výstraha o rozpracovanosti zmizí a `Mergnout…` se
rozsvítí, když nic jiného nepřekáží. **Záložka zůstává otevřená** — na rozdíl od merge, kde ji
zavírá tentýž klik: tady se PR teprve předává ostatním. Když volání spadne, je pod tlačítkem věta
proč a `Zavřít`; stav se v tom případě znovu nenačítá, takže se to dá zkusit hned znovu.

### `Rebase` a `Force push` — jediné místo, odkud aplikace zapisuje do remote (#466)

Druhá věc, kvůli které se od hotového review chodilo do prohlížeče: **`main` mezitím ujel a větev
se musí srovnat.**

**Jsou to dva kroky, a dělí se podle vratnosti.** `Rebase` udělá **rebase v kopii repa
v cache aplikace** a **do remote nesáhne** — je to vratná práce, takže stojí na jedno kliknutí a co
udělá, stojí v nápovědě pod kurzorem. Force push je nevratný, takže se **potvrzuje zvlášť**:
`Force push…` otevře sheet, ve kterém je vypsané, co odejde (větev, kolik commitů, jaká hlava
z rebase vznikla a na jakou hlavu čeká pojistka), k tomu výstraha o tom, co se stane při pohnutém
remote — a tlačítko `Force push` **není výchozí akce**, takže `Enter` historii větve nepřepíše.

**Do #466 aplikace do remote nezapisovala vůbec.** Je to proto jediná akce svého druhu a drží ji
dvě pojistky, které platí obě:

- **Cílem smí být jedině hlava pull requestu, jehož autorem jsem já** — a posuzuje se to proti
  **datům pull requestu**, ne proti jménu větve. Jméno se dá nastavit na cokoli, takže shoda jména
  by byla kontrola, která jenom vypadá jako kontrola. Ověřuje se autor, stav PR, jméno větve, hlava
  a **jestli hlava neleží ve forku** — u PR z forku by push mířil jinam, než na co se člověk dívá,
  takže se odsud nedělá.
- **`--force-with-lease`, nikdy holé `--force`.** Když se větev na GitHubu mezitím pohnula, push
  **selže a nic se nepřepíše**; v panelu je pak věta, že se nic nestalo a že to jde zkusit znovu po
  obnovení. Je to jiná věta než u ostatních selhání schválně: z odmítnuté pojistky plyne „zkus to
  znovu“, z odmítnutého přihlášení něco jiného.

**Nabídne se jen na vlastním otevřeném PR se zapnutým odesíláním a jen když je větev pozadu.**
Rozpracovaný PR (draft) se srovnat smí — je to zrovna ten, na kterém se pushuje nejvíc — a **červený
check srovnání nebrání**, protože srovnat větev je zrovna to, co se s ním dělá. Když je větev nad
základem, tlačítko to řekne (`Větev je nad main — není co přehrávat`).

**Když se hlava po rebasu nezmění, do remote se nesáhne** a v panelu stojí `Větev už nad základem
byla, do remote se nesáhlo` — ne „přetlačeno 0 commitů“.

**Mezi krokem jedna a dva je stav, ne mezikrok.** Po rebasu stojí v panelu `Srovnáno v kopii repa —
4 commity přehrané. Do remote se zatím nesáhlo.` a k tomu dvě tlačítka: `Force push…`
a `Zahodit rebase`. **Zavřít se ta hláška nedá schválně** — zavřít ji by tu práci schovalo, aniž by
zmizela. Dá se v tom stavu zavřít okno a přijít za hodinu: **hledá se v kopii repa při každém
otevření vlastního PR**, takže se o ní okno dozví i po restartu. A **druhý rebase se nad ní
nenabízí**, protože přehrát commity znovu nad výsledkem, který neodešel, by tu práci zahodilo
potichu.

**Konflikt je stav, ne chyba** — a od #467 ho **slije session** (viz níž). Zůstává to pravda i tam,
kde se slévat nemá čím: bez `claude` se rebase **zahodí** a v panelu je napsané, na kterých souborech
uvázl (nejvýš tři jména). Rozdělaný rebase v kopii repa je napsaný taky — s tlačítkem **`Zahodit
rebase`**, protože tichý rozdělaný stav v cache je horší než chyba: příští akce nad tím pull
requestem by se nad ním zachovala divně. Hledá se přitom **při každém otevření vlastního PR**, ne jen
po neúspěšném pokusu — aplikaci zabitou uprostřed rebase nemá kde nic zapsat.

**Lease čeká na tu hlavu, ze které se rebasovalo** — ne na tu, kterou má PR v okamžiku potvrzení.
Mezi rebasem a potvrzením se hlava může pohnout (push z jiného stroje, z terminálu, z GitHubu)
a s aktuální hodnotou by pojistka takový commit přepsala; takhle se přetlačení odmítne a řekne, že
se hlava posunula.

**Záložka zůstává otevřená**, na rozdíl od merge: pull request žije dál. Detail a stav větve se ale
načtou znovu, protože se hlava změnila — nálezy proti staré hlavě se tím stanou zastaralými, stejně
jako po pushi z terminálu.

**Rebase běží ve vlastním pracovním stromě**, ne v tom, ve kterém běželo review — ten drží kód,
proti kterému nálezy platí a ve kterém stojí terminál v zásuvce. Nikdy se nesahá na klony mimo cache
aplikace.

### Konflikty slije session — a výsledek se ukáže dřív, než se cokoli přetlačí (#467)

Bez konfliktu je `Rebase` nudný. Ten druhý případ do #467 skončil zašedlým tlačítkem a větou
*„Konflikty odsud zatím vyřešit neumím“* — tedy návodem, jak z okna odejít. Od #467 na něj aplikace
pustí **headless session Claude Code, která smí měnit soubory** — jedinou svého druhu v celé
aplikaci.

**Session upraví soubory. Commituje aplikace.** `git add` a `git rebase --continue` dělá aplikace;
session nemá `Bash`, takže si `git` spustit nemůže. Dvě věci, které commitují, by se rozešly.

**Co ji drží** (a je toho víc než prompt — ten je pojistka, ne brána):

- **`Write` a `Edit` jen v tom stromě v kopii repa, kde rebase uvázl.** Změřeno, že holé povolení
  `Write` píše **kamkoli**; posílá se proto **s vypsaným rozsahem**, a že strom leží v cache
  aplikace, ověřuje tatáž kontrola jako u pushe.
- **Žádný `Bash`** — první session tady, která ho nemá. Chybějící `git` nahrazuje `zdiff3`, po kterém
  je v konfliktní značce vidět i **základ**, ne jen obě strany.
- **Žádné `gh`, `git push` dál v zákazu.** Pushuje aplikace, přes protokol, s bránou a s potvrzením.
- **Když by session psala mimo strom, výsledek se nepřijme** — `git add` ani `--continue` neproběhnou
  a v panelu je napsané proč.

**Výsledek se ukazuje dřív, než se cokoli přetlačí**, a je to **tentýž sheet** jako u bezkonfliktní
cesty, jen s obsahem navíc:

- **`Co s tím session udělala`** — které soubory kolidovaly a co s nimi udělala (`vzala obojí`,
  `ruční slití`, `beze změny`). Rozsah a pořadí výpisu drží **`git`**: soubor, o kterém session mlčí,
  dostane `beze změny`, a soubor, ve kterém `git` pořád vidí značky, dostane `nevyřešeno` **bez
  ohledu na to, co o něm session tvrdí**.
- **Čím si session není jistá** — vlastní řádek, protože je to nejcennější věta z celého výsledku.
- **Kolik to stálo.** Do `Dneska stálo` se to počítá jako každá jiná session.
- **`Co z toho vzniklo`** — **diff, ne popis**. Je za výstrahou o lease schválně: uprostřed sheetu
  by celý payload i tu výstrahu odrolil pod hranu.
- V patce **`Terminál`** a `Zahodit rebase`. **Bez kliknutí na `Force push` se nepushuje nic.**

**Co nerozřeší, nechá být.** Nedokončený rebase zůstane v kopii repa, panel řekne, čím to bylo,
a nabídne **`Otevřít v terminálu`** — zásuvka se otevře **v tom stromě, kde to uvázlo**, takže je
kontext připravený a plnou moc má člověk. Platí to i pro `Zrušit` uprostřed slévání: co už session
slila, zůstane a jde to zahodit tlačítkem. **Uhádané slití, které projde testy a rozbije se
v provozu, je horší výsledek než přiznané „na tohle nestačím“.**

**Kol je nejvýš tři.** Rebase se zastaví u každého kolizního commitu a každé kolo je vlastní session,
tedy vlastní útrata; u čtvrtého je poctivější nabídnout terminál než platit dál. Během slévání je
v panelu vidět kolo, počet souborů a **co session dělá právě teď**.

Segmenty jsou od #242 **dva**: `Průběh` se odstěhoval do vlastní záložky PR, protože se u kódu
nečte a u spadlé session se do 300 bodů nevešel ani důvod, ani konec logu. Nálezy v panelu
naopak zůstávají — tab `Nálezy` je druhý pohled na tu samou věc, ne přesun.

**Na vlastním PR je vedle nálezů `Zadání`, ne `Moje review`** (#333). `APPROVE`
i `REQUEST_CHANGES` na vlastní pull request GitHub odmítá (422, změřeno u #62), takže verdikt
a `Odeslat` tam **zmizí celé** — zašedlé tlačítko svádí na něj kliknout a přečíst si chybu. Místo
nich panel sbírá, co je potřeba opravit, a skládá z toho **jedno zadání pro agenta**: nálezy
reviewerů, vlákna u řádků, komentáře pod PR a souhrny review. Sedm zaškrtávacích voleb s počty říká,
co v textu je; vyřešená vlákna a odmítnuté nálezy v něm nejsou, ale **je u nich vidět, kolik jich
je**, a dají se přibrat. `Sestavit prompt →` (nebo `⌘⇧P`) otevře okno s celým markdownem, ze kterého
se dá text zkopírovat nebo uložit do souboru. To okno je **širší než ostatní sheety** (1080 bodů proti
720 u ostatních): obsah je markdown s fenced diffy, a na užším se zalamoval skoro každý řádek —
zalomený diff se přestane číst jako diff. Text se **nikam neodesílá**, cesta ven zůstává jen jedna
(viz *Odeslání review*). Proto tu taky **není druhé potvrzení**: dvě kliknutí na dvou tlačítkách jsou
brána proti tomu, aby něco odešlo na GitHub, a zkopírovaný text nikomu nic neudělá.

**V tom okně se vybírá po položkách, ne po druzích** (#377). Zaškrtávátko má **každý** nález, vlákno,
komentář i souhrn review; seskupené je to po druzích a v hlavičce grupy stojí `2 z 3`, tedy kolik z ní
je vybrané. U položky je vidět **autor** a `soubor:řádek` — podle toho se pozná, co je signál —
a rozklik ukáže **celý text** i s hlavičkou `druh · autor · čas · velikost`; dlouhý se roluje, nekrátí.
Volby po druzích zůstávají v panelu jako **hrubý filtr** a přibyl u nich počet vybraných.

**Vypnuté předvybírá aplikace a píše proč**: `napsal jsi to ty` (vlastní komentář — typicky release
notes, které jsou nejdelší blok v promptu a agentovi neříkají nic), `bez obsahu` (souhrn, ve kterém
kromě nadpisu nic není) a `shrnuje diff` (Copilotův `Pull request overview`, tedy převyprávěný diff,
který agent má sám). Vedle nich zůstávají `odmítl jsi ho` a `vyřešeno`. **Vypnuté položky zůstávají
vidět a jdou zapnout** — a co se nakonec vynechalo, je nad textem vypsané odznakem s důvodem
(`1 vlastní vynechán`), protože tiché zahození vypadá jako „tohle je všechno“. Náhled je **funkcí
výběru** a je to pod ním napsané: `Přepočítáno podle výběru — 6 položek, 2,8 kB. Odškrtnuté v textu
nejsou.` Výběr **nepřežije zavření okna**: sheet se otevírá k jednomu předání a předvybrání se počítá
z dat, takže ukládat ho by znamenalo další stav u PR, který zastará pushem.

Text je seskupený **po souborech, ne po zdrojích** (agent otevírá soubor, ne revieweera), u každé
položky je napsané, odkud přišla — podle toho se pozná, komu se dá odpovědět —, a co soubor nemá
(souhrn review, komentář v diskuzi), stojí ve vlastní sekci před nimi. V hlavičce textu je **hlava
PR**, protože nálezy platí proti ní a zadání se předává dál. Když konverzace není načtená, je to
napsané v panelu i v textu: prázdný počet vláken nesmí vypadat jako „nikdo nic nenapsal“.

**Rozdělané review se na vlastním PR nezakládá** — tlačítka, kterými by vzniklo (převzetí nálezu,
poznámka, komentář u řádku, tažení rozsahu), tam **nejsou**, protože odeslat ho není kudy. Co tam
zbylo z dřívějška, ale nezmizí: je vidět v panelu `Zadání` i v bublinách u kódu a jde smazat.

**Předáno není hotovo** (#334). Zkopírováním nebo uložením textu se u pull requestu zapíše razítko —
**kdy, proti jaké hlavě a co v tom zadání bylo** — a od té chvíle se okno ptá „zbývá tu ještě něco,
co jsem nepředal?“ místo „je tu něco?“. Odznak sekce `Moje PR` proto po předání **zhasne, i když
nálezy dál existují**, a pilulka `N k předání` v řádku zmizí; rozsvítí je zpátky nový nález, nový
komentář, cizí odpověď v už předaném vlákně, nebo nový commit. Razítko je **lokální stav v cache**,
ne značka na PR — na GitHub se tím neposílá nic.

Když agent opraví a pushne, panel to řekne sám: *„Předával jsi proti `9c1de02`, mezitím přišly
2 commity. Nálezy platí pro starý kód — než sestavíš nové zadání, pusť review znovu.“* Počet commitů
se píše jen tehdy, když se dá spočítat (po force pushi se předaná hlava v seznamu nenajde, takže tam
stojí jen „hlava PR se posunula“). **Zastaralé nálezy nemizí** — zůstávají v diffu i v tabu `Nálezy`,
jen se do nového zadání nepředvybírají. Vedle hlavního `Pustit review znovu →` je proto druhá cesta,
`Sestavit i tak (jen nové vlákno)`: nové vlákno od kolegy se dá předat i bez nového review a bývá to
nejrychlejší kolo. **Review se po pushi nepustí samo** — automat se vlastních PR netýká vůbec, protože
na nich se pushuje často a každý commit by spustil kolo, které nikdo nečte.

Do #182 byl panel **pod** diffem, kde si bral výšku — tedy to, čeho je u kódu nejmíň. Napravo bere
šířku, které je v okně přes celou obrazovku dost: v pohledu pod sebou zbude i na 14" displeji 126
znaků na stranu, takže slib „PHP na 120 znaků se vejde“ platí dál. **Složit ho jde na ⌘2** nebo
šipkou v jeho hlavičce; složený je proužek na hraně s počtem nálezů, který zčervená, když mezi
nimi něco blokuje. Šířka se táhne za levou hranu a pamatuje se.

**Nález je karta se závažností na hraně** (#175): červená blokuje, oranžová je běžný nález,
šedá odmítnutý — tatáž škála jako v řádku fronty, aby seznam a panel neříkaly o téže věci každý
něco jiného. Nahoře `blokuje · kategorie · reviewer`, pod tím shrnutí na tři řádky a dole místo
v kódu, ořezané **zepředu**, ať zůstane vidět jméno souboru a číslo řádku. Karta, na které stojí
procházení šipkami, má rámeček a popisek `tady jsi`, takže je z panelu i z lišty nad diffem
poznat totéž místo.

Do #175 to byla řaditelná tabulka. **V panelu se řazení podle sloupců nevrátilo**, a je to
vědomé: ve 300 bodech se sloupce nemají kam vejít — kategorie, místo a shrnutí se praly o místo
a odmítnutí muselo skončit jako odznak u kategorie. Platí tam pořadí podle závažnosti, tedy to,
v jakém se nálezy mají číst. **Tabulka se vrátila u #242, ale ve vlastní záložce** přes celou
šířku, kde je sloupců dost, viz níž.

### Záložka `Zeptat se` (#452)

**Rozhovor s Claudem nad tímhle pull requestem.** Reviewery odpovídají na to, na co byly puštěné;
při čtení diffu ale vzniká druhá otázka — *proč tohle vůbec dělá*, *co z těch nálezů je doopravdy
problém*, *co se stane, když se to mergne* — a ta se do #452 musela odnést do prohlížeče nebo do
terminálu.

**Je to rozhovor, ne jednorázový dotaz.** Druhá otázka navazuje na první, protože je to **jedna
session na pull request** držená přes `--resume`; bez toho by se každá otázka ptala znovu na
všechno a odpovědi by si protiřečily. Rozhovor se ukládá **k PR, ne k `headSha`** — nálezy hlava
zneplatní schválně, ale otázka „proč se ten mutex bere“ pushem nezastará —, takže přežije zavření
záložky, nový commit i restart aplikace.

**Čte, neodesílá — a je to napsané v okně, ne jen v dokumentaci.** Session má **užší** sadu
nástrojů než reviewer: `Read`, `Grep`, `Glob` a `Bash(git:*)`, se zákazem `Bash(gh:*)` i `git push`
a **bez** `ReportFindings` (nemá co hlásit) a **bez** `Skill` (skill načtený za běhu si umí říct
o odeslání na GitHub). Pracuje ve **vlastní kopii repa** v cache aplikace, tedy v tomtéž worktree,
jaký dostal reviewer; na uživatelovy klony nesahá. Kdo z odpovědi chce komentář na PR, pošle ho
**tou jednou cestou ven**, kterou okno má: composerem v `Konverzaci`.

**Kontext je materiál, ne nástroj.** Popis PR, nálezy, konverzace a checky si session nedotahuje
sama — k tomu by potřebovala `gh`, a ten se nedá povolit jen na čtení. Aplikace je složí do souboru
vedle pracovního stromu a do promptu jde **cesta k němu**, ne obsah (tentýž precedens jako zadání
pro reviewera). Diff v tom souboru není: session si ho přečte `git diff base...HEAD`, tedy toutéž
cestou jako reviewer. Co do promptu doopravdy jde, stojí **nahoře a jednou** — pruh `ví o tomhle
PR:` s počty souborů diffu, nálezů, komentářů a checků.

Nahoře vpravo je kapsle `čte · neodesílá`, dole composer s větou *Čte kód ve své kopii repa.
Odeslat na GitHub neumí.* Odesílá se tlačítkem `Zeptat se` nebo **`⌘⏎`** — v tomhle tabu je proto
zkratka okna na potvrzení odeslání review **zakázaná**, aby klávesa propadla composeru. Během
odpovědi se z tlačítka stane **`Zastavit`**: jedna odpověď stojí kolem dolaru a běží minuty, takže
„rozmyslel jsem si to“ nesmí znamenat čekat na konec.

Bubliny, ne karty: moje otázky vpravo na akcentu, odpovědi vlevo na tichém podkladu, **co si
přečetl** nad odpovědí a **čas a cena** drobně pod ní. Že se zrovna odpovídá, nese **prstýnek na
místě příští bubliny** i s tím, co session právě dělá (`čte SecretClient.php`). Odpověď smí odkázat
na **soubor a řádek** — pod prózou stojí kapsle `→ SecretClient.php:80` a klik skočí do `Změněných
souborů` na to místo.

**Prázdný tab nabízí otázky k odpíchnutí** jako přerušované kapsle a **klik je rovnou odešle** —
jedno kliknutí je celý jejich smysl. Nejsou to schopnosti, je to nápověda, co tab umí; přepsat se
dají tím, že se místo kliknutí napíše vlastní otázka do pole pod nimi. **Nabídka se řídí tím, co na
PR doopravdy je**: když má pull request nálezy, je mezi otázkami ta, která je nechá prověřit, a se
**stejným počtem**, jaký hlásí pruh `ví o tomhle PR:` o kus výš. Bez nálezů se nenabízí — ptala by
se na nic.

**Rozepsaná otázka přežije překliknutí tabu** i přepnutí na jiný PR: pole si ji drží samo a do
paměti aplikace ji uloží, až když tab zmizí. Odeslaná otázka z pole **zmizí** (jinak by se dala
odeslat a zaplatit podruhé), a když se neodešle, **zůstane** — přijít o napsanou otázku je horší
než ji tam mít.

**`Nový rozhovor`** vpravo nahoře zahodí rozhovor i navázanou session, takže příští otázka začíná
načisto. Smaže i to, co není vidět — uložený rozhovor v cache a id session —, a proto **se ptá**:
odpověď stála kolem dolaru a zpátky se nedá dostat ani zopakovat za stejné peníze. V prázdném tabu
tlačítko není, protože nemá co zahodit; rozepsané otázky v poli se netýká.

**Utrácí to, a je to vidět.** Cena každé odpovědi se počítá do `Dneska stálo` ve stavovém řádku
jako všechno ostatní. **Strop se nedává** — sazbu si člověk řídí tím, kolik se ptá; skrytá útrata
je horší než drahá.

### Terminál v zásuvce (#459)

**`` ⌃` `` vytáhne přes spodek záložky shell**, který stojí v **kopii repa toho pull requestu**
v cache aplikace. Do #459 se dal terminál otevřít jedním tlačítkem v tabu `Průběh` (#453), jenže
to pořád znamená **odejít z okna**: kdo se během review potřebuje podívat na `git log`, pustit test
nebo dopsat otázku do běžící session, odejde a vrátí se za deset minut. Od #460 do zásuvky míří
i to tlačítko: `▶` v tabu `Průběh` v ní rovnou pustí `claude --resume` (viz níž).

**Zásuvka, ne devátá záložka**, a je to celý smysl: půlka užitku je, že je vidět diff a **pod ním**
výstup příkazu. Roztahuje se **tažením za horní hranu** a výška si pamatuje mezi spuštěními; nad
zásuvkou vždycky kus obsahu zůstane, jinak by se z ní stala ta záložka.

**Je to skutečný emulátor** — pty a VT/xterm, ne zjednodušený výpis: `claude --resume` v ní vypadá
jako v Terminálu, včetně kurzoru, barev a překreslení při změně velikosti okna. Stojí za tím
[`SwiftTerm`](https://github.com/migueldeicaza/SwiftTerm), jediná závislost třetí strany v tomhle
repu.

**Tady končí „aplikace nemá čím odeslat“, a je to napsané na obrazovce.** V hlavičce zásuvky stojí
kapsle **`plná práva`** — protějšek `čte · neodesílá` z tabu `Zeptat se`. Aplikace **sama** dál nic
neodesílá a odesílat umí jedině tou jednou cestou (`ReviewPublishing`), jenže ze shellu jde
`gh pr merge` i `git push` a to už neuhlídá žádný test: plnou moc má v zásuvce **člověk**.

**Klávesy patří terminálu.** Dokud má zásuvka fokus, okenní zkratky **bez `⌘`** se neuplatní —
`⌃W` v terminálu maže slovo, `⌃C` přerušuje běh, `⌃1`–`⌃5` a `⌃⇥` patří tomu, co uvnitř běží, `⎋`
vyskakuje z vimu. Jediná zkratka, která platí dál, je `` ⌃` `` sama; jinak by se zásuvka nedala
zavřít klávesnicí. Na české klávesnici funguje i **`⌃;`** — je to táž klávesa vlevo od `1`.

**Co aplikace spustila, to i ukončí.** Zavření okna se na běžící shell **zeptá** a po odpovědi ho
zabije — a ne jenom shell: zabíjí se **popředí pty**, takže odejde i `claude`, který v něm běží
(job control mu dává vlastní process group, kterou by signál shellu minul). Zabitá aplikace na to
nemá kde dojít, takže se běžící shell zapisuje do `sessions.json` a osiřelý zabije **další start**,
stejně jako u review (#351). **Zavření záložky** shell zabije taky; **schování zásuvky ne** —
`` ⌃` `` je pohled, ne konec práce.

**Relací je v zásuvce víc, ne jedna** (#460). Aplikace pouští review **paralelně**, takže „jedna
zásuvka = jeden shell“ by nutila jednu session ukončit, aby byla vidět druhá — a to je zrovna ten
stav, ve kterém se na ně chce člověk dívat. Přepíná se **záložkami** v hlavičce; puntík u záložky
nese, jestli v ní něco běží (a **červený** znamená, že to skončilo nenulově — celý kód je
v nápovědě). `shell` je jedna z relací, ta, kterou dá `` ⌃` ``.

**Relace jsou vázané na pull request**, protože pracovní adresář je checkout **toho** PR. Drží se
jich nejvíc **pět**; když je plno, vytlačí se **nejstarší doběhlá**, a když všechny běží, nová
nevznikne a řekne se to. Zavření záložky PR zabije **všechny** jeho relace. Když v cache žádná kopie
repa není, zásuvka to místo prázdné plochy řekne — terminál bez repozitáře je obyčejný shell a ten
má člověk vedle.

**Známé omezení proti návrhu:** v hlavičce není napsaný příkaz, který zrovna běží — jen puntík
u záložky. Zjistit ho znamená ptát se jádra na popředí pty v pravidelném taktu, tedy další časovač
v okně kvůli popisce.

**Změna velikosti je změřená** (#460): šířka okna dojede přes SwiftUI do emulátoru i do jádra
(buňky i pixely) a `TIOCSWINSZ` chodí jen na skutečnou změnu, ne na každý průchod rozvržení. Co je
při zúžení vidět jako přeskládaný text, je **reflow scrollbacku** — `SwiftTerm` přesází jen
normální buffer, kdežto alternativní (do kterého kreslí celoobrazovkové TUI) nechá být. Tak se
chová `Terminal.app` i `iTerm`.

### Záložka `Nálezy` (#242)

**Přes celou šířku se nález nasází jako tabulka**, což ve 300 bodech nešlo: na jeden řádek se vejde
závažnost, shrnutí, místo, `reviewer · kategorie` a akce. **Řadí se kliknutím na hlavičku sloupce**
— první kliknutí tak, jak se sloupec čte (závažnost od nejvážnějšího, text od „a“), druhé otočí.
Odmítnuté zůstávají naspod ať se klikne na cokoli: nálezu, kterému nevěřím, nemá konkurovat
platnému ani v cizím řazení.

**Řádek je místo, ne nález.** Když se dva reviewery potkají na jednom řádku kódu, je z toho jeden
řádek s odznakem `2×` — dva řádky by tvrdily, že jsou to dva různé nálezy. Souhrn nad tabulkou
proto počítá **nálezy** (`4 nálezy · 1 blokující · 3 místa`), a je to tentýž počet, jaký je na
odznaku záložky a jaký je v diffu v bublinách; počítá ho `Policy` na jednom místě.

**Kliknutí na shrnutí skáče do diffu** — přepne záložku a odscrolluje, tedy tentýž pohyb jako
odkaz na nález v `Přehledu`. Šipka na konci řádku ho **rozbalí**, a to do **té samé bubliny**,
jaká visí u kódu: celé texty, „Kdy to selže“, `Převzít do review` a odmítnutí u každého nálezu
zvlášť. Ve sbaleném řádku je odmítnutí v `⋯` — vědomý rozdíl proti bublině, kde jsou dvě tlačítka
vedle sebe: v tabulce by se šest ovladačů opakovalo na každém řádku a přebily by shrnutí, kvůli
kterému se tabulka čte.

**Panel vpravo je tady schovaný** (#294) — je to tatáž sada nálezů přes celou šířku, takže by vedle
sebe stály dvakrát. Smyčka nález → `Převzít` → text v mém review to nezruší: `Převzít` si přepne do
tabu, ve kterém panel je, a rozepsaná věta tedy skončí na obrazovce. Do #294 tu stálo, že panel
zůstává, protože se ta smyčka musí stát naráz — děje se pořád naráz, jen o tab vedle.

A **prázdná tabulka vysvětlí, proč je prázdná**: schované filtrem reviewerů / reviewer nic
nenahlásil / session spadla (i se `stderr`) — prázdná obrazovka se totiž čte jako „čisto“, a
schválený PR s neohlášenou chybou je ta nejdražší chyba, jakou tohle okno umí.

V **nejmenším okně odpadá sloupec `reviewer · kategorie`**: je to jediný, jehož obsah je i v bublině
u kódu a v chipech reviewerů nad diffem. Šířka se přitom **předává, ne vyjednává** (#220).

**Falešně pozitivní nález se dá odmítnout, aniž bys zahodil ostatní.** V bublině jsou vedle
`Převzít do review` dvě tlačítka: `Neplatí` znamená „reviewer se mýlí“, `Nepatří sem` „má pravdu,
ale k tomuhle PR to nepatří“. Rozdíl stojí za dva knoflíky, protože první je vstup pro doladění
skillu nebo blokující sady a druhý ne; volný text u toho není, protože se nikam neodesílá a nikdo
by ho nečetl. Totéž jde z **kontextového menu** v tabulce (`Označit jako…` / `Vrátit mezi platné`),
kde se stav píše jako přídavné jméno (`neplatný`, `irelevantní`) — na tlačítku má být tvrzení,
v odznaku vlastnost.

Odmítnutý nález se **nepočítá do návrhu verdiktu ani do řádku seznamu** — jeden falešný nález
s `CONFIRMED` v blokující kategorii tak nedrží celý PR na `request changes`. **Nikam ale
nezmizí:** v bublině se sbalí na jeden řádek s odznakem důvodu a tlačítkem `Vrátit`,
v tabulce zůstane ztlumený naspod. Schovaný nález se nedá přečíst a nedá se odlišit od
neexistujícího — a když je to moje rozhodnutí, musím mít jak zkontrolovat, co jsem odmítl;
proto tu není ani přepínač „schovat odmítnuté“. Když jsi nálezy odmítl všechny, řádek
v seznamu ukáže `odmítnuto · N`, **ne `čisté`**: „reviewer nic nenašel“ je jiné tvrzení než
„našel a já to zamítl“. Návrh verdiktu to napíše taky (`1 odmítnutý nález se nepočítá`).

Ze stejného důvodu existuje **třetí stav vedle `čisté` a `selhalo`** (#383): review, které doběhlo,
ale čisto z něj neplyne. Odznak v seznamu řekne, co chybí — `kód nepřečten` (reviewer neotevřel ani
jeden soubor z pracovní kopie, pozná se to z jeho osy v tabu `Průběh`), `bez hlášení`
(`ReportFindings` nezavolal) nebo `ztracené nálezy` (něco nahlásil a nepodařilo se to přečíst) — a je
okrový jako `zastaralé`, protože je to výsledek, který se nedá použít, ne porucha. V prázdném tabu
`Nálezy` k tomu stojí věta i s tím, čím review pustit znovu. Vzniklo to z měření: `security-review`
hlásil v jednom týdnu nulu nálezů ve 12 ze 14 běhů, protože přestal chodit do kódu, a okno z toho
dělalo `čisté`. **Chybějící záznam ale obvinění není** — u běhu, ke kterému se osa neuložila (soubory
z doby před #203) nebo v ní jsou nástroje, u kterých není vidět, kam sáhly, zůstává stav, jaký byl.

Označení platí **jen pro ten commit** — nálezy jsou klíčované head commitem, takže nález
falešný nad starým kódem nemusí být falešný nad novým. Přežije to restart i **opakované
review týmž skillem**, které jinak celý předchozí výsledek přepíše. Odmítnutí u jednoho
revieweera nesundá nález druhého; odznak `2×` proto spadne na `1×`. A komentář, který jsi
z nálezu už převzal do svého review, se odmítnutím **nevyjme** — je to tvoje próza, vyjímá
se v `Moje review` a bublina to u takového nálezu napíše.

V hlavičce záložky `Nálezy` je **`Zahodit nálezy`**, kterým se uložený záznam zahodí — hodí se, když
se změnila sada skillů a v záznamu leží nálezy od revieweera, který už neběží. Je to hrubší nástroj
než odmítnutí: maže celý záznam viditelného commitu, historie starších zůstává, a na repu
v automatickém režimu se review vzápětí pustí samo. Ptá se proto na potvrzení a za běhu je zakázané
— doběhlý skill by se zapsal do právě vyčištěného záznamu. **Do #242 to byl koš v liště panelu**;
odstěhoval se spolu se stářím výsledku, protože obojí platí pro uložený záznam, ne pro panel, a
o 300 bodů se pralo s tím, co se čte.

**Zavřít aplikaci během review se musí potvrdit.** Ukončení session zabije a nálezy, které
už reviewer nahlásil, se ztratí — z řádku pak vyjde `neběželo`, tedy totéž jako u PR, který
nikdo nekontroloval. Dialog nabídne `Zpět` (výchozí) a `Ukončit`; co doběhlo, zůstává
uložené. Pád aplikace ani zabití zvenčí takhle odchytit nejde, proto to `bin/run.sh` při
rebuildu neobchází a aplikaci ukončuje tou samou cestou jako ⌘Q.

Nad diffem jsou **chipy reviewerů**: u každého je vidět, co udělal (`3 nálezy`, `čisté`,
`běží`, `selhalo`, `nejisté`) a kliknutím se jeho nálezy schovají z bublin i z tabulky.
Vpravo je **návrh verdiktu** — je to doporučení, ne akce. Sám nic neodešle; odeslat review
umí jedině člověk, a jedinou cestou (viz úvod). Tentýž návrh **předvyplní verdikt** v tabu
`Moje review`, takže se u něj pozná, jestli hodnota je z nálezů, nebo moje.
Filtr návrhem nehýbe, aby se schováním revieweera nedal „vyrobit“ approve.

**Když ze tří reviewerů jeden spadne, jde pustit znovu jen on** — pravým tlačítkem na jeho chip.
Za výsledky ostatních, které už leží na disku, se tím neplatí podruhé; jejich nálezy i průběh
zůstávají. Dokud nad PR nějaké review běží, je ta položka zakázaná: je to jedna úloha na pull
request.

V záložce **Průběh** má každý reviewer **vlastní dráhu** (#242): fáze `čeká na slot` /
`session` / `prochází kód` / `hlásí nálezy` vedle sebe, takže „kdo je hotový, kdo běží a kdo
spadl“ je jeden pohled. Do #242 to byly karty pod sebou v panelu 300 bodů širokém, ze kterých se
to muselo sesbírat scrollováním.

**Fáze jsou z toho, co v ose doopravdy je.** Fáze za tou, kam se běh dostal, zůstává nedotčená
i u úspěšně doběhlého běhu: reviewer, který `ReportFindings` nezavolal, nálezy **nenahlásil**, a to
není totéž jako nula. Pod dráhou je věta o tom, co se právě děje (`Právě: Read src/Cart.php`) nebo
čím to skončilo — a ta rozlišuje tři různé konce: nahlásilo nálezy, nahlásilo prázdný seznam
(čisto), nenahlásilo nic.

**Spadlá session dostane důvod, `stderr` a dvě tlačítka** — `Pustit znovu` a `Zkopírovat příkaz`
(příkaz, jakým by se ten reviewer spustil teď, k vložení do terminálu). Do #242 se v panelu lišila
od proběhlé jen barvou odznaku, protože na důvod ani na konec logu nebylo místo — a `čisté`
a `spadlo` se slít nesmí.

Podrobný výpis toho, co reviewer spouštěl — který soubor čte, co hledá, jaký příkaz spustil —
je pod rozbalením každé dráhy. Skládá se nativně z eventů, ne přeposíláním textu, takže se dá
číst i bez terminálu; když je potřeba se do session vrátit, zkopíruje se `claude --resume <id>`
jedním tlačítkem — nebo se od #453 rovnou **pustí** (do #460 v `Terminal.app`, od #460
v zásuvce), viz níž. Osa zůstane i po doběhnutí běhu — a od #203
**přežije i restart aplikace**: ukládá se k běhu, takže se k ní dá vrátit druhý den i s tím
`sessionID`. Delší běh nadělá stovky událostí, proto se drží posledních 300 a kolik se jich
nevešlo, je u rozbalení vidět; ořezává se **začátek**, protože se do osy kouká kvůli tomu, čím
to skončilo.

**Krok v ose je pokus, dokud nedorazí odpověď** (#326). U hotového kroku stojí vpravo trvání
(`0,2 s`), u toho, na který odpověď ještě nepřišla, `běží…` — a u odmítnutého odznak `ODMÍTNUTO`.
Odmítnutí **není chyba běhu**: reviewer je read-only, takže `Bash(gh:*)` se odmítnout **má**
a session přesto skončí úspěchem; proto je to štítek u kroku, ne červený řádek. Chyba nástroje
(`grep` bez shody, čtení souboru, který není) se od odmítnutí liší — vypadá jako hotový krok a co
nástroj vrátil, je v nápovědě řádku. Do #326 se odmítnutí poznalo až ze závěrečného souhrnu session,
tedy o minuty později, a do té doby okno tvrdilo, že nástroj proběhl. Osy uložené dřív značku
nemají, protože se jejich krokům nemá s čím párovat — a `běží…` u doběhlého review by tvrdilo víc,
než ta data unesou.

**Když výpis kroků nestačí, je pod ním záchranná brzda: `Ukázat session`** (#327). Výpis
kreslí jen nástroje — odpovídá na „koukal se tam, kam měl“. Na jinou otázku (*proč to dopadlo
takhle*, *co dělal, než to spadlo*) odpovídá to, co výpis schválně zahazuje, a to je v sheetu
s **přepisem celého transcriptu**: próza modelu, jeho uvažování, výstupy nástrojů a systémové
události. Tlačítko je v hlavičce výpisu **i v jeho sbaleném řádku** — doběhlá dráha je ta častější —
a bez známého `session_id` **nebo bez pracovního stromu** se nekreslí (z těch dvou se odvozuje cesta
k souboru), stejně jako u `Zkopírovat resume`.

Přepis je **snímek k okamžiku otevření**, ne živý pohled: v hlavičce je to napsané, patička hlásí,
kolik od té chvíle přibylo, a vedle je `Načíst znovu`. Sledovat rostoucí soubor umí výpis o patro
výš; dvě věci nad touž session jsou dvě místa, kde se dá splést pořadí. Kreslí se z něj **okno
posledních 4 MB** a jedna událost má strop **8 kB** — obojí je změřené na 922 transcriptech na disku,
kde největší má 53,3 MB a nejdelší jeden řádek 7,5 MB. Protože je soubor lokální, čte se od konce
a **stav „moc velký“ nevzniká vůbec** (u logu z Actions ho vynutila síť). Zkrácení se přiznává
**třikrát**: v hlavičce, řezem na začátku textu a u ořezané události na místě řezu; base64 obrázku se
nevypisuje nikdy, jen se přizná, že tam je a kolik váží.

**Sheet se dá roztáhnout za okraj a velikost si pamatuje** mezi otevřeními — u přepisu s dlouhými
řádky je „jak široké to mám“ půlka užitku. Otevírá se na 1 180 × 760 bodů (ořezáno o okraje
obrazovky, takže se na menším displeji nevejde přes hrany), pod 720 × 420 ho tažení nepustí, a jedno
tažení stojí 2,61 ms na krok i nad přepisem o 1,5 milionu znaků — text se při změně šířky jen přelámí,
nesází se znovu. Šířka není od oka: přepis zalamuje, takže ze 720 na 1 180 bodů ubude nad skutečným
transcriptem 15 % řádků sazby, dál už jen jednotky procent za sheet přes celou plochu.

**Že přepis není, má tři různé podoby, a každá nabídne něco jiného.** *Není* znamená, že soubor
na disku **není** — a je to konečná odpověď: bez `Načíst znovu`, a je u toho napsané, že tím padá
i `claude --resume`, protože čte tentýž soubor. Proč tam není (úklid cache, session ho ještě
nezaložila) se **netvrdí** — z chybějícího souboru se to nepozná. *Nedá se přečíst* nabídne opakování i `Ukázat v Finderu`, protože soubor
tam pořád leží. *Prázdný* nabídne opakování, protože u běžící session je to dočasný stav — prázdný
sheet by vypadal jako „session nic nedělala“. Do sheetu se **nepíše**: čte se, vybírá a kopíruje,
a cesta zpátky do session zůstává `Zkopírovat resume`.

**Do běžící session se dá vstoupit rovnou v okně** (#453, od #460 návrh sekce 35, poznámka 112).
Vedle `⧉` (zkopíruje `claude --resume <id>`) je `▶` — **`Pustit session v terminálu`**,
které vytáhne **zásuvku** (viz *Terminál v zásuvce* výš), přejde v ní **do pracovního stromu té
session** a pustí tam tentýž příkaz i s režimem povolení (viz níž). Strom je podmínka, ne
kosmetika: `claude --resume` hledá
vlákno podle adresáře, ve kterém se spustí. Kopírování **zůstává**: kdo si session pouští jinde
(iTerm, tmux, jiný stroj), potřebuje text — jsou to dvě akce, ne dvě podoby jedné.

**Do #460 se tím otevíralo okno `Terminal.app`.** Změnilo se to proto, že od #459 je terminál
v okně, takže odcházet do cizí aplikace kvůli session, která se dá pustit o kus níž, nemá důvod.
Co odchodu do `Terminal.app` zůstalo: session tam **přežije zavření PRismu**, kdežto shell
v zásuvce se s ním zabije. Cesta ven do `Terminal.app` je proto v kódu ještě chvíli **jako
záloha**; z okna se dnes nepoužije.

**Každá dráha má v zásuvce vlastní relaci**, takže `▶` u druhého reviewera tu první nepřebije —
přepne se na ni. **Když v té relaci zrovna něco běží, `▶` do toho nepíše**: řádka poslaná do
běžícího programu je pro něj vstup, takže by z `claude --resume …` byla zpráva odeslaná do
rozdělaného `claude`. Zásuvka se v tom případě jen přepne (běžící příkaz je zrovna to, na co je
potřeba se podívat) a ve stavovém řádku stojí, že se nic neposlalo. Když v relaci shell skončil,
`▶` ho pustí znovu — starý výpis v ní přitom zůstane.

**Session z `▶` běží v auto režimu** (`--permission-mode auto`), takže nepřerušuje práci dotazem
u každého kroku — klikáš na `▶` proto, aby se ptala tebe, ne abys odklikával dialogy. **Nová práva
to nedává**: zásuvka je plnohodnotný shell s kapslí `plná práva`, takže cokoli, co ta session
udělá, si tam můžeš napsat sám; odpadají dotazy, ne hranice. `⧉` ten přepínač **nekopíruje** — kdo
si příkaz pouští jinde, dostane ho tak, jak by ho psal.

**A neptá se na důvěru ke složce.** Interaktivní `claude` se v neznámém adresáři ptá *„Is this
a project you created or one you trust?“*, a protože každý PR dostane vlastní pracovní strom, přišel
by ten dotaz u každého PR znovu. PRism proto zapíše důvěru do `~/.claude.json` — je to cesta, na
kterou odkazuje sám `claude`. Zapisuje se **kořen cache i ta složka, ve které se shell doopravdy
pouští**: důvěra se sice dědí na všechno pod zapsanou složkou, ale **ne do git pracovního stromu**,
a strom review je právě to, kam `▶` míří. Sahá se jedině na složky, které si aplikace vyrobila sama;
na konfiguraci, které nerozumí, **nesáhne**, a když se zápis nepovede, přijde jen ten dialog.

**Rolovat jde v shellu i nad běžícím `claude`** (#478). V holém shellu se roluje 500 řádků vlastní
historie; nad celoobrazovkovým TUI, které si o hlášení myši řeklo, se kolečko **předá jemu** jako
tlačítka 64 / 65 — stejně jako to dělá `Terminal.app` a iTerm. Do #478 se nepředávalo, protože
`SwiftTerm` kolečko aplikaci nepředá sám, takže rolovat nad `claude` nešlo vůbec. K tomu druhá
polovina téže opravy: **odrolovaný pohled se přiteklým výstupem nesrovná dolů**, dokud se člověk
sám nevrátí na konec.

Nabízí se to **jen tam, kde je co obnovit**: bez `session_id` **a bez pracovního stromu** se
tlačítko nekreslí (ne zašedle — u dráhy, která teprve čeká na slot, by zašedlé slibovalo něco,
co přijde samo). **Nekreslí se ani tam, kde zásuvka není** — tichý pád zpátky do `Terminal.app`
by znamenal dvě různá chování pod jednou ikonou, tedy že se nedá spolehnout ani na jedno.

U doběhlého revieweera je v hlavičce **cena, trvání a počet kol** — `0,23 $ · 11,8 s · 3 kola`.
Bere se to z toho, co nahlásila sama session, takže **zabitý běh je nemá**: nula by tvrdila, že
byl zdarma. Součet za dnešek je ve stavovém řádku, viz níž.

Na spodku okna je **stavový řádek**: vlevo hlášky o stavu celé aplikace (rozbitá
konfigurace, pozastavený automat kvůli dennímu limitu, soubory, které se nepodařilo
přečíst), vpravo **útrata za dnešek**, kdy se naposledy něco ohlásilo, a puntík u GitHubu
a u Claude. Puntík odpovídá na otázku „je to na mojí
straně, nebo mají oni výpadek?“ ještě předtím, než se člověk začne prohrabávat chybou:

| Puntík | Význam |
|---|---|
| ○ šedá | zatím nezjištěno — po startu, dokud se něco nestane |
| ● zelená | žádný incident na komponentách, které používáme — a poslední skutečné volání prošlo, nebo ještě žádné neproběhlo (nápověda řekne které) |
| ● žlutá | provozovatel hlásí incident na komponentě, kterou používáme (i když volání procházejí) |
| ● červená | poslední skutečné volání selhalo — nebo je stroj bez sítě, což řekne nápověda |

Červenou určuje **skutečný provoz**, ne sonda: polling se ptá `gh` každou minutu a review
pouští `claude`, takže lepší signál se nedá koupit a nestojí nic navíc. Zelenou dá i samotná
čistá status page — šedá znamená „nevíme nic“ a tady něco víme; puntík Claude by jinak zůstal
šedý, dokud neproběhne první review. Žlutá jde
ze status pages provozovatelů ([GitHub](https://www.githubstatus.com),
[Claude](https://status.claude.com)) — sleduje se z nich jen to, co aplikace používá, takže
incident v `Actions` nebo `Packages` puntík nerozsvítí. Kontroluje se po deseti minutách,
podmíněným dotazem (druhý dotaz je `304` bez těla), po selhaném volání častěji a **na pozadí
vůbec** — aplikace, kterou nikdo nevidí, nemá komu svítit. Když se stav služby zjistit
nepovede, nic se nezablokuje: puntík se řídí voláními a nápověda po hoveru řekne, co se
nepovedlo a kdy se to zjišťovalo.

Chování se řídí souborem `config.json` v `~/Library/Application Support/PRism/`: zdroje
PR, **další „moje“ loginy** (`ownLogins`, #330), **organizace k prohledávání**
(`searchOrganizations`, #532), **jméno MCP nástroje, kterým se čte text issue**
(`issueTextTool`, #345), sada skillů, **prompt review**, **časový limit běhu**, blokující kategorie, výchozí režim
review, jazyk nálezů, povolení odesílání, notifikace, výchozí pohled na diff, vzhled okna, interval
pollingu, kolik session smí běžet naráz, denní strop automatu, rozpočet cache a model. Repozitář si
může přebít režim (`manual`/`automatic`), povolení odesílání, jazyk nálezů, skilly, kategorie
i časový limit — a nic víc: prompt, pohled na diff, vzhled okna a notifikace jsou vlastnost
člověka, ne repozitáře.

**Celá globální konfigurace se dá nastavit z okna** (#389). Poslední dvě hodnoty, které se do té
doby daly napsat jedině ručně do souboru, dostaly pole na stránkách, kam podle své otázky patří —
a to je celé rozhodnutí, které za tím je: `issueTextTool` je věc **review** a `ownLogins` věc
**identity**, takže společná sekce „ostatní“ by z okna udělala smetiště.

- **`Text issue z trackeru`** na stránce `Review a skilly`, hned pod promptem — je to materiál
  zadání, tedy tatáž otázka jako prompt. Pole je jedno, jméno nástroje se píše celé
  (`mcp__<server>__<nástroj>`; servery vypíše `claude mcp list`) a **pevný seznam ani výchozí
  hodnota tam být nemůže**: jméno závisí na tom, jak si člověk server pojmenoval, takže konstanta
  by byla tvrzení o cizím stroji. Pod polem stojí **věta o tom, co z hodnoty plyne** — u prázdného
  pole `Nevyplněno — text issue se netahá.`, u vyplněného `Tahá se — u PR s odkazem na issue běží
  session navíc.` a u jména bez prefixu `mcp__` **varování** (ne zákaz: aplikace jméno neumí
  ověřit, dokud session neběží). Prázdno je tedy **odpověď, ne nedodělek** — a přesně to je ten
  stav, který by z prázdného pole nikdo nepoznal.
- **`Moje loginy`** na stránce `Zdroje PR`, pod zdroji — tam se rozhoduje, čí PR je čí. Seznam se
  edituje týmž editorem jako skilly a nad ním je **přihlášený účet ke čtení**: bere se z `gh api
  user`, napsat se nedá, a bez toho řádku by prázdný seznam (běžný stav — kdo pushuje pod svým
  `gh`, druhý login nemá) vypadal stejně jako **nenačtený** login, tedy stav, ve kterém je každý
  PR cizí. Dokud se nenačte, stojí to u něj napsané.

`appearance` v nastavení schválně **není** — přepíná se v railu (#278) a druhé místo by se s ním
rozešlo.

**Organizace k prohledávání** (#532) jsou na stránce `Zdroje PR`, pod `Moje loginy` — je to seznam
míst, ve kterých se hledají **repozitáře podle jména**, ne další zdroj fronty. Rozdíl je celý v tom,
co z něj plyne: zdroje říkají, co se tahá pravidelně a co se počítá do karet, odznaku a automatu,
kdežto odsud se jen hledá, když chci otevřít nějaký PR ke čtení.

Seznam repozitářů každé organizace se **drží v cache** (`catalogs/<org>.json`), protože jeho
dotažení je drahé — nad `keboola` naměřeno **46,8 s** a 98 kB (`gh repo list --limit 1000` s počtem
otevřených PR; bez toho počtu 9,5 s). Z toho plyne, jak se obnovuje: **jednou denně, dopsáním
organizace nebo tlačítkem `Obnovit`** — a **nikdy při psaní**, protože `keboola` po písmenech je
sedm hodnot, tedy sedm takových výpisů. Pod seznamem stojí souhrn `412 rep · obnoveno 7:58` (bere
**nejstarší** razítko, protože je to tvrzení o celém katalogu) a organizaci bez snímku počítá
zvlášť — `1 organizace nenačtena`, aby součet mlčky nevynechal, co v něm není. Když repozitářů
přijde přesně tisíc, stojí tam `nejméně 1 000 rep`: `--limit` se dosáhl, takže jich je víc.

**Organizace, na kterou účet nevidí, dostane větu z `gh`** pod svým řádkem, ne prázdný seznam —
prázdno by vypadalo jako organizace bez repozitářů. Selhané obnovení přitom nezahodí, co už v cache
je, a jedna nedostupná organizace nezastaví ostatní.

**Časový limit běhu se dá nastavit** (#320) na stránce `Review a skilly`, v sekci `Režim review`.
Do té doby byl zadrátovaný v kódu (patnáct minut), takže dlouhé review skončilo `timeout`
a jedinou odpovědí bylo „pusť to znovu a doufej“. Platí **na jednu session** — tedy na každý skill
zvlášť a stejně tak na kontrolu nálezů; zabitý běh si přitom pořád nechá, co stihl nahlásit.
Rozsah je **5–60 minut** a „bez limitu“ mezi volbami **není**:

- **Horní mez je vazba na účet.** Timeout je jediná pojistka proti session, která se zacyklí —
  denní strop automatu a limit souběhu omezují **počet** běhů, ne délku jednoho. Strop krát
  `autoRunsPerDay` je nejhorší možný den: při 15 minutách a výchozích 20 automatických bězích je
  to pět hodin session denně, při 60 minutách dvacet.
- **Dolní mez je proti falešným timeoutům.** Naměřeno na 19 bězích: medián 2,5 min, nejdelší
  doběhlý 6,8 min. Pod pěti minutami by `timedOut` přestal být zprávou o pomalém review a stal se
  vlastností nastavení — vypadalo by to jako porucha aplikace. Zkracovat limit se navíc nevyplácí:
  zabitá session už utratila, co utratila, jen z ní místo hotových nálezů zbydou částečné.

Hodnota mimo rozsah, napsaná ručně do `config.json`, soubor nepoloží — **srazí se do mezí a je to
pod polem vidět**, i s tím, kolik v souboru doopravdy je. Limit **putuje s požadavkem** jako
šablona promptu, takže rozjeté review doběhne s tím, se kterým začalo, i když se mezitím nastavení
uloží. Číslo se naopak **nikde nepíše k výsledku běhu**: uložený běh limit nenese, takže by šlo
napsat jen to, co je nastavené teď — a to je o starším timeoutu nepravda. **Překladač nálezů**
(dnes 120 s) nastavení nemá schválně: uvažuje se o tom, že se jazyk nálezů přesune do promptu
review a překladač zanikne.

**Prompt review se dá psát** (#281) na stránce `Review a skilly`, hned pod sadami skillů. Do té
doby byl natvrdo v kódu, takže se dal změnit jedině commitem — a přitom je to zrovna to, co se
mění nejčastěji a posuzuje se podle výsledku. Není to ale jedno textové pole na celý prompt:

- **Šablona** se zástupnými texty `{{skill}}` a `{{baseSha}}`, které aplikace dosadí při
  spuštění. Výchozí obsah je **doslova ten text, co byl v kódu** — po zavedení pole se aplikace
  nesmí začít chovat jinak. Prázdné pole znamená „ber výchozí“, ne „pusť reviewera bez zadání“.
- **Jádro** — věta o `ReportFindings` (i s prázdným seznamem) a zákaz zápisu a odesílání — se
  připojuje **vždycky** a ze šablony se vyhodit nedá. Není to bezpečnostní opatření (to drží
  `--disallowedTools`, viz *Oprávnění* níž): chrání to **sběr nálezů**, protože bez
  `ReportFindings` reviewer nálezy napíše textem, sběr tiše nefunguje a v okně stojí „čisté
  review“.
- **Náhled** pod polem ukazuje, jak se prompt poskládá — šablonu s dosazenými ukázkovými
  hodnotami a pod ní jádro, které jde přečíst, ale ne přepsat.
- **Chybějící zástupný text je chyba u pole** a taková šablona se **neuloží**; v konfiguraci
  zůstane poslední platná. Kdyby se do souboru dostala ručně, review se s ní **nespustí** a v PR
  stojí, který zástupný text chybí — spadnout potichu na výchozí by znamenalo, že „nic se
  nestalo“ vypadá jako „funguje“.

Šablona **putuje s požadavkem** stejně jako `baseSha`, takže běh doběhne s tou, se kterou začal,
a `Zkopírovat příkaz` v tabu `Průběh` skládá text toutéž funkcí — dvě místa s vlastní kopií by se
rozešla první úpravou věty. Prompt **kontroly nálezů** (#150) a **překladu nálezů** zůstává
natvrdo: jejich odpověď nenese nástroj, ale parser, takže by editovatelný prompt rozbil čtení,
ne jen výsledek.

**Nálezy chodí česky**, protože okno je české — u firemního repa s mezinárodním týmem se
dá přepnout na angličtinu, globálně i jen pro to jedno repo. Překládají se **až po
doběhnutí review**, jednou krátkou session na celý běh; reviewer sám dostane pořád tentýž
anglický prompt. Je to schválně: instrukce v promptu by kvalitu review ovlivnit mohla,
překlad po něm nemůže. Originál zůstává uložený vedle překladu a když se překlad nepovede,
ukáže se prostě anglicky.

Sada skillů se dá navázat na **programovací jazyk**: při review se z obsahu repa pozná,
čím je psané (`composer.json` a `.php` → PHP, `go.mod` → Go), a odpovídající sada se
použije. Smysl je nepouštět PHP skilly na Go repu — každý skill je jedna session.
Repu se sada **zapíše, jen když se od globální liší** — jinak by v konfiguraci vznikl
override, o který nikdo nežádal, a pozdější změna globální sady by takové repo minula.
Odhad se opakuje při každém review, dokud si repo neřekne o vlastní sadu; ručně nastavená
sada má vždycky přednost a detekci navždycky umlčí. Mapa jazyk → skilly je ve výchozím
stavu prázdná, takže dokud se nevyplní, detekce na nic nesahá. Soubor se zakládá sám s dosavadními výchozími
hodnotami, načítá se při startu i při návratu do aplikace, a když je rozbitý, běží se na
defaultech a je to vidět.

Editovat ho jde ručně, nebo **oknem nastavení** (⌘, nebo ozubené kolo v hlavičce okna). Okno
má **boční navigaci se sedmi stránkami** (#177, do té doby tři záložky): `Zdroje PR`,
`Review a skilly`, `Diff`, `Odesílání`, `Notifikace`, `Repozitáře` a `Běh`, seskupené podle otázky,
na kterou odpovídají (`Co se hlídá` / `Co jde ven` / `Prostředí`). Na stránce `Repozitáře` se
u každého repa z posledního seznamu PR nastavuje režim, případný override skillů a kategorií
a vlastní časový limit běhu.
Ukládá se samo do téhož souboru, pár set milisekund po posledním úhozu, a změna se projeví bez
restartu. Rozbitý soubor
editor **nepřepíše** — místo formuláře ukáže chybu a nabídne soubor otevřít. Dokud je
nastavení vepředu, hlavní okno se lehce rozostří.

**Dokud je okno otevřené a PRism je vpředu, zůstává před hlavním oknem** — kliknutí do hlavního
okna ho nezaklopí. **Fokus tím ale přejde na hlavní okno**: titulek nastavení zešedne a klávesy
jdou jinam, dokud se do nastavení nekliká znovu nebo se nedá `⌘,`. Není to opomenutí — klíčové okno
je v macOS právě jedno a udržet ho ve dvou nejde; co se u toho měřilo (včetně toho, že utility panel
nepomůže ani vzhledem), je v [`docs/architektura.md`](docs/architektura.md). Nad *cizími* aplikacemi ale neplave: jak PRism přestane být vpředu, okno spadne
na normální hladinu a leží pod nimi jako každé jiné okno; po návratu do aplikace je zpátky vpředu
i s rozepsanou hodnotou v poli. Zavřené okno se nevrací. Do #243 to bylo obyčejné okno, takže se za
hlavním oknem schovalo celé (středí se v něm) a vypadalo to, že se zavřelo — přitom bylo pořád
otevřené a `⌘,` ho jen znovu vytáhlo dopředu.

Zavírá se křížkem, ⌘W i **Escem** (#151) — sem se chodí přepnout jednu věc a jít zpátky
k review, takže cesta ven má být pod rukou. Rozepsaná hodnota se přitom **doručí**: Escem se
zavírá jedním hmatem uprostřed psaní, kdy těch pár set milisekund do automatického uložení
nemuselo uběhnout.

**Stavový řádek sčítá frontu** (#155): `12 PR`, `3 blokující`, `2 review` — kolik PR čeká, kolik
z nich má blokující nález a kolik má rozdělané review. Odznak v řádku seznamu mluví za jeden PR, tenhle souhrn za celou frontu — a sčítá
ji **celou**, ne to, co je vidět po filtru reviewerů, protože filtr je pohled, ne obsah. Blokující se
počítají bez odmítnutých nálezů, stejně jako v řádku. Dokud se seznam nenačetl, souhrn se neukáže
vůbec: nula blokujících nad nenačtenými daty by vypadala jako čisto.

Pod tím vším je vlastní cache repozitářů: bare partial clone do
`~/Library/Application Support/PRism/`, přihlášení delegované na `gh`, odpojený
`git worktree` pro každé review a úklid, který po každém pollingu zahodí repa bez
otevřeného PR a při překročení rozpočtu (10 GB) i ta nejdéle nepoužitá. Platí u ní, že
**vlastních klonů na disku se aplikace nikdy nedotkne** — pracuje výhradně ve své cache.
Uložené nálezy jsou klíčované head commitem: nové commity je označí jako zastaralé
a záznamy PR, který ze seznamu zmizel, se po třiceti dnech uklidí.

**Rozsah v1 podle specifikace je hotový** — všech pět fází (viz [`docs/stav.md`](docs/stav.md)).
Hotové jsou i milníky **M6** (odesílání review), **M7** (konverzace) a **M8** (notifikace), tedy
poslední naplánované; co přijde teď, jde přes issues.

Z M7 je čtení konverzace: **vlákna od kolegů visí jako bubliny u svých řádků**, vedle nálezů. Vyřešená jsou sbalená na jeden pruh s odznakem `vyřešeno` (nemažou se — je to
historie), moje komentáře mají odznak `já` a z každého se dá odskočit na GitHub. Konverzace
se načte při výběru PR a drží se, dokud se nezmění `updatedAt`; pollingem se netahá, aby
z jednoho tiku nebylo N podprocesů.

**A dá se do nich odpovědět.** V rozbaleném vlákně je pole na odpověď a tlačítko `Odpovědět`,
vedle něj `Vyřešit` (u vyřešeného `Znovu otevřít`) — všechno funguje jak v diffu, tak
v `Konverzaci`. Odeslaná odpověď se ve vlákně objeví hned, bez čekání na další načtení, protože
ji GitHub v odpovědi celou vrací. **Odpověď se nepotvrzuje** dialogem jako review: je to jedna
věta v diskuzi, dá se smazat a potvrzování každé by z okna udělalo klikačku — tlačítko je
pojmenované, takže se to nestane omylem.

Dvě věci, které nejsou vidět, ale jsou v tom to podstatné: **když odeslání selže, rozepsaný
text zůstane** na místě a chyba pod polem řekne, co s ní jde udělat. A **prázdná odpověď se
neodešle** — GitHub ji totiž přijme, nic nevytvoří a vrátí úspěch, takže by okno hlásilo
odeslanou odpověď, která nikdy nevznikla. `Vyřešit` se navíc nabízí jen tam, kde na to GitHub
dává právo; jinde by tlačítko vždycky selhalo.

**A dá se napsat i pod PR.** Na spodní hraně tabu `Konverzace` je pole `Napsat do konverzace
pod PR…` a tlačítko `Odeslat komentář`. Je to poslední věc, kvůli které se u review přepínalo
do prohlížeče. **Není to review**: nenese verdikt, nepotvrzuje se dialogem a v panelu
`Moje review` se neobjeví — proto sedí pod osou konverzace, ne v panelu, kde by se s review
pletlo. Platí u něj totéž co u odpovědi: po selhání text zůstane, prázdný komentář se neodešle
a bez povolení v nastavení neodejde nic.

**Rozdělané review se skládá v okně** a přežije restart: tělo, verdikt a řádkové komentáře
leží v `drafts/` vedle uložených nálezů, mimo dosah úklidu cache. Nový commit ho nesmaže,
jen zablokuje odeslání — vlastní próza nezastarává tak rychle jako strojové nálezy.

**Po novém commitu se review přenese, ale ne tiše.** Tlačítko se u zastaralého draftu jmenuje
`Zkontrolovat a odeslat…` a okno začne kontrolou kotev: u každého komentáře je vidět, jestli
**sedí**, **posunul se na jiný řádek**, jestli **nevíme, co na tom řádku bylo** (komentář z doby
před touhle funkcí), nebo že se **řádek v novém diffu ztratil**. Rozhoduje text řádku, ne jeho
číslo — komentáře si proto ukládají snímek kódu, ke kterému se psaly, a změna odsazení kotvu
neztratí. U každého se dá vybrat, co s ním: nechat, přepsat do těla review s odkazem na kód, nebo
vyjmout; ztracený komentář míří do těla, protože smazat ručně psaný text musí být tvoje
rozhodnutí. Teprve po přenesení se ukáže payload a dá se odeslat.

Hlavní smyčka je **nález → komentář mými slovy**: v bublině nálezu je `Převzít do review`,
které z jeho textu udělá můj komentář u toho řádku — a ten se dá přepsat. Převzatý nález
nese odznak `v mém review`, takže se nedá vzít dvakrát; rozeznává se podle revieweera, aby
u shody `2×` nesvítil odznak i u toho druhého. Vlastní poznámku přidá tlačítko, které se
objeví po najetí na řádek diffu.

**Co GitHub jako řádkový komentář nepřijme, jde do těla review jako odkaz na kód** —
permalink na commit, který se vyrenderuje jako obarvený úryvek. Týká se to nálezů mimo diff
a řádků, které v diffu nejsou (rozbalený kontext). Tlačítko to říká dopředu
(`Převzít do těla review`), důvod stojí pod řadou akcí, a po kliknutí se panel přepne na tab,
kam text spadl.

V tabu **Moje review** je tělo, seznam všech řádkových komentářů a výběr verdiktu, který je
**předvyplněný návrhem z nálezů**. Takový verdikt je jen **obtažený** a stojí u něj popisek
`návrh z nálezů`; vyplněné tlačítko se zaškrtnutím zůstává vyhrazené mé volbě, která návrh
vždycky přebije (a druhý klik ji zruší, takže se návrh vrátí). Když návrh není — review
neproběhlo, spadlo, nebo je jeho záznam zastaralý — zůstává verdikt nevybraný a odeslat se nedá:
schválit PR proto, že reviewer spadl, je nejdražší chyba, kterou tahle aplikace umí udělat.
**Na vlastním PR se návrh nenabídne** a panel řekne proč: GitHub tam přijme jedině `Jen komentář`.

Návrh se přitom **nikam neukládá**. Rozdělané review z otevření PR nevznikne — dokud se do něj
něco nenapíše, žádný draft není a ikona v řádku seznamu nesvítí. Předvyplněný verdikt tedy
zastoupí chybějící volbu u review, které už nějaký obsah má; u čistého PR bez poznámek se návrh
přijme za svůj jedním kliknutím a panel to říká větou.

Seznam komentářů je jediné úplné místo: komentář na řádku, který
z diffu zmizel, se nemá kde ukázat jako bublina, ale tady je i s možností ho vyjmout.
Prázdný komentář se neuloží a odeslání zablokuje, protože GitHub takový payload odmítne —
a odmítne s ním celé review.

Že je něco rozděláno, je vidět **v řádku seznamu i v detailu** (ikona pera). Draft psaný
proti staršímu commitu má v tabu **banner** a odeslat se nedá; text zůstává.

Na jeden řádek jde napsat i **víc komentářů** a odejdou spolu s review. Panel u toho ale řekne,
co z nich vznikne: **samostatná vlákna vedle sebe, ne odpověď** pod prvním komentářem. Jinak to
GitHub neumí — v payloadu review se nedá říct „tenhle je odpověď na tamten“ a neodeslané vlákno
ještě nemá identitu, na kterou by šlo odkázat. Odpovědět jde na vlákno, které z odeslaného
komentáře vznikne.

### Klávesové zkratky okna (#441)

Okno mělo zkratky jen na část toho, co se v něm dělá denně. Od #441 má i to nejčastější rukou:
zavřít dočtený PR, obnovit seznam, přepnout sekci railu a zastavit běh, který nemá cenu dokoukat.

| Zkratka | Co udělá |
|---|---|
| `⌘K` | command palette |
| `⌃⇥` / `⌃⇧⇥` | sousední záložka, dokola a včetně domácí |
| `⌃W` | zavřít záložku pull requestu (nic se tím nezahodí) |
| `⌘R` | obnovit seznam |
| `⌃1`–`⌃5` | sekce railu: `Přehled`, `Fronta`, `Moje PR`, `Rozdělaná`, `Dění` |
| `⌥↓` / `⌥↑` | další / předchozí nález, `⌥⇧↓` další blokující |
| `⌘1` / `⌘2` | strom souborů u diffu / panel s mým review |
| `⌘F` | hledat v diffu (podruhé vrátí fokus do pole) |
| `⌘G` / `⌘⇧G` | další / předchozí výskyt; v poli i `⏎` / `⇧⏎` |
| `⌘⏎` nebo `⌃⏎` | otevřít **potvrzení** odeslání review |
| `⌘⇧P` | sestavit zadání pro agenta |
| `⌘.` | zastavit běžící review na PR v okně |
| `` ⌃` `` | zásuvka s terminálem (na české mapě i `⌃;`) |
| `⎋` | zavřít pruh hledání, jinak zpět na seznam commitů |
| `⌘⇧R` / `⌘⇧D` | z dashboardu: pustit review na vše, co neběželo / dopsat rozdělané |
| `⌘,` | nastavení |

**`⌃W`, ne `⌘W`** — `⌘W` patří systému (zavře okno). Ze stejného důvodu jsou na `Control`u i sekce
railu: `⌘1` a `⌘2` jsou uvnitř PR strom souborů a panel.

**Na české klávesnici mají sekce railu druhou klávesu.** `keyboardShortcut` páruje na **znak**,
a pod `1`–`5` je v české mapě `+ ě š č ř` — samotné `⌃1` na ní tedy nezabere vůbec. Aplikace proto
registruje obě: `⌃1`+`⌃+`, `⌃2`+`⌃ě`, `⌃3`+`⌃š`, `⌃4`+`⌃č`, `⌃5`+`⌃ř`. Dvě tlačítka se **stejnou
akcí a jinou klávesou** jsou v pořádku; dvě se **stejnou kombinací** ne — vyhraje to zaregistrované
později, a pozná se to jedině tím, že jedna ze zkratek „nefunguje“ (#151, #184).

**`⌃⏎` je druhá klávesa k `⌘⏎`, ne náhrada** — a otevírá **potvrzení**, neodesílá (tvrdá podmínka
č. 1). Přibylo proto, že `⌘⏎` si bere i paleta ⌘K, takže nad otevřenou paletou je zkratka detailu
zakázaná; `⌃⏎` se s ní nepotká. V samotném potvrzovacím sheetu zkratka na odeslání **není a nebude**.

**Zakázaná zkratka klávesu nebere a propadne dál** — `⌃W` na domácí záložce, `⌘R` po dobu dotazu,
`⌘.` nad PR, na kterém nic neběží, `⌘2` v tabech bez panelu, `` ⌃` `` mimo záložku PR. Zkratka, po
které se nic nestane, je totiž k nerozeznání od rozbité aplikace.

**S fokusem v terminálu (#459) se zkratky bez `⌘` neuplatní vůbec.** `⌃W` uvnitř maže slovo, `⌃C`
přerušuje běh, `⎋` vyskakuje z vimu — a zkratka, která uprostřed psaní zavře záložku, je horší než
žádný terminál. Hranice je `⌘`, ne `Control`, protože jinak by venku zůstalo `⎋` a `⌥↑`/`⌥↓`;
`⌘` naopak terminál nikdy nedostane. Jedinou výjimkou je `` ⌃` `` sama.

Dvě věci na tom řídí systém, ne aplikace: **`⌃1`–`⌃5` může sebrat Mission Control** (`Přepnout na
plochu N`), a pak se k oknu událost nedostane vůbec — buď se ta systémová zkratka vypne, nebo se
použije česká varianta, na kterou Mission Control nesahá. A **`⌘.` je v Cocoa druhé jméno pro
Escape**: nad běžícím review vyhraje naše zastavení (klávesové ekvivalenty tlačítek se vyhodnocují
dřív), ale tam, kde je zakázané, se `⌘.` chová jako `⎋`.

Kombinace jsou v aplikaci na **jednom místě** (katalog v `Policy`) a nápovědy tlačítek, kapsle
v hlavičce i řádky palety si popisku **odvozují** z něj (`Obnovit seznam (⌘R)`, jak to kreslí
návrh), takže nakreslená zkratka nemůže tvrdit něco jiného než klávesa.
Že se žádné dvě kombinace neopakují, tvrdí test;
že klávesy doopravdy chodí, se v harnessu ověřit nedá (testovací host nedostane aktivaci, takže
nemá key okno) — to zkouší člověk na běžící aplikaci, na české i anglické mapě.

### Command palette ⌘K (#184)

**Jedno pole na všechno.** S pěti PR a sedmi soubory je klikání únosné, s dvaceti už ne —
a paleta je zároveň jediné místo, kde se nemusí pamatovat, kde co v okně bydlí. Otevírá se
**⌘K** (druhé zmáčknutí zavře) nebo kapslí `⌘K` v hlavičce okna; ta tam je proto, že jinak by
o paletě věděl jen ten, kdo si přečetl release notes.

Výsledky jsou v **pěti skupinách a jejich pořadí je pevné**: **Nálezy**, soubory otevřeného
PR, `Pull requesty k review`, `Moje PR`, akce. Nálezy jsou první schválně — je to jediná věc, kterou
tahle aplikace má a prohlížeč ne, takže pořadí skupin je tvrzení o tom, k čemu je okno. Z každé
skupiny je vidět **nejvýš šest** řádků; strop je na skupinu, protože jinak by dvacet nálezů
vytlačilo všechno ostatní.

**Vlastní PR mají vlastní skupinu, ne odznak v cizí** (#336), a je to důsledek toho stropu: ve
společné skupině by při dvaceti cizích PR to moje nemuselo vyjít vůbec. Rozřazuje se podle **autora**
(tak jako sekce `Moje PR` v railu), skupina stojí za cizími PR, protože cizí jsou to, na co se čeká,
a skupina, ve které nic nesedlo, se **nekreslí** — kdo vlastní PR nemá, neuvidí prázdný nadpis.
Otevírají se stejně jako cizí, `↵` v obou případech otevře záložku.

**Pole má fokus hned po ⌘K** a je **prázdné** — paleta je „začínám hledat“, ne „vracím se
k rozdělané práci“, takže po zavření z ní nezůstane text z minula.

**Prázdný dotaz není prázdné okno** — ukáže začátek každé skupiny, tedy nabídku toho, co je po
ruce: nálezy od nejvážnějšího, soubory v pořadí diffu, cizí i vlastní PR od naposledy změněného,
akce v pevném pořadí. Hledá se **bez ohledu na velikost písmen a diakritiku** (`nalez` najde
`nález`) a víc slov znamená **a zároveň** — `vault secret` najde nález ve `vaultu`, i když ta slova
v textu vedle sebe nestojí. Shoda v titulku váží víc než v podtitulku, začátek slova víc než vnitřek; nalezený úsek
je v řádku **zvýrazněný** — a to v tom textu, ve kterém se doopravdy potkal.

Hledá se i **podle autora a podle repozitáře**: autor u pull requestů, repo u pull requestů
i u nálezů. Obojí je proto vidět v podtitulku řádku (`connection#21663 · sykora-ji`) — výsledek,
u kterého není poznat, proč vyšel, vypadá jako chyba hledání. Soubory podle repa nejdou: jsou
všechny z jednoho otevřeného PR, takže by se vytáhly všechny naráz a nic by to nerozlišilo.

`↵` otevře (nález i soubor **odscrollují diff** na to místo, nález se navíc zvýrazní),
`⌘↵` otevře věc na GitHubu, `esc` zavře, `↑↓` chodí po řádcích a cyklí. Když nic nesedí, řekne
to — a napíše, **kde** se hledalo: paleta se nikoho nedoptává, hledá jen v tom, co je v paměti.
Proto jsou soubory jen z **otevřeného** PR (diff jiného v paměti není), zato nálezy ze **všech**;
odmítnuté se nenabízejí, protože nálezu, kterému nevěřím, není kam skákat.

**Filtr seznamu paletu nezužuje.** Filtr je zúžení seznamu, kdežto paleta je způsob, jak něco
najít — a hledání, ze kterého vypadne schovaný PR, je k nepotřebě právě tehdy, když je filtr
zapnutý.

**Akce, ne jen navigace**: pustit review na otevřený PR (nebo ho zrušit, když běží), přepnout
pohled na diff, složit panel s mým review, otevřít sekci railu, obnovit seznam, otevřít
nastavení. Nabízí se **jen to, co by něco udělalo** — bez otevřeného PR tedy nic, co na PR visí.
Kreslená zkratka je **vždycky ta skutečná** — od #441 se **nekreslí opsaná, ale odvozená**
z katalogu zkratek, takže se s klávesou nedá rozejít: `⌘2` u panelu, `⌃1`–`⌃5` u sekcí railu,
`⌘R` u obnovení, `⌘.` u zrušení běžícího review a `⌘,` u nastavení. Návrh měl u „pustit review“
`⌘⇧R`, což v aplikaci dělá něco jiného (pustit review na vše, co neběželo, z dashboardu), takže se
nenakreslila. U sekcí se kreslí **číslicová** varianta (`⌃1`); česká (`⌃+`) je druhé tlačítko na
tutéž akci a v jednom řádku by z jedné kapsle udělala dvě.

**Odsud nic neodchází.** Paleta nemá přístup k `ReviewPublishing` a nepřidává druhou cestu ven;
jediná věc, kterou pouští, je read-only reviewer.

### Odeslání review

**Dvě kliknutí, dvě různá tlačítka.** `Odeslat review…` v tabu `Moje review` nic neodesílá —
otevře potvrzení, ve kterém je vidět **celý payload**: verdikt, tělo tak, jak je napsané,
a každý řádkový komentář i s poli, se kterými odejde do API — `path`, `line` (u rozsahu
`start_line`) a `side`. Ta pole se berou **z téhož payloadu, který se posílá** (#178), takže se
výpis s odeslaným tělem nemůže rozejít; do #178 si je sheet skládal vlastní cestou a strana ani
začátek rozsahu v něm nebyly vůbec, přestože právě ony rozhodují, ke kterému kódu komentář sedne. Teprve
tlačítko tam zavolá GitHub. Zavřít se dá kdykoli a draft tím zůstane netknutý.

Ochrana stojí právě na tom výpisu, ne na obřadu: **žádné opisování názvu repa** a **žádný
druhý dialog nad sheetem**. Obojí se za týden odklikává poslepu a oslabí to i to první
potvrzení. Co zůstává, je pojmenování akce — tlačítko se jmenuje
`Odeslat APPROVE pro owner/repo#123` — a to, že **není výchozí**: Enterem se nic neodešle.

**`⌘⏎` otevře to potvrzení** (#151), a jenom to — odeslání zůstává druhé kliknutí na druhém
tlačítku, uvnitř sheetu žádná zkratka není. Dělá přesně totéž co `Odeslat review…` v panelu
včetně toho, kdy nedělá nic: nad draftem, který se odeslat nedá (chybí verdikt, prázdný
komentář, nepovolené repo), je zhasnutá stejně jako to tlačítko. Nad zastaralým draftem okno
otevře, protože se v něm dá přenést na nový commit.

Návrh verdiktu z nálezů stojí v potvrzení **vedle** toho odesílaného. Když je odesílaná hodnota
z návrhu, sheet to napíše (`Je to návrh z nálezů — ručně jsi verdikt nevybral.`), aby se v posledním
okně před odesláním nedala splést s mým rozhodnutím. A když se **moje** volba s návrhem rozchází
(schvaluju PR, u kterého reviewer hlásí blokující nález), řekne to nahlas.

Proč odeslat nejde, je vidět **předem** — vedle zakázaného tlačítka, ne až po pokusu:
chybějící verdikt, prázdný řádkový komentář, draft proti staršímu commitu, nebo repo, které
odesílat nesmí.

**Povolení je nastavení, ne konstanta**, a ve výchozím stavu je vypnuté. Zapíná se globálně
nebo u konkrétního repa (`Povoleno` / `Zakázáno` / `Podle globálního nastavení`) a platí hned,
bez restartu. Rozhoduje **jen** o tom, jestli se tlačítko vůbec nabídne: odesílá pořád člověk
potvrzením a proti commitu, který má před sebou. Přepnutí u repa se drží i po změně globálního
defaultu — repo, které si o zákaz řeklo, se tím nesmí tiše otevřít. Překlep v `config.json` se
sráží na zakázané, nikdy na povolené. **Platí to i pro odpovědi do vláken** — jedna brána pro
obojí, takže se nedá stát, že se do repa nesmí poslat review, ale komentář ano.

Po úspěchu se potvrzení **zavře samo**, draft zmizí (i z disku) a konverzace se načte znovu,
takže je moje review hned vidět v `Konverzaci`. Otevřené zůstane jen tehdy, když GitHub vrátí
stav, kterému aplikace nerozumí — tam je jediná zpráva ta, že se to má zkontrolovat ručně.
**Selhání draft nemaže**: chyba je vypsaná i s tím, co se s ní dá dělat, a dá se zkusit znovu.

Vlákna, jejichž řádek v aktuálním diffu **není** (typicky zastaralá po novém commitu), se
do kódu nekotví — jejich čísla platila pro starý head, takže by bublina sedla na cizí řádky.
Domov mají v záložce `Konverzace` spolu s review ostatních a komentáři pod PR, a je u nich vidět
kód, ke kterému se vážou — ten ze **starého** commitu, ne z dnešního.

Co se ve které verzi změnilo, ukazuje **okno `Novinky v PRism`** přímo v aplikaci (✨ v hlavičce
okna, nebo menu aplikace): vlevo celá historie vydání, vpravo release notes té vybrané. **Po aktualizaci se otevře samo**, jednou, s vybranou nejnovější verzí — jinak
by o novinkách nikdo nevěděl. Podrobnosti jsou v sekci [Novinky](#novinky) níž; totéž je
i v [releases](https://github.com/ondrajodas/PRism/releases) na GitHubu. Kde projekt je
jako celek, říká [`docs/stav.md`](docs/stav.md), ne release notes: ten stav by v nich
zastaral hned další verzí.

- [Návrh (specifikace)](docs/superpowers/specs/2026-07-31-prism-design.md) — plný
  návrh včetně záznamu rozhodnutí a zamítnutých alternativ
- [`docs/navrh.html`](docs/navrh.html) — **vizuální** návrh (mockup): 23 sekcí rozdělených
  do stránek podle místa v aplikaci. Publikovaná kopie je artifact, na který se posílá odkaz
- [`docs/navrh.md`](docs/navrh.md) — jak se s mockupem pracuje: čím se čte, jak se
  aktualizuje; co mění vzhled, se do něj kreslí a schvaluje dřív, než na to vznikne issue
- [`docs/claude-cli.md`](docs/claude-cli.md) — ověřené chování `claude` CLI
- [`docs/github-cli.md`](docs/github-cli.md) — co v tomhle repu na `gh` padá a čím to
  nahradit; jak se čte výsledek Copilota
- [`docs/github-review-api.md`](docs/github-review-api.md) — ověřené chování zápisového
  review API GitHubu; podklad pro odesílání review (M6)
- [CLAUDE.md](CLAUDE.md) — pravidla pro práci v tomto repu
- [`docs/architektura.md`](docs/architektura.md) — co který modul drží a co se u něj nemá
  rozbít
- [`docs/testovani.md`](docs/testovani.md) — co se u které oblasti testuje a proč zrovna to
- [`docs/stav.md`](docs/stav.md) — co je hotové a co zbývá
- [`docs/paralelni-vyvoj.md`](docs/paralelni-vyvoj.md) — jak se vyřizuje seznam issues naráz
  a jak vypadá milník na větší objem práce

## Jak to funguje

1. **Polling GitHubu** přes `gh` — hledají se PR, u kterých je po mně požadované review
   (`review-requested:@me`), a od #330 i **moje vlastní** (`author:@me is:open`). Repozitáře
   nejsou pevný seznam, může přijít cokoli. Čí PR to je, se pozná z **autora**, ne ze zdroje:
   login se zjistí jednou při startu (`gh api user`) a dokud nedorazí, je všechno cizí —
   „nevím, kdo jsem“ nesmí znamenat „to je moje“. Další „moje“ loginy pro agenta, který pushuje
   pod vlastním účtem (`ownLogins`), se od #389 zadávají v nastavení na stránce `Zdroje PR`
   (a pořád i ručně v souboru).

   **Vlastní zdroj přibyl jen do výchozí konfigurace, uložená se nemigruje** — kdo `config.json`
   už má, nový zdroj v něm nenajde a musí si ho dopsat (aplikace mu do ručně editovaného souboru
   dotaz nedopisuje). Že chybí, aplikace pozná a napíše to tam, kde by vlastní PR měly být.
2. **Checkout na vyžádání** — repo se naklonuje do vlastní cache aplikace jako bare
   partial clone a přidá se detached `git worktree` na head commitu daného PR.
   **Vlastních** klonů na disku se aplikace nikdy nedotkne.
3. **Review** — nakonfigurované skilly se spustí jako paralelní headless session
   Claude Code v tom worktree, omezené na read-only nástroje. Prompt si o skill říká
   nástrojem `Skill` výslovně, takže v konfiguraci jsou jeho id (`plugin:skill`), ne
   slash commandy; **jeho text se dá psát v nastavení** (#281), jádro s `ReportFindings`
   a zákazem zápisu se k němu připojí vždycky. Které skilly to jsou, může záviset
   na programovacím jazyce repa; ten se odhaduje z `git ls-files`. Spouští se **tlačítkem**,
   nebo samo, když je repo v automatickém režimu — ten se zapíná globálně i zvlášť pro každé
   repo a výchozí je manuální, aby neznámé repo nespálilo panel session bez dozoru.
   **Automat utratí session, teprve když se změnil head commit**, takže komentář na PR ho
   nespustí, a hlídá ho denní limit.
4. **Zadání vedle kódu** (#120) — aplikace položí **vedle** pracovního stromu soubor
   s popisem PR a s odkazy na issue, které v něm jsou, a prompt řekne jedinou větou, kde leží.
   Reviewer si ho přečte `Read`em stejně jako změněné soubory, takže může hledat **rozdíl**
   mezi tím, co se mělo udělat, a tím, co se udělalo. Zadání je pro něj **materiál, ne pokyn**:
   proto soubor, a ne prompt — cizí text vložený do promptu má váhu instrukce a popis PR píše
   někdo jiný. Do promptu jde jen cesta, takže se prompt nemá čím rozkolísat, a **sada nástrojů
   reviewera se nemění**. PR bez popisu a bez odkazu zadání nedostane a věta se do promptu
   nepřipojí vůbec.

   **Od #345 se k odkazům dotáhne i text issue** — a odkazy se hledají i v **komentářích pod PR**,
   protože linkback z trackeru chodí zrovna komentářem. Text tahá **vlastní krátká `claude -p`
   session**, aby aplikace nemusela držet druhý token; má vyjmenovaná povolení (`ToolSearch` a jeden
   čtecí MCP nástroj, jehož jméno je v `config.json`) a sada nástrojů revieweera se tím **nemění**.
   Stojí to ~$0,2–0,3 a ~20 s na review a **tahá se vždycky, i v automatu**: zadání vedle diffu je
   důvod, proč ta funkce existuje.

   **Nedotažené zadání review nepoloží, ale nezmizí.** V souboru zůstane u každého issue věta,
   která říká **proč** ho tam není — jinak by „issue nic neříká“ vypadalo stejně jako „text se
   nestáhl“ —, a v tabu `Průběh` je u dráhy odznak `zadání není celé` s důvodem v nápovědě.
   Rozhoduje se přitom podle stavu MCP serveru v `init` eventu session, **ne podle toho, co model
   napsal**: dva ze tří tvarů selhání skončí nulovým kódem a hlásí se jako úspěch.
5. **Sběr nálezů** — z `ReportFindings` tool callů ve `stream-json` event streamu.
   Strukturovaná data, ne parsování textu.
6. **Zobrazení** — diff v plné šířce s nálezy jako bubliny na svém `file:line`, plus
   řaditelná tabulka pro nálezy, které ke konkrétnímu řádku nepatří (chybějící testy,
   architektonické poznámky).

7. **Notifikace** — aplikace dá vědět, i když se do ní nikdo nedívá: o novém PR ve frontě
   a o doběhlém review. Klik na notifikaci **otevře záložku** toho pull requestu (na tabu, kde jsi
   v něm skončil) a dá okno dopředu. PR, který se mezitím ze seznamu odklidil, se neotevírá —
   a filtr, který ho schoval, klik zruší.

**Co nedoběhlo, se neztratí.** Když se aplikace zavře, ptá se — a když se ukončení potvrdí,
**běžící session zabije** a čeká, dokud po nich nezůstane běžet nic. Bez toho `claude` aplikaci
přežil: osiřelý proces počítal tokeny za review, které už nemá komu doručit, a držel pracovní
strom v cache (změřeno, dvě takové session běžely čtyři dny). Ze zaseknuté session přitom nesmí
vzniknout aplikace, která se nedá zavřít, takže čekání má strop dvou sekund.

Nálezy z takového běhu se pak **dotáhnou z transcriptu**, který si `claude` vede na disku: běh se
poznamená, jakmile nahlásí id session, a po startu se z něj přečte, co stihl. Platí to i pro pád
aplikace nebo `kill`, na které se ptát nedá — zavření aplikace se od nich v tomhle záměrně neliší.
Takový výsledek je v řádku `přerušeno`, ne `timeout` ani `čisté` — nedoběhl, takže se z něj nesmí
soudit, že je hotovo. Zrušení review člověkem je proti tomu jiná odpověď: tam se nedotahuje nic,
protože o ty nálezy si nikdo neřekl.

**A po aplikaci zabité zvenčí nezůstane běžet `claude`** (#351). Zabíjení při zavírání pokrývá
jen normální ukončení — když aplikace ztuhne a někdo ji zabije, nemá se úklid kde spustit
a session přejde pod `launchd` a počítá tokeny dál. Prevence na macOS neexistuje (změřeno:
potomek přežije rodiči `SIGTERM` i `SIGKILL` a Darwin nemá čím to zakázat), takže si aplikace
běžící session **zapisuje do své cache** a při dalším startu ty osiřelé zabije. Sirotek tedy žije
do dalšího spuštění, což jsou v praxi vteřiny — zaseknutá aplikace se zabíjí právě proto, aby se
spustila znovu. Cizí `claude` se u toho nemá jak splést s vlastním: pozná se jedině podle
identity, kterou si aplikace sama zapsala (PID **a** okamžik vzniku procesu), nikdy hledáním
mezi běžícími procesy podle jména.

Nálezy jsou klíčované head commitem PR. Když přijdou nové commity, předchozí nálezy se
označí jako zastaralé — nezobrazují se proti kódu, který už neexistuje.

**A dá se u nich zjistit, co nové commity spravily** (#150). Nad zastaralými nálezy se v hlavičce
nabídne `Zkontrolovat nálezy`: pustí to session, která dostane **uložené nálezy z předchozího
commitu** jako seznam a projde je proti pracovní kopii na hlavě PR — vlastní prompt, tytéž
read-only nástroje jako review. U každého nálezu pak stojí odznak `kontrola: vyřešeno`,
`kontrola: pořád platí` nebo `kontrola: nejasné` a k němu věta, jak k tomu běh došel; v hlavičce
je souhrn (`3 vyřešené, 1 pořád platí, 1 bez odpovědi`).

Vyřešený nález je poznat na první pohled: **shrnutí je přeškrtnuté** a v odznaku závažnosti stojí
`vyřešeno`. Přeškrtne se u toho jen text nálezu, ne celý řádek — celá plocha se ztlumí jedině
u nálezu, který jsem **odmítl** sám, a ty dva stavy se nesmí plést. A když nález blokuje, zůstává
u něj `blokuje` i nadále: „vyřešeno“ je tvrzení modelu, kdežto to, že se PR pořád nemerguje, je fakt.

Tři věci, které z toho **neplynou**. Odznak nálezy **nemaže ani neschovává** — je to tvrzení
modelu, ne fakt, a sundat nález smí jedině odmítnutí (#113), za kterým stojí člověk. Kontrola se
**nenabízí**, dokud není uložený záznam proti staršímu commitu, protože bez nálezů by se session
neměla na co ptát. A **platí jen pro tu hlavu, proti které běžela**: po dalším commitu odznaky
zmizí a v hlavičce zbyde věta, že se dá pustit znovu.

### Notifikace

Co přijde a co v tom bude:

| Kdy | Co uvidím |
|---|---|
| Nový PR ve frontě | `Nový PR k review — owner/repo#123` a název PR |
| PR, který jsem už reviewoval, se vrátil | `Znovu požádáno o review — owner/repo#123` a název PR |
| Víc nových PR naráz | Jeden souhrn: `4 nové PR k review` a tři z nich jménem plus `a 1 další` |
| Víc naráz, něco z toho znovu | `4 PR k review (1 znovu)` |
| Review našlo nálezy | `3 nálezy · 1 blokuje`, pod tím nejzávažnější nález (`correctness: …`) a na třetím řádku `owner/repo#123` |
| Review našlo nálezy, ale nic nezastavuje merge | `3 nálezy · nic neblokuje` |
| Review je čisté | `Čisté review` a `Reviewer nenašel žádný nález.` |
| Review se nepovedlo | `Review se nepovedlo` a pod tím důvod, se kterým se dá něco dělat — spadlá session, timeout bez nálezů, selhaná pracovní kopie |
| Na **mém** PR se ozval někdo jiný | `2 nové komentáře a 1 review`, pod tím ta nejnovější věta (`odinuv: opravdu to potřebuje ten mutex?`) a na třetím řádku `owner/repo#123` |

**Titulek odpovídá na „mám k tomu jít hned?“** (#200) — proto v něm je počet nálezů a kolik
z nich blokuje, ne jméno pull requestu. To je až na třetím řádku; v banneru je vidět taky
(změřeno: vejdou se čtyři řádky těla), a co se do něj nevejde, je celé v Oznamovacím centru.
Dlouhý souhrn nálezu se proto krátí sám — bez toho by systémový ořez sebral i řádek
s identifikací.

**Jedna notifikace na pull request**, ne jedna na skill: reviewery jedou paralelně a tři
hlášky za jednu věc jsou tři vyrušení. Nový výsledek review přepíše ten starý, aby vedle
`3 nálezy` nezůstala viset stará hláška `Čisté review`. Notifikace o témž PR systém řadí
k sobě.

**Co se hlásí, se nastavuje** — stránka `Notifikace` v okně nastavení: hlavní vypínač a pět
událostí (nový PR, review s nálezy, čisté review, selhání a „ozval se někdo na mém PR“). Ve výchozím
stavu je zapnuté všechno. S vypnutým hlavním přepínačem se aplikace **nezeptá ani na systémové
oprávnění**.

**Cizí aktivita na mém PR nepřebíjí výsledek review** (#335), a naopak: nový výsledek review přepíše
jen ten předchozí, kdežto „kolega odpověděl“ zůstane na obrazovce vedle — jsou to dvě různé věci.
Hláška o témže komentáři přitom **nepřijde dvakrát**: vedle poslední návštěvy PR si aplikace pamatuje,
o čem už dala vědět, protože oznámením se PR nenavštíví.

**Re-review se pozná od novinky.** U pull requestu, který jsem už někdy reviewoval, není
„nový PR“ pravda — a je to jiné očekávání: u nového jde o první přečtení, u re-review o to,
co se od mého review změnilo. Že ho znám, se pozná z uložených nálezů; zahozený záznam z něj
udělá zase novinku, protože zahození znamená „tenhle výsledek je k ničemu“.

**Co dneska stálo review, je vidět ve stavovém řádku** — cena za dnešek, ruční i automatická
review dohromady, počítáno od půlnoci a přežívá to restart. Rozpočet v penězích aplikace nemá:
`autoRunsPerDay` omezuje **počet PR**, ne sessions ani dolary, a je to vědomé — nejdřív se má
pár týdnů koukat na skutečné číslo a teprve pak rozhodnout, jestli je brána potřeba. Součet, do
kterého se nepodařilo započítat všechno (zabitý nebo přerušený běh cenu nenahlásí), je označený
`≥`: je to **dolní odhad**, ne úplná částka.

**Že notifikace fungují, je vidět ve stavovém řádku** — vlevo od puntíků služeb je zvonek
s časem posledního doručení. `zatím nic` znamená, že se od spuštění nic neohlašovalo (a nic se
tím netvrdí o tom, jestli to funguje), `vypnuto` že jsou vypnuté v nastavení. Čas posune jedině
**doručená** notifikace: odmítnuté oprávnění ani selhání systému ho nechají být, jinak by řádek
tvrdil, že to chodí, zrovna když nechodí. Drží se v paměti, takže po restartu začíná znovu —
je to odpověď na „funguje mi to teď“, ne historie.

**Po prvním spuštění nepřijde lavina.** Aplikace si drží snímek poslední fronty, takže PR, která
tam byla, než začala hlídat, za nová nepovažuje. Ohlásí se až devátý.

Notifikace fungují jedině z `/Applications` — `bin/run.sh` tam aplikaci instaluje sám, viz
*Build*.

## Novinky

Okno `Novinky v PRism` (menu aplikace hned pod `O aplikaci PRism`, nebo ✨ v hlavičce okna)
je jedno okno nad jedněmi daty: vlevo seznam všech vydání s tagem, názvem a časem vydání,
vpravo release notes té vybrané, vykreslené jako Markdown. Dvě obrazovky — „co je nového“
zvlášť a „historie“ zvlášť — by se dřív nebo později rozešly. **Čas u data je tam schválně:**
verzí vyjde za jeden den klidně šest, takže samotné `5. 8. 2026` o pořadí neříká nic.

**Po aktualizaci se otevře samo, jednou**, s vybranou nejnovější verzí; vydání novější než to
naposledy viděné mají v seznamu odznak `nové`. Jinak by o novinkách nikdo nevěděl — a otevřít
se dá kdykoli — z menu aplikace nebo tlačítkem v hlavičce hlavního okna, hned vedle
ozubeného kola. Zavírá se **Escem** i ⌘W: je to okno na čtení, takže v něm není co ztratit.

**Otevře se vystředěné v hlavním okně**, ne doprostřed obrazovky — otevírá se z jeho hlavičky,
z menu a po aktualizaci, takže tam se člověk v tu chvíli kouká; na velkém (nebo druhém) monitoru
by jinak vyskočilo někde vedle. S hlavním oknem u kraje obrazovky se zarovná zpátky na viditelnou
plochu a bez hlavního okna se otevře tak, jak rozhodne systém. Stejně se od začátku středí okno
nastavení — je to jeden mechanismus pro obě.

Odsunuté okno **v rámci běhu zůstane, kam si ho dáš**, a po restartu je zpátky ve středu. Okno,
které pod rukama uskakuje, je horší než okno mimo střed, takže se pozice srovnává jen při
otevření, ne při vytažení dopředu.

**A dokud je otevřené, zůstává před hlavním oknem** — stejně jako nastavení a tou samou cestou.
Nad cizí aplikací neplave: s odchodem PRismu do pozadí spadne na normální hladinu a s návratem je
zpátky vpředu. Zavřené okno se nevrací.

Historie se tahá **jedním voláním** `gh` z vlastního repa aplikace (tělo releasu je rovnou
v seznamu, takže se na jednotlivou verzi nechodí zvlášť) a drží se v paměti do konce běhu:
jednou při startu kvůli tomu, jestli něco přibylo, a pak už jen z paměti. V pollingu ani na
pozadí se aplikace na nic neptá. Bez sítě je v okně **důvod a tlačítko `Zkusit znovu`**, ne
prázdný seznam — „nepovedlo se to načíst“ a „žádná vydání nejsou“ znamenají opak.

Že se vydání ukázalo, si aplikace poznamená **až ve chvíli, kdy je okno na obrazovce** — ne
když se to rozhodne. Kdyby se okno neotevřelo, zůstane značka na místě a příští spuštění to
zkusí znovu; opačné pořadí znamená vydání ohlášené „na papíře“, které se neukáže nikdy.

**Okno mluví o tom, co vyšlo na GitHubu, ne o spuštěném buildu**, a nevypisuje proto číslo
verze. Verze v bundlu (`MARKETING_VERSION`) tagy nikdy nesledovala, takže by tvrdila `0.1`;
a u lokálního buildu se ty dvě věci rozcházejí v obou směrech. Aplikace si místo toho pamatuje
poslední **viděný tag** a nabízí, co je novější. **První spuštění mlčí** a značku jen založí —
jinak by po startu vypadala jako nová celá historie.

## Klíčová rozhodnutí

| | |
|---|---|
| **Reviewery** | Běží nezávisle a paralelně. Texty nálezů se mezi nimi neslučují — nesouhlas dvou reviewerů je informace. Shoda na stejném `file:line` se označí odznakem `2×`. |
| **Jazyk nálezů** | Volba v nastavení, ne natvrdo. Řeší se **překladem po doběhnutí**, ne instrukcí v promptu: psát rovnou česky měřitelně ubírá nálezy. Reviewer píše v jazyce, ve kterém je nejsilnější; jazyk je věc zobrazení. |
| **Závažnost** | Aplikace nevymýšlí vlastní škálu. Seskupuje podle `category` z výstupu reviewera a odvozuje jediný blokující boolean (`verdict == CONFIRMED` a `category` v blokující sadě). Z toho vypadne návrh verdiktu. |
| **Falešně pozitivní nálezy** | Normální provoz, ne chyba. Jeden nález se dá odmítnout jako `neplatný` nebo `irelevantní` a ostatní platí dál; do verdiktu a do řádku seznamu se nepočítá, ale z okna nezmizí — sbalí se. Označení bydlí na záznamu, ne na nálezu, aby ho nesmazalo opakované review týmž skillem, a platí jen pro ten commit: nálezy jsou klíčované head commitem. |
| **Oprávnění** | Reviewer je read-only: `Write` ani `Edit` nemá povolené a `git push` s `gh` jsou výslovně zakázané. Ověřeno spuštěním, včetně toho, že zákaz platí i na `git push` s vypsanou URL — bez něj by session uměla pushnout do mého repozitáře, protože `origin` v cache míří na skutečné repo. |
| **Token** | Aplikace na GitHub token nikdy nesahá. Autentizace je delegovaná na `gh`, který credential drží v keychainu. |
| **Prompt review** | Psaná **šablona** se zástupnými texty a **jádro**, které se připojí vždycky. Dělí se to proto, že věta o `ReportFindings` není styl, ale kontrakt: bez ní reviewer nálezy napíše textem a rozbitý sběr vypadá jako čisté review. Výchozí šablona je doslova ten text, co byl v kódu, prázdná znamená „ber výchozí“ a chybějící zástupný text je chyba u pole — neplatná šablona se neuloží a review se s ní nespustí. Globálně, ne per repo: prompt je „jak vypadá review u mě“, ne vlastnost repozitáře. |
| **Časový limit běhu** | V nastavení, globálně i per repo, s rozsahem 5–60 minut a **bez volby „bez limitu“**: timeout je jediná pojistka proti session, která se zacyklí, kdežto denní strop a limit souběhu omezují jen počet běhů. Horní mez je vazba na účet (strop krát denní limit je nejhorší den), dolní proti tomu, aby limit dělal `timedOut` z review, které fungovalo. Putuje s požadavkem, takže rozjetý běh doběhne s tím svým; ke staršímu výsledku se číslo nepíše, protože uložený běh limit nenese. Sdílí ho kontrola nálezů — tatáž session, tentýž strom, tytéž peníze. |
| **Konfigurace** | Tři úrovně: globální default, sada podle programovacího jazyka repa a override per repo (režim auto/manual, sada skillů, blokující kategorie, časový limit). Co si repo neřekne, bere globálně — proto je override `nil`, ne prázdná hodnota. Edituje se ručně v `config.json` i oknem nastavení; obojí píše do téhož souboru. |
| **Odesílání na GitHub** | Platí pro review, odpovědi do vláken, komentáře pod PR, labely s reviewery, od #465 **merge vlastního PR** a od #466 **přetlačení vlastní větve** (`git push --force-with-lease`, jediný zápis do remote v celé aplikaci). Ve výchozím stavu vypnuté a zapíná se v nastavení, globálně i per repo. Brána je jedno místo (`PublishScope`), na které se ptá publisher i okno — jinak by tlačítko slibovalo něco, na čem odeslání skončí. Proti omylu nechrání seznam rep, ale potvrzení s úplným výpisem payloadu a kontrola, že se posílá proti commitu, který jsi viděl — u merge navíc **hlava v payloadu**, na kterou GitHub odpoví `409` a nemergne nic. |
| **Notifikace** | Slévají se nad seznamem z jednoho tiku pollingu, ne přes vlastní čekací okno — tik dodá všechna nová PR naráz, takže se slévá právě to, co se stalo mezi dvěma tiky, a nepotřebuje to stav ani zdržení hlášky. Vypnout je jde po událostech; s vypnutým hlavním přepínačem se nežádá ani o systémové oprávnění, protože dialog za něco vypnutého je dialog za nic. |
| **Novinky v aplikaci** | Okno mluví o tom, co vyšlo na GitHubu, ne o spuštěném buildu — verze v bundlu tagy nikdy nesledovala, takže by tvrdila `0.1`. Značka je poslední **viděný tag** v předvolbách aplikace (stav aplikace, ne nastavení k editaci) a historie se drží v paměti do konce běhu: disková cache by dala offline režim, ale je to další store s vlastním úklidem. |
| **Vzhled okna** | Tmavý, světlý, nebo podle systému — ovládá se **z levé lišty**, kde ho má návrh, a rozhoduje o tom jediný řádek (`NSApp.appearance`), ne větvení podle režimu. Barvy zůstávají v paletě, kde jednu hodnotu vybírá dynamická systémová barva podle vzhledu, ve kterém se zrovna kreslí; přepínač proto volí režim, ne paletu, a platí naráz pro všechna okna. Uplatňuje se na tom jednom místě, kterým konfigurace vchází do běžící aplikace — ve view by se minul okna, které zrovna není otevřené. |
| **Kapsle a odznaky** | Stav a počet nese v okně **mono kapsle** (`.pill` z návrhu: mono 10,5, odsazení 7 a 2) a metrika je na jednom místě (`designPill`) — do #348 stála v sedmi kopiích a jedna z nich se rozešla na `11` bez mono, takže v hlavičce karty popisu vypadala jako jiný druh prvku. Mono není ozdoba: odlišuje **stav** od labelu z repozitáře, který je slovo a sází se v UI fontu. Odznak s počtem v railu je od #366 **červený a uvnitř rámu ikony**, jak ho kreslí návrh — fialový akcent v tomhle okně znamená „tady jsi“, takže odznak v téže barvě neříkal nic, a text v barvě plochy okna má na červené kontrast 5,4 proti 3,3 u bílé. |
| **Rozměry v okně** | Šířka se v zanořeném stromu **předává, ne vyjednává**. `frame(maxWidth: .infinity)` na každé úrovni zanoření stojí ~5,5× na úroveň, takže okno na PR s 2000 změněnými řádky tuhlo dvacet minut na plném CPU — a to v obou tabech, protože o obsah vůbec nešlo, jen o tvar stromu. Šířka se proto měří jednou na hranici obsahu tabu a posílá dolů. Pružná výška v líném seznamu je tatáž chyba a řešila se dřív u dvojice řádků diffu. |
| **Dostupnost služeb** | Jede na skutečném provozu, ne na sondě: `gh auth status` na timeru by stál spawn procesu a přístup do keychainu — a projde i tehdy, když skutečné volání selže na rate limitu. Status pages jsou proti tomu levné (`components.json` s `ETagem`) a odpovídají na to, co z volání nezjistíme: jestli je problém na jejich straně. |

## Požadavky

- macOS 26, Xcode 26
- [`gh`](https://cli.github.com) — přihlášený (`gh auth login`)
- `claude` — Claude Code CLI
- `git`
- Při **prvním buildu síť** — rozpouští se jediná závislost třetí strany,
  [`SwiftTerm`](https://github.com/migueldeicaza/SwiftTerm) (#459), připnutý na `1.11.2`.
  `Package.resolved` je v repu, takže se verze nikam neposune sama.

Kromě těch tří binárek chodí aplikace na síť **jedinou vlastní cestou** (`HTTPGetting`) a jsou na
ní dvě věci: stav komponent ze status pages GitHubu a Claude pro stavový řádek, a **avatary**
autorů a komentujících. Obojí jsou veřejné endpointy, jde o `GET` bez tokenu a bez cookies, a když
se nepovede, aplikace o něj nezavadí — puntík se pak řídí jen skutečnými voláními a místo avataru
se nakreslí zástupný symbol. Vše ostatní — včetně anotací a logu spadlého checku — jde přes
podprocesy `gh`, `git` a `claude`.

Aplikace binárky hledá absolutní cestou, protože GUI aplikace spuštěná z Finderu nedědí
`PATH` z shellu. Nejdřív zkusí známá místa (`/opt/homebrew/bin`, `/usr/local/bin`,
`/usr/bin`, `~/.local/bin`), a co v nich není, dohledá v `PATH` login shellu. Ten čte
`.zshenv`, `.zprofile` a `.zlogin`, ale **ne `.zshrc`** — kdo má nástroj mimo známá místa
a `PATH` doplněný jen v `.zshrc`, musí cestu přidat do `.zprofile`.

Když něco chybí, aplikace se nespustí do prázdna — ukáže blokující obrazovku se **všemi**
problémy naráz: u každého nástroje cestu, kde se našel, nebo k čemu je a čím se instaluje.
U `gh` navíc kontroluje přihlášení. Po instalaci stačí `Zkusit znovu`, restart není
potřeba.

## Build

Spustit aplikaci — jeden příkaz, buildne v Debug, nainstaluje do `/Applications` a otevře
okno:

```bash
./bin/run.sh
```

Samotný build a testy:

```bash
xcodebuild -project PRism.xcodeproj -scheme PRism -derivedDataPath build.noindex build
```

```bash
xcodebuild -project PRism.xcodeproj -scheme PRism -derivedDataPath build.noindex test
```

`bin/run.sh` buildí do `build.noindex/` v repu (`-derivedDataPath`), aby byla cesta k `.app`
předvídatelná; složka je gitignorovaná. Před spuštěním ukončí předchozí instanci.

**Přípona `.noindex` v názvu je funkční, ne kosmetická.** Bez ní si LaunchServices kopii
v `build/` samo zaregistruje — po odregistrování je do 25 vteřin zpátky — a ve Spotlightu
i v `Otevřít v aplikaci` pak stojí dva PRismy se stejným jménem, ze kterých se nedá vybrat.
Spotlight `.noindex` složky neprohledává, takže se registrace sama nevrátí; Xcode ji ale na
konci buildu přidá výslovně a `xcodebuild test` navíc testovacího hosta **spouští**, čímž
ho zaregistruje taky. `bin/run.sh` proto po instalaci tu jednu cestu odregistruje — a protože
do `build.noindex/` míří i testy, uklidí tím i po nich. Proto ten přepínač patří i k nim.

**A při každém spuštění zamete i záznamy o PRism bundlech, které na disku nejsou** — po zaniklých
worktree, po slotových bundlech a po testovacích hostech (#398). Na ty odregistrování jedné cesty
nedosáhne: skript, který měl odregistrovat, zanikl se svým stromem. Vybírá se **podle toho, co na
disku chybí, ne podle jména**, takže hlavní aplikaci ani běžící instanci jiného slotu to vzít nemůže.
Rozhoduje se z výpisu databáze a ověřuje **zpětným čtením** — `lsregister -u` totiž vrací nenulu i
nad cestou, která v databázi vůbec není, takže jeho návratový kód o úspěchu nemluví.

Hotový bundle pak **nainstaluje do `/Applications` a spustí odtud**, protože jinde
nefungují notifikace: z `build.noindex/` i z `~/Applications` vrací systém
`Notifications are not allowed for this application` a stav oprávnění zůstane `denied` —
bez dialogu a bez záznamu v Nastavení systému, takže se to nedá ani ručně povolit.
Ověřeno i na minimální cizí aplikaci s jiným bundle identifikátorem, takže to není
vlastnost PRismu, ale toho, odkud je aplikace spuštěná.

Skript odmítne přepsat bundle, který se hlásí cizím identifikátorem, a když se instalace
nepovede, radši nespustí nic — spuštěná stará verze z `/Applications` je přesně ta past
„koukám na starý build“.

### Diagnostika kreslení (#361)

Když okno začne spálit jádro na nečinnosti, `sample` ukáže, **kde** hlavní vlákno je, ale ne
**kolikrát** se co přeložilo. Na to je diagnostika, která se zapíná jedním přepínačem:

```bash
./bin/run.sh --diagnose
```

Aplikace pak zapisuje do `~/Library/Application Support/PRism/diagnostics.log` — řádek za sekundu
s časem, počtem kol runloopu, CPU hlavního vlákna a počtem průchodů `body` po typech views. Soubor
se dá poslat v příloze.

**Sezení má svůj soubor** (#412). Dosavadní záznam se při startu uloží vedle jako
`diagnostics-do-<čas posledního zápisu>.log` a nové sezení začíná prázdné, takže strop 8 MB platí na
**tohle** sezení. Do #412 se přípisovalo a strop se počítal napříč sezeními — naměřeno, že záznam
narazil na strop ve 4:01 ráno a dalších 42 hodin aplikace běžela bez záznamu. Uložených záznamů se
drží nejvýš dvacet a nejvýš 64 MB; maže se od nejstaršího, nejnovější nikdy, a co rotace udělala
(kam se uložil předchozí, co se smazalo, co se nepovedlo) je **napsané v záznamu**. Velikost
předchozího souboru a počet uložených hlásí `bin/run.sh` při startu.

**Klid se sráží do minutového souhrnu** (`za 61.00 s klid: 57 úseků, 235 kol runloopu, 0.366 s CPU,
1 bez kola runloopu`), místo řádku za sekundu. Změřeno nad skutečným záznamem: klidné úseky byly
89 % hlavních řádků a 60 % objemu souboru, a příloha o grafu k nim nestála ani jednou. Záchvat se
naopak zapisuje pořád po sekundách — hoření ani průchod tělem klid není —, takže je z náběhu vidět,
kdy kolo začalo. Mezera v souboru tím zmizela úplně: dokud souhrny chodí, záznam žije.

**Zaseknuté okno v něm je vidět, a to je celý smysl** (#391). Řádky zapisuje vlastní vlákno, ne
observer hlavního runloopu, takže se píše dál i tehdy, když hlavní vlákno runloop vůbec nepustí ke
slovu — takový úsek má `0 kol runloopu`, celou sekundu CPU a větu `HLAVNÍ VLÁKNO NEPUSTILO RUNLOOP KE SLOVU`. Do #391 to byla
mez, o které se vědělo: ve čtvrtém záchvatu (#361) přestal záznam **v okamžiku ztuhnutí** a zbylo
z něj jen to, co bylo předtím.

**A od osmého kola u #361 řekne i to, co se v tom kole přepočítává.** Počitadlo průchodů `body`
totiž v hořícím kole mlčí — nepřeloží se v něm ani jedno tělo. Za hlavním řádkem úseku proto stojí
ještě dva až pár řádků odsazených: kolikrát se ozvala která část líného seznamu (`graf:
DiffRow.id=857 …`) a **evaluační zásobník AttributeGraphu** — tedy jména atributů od toho, co se
počítá teď, k tomu, kdo si o to řekl, a u vstupů příznak `changed`:

```
za 1.01 s: 0 kol runloopu, 1.007 s CPU — HLAVNÍ VLÁKNO NEPUSTILO RUNLOOP KE SLOVU
    graf: DiffRow.id=857 FileDiff.id=453 DiffPairBlockRow.geometry=172
    zásobník: 6 dotazů, 6 vzorků, kořen LazySubviewPrefetcher<…>=3, vrchol LazySubviewPlacements<…>=3, změněné vstupy CoordinateSpaceNameTransform=5
    #0: 2254672 LazySubviewPlacements<LazyVStackLayout> -> Array<_LazyLayout_PlacedSubview>
    2254192 CoordinateSpaceNameTransform -> ViewTransform, changed
```

Čte se to jednou funkcí privátního frameworku a **jedině se zapnutou diagnostikou**; když ji systém
nemá, stojí to v souboru hned za hlavičkou, takže „graf nic neřekl“ a „graf nejde otevřít“ nesplyne.

**Vypnutá nestojí nic** (jedna podmínka na začátku `body`, resp. u dotazu na identitu řádku)
a **vypne se sama**: příznak umře
s procesem, takže další `./bin/run.sh` bez `--diagnose` je zpátky v normálním provozu. Že je
zapnutá, je vidět z banneru skriptu i z hlavičky sezení v souboru. Proč to není přepínač
v nastavení a co si diagnostika nesmí dovolit, je v
[`docs/architektura.md`](docs/architektura.md), sekce *Diagnostika kreslení*.

### Paralelní vývoj — sloty

Vývoj se zdržuje čekáním, takže se dá pracovat ve víc oknech naráz. Překáží tomu jediná věc:
`bin/run.sh` bez dalšího zařízení instaluje pořád do stejného `/Applications/PRism.app`,
ukončuje běžící instanci a všechny instance sdílejí jednu cache. Druhé okno by tedy
sestřelilo aplikaci, se kterou se zrovna pracuje, a rozestavěný build by sáhl na uložené
nálezy a rozdělané drafty.

Řeší to **slot**. Pracovní strom se založí skriptem:

```bash
./bin/worktree.sh a issue-231-neco
cd ../PRism-a && ./bin/run.sh
```

Vznikne strom `../PRism-a` s novou branchí z `origin/main` a se souborem `.prism-slot`.
Ten pak čte `bin/run.sh` a odvodí z něj celou identitu instance:

| | hlavní strom | slot `a` | `xcodebuild test` |
|---|---|---|---|
| bundle ID | `com.ondrajodas.prism` | `com.ondrajodas.prism.a` | `com.ondrajodas.prism.testhost` |
| v `/Applications` | `PRism.app` | `PRism-a.app` | neinstaluje se |
| jméno v Docku | `PRism` | `PRism-a` | `PRism` |
| cache | `~/Library/Application Support/PRism/` | `…/PRism-a/` | `…/PRism/`, tedy sdílená |
| build | `build.noindex/` v tom stromu | vlastní, cesta je relativní | `build.noindex/` v tom stromu |

Bez souboru `.prism-slot` se nemění vůbec nic, takže hlavní strom zůstává tou aplikací,
která se používá. Slotů může být víc; slot je libovolný řetězec z písmen, číslic a pomlček,
protože jde do bundle ID.

**Třetí sloupec je testovací host a od #411 má vlastní doménu.** `bin/run.sh` předává
`PRISM_SLOT` (a `PRISM_SLOT_LABEL`) na příkazové řádce **vždycky, i prázdné**, takže identitu
aplikace stanoví ten skript; **výchozí hodnota v `project.pbxproj` je `.testhost`**, a platí
tedy pro každý build, který si o identitu neřekl — pro `xcodebuild test` i pro samotné
`xcodebuild … build`. Bez toho běžel `xcodebuild test` jako `com.ondrajodas.prism`, a všechno,
co v testu prošlo `@AppStorage` nebo `UserDefaults.standard`, **zapisovalo do nastavení, které
se doopravdy používá** — po jednom běhu tam takhle ležela uložená velikost sheetu, návštěvy
u vymyšlených PR (`cli/cli#1` s časem z roku 1970) a poslední viděné vydání. Podrobnosti,
včetně zamítnutých cest, jsou v [`docs/testovani.md`](docs/testovani.md).

Dvě věci, které z toho plynou. **`bin/slot-cleanup.sh testhost` po té doméně uklidí** — je to
slotové jméno, takže na ni platí tentýž skript jako na sloty. A **`xcodebuild test` po
`bin/run.sh` (nebo naopak) nespustí překlad znovu**: měřeno, přeložily se nula souborů, jen se
přepsal `Info.plist` a podepsal bundle. **Cache sdílená zůstává** — `CFBundleName` se nemění,
takže testovací host pořád píše `sessions.json` do cache hlavní instance (viz `RunningSessions`);
#411 řešilo `UserDefaults`, ne cache.

**Kořen cache si aplikace odvozuje z `CFBundleName`**, ne z konstanty — proto má slot vlastní
konfiguraci, klony i uložené nálezy. Je to ta podstatná část: build s rozbitou persistencí
nemá jak smazat rozdělaný draft, tedy ručně psanou práci.

Konfigurace se do slotu zkopíruje, ale **očištěná** — bez povoleného odesílání, bez
notifikací a bez automatického spouštění review, a to **na obou úrovních**: globálně
i u každého repa. Odesílání proto, že výchozí stav je vypnuto a u rozestavěného buildu to
platí dvojnásob; notifikace proto, že slot má vlastní `announced.json` a ohlásil by jako nové
úplně všechny PR ve frontě; automat proto, že by spouštěl review, které nikdo nečte a za které
se platí. Když na stroji není `jq`, konfigurace se **nezkopíruje vůbec** — kopírovat ji
neočištěnou by znamenalo předat slotu povolené odesílání.

Očistu drží **`bin/slot-config.sh`** a je to jediné místo, kde existuje (#262):

```bash
./bin/slot-config.sh      # slot se přečte z .prism-slot v tomhle stromě
./bin/slot-config.sh d    # slot výslovně; takhle to volá bin/worktree.sh
```

Samostatný skript je proto, že do slotu se nedostane každý přes `worktree.sh` — subagent
v paralelním vývoji má strom od harnessu, takže si očistu do #262 opisoval, a dvě kopie
znamenají, že se příští oprava udělá jen v jedné. Přesně to se stalo: `mode` se čistil
globálně, ale ne u rep, takže per-repo override `mode: automatic` očistou prošel a přebil
globální `manual` (per-repo override je přednější — je to celý smysl `resolved(for:)`).
Slotová aplikace si sama pustila review za **2,80 $ v jednom slotu a 1,16 $ v dalším**.

Tři vlastnosti, kterými se ta chyba splácí:

- **Vypíše, co našlo.** Repa s automatem jmenovitě, počet rep s povoleným odesíláním — očista,
  která proběhne potichu, se nedá zkontrolovat.
- **Ověří výsledek, ne filtr.** Po přepsání se v datech hledá zbylý automat a povolené
  odesílání; když se něco najde, **nezapíše se nic** a skript skončí nenulově.
- **Existující konfiguraci slotu nepřepíše tou hlavní** (proklikané nastavení je ruční práce),
  ale **pustí na ni tutéž očistu** — sloty se používají opakovaně a v cache může ležet
  konfigurace z doby, kdy očista automat u repa nechytala.

Co se čistí a co ne, je vyjmenované v komentáři skriptu — **celý `GlobalConfig`**, včetně
klíčů, které se nechávají být, a důvodu u každého. Nový klíč, který má obě úrovně
(`GlobalConfig` i `RepositoryConfig`), do toho výčtu patří, i kdyby se nakonec nečistil.

Po mergnutí branche se slot uklidí **jedním příkazem** (#398, #399) a strom se odklidí:

```bash
./bin/slot-cleanup.sh      # slot z .prism-slot v tomhle stromě
./bin/slot-cleanup.sh a    # slot výslovně
git worktree remove ../PRism-a
```

Skript ukončí aplikaci slotu (Apple eventem, ne `killall`em — běžící review se tedy ohlásí), smaže
bundle z `/Applications`, cache, **záznamy o složkách slotu v `~/.claude.json`**, **doménu
v `UserDefaults`** i prázdný plist po ní, a nakonec zamete databázi LaunchServices. Bez slotu **odmítne**: cílem by byla hlavní instance, tedy ta aplikace,
která se používá — a v `/Applications` nesmaže bundle, který se hlásí cizím identifikátorem (tatáž
kontrola, jakou má `bin/run.sh` u instalace, a od #398 na jednom místě).

Doména se maže proto, že **nastavení přežije smazání bundlu i cache**: příští slot na tomtéž písmenu
by nastartoval s nastavením po předchůdci, tedy i s tím, co z něj `bin/slot-config.sh` schválně
vyndal. `defaults delete` má u toho dvě pasti a obě jsou změřené — nad neexistující doménou vrací
**nenulu** a po sobě nechá **prázdný plist** (42 B), na kterém `defaults read` už tvrdí, že doména
neexistuje. Úklid proto maže obojí a ověřuje se **zpětným čtením, ne návratovým kódem**.

**Záznamy v `~/.claude.json` se od #484 uklízejí taky.** Aplikace do konfigurace Claude Code
zapisuje důvěru ke složkám **své** cache (#460), a od #479 ne jen ke kořeni, ale ke **každému
pracovnímu stromu review** — záznamů po slotu tedy vzniknou desítky a bundle, cache ani doména je
s sebou nevezmou. Sahá se přitom do souboru cizího nástroje, takže na to platí tytéž pojistky jako
na zápis v aplikaci: **na soubor, kterému skript nerozumí, se nesahá** (bez `jq`, nebo když se
obsah nedá přečíst jako objekt JSON, se nepíše nic a řekne se to), **zachová se, co v něm je**,
a **píše se atomicky** — přes soubor vedle cílového, s právy, která měl původní.

Maže se jedině to, co leží pod kořenem cache **toho slotu**: klíč rovný
`…/Application Support/PRism-<slot>`, nebo začínající toutéž cestou **a lomítkem**. Lomítko je
podstatné — bez něj by úklid slotu `a` vzal i záznamy slotu `ab`; hlavní instance (`…/PRism/`) ani
cizí projekty se pod ten prefix nedostanou. Porovnává se s **cestou, ne s tím, co na disku zbylo**
(cache je v tu chvíli o krok dřív smazaná), a to v obou podobách kořene — rozvinuté i nerozvinuté,
protože klíč si `claude` ukládá přes `realpath` a domovská složka umí ležet za symlinkem.
Kontroluje se to **nad výsledkem, ne nad filtrem**: než se soubor vymění, musí v něm zbýt nula
záznamů pod kořenem slotu a **přesně tolik ostatních, kolik jich v něm bylo** — jinak se nezapíše
nic. Záznamy po slotech, které zanikly dřív, uklidí nejbližší běh skriptu.

### Katalog emotikonů

Ve třech polích, ze kterých text odchází na GitHub — komentář pod PR, odpověď do vlákna a tělo
review v panelu — se píše `:ta` a nabídka doplní zbytek; do textu se vloží **znak, ne zkratka**
(`:tada:` by byl náhled, který tvrdí něco jiného než výsledek na GitHubu). Vybírá se klávesnicí
(`↑↓`, `↵`, `esc`), v tabu `Zeptat se` nabídka **není** — to není text pro GitHub a `Return` si
tam bere odeslání otázky.

Katalog je **v aplikaci, ne z GitHubu**: `GET /emojis` vrací jména a adresy obrázků, ne znaky, a
seznam se nemění. Generuje se ze zdroje v repu:

```bash
swift bin/make-emoji.swift    # bin/emoji-sources/gemoji-emoji.json → App/Support/EmojiTable.swift
```

Zdroj je `db/emoji.json` z [github/gemoji](https://github.com/github/gemoji) (MIT) — ten seznam,
ze kterého GitHub své shortcody bere. Leží v repu schválně: bez něj by se katalog nedal vyrobit
znovu. Vygenerovaný soubor je **jeden velký řetězec, ne pole 1870 struktur** (doslovné pole té
velikosti by type-checker překládal minuty) a shortcody bez Unicode (`:shipit:`, `:octocat:`)
v něm nejsou — nemají znak, který by se vložil.

### Ikona

Ikona je **generovaná z kódu**, ne obrázek přinesený zvenčí:

```bash
swift bin/make-icon.swift                    # nasazená varianta
swift bin/make-icon.swift split              # druhá barevná varianta
swift bin/make-icon.swift split /tmp/náhled  # jen vykreslit, bez zásahu do repa
```

Motiv jsou znaky obou nástrojů rozpůlené diagonálou zleva zdola doprava nahoru — vlevo
nahoře Claude, vpravo dole GitHub. Skládá se z **oficiálních** značek (`bin/icon-sources/`,
favicony obou služeb), takže se nekreslí zpaměti; barvy jsou z nich taky. Nasazená je
varianta s krémovým znakem na oranžové, druhá (Claude v původních barvách) zůstává v repu,
aby se dalo přepnout.

**Malé velikosti nejsou zmenšené velké** — pod 64 px se kreslí hruběji, protože ve 16 bodech
ikona skončí v přepínači aplikací a jemná kresba se tam slije.

Po překreslení je potřeba **restartovat Dock** (`killall Dock`), jinak se dál dívá na starou
ikonu z cache a vypadá to, že se nic nezměnilo.

Aplikace běží **bez App Sandboxu** — spouští `git`, `gh` a `claude` a zapisuje do vlastní
cache.

### Podpis

Výchozí podpis je ad-hoc (`CODE_SIGN_IDENTITY = -` v `Signing.xcconfig`), takže build
nepotřebuje Apple účet ani tým a projde na jakémkoli stroji bez přípravy. Developer ID
podpis a notarizace by byly potřeba až pro distribuci.

Ad-hoc podpis ale **nemá stálou identitu**: každý build dá jiný otisk, takže macOS považuje
aplikaci pokaždé za jinou a povolení udělená přes TCC se na novou verzi nevztahují. Prakticky
to znamená dotaz na přístup do **Stažených souborů** po každém rebuildu. Aplikace tam
nesahá — vyvolává ho `claude`, který si při startu bere prostředí z uživatelova shellu, a ten
načte `~/.zshrc` sourcující Google Cloud SDK rozbalený v `~/Downloads`. Dotaz se proto objeví
až při spuštění review, ne po startu aplikace.

Stálou identitu dá vlastní certifikát. Vyrobí ho jednorázově:

```bash
./bin/setup-signing.sh
```

Skript vytvoří self-signed certifikát typu *Code Signing* s názvem `PRism Local` v login
keychainu a napíše `Signing.local.xcconfig` s jeho jménem; odtud si ho přes `#include?`
vezme `Signing.xcconfig`, takže se podepisuje stejně ve `bin/run.sh`, v `xcodebuild` i v
Xcode. Ten soubor se **necommituje** — jméno certifikátu je vlastnost stroje, ne repa, a
bez něj se spadne zpátky na ad-hoc. Systém si přitom může říct o přihlašovací heslo —
jednou při zápisu do nastavení důvěry (bez něj se self-signed certifikát mezi platné
identity nezapočítá) a při prvním buildu ještě o přístup ke klíči, kde stačí kliknout na
*Vždy povolit*. Ten druhý dotaz odbourá předem heslo zadané na řádku, který skript nabízí;
přeskočit ho jde Enterem.

Že je podpis stálý, se ověří takhle:

```bash
codesign -dv --verbose=4 build.noindex/Build/Products/Debug/PRism.app
```

Ad-hoc build hlásí `Signature=adhoc`, podepsaný `Authority=PRism Local`. Na ad-hoc podpis
upozorní i `bin/run.sh`, protože jinak je příčina vracejících se dotazů neviditelná.
Certifikát se odstraní přes `security delete-identity -c "PRism Local"`.

## Struktura

```
PRism.xcodeproj/          Xcode projekt (shared scheme je verzovaný)
App/                      zdrojáky aplikace — target PRism
  Models/                 doménové modely: PR, identifikátory, stav review
  Environment/            přístup ke stroji: hledání binárek, podprocesy, preflight, notifikace, předvolby
  GitHub/                 čtení PR a konverzace přes gh CLI: gateway, typované chyby, tvar výstupu;
                          labely a vyžádaní reviewery i nabídky k nim (#392), hlavy víc PR jedním
                          dávkovým dotazem (#420) a repozitáře organizace (#532 — nejdražší čtení,
                          proto vlastní limit) — pořád bez zápisu
  Checkout/               vlastní cache repozitářů: klony, worktrees, úklid
  Config/                 config.json: globální default, override per repo, čtení a zápis
  Diff/                   parsování unified diffu na soubory, hunky a řádky, slití do dvojic pro pohled
                          vedle sebe a porovnání uvnitř přepsané dvojice (word-level diff)
  Health/                 dostupnost služeb pro stavový řádek: status pages, signály, monitor
  Markdown/               vykreslení Markdownu z GitHubu: bloky (včetně citací a výstrah), inline HTML
                          od botů, škála nadpisů a mezer, zapamatované rozložení na bloky
  Policy/                 čisté funkce: slučování zdrojů, řazení, stav řádku, odhad jazyka, hledání v paletě,
                          složení zadání pro agenta na vlastním PR (#333), co z něj zbývá předat (#334),
                          co na něm od minule udělal někdo jiný, i za jakou cenu se na to ptát (#335),
                          a jestli reviewer vůbec otevřel kód — tedy jestli se z běhu dá tvrdit čisto (#383);
                          o čem se v dění hlásí, co je nepřečtené a jak se dělí po dnech (#414),
                          na hlavy kterých PR se tik zeptá a čím se datuje zastarání nálezů (#420);
                          jestli se z dotazu nabídne založení nového labelu a jakou dostane barvu (#413)
  Publish/                jediná cesta ven: odeslání review, odpovědi do vláken a jejich vyřešení, komentář pod PR,
                          labely a vyžádání reviewera na vlastním PR (#392), založení nového labelu
                          v repozitáři (#413 — sedmá a jediná metoda, která píše mimo PR), brána z nastavení
  Review/                 spuštění session claude a překlad stream-json na nálezy;
                          zadání PR pro reviewera vedle pracovního stromu (#120),
                          dotažení textu issue vlastní krátkou session (#345)
                          a rozhovor nad PR (#452 — třetí vyjmenovaná session, užší sada
                          nástrojů, --resume a materiál v souboru vedle stromu)
  Polling/                obnovování seznamu v intervalu, backoff, neaktuální data
  Store/                  AppStore — stav, který kreslí okno (stav v AppStore.swift, metody v AppStore+*.swift);
                          ReviewStore a ReviewDraftStore — nálezy a rozdělaná review na disku;
                          HandoffLedger — razítka předání zadání agentovi (#334);
                          ActivityNoticeLedger — o čem už se u vlastního PR hlásilo (#335);
                          ActivityLog a ActivityVisitLedger — záznam dění se stropem 200 položek
                          a značka poslední návštěvy té sekce (#414);
                          AskStore — rozhovory z tabu Zeptat se, klíčované PR, ne commitem (#452);
                          RepositoryCatalog a RepositoryCatalogStore — seznamy repozitářů organizací
                          v cache s denní obnovou (#532)
  Syntax/                 obarvení kódu: jazyky, tokenizace, paleta, zapamatování výsledků
  Terminal/               vestavěný terminál (#459): plocha SwiftTermu obarvená paletou, hlášení fokusu
                          a zabití popředí pty; hostitel drží od #460 víc relací na pull request
                          (TerminalSlot) a do každé umí napsat řádku (▶ v tabu Průběh)
  Support/                sdílené drobnosti bez příslušnosti k modulu;
                          diagnostika kreslení za přepínačem PRISM_DIAGNOSE (#361) —
                          včetně rotace jejího záznamu při startu sezení (#412)
  Views/                  SwiftUI obrazovky
    ReleaseNotes/         okno s novinkami — historie vydání a release notes vybrané verze
    Settings/             okno nastavení (⌘,) — sedm stránek v boční navigaci (#177)
  Assets.xcassets/        ikona aplikace (generovaná, viz bin/make-icon.swift)
Tests/                    unit testy — target PRismTests
  Models/                 testy modelů + pomocníci na Codable round-trip
  Environment/            testy Environment vrstvy + fakes
  Checkout/               testy klonování — proti fake runneru i skutečnému gitu
  Config/                 testy čtení, zápisu a slučování konfigurace
  Diff/                   testy parseru diffu proti skutečným výstupům gh pr diff a word-level rozdílu
  Health/                 testy status pages, monitoru dostupnosti a HTTP vrstvy
  Markdown/               testy parseru Markdownu (invariant: nic se neztratí), HTML od botů, sazby
                          (nadpisy, mezery, barvy výstrah) a cache; sonda na render do PNG
  GitHub/                 testy gateway a klasifikace chyb gh
  Policy/                 testy čistých funkcí
  Review/                 testy parseru a runneru proti skutečným streamům
  Polling/                testy pollingu proti fake gateway a fake času
  Publish/                testy odesílání — hlavně že se při neshodě neodešle nic
  Store/                  testy AppStore a persistence nálezů
  Views/                  testy řádků tabulky, modelu okna nastavení a novinek
  Syntax/                 testy detekce jazyka a obarvení kódu
  Support/                testy sdílených drobností
  Scripts/                testy skriptů v bin/ — úklid slotu a databáze LaunchServices
  Fixtures/gh/            skutečné výstupy gh z veřejných repozitářů (JSON i diffy)
  Fixtures/stream-json/   skutečné stream-json výstupy claude z reálných běhů
  Fixtures/statuspage/    skutečné components.json ze status pages (a jeden s dopsaným incidentem)
  Fixtures/transcript/    skutečné transcripty claude — dotažení nálezů z přerušeného běhu
bin/run.sh                build + spuštění jedním příkazem (--diagnose zapne diagnostiku kreslení)
bin/worktree.sh           pracovní strom se slotem — paralelní vývoj vedle běžící aplikace
bin/slot-config.sh        očištěná konfigurace do cache slotu (jediné místo, kde ta očista je)
bin/slot-cleanup.sh       úklid po slotu — aplikace, cache, ~/.claude.json, doména v UserDefaults, LaunchServices
bin/lib/bundles.sh        sdílené funkce nad PRism bundly a databází LaunchServices (sourcuje se)
bin/copilot-review.sh     vyžádání Copilot review na PR
bin/setup-signing.sh      jednorázová příprava stálého podpisu (self-signed certifikát)
bin/make-icon.swift       vykreslí ikonu do asset catalogu (bez závislosti, přes ImageRenderer)
bin/icon-sources/         oficiální značky, ze kterých se ikona skládá
bin/make-emoji.swift      vygeneruje katalog emotikonů do App/Support/EmojiTable.swift
bin/emoji-sources/        db/emoji.json z github/gemoji — zdroj toho katalogu
Info.plist                název aplikace, verze, minimální systém
PRism.entitlements        vypnutý App Sandbox
Signing.xcconfig          podpis: ad-hoc default + volitelný Signing.local.xcconfig
docs/architektura.md      podrobnosti po modulech
docs/testovani.md         co se u které oblasti testuje
docs/navrh.html           vizuální návrh (mockup) — zdroj, artifact je publikovaná kopie
docs/navrh.md             jak se s mockupem pracuje (čtení, aktualizace, schvalování)
docs/stav.md              co je hotové a co zbývá
docs/paralelni-vyvoj.md   jak se vyřizuje seznam issues naráz — sloty, subagenti, milníky, merge
docs/claude-cli.md        ověřené chování claude CLI (flagy, tvar eventů)
docs/github-cli.md        co na gh v tomhle repu padá, čím to nahradit, jak číst Copilota
docs/github-review-api.md ověřené chování zápisového review API GitHubu (spike k M6)
docs/superpowers/specs/   návrh a specifikace
CLAUDE.md                 pravidla pro práci v repu
README.md                 tento soubor
.gitignore                artefakty Xcode buildu, SPM, .DS_Store, Signing.local.xcconfig
.gitattributes            fixtures, které stojí na zakončení řádků (-text, ať je CRLF nedotčené)
```

`App/` a `Tests/` jsou v projektu napojené jako **buildable folders** — obsah se do
targetu bere z filesystému. Nový soubor stačí vytvořit, do `project.pbxproj` se nic
nezapisuje. `Info.plist` a entitlements proto leží v kořeni: cokoli uvnitř `App/`, co
není zdroják, by se zkopírovalo do `.app` jako resource.

Repo, Xcode projekt, target, produkt i to, co appka ukazuje v Docku, se jmenují stejně —
`PRism`. Swiftový modul taky (`PRODUCT_MODULE_NAME`), takže testy dělají
`@testable import PRism`.
