import { test } from 'node:test';
import assert from 'node:assert/strict';
import { BundleFile, packBundle, unpackBundle } from '../.gen/protocol/Bundle';
import { utf8Encode } from '../.gen/protocol/Utf8';
import { randomBytes } from './helpers/random';

export function bf(name: string, data: Uint8Array): BundleFile { const f = new BundleFile(); f.name = name; f.data = data; return f; }

test('bundle round-trips names (incl. non-ASCII) and data', () => {
  const files = [bf('a.jpg', randomBytes(10)), bf('测试 图片(1).png', randomBytes(0)), bf('😀.jpg', randomBytes(3000))];
  assert.deepEqual(unpackBundle(packBundle(files)), files);
});
test('bundle layout starts with DQB1 and LE count', () => {
  const b = packBundle([bf('x', new Uint8Array([7]))]);
  assert.deepEqual(Array.from(b), [0x44, 0x51, 0x42, 0x31, 1, 0, 1, 0, 0x78, 1, 0, 0, 0, 7]);
});
test('bundle rejects bad magic, truncation and trailing bytes', () => {
  const good = packBundle([bf('a.jpg', randomBytes(100))]);
  assert.throws(() => unpackBundle(utf8Encode('XXXX')));
  assert.throws(() => unpackBundle(good.slice(0, 20)));
  const extra = new Uint8Array(good.length + 1); extra.set(good);
  assert.throws(() => unpackBundle(extra));
});
