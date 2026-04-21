# RawCull Rewrite Plan: Windows / Cross-platform med Flutter + Rust + OpenCV + ONNX

- **Versjon:** 1.0
- **Dato:** 2026-04-21
- **Status:** Approved
- **Relaterte ADR-er:**
  - [ADR-001: Engine stack (Rust vs C++)](../adr/ADR-001-engine-stack-rust-vs-cpp.md)
  - [ADR-002: ONNX Execution Providers på Windows](../adr/ADR-002-onnx-runtime-execution-providers-windows.md)

## Implementasjonsstatus

- ✅ Fase 1 kickoff fullført:
  - Opprettet `engine/rust/` workspace med `core` og `ffi`.
  - Opprettet CI-workflow for Rust med `fmt`, `clippy`, `check` og `test`.
  - Opprettet `apps/flutter_desktop/` struktur med `pubspec`, `lib/main.dart` og test-hook.
- ✅ M1 (første leveranse) implementert:
  - Rekursiv katalogscan for støttede filtyper.
  - Rating-modell og oppdatering per item.
  - FFI-funksjoner for `scan_catalog`, `item_count`, `get_item_path`, `get_item_rating`, `set_item_rating`.
- 🔜 Neste steg:
  - Koble Flutter UI direkte til native FFI-bibliotek.
  - Bytte placeholder-data med ekte katalogdata.
- ✅ M2 (thumbnail/cache baseline) implementert:
  - Disk-cache modul for thumbnails i Rust core.
  - FFI-funksjoner for cache-dir og thumbnail-generering.
  - Windows-oppskrift dokumentert for `rawcull_ffi.dll` load-path i Flutter.

## 1. Mål

Bygge en ny desktop-app med samme kjernefunksjonalitet som RawCull, men uten avhengighet til macOS-spesifikke rammeverk.

### Primære mål

1. Windows x64 som førsteclass target.
2. Cross-platform arkitektur (Windows først, deretter macOS/Linux).
3. Analysepipeline basert på OpenCV + ONNX Runtime.
4. Flutter som felles UI-lag.
5. Stabil, testbar, modulær kodebase med CI fra dag 1.

## 2. Endelig arkitekturvalg (inkludert oppdateringer)

### 2.1 Core engine

- **Valgt:** Rust (ADR-001)
- **Hvorfor:** minnesikkerhet, god concurrency-modell, robust FFI mot Flutter.

### 2.2 Inference providers på Windows

- **Valgt policy:** DirectML default, CPU fallback, CUDA opt-in (ADR-002).
- **Init-rekkefølge i auto mode:** `CUDA (hvis prefer_cuda=true) -> DirectML -> CPU`.

### 2.3 UI

- Flutter desktop for alle plattformer.
- State management: Riverpod (anbefalt).
- Kommunikasjon mot engine: FFI + asynkrone callbacks/streams for progress.

### 2.4 Imaging/ML

- OpenCV for preprocessing + skarphetsmål.
- ONNX Runtime for saliency, klassifisering og embeddings/similarity.

## 3. Faseplan

## Fase 0: Foranalyse og baseline (1-2 uker)

- Kartlegg funksjonell paritet (MVP og post-MVP).
- Definer golden dataset for ARW/NEF/JPEG testfiler.
- Etabler måleparametere:
  - score-samsvar
  - throughput
  - minneforbruk

**Leveranse:** spesifikasjon + baseline målinger.

## Fase 1: Monorepo-struktur og CI (1 uke)

Opprett prosjektstruktur:

- `apps/flutter_desktop/`
- `engine/rust/core/`
- `engine/rust/ffi/`
- `models/onnx/`
- `docs/adr/`

CI pipelines:

- lint + format
- unit tests
- smoke benchmark

**Leveranse:** grønn CI på tom skeleton + første test.

## Fase 2: Core domenemodell og filarbeidsflyt (2-3 uker)

Implementer i Rust:

- katalogscan
- metadata-index
- rating/tag-modell
- disk + memory cache API

FFI API v1:

- `scan_catalog(path)`
- `get_items()`
- `set_rating(item_id, rating)`

**Leveranse:** Flutter kan vise katalog + rating med ekte data.

## Fase 3: Thumbnail + preprocessing (2-4 uker)

- RAW/JPEG decode pipeline.
- thumbnail generation + caching.
- robust fallback-strategi ved decode-feil.

**Leveranse:** stabil grid med rask scrolling og cache-hit over tid.

## Fase 4: Sharpness og focus pipeline (3-5 uker)

- OpenCV Laplacian/gradient-basert score.
- parameterisert konfigurasjon (ISO/aperture-hints der mulig).
- validering mot golden dataset.

**Leveranse:** score per bilde + sortering/filter i UI.

## Fase 5: Saliency/klassifisering/similarity (3-5 uker)

- ONNX-modeller integrert i engine.
- provider policy iht. ADR-002.
- batchet inferens med progress callbacks.

**Leveranse:** saliency + similarity + subject labels.

## Fase 6: Copy/sync og eksport (2-3 uker)

- cross-platform copy engine.
- include/exclude/rating filters.
- robust resumable behavior + tydelig logging.

**Leveranse:** produksjonsklar eksport/workflow.

## Fase 7: Hardening + release (2-4 uker)

- full regressjon
- ytelsesoptimalisering
- release-pakking (MSIX/installer)

**Leveranse:** v1.0 RC.

## 4. Testing som del av arbeidsflyten (obligatorisk)

Følgende er obligatorisk i all agentdrevet utvikling:

1. Kjør relevante tester etter hver endring.
2. Ingen commit uten grønn teststatus (eller dokumentert miljøbegrensning).
3. Ved nye features: legg til/oppdater tester i samme endring.
4. Ved bugfix: legg til reproduksjonstest før/med fix.
5. Kjør benchmark på berørte hotspots før merge til main.

## 5. Definisjon av "Done"

En oppgave anses som ferdig når:

- kode er implementert
- tester er oppdatert og grønn
- dokumentasjon er oppdatert
- måledata (hvis relevant) er logget
- endringen er review-klar

## 6. Risiko og mitigasjon

### Risiko A: Modellkvalitet avviker fra dagens app

- Tiltak: golden-set + toleransevindu + A/B sammenligning.

### Risiko B: Ytelse for svak på CPU-only maskiner

- Tiltak: tile-baserte pipelines, caching, batchet inferens, profilering tidlig.

### Risiko C: For høy kompleksitet i provider-matrisen

- Tiltak: tydelig EP-policy (ADR-002), CPU fallback alltid tilgjengelig.

## 7. Operativ arbeidsflyt per oppgave

1. Lag plan for oppgaven.
2. Implementer minste fungerende endring.
3. Kjør tester.
4. Oppdater dokumentasjon.
5. Commit med forklarende melding.
6. Åpne PR med teststatus og eventuelle avvik.

## 8. Milepæler

- **M1:** Flutter + Rust skeleton med scan/rating.
- **M2:** Thumbnail pipeline + cache.
- **M3:** Sharpness scoring v1.
- **M4:** ONNX saliency/similarity.
- **M5:** Copy/export.
- **M6:** RC + release.
