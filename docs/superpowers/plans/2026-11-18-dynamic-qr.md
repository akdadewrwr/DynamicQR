# DynamicQr Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A double-click Windows sender that plays images as an endless fountain-coded QR animation, and a HarmonyOS app that scans it from any point and rebuilds the verified images.

**Architecture:** One wire protocol, implemented twice: in C# 5 (PC sender: resize → bundle → LT encoder → Base45 → QRCoder → full-screen WinForms) and in ArkTS (phone: Scan Kit `customScan` → Base45 → frame parse → LT peeling decoder → CRC verify → unpack). Pure-ArkTS protocol code lives in `entry/src/main/ets/protocol/` with no UI imports, is unit-tested under Node, and both implementations are pinned by shared test vectors that the PC sender generates.

**Tech Stack:** Windows PowerShell 5.1 + .NET Framework 4 (C# 5 via `Add-Type`), QRCoder 1.6.0 (net40 DLL), WinForms/System.Drawing; HarmonyOS ArkTS (Stage model, API 24+), Scan Kit, photoAccessHelper; Node 24 (`node:test`) for protocol tests.

**Spec:** `docs/superpowers/specs/2026-11-18-dynamic-qr-design.md` — read it before starting any task; byte layouts and constants come from §5.

## Global Constraints

- PC: nothing installed on the user's machine. Stock Windows PowerShell 5.1 + .NET Framework 4.x only. QRCoder.dll is a file next to the scripts.
- C# compiled by `Add-Type` is **C# 5**: no `$""`, no `?.`, no `nameof`, no expression-bodied members, no `out var`, no tuples. All arithmetic in the protocol uses `uint` inside `unchecked`.
- Phone: `compatibleSdkVersion` 6.1.1(24), `targetSdkVersion` 26.0.0, ArkTS strict (no `any`/`unknown`, no untyped object literals, no structural typing, no `enum` in protocol files, no destructuring).
- Protocol files (`entry/src/main/ets/protocol/*.ets`) must be **plain TypeScript-compatible ArkTS**: no decorators, no `struct`, no `@kit.*`/`@ohos.*` imports, no `enum`, no constructor parameter properties, no namespaces (so Node can strip types and run them).
- Constants (spec §5): bundle magic `"DQB1"`; frame version `1`; header 21 bytes; CRC16 trailer 2 bytes; Robust Soliton `c = 0.1`, `δ = 0.5`; defaults `BlockSize 800`, `Fps 8`, `Ecc L`, `MaxSide 1280`, `Quality 80`; fps range 1–30.
- All multi-byte integers little-endian. CRC-32/IEEE (poly 0xEDB88320, check value of "123456789" = `0xCBF43926`). CRC-16/CCITT-FALSE (poly 0x1021, init 0xFFFF, check = `0x29B1`).
- Base45 alphabet (RFC 9285): `0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ $%*+-./:`.
- Never present images whose bundle CRC32 did not verify.
- Build the HAP with `bash tools/build-hap.sh` (Task 1). Protocol tests: `node tools/protocol-tests/run.mjs` (Task 1). `ohpm install` cannot reach its registry on this machine, so hypium-based tests are not used; leave the template's hypium test files untouched.

## Review Focus

1. **A QR code that isn't ours in the camera's view** (a URL, Wi-Fi code, truncated scan) → silently ignored, no crash, no progress change. Pinned in Task 2 (`parseFrame` rejects) and Task 3 (session ignores).
2. **The PC sender is restarted mid-transfer** (new transferId) → phone drops old progress and finishes the new transfer correctly. Pinned in Task 3.
3. **Non-ASCII file names** (e.g. `测试 图片(1).png`) → arrive with the identical UTF-8 name. Pinned in Task 3 (bundle round trip) and Task 7 (cross-implementation vector).
4. **Paths with spaces, parentheses, `&`, `[ ]`** dragged onto `send.bat` → all files are sent. Pinned in Task 5.
5. **A single small image** (bundle ≤ BlockSize, K = 1) and odd-length Base45 tails → transfer completes. Pinned in Task 2 (Base45 odd lengths) and Task 3 (K = 1).

---

## File Structure

```
.gitignore                                   (modify: add tools/protocol-tests/.gen/)
tools/build-hap.sh                           build HAP with DevEco's bundled JDK/node
tools/protocol-tests/run.mjs                 copies protocol/*.ets → .gen/*.ts, runs node --test
tools/protocol-tests/hooks.mjs               resolves extensionless relative imports to .ts
tools/protocol-tests/register.mjs
tools/protocol-tests/package.json            {"type":"module"}
tools/protocol-tests/tests/*.test.ts         Node tests for protocol code
tools/protocol-tests/tests/helpers/TestEncoder.ts  reference LT encoder for tests
entry/src/main/ets/protocol/Base45.ets
entry/src/main/ets/protocol/Crc.ets
entry/src/main/ets/protocol/Utf8.ets
entry/src/main/ets/protocol/Prng.ets         mix32, Mulberry32, ltNeighbors
entry/src/main/ets/protocol/Frame.ets
entry/src/main/ets/protocol/LtDecoder.ets
entry/src/main/ets/protocol/Bundle.ets
entry/src/main/ets/protocol/ReceiverSession.ets
entry/src/main/ets/pages/Index.ets           scan + progress + results UI
entry/src/main/module.json5                  (modify: camera permission)
entry/src/main/resources/base/element/string.json  (modify: strings)
entry/src/test/vectors/frames.txt            generated by sender (Task 7)
entry/src/test/vectors/bundle.bin            generated by sender (Task 7)
tools/pc-sender/send.bat
tools/pc-sender/DynamicQrSender.ps1
tools/pc-sender/src/Protocol.cs              Base45, Crc, Prng, RobustSoliton, BundleWriter, FrameEncoder
tools/pc-sender/src/ReferenceDecoder.cs      C# peeling decoder, used by -SelfTest only
tools/pc-sender/src/ImagePrep.cs             EXIF orientation, resize, JPEG
tools/pc-sender/src/SenderForm.cs            full-screen animation window
tools/pc-sender/src/SelfTest.cs
tools/pc-sender/lib/QRCoder.dll              QRCoder 1.6.0 lib/net40
tools/pc-sender/lib/QRCoder-LICENSE.txt
tools/pc-sender/make-vectors.ps1             regenerates entry/src/test/vectors
tools/pc-sender/README.md
docs/results.md                              feasibility measurements (Task 10)
```

(The spec's single `Sender.cs` is split into focused files under `src/`; `Add-Type -Path` takes all of them.)

---

### Task 1: Repo, build script, Node test harness, Base45 + CRC + UTF-8 (ArkTS)

**Files:**
- Create: `tools/build-hap.sh`, `tools/protocol-tests/{run.mjs,hooks.mjs,register.mjs,package.json}`
- Create: `entry/src/main/ets/protocol/Base45.ets`, `Crc.ets`, `Utf8.ets`
- Test: `tools/protocol-tests/tests/base45.test.ts`, `crc.test.ts`, `utf8.test.ts`
- Modify: `.gitignore`

**Interfaces:**
- Produces:
  - `base45Encode(data: Uint8Array): string`; `base45Decode(text: string): Uint8Array | null` (null on any invalid char, length % 3 == 1, or a triple value > 65535 / pair value > 255)
  - `crc32(data: Uint8Array, start: number, end: number): number` (unsigned); `crc16(data: Uint8Array, start: number, end: number): number`
  - `utf8Encode(s: string): Uint8Array`; `utf8Decode(b: Uint8Array): string` (handles surrogate pairs)

- [ ] **Step 1: Init git and tooling**

`git init`; append `tools/protocol-tests/.gen/` to `.gitignore`. Create `tools/build-hap.sh`:
```bash
#!/usr/bin/env bash
set -e
cd "$(dirname "$0")/.."
DE="/c/Program Files/Huawei/DevEco Studio"
export DEVECO_SDK_HOME="C:/Program Files/Huawei/DevEco Studio/sdk"
export JAVA_HOME="C:/Program Files/Huawei/DevEco Studio/jbr"
export PATH="$DE/jbr/bin:$DE/tools/node:$PATH"
"$DE/tools/hvigor/bin/hvigorw.bat" --mode module -p module=entry@default -p product=default -p buildMode=debug assembleHap --no-daemon
```
`hooks.mjs` (verified working with Node 24 in this environment):
```js
export async function resolve(spec, ctx, next) {
  if ((spec.startsWith('./') || spec.startsWith('../')) && !/\.[cm]?[jt]s$/.test(spec)) {
    try { return await next(spec + '.ts', ctx); } catch {}
  }
  return next(spec, ctx);
}
```
`register.mjs`: `import { register } from 'node:module'; register('./hooks.mjs', import.meta.url);`
`run.mjs`: delete and recreate `.gen/protocol/`, copy every `entry/src/main/ets/protocol/*.ets` to `.gen/protocol/*.ts`, then spawn `node --import ./register.mjs --test tests/*.test.ts` with cwd `tools/protocol-tests`, inherit stdio, exit with its code. Tests import from `'../.gen/protocol/<Name>'`.

- [ ] **Step 2: Write failing tests**

```ts
// base45.test.ts — RFC 9285 examples
assert.equal(base45Encode(utf8Encode('AB')), 'BB8');
assert.equal(base45Encode(utf8Encode('Hello!!')), '%69 VD92EX0');
assert.equal(base45Encode(utf8Encode('base-45')), 'UJCLQE7W581');
assert.equal(utf8Decode(base45Decode('QED8WEX0')!), 'ietf!');
// odd tail + all byte values round-trip, lengths 0..20 and 1001
for (const n of [0, 1, 2, 3, 20, 1001]) { const b = randomBytes(n); assert.deepEqual(base45Decode(base45Encode(b)), b); }
assert.equal(base45Decode('GGW'), null);      // 65535+ overflow ("GGW" = 16*1+16*45+32*2025 > 65535)
assert.equal(base45Decode('A'), null);        // length % 3 == 1
assert.equal(base45Decode('https://x'), null);// lowercase not in alphabet
// crc.test.ts
const t = utf8Encode('123456789');
assert.equal(crc32(t, 0, t.length), 0xCBF43926);
assert.equal(crc16(t, 0, t.length), 0x29B1);
assert.equal(crc32(t, 1, 3), crc32(utf8Encode('23'), 0, 2));
// utf8.test.ts
for (const s of ['', 'abc', '测试 图片(1).png', 'emoji 😀.jpg']) assert.equal(utf8Decode(utf8Encode(s)), s);
assert.deepEqual(Array.from(utf8Encode('测')), [0xE6, 0xB5, 0x8B]);
```

- [ ] **Step 3: Run to verify failure** — `node tools/protocol-tests/run.mjs` → FAIL (modules missing).

- [ ] **Step 4: Implement the three modules** (table-free bitwise CRCs are fine).

- [ ] **Step 5: Run tests** — `node tools/protocol-tests/run.mjs` → all pass. `bash tools/build-hap.sh` → `BUILD SUCCESSFUL` (proves the files are valid ArkTS).

- [ ] **Step 6: Commit** — `git add -A && git commit -m "chore: init repo, build script, protocol test harness; feat: base45, crc, utf8"`

---

### Task 2: PRNG, LT neighbours, frame parse/encode (ArkTS)

**Files:**
- Create: `entry/src/main/ets/protocol/Prng.ets`, `Frame.ets`
- Test: `tools/protocol-tests/tests/prng.test.ts`, `frame.test.ts`

**Interfaces:**
- Consumes: Task 1 Base45/Crc.
- Produces:
  - `mix32(a: number, b: number): number`; `class Mulberry32 { constructor(seed: number); next(): number }`
  - `ltNeighbors(transferId: number, blockId: number, degree: number, k: number): number[]` — returns `[blockId]` when `blockId < k`; else `degree` distinct indices in draw order
  - `class Frame { version, transferId, bundleLen, blockSize, bundleCrc32, blockId, degree: number; payload: Uint8Array }`
  - `const FRAME_HEADER_LEN = 21`, `FRAME_OVERHEAD = 23`
  - `parseFrame(text: string): Frame | null`; `encodeFrame(f: Frame): string` (used by tests and TestEncoder)

- [ ] **Step 1: Write failing tests**

```ts
assert.equal(mix32(0, 0), 2287948138);
assert.equal(mix32(0x12345678, 1000), 222234753);
const r = new Mulberry32(1);
assert.deepEqual([r.next(), r.next(), r.next(), r.next(), r.next()],
  [2693262067, 11749833, 2265367787, 4213581821, 4159151403]);
assert.deepEqual(ltNeighbors(0x12345678, 1000, 5, 188), [19, 168, 24, 11, 20]);
assert.deepEqual(ltNeighbors(0x12345678, 7, 3, 188), [7]);            // systematic
// frame round trip
const f = makeFrame({ transferId: 0xDEADBEEF, bundleLen: 5000, blockSize: 800, bundleCrc32: 0xCAFEBABE, blockId: 4000000000, degree: 3, payload: randomBytes(800) });
assert.deepEqual(parseFrame(encodeFrame(f)), f);
// rejects
assert.equal(parseFrame('HTTPS://EXAMPLE.COM'), null);
assert.equal(parseFrame(''), null);
assert.equal(parseFrame(flipOneByteThenBase45(f)), null);              // CRC16 fails
assert.equal(parseFrame(encodeWithVersion(f, 2)), null);
assert.equal(parseFrame(truncatedFrameText(f)), null);                 // payload length != blockSize
assert.equal(parseFrame(encodeFrameWith(f, { blockSize: 0 })), null);
assert.equal(parseFrame(encodeFrameWith(f, { degree: 0, blockId: 9999 })), null);
```
(`makeFrame`, `flipOneByteThenBase45`, etc. are small helpers in the test file.)

- [ ] **Step 2: Run to verify failure** — `node tools/protocol-tests/run.mjs` → FAIL.

- [ ] **Step 3: Implement.** The PRNG and mix must be exactly (both platforms must match bit-for-bit):
```ts
// mix32
let h = (a ^ Math.imul((b + 0x9E3779B9) | 0, 0x85EBCA6B)) | 0;
h ^= h >>> 16; h = Math.imul(h, 0x85EBCA6B); h ^= h >>> 13; h = Math.imul(h, 0xC2B2AE35); h ^= h >>> 16;
return h >>> 0;
// Mulberry32.next
this.s = (this.s + 0x6D2B79F5) | 0;
let t = Math.imul(this.s ^ (this.s >>> 15), 1 | this.s);
t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
return (t ^ (t >>> 14)) >>> 0;
```
`ltNeighbors` (blockId ≥ k): `rng = new Mulberry32(mix32(transferId, blockId))`; loop `i = rng.next() % k`, push if not already present, until `degree` entries. `parseFrame` validation: Base45 ok, total length = 23 + blockSize, version 1, CRC16 over [0, 21+blockSize) matches the trailing u16, `blockSize ≥ 1`, `bundleLen ≥ 1`, `1 ≤ degree ≤ K` where `K = ceil(bundleLen / blockSize)`, and `degree == 1` when `blockId < K`.

- [ ] **Step 4: Run tests** → pass; `bash tools/build-hap.sh` → `BUILD SUCCESSFUL`.

- [ ] **Step 5: Commit** — `git commit -am "feat(protocol): prng, lt neighbours, frame format"` (add new files first).

---

### Task 3: LT peeling decoder, bundle, receiver session (ArkTS)

**Files:**
- Create: `entry/src/main/ets/protocol/LtDecoder.ets`, `Bundle.ets`, `ReceiverSession.ets`
- Create: `tools/protocol-tests/tests/helpers/TestEncoder.ts`
- Test: `tools/protocol-tests/tests/lt.test.ts`, `bundle.test.ts`, `session.test.ts`

**Interfaces:**
- Consumes: Tasks 1–2.
- Produces:
  - `class LtDecoder { constructor(k: number, blockSize: number); addBlock(neighbors: number[], data: Uint8Array): void; resolvedCount(): number; isComplete(): boolean; assemble(totalLen: number): Uint8Array }`
  - `class BundleFile { name: string; data: Uint8Array }`; `packBundle(files: BundleFile[]): Uint8Array`; `unpackBundle(bytes: Uint8Array): BundleFile[]` (throws `Error` on bad magic/truncation/trailing bytes)
  - `class SessionState { static readonly IDLE = 0; static readonly RECEIVING = 1; static readonly COMPLETE = 2; static readonly FAILED = 3 }`
  - `class SessionProgress { transferId, k, resolved, uniqueFrames, scans, bundleLen, elapsedMs: number }`
  - `class ReceiverSession { constructor(now: () => number); onScan(text: string): boolean; state(): number; progress(): SessionProgress; files(): BundleFile[]; error(): string; reset(): void }`
  - Test helper `TestEncoder(bundle: Uint8Array, blockSize: number, transferId: number)` with `frame(blockId: number): string` (degree for LT blocks from a simple robust-soliton sampler seeded per block — the receiver doesn't care how degrees are chosen)

Behaviour pinned by the spec (§5.6): dedupe by blockId; lock onto first valid transferId; a frame with a different transferId resets and starts the new transfer; `scans` counts every `onScan` call; `uniqueFrames` counts accepted new blocks; `elapsedMs` runs from the first valid frame to completion; on completion assemble → truncate to bundleLen → CRC32 check → `unpackBundle`. CRC mismatch or unpack error → `FAILED` with `error()` set and `files()` empty; the next `onScan` after `FAILED` resets and starts over. `onScan` returns true only for a newly accepted block.

- [ ] **Step 1: Write failing tests**

```ts
// lt.test.ts
for (const [len, bs] of [[1, 800], [800, 800], [801, 800], [50_000, 800], [150_000, 800]]) {
  const bundle = randomBytes(len); const enc = new TestEncoder(bundle, bs, 42);
  // random start, 50% loss, shuffled within windows of 20
  const d = decodeWithLoss(enc, { startId: 500, loss: 0.5, seed: 7 });
  assert.deepEqual(d.assemble(len), bundle);
}
// systematic-only path: blocks 0..K-1 in order complete exactly at K
// duplicates and already-resolved blocks are harmless
// bundle.test.ts
const files = [bf('a.jpg', randomBytes(10)), bf('测试 图片(1).png', randomBytes(0)), bf('😀.jpg', randomBytes(3000))];
assert.deepEqual(unpackBundle(packBundle(files)), files);
assert.throws(() => unpackBundle(utf8Encode('XXXX')));
assert.throws(() => unpackBundle(packBundle(files).slice(0, 20)));
// session.test.ts
//  completes with files() equal to input; state COMPLETE; elapsedMs from fake clock
//  foreign texts ('HTTPS://X', '', 'WIFI:S:x;;') → onScan false, state stays IDLE, scans increments
//  restart: feed 60% of transfer A, then frames of transfer B (different id, different files) → completes with B's files
//  CRC failure: TestEncoder over a bundle but frames carry a wrong bundleCrc32 → FAILED, files() empty, error() non-empty; next onScan → RECEIVING
//  K = 1: one tiny file (bundle ≤ blockSize) completes after a single frame
```

- [ ] **Step 2: Run to verify failure** — `node tools/protocol-tests/run.mjs` → FAIL.

- [ ] **Step 3: Implement.** Peeling decoder: for an incoming block, XOR out every already-resolved neighbour; if none left, drop; if one left, resolve it and cascade through pending blocks that reference it (keep `Map<number, PendingBlock[]>` from source index → pending blocks, and a work queue — iterative, not recursive, since cascades can be K deep).

- [ ] **Step 4: Run tests** → pass; `bash tools/build-hap.sh` → `BUILD SUCCESSFUL`.

- [ ] **Step 5: Commit** — `git add -A && git commit -m "feat(protocol): LT peeling decoder, bundle, receiver session"`

---

### Task 4: C# protocol core + reference decoder + `-SelfTest` + `-DumpFrames`

**Files:**
- Create: `tools/pc-sender/src/Protocol.cs`, `ReferenceDecoder.cs`, `SelfTest.cs`, `tools/pc-sender/DynamicQrSender.ps1` (parameter block, `Add-Type`, `-SelfTest`, `-DumpFrames`; image handling and window come in Tasks 5–6)
- Create: `tools/pc-sender/lib/QRCoder.dll` (from `https://api.nuget.org/v3-flatcontainer/qrcoder/1.6.0/qrcoder.1.6.0.nupkg`, `lib/net40/QRCoder.dll`), `lib/QRCoder-LICENSE.txt` (MIT text from the package)

**Interfaces (namespace `DynamicQr`, all `public static` unless noted):**
- `Base45.Encode(byte[] data) : string`
- `Crc.Crc32(byte[] d, int start, int end) : uint`, `Crc.Crc16(byte[] d, int start, int end) : ushort`
- `Prng.Mix32(uint a, uint b) : uint`; `class Mulberry32 { Mulberry32(uint seed); uint Next(); }` — same algorithm as Task 2 in `unchecked` uint arithmetic
- `Lt.Neighbors(uint transferId, uint blockId, int degree, int k) : int[]`
- `class RobustSoliton { RobustSoliton(int k); int Sample(uint r); }` — CDF built once (c = 0.1, δ = 0.5, `R = c·ln(K/δ)·√K`, spike at `floor(K/R)` clamped to [1, K]); `Sample` maps `r / 2^32` through the CDF; K = 1 → always 1
- `BundleWriter.Pack(IList<KeyValuePair<string, byte[]>> files) : byte[]` (spec §5.2, names UTF-8)
- `class FrameEncoder { FrameEncoder(byte[] bundle, int blockSize, uint transferId); int K; uint BundleCrc32; string FrameText(uint blockId); }` — degree for `blockId ≥ K`: `soliton.Sample(new Mulberry32(Prng.Mix32(transferId, blockId) ^ 0xA5A5A5A5u).Next())`
- `class ReferenceDecoder { ReferenceDecoder(); bool AddFrameText(string text); bool IsComplete; byte[] Bundle; }` — includes Base45 decode and frame validation (self-test only)
- `SelfTest.Run() : bool` (prints each check as `PASS name` / `FAIL name: detail`)
- `.ps1` params: `[Parameter(ValueFromRemainingArguments=$true)][string[]]$Files`, `[int]$MaxSide=1280`, `[int]$Quality=80`, `[int]$BlockSize=800`, `[int]$Fps=8`, `[ValidateSet('L','M')][string]$Ecc='L'`, `[int]$DumpFrames=0`, `[string]$Out`, `[string]$TransferId` (hex like `12345678`; empty → random), `[switch]$SelfTest`. `Add-Type -Path (all src/*.cs) -ReferencedAssemblies System.Drawing, System.Windows.Forms, <lib/QRCoder.dll path>` after `Add-Type -Path lib/QRCoder.dll`.

- [ ] **Step 1: Write `SelfTest.Run()` checks first** (they are the failing tests):
  - `Crc32("123456789") == 0xCBF43926`, `Crc16(...) == 0x29B1`
  - `Base45.Encode("Hello!!") == "%69 VD92EX0"`, `"AB" → "BB8"`
  - `Mix32(0,0) == 2287948138`, `Mix32(0x12345678,1000) == 222234753`
  - `Mulberry32(1)` first five = `2693262067, 11749833, 2265367787, 4213581821, 4159151403`
  - `Lt.Neighbors(0x12345678, 1000, 5, 188)` = `{19, 168, 24, 11, 20}`
  - RobustSoliton(188): 10 000 samples all within [1, 188], mean degree between 3 and 15
  - round trip: random 150 000-byte bundle, blockSize 800, start at blockId 300, drop each frame with p = 0.5 (seeded `System.Random(1)`), feed `ReferenceDecoder` until complete; bundle equals input; frames used < 1.5·K
  - K = 1 round trip with a 10-byte bundle
  - every `FrameText` contains only Base45 alphabet characters
  - `QRCodeGenerator.CreateQrCode(FrameText(0), ECCLevel.L)` succeeds for blockSize 800 and its `Version ≤ 25`

- [ ] **Step 2: Run to verify failure** — `powershell -NoProfile -ExecutionPolicy Bypass -File tools/pc-sender/DynamicQrSender.ps1 -SelfTest` → compile errors / FAIL lines.

- [ ] **Step 3: Implement `Protocol.cs`, `ReferenceDecoder.cs`, and the `.ps1` switches.** `-SelfTest` exits 0 only when all checks pass and prints `SELFTEST PASS`. `-DumpFrames n -Out file` (used with files in Task 7) writes `FrameText(0..n-1)` one per line (UTF-8 without BOM, `\n`) to `file` and the raw bundle to `file.bundle`, then exits without opening the window.

- [ ] **Step 4: Run** the self-test command → last line `SELFTEST PASS`, exit code 0.

- [ ] **Step 5: Commit** — `git add tools/pc-sender && git commit -m "feat(sender): C# protocol core, reference decoder, self-test"`

---

### Task 5: Image preparation, file selection, `send.bat`, console summary

**Files:**
- Create: `tools/pc-sender/src/ImagePrep.cs`, `tools/pc-sender/send.bat`
- Modify: `tools/pc-sender/DynamicQrSender.ps1`, `tools/pc-sender/src/SelfTest.cs`

**Interfaces:**
- Produces: `ImagePrep.Prepare(string path, int maxSide, long quality) : byte[]` (JPEG bytes); `ImagePrep.OutputName(string path, ISet<string> taken) : string` (`<base>.jpg`, then `<base>_2.jpg`, `_3`…, case-insensitive)
- `send.bat`:
  ```bat
  @echo off
  powershell -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0DynamicQrSender.ps1" %*
  if errorlevel 1 pause
  ```

Rules (spec §5.1): apply EXIF orientation 0x0112 (values 1–8 → `RotateFlipType`) then remove all property items; scale long side to ≤ maxSide (never upscale), `HighQualityBicubic`; draw onto a white 24bpp canvas (flattens alpha); save JPEG with `Encoder.Quality = quality`. Accept `.jpg .jpeg .png .bmp .gif .tif .tiff` (case-insensitive); anything else (including `.heic`, `.webp`, folders) → console line `Skipped <name>: unsupported format`; if nothing is left, print `No images to send.` and exit 1. No `$Files` → `OpenFileDialog` (Multiselect, image filter); cancel → exit 0. All file access via `-LiteralPath` / .NET `File.ReadAllBytes` (never wildcard-expanded paths). Console summary before the window: one line per file (`name  WxH  NN KB`), then `Bundle: NNN KB, K = n blocks, ~MM s at F fps` (estimate = `ceil(K·1.15 / fps)`).

- [ ] **Step 1: Add self-test checks:**
  - 4000×3000 PNG with alpha → output decodes as JPEG, 1280×960, pixel at a transparent spot is white (each channel ≥ 250)
  - 800×600 → stays 800×600 (no upscale)
  - JPEG with orientation 6, 400×200 → output 200×400 (create the `PropertyItem` via `FormatterServices.GetUninitializedObject(typeof(PropertyItem))`)
  - output has no property items
  - `OutputName`: `a.png`, `A.jpg`, `a.bmp` → `a.jpg`, `A_2.jpg`, `a_3.jpg`

- [ ] **Step 2: Run self-test** → new checks FAIL.

- [ ] **Step 3: Implement `ImagePrep.cs` and the `.ps1` file-gathering / summary flow, plus `send.bat`.**

- [ ] **Step 4: Run self-test** → `SELFTEST PASS`.

- [ ] **Step 5: Special-path check.** In the scratch dir, create folder `dir with space & (x) [1]` containing `测试 图片(1).png` and `b.jpg` (generate via a short PowerShell snippet), then run `cmd /c "tools\pc-sender\send.bat" -DumpFrames 5 -Out <scratch>\f.txt "<that folder>\测试 图片(1).png" "<that folder>\b.jpg"`. Expected: summary lists both files, `f.txt` has 5 lines, `f.txt.bundle` exists. Also run with `x.webp` → `Skipped x.webp: unsupported format`.

- [ ] **Step 6: Commit** — `git commit -am "feat(sender): image preparation, file picker, send.bat"` (add new files).

---

### Task 6: Full-screen animation window

**Files:**
- Create: `tools/pc-sender/src/SenderForm.cs`; Modify: `DynamicQrSender.ps1` (show the form after the summary)
- Create: `tools/pc-sender/README.md` (usage: drag images onto `send.bat` or double-click; flags; keys)

**Interfaces:**
- Consumes: `FrameEncoder` (Task 4).
- Produces: `class SenderForm : Form { SenderForm(FrameEncoder enc, int fps, QRCodeGenerator.ECCLevel ecc, int fileCount, int bundleLen); }`, shown with `[System.Windows.Forms.Application]::Run($form)`.

Behaviour (spec §5.5): borderless, maximized on primary screen, white background, `DoubleBuffered = true`. Block IDs increase from 0 forever (`uint`, wrap is irrelevant). A `System.Windows.Forms.Timer` at `1000 / fps` ms advances to the next frame. QR from `QRCodeGenerator.CreateQrCode(text, ecc)` → `ModuleMatrix` (already includes the 4-module quiet zone); module pixel size = `floor((ClientHeight − 40) / matrixSize)`, drawn with `FillRectangle` per dark module, centred horizontally. Status strip (bottom 40 px, small grey text): `3 files · 412 KB · K=188 · block 1234 · 8 fps · 02:31 · +/- speed · Space pause · Esc quit`. Keys: `+`/`=`/numpad-add → fps+1, `-`/numpad-subtract → fps−1 (clamp 1–30, update timer interval), Space toggles pause, Esc closes.

- [ ] **Step 1: Implement.**
- [ ] **Step 2: Self-test still passes** — `... -SelfTest` → `SELFTEST PASS`.
- [ ] **Step 3: Manual check.** Double-click `send.bat`, pick two images. Expected: console summary, then a full-screen QR that visibly changes ~8×/s; `+` speeds up (status shows fps), Space freezes, Esc closes and the console exits. Scan one frame with any phone camera app: it decodes as text made of Base45 characters.
- [ ] **Step 4: Commit** — `git add -A && git commit -m "feat(sender): full-screen QR animation window"`

---

### Task 7: Cross-implementation vectors

**Files:**
- Create: `tools/pc-sender/make-vectors.ps1`, `entry/src/test/vectors/frames.txt`, `entry/src/test/vectors/bundle.bin`
- Test: `tools/protocol-tests/tests/vectors.test.ts`

**Interfaces:**
- Consumes: sender `-DumpFrames/-Out/-TransferId` (Task 4–5); `parseFrame`, `ReceiverSession`, `unpackBundle` (Tasks 2–3).

`make-vectors.ps1`: in a temp folder generate three small images with System.Drawing — `a.png` 300×200 gradient, `测试 图片(1).png` 240×240 with text, `c.jpg` 200×300 — run the sender with `-BlockSize 200 -TransferId 12345678 -DumpFrames <3·K> -Out entry/src/test/vectors/frames.txt` (compute K from a first dry run or dump 600 lines; K must be ≥ 20), then rename `frames.txt.bundle` → `bundle.bin`.

- [ ] **Step 1: Write failing test**
```ts
const lines = readFileSync(VEC + '/frames.txt', 'utf8').trim().split('\n');
const bundle = new Uint8Array(readFileSync(VEC + '/bundle.bin'));
// every line parses; transferId 0x12345678; blockSize 200; bundleCrc32 == crc32(bundle)
// session fed only lines with index ≥ K/2 (skip the first half of systematic blocks), every 3rd line dropped → COMPLETE
// files(): names exactly ['a.jpg', '测试 图片(1).jpg', 'c.jpg']; packBundle(files()) deep-equals bundle
```
- [ ] **Step 2: Run** `node tools/protocol-tests/run.mjs` → FAIL (vector files missing).
- [ ] **Step 3: Run** `powershell -NoProfile -ExecutionPolicy Bypass -File tools/pc-sender/make-vectors.ps1` → vector files written.
- [ ] **Step 4: Run tests** → all pass. A failure here means the C# and ArkTS PRNG/frame code disagree — fix the side that breaks its own pinned values, never the vector.
- [ ] **Step 5: Commit** — `git add -A && git commit -m "test: cross-implementation frame vectors"`

---

### Task 8: Phone scanning page with live progress

**Files:**
- Modify: `entry/src/main/ets/pages/Index.ets` (replace template), `entry/src/main/module.json5`, `entry/src/main/resources/base/element/string.json`

**Interfaces:**
- Consumes: `ReceiverSession`, `SessionState`, `SessionProgress` (Task 3).

Requirements:
- `module.json5`: `requestPermissions: [{ name: 'ohos.permission.CAMERA', reason: '$string:camera_reason', usedScene: { abilities: ['EntryAbility'], when: 'inuse' } }]`; `camera_reason` = "Scan the animated QR code shown on your PC".
- On `aboutToAppear`: request CAMERA via `abilityAccessCtrl.createAtManager().requestPermissionsFromUser`; on denial show "Camera permission is needed to receive images" with a retry button. Keep the screen on (`window.getLastWindow(ctx)` → `setWindowKeepScreenOn(true)`).
- Scanning: `customScan.init({ scanTypes: [scanCore.ScanType.QR_CODE], enableMultiMode: false, enableAlbum: false })`; `XComponent` of type `SURFACE` with 16:9 portrait aspect at full width; in `onLoad` get the surfaceId and call `customScan.start(viewControl, callback)` with the XComponent's size in px. In the callback: for each result call `session.onScan(result.originalValue)`, refresh `@State` progress, then `customScan.rescan()`. Errors from the callback are logged (`hilog`) and followed by `rescan()`. `onPageHide`/`aboutToDisappear` → `customScan.stop()` + `customScan.release()`; `onPageShow` re-inits if released.
- Progress panel (spec §5.6 sketch): `Receiving N files`-line shows `bundleLen` as KB once known; progress bar `resolved / k`; `mm:ss · X KB/s · Y fr/s` where KB/s = `bytes resolved (resolved·blockSize, capped at bundleLen) / elapsed`, fr/s = `scans` over the last 2 s (sliding window in the page); also `unique frames: n`. Before the first valid frame: "Point the camera at the QR animation on your PC". `[Reset]` calls `session.reset()`.
- When the session reaches `COMPLETE`: stop scanning and switch to the results view (Task 9 fills it; for now show `✓ N images · KB · s`). `FAILED`: show the error text in red; scanning continues (the session restarts itself).

- [ ] **Step 1: Implement.**
- [ ] **Step 2: Build** — `bash tools/build-hap.sh` → `BUILD SUCCESSFUL`. Protocol tests still pass.
- [ ] **Step 3: Device check (manual, user's phone via DevEco Run).** Start `send.bat` with 3 photos. Expected: camera preview, progress rises, counters update, completion line appears. Note the fr/s value — it is the key feasibility number.
- [ ] **Step 4: Commit** — `git add -A && git commit -m "feat(app): continuous scan page with live progress"`

---

### Task 9: Results view and save to gallery

**Files:**
- Modify: `entry/src/main/ets/pages/Index.ets`

**Interfaces:**
- Consumes: `ReceiverSession.files(): BundleFile[]`, `progress()`.

Requirements:
- On COMPLETE: decode each file with `image.createImageSource(data.buffer)` → `createPixelMap()`; show header `✓ N images · KB · s` and a 3-column grid of thumbnails with names. A file that fails to decode shows a grey tile "can't display" (it is still saved).
- Tap a thumbnail → full-screen overlay `Image(pixelMap).objectFit(ImageFit.Contain)`, tap to close.
- `SaveButton` (icon + text "Save all to gallery"): on `SaveButtonOnClickResult.SUCCESS`, for each file `photoAccessHelper.getPhotoAccessHelper(ctx).createAsset(photoAccessHelper.PhotoType.IMAGE, 'jpg')` → open the URI with `fileIo.openSync(uri, READ_WRITE | CREATE)` → write bytes → close; then a toast `Saved N images`. Any failure → toast with the error message, others continue.
- `[Scan again]`: release pixel maps, `session.reset()`, return to scanning (re-init `customScan`).

- [ ] **Step 1: Implement.**
- [ ] **Step 2: Build** — `bash tools/build-hap.sh` → `BUILD SUCCESSFUL`.
- [ ] **Step 3: Device check.** Transfer 3 photos; thumbnails match the PC originals; tap opens full view; "Save all" → the 3 images appear in the Gallery app; "Scan again" returns to the camera and a second transfer works.
- [ ] **Step 4: Commit** — `git commit -am "feat(app): results grid, full view, save to gallery"`

---

### Task 10: End-to-end feasibility run

**Files:**
- Create: `docs/results.md`

- [ ] **Step 1: Run the acceptance test with the user** (spec §8): 3 typical photos at default settings; then the same with `-Fps 12`, and with `-BlockSize 500` and `-BlockSize 1200`.
- [ ] **Step 2: Record** in `docs/results.md` a table per run: phone model, settings, bundle KB, K, total seconds, KB/s, scan fr/s, unique frames / K (overhead), verified yes/no, notes (moiré, focus).
- [ ] **Step 3: Write the verdict** in 3–5 lines: does it work, best settings, whether Scan Kit's rate makes the fallback scanning path (spec §4 option 2) worth building — that decision goes back to the user.
- [ ] **Step 4: Commit** — `git add docs/results.md && git commit -m "docs: feasibility results"`
