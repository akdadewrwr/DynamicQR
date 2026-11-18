import { test } from 'node:test';
import assert from 'node:assert/strict';
import { LtDecoder } from '../.gen/protocol/LtDecoder';
import { parseFrame } from '../.gen/protocol/Frame';
import { ltNeighbors } from '../.gen/protocol/Prng';
import { TestEncoder } from './helpers/TestEncoder';
import { randomBytes, TestRng } from './helpers/random';

function feed(d: LtDecoder, enc: TestEncoder, text: string): void {
  const f = parseFrame(text)!;
  d.addBlock(ltNeighbors(f.transferId, f.blockId, f.degree, enc.k), f.payload);
}

test('decodes from a random start with 50% loss and shuffling', () => {
  for (const [len, bs] of [[1, 800], [800, 800], [801, 800], [50000, 800], [150000, 800]]) {
    const bundle = randomBytes(len);
    const enc = new TestEncoder(bundle, bs, 42);
    const d = new LtDecoder(enc.k, bs);
    const rng = new TestRng(7);
    let id = 500, used = 0;
    while (!d.isComplete()) {
      const window: number[] = [];
      for (let i = 0; i < 20; i++, id++) if (rng.float() >= 0.5) window.push(id);
      for (let i = window.length - 1; i > 0; i--) { const j = rng.next() % (i + 1); [window[i], window[j]] = [window[j], window[i]]; }
      for (const b of window) { feed(d, enc, enc.frame(b)); used++; }
      assert.ok(id < 500 + 40 * enc.k + 400, `no completion for len=${len}`);
    }
    assert.deepEqual(d.assemble(len), bundle);
    assert.equal(d.resolvedCount(), enc.k);
  }
});

test('systematic blocks in order complete exactly at K', () => {
  const bundle = randomBytes(8000);
  const enc = new TestEncoder(bundle, 800, 5);
  const d = new LtDecoder(enc.k, 800);
  for (let i = 0; i < enc.k; i++) {
    assert.equal(d.isComplete(), false);
    feed(d, enc, enc.frame(i));
    assert.equal(d.resolvedCount(), i + 1);
  }
  assert.ok(d.isComplete());
  assert.deepEqual(d.assemble(8000), bundle);
});

test('duplicates and redundant blocks are harmless', () => {
  const bundle = randomBytes(4000);
  const enc = new TestEncoder(bundle, 400, 9);
  const d = new LtDecoder(enc.k, 400);
  for (let i = 0; i < enc.k; i++) { feed(d, enc, enc.frame(i)); feed(d, enc, enc.frame(i)); }
  for (let i = enc.k; i < enc.k + 30; i++) feed(d, enc, enc.frame(i));
  assert.deepEqual(d.assemble(4000), bundle);
});
