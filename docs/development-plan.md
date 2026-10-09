# MediaSpy — Development Plan

A native, modern macOS media-file inspector. A stylish Swift/SwiftUI replacement for
[MediaInfo](https://mediaarea.net/en/MediaInfo) that shows container, video, audio,
subtitle, and chapter details for any media file — with the same accuracy MediaInfo is
trusted for, but a native Apple-platform look and feel.

Status: **Planning.** Engine and integration approach decided; UI design pending (external).
Last updated: 2026-07-06.

---

## 1. Goals & non-goals

### Goals
- Match MediaInfo's **accuracy and format coverage** (MKV, MP4/MOV, AVI, TS, WebM, FLAC,
  etc.) — this is the whole reason people use MediaInfo.
- A **native, stylish SwiftUI app** that feels like a first-class Mac citizen (materials,
  SF Symbols, light/dark, keyboard-driven, resizable dense layouts).
- Preserve the workflow the user relies on: **right-click a file in Finder → see its media
  info** (see §7 for how this actually works on modern macOS).
- Fast: inspection is metadata parsing, not decoding — results should feel instant.
- Drag-and-drop, multi-file, and "Open With" support.

### Non-goals (at least for v1)
- Not a transcoder, player, or editor. Read-only inspection.
- Not cross-platform. macOS-native is the point. (A shared parsing core could later back an
  iOS/iPadOS build, but that's out of scope now.)
- Not re-implementing container/codec parsers from scratch — we stand on libmediainfo.

---

## 2. How MediaInfo works (research findings)

**MediaInfo does not use ffmpeg.** It is built on its own engine:

- **libmediainfo (MediaInfoLib)** — a C++ library that is the actual analysis engine. The
  desktop app is a thin GUI over it.
- **libzen (ZenLib)** — a small utility dependency by the same author (MediaArea /
  Jérôme Martinez).

Key architectural fact: **MediaInfo is a metadata parser, not a decoder.** It never decodes a
frame. It:
1. Parses the **container** structure directly (MP4/MOV atoms, Matroska/EBML elements, AVI
   RIFF chunks, MPEG-TS packets, etc.).
2. Reads **codec bitstream headers** (H.264 SPS/PPS, HEVC, AV1, AAC, AC-3, …) for profile,
   level, bit depth, chroma, frame rate, etc.
3. Maps raw identifiers to friendly names via an internal database ("AVC" → "H.264/MPEG-4
   AVC").

This is why it is fast and why it surfaces details general-purpose tools gloss over.

**Licensing — the decisive point:** libmediainfo is **BSD-2-Clause** and libzen is **zlib**. We can
legally wrap them inside a proprietary, closed-source, or paid app, including on the Mac App
Store. This is what makes reusing the real engine the obvious choice.

### Why not the alternatives
| Engine | Verdict |
| --- | --- |
| **libmediainfo** | ✅ Chosen. Same accuracy as MediaInfo, BSD-2, App-Store-safe. |
| ffmpeg / libav | Rich data but LGPL/GPL friction; GPL is App-Store-incompatible; heavier bridge. |
| Pure AVFoundation | Zero deps but no MKV, thin codec/subtitle detail — fails the core use case. |

---

## 3. Proof of concept (already validated on this machine)

- Installed `libmediainfo 26.05` (+ `libzen 0.4.41`) via Homebrew:
  - dylib: `/opt/homebrew/lib/libmediainfo.dylib`
  - headers: `/opt/homebrew/include/MediaInfoDLL/MediaInfoDLL_Static.h` (C interface)
- Wrote and ran a small C program against the C interface
  (`MediaInfoA_New` → `_Option("Output","JSON")` → `_Open(path)` → `_Inform`) and got clean,
  rich JSON for a real `.mp4`: `Format`, `OverallBitRate`, `FrameRate`, per-track video/audio
  formats, `CodecID`, human-readable `*_String` variants, etc.
- Toolchain present: **Xcode 26.6 / Swift 6.3.3**, target `arm64-apple-macosx26`.

Conclusion: the full pipeline (libmediainfo → C interface → JSON → Swift) works locally today.
Doability is confirmed; remaining work is engineering and polish.

---

## 4. Architecture

```
┌─────────────────────────────────────────────────────────┐
│  MediaSpy.app  (SwiftUI)                                 │
│  ┌───────────────────────────────────────────────────┐  │
│  │  UI layer  (SwiftUI views — DESIGN PENDING)        │  │
│  └───────────────────────────────────────────────────┘  │
│  ┌───────────────────────────────────────────────────┐  │
│  │  MediaSpyKit  (Swift framework — shared core)      │  │
│  │   • MediaInfoReader  (async wrapper)               │  │
│  │   • MediaReport / MediaTrack models                │  │
│  │   • Curated field mapping + formatting             │  │
│  └───────────────────────────────────────────────────┘  │
│  ┌───────────────────────────────────────────────────┐  │
│  │  CMediaInfo  (C bridge / module map → dylib)       │  │
│  └───────────────────────────────────────────────────┘  │
└──────────────────────────┬──────────────────────────────┘
                           │ links
              libmediainfo.xcframework + libzen  (BSD-2)
                           │
        ┌──────────────────┴───────────────────┐
   Finder integration (Service / Quick Action / QL — see §7)
```

Design principle: **all parsing lives in `MediaSpyKit`**, a dependency-light Swift framework.
The app UI, the Finder-facing extensions, and any future CLI or iOS build all reuse the same
core. Extensions must not duplicate parsing logic.

---

## 5. Tech stack & project layout

- **Language:** Swift 6 (language mode v5 initially to sidestep strict-concurrency churn;
  tighten later).
- **UI:** SwiftUI, macOS 14+ target (revisit; 13+ possible if needed).
- **Build:** Xcode project (required — app extensions need Xcode targets). An SPM package may
  back `MediaSpyKit` for fast unit-test iteration.
- **Engine:** libmediainfo + libzen, packaged as an **xcframework** (see §8).

Proposed repo structure:
```
media-spy/
├── docs/
│   └── development-plan.md          ← this file
│   └── design/                      ← (incoming) UI design from Claude Design
├── MediaSpy.xcodeproj
├── MediaSpy/                        app target (SwiftUI)
├── MediaSpyKit/                     shared framework (bridge + models)
│   ├── CMediaInfo/                  module.modulemap + shim header
│   ├── MediaInfoReader.swift
│   └── Model/  (MediaReport, MediaTrack, curated fields)
├── MediaSpyService/                 Finder right-click integration (see §7)
├── MediaSpyQuickLook/               (optional) Quick Look preview extension
├── Vendor/
│   └── libmediainfo.xcframework     bundled engine (BSD-2)
└── MediaSpyKitTests/
```

---

## 6. Data model

libmediainfo emits JSON as `media.track[]`, where each track has an `@type`
(`General`, `Video`, `Audio`, `Text`, `Menu`) and a flat bag of string fields, including
pre-formatted human-readable `*_String` variants (e.g. `Duration_String3` = `00:01:55.971`,
`OverallBitRate_String` = `1 465 kb/s`).

Model:
- `MediaReport` — `ref` (file path), `[MediaTrack]`, raw JSON string retained for a
  "raw / all fields" view.
- `MediaTrack` — `type`, plus a flattened `[String: String]` of all fields (nested `extra`
  flattened with a key prefix). Convenience lookups with fallback key lists.
- **Curated presentation:** because `JSONSerialization` does not preserve key order, we define
  a curated, ordered set of rows per track type (Format, bit rate, resolution, frame rate,
  channels, sampling rate, language, title, default/forced, …), preferring the pretty
  `*_String` variants for display. A "show all fields" disclosure exposes the complete set.

This keeps the common view clean and MediaInfo-familiar while still exposing everything.

---

## 7. Finder right-click integration (the workflow that matters)

The old MediaInfo Windows shell extension has no exact macOS equivalent. On modern macOS the
sanctioned routes for "right-click a file → media info" are:

1. **macOS Service (NSServices).** The app registers a service ("Get Media Info") that accepts
   file URLs. Appears under right-click → *Services*, and (if promoted) at the top level.
   Simple, robust, no monitored-folder constraints. **Recommended primary.**
2. **Quick Action (Automator/Shortcuts).** A workflow that appears in the right-click menu and
   the Finder preview pane; can call the app or a bundled CLI. Easy to ship, user-visible.
3. **Finder Sync extension (`FIFinderSync`).** Can inject contextual menu items, but is
   designed around monitored directories — awkward for "any file anywhere." Not preferred.
4. **Quick Look preview extension.** Press space on a media file → a MediaSpy-rendered info
   panel. Great complementary feature; not a context-menu item itself.

Plan: ship **(1) Service** as the core right-click path, evaluate **(2) Quick Action** for
discoverability, and treat **(4) Quick Look** as a high-value stretch. All of these call into
`MediaSpyKit` — no parsing logic is duplicated.

Sandbox/entitlement note: right-click extensions receive a security-scoped URL to the selected
file; the app needs the user-selected-files read entitlement. Straightforward but must be
wired correctly for App Store distribution.

---

## 8. Packaging & distribution

- **Engine packaging:** build/repackage libmediainfo + libzen as a **universal
  (arm64 + x86_64) `libmediainfo.xcframework`** bundled in `Vendor/`, so the app has no
  Homebrew runtime dependency. (Homebrew is fine for dev; not for shipping.) Fix up install
  names / rpaths so the dylibs load from within the app bundle.
- **Signing & notarization:** code-sign the app and the bundled dylibs; notarize for
  distribution outside the App Store.
- **App Store vs. Developer ID:** libmediainfo's BSD-2 license permits both. Decide
  distribution channel later; App Store adds sandbox + entitlement requirements (manageable).
- **Licensing compliance:** ✅ notices for libmediainfo (BSD-2), libzen (zlib) and the third-party
  code compiled into libmediainfo (Gladman AES/SHA/HMAC, tfsxml, TinyXML-2, fmt, MD5) ship in
  `Support/Credits.html` (in the repo, and shown in the standard About panel).

---

## 9. Milestones

- **M0 — Foundations** ✅ confirm engine, license, toolchain; prove the JSON pipeline.
- **M1 — Core in Swift** ✅ `CMediaInfo` bridge + `MediaSpyKit` (`MediaInspector`, models,
  `Curated` presentation). `mediaspy` CLI verifier. 10/10 tests; verified on real
  MKV/MP4/MOV/WAV. Serialised engine queue (libmediainfo's C string buffers are not
  thread-safe — concurrent inspections corrupt each other).
- **M2 — App shell** ✅ SwiftUI Ember app: sidebar/multi-file, adaptive thumbnails
  (landscape + portrait, no playback), audio waveform + dB meters (AVFoundation),
  drag-and-drop, Open With.
- **M3 — Finder integration** ✅ macOS **Service** "Get Media Info" (NSServices in app
  Info.plist + `MediaInfoServiceProvider` on `NSApp.servicesProvider`). Registered &
  verified via `pbs`. Lands in Finder ▸ right-click ▸ Services (no supported top-level
  placement without a FIFinderSync extension — deferred).
- **M4 — Packaging** ✅ **XcodeGen** project (`project.yml`) → signed `MediaSpy.app` that
  **bundles** libmediainfo + libzen (arm64) in `Contents/Frameworks`, relocated to
  `@rpath`/`@loader_path`, ad-hoc signed. Runs with **no Homebrew dependency** (verified via
  `lsof`). Universal (+x86_64) + Developer-ID/notarize deferred (see §8).
- **M5 — Polish & stretch:**
  - **Export** ✅ Text/JSON/XML/HTML (libmediainfo output modes) — CLI + app menu.
  - **All-fields view** ✅ searchable raw field list (`⌘L` / toolbar toggle).
  - **Quick Look preview** ✅ `MediaSpyQL.appex` — view-based `QLPreviewingController`
    hosting a native SwiftUI Ember report. Verified rendering an MKV via `qlmanage`.
  - Batch/compare view, app icon, universal build — future.

### Gotchas discovered (so they aren't rediscovered)
- **SwiftUI window won't appear when launched with file *arguments*** — positional argv makes
  SwiftUI wait for scene routing and create no window. Files must arrive via `onOpenURL`
  (Finder/Service/Open With) or, in dev, the `MEDIASPY_OPEN` env var.
- **Framework needs an Info.plist** (`GENERATE_INFOPLIST_FILE: YES`) or codesign fails with
  "bundle format unrecognized".
- **install_name_tool invalidates signatures** — re-sign dylibs *and* the framework *and* the
  appex after relocation (inner→outer), before Xcode's final app signing. Otherwise the app
  is SIGKILL'd for "Code Signature Invalid".
- **appex rpath must be `@loader_path/../../../../Frameworks`**, never `@executable_path` — a
  QL extension is hosted by a system process.
- **Data-based `QLPreviewProvider` is not available on macOS** (iOS-only) — use view-based
  `QLPreviewingController`. **WKWebView doesn't paint inside a sandboxed QL extension** — host
  SwiftUI via `NSHostingController` instead.
- **Quick Look reality:** macOS's built-in AV preview shadows custom previews for
  `.mp4/.mov/.wav` — MediaSpy's QL preview reliably appears for **.mkv** and other containers
  with no native preview. This is a platform limitation, not a bug.

## 13. Build & run

```sh
# CLI + tests (fast iteration, links Homebrew libmediainfo)
swift build && swift test
.build/debug/mediaspy --preview <file>   # Ember HTML (the Quick Look content)

# The engine, built from MediaArea source for the app's deployment target
# (Homebrew bottles require the build machine's macOS — never bundle those).
# Versions + checksums live at the top of the script; re-run after bumping them.
./scripts/build-engine.sh                  # → Vendor/engine/{include,lib} (git-ignored)

# The app + extensions (bundles Vendor/engine, self-contained, ad-hoc signed)
xcodegen generate
xcodebuild -project MediaSpy.xcodeproj -scheme MediaSpy -configuration Release \
           -derivedDataPath build build
# → build/Build/Products/Release/MediaSpy.app  (arm64, minos 14.0)
# (If Xcode's custom compilation-cache location is broken, append
#  COMPILATION_CACHE_CAS_PATH="$PWD/build/CompilationCache.noindex".)

# Release: Developer ID signature, then notarize + staple + DMG (run in Terminal;
# notarytool needs the "MediaSpy" keychain profile — setup notes in the script)
./scripts/sign.sh
./scripts/notarize.sh                      # → dist/MediaSpy-<version>.dmg

# Install so the Service + Quick Look extension register:
cp -R build/Build/Products/Release/MediaSpy.app /Applications/
lsregister -f /Applications/MediaSpy.app         # (full path under LaunchServices.framework)
qlmanage -p <some.mkv>                            # test the Quick Look preview
```

Dev prerequisite: `brew install libmediainfo xcodegen cmake ninja create-dmg` (Homebrew libmediainfo is only for the SPM CLI/tests). `project.yml` is the source of truth;
`MediaSpy.xcodeproj` is generated (git-ignored).

---

## 10. Risks & mitigations

| Risk | Mitigation |
| --- | --- |
| Universal xcframework build for libmediainfo/libzen is fiddly | Start from Homebrew arm64 for dev; script the universal build early in M4; MediaArea also publishes prebuilt libs. |
| App Store sandbox + extension entitlements | Prototype the Service + security-scoped file access early; keep parsing in the framework. |
| Right-click UX weaker than Windows shell ext | Combine Service + Quick Action + Quick Look for MediaInfo-parity feel. |
| JSON key order not preserved | Curated ordered field lists per track type (already planned). |
| libmediainfo version drift / field changes | Pin the bundled version; models tolerate missing keys via fallback lookups. |
| Swift 6 strict concurrency friction | Ship in language mode v5 first, tighten later. |

---

## 11. Open decisions

- Minimum macOS version (14 vs 13).
- Distribution channel: App Store, Developer ID, or both.
- App name / bundle identifier (working name: **MediaSpy**).
- Whether to ship a bundled CLI helper (useful for Quick Actions and power users).
- Export formats to support in v1 (MediaInfo offers text/HTML/XML/JSON).

---

## 12. UI / design — LANDED ✅ (Ember direction)

Design files live in `/design/` (Claude Design canvases):
- `MediaSpy Concepts.dc.html` — three theme directions (1a **Ember**, 1b Signal, 1c Folio)
  plus a tabs-instead-of-sidebar variant (1d).
- `MediaSpy Ember.dc.html` — **the chosen direction, refined.** Four screens:
  **2a** single horizontal video (no sidebar, General on top, streams below) ·
  **2b** multiple files (sidebar slides in) ·
  **2c** audio file (waveform hero + per-channel dB meters) ·
  **2d** many streams (dense one-row-per-stream subtitle table, 10 subs).

### Design tokens (extracted from the Ember canvas)
- **Fonts:** Space Grotesk (display) + IBM Plex Mono (data/labels). Both SIL OFL —
  bundle in the app. System-font fallback possible but changes the character.
- **Palette (warm near-black):** backgrounds `#17120f`/`#1e1815`/`#241d19`; amber accent
  `#f2a93b`; coral `#f26d5b`; purple `#b583ff`; warm text tones `#eaded2`/`#c9bcb0`/`#857468`.
- **Chrome:** hidden title bar, centered mono filename, traffic lights, `+` add-file button
  (SwiftUI `.hiddenTitleBar` + custom toolbar).
- Refined direction **drops the right-click popup** — Finder actions open straight into the
  main window. This simplifies §7: the Service just opens the app with the file.

### Feasibility vs the engine (assessed 2026-07-06)
~90% of every pixel is a straight render of libmediainfo JSON fields (all General/Video/
Audio/Text fields shown exist verbatim in the PoC output — profile, chroma, CABAC/ref
frames, BT.709, Default/Forced flags, HDR format, writing app, …). Three elements need
**AVFoundation decode machinery beyond libmediainfo** (it never decodes):

1. **Video thumbnails** — `AVAssetImageGenerator` covers MP4/MOV/M4V. **MKV is not
   AVFoundation-decodable** → codec-styled placeholder tile (design's dark tile + play glyph
   degrades cleanly). Revisit third-party decode later if it matters.
2. **Waveform hero (2c)** — `AVAudioFile` decode + peak downsampling; WAV/AIFF/MP3/M4A/FLAC
   all supported. Non-decodable audio → decorative bars fallback.
3. **Channel dB meters (2c)** — same decode path + Accelerate/vDSP peak/RMS.

SDH flag (2d) = heuristic from subtitle Title text. Bitrate-quality bar ("HIGH BITRATE",
"MASTERING QUALITY") = simple resolution/codec-aware heuristic. Chapters (Menu tracks)
aren't in the design — add as a small section later (M5). No blockers; M2 can implement
this design as drawn.
