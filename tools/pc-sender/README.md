# DynamicQr PC sender

Shows images as an endless animated QR code that the DynamicQr phone app can scan from any point.
Runs on stock Windows 10/11 (Windows PowerShell 5.1 + .NET Framework 4). Nothing to install:
copy this whole folder (it includes `lib/QRCoder.dll`, MIT licence in `lib/QRCoder-LICENSE.txt`).

## Use

- **Drag images onto `send.bat`**, or **double-click `send.bat`** and pick images.
- A console lists each image after shrinking, the bundle size and an estimated time, then a
  window with the QR animation opens (maximized; resize or move it freely, the code rescales).
- Open the app on the phone and point the camera at the screen. It can start at any moment.

Keys in the animation window: `+` / `-` change speed (1-30 fps), `Space` pause, `F11` toggle full screen, `Esc` quit (or leave full screen).

Accepted formats: JPG, PNG, BMP, GIF (first frame), TIFF. HEIC/WebP are skipped with a message.
Each image is rotated per its EXIF orientation, shrunk to at most 1280 px on the long side, and
re-encoded as JPEG quality 80 (metadata removed). Names become `<name>.jpg` (`_2`, `_3` on clashes).

## Options

Run `DynamicQrSender.ps1` directly (or pass options after `send.bat`):

| Option | Default | Meaning |
|---|---|---|
| `-Fps` | 8 | Frames per second (1-30) |
| `-BlockSize` | 800 | Payload bytes per QR frame (bigger = denser codes) |
| `-Ecc` | L | QR error-correction level, `L` or `M` |
| `-MaxSide` | 1280 | Longest image side in pixels after shrinking |
| `-Quality` | 80 | JPEG quality |
| `-SelfTest` | | Run the built-in checks; prints `SELFTEST PASS` |
| `-DumpFrames n -Out file` | | Write the first n frames as text (+ `file.bundle`) instead of showing them |
| `-TransferId hex` | random | Fixed transfer id (for reproducible dumps) |

Example: `powershell -ExecutionPolicy Bypass -File DynamicQrSender.ps1 -Fps 12 -BlockSize 600 a.jpg b.png`

## Code

- `src/Protocol.cs`: Base45, CRCs, PRNG, Robust Soliton, bundle and frame encoding (must match `entry/src/main/ets/protocol`)
- `src/ImagePrep.cs`: orientation, resize and JPEG
- `src/SenderForm.cs`: full-screen window
- `src/ReferenceDecoder.cs`, `src/SelfTest.cs`: self-test only
- `make-vectors.ps1`: regenerates the cross-implementation test vectors in `entry/src/test/vectors`
