# photo_vault

Local-first encrypted photo vault (Android-first).

## Overview

photo_vault is a Flutter application that stores photos encrypted locally using AES-GCM and platform-backed secure storage for keys. The project follows a clean architecture with distinct layers: domain, application (usecases/services), data (repositories/datasources), presentation (UI), crypto, and storage.

## Quickstart

Prerequisites: Flutter SDK >= 3.12

1. Install dependencies

   flutter pub get

2. Generate code (drift/build_runner) when needed

   flutter pub run build_runner build --delete-conflicting-outputs

3. Run the app

   flutter run

## Project layout (high level)

- lib/application — usecases and application services (vault_session, import manager, etc.)
- lib/domain — entities and repository interfaces
- lib/data — repository implementations, datasources (local and test helpers)
- lib/presentation — app widgets, screens, state (cubits)
- lib/crypto — crypto services and models
- lib/storage/local_db — drift schema and generated DB (generated files are gitignored)

## Development

- Analyze: flutter analyze
- Tests: flutter test
- Codegen: flutter pub run build_runner build --delete-conflicting-outputs

## Docs

See STORAGE_ARCHITECTURE.md and PERSISTENCE_FIX_SUMMARY.md for persistence design notes and rationale.

## Notes on generated files

Generated artifacts (for example, drift-generated *.g.dart) are ignored by default and should be produced in CI using build_runner. If you intentionally keep generated outputs committed, document that decision here.

## Contributing

Please open issues or PRs for any improvements. Add a CONTRIBUTING.md for contributor guidelines.
