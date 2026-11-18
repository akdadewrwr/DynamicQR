import { test } from 'node:test';
import assert from 'node:assert/strict';
import { ltNeighbors, mix32, Mulberry32 } from '../.gen/protocol/Prng';

test('mix32 pinned values', () => {
  assert.equal(mix32(0, 0), 2287948138);
  assert.equal(mix32(0x12345678, 1000), 222234753);
});
test('mulberry32 pinned sequence', () => {
  const r = new Mulberry32(1);
  assert.deepEqual([r.next(), r.next(), r.next(), r.next(), r.next()],
    [2693262067, 11749833, 2265367787, 4213581821, 4159151403]);
});
test('ltNeighbors pinned LT selection', () => {
  assert.deepEqual(ltNeighbors(0x12345678, 1000, 5, 188), [19, 168, 24, 11, 20]);
});
test('ltNeighbors is systematic below K', () => {
  assert.deepEqual(ltNeighbors(0x12345678, 7, 3, 188), [7]);
});
test('ltNeighbors returns distinct indices in range', () => {
  for (let b = 200; b < 400; b++) {
    const n = ltNeighbors(99, b, 6, 10);
    assert.equal(new Set(n).size, 6);
    for (const i of n) assert.ok(i >= 0 && i < 10);
  }
});
