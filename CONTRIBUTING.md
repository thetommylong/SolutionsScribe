# Contributing

Thanks for your interest in SolutionsScribe.

## Project conventions

- **Commits**: Conventional Commits, concise subject (`feat:`, `fix:`, `refactor:`, `docs:`, `ci:`).
- **Verify before submitting**: `flutter analyze` (no new issues), `flutter test` (all pass), and a debug build for your platform.
- **Design notes**: the project favors small, focused services (see `lib/services/`) with a single responsibility.

## Building locally

Requires the project Flutter SDK (pinned in `.github/workflows/build_release.yml`).

```bash
flutter pub get
flutter test
flutter build <linux|macos|windows> --release
```

Platform-specific build dependencies:
- **Linux**: `clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev libstdc++-12-dev`

## Opening a PR

1. Open an issue first describing the change (or scope the PR to an existing issue).
2. Branch from `main`, make focused commits.
3. Ensure the full test + analyze passes.
4. Open the PR against `main`.

## Issue tracker

Issues and specs live as GitHub Issues. See [docs/agents/issue-tracker.md](docs/agents/issue-tracker.md) for the conventions the CLI-driven skills use.