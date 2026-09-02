# AGENTS.md

Guidance for AI agents working in this repository.

## Stack

- **Flutter desktop app** (Linux / macOS / Windows). Current Flutter 3.47.x, Dart SDK `^3.13.2`.
- **State management**: Riverpod (`flutter_riverpod`), providers + a shared `ProviderContainer`.
- **Audio playback**: `just_audio`; on macOS/Windows routed through `audio_service` for OS media controls; on Linux via `media_kit`.
- **Transcription**: `whisper_ggml` — fully local Whisper inference. Model handled by `whisper_ggml`'s download/cache.
- **Windowing**: `window_manager`.
- **File picker / drag-drop**: `file_picker`, `desktop_drop`.

## Layout

- `lib/services/` — single-responsibility services: `AudioPlayerService`, `TranscriptionService`, `SpeakerService`, `SettingsStore`, `FileOpenService`, `WindowService`.
- `lib/providers/` — Riverpod providers / notifiers. `appStateProvider` holds the pipeline state (`AppStage` idle→processing→ready→error) plus streaming phase/segment providers.
- `lib/audio/` — `SolutionsAudioHandler` (OS-media-controls bridge).
- `lib/models/`, `lib/views/`, `lib/components/`, `lib/theme/`, `lib/utils/`.
- `macos/Runner/AppDelegate.swift` — macOS open-file bridge; macOS builds must be validated on a real Mac (Cocoa/FlutterMacOS aren't available on Linux).
- `.github/workflows/build_release.yml` — build & release CI (Linux/macOS/Windows).

## Verification

- `flutter analyze` — no new issues.
- `flutter test` — the full suite must pass (currently 19 tests).
- `flutter build <platform> --release` — must succeed for touched platforms.
- Swift files under `macos/`: only `swiftc -parse` is possible on Linux; full compile requires macOS tooling.

## Commit conventions

- Conventional Commits, concise subject.
- Local commits only with `git -c commit.gpgsign=false` (gpg pinentry times out). Never force-push.

## Agent skills

### Issue tracker

Issues and specs live as GitHub Issues via the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Domain docs

Single-context layout: optional `CONTEXT.md` at the repo root and `docs/adr/` for decisions. See `docs/agents/domain.md`.