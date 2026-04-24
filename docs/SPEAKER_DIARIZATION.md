# Speaker Diarization — Implementation Spec

## What It Is

Speaker diarization answers "who spoke when." Applied to StudentMax, it labels each transcript segment with a speaker — e.g. `SPEAKER_00` (professor) and `SPEAKER_01` (student asking a question) — so the transcript reads like a screenplay rather than a wall of undifferentiated text.

---

## Recommended Approach: SpeakerKit (Argmax)

SpeakerKit is built by the same team as WhisperKit and is designed to merge directly with WhisperKit output. Since StudentMax already depends on WhisperKit, this is the lowest-friction path.

- **Model**: Pyannote v4 (community tier, no API key needed)
- **Size**: ~10 MB
- **Speed**: ~1 second for 4 minutes of audio on Apple Silicon
- **Platform**: macOS 13+ / iOS 16+ (app targets macOS 14, so fine)
- **License**: Free community tier; Pro tier (Sortformer, API key) available separately

---

## Package Dependency

SpeakerKit ships inside the same `argmaxinc/WhisperKit` Swift package — just add a new product:

```swift
// In project.yml, under MarkdownMax dependencies:
- package: WhisperKit
  product: SpeakerKit   // add alongside existing WhisperKit product
```

Or in `Package.swift`:
```swift
.product(name: "SpeakerKit", package: "WhisperKit")
```

---

## Core API

### Initialize

```swift
import SpeakerKit

let speakerKit = try await SpeakerKit()
```

Models are downloaded on first run (~10 MB) and cached locally.

### Diarize

```swift
let audioArray: [Float] = // same float array passed to WhisperKit
let diarization = try await speakerKit.diarize(audioArray: audioArray)
```

**Options** (`PyannoteDiarizationOptions`):

| Option | Type | Default | Notes |
|--------|------|---------|-------|
| `numberOfSpeakers` | `Int?` | `nil` | Pass `nil` for auto-detection. Pass `2` for typical lecture (prof + students). |
| `clusterDistanceThreshold` | `Double` | `0.6` | Lower = more speakers detected. Raise if false splits. |
| `useExclusiveReconciliation` | `Bool` | `true` | Ensures each moment assigned to exactly one speaker. |

### Merge with WhisperKit Transcript

```swift
let transcription: [TranscriptionResult] = // output from whisperKit.transcribe()
let speakerSegments = diarization.addSpeakerInfo(to: transcription)

for group in speakerSegments {
    for segment in group {
        print("\(segment.speaker): \(segment.text)")
        // e.g. "SPEAKER_00: Today we'll cover quantum entanglement."
    }
}
```

**Matching strategies** (pass as parameter to `addSpeakerInfo`):
- `.subsegment` *(default)* — splits WhisperKit segments at word gaps before assigning speakers. Better accuracy.
- `.segment` — assigns one speaker per entire segment. Faster, works well when segments are short.

---

## Integration Points in StudentMax

### 1. TranscriptionService

`TranscriptionService.swift` is where WhisperKit is called. After getting the `TranscriptionResult`, call `speakerKit.diarize()` on the same audio array, then merge.

```swift
// After transcription completes:
let diarization = try await speakerKit.diarize(audioArray: audioArray)
let labeled = diarization.addSpeakerInfo(to: [transcriptionResult])
// Map labeled segments back to Transcript model, adding speaker field
```

### 2. Transcript Model (`MarkdownMaxCore/Models/Transcript.swift`)

Add a `speaker` field:

```swift
struct Transcript: Identifiable, Codable {
    // existing fields...
    var speaker: String?   // "SPEAKER_00", "SPEAKER_01", nil if diarization not run
}
```

### 3. DatabaseManager

Add `speaker TEXT` column to the transcripts table (nullable, so existing rows are unaffected):

```sql
ALTER TABLE transcripts ADD COLUMN speaker TEXT;
```

### 4. TranscriptTextView / GlassBackground.swift

Render speaker labels inline. Each unique speaker gets a color:

```swift
let speakerColors: [String: NSColor] = [
    "SPEAKER_00": .systemGreen,
    "SPEAKER_01": .systemBlue,
    "SPEAKER_02": .systemOrange,
    // ...
]
```

Display as a colored chip before each speaker-change paragraph — not before every segment (group consecutive segments by same speaker before rendering).

### 5. Export (ExportService.swift)

Add speaker labels to Markdown export:

```markdown
**Professor** [0:00]
Today we'll cover quantum entanglement and Bell's theorem.

**Student** [2:14]
Can you explain what a Bell state is?
```

Allow user to rename `SPEAKER_00` → "Professor", `SPEAKER_01` → "Student" in the UI.

---

## Data Flow

```
AudioRecorder → [Float] audio buffer
        ↓
WhisperKit.transcribe()  →  [TranscriptionResult]
        ↓  (parallel or sequential)
SpeakerKit.diarize()     →  DiarizationResult
        ↓
diarization.addSpeakerInfo(to: transcription)
        ↓
[SpeakerSegment] with .speaker + .text + .startTime
        ↓
Map → [Transcript] (with speaker field)
        ↓
DatabaseManager.save()
        ↓
TranscriptTextView renders with speaker chips
```

---

## Sequencing: Parallel vs. Sequential

WhisperKit and SpeakerKit both take the same `[Float]` audio array. They can run **concurrently** with Swift's structured concurrency:

```swift
async let transcription = whisperKit.transcribe(audioArray: audioArray)
async let diarization = speakerKit.diarize(audioArray: audioArray)

let (t, d) = try await (transcription, diarization)
let labeled = d.addSpeakerInfo(to: t)
```

This adds near-zero wall-clock overhead since diarization (~1–2s) completes well before transcription (~25s for a typical lecture).

---

## Speaker Naming UX

Raw labels (`SPEAKER_00`) are not user-friendly. After diarization, show a one-time rename sheet:

- List each detected speaker with a short audio preview clip
- Let user type a name ("Professor Chen", "Me", "Class")
- Store name mapping in `UserDefaults` keyed by recording ID
- Apply names in transcript view and exports

---

## Alternative: FluidAudio (Open Source, No API Key)

If SpeakerKit's community tier has limitations, FluidAudio is a fully open-source fallback:

```swift
// Package dependency
.package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.12.4")

// Usage (Offline Pyannote pipeline — best accuracy for batch use)
import FluidAudio

let manager = OfflineDiarizerManager(config: OfflineDiarizerConfig())
try await manager.prepareModels()  // ~32 MB download, cached

let samples = try AudioConverter().resampleAudioFile(path: recordingPath)
let result = try await manager.process(audio: samples)

for segment in result.segments {
    print("\(segment.speakerId) \(segment.startTimeSeconds)s → \(segment.endTimeSeconds)s")
}
```

FluidAudio's output is a timeline of `(speakerId, start, end)` segments — you then align these with WhisperKit's word-level timestamps manually (no `addSpeakerInfo` equivalent). More work, but no dependency on Argmax's SDK versioning.

**FluidAudio pipeline comparison:**

| Pipeline | Latency | Max Speakers | Best For |
|----------|---------|--------------|----------|
| Offline Pyannote | ~2s/lecture | Unlimited | StudentMax (batch after recording) |
| LS-EEND | Real-time | 10 | Live diarization during recording |
| Sortformer | Low | 4 | Seminars / small groups |

---

## What to Build First

1. **Phase 1** — Post-recording diarization with SpeakerKit (batch, after stop)
   - Minimal UI change: speaker chips in transcript
   - No streaming complexity

2. **Phase 2** — Speaker naming sheet (rename SPEAKER_00 → real names)

3. **Phase 3** *(optional)* — Live diarization during recording using FluidAudio's LS-EEND streaming pipeline

---

## Known Limitations

- **Overlapping speech**: Pyannote assigns overlapping speech to one speaker. Simultaneous talk (crosstalk) loses accuracy.
- **Short segments**: Very short utterances (<1s) are often mis-assigned. Typical lecture Q&A is fine.
- **First run**: Model download required (~10 MB SpeakerKit or ~32 MB FluidAudio). Should happen silently in background when app first launches, or on first recording stop.
- **Accuracy**: DER (Diarization Error Rate) ~15–20% in real-world noisy classrooms. Better in quiet lecture halls with a good mic.

---

## Sources

- [SpeakerKit — Argmax Blog](https://www.argmaxinc.com/blog/speakerkit)
- [Argmax Docs: Speaker Diarization](https://app.argmaxinc.com/docs/examples/speaker-diarization)
- [argmaxinc/WhisperKit — GitHub](https://github.com/argmaxinc/WhisperKit)
- [FluidInference/FluidAudio — GitHub](https://github.com/FluidInference/FluidAudio)
- [Speaker Diarization with MLX — Ivan's Blog](https://blog.ivan.digital/speaker-diarization-and-voice-activity-detection-on-apple-silicon-native-swift-with-mlx-92ea0c9aca0f)
- [speech-swift — soniqo/GitHub](https://github.com/soniqo/speech-swift)
