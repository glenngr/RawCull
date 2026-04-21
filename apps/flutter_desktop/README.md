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
