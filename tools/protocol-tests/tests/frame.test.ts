import { test } from 'node:test';
import assert from 'node:assert/strict';
import { encodeFrame, Frame, FRAME_HEADER_LEN, FRAME_OVERHEAD, parseFrame } from '../.gen/protocol/Frame';
import { base45Decode, base45Encode } from '../.gen/protocol/Base45';
import { randomBytes } from './helpers/random';

function makeFrame(p: { transferId: number; bundleLen: number; blockSize: number; bundleCrc32: number; blockId: number; degree: number; payload: Uint8Array }): Frame {
  const f = new Frame();
  f.version = 1; f.transferId = p.transferId; f.bundleLen = p.bundleLen; f.blockSize = p.blockSize;
  f.bundleCrc32 = p.bundleCrc32; f.blockId = p.blockId; f.degree = p.degree; f.payload = p.payload;
  return f;
}
const base = () => makeFrame({ transferId: 0xDEADBEEF, bundleLen: 5000, blockSize: 800, bundleCrc32: 0xCAFEBABE, blockId: 4000000000, degree: 3, payload: randomBytes(800) });
function mutateBytes(text: string, fn: (b: Uint8Array) => Uint8Array): string { return base45Encode(fn(base45Decode(text)!)); }

test('frame constants', () => { assert.equal(FRAME_HEADER_LEN, 21); assert.equal(FRAME_OVERHEAD, 23); });
test('frame round-trips', () => { const f = base(); assert.deepEqual(parseFrame(encodeFrame(f)), f); });
test('frame is little-endian with header layout from spec', () => {
  const b = base45Decode(encodeFrame(base()))!;
  assert.equal(b.length, 823);
  assert.equal(b[0], 1);
  assert.deepEqual(Array.from(b.slice(1, 5)), [0xEF, 0xBE, 0xAD, 0xDE]);
  assert.deepEqual(Array.from(b.slice(9, 11)), [0x20, 0x03]);
});
test('rejects foreign QR text', () => {
  assert.equal(parseFrame('HTTPS://EXAMPLE.COM'), null);
  assert.equal(parseFrame('WIFI:S:x;;'), null);
  assert.equal(parseFrame(''), null);
});
test('rejects a corrupted byte (CRC16)', () => {
  assert.equal(parseFrame(mutateBytes(encodeFrame(base()), (b) => { b[100] ^= 1; return b; })), null);
});
test('rejects unknown version', () => { const f = base(); f.version = 2; assert.equal(parseFrame(encodeFrame(f)), null); });
test('rejects truncated payload', () => {
  assert.equal(parseFrame(mutateBytes(encodeFrame(base()), (b) => b.slice(0, 500))), null);
});
test('rejects blockSize 0', () => { const f = base(); f.blockSize = 0; f.payload = new Uint8Array(0); assert.equal(parseFrame(encodeFrame(f)), null); });
test('rejects degree 0 and degree > K', () => {
  const f = base(); f.degree = 0; assert.equal(parseFrame(encodeFrame(f)), null);
  const g = base(); g.degree = 8; assert.equal(parseFrame(encodeFrame(g)), null); // K = 7
});
test('rejects degree != 1 on a systematic block', () => { const f = base(); f.blockId = 3; assert.equal(parseFrame(encodeFrame(f)), null); });
test('rejects bundleLen 0', () => { const f = base(); f.bundleLen = 0; assert.equal(parseFrame(encodeFrame(f)), null); });
