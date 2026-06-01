# dataset.domovina.tv

Tekstualni dataset hrvatskih YouTube podcasta i emisija — transkripti, dijarizacija,
sažetci, generirani članci i RAG artefakti. Sadrži **samo tekst/metapodatke**;
audio/video se ne pohranjuje u ovaj repo.

Trenutno: **~2.600 epizoda** u **39 kanala** (npr. `budi_frajer`, `mreze_rijeci`,
`mladi_za_domovinu`, `40_dana_za_zivot`, `zeljka_markic_i_narod_hr`, …).

## Struktura

```
data/
  <kanal>/
    <YYYYMMDD_naslov_yt_VIDEOID>/
      <YYYYMMDD_naslov_yt_VIDEOID>.<ekstenzija>          # datoteke epizode
      <…>.og-sections/manifest.json                      # poglavlja/sekcije
      <…>_screenshots/_manifest.json                     # manifest screenshotova
      <…>_raw/                                            # sirovi LLM outputi
```

Naziv direktorija epizode je `video_base` = `YYYYMMDD_naslov_yt_VIDEOID`, a sve
datoteke unutar nose isti prefiks.

## Vrste datoteka

Pipeline je organiziran u faze; svaka faza dodaje svoje datoteke uz istu epizodu.

### Izvor / preuzimanje (yt-dlp)

| Datoteka | Opis |
|---|---|
| `.info.json` | yt-dlp metapodaci (naslov, kanal, datum, trajanje, tagovi) |
| `.description` | Opis YouTube videa |
| `.txt` | Plain-text transkript |
| `.loudnorm.json` | Izvještaj o EBU R128 normalizaciji glasnoće (`input`/`output`/`target`) |

### Transkripcija i dijarizacija

| Datoteka | Opis |
|---|---|
| `.wav.srt` | Osnovni ASR transkript |
| `.wav.canary.srt` | Transkript NVIDIA **Canary** ASR modelom (primarni) |
| `.wav.canary.csv` | Canary transkript u CSV-u (segmenti s timestampovima) |
| `.wav.diarized.srt` | Transkript s oznakama govornika (osnovni) |
| `.wav.canary.diarized.srt` | Canary + dijarizacija — **glavni transkript** za sve dalje faze |
| `.wav.sortformer.srt` / `.wav.sortformer.diarized.srt` | Varijanta s NeMo **Sortformer** dijarizacijom |
| `.en.vtt` / `.hr.vtt` | WebVTT titlovi (engleski / hrvatski) |

### Speaker embeddings (identifikacija govornika)

| Datoteka | Opis |
|---|---|
| `.wav.canary.diarized.embeddings.titanet.json` | Vektori govornika (NVIDIA **TitaNet**) po segmentu |
| `.wav.canary.diarized.embeddings.pyannote_wespeaker34.json` | Vektori govornika (**pyannote/WeSpeaker**) — za prepoznavanje istog govornika kroz epizode |

### Sažetak

| Datoteka | Opis |
|---|---|
| `.wav.canary.summary.json` | Strukturirani sažetak (`model`, `source`, `summary`) |
| `.wav.canary.summary.md` | Sažetak u Markdownu |
| `.wav.canary.summary.en.json` | Engleski sažetak |
| `.wav.canary.summary.blocked.json` | Zapis kad je sažetak blokiran (safety filter) |

### Generiranje članka

Datoteke nose oznaku datuma i modela: `.wav.canary.diarized_<DATUM>_<MODEL>.*`
(npr. `_2026-03-20_gemini-2.5-flash`, `_2026-05-26_claude-opus-4-7`).

| Datoteka | Opis |
|---|---|
| `.outline.json` | Faza 1 — outline članka (`iterations`) |
| `.article.json` | Finalni dugi članak (`metadata` + `iterations`) |
| `.article.en.json` | Engleski prijevod članka |
| `_raw/faza1_outline.raw.txt` | Sirovi LLM output faze 1 (outline) |
| `_raw/faza2_iteracija_N.raw.txt` | Sirovi LLM output faze 2, iteracija N (pisanje članka) |
| `.article.magisterium.json` | Članak obogaćen citatima crkvenog učiteljstva (Magisterium) |
| `.article.magisterium.en.json` | Engleska verzija magisterium članka |
| `.article.magisterium_full.json` + `…_prompt.md` | Proširena magisterium varijanta + korišteni prompt |
| `.article.magisterium_full_v2.json` + `…_prompt.md` | v2 proširene varijante |
| `.article.magisterium_batch.json` | Batch-obrađena magisterium varijanta |
| `gemini_usage.json` | Praćenje tokena/troška Gemini poziva (`total_est_usd`, `runs`) |

### RAG artefakti (vektorska pretraga)

| Datoteka | Opis |
|---|---|
| `.rag_chunks.jsonl` | Tekst izrezan u chunkove (`id`, `text`, `metadata`) |
| `.rag_combined.jsonl` | Kombinirani chunkovi (transkript + članak) |
| `.rag_import.jsonl` | Chunkovi formatirani za import u vektorsku bazu |
| `.wav.canary.diarized_rag_ready.json` | Dijarizirani transkript pripremljen kao RAG chunkovi |

### Sekcije i screenshotovi

| Datoteka | Opis |
|---|---|
| `og-sections/manifest.json` | Poglavlja/sekcije epizode (`title`, `duration_sec`, `sections`) |
| `<…>_screenshots/_manifest.json` | Manifest screenshotova za članak (same slike `.png`/`.jpg` su isključene iz syncа) |

## Sync

`sync_dataset.sh` kopira tekstualne datoteke iz fetch outputa (s vanjskog diska)
u `data/` i opcionalno radi po jedan git commit po epizodi.

```bash
./sync_dataset.sh                     # samo sync (bez commitova)
./sync_dataset.sh --commit            # sync + commit po epizodi
./sync_dataset.sh --commit --push     # sync + commit + push na GitHub
./sync_dataset.sh --commit --dry-run  # prikaz bez commitanja
```

Sync radi po **whitelisti ekstenzija** (linije 65–76 u skripti):
`*.description *.txt *.md *.srt *.vtt *.json *.jsonl *.canary.csv`

Pošto su `*.json` i `*.jsonl` široki, **svaka nova JSON vrsta koju pipeline
počne generirati automatski ulazi u sync** — skriptu ne treba mijenjati.

Isključeno: sav binarni media (`.wav .mp3 .mp4 .webm .mkv .png .webp .jpg .m4a .part`),
macOS `._*` resource forkovi i generički `.csv` (prolazi samo `.canary.csv`).

Sync je inkrementalan: rsync sinkronizira u `.sync_staging/` cache (hardlinkovi,
bez dodatnog prostora), pa se samo nove/promijenjene datoteke organiziraju u
per-epizoda direktorije.

## Ostale skripte

| Skripta | Namjena |
|---|---|
| `sync_dataset.sh` | Sync teksta iz fetch outputa + per-epizoda commitovi |
| `sync_to_r2.sh` | Upload u Cloudflare R2 |
| `reorganize_data.sh` | Reorganizacija postojećih datoteka u per-epizoda strukturu |
| `calculate_r2_storage.sh` | Procjena R2 zauzeća |
| `dataset_stats.mjs` | Statistika dataseta |

## Licenca

Vidi [LICENSE](LICENSE).
