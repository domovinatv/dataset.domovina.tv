# Zašto epizoda koja čita evanđelje dobije 71 kod Magisteriuma

Epizoda: Ora et labora, 120 „Milosrđe Božje – Kako raste kraljevstvo Božje?” (`nBPDxzrAW0Q`).
Produkcijski Magisterium (27.10.2026., MCP, batch-of-1): **overall 71**, holistički 63.
Analiza 28.10.2026.: 10 dodatnih poziva Magisterium MCP-a s **istim produkcijskim promptom**,
mijenjan je samo ulaz.

## Zaključak

**Evanđelje dobiva ~96. Nisku ocjenu nosi voditeljev komentar, ne Sveto pismo ni način na
koji ga šaljemo.** Pipeline ne kvari rezultat: doslovni prijepis prolazi jednako ili lošije
od Opusova prepričavanja.

## Mjerenja

### 1. Od čega se epizoda sastoji (produkcijske ocjene sekcija)

| Dio | Trajanje | Sekcija | Prosjek | Najniža |
|---|---|---|---|---|
| Molitve (krunice, litanije, posvete) | 39 min (37 %) | 9 | **90** | 60 |
| Komentar voditelja (+ čitanja) | 61 min (57 %) | 25 | **63** | 42 |
| Najave i svjedočanstva | 7 min (6 %) | 4 | 78 | 74 |

Doslovno čitano Sveto pismo (Ef 5,21-33, psalam, Lk 13,18-21) traje ukupno **~2 min od 107**.
Evanđelje dana je ~30 s unutar sekcije 01:30:10, a ostatak te sekcije je tumačenje
(„sinovi tame… racionalnog, strogo ortodoksnog duha”).

Kontekst kataloga: 425 epizoda, medijan 88, p10 = 75. Epizoda 120 je oko 8. percentila.
Sekcija ispod 60: ovdje 11/38 (29 %), u katalogu 2,8 %.

### 2. Sam tekst Svetog pisma, isti prompt

| Ulaz | Ocjena |
|---|---|
| Lk 13,18-21 doslovno iz prijepisa (3 ponavljanja) | **98 / 96 / 94** |
| Ef 5,21-33 doslovno iz prijepisa | **94** (jedina primjedba: „žene muževima u svemu” čitati uz uzajamnu podložnost) |

Kad se pošalje samo Sveto pismo, ocjena je blizu 100, kako se i očekuje. Do 100 ne ide jer
skala za 90-100 traži „aktivno promiče i produbljuje”, a goli citat ništa ne razrađuje.

### 3. Opus prepričavanje vs doslovni prijepis (ista sekcija)

| Sekcija | Produkcija (članak) | Članak, ponovljeno | Doslovni prijepis |
|---|---|---|---|
| 01:30:10 evanđelje + tumačenje prispodoba | 56 | 64 | 52 |
| 00:46:11 predbračni odnosi → homoseksualnost, „generacijsko stablo” | 42 | 42 | 38 |
| 01:13:05 žalovanje za nekršćaninom, „kako se Boga ne bojiš” | 42 | — | **24** |
| 00:00:25 molitva oslobođenja („uzimam vlast i vežem”) | 60 | — | 68 |

- **Šum mjerenja je oko ±8** (56 → 64 za identičan ulaz; 42 → 42).
- **Prijepis je u prosjeku ~5 bodova strože ocijenjen od članka.** Opusovo prepričavanje
  ublažava („prema njegovu tumačenju”), dakle ne ruši ocjenu. Hipoteza „šaljemo dio, pa
  Magisterium nema kontekst” ne drži: sporne tvrdnje su u samom izgovorenom tekstu.

### 4. Zbog čega konkretno pada (primjedbe su utemeljene)

- **00:46:11 (42/38):** promiskuitet „vodi do homoseksualnosti” i prenosi se na potomke.
  KKC 2357: psihološki nastanak sklonosti „ostaje uglavnom neobjašnjen”; sklonost nije grijeh.
- **01:20:30 (42):** „za sakramentalni brak oboje moraju biti katolici” je činjenično netočno
  (brak dvoje krštenih je sakrament). „Mješoviti brakovi se u pravilu brzo raspadaju” nema
  izvor.
- **01:13:05 (42/24):** prijekor zbog prijateljstva s nekršćaninom i žalovanja za njim.
- **00:00:25 (60/68):** laik izgovara imperativnu formulu protiv zlih sila. Prema obredniku
  (i pismu Inde ab aliquot annis, 1985.) ta formula pripada egzorcistu.
- **01:30:10 (56):** racionalnost i „strogu pravovjernost” izjednačava s tamom.

Dio primjedbi je strog prema propovjedničkom žanru (npr. „ptice = anđeli i sveti”, „30 godina
u radionici”). Magisterium slikovite homiletske primjene čita kao činjenične tvrdnje, pa
gubimo nekoliko bodova i na neproblematičnim mjestima. To je manji efekt od gore navedenog.

### 5. Holistička ocjena (63) gleda samo naslove

`buildHolisticPrompt` šalje teme blokova i podnaslove, ne sadržaj (model to i kaže: „dostupna
je samo struktura”). Naslovi poput „Predbračni odnosi i mijenjanje partnera” spuštaju je.
Usput: polje `Podcast:` u svim promptovima je ime datoteke jer `article.metadata` nema naslov.

## Što bi imalo smisla (nije napravljeno)

1. **Prikazivati ocjenu po vrsti sadržaja**, ne samo prosjek: „Sveto pismo i molitve ~93 ·
   komentar voditelja 63”. Za kanale tipa „molitva + čitanja + laička propovijed” jedan broj
   miješa tekst Crkve i osobne teze voditelja. Podatak već postoji po sekcijama; treba samo
   oznaka vrste sekcije (može je dati outline/Opus).
2. U batch promptu dodati jednu rečenicu o žanru („homiletska primjena, ne egzegeza; ocjenjuj
   doktrinarne tvrdnje, ne slikovite primjene”). To bi skinulo dio nepravednih bodova, ali
   **ne bi** podiglo 42-ice, jer su one utemeljene.
3. Proslijediti pravi naslov epizode u `Podcast:` polje.

## Datoteke

- `analiza.job.json`, `prompts/`: točni promptovi (generator:
  `experiments/2026-10-28-magisterium-evandjelje/build_job.js` u repou)
- `results/*.mcp.json|raw.txt`: sirovi odgovori MCP-a (`holistic` = 3. ponavljanje evanđelja)
- `rezultati.json`: parsirane ocjene + primjedbe
- `client.log`: 10 poziva, 471 s, 0 neuspjelih
