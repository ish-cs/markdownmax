# MarkdownMax — Usage Guide

## Requirements

- macOS 14.0 (Sonoma) or later
- Apple Silicon Mac (M1/M2/M3) — required for Metal-accelerated transcription
- Xcode 15 or later (to build from source)
- Internet connection on first launch (to download a Whisper model)

---

## Build & Run

### 1. Open in Xcode

```bash
open MarkdownMax.xcodeproj
```

Select the **MarkdownMax** scheme and press **⌘R** to build and run.

### 2. Build from the terminal

```bash
xcodebuild \
  -project MarkdownMax.xcodeproj \
  -scheme MarkdownMax \
  -destination 'platform=macOS' \
  -clonedSourcePackagesDirPath .build/packages \
  build
```

The built app lands at:

```
~/Library/Developer/Xcode/DerivedData/MarkdownMax-*/Build/Products/Debug/MarkdownMax.app
```

You can open it directly:

```bash
open ~/Library/Developer/Xcode/DerivedData/MarkdownMax-*/Build/Products/Debug/MarkdownMax.app
```

### 3. Run tests

```bash
xcodebuild \
  -project MarkdownMax.xcodeproj \
  -scheme MarkdownMaxTests \
  -destination 'platform=macOS' \
  -clonedSourcePackagesDirPath .build/packages \
  test
```

---

## First Launch

1. The app runs as a **menu bar app** — look for the waveform icon (⌁) in your menu bar.
2. On first launch, an **onboarding sheet** appears asking you to download a Whisper model.
3. Choose a model based on your needs:

   | Model  | Size    | Accuracy | Speed (10 min audio) |
   |--------|---------|----------|----------------------|
   | Tiny   | 39 MB   | 4–5% WER | ~8 seconds           |
   | Small  | 244 MB  | 3–4% WER | ~45 seconds          |
   | Medium | 1.5 GB  | 2–3% WER | 2–3 minutes ★        |
   | Large  | 3 GB    | ~1% WER  | 5–7 minutes          |

   **Medium is recommended** for most users. Tiny is good for quick tests.

4. The model downloads from Hugging Face. A progress bar is shown.
5. Once downloaded, you're ready to record.

---

## Recording

| Action | How |
|--------|-----|
| Start recording | Click the mic button in the menu bar popover, or press **⌘R** from any app |
| Stop recording | Click the stop button, or press **⌘R** again |
| View last transcript | Press **⌘⇧T** from any app |

Transcription starts automatically after you stop recording. A spinner appears on the recording row while it processes.

---

## Transcripts

- Click the **doc icon** on any completed recording to open its transcript.
- Transcripts show each segment with a `[start → end]` timestamp.
- Text is selectable — click and drag to copy any segment.
- The **Copy All** button copies the full transcript to your clipboard.

### Export

From the transcript window, click **Export** to save as:

- **Markdown** (`.md`) — timestamps + formatted header, great for Obsidian / Notion
- **Plain Text** (`.txt`) — clean timestamped lines
- **PDF** — print-ready document

---

## Search

The search bar in the menu bar popover searches **all transcript text** using full-text search (FTS5). Results appear in real time and link back to the source recording.

---

## Settings (`⌘,`)

### Models tab
- **Download** additional models
- **Switch** active model (affects future transcriptions)
- **Delete** models to free disk space

### Shortcuts tab
- Rebind **Toggle Recording** (default: `⌘R`)
- Rebind **Open Last Transcript** (default: `⌘⇧T`)

### Storage tab
- See total disk usage for models
- Clear all models at once

---

## Data Location

All data is stored locally — nothing leaves your Mac.

```
~/Library/Application Support/MarkdownMax/
├── database.sqlite       recordings + transcripts + model index
├── models/
│   ├── tiny/             Whisper Tiny model files
│   ├── small/
│   ├── medium/           (default)
│   └── large/
└── recordings/           WAV audio files
```

To fully uninstall, delete the app and this directory.

---

## Regenerating the Xcode project

If you modify `project.yml` (e.g. to add a dependency or change build settings):

```bash
xcodegen generate
```

Requires [xcodegen](https://github.com/yonaskolb/XcodeGen):

```bash
brew install xcodegen
```
