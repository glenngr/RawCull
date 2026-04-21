# ADR-002: ONNX Runtime Execution Providers på Windows (CPU vs DirectML vs CUDA)

- **Status:** Accepted
- **Dato:** 2026-04-21
- **Scope:** Windows desktop runtime for ny RawCull engine (Rust + ONNX Runtime + OpenCV + Flutter).

## Context

Ny løsning skal kjøre stabilt på vanlige Windows-maskiner (inkl. laptop uten dedikert GPU), men også kunne skalere opp ytelse på maskiner med kompatibel GPU.

## Decision

Vi velger følgende **prioritetsrekkefølge på Windows**:

1. **DirectML EP** (default når tilgjengelig)
2. **CPU EP** (alltid fallback)
3. **CUDA EP** (opt-in “power user”-modus, ikke default)

## Rasjonale

### 1) DirectML som primær/default

- Best balanse mellom ytelse og distribusjon på Windows.
- Fungerer på bredere spekter av GPU-er (ikke bare NVIDIA).
- Lavere brukerfriksjon enn CUDA-first.

### 2) CPU som obligatorisk fallback

- Garantert baseline på alle støttede maskiner.
- Kritisk for robusthet, CI, testmiljø og support.
- Gir deterministisk fail-safe hvis GPU-init feiler.

### 3) CUDA som opt-in

- Kan gi best throughput på NVIDIA i noen modeller/workloads.
- Høyere kompleksitet (driver/toolkit/kompatibilitet), derfor ikke default.
- Aktiveres via eksplisitt setting/flagg.

## Provider policy (konkret)

Ved oppstart:

- Hvis `prefer_cuda=true` og CUDA init OK -> bruk CUDA.
- Ellers prøv DirectML.
- Hvis DirectML ikke er tilgjengelig/feiler -> CPU.

Alle init-feil logges med tydelig "reason + fallback valgt".

## Konfigurasjon (foreslått)

`engine_config.json`:

```json
{
  "provider_mode": "auto",
  "prefer_cuda": false,
  "allow_cpu_fallback": true,
  "gpu_timeout_ms": 1500
}
```

## Konsekvenser

### Positive

- Høy kompatibilitet out-of-the-box på Windows.
- God ytelse for majoriteten av brukere med GPU.
- Forutsigbar drift med sikker CPU fallback.

### Negative

- Tre EP-paths krever mer testing.
- Små numeriske avvik mellom EP-er må håndteres i toleranser.
- CUDA-støtte øker support-matrise.

## Test- og kvalitetskrav

1. Smoke-test per EP: model load + 10 bilder inferens.
2. Golden comparison:
   - Samme input på CPU vs DirectML/CUDA.
   - Resultatavvik innen definert toleranse.
3. Fallback-test:
   - Simulert GPU-feil skal automatisk ende i CPU uten crash.
4. Perf-test:
   - Rapporter bilder/sek og latens p50/p95 per EP.

## Rollout

- **v1:** Auto = DirectML -> CPU, CUDA skjult bak feature flag.
- **v1.1:** CUDA eksponeres i avanserte innstillinger.
- **v1.2:** Telemetri-basert tuning av default policy.

## Revisit triggers

Revurder beslutningen hvis:

- DirectML gir signifikant dårligere kvalitet/ytelse på hovedmodeller.
- CUDA-adopsjon i brukerbasen blir høy nok til at CUDA bør bli default på NVIDIA.
- ONNX Runtime endrer EP-stabilitet/feature-set vesentlig.
