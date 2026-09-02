# SolutionsScribe ✍️

Local, on-device audio transcription with speaker diarization. Turn any recording into a readable, per-speaker transcript without sending a byte to the cloud.

> [!WARNING]
> **Vibe-coded software ahead.** Proceed at your own risk!

## The Problem

Meeting recordings, interviews, and voice memos pile up, but they're only useful if you can *read* them. Cloud transcribers cost money, ship your audio off-device, and rarely tell you who said what.

## The Solution

SolutionsScribe runs **Whisper locally** on your machine, transcribes your audio in one pass, and groups sentences by speaker. No account, no upload, no recurring fee — your audio never leaves your device.

## Features

- 🤫 **Fully local transcription** — Whisper via `whisper_ggml`, no cloud involved
- 🗣️ **Speaker diarization** — automatically clusters segments by who's talking
- ⏳ **Whole-file transcription with live progress** — transcribes the full file in one pass (audio doesn't need to be playing); a banner shows the phase and percentage, and the transcript appears once it's done
- ▶️ **Built-in playback** — seek, volume, and transport controls right in the app
- 🎛️ **OS media controls** — play/pause/seek from your keyboard or notification shade (macOS & Windows; Linux stays in-app)
- 🪟 **Desktop-native windowing** — minimum/maximum size, collapse-to-fit when the transcript is hidden (Linux, macOS, Windows)
- 📂 **Open-with integration** — drag an audio file onto the app or open it from your OS (macOS file associations; launch-arg on Linux/Windows)
- 🎚️ **Model picker** — choose the Whisper model that matches your hardware and privacy needs

## Installation

Grab the latest build for your platform from [Releases](https://github.com/thetommylong/SolutionsScribe/releases).

| Platform | Package |
|----------|---------|
| Linux (x64) | tar.gz bundle |
| macOS | `.app` |
| Windows (x64) | zip of the runner |

## Usage

1. **Launch SolutionsScribe**
2. **Drop an audio file** onto the window, or open it via *Open With* / drag-onto-icon
3. **Pick a model** (first run downloads it; larger models are more accurate, smaller are faster)
4. **Wait for transcription** — the full file is transcribed in one pass; a progress banner shows the current phase and percentage
5. **Read your transcript** — sentences grouped by detected speaker, revealed once transcription finishes

### Opening a file

| Way | How |
|-----|-----|
| Drag & drop | Drop any `.mp3`/`.wav`/`.m4a` onto the window |
| File picker | Browse from the upload screen |
| Open With (macOS) | Right-click a file → Open With → SolutionsScribe |
| Launch argument | `solutionscribe path/to/audio.mp3` |

## Model notes

- Models download on first use and are cached locally.
- Bigger isn't always better — the default `base` model is a good speed/accuracy balance for most machines.
- Transcription is isolated to your device; nothing is uploaded.

## Known Limitations

- Transcription is a single whole-file pass: the transcript appears all at once when it finishes, not progressively while the file plays. (Streaming/progressive output is a possible future direction.)
- Linux uses in-app media controls rather than system MPRIS (planned).
- Whisper accuracy varies with audio quality and accent; diarization is best-effort clustering, not speaker ID.
- First-run model download requires an internet connection; after that it's fully offline.

---

## Seriously, That's It

It's a focused tool, not a framework. Drop a recording in, get a speaker-labeled transcript out. If you need cloud collaboration, live meeting captions, or timestamp-perfect SRT exports, there are heavier tools for that.

## License

GPL-3.0. Read [LICENSE](LICENSE).

## Contributing

Issues and PRs are welcome — see [CONTRIBUTING](CONTRIBUTING.md) and the [issue tracker](docs/agents/issue-tracker.md).
