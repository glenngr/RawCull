# ADR-001: Valg av core-engine stack for RawCull rewrite (Rust vs C++)

- **Status:** Accepted
- **Dato:** 2026-04-21
- **Beslutningstakere:** RawCull team
- **Scope:** Ny cross-platform engine (Windows først, deretter macOS/Linux), brukt av Flutter desktop UI.

## Context

Eksisterende app er tett koblet til Apple-spesifikke teknologier (`AppKit`, `Vision`, `CoreImage`/Metal) og arm64-bygg i Xcode, som hindrer direkte portering til Windows/x64 uten omskriving.

Målet er å bygge en ny plattformuavhengig engine med:

- ONNX Runtime (saliency/similarity/classification)
- OpenCV (bildetransformasjoner, skarphetsmåling)
- Flutter som UI-lag (desktop)

## Decision

Vi velger **Rust** som primær språkstack for ny core-engine.

### Hvorfor Rust

1. **Minne- og trådsikkerhet som default**
   - Kritisk for bildepipeline og batch-prosessering under høy last.
2. **God FFI mot Flutter**
   - Stabil C ABI-eksport fra Rust er rett fram.
3. **Sikker concurrency**
   - Færre race-condition-klasser enn typisk C++ uten streng disiplin.
4. **Drift/vedlikehold**
   - Mindre risiko for subtile memory bugs i langtidsperspektiv.

## Alternatives considered

### A) C++ (forkastet som primærvalg)

**Fordeler**
- Størst modenhet i CV/ML-økosystem.
- Enkel tilgang til OpenCV/ONNX C++ API.

**Ulemper**
- Høyere risiko for memory/thread-bugs.
- Tyngre kode-review krav for sikkerhet og robusthet.
- Mer kompleksitet i langsiktig vedlikehold.

### B) Hybrid: Rust orkestrering + C++ performance-kjerne

**Vurdering**
- Aktuelt for hotspots hvis profiling viser at Rust + bindings ikke holder mål.
- Ikke default fra dag 1; introduseres kun ved dokumentert behov.

## Consequences

### Positive

- Høy robusthet og stabilitet på Windows/x64.
- Tydelig separasjon mellom UI (Flutter) og engine (Rust).
- Enklere å lage testbar, deterministisk analysepipeline.

### Negative

- Teamet må ha Rust-kompetanse (læringskurve).
- Noe integration overhead mot OpenCV/ONNX i starten.
- Potensielt behov for C++-shim i enkelte biblioteker.

## Architecture implications

- `engine-core` (Rust): filscan, metadata, thumbnail-pipeline, scoring, similarity, caching.
- `engine-ffi` (Rust, C ABI): funksjoner eksponert til Flutter.
- `app-flutter` (Dart): all presentasjon, state og workflows.
- `model-zoo` (ONNX): versjonerte modeller + valideringsdata.

## Non-goals

- Ingen direkte port av AppKit/SwiftUI-kode.
- Ingen avhengighet til `Vision` eller Metal i ny engine.
- Ingen hardkobling til `/usr/bin/rsync` i cross-platform kopi-flyt.

## Migration plan (high-level)

1. Definer stabile engine-API-er (scan, thumbnail, score, similarity, copy).
2. Bygg Rust skeleton + FFI kontrakt.
3. Implementer OpenCV + ONNX pipeline.
4. Koble Flutter desktop UI.
5. Kjør golden tests mot eksisterende output.
6. Profilering og evt. C++-hotspot-optimalisering.

## Acceptance criteria

- Windows x64 release med funksjonell paritet for MVP.
- Deterministiske score-resultater innen avtalt toleranse.
- Ingen kritiske memory/thread defects i stresstester.
- Batch throughput møter definert minimumskrav.

## Revisit triggers

Beslutningen revurderes hvis:

- Rust-FFI gir uakseptabel ytelse i kritiske hotspots, eller
- ONNX/OpenCV integrasjon blir vesentlig mer kompleks enn estimert.
