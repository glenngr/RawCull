# RawCull Rust Engine (Rewrite)

Dette er M1-startpunktet for cross-platform engine under omskrivingen.

## Struktur

- `core/` – domenemodeller, rekursiv katalogscan, rating-oppdatering
- `ffi/` – C ABI for Flutter-integrasjon

## FFI (M1)

Eksponerte funksjoner:

- `rawcull_ffi_api_version()`
- `rawcull_engine_new()` / `rawcull_engine_free()`
- `rawcull_engine_scan_catalog(engine, path)`
- `rawcull_engine_item_count(engine)`
- `rawcull_engine_get_item_path(engine, index)`
- `rawcull_engine_get_item_rating(engine, index)`
- `rawcull_engine_set_item_rating(engine, index, rating)`
- `rawcull_string_free(ptr)`

## Kommandoer

```bash
cargo fmt --all
cargo clippy --workspace --all-targets -- -D warnings
cargo test --workspace
cargo check --workspace
```
