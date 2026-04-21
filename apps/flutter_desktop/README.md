# Flutter Desktop App (Rewrite)

Dette er M1-skjelettet for cross-platform UI laget i Flutter.

## Innhold

- `lib/main.dart` – enkel katalogliste med rating-kontroller (placeholder).
- `test/app_test.dart` – grunnleggende test-hook for CI.
- `pubspec.yaml` – Flutter package-definisjon.

## Kjøring (lokalt)

```bash
flutter pub get
flutter run -d windows
```

## M1-notat

UI-en viser foreløpig eksempeldata. Neste steg er å hente ekte data via FFI fra `engine/rust/ffi` (`scan_catalog`, `get_items`, `set_rating`).

## Windows-oppskrift: koble `rawcull_ffi.dll` med `dart:ffi`

### 1) Bygg DLL

Fra repo root:

```bash
cd engine/rust
cargo build -p rawcull_ffi --release
```

DLL blir generert i:

`engine/rust/target/release/rawcull_ffi.dll`

### 2) Kopier DLL til Flutter runner-mappe

For lokal debug på Windows, kopier DLL til samme mappe som `.exe` lastes fra, typisk:

`apps/flutter_desktop/windows/runner/Debug/rawcull_ffi.dll`

Ved release-byggeprofil:

`apps/flutter_desktop/windows/runner/Release/rawcull_ffi.dll`

### 3) Load-path i Flutter (`dart:ffi`)

`lib/ffi/rawcull_bindings.dart` forsøker i denne rekkefølgen:

1. `RAWCULL_FFI_LIB` miljøvariabel (full path)
2. `rawcull_ffi.dll` (Windows default ved siden av exe)
3. `librawcull_ffi.dylib` (macOS)
4. `librawcull_ffi.so` (Linux)

### 4) Valgfri override med miljøvariabel

PowerShell eksempel:

```powershell
$env:RAWCULL_FFI_LIB="C:\full\path\to\rawcull_ffi.dll"
flutter run -d windows
```
