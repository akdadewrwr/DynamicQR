# DynamicQr

Send images from a Windows PC to a HarmonyOS phone **through the screen and the camera**: no cable, no Wi-Fi, no Bluetooth, no pairing.

The PC plays the images as a looping, animated QR code. The phone app points its camera at the screen and rebuilds the images. It can start watching at any moment and can miss any number of frames: it simply keeps reading until it has enough.

Inspired by [divan/txqr](https://github.com/divan/txqr), with a few changes: an endless (truly rateless) fountain code, a Robust Soliton distribution, per-frame and whole-transfer checksums, multiple files per transfer, and a zero-install Windows sender.

> **Status:** feasibility prototype. The PC sender and the decoding logic are tested; the phone app builds but has **not yet been measured on a real device**. Expected speed is roughly 2-10 KB/s, so a shrunk photo (~100-200 KB) takes on the order of 15-60 s.

```
 Windows PC                                              HarmonyOS phone
 ┌──────────────────────────────┐   screen → camera   ┌─────────────────────────────┐
 │ images → shrink → bundle     │  ═══════════════▶   │ scan → decode → verify      │
 │ → fountain code → QR frames  │   animated QR code  │ → show → save to gallery    │
 └──────────────────────────────┘                     └─────────────────────────────┘
```

## Quick start

### On the PC (Windows 10/11, nothing to install)

1. Copy the `tools/pc-sender` folder anywhere.
2. **Drag images onto `send.bat`**, or double-click it and pick images.
3. A console lists the images and an estimated time, then a window with the QR animation opens. Resize or move it as you like (the code rescales); `F11` toggles full screen.

Keys in the animation window: `+` / `-` change speed, `Space` pause, `F11` full screen, `Esc` quit.

### On the phone (HarmonyOS, API 24+)

1. Open this project in **DevEco Studio**, set up signing, and run the `entry` module on your phone.
2. Allow camera access and point the phone at the PC screen.
3. Watch the progress bar. When it finishes, the images are checked against a checksum and shown in a grid. Tap **Save to gallery** to keep them.

## Sender options

`send.bat` accepts the same options as `DynamicQrSender.ps1`, for example
`send.bat -Fps 12 -BlockSize 600 photo1.jpg photo2.png`.

| Option | Default | Meaning |
|---|---|---|
| `-Fps` | 8 | Frames per second (1-30); also adjustable with `+` / `-` |
| `-BlockSize` | 800 | Payload bytes per QR frame. Bigger means denser codes and fewer frames |
| `-Ecc` | L | QR error-correction level (`L` or `M`) |
| `-MaxSide` | 1280 | Longest image side after shrinking, in pixels |
| `-Quality` | 80 | JPEG quality after shrinking |
| `-SelfTest` | | Run the built-in checks (prints `SELFTEST PASS`) |

Accepted formats: JPG, PNG, BMP, GIF (first frame), TIFF. Images are rotated according to EXIF, shrunk and re-encoded as JPEG before sending, so the phone gets a good-looking copy, not the original file.

## How it works

1. **Prepare.** Each image is shrunk and re-encoded as JPEG. All images are packed into one *bundle* (file names + data).
2. **Split.** The bundle is cut into `K` blocks of `BlockSize` bytes.
3. **Fountain code.** The sender produces an endless stream of frames. The first `K` are the blocks themselves; after that, each frame is the XOR of a random set of blocks, with the set size drawn from a Robust Soliton distribution. Any slightly-more-than-`K` frames are enough to rebuild everything, in any order, from any starting point.
4. **QR.** Each frame gets a small header and a CRC-16, is encoded as [Base45](https://www.rfc-editor.org/rfc/rfc9285) text and shown as an alphanumeric-mode QR code.
5. **Receive.** The phone decodes each QR code it sees, ignores anything that isn't a valid frame, and runs a peeling decoder. Once all `K` blocks are known, the bundle's CRC-32 is checked before any image is shown.

Frame layout (little-endian, before Base45):

| Bytes | Field |
|---|---|
| 1 | version (1) |
| 4 | transfer id (random per sender run) |
| 4 | bundle length |
| 2 | block size |
| 4 | bundle CRC-32 |
| 4 | block id |
| 2 | degree (number of blocks XORed) |
| BlockSize | payload |
| 2 | CRC-16 of everything above |

Both sides derive the XORed block set from the same 32-bit generator (mulberry32 seeded from transfer id + block id), so only the degree travels in the header. The full design is in [`docs/superpowers/specs/2026-11-18-dynamic-qr-design.md`](docs/superpowers/specs/2026-11-18-dynamic-qr-design.md).

## Project layout

```
tools/pc-sender/          Windows sender: send.bat, DynamicQrSender.ps1, C# sources, QRCoder.dll
entry/src/main/ets/
  protocol/               Pure-ArkTS protocol: Base45, CRC, PRNG, frames, LT decoder, bundle, session
  pages/Index.ets         Phone UI: camera scanning, progress, results, save to gallery
entry/src/test/vectors/   Frames produced by the PC sender, used to test the phone decoder
tools/protocol-tests/     Node test runner for the ArkTS protocol code
tools/build-hap.sh        Command-line build of the phone app
docs/                     Design spec and implementation plan
```

## Development

| Task | Command |
|---|---|
| Phone protocol tests (Node 22+) | `node tools/protocol-tests/run.mjs` |
| PC sender self-test | `powershell -ExecutionPolicy Bypass -File tools/pc-sender/DynamicQrSender.ps1 -SelfTest` |
| Build the phone app (Git Bash) | `bash tools/build-hap.sh` |
| Regenerate cross-implementation vectors | `powershell -ExecutionPolicy Bypass -File tools/pc-sender/make-vectors.ps1` |

The PC and phone implementations are pinned to the same test values (PRNG sequence, block selection, CRC check values) and to the shared frame vectors, so a change on one side that breaks compatibility fails the tests.

## Limitations

- One direction only (PC → phone), one sender at a time.
- Images are shrunk; exact original files are not transferred.
- Speed depends heavily on how many QR codes per second the phone's scanner can read; this hasn't been measured yet.

## Credits

- [divan/txqr](https://github.com/divan/txqr): the original idea and protocol.
- [QRCoder](https://github.com/codebude/QRCoder) (MIT): QR rendering on the PC, bundled as `tools/pc-sender/lib/QRCoder.dll` (licence in `lib/QRCoder-LICENSE.txt`).
