# DynamicQr — Image Transfer PC → Phone via Animated QR

Date: 2026-11-18
Status: Draft for approval

## 1. Intent

A feasibility test: can a txqr-style animated QR code (https://github.com/divan/txqr)
move images from a Windows PC to a HarmonyOS phone with no cable, network, or
pairing? The PC plays a looping animation of QR codes on screen; the phone app
points its camera at the screen, can join at any moment, and rebuilds the images.

Convenience is the point of the PC side: the user should copy a folder and
double-click, installing nothing.

## 2. Goals, non-goals, anti-goals

Goals
- PC: double-click `.bat` sender, nothing to install. Accepts any number of images
  (drag-and-drop onto the `.bat`, or a multi-select file picker when started bare).
- Phone: HarmonyOS app (this `DynamicQr` project) that scans continuously, shows
  progress, verifies the result, shows the images and can save them to the gallery.
- Receiver can start mid-animation and miss arbitrary frames (fountain code).
- Measurable: the app reports elapsed time and effective throughput so we can judge feasibility.

Non-goals
- Byte-exact originals. **Decided by user:** images are shrunk before sending.
- Phone → PC direction, back channel, streaming, encryption, non-image files
  (the bundle format is generic, but the PC UI only accepts images).
- Android/iOS receivers; non-Windows senders.

Anti-goals (would make it a failure even if it "works")
- Requiring the user to install Python, .NET SDK, Node, etc. on the PC.
- Silent corruption: the phone must never present an image that failed verification.

## 3. Constraints

- PC: Windows 10/11, stock Windows PowerShell 5.1 + .NET Framework 4.x.
  `Add-Type` there compiles **C# 5 only** (no `$""` interpolation, no `?.`, no
  `nameof`, no expression-bodied members). All C# must respect this.
- Phone: HarmonyOS, ArkTS, Stage model, `compatibleSdkVersion` 6.1.1(24),
  `targetSdkVersion` 26.0.0 (from existing `build-profile.json5`). ArkTS strict
  rules apply (no `any`, no untyped object literals, etc.).
- QR scanning via Scan Kit returns results as **strings**, so the payload must be
  text-safe → Base45 in QR alphanumeric mode.
- No git repo exists in the project yet; this doc is not committed.

## 4. Approaches considered

PC sender
- **A (chosen):** `.bat` → PowerShell → embedded C# (via `Add-Type`) for resize,
  bundle, fountain code, and a full-screen WinForms window; QR rendering by the
  bundled MIT library **QRCoder.dll** (a file next to the `.bat`, not installed).
  Chosen: zero install, reliable QR generation, editable without a build step.
- B: same but hand-written QR encoder — removes one DLL but adds hundreds of lines
  of error-prone code unrelated to what we're testing.
- C: compiled `.exe` — needs a build step per change and unsigned exes get flagged.
- (Rejected earlier: Python script — requires an install.)

Phone scanning
- **1 (chosen to start):** Scan Kit `customScan` with a `rescan()` loop — simplest, has autofocus.
- **2 (fallback):** camera frames + `detectBarcode.decode()` per frame, if (1) is too slow.
  The protocol/decoder layer must not depend on which scanning path is used.
  **User decision:** this build includes option 1 only. It ends with a measurement
  on a real device (scan rate shown in the app); whether to build option 2 is decided
  with the user afterwards. Option 2 is out of scope for this plan.

Payload text encoding: Base45 (RFC 9285) in alphanumeric mode, ~97% of byte-mode
efficiency, text-safe. Fountain code: LT with Robust Soliton, endless new block IDs.

**User decisions:** shrink images (option 2); approach A + 1 with 2 as fallback.

## 5. Architecture

```
PC (tools/pc-sender/)                          Phone (entry/)
images ─► resize/JPEG ─► bundle ─► LT encoder   customScan ─► Base45 decode ─► frame parse
                                    │                                  │
                              frame bytes                         LT peeling decoder
                                    │                                  │
                         Base45 ─► QRCoder ─► full-screen      bundle verify (CRC32) ─► unpack
                                     window @ N fps               ─► thumbnails ─► save to gallery
```

### 5.1 Image preparation (PC)
- Load each image with System.Drawing; apply EXIF orientation (tag 0x0112) then drop metadata.
- Scale so the long side ≤ 1280 px (never upscale). High-quality bicubic.
- Flatten transparency onto white. Re-encode every image as JPEG, quality 80.
- Output name: original base name + `.jpg`; on duplicate names append `_2`, `_3`, …
- Configurable via flags: `-MaxSide`, `-Quality`.

### 5.2 Bundle format (binary, little-endian)
```
magic     4  bytes  "DQB1"
count     u16
repeat count times:
  nameLen u16
  name    nameLen bytes, UTF-8
  dataLen u32
  data    dataLen bytes
```
The whole bundle is described by `bundleLen` and `bundleCrc32` (CRC-32/IEEE, the
zlib polynomial 0xEDB88320) carried in every frame header.

### 5.3 Blocks and LT fountain code
- `blockSize` B (default 800 bytes, flag `-BlockSize`). `K = ceil(bundleLen / B)`.
  The last source block is zero-padded to B.
- Block IDs are u32 and increase forever (0, 1, 2, …); the sender never loops a fixed set.
- **Systematic start:** for `blockId < K` the block is source block `blockId` (degree 1).
  For `blockId ≥ K` it is an LT block.
- LT block for `blockId`:
  - Degree d drawn on the **sender only** from Robust Soliton(K, c = 0.1, δ = 0.5)
    and **written into the frame header**, so receivers never recompute floating-point
    distributions (avoids cross-runtime floating-point mismatch).
  - Neighbour indices: PRNG seeded with `seed = mix32(transferId, blockId)`; draw
    `next() % K` repeatedly, skipping duplicates, until d distinct indices.
  - Data = XOR of those source blocks.
- PRNG = **mulberry32**, `mix32(a, b)` = `a ^ Math.imul(b + 0x9E3779B9 | 0, 0x85EBCA6B)`
  followed by the murmur3 fmix32 finaliser. Specified as 32-bit unsigned integer
  ops so C# (`uint`, `unchecked`) and ArkTS (`Math.imul`, `>>> 0`) produce identical
  sequences. The exact reference code lives in both implementations and is pinned
  by cross-implementation test vectors (§8).
- If `bundleLen ≤ B` then K = 1 and every frame is just the single block.

### 5.4 Frame format
Binary frame, then Base45-encoded into an alphanumeric-mode QR string:
```
offset size field
0      1    version      = 1
1      4    transferId   u32, random per sender run
5      4    bundleLen    u32
9      2    blockSize    u16
11     4    bundleCrc32  u32
15     4    blockId      u32
19     2    degree       u16
21     B    payload
21+B   2    frameCrc16   CRC-16/CCITT-FALSE over bytes [0, 21+B)
```
Header overhead 23 bytes. Default frame = 823 bytes → 1235 Base45 chars → about
QR version 22 at ECC level L. ECC level is **L** (fountain code handles losses;
txqr found higher ECC levels just cost capacity). Flag `-Ecc` allows M.

### 5.5 Sender window (PC)
- Borderless full-screen WinForms window on the primary monitor, white background.
- QR drawn as large as fits the screen height minus a ~40 px status strip, integer
  module scaling (nearest-neighbour, no blur), 4-module quiet zone.
- Status strip: file count, bundle size, K, blockId, fps, elapsed.
- Frames generated on the fly at the target fps (default 8, flag `-Fps`); a timer
  drives the frame clock. Keys: `+`/`-` change fps by 1 (range 1–30), `Space` pause,
  `Esc` quit.
- Before showing the window, print a console summary (images, sizes after shrink,
  bundle size, K, estimated time at the current fps).
- Hidden mode `-DumpFrames <n> -Out <file>`: write the first n frame strings, one
  per line, plus the input bundle as `<file>.bundle`, for tests (§8). Allows a fixed
  `-TransferId` for reproducible output.

### 5.6 Receiver (phone)
Scanning
- Request `ohos.permission.CAMERA` at runtime.
- `customScan` with QR only, rendered in an XComponent. In the result callback, hand
  the string to the protocol layer, then call `rescan()` immediately.
- Keep the screen on while scanning.

Protocol layer (pure ArkTS, no UI dependencies, unit-testable)
- `Base45.decode`, `Crc32`, `Crc16`, `Mulberry32`/`mix32`, `Frame.parse` (validate
  version, length and frameCrc16; reject silently on any failure).
- `LtDecoder`: peeling (belief-propagation) decoder. Dedupe by blockId. Store
  undecoded blocks with their neighbour sets; when a source block resolves, XOR it
  out of pending blocks and cascade.
- Session rule: the decoder locks onto the first valid `transferId`. A frame with a
  different `transferId` resets the session and starts over with the new one
  (one sender at a time; a restarted sender wins).
- On completion: assemble, truncate to `bundleLen`, check `bundleCrc32`. If it fails,
  show an error and reset (never show unverified images).
- `Bundle.unpack` → list of {name, bytes}.

UI (single page)
```
┌─────────────────────────────┐
│     camera preview          │
│     (scan area)             │
├─────────────────────────────┤
│ Receiving 3 files · 412 KB  │
│ ████████░░░░  142/188 (75%) │
│ 00:31 · 13.2 KB/s · 9 fr/s  │
│ [Reset]                     │
└─────────────────────────────┘
after success:
┌─────────────────────────────┐
│ ✓ 3 images · 412 KB · 41 s  │
│ ┌───┐ ┌───┐ ┌───┐           │
│ │img│ │img│ │img│  (tap = full view)
│ └───┘ └───┘ └───┘           │
│ [Save all to gallery] [Scan again] │
└─────────────────────────────┘
```
- Progress = resolved source blocks / K. Also show scan rate (frames/s) and unique
  frames received, which is the key feasibility metric for the Scan Kit path.
- Saving: `SaveButton` security component + `photoAccessHelper` so no extra
  storage permission is needed.

## 6. Project layout
```
DynamicQr/
  tools/pc-sender/
    send.bat                 # entry point; forwards args to the .ps1 with -ExecutionPolicy Bypass
    DynamicQrSender.ps1      # params, file picker, Add-Type, launches window
    Sender.cs                # C# 5: resize, bundle, LT encoder, Base45, CRCs, window
    lib/QRCoder.dll          # MIT, net40-compatible build, committed with LICENSE
    README.md
  entry/src/main/ets/
    protocol/  Base45.ets Crc.ets Prng.ets Frame.ets LtDecoder.ets Bundle.ets
    pages/Index.ets          # scan + progress + results
  entry/src/test/            # local unit tests (hypium) for protocol/
  docs/superpowers/specs/2026-11-18-dynamic-qr-design.md
```

## 7. Risks / unknowns
1. **Scan Kit rate.** `customScan` + `rescan()` may give only a few codes/s and
   dense codes may be rejected. That's the first thing to measure; fallback 2 exists.
2. Base45 contains a space character; confirm Scan Kit returns it intact (test vector
   with spaces in §8).
3. Monitor moiré/refresh and auto-exposure; mitigated by large integer-scaled modules,
   tunable `-BlockSize`/`-Fps`.
4. LT overhead at small K is ~10–30%; acceptable. The systematic start reduces it
   when the receiver happens to join early.

## 8. Testing and success criteria
- PC unit-ish checks: the `.ps1` has a `-SelfTest` switch that round-trips a random
  bundle through its own encoder and a C# reference decoder with 50% random frame loss.
- Cross-implementation vectors: `-DumpFrames` output for a fixed `-TransferId` and a
  small sample bundle is checked into `entry/src/test/vectors/`; ArkTS unit tests
  decode it and compare bytes with the `.bundle` file. Also tests for Base45 (RFC 9285
  examples), CRC32/CRC16 known values, PRNG sequence, and decoding with frames dropped
  and shuffled.
- End-to-end acceptance (manual, real devices): send 3 typical photos; the phone
  shows "verified", displays all 3, and saves them to the gallery. Record total time
  and KB/s. Feasibility verdict = those numbers.

## 9. Left to the builder
- Exact QRCoder version (any net40-compatible release), WinForms details, status-strip styling.
- ArkTS UI styling, thumbnail grid details, full-image viewer.
- Internal data structures of the peeling decoder.

## 10. Calls made by the designer (not discussed with the user)
- Accepted input formats: whatever System.Drawing reads — JPG, PNG, BMP, GIF (first
  frame), TIFF. HEIC/WebP are rejected with a clear console message.
- Defaults: block size 800 B, 8 fps, ECC L, long side 1280 px, JPEG quality 80.
- Systematic first K blocks; LT degree carried in the header; CRC16 per frame.
- A new transferId resets the phone's session.
- Images are shown in-app and saved only when the user taps "Save all to gallery".
- A git repo will be initialised at the start of implementation so the work can be committed.
