// Cross-implementation check: frames produced by the C# sender (tools/pc-sender/make-vectors.ps1)
// must decode with the ArkTS protocol code into the exact bundle the sender wrote.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseFrame } from '../.gen/protocol/Frame';
import { crc32 } from '../.gen/protocol/Crc';
import { packBundle } from '../.gen/protocol/Bundle';
import { ReceiverSession, SessionState } from '../.gen/protocol/ReceiverSession';

const VEC = join(dirname(fileURLToPath(import.meta.url)), '..', '..', '..', 'entry', 'src', 'test', 'vectors');
const lines = readFileSync(join(VEC, 'frames.txt'), 'utf8').split(/\r?\n/).filter((l) => l.length > 0);
const bundle = new Uint8Array(readFileSync(join(VEC, 'bundle.bin')));
const K = Math.ceil(bundle.length / 200);

test('every sender frame parses with the expected header', () => {
  assert.ok(K >= 20, `K=${K}`);
  assert.ok(lines.length >= 2 * K, `${lines.length} lines for K=${K}`);
  lines.forEach((line, i) => {
    const f = parseFrame(line);
    assert.ok(f !== null, `line ${i} does not parse`);
    assert.equal(f.transferId, 0x12345678);
    assert.equal(f.blockSize, 200);
    assert.equal(f.blockId, i);
    assert.equal(f.bundleLen, bundle.length);
    assert.equal(f.bundleCrc32, crc32(bundle, 0, bundle.length));
  });
});

test('sender frames decode from the middle with losses into the same bundle', () => {
  const s = new ReceiverSession(() => 0);
  for (let i = Math.floor(K / 2); i < lines.length && s.state() !== SessionState.COMPLETE; i++) {
    if (i % 3 === 2) continue;
    s.onScan(lines[i]);
  }
  assert.equal(s.state(), SessionState.COMPLETE, s.error());
  const names = s.files().map((f) => f.name);
  assert.deepEqual(names, ['a.jpg', '测试 图片(1).jpg', 'c.jpg']);
  assert.deepEqual(packBundle(s.files()), bundle);
});
