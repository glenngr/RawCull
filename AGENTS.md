# AGENTS.md

Instruksjoner for agenter som jobber i dette repoet under omskriving til Windows/cross-platform.

## 1) Formål

Målet er å bygge en cross-platform versjon av RawCull med Flutter (UI), Rust (core), OpenCV og ONNX Runtime, i tråd med:

- `docs/rewrite/windows-cross-platform-rewrite-plan.md`
- `docs/adr/ADR-001-engine-stack-rust-vs-cpp.md`
- `docs/adr/ADR-002-onnx-runtime-execution-providers-windows.md`

## 2) Obligatoriske regler

1. **Følg ADR-er:** Alle arkitekturvalg skal følge ADR-001 og ADR-002. Avvik krever ny ADR.
2. **Små, verifiserbare endringer:** Del opp i små commits med tydelig hensikt.
3. **Test etter hver endring (KRAV):**
   - Etter hver kodeendring gjort av en agent skal relevante tester kjøres automatisk.
   - Ingen commit uten testkjøring.
   - Hvis test ikke kan kjøres pga miljøbegrensning, dokumenter eksplisitt hvorfor.
4. **Oppdater tester sammen med kode:** Nye features/bugfixes skal ha tilhørende tester.
5. **Oppdater dokumentasjon:** Endringer i arkitektur, API eller arbeidsflyt skal reflekteres i docs.
6. **Ikke introduser plattformlås:** Ny kode skal være cross-platform by design, med tydelig adapter-lag ved behov.
7. **Fallback-sikkerhet:** For ONNX på Windows skal provider-policy følge ADR-002 (DirectML default, CPU fallback, CUDA opt-in).

## 3) Kodekvalitet

- Prioriter lesbarhet og vedlikeholdbarhet.
- Bruk konsekvent navngiving og modulstruktur.
- Unngå skjulte sideeffekter i API-er.
- Logg feil med nok kontekst til feilsøking.

## 4) Testing policy

Minimum per endring:

1. Kjør relevante unit tests for berørte moduler.
2. Kjør minst én integrasjon/smoke test når arbeidsflyt berøres.
3. Ved ytelseskritisk kode: kjør benchmark før merge.

PR skal inneholde:

- hvilke tester som ble kjørt
- resultat (pass/fail)
- eventuell begrunnelse for hoppe over test

## 5) PR-krav

- Beskriv hva som er endret og hvorfor.
- Referer til relaterte ADR-er.
- Dokumenter testresultater.
- Beskriv risiko og rollback-plan ved større endringer.

## 6) Hvis du er i tvil

- Stopp opp og skriv et kort forslag i PR/issue.
- Be om avklaring før du implementerer større arkitekturendringer.
