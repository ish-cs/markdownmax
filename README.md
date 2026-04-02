# MarkdownMax

A macOS menu bar app for local, on-device audio transcription using Whisper + MLX. No cloud uploads. No subscriptions. Everything stays on your Mac.

## Features

- **100% local** — recordings and transcripts never leave your device
- **Whisper-powered** — 2–3% WER with the Medium model on Apple Silicon
- **Menu bar app** — one-click recording from anywhere, global keyboard shortcuts
- **Full-text search** — search across all transcripts instantly
- **Export** — Markdown, plain text, or PDF

## Requirements

- macOS 14.0 (Sonoma) or later
- Apple Silicon (M1/M2/M3)
- Xcode 15+ (to build from source)
- Internet connection on first launch (to download a Whisper model)

## Build & Run

```bash
open MarkdownMax.xcodeproj
```

Select the **MarkdownMax** scheme and press **⌘R**.

Or from the terminal:

```bash
xcodebuild \
  -project MarkdownMax.xcodeproj \
  -scheme MarkdownMax \
  -destination 'platform=macOS' \
  -clonedSourcePackagesDirPath .build/packages \
  build
```

## First Launch

1. Look for the waveform icon (⌁) in your menu bar.
2. Download a Whisper model from the onboarding sheet.

| Model  | Size   | Accuracy | Speed (10 min audio) |
|--------|--------|----------|----------------------|
| Tiny   | 39 MB  | ~5% WER  | ~8 seconds           |
| Small  | 244 MB | ~3% WER  | ~45 seconds          |
| Medium | 1.5 GB | ~2% WER  | 2–3 minutes ★        |
| Large  | 3 GB   | ~1% WER  | 5–7 minutes          |

**Medium recommended** for most users.

## Usage

| Action | Shortcut |
|--------|----------|
| Start / stop recording | ⌘R |
| Open last transcript | ⌘⇧T |

Transcription starts automatically after recording stops. Transcripts are searchable, selectable, and exportable as Markdown, plain text, or PDF.

## Data

All data is stored locally at `~/Library/Application Support/MarkdownMax/`. To uninstall, delete the app and that directory.

## License

MIT
